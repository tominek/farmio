// Humanizes a MIDI file from abc2midi: small timing and velocity jitter, strummed chords.
// Usage: node humanize.mjs in.mid out.mid
// Deterministic (seeded by the file name), so a re-render of unchanged notes sounds the same.
import { readFileSync, writeFileSync } from "node:fs";
import { basename } from "node:path";

const [, , inPath, outPath] = process.argv;
const TIMING = 0.018;   // max jitter of a note start, in quarter notes
const VELOCITY = 0.12;  // max relative velocity jitter
const STRUM = 0.035;    // delay between strummed chord notes, in quarter notes

let seed = [...basename(inPath)].reduce((h, c) => (h * 31 + c.charCodeAt(0)) >>> 0, 7);
const rand = () => {
	seed = (seed * 1664525 + 1013904223) >>> 0;
	return seed / 4294967296;
};

const buf = readFileSync(inPath);
let pos = 0;
const u32 = () => { const v = buf.readUInt32BE(pos); pos += 4; return v; };
const u16 = () => { const v = buf.readUInt16BE(pos); pos += 2; return v; };
const vlq = () => { let v = 0, b; do { b = buf[pos++]; v = (v << 7) | (b & 0x7f); } while (b & 0x80); return v; };

if (buf.toString("ascii", 0, 4) !== "MThd") throw new Error("not a MIDI file");
pos = 4;
const headLen = u32();
const format = u16(), ntrks = u16(), division = u16();
pos = 8 + headLen;

// Each event: { t: absolute ticks, bytes: Buffer (status included), note?, ch?, on? }
const tracks = [];
for (let i = 0; i < ntrks; i++) {
	if (buf.toString("ascii", pos, pos + 4) !== "MTrk") throw new Error("bad track");
	pos += 4;
	const end = u32() + pos;
	const events = [];
	let t = 0, running = 0;
	while (pos < end) {
		t += vlq();
		let status = buf[pos];
		if (status < 0x80) status = running; else pos++;
		const start = pos;
		if (status === 0xff) {
			pos++;
			const len = vlq();
			pos += len;
		} else if (status === 0xf0 || status === 0xf7) {
			const len = vlq();
			pos += len;
		} else {
			running = status;
			const kind = status & 0xf0;
			pos += (kind === 0xc0 || kind === 0xd0) ? 1 : 2;
		}
		const bytes = Buffer.concat([Buffer.from([status]), buf.subarray(start, pos)]);
		const ev = { t, bytes };
		const kind = status & 0xf0;
		if (kind === 0x90 || kind === 0x80) {
			ev.ch = status & 0x0f;
			ev.note = bytes[1];
			ev.on = kind === 0x90 && bytes[2] > 0;
		}
		events.push(ev);
	}
	tracks.push(events);
}

for (const events of tracks) {
	// Strum: three or more notes starting together on one channel (not drums) go low to high.
	const groups = new Map();
	for (const ev of events) {
		if (!ev.on || ev.ch === 9) continue;
		const key = ev.t * 16 + ev.ch;
		if (!groups.has(key)) groups.set(key, []);
		groups.get(key).push(ev);
	}
	const shift = new Map(); // note-on event -> tick offset
	for (const group of groups.values()) {
		const base = Math.round((rand() * 2 - 1) * TIMING * division);
		group.sort((a, b) => a.note - b.note);
		group.forEach((ev, i) => {
			const strum = group.length >= 3 ? Math.round(i * STRUM * division) : 0;
			shift.set(ev, Math.max(base + strum, -ev.t));
		});
	}
	// Note-offs move with their note-on, so lengths stay.
	const open = new Map();
	for (const ev of events) {
		if (ev.note === undefined) continue;
		const key = ev.ch * 128 + ev.note;
		if (ev.on) {
			const v = Math.round(ev.bytes[2] * (1 + (rand() * 2 - 1) * VELOCITY));
			ev.bytes[2] = Math.min(127, Math.max(1, v));
			if (!open.has(key)) open.set(key, []);
			open.get(key).push(shift.get(ev) ?? 0);
			ev.t += shift.get(ev) ?? 0;
		} else {
			const queue = open.get(key);
			if (queue && queue.length) ev.t += queue.shift();
		}
	}
	events.forEach((ev, i) => (ev.i = i));
	events.sort((a, b) => a.t - b.t || a.i - b.i);
	// The end-of-track meta must stay last.
	const eot = events.findIndex((ev) => ev.bytes[0] === 0xff && ev.bytes[1] === 0x2f);
	if (eot >= 0) {
		const [ev] = events.splice(eot, 1);
		ev.t = Math.max(ev.t, events.length ? events[events.length - 1].t : 0);
		events.push(ev);
	}
}

const out = [];
const head = Buffer.alloc(14);
head.write("MThd", 0, "ascii");
head.writeUInt32BE(6, 4);
head.writeUInt16BE(format, 8);
head.writeUInt16BE(ntrks, 10);
head.writeUInt16BE(division, 12);
out.push(head);
const vlqBytes = (v) => {
	const bytes = [v & 0x7f];
	while ((v >>= 7) > 0) bytes.unshift((v & 0x7f) | 0x80);
	return Buffer.from(bytes);
};
for (const events of tracks) {
	const parts = [];
	let t = 0;
	for (const ev of events) {
		parts.push(vlqBytes(ev.t - t), ev.bytes);
		t = ev.t;
	}
	const body = Buffer.concat(parts);
	const th = Buffer.alloc(8);
	th.write("MTrk", 0, "ascii");
	th.writeUInt32BE(body.length, 4);
	out.push(th, body);
}
writeFileSync(outPath, Buffer.concat(out));
