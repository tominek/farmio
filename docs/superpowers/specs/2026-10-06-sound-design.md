# Sound: folk music as code, farm sounds from free libraries

Status: approved in conversation (2026-10-06), not implemented.

## Why

The game is silent. The bustle of workers and vehicles is the payoff of a running farm (vision:
visible workforce), and it should be heard as well as seen: an axe close up, the hum of a busy farm
from afar. Calm background music carries the "peaceful and satisfying" pillar. Today the audio buses
(Music, Effects, Ambience in `default_bus_layout.tres`) and the volume settings exist, nothing plays.

## Decisions (from the brainstorm)

- Music is written as code by Claude: notes in text, rendered offline to OGG. No DAW, no AI music.
- Style: acoustic folk (guitar, fiddle, accordion, flute or whistle, upright bass, light percussion).
- Sound effects come only from free libraries: Sonniss GDC Game Audio Bundle, Kenney (CC0),
  Freesound (CC0, or CC-BY credited in the credits). Nothing NC, nothing BBC Sound Effects, no
  generated sounds.
- In the game a central sound director plays the nearest activity sounds over ambience layers
  (option B); no audio player per worker or vehicle.
- Claude can't listen: Tomas picks the sounds and judges the music; Claude measures, processes and
  wires them in.

## 1. In the game: the sound director

`SoundDirector`, one node in the game scene (`scripts/view/sound_director.gd`).

**Activity sounds.** Four times a second it goes through workers and vehicles (about 60, so the
cost scales with agents, not with the map). For those near the camera that are working it keeps a
repeating sound by the kind of work:

| Source | Sound |
|---|---|
| Worker, `CHOP` | axe strokes |
| Worker, `BUILD` | hammer, saw |
| Worker, `FIELD` | hoe / sowing / harvest by the row step |
| Worker, `PROCESS` | mill |
| Vehicle | engine: driving, idle, loading |

Each stroke varies a little in pitch and volume and agents are not in sync. Sounds play from a pool
of 16–24 positional players (`AudioStreamPlayer3D`, bus Effects); when more want to play, the ones
nearest the camera win.

**One-shot events** hang on existing `World` signals: a tree falls (`tree_changed`), a building is
finished (`building_added`), goods are put down or loaded (`pile_changed`, `stock_changed`). They use
the same pool.

**Ambience.** 4–5 loops always running, only their volume changes (bus Ambience): nature (wind,
birds), forest, water, work bustle, engines. Twice a second the volumes are recomputed from what is
on screen: terrain from a fixed grid of about 16×16 sample points over the camera view, activity
from the counts of working agents and moving vehicles in view. Volumes glide, never jump.

**Zoom and game speed.** Close up the activity sounds lead; zoomed out they fade and the ambience
("farm hum") stays. At 3× the activity strokes are thinned so they don't rattle; at 50× only
ambience plays. Paused: muffled ambience only.

**UI sounds** (click, building placed, toast, Dealer buy and sell) go through `UiStyle` helpers on
bus Effects.

**Cost.** Activity: O(agents) 4× a second. Ambience: a fixed number of samples 2× a second. At most
24 voices. No per-frame work over the map. Within the performance gate.

## 2. Making the sound effects

**Sources.** The Sonniss bundle is downloaded once by Tomas to a folder outside the repo
(e.g. `~/Audio/sonniss/`); its files are well named, Claude finds candidates by name. Kenney packs
are downloaded directly. Freesound needs an API key, or Tomas sends links.

**In the repo.**
- `assets/audio/sfx/`, `assets/audio/ambience/`, `assets/audio/music/`: final `.ogg` files the game
  loads. Source originals are not committed.
- `art/audio/sources.md`: one row per file (file, origin, author, licence, URL). Nothing enters the
  game without a row. CC-BY rows are shown in the main menu credits next to "Tominek".
- `art/audio/process.sh` (ffmpeg): trim, short fades, loudness to a target per kind (effects,
  ambience, music), mono for positional effects, stereo for ambience and music, seamless loop seams
  for ambience, OGG Vorbis.

**Choosing.** Claude can measure loudness, length and spectrum but not taste:
- a listening page in `tmp/` (2–3 candidates per sound, play buttons); Tomas picks, Claude wires in;
- a sound board in the dev menu: every sound and ambience layer with volume sliders, to balance the
  mix in the game.

**First set** (about 30–40 sounds): axe, tree fall, hammer, saw, hoe, sowing, harvest, mill, pickup
engine (drive, idle, loading), goods put down and loaded, ducks and animals, UI, 5 ambience loops.
New buildings bring their sounds with them.

## 3. Music as code

**Notes in ABC notation** (`art/audio/music/<name>.abc`): the text format used for folk tunes;
headers for tempo, key and instruments, several voices (melody, counter-melody, bass) and
accompaniment from chord symbols with a rhythm pattern.

**Pipeline** (one command, `art/audio/music/render.sh`):
1. `abc2midi` (Homebrew `abcmidi`) turns ABC into MIDI.
2. A small Node script humanizes the MIDI: slight timing and velocity jitter, strummed chords.
3. `fluidsynth` plays the MIDI with a soundfont and reverb into WAV.
4. ffmpeg sets the loudness and writes OGG to `assets/audio/music/`.

Tools to install with Homebrew: `abcmidi`, `fluid-synth`, `ffmpeg`. Python is blocked, hence Node.

**Soundfont:** candidates GeneralUser GS and FluidR3 (MIT); the licence is checked before use and
recorded in `art/audio/sources.md`. If an instrument sounds too synthetic, the notes stay and are
re-rendered with a better soundfont later.

**Identity:** a short "duck" motif that returns in every track and in the menu theme.

**First version:**
- menu theme (loops);
- 4–5 game tracks of 2–3 minutes, shuffled without repeats, 1–3 minutes of silence between them;
- crossfade from menu to game; all on bus Music (`scripts/core/music.gd` autoload, survives the scene
  change).

**Order:** the menu theme first; Tomas listens, soundfont and humanizing are tuned on it, only then
the other tracks.

## Steps

Each step leaves a playable game.

1. **Music:** render pipeline, menu theme, music player with the playlist (after the menu theme is
   approved, the game tracks one by one).
2. **Sound director and ambience:** director, voice pool, ambience layers, dev sound board,
   processing script and `sources.md`; first ambience loops and activity sounds.
3. **Full first set:** remaining activity and event sounds, UI sounds, credits for CC-BY.

Steps 1 and 2 are independent and can run in parallel.

## Later (in `docs/design/09-future-ideas.md`)

- Music by season; adaptive music that adds instruments as the farm grows.
- Sounds for seasons and weather (rain, winter wind).
