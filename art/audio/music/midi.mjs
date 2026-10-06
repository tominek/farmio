// Minimal Standard MIDI File reading and writing for the music scripts.
// read(path) -> { format, division, tracks: [[{ t, bytes, ch?, note?, on? }]] } with absolute ticks;
// `bytes` holds the whole event with its status byte. write(path, song) writes it back.
import { readFileSync, writeFileSync } from "node:fs";

export function read(path) {
	const buf = readFileSync(path);
	let pos = 0;
	const u32 = () => { const v = buf.readUInt32BE(pos); pos += 4; return v; };
	const u16 = () => { const v = buf.readUInt16BE(pos); pos += 2; return v; };
	const vlq = () => { let v = 0, b; do { b = buf[pos++]; v = (v << 7) | (b & 0x7f); } while (b & 0x80); return v; };

	if (buf.toString("ascii", 0, 4) !== "MThd") throw new Error(`${path}: not a MIDI file`);
	pos = 4;
	const headLen = u32();
	const format = u16(), ntrks = u16(), division = u16();
	pos = 8 + headLen;

	const tracks = [];
	for (let i = 0; i < ntrks; i++) {
		if (buf.toString("ascii", pos, pos + 4) !== "MTrk") throw new Error(`${path}: bad track`);
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
			if (status < 0xf0) ev.ch = status & 0x0f;
			const kind = status & 0xf0;
			if (kind === 0x90 || kind === 0x80) {
				ev.note = bytes[1];
				ev.on = kind === 0x90 && bytes[2] > 0;
			}
			events.push(ev);
		}
		tracks.push(events);
	}
	return { format, division, tracks };
}

export function write(path, { format, division, tracks }) {
	const out = [];
	const head = Buffer.alloc(14);
	head.write("MThd", 0, "ascii");
	head.writeUInt32BE(6, 4);
	head.writeUInt16BE(format, 8);
	head.writeUInt16BE(tracks.length, 10);
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
	writeFileSync(path, Buffer.concat(out));
}

// Sorts by time (stable) and keeps the end-of-track meta last.
export function finish(events) {
	events.forEach((ev, i) => (ev.i = i));
	events.sort((a, b) => a.t - b.t || a.i - b.i);
	const eot = events.findIndex((ev) => ev.bytes[0] === 0xff && ev.bytes[1] === 0x2f);
	if (eot >= 0) {
		const [ev] = events.splice(eot, 1);
		ev.t = Math.max(ev.t, events.length ? events[events.length - 1].t : 0);
		events.push(ev);
	}
	return events;
}
