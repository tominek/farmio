#!/bin/bash
# Turns a source sound into the OGG the game loads: assets/audio/<kind>/<name>.ogg
#
#   art/audio/process.sh <kind> <source file> <name>
#   art/audio/process.sh --batch art/audio/batch.txt     # every line: <kind> <name> <source>
#
# kind:
#   sfx       positional effects: mono, -18 LUFS, silence trimmed, 5 ms fade in, 30 ms fade out
#   ui        interface sounds:   mono, -20 LUFS, trimmed, short fades
#   ambience  loops:              stereo, -26 LUFS, trimmed, the last LOOP_XFADE seconds are
#             crossfaded into the start so the file loops without a seam
#   music     tracks:             stereo, -16 LUFS, trimmed, 1 s fade out
#
# Batch sources are relative to $AUDIO_SRC (default ~/Audio), e.g. "kenney/rpg/Audio/chop.ogg";
# '#' starts a comment. Source originals stay outside the repo; record every output in
# art/audio/sources.md.
#
# Loudness is measured with ffmpeg's EBU R128 scanner (short clips padded with silence, which the
# gate ignores) and set with a plain gain, capped so the peak stays under -1 dBFS; a gain keeps an
# ambience loop seamless where loudnorm's dynamic mode would not. ffmpeg writes WAV, oggenc
# (Homebrew vorbis-tools) encodes it: Homebrew's ffmpeg has no libvorbis.
#
# Needs: ffmpeg, ffprobe, oggenc (brew install ffmpeg vorbis-tools).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
AUDIO_SRC="${AUDIO_SRC:-$HOME/Audio}"
LOOP_XFADE=2.0       # seconds of an ambience loop's end crossfaded into its start
OGG_QUALITY=5
PEAK_MAX=-1.0        # dBFS
SILENCE=-50dB        # quieter than this at the start and end is cut

target_lufs() {
	case "$1" in
		sfx) echo -18 ;;
		ui) echo -20 ;;
		ambience) echo -26 ;;
		music) echo -16 ;;
		*) echo "unknown kind: $1 (sfx, ui, ambience, music)" >&2; exit 1 ;;
	esac
}

duration() {
	ffprobe -v error -show_entries format=duration -of csv=p=0 "$1"
}

## Prints "<integrated LUFS> <peak dBFS>" of a WAV.
measure() {
	ffmpeg -hide_banner -nostats -i "$1" -af "apad=pad_dur=3,ebur128=peak=sample:framelog=quiet" -f null - 2>&1 \
		| awk '/Integrated loudness:/ {s=1} s && /I:/ {i=$2} /Sample peak:/ {p=1} p && /Peak:/ {pk=$2} END {print i, pk}'
}

process() {
	local kind="$1" src="$2" name="$3"
	local target out tmp channels
	target=$(target_lufs "$kind")
	[ -f "$src" ] || { echo "missing source: $src" >&2; return 1; }
	out="$ROOT/assets/audio/$kind/$name.ogg"
	mkdir -p "$(dirname "$out")"
	tmp=$(mktemp -d)
	channels=1
	[ "$kind" = ambience ] || [ "$kind" = music ] && channels=2

	# 1. trim silence at both ends, set channels and rate
	local trim="silenceremove=start_periods=1:start_threshold=$SILENCE,areverse,silenceremove=start_periods=1:start_threshold=$SILENCE,areverse"
	ffmpeg -hide_banner -loglevel error -y -i "$src" -af "$trim" -ac "$channels" -ar 44100 "$tmp/trim.wav"
	local d
	d=$(duration "$tmp/trim.wav")

	# 2. fades, or the loop seam for ambience
	case "$kind" in
		ambience)
			local x="$LOOP_XFADE"
			if awk -v d="$d" -v x="$x" 'BEGIN {exit !(d < 3 * x)}'; then
				x=$(awk -v d="$d" 'BEGIN {printf "%.3f", d / 4}')
			fi
			local e
			e=$(awk -v d="$d" -v x="$x" 'BEGIN {printf "%.3f", d - x}')
			ffmpeg -hide_banner -loglevel error -y -i "$tmp/trim.wav" -filter_complex \
				"[0]asplit=3[a][b][c];\
				[a]atrim=0:$x,asetpts=N/SR/TB,afade=t=in:d=$x:curve=qsin[head];\
				[b]atrim=$e:$d,asetpts=N/SR/TB,afade=t=out:d=$x:curve=qsin[tail];\
				[head][tail]amix=inputs=2:normalize=0[seam];\
				[c]atrim=$x:$e,asetpts=N/SR/TB[mid];\
				[mid][seam]concat=n=2:v=0:a=1[out]" -map "[out]" "$tmp/shaped.wav"
			;;
		music)
			local st
			st=$(awk -v d="$d" 'BEGIN {printf "%.3f", (d > 2 ? d - 1 : d / 2)}')
			ffmpeg -hide_banner -loglevel error -y -i "$tmp/trim.wav" -af "afade=t=out:st=$st:d=1" "$tmp/shaped.wav"
			;;
		*)
			local fo st
			fo=$(awk -v d="$d" 'BEGIN {printf "%.3f", (d < 0.12 ? d / 4 : 0.03)}')
			st=$(awk -v d="$d" -v f="$fo" 'BEGIN {printf "%.3f", d - f}')
			ffmpeg -hide_banner -loglevel error -y -i "$tmp/trim.wav" -af "afade=t=in:d=0.005,afade=t=out:st=$st:d=$fo" "$tmp/shaped.wav"
			;;
	esac

	# 3. loudness: one gain to the target, the peak kept under PEAK_MAX
	local m lufs peak gain
	m=$(measure "$tmp/shaped.wav")
	lufs=${m% *}
	peak=${m#* }
	gain=$(awk -v t="$target" -v i="$lufs" -v p="$peak" -v pm="$PEAK_MAX" \
		'BEGIN {g = t - i; if (p + g > pm) g = pm - p; printf "%.2f", g}')
	ffmpeg -hide_banner -loglevel error -y -i "$tmp/shaped.wav" -af "volume=${gain}dB" -c:a pcm_s16le -map_metadata -1 -bitexact "$tmp/final.wav"

	# 4. OGG Vorbis
	oggenc -Q -q "$OGG_QUALITY" -o "$out" "$tmp/final.wav"
	local after
	after=$(measure "$tmp/final.wav")
	printf "%-9s %-22s %6.2fs  %s LUFS -> %s LUFS (gain %s dB, peak %s dBFS)\n" \
		"$kind" "$name" "$(duration "$out")" "$lufs" "${after% *}" "$gain" "${after#* }"
	rm -rf "$tmp"
}

if [ "${1:-}" = "--batch" ]; then
	[ -f "${2:-}" ] || { echo "usage: $0 --batch <list>" >&2; exit 1; }
	while read -r kind name src _; do
		[ -z "${kind:-}" ] && continue
		case "$kind" in \#*) continue ;; esac
		process "$kind" "$AUDIO_SRC/$src" "$name"
	done < "$2"
elif [ $# -eq 3 ]; then
	process "$1" "$2" "$3"
else
	sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
	exit 1
fi
