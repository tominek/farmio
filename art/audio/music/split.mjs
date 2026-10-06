// Splits a (humanized) MIDI file into one track per instrument, for a DAW such as Reason, which
// ignores program changes: a melody voice that goes fiddle -> flute becomes a Fiddle and a Flute track.
// Track 1 holds tempo, metre and key; every instrument track is named and starts with its program.
// Usage: node split.mjs in.mid out.mid
import { read, write, finish } from "./midi.mjs";

const [, , inPath, outPath] = process.argv;
const NAMES = {
	21: "Accordion", 22: "Harmonica", 24: "Nylon Guitar", 25: "Steel Guitar", 32: "Upright Bass",
	40: "Fiddle", 48: "Strings", 73: "Flute", 78: "Whistle",
};
const CONDUCTOR = new Set([0x51, 0x58, 0x59]); // tempo, time signature, key signature

const song = read(inPath);
const all = song.tracks.flat();
all.forEach((ev, i) => (ev.i = i));
all.sort((a, b) => a.t - b.t || a.i - b.i);

const conductor = [];
const parts = new Map(); // "ch:program" or "drums" -> { name, program, events }
const program = new Map(); // channel -> current program
const first = new Map(); // channel -> its first program (for notes humanized ahead of it)
for (const ev of all) if ((ev.bytes[0] & 0xf0) === 0xc0 && !first.has(ev.ch)) first.set(ev.ch, ev.bytes[1]);
const playing = new Map(); // "ch:note" -> [part keys of sounding notes]
const partOf = (ch) => {
	if (ch === 9) return "drums";
	const p = program.get(ch) ?? first.get(ch) ?? 0;
	const key = `${ch}:${p}`;
	if (!parts.has(key)) parts.set(key, { name: NAMES[p] ?? `Program ${p}`, program: p, events: [] });
	return key;
};

for (const ev of all) {
	const status = ev.bytes[0];
	if (status === 0xff) {
		if (CONDUCTOR.has(ev.bytes[1])) conductor.push(ev);
		continue;
	}
	if (ev.ch === undefined) continue;
	const kind = status & 0xf0;
	if (kind === 0xc0) {
		program.set(ev.ch, ev.bytes[1]);
		continue;
	}
	if (ev.note !== undefined) {
		const sounding = `${ev.ch}:${ev.note}`;
		let key;
		if (ev.on) {
			key = partOf(ev.ch);
			if (!playing.has(sounding)) playing.set(sounding, []);
			playing.get(sounding).push(key);
		} else {
			key = playing.get(sounding)?.shift() ?? partOf(ev.ch);
		}
		if (key === "drums" && !parts.has("drums")) parts.set("drums", { name: "Percussion", program: -1, events: [] });
		parts.get(key).events.push(ev);
		continue;
	}
	// Controllers and the like: to the part that plays on this channel now.
	const key = partOf(ev.ch);
	if (key === "drums" && !parts.has("drums")) parts.set("drums", { name: "Percussion", program: -1, events: [] });
	parts.get(key).events.push(ev);
}

const meta = (t, type, data) => ({ t, bytes: Buffer.concat([Buffer.from([0xff, type, data.length]), data]) });
const eot = (t) => ({ t, bytes: Buffer.from([0xff, 0x2f, 0x00]) });
const last = all.length ? all[all.length - 1].t : 0;
const tracks = [finish([meta(0, 0x03, Buffer.from("Tempo")), ...conductor, eot(last)])];

// Each instrument gets its own channel (drums stay on 10), so the file also plays right as it is.
let next = 0;
const sorted = [...parts.values()].filter((p) => p.events.some((ev) => ev.on));
const seen = new Map();
for (const part of sorted) {
	const n = (seen.get(part.name) ?? 0) + 1;
	seen.set(part.name, n);
	if (n > 1) part.name += ` ${n}`;
}
for (const part of sorted) {
	let ch = 9;
	if (part.program >= 0) {
		if (next === 9) next++;
		ch = next++ % 16;
	}
	const events = part.events.map((ev) => {
		const bytes = Buffer.from(ev.bytes);
		bytes[0] = (bytes[0] & 0xf0) | ch;
		return { t: ev.t, bytes };
	});
	const head = [meta(0, 0x03, Buffer.from(part.name))];
	if (part.program >= 0) head.push({ t: 0, bytes: Buffer.from([0xc0 | ch, part.program]) });
	tracks.push(finish([...head, ...events, eot(last)]));
}

write(outPath, { format: 1, division: song.division, tracks });
console.log(`${outPath}: ${sorted.map((p) => p.name).join(", ")}`);
