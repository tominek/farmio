// Humanizes a MIDI file from abc2midi: small timing and velocity jitter, strummed chords.
// Usage: node humanize.mjs in.mid out.mid
// Deterministic (seeded by the file name), so a re-render of unchanged notes sounds the same.
import { basename } from "node:path";
import { read, write, finish } from "./midi.mjs";

const [, , inPath, outPath] = process.argv;
const TIMING = 0.018;   // max jitter of a note start, in quarter notes
const VELOCITY = 0.12;  // max relative velocity jitter
const STRUM = 0.035;    // delay between strummed chord notes, in quarter notes

let seed = [...basename(inPath)].reduce((h, c) => (h * 31 + c.charCodeAt(0)) >>> 0, 7);
const rand = () => {
	seed = (seed * 1664525 + 1013904223) >>> 0;
	return seed / 4294967296;
};

const song = read(inPath);
const division = song.division;

for (const events of song.tracks) {
	// Strum: three or more notes starting together on one channel (not drums) go low to high.
	const groups = new Map();
	for (const ev of events) {
		if (!ev.on || ev.ch === 9) continue;
		const key = ev.t * 16 + ev.ch;
		if (!groups.has(key)) groups.set(key, []);
		groups.get(key).push(ev);
	}
	// No note may move before its channel's first program change (abc2midi sets it at tick 1).
	const ready = new Map();
	for (const ev of events) if ((ev.bytes[0] & 0xf0) === 0xc0 && !ready.has(ev.ch)) ready.set(ev.ch, ev.t);
	const shift = new Map(); // note-on event -> tick offset
	for (const group of groups.values()) {
		const base = Math.round((rand() * 2 - 1) * TIMING * division);
		group.sort((a, b) => a.note - b.note);
		group.forEach((ev, i) => {
			const strum = group.length >= 3 ? Math.round(i * STRUM * division) : 0;
			shift.set(ev, Math.max(base + strum, (ready.get(ev.ch) ?? 0) - ev.t));
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
	finish(events);
}

write(outPath, song);
