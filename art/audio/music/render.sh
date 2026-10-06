#!/bin/sh
# Renders the music: ABC notes -> MIDI (abc2midi) -> humanized MIDI (humanize.mjs) -> WAV
# (fluidsynth + soundfont, reverb) -> OGG with set loudness in assets/audio/music/.
# Usage (from the repo root): sh art/audio/music/render.sh [art/audio/music/<name>.abc ...]
# Needs Homebrew abcmidi, fluid-synth, ffmpeg and vorbis-tools, Node, and the GeneralUser GS soundfont
# (https://www.schristiancollins.com) at $SOUNDFONT (default ~/Audio/soundfonts/GeneralUser-GS.sf2).
# Intermediate files go to tmp/music/ (tmp/music/<name>.mid is the humanized MIDI, e.g. for Reason).
# A mix made elsewhere wins over fluidsynth: put it at $MIXES/<name>.wav (default ~/Audio/music-mixes/).
set -e
here=$(dirname "$0")
sf=${SOUNDFONT:-$HOME/Audio/soundfonts/GeneralUser-GS.sf2}
mixes=${MIXES:-$HOME/Audio/music-mixes}
work=tmp/music
out=assets/audio/music
mkdir -p "$work" "$out"
[ $# -gt 0 ] || set -- "$here"/*.abc
for abc in "$@"; do
	name=$(basename "$abc" .abc)
	abc2midi "$abc" -o "$work/$name.raw.mid" -quiet -silent
	node "$here/humanize.mjs" "$work/$name.raw.mid" "$work/$name.mid"
	if [ -f "$mixes/$name.wav" ]; then
		cp "$mixes/$name.wav" "$work/$name.wav"
	else
		fluidsynth -ni -q -g 0.5 -r 44100 -R 1 -C 0 \
			-o synth.reverb.room-size=0.55 -o synth.reverb.damp=0.4 -o synth.reverb.level=0.45 \
			-F "$work/$name.wav" "$sf" "$work/$name.mid"
	fi
	ffmpeg -y -loglevel error -i "$work/$name.wav" -af loudnorm=I=-18:TP=-1.5:LRA=11 \
		-ar 44100 "$work/$name.norm.wav"
	oggenc -Q -q 5 -o "$out/$name.ogg" "$work/$name.norm.wav"
	echo "$out/$name.ogg"
done
