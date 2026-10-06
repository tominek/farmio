class_name SoundBank
## Every sound the game plays, by name: its files (variants picked at random), base pitch and
## volume. Files that are not there yet are skipped, so a name without any file stays silent.
## The files are made by art/audio/process.sh and listed in art/audio/sources.md.

const SFX := "res://assets/audio/sfx/%s.ogg"
const UI := "res://assets/audio/ui/%s.ogg"
const AMBIENCE := "res://assets/audio/ambience/%s.ogg"

## name -> {"files": [paths], "pitch": base pitch scale, "db": volume offset}
const SOUNDS := {
	# work strokes (SoundDirector, positional)
	&"axe": {"files": ["axe_1", "axe_2", "axe_3", "axe_4"]},
	&"hammer": {"files": ["hammer_1", "hammer_2", "hammer_3", "hammer_4"], "db": -3.0},
	&"saw": {"files": ["saw_1", "saw_2"], "pitch": 0.8, "db": -4.0},
	&"hoe": {"files": ["hoe_1", "hoe_2", "hoe_3"]},
	&"sow": {"files": ["sow_1", "sow_2"]},
	&"harvest": {"files": ["harvest_1", "harvest_2"]},
	&"mill": {"files": ["mill_1"]},
	# vehicles: loops held while the vehicle is heard
	&"engine_drive": {"files": ["engine_drive"], "loop": true},
	&"engine_idle": {"files": ["engine_idle"], "loop": true},
	&"engine_load": {"files": ["engine_load"], "loop": true},
	# events (positional)
	&"tree_fall": {"files": ["tree_fall_1", "tree_fall_2"], "pitch": 0.7},
	&"goods_down": {"files": ["goods_down_1", "goods_down_2", "goods_down_3", "goods_down_4"], "db": -4.0},
	&"goods_up": {"files": ["goods_up_1", "goods_up_2"], "db": -4.0},
	&"build_done": {"files": ["build_done"], "db": -4.0},
	# interface (UiStyle.sound)
	&"click": {"files": ["click"], "ui": true, "db": -6.0},
	&"placed": {"files": ["placed"], "ui": true},
	&"toast": {"files": ["toast"], "ui": true, "db": -10.0},
	&"toast_ok": {"files": ["toast_ok"], "ui": true, "db": -9.0},
	&"toast_fail": {"files": ["toast_fail"], "ui": true, "db": -6.0},
	&"buy": {"files": ["buy"], "ui": true},
	&"sell": {"files": ["sell"], "ui": true},
}

## Credits screen (main menu): [what, who, licence]. Every CC-BY row of art/audio/sources.md must be
## here; CC0 libraries are thanked too.
const CREDITS: Array = [
	["Sound effects", "Kenney (kenney.nl)", "CC0"],
]

## Ambience layers (SoundDirector): looped, always running, only their volume changes.
const LAYERS: Array[StringName] = [&"nature", &"forest", &"water", &"bustle", &"engines"]

static var _streams := {}      # name -> Array[AudioStream] (empty: no file yet)


## The variants of a sound that have a file (loaded once).
static func streams(name: StringName) -> Array:
	if not _streams.has(name):
		var list: Array = []
		var def: Dictionary = SOUNDS.get(name, {})
		var pattern: String = UI if def.get("ui", false) else SFX
		for f: String in def.get("files", []):
			var s := _load(pattern % f, def.get("loop", false))
			if s:
				list.append(s)
		_streams[name] = list
	return _streams[name]


## A random variant, or null when the sound has no file yet.
static func pick(name: StringName) -> AudioStream:
	var list := streams(name)
	return list[randi() % list.size()] if not list.is_empty() else null


static func pitch(name: StringName) -> float:
	return SOUNDS.get(name, {}).get("pitch", 1.0)


static func db(name: StringName) -> float:
	return SOUNDS.get(name, {}).get("db", 0.0)


static func has(name: StringName) -> bool:
	return not streams(name).is_empty()


## The loop of an ambience layer, or null when there is no file yet.
static func layer(name: StringName) -> AudioStream:
	var key := StringName("layer:" + name)
	if not _streams.has(key):
		var s := _load(AMBIENCE % name, true)
		_streams[key] = [s] if s else []
	return _streams[key][0] if not _streams[key].is_empty() else null


static func _load(path: String, loop: bool) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var s := load(path) as AudioStream
	if loop and s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	return s
