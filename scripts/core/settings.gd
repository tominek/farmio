extends Node
## Player settings (autoload "Settings"): kept in user://settings.cfg and applied on start and on
## Apply in the Settings panel. Other code reads the values here, e.g. `Settings.warning_lines`, and
## can listen to `changed`.

signal changed

const PATH := "user://settings.cfg"
const WINDOW_MODES := ["fullscreen", "borderless", "windowed"]
const RESOLUTIONS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900),
	Vector2i(1920, 1080), Vector2i(2560, 1080), Vector2i(2560, 1440), Vector2i(3440, 1440), Vector2i(3840, 2160)]
const FRAME_LIMITS := [30, 60, 120, 144, 0]          # 0 = unlimited
const QUALITIES := ["low", "medium", "high"]
const AUTOSAVE_MINUTES := [0, 5, 10, 15, 30]       # game minutes, 0 = off

## Defaults of every setting (key -> value). Window mode and resolution are only applied once the
## player has chosen them (until then the window starts as the project sets it up).
const DEFAULTS := {
	"window_mode": "windowed",
	"resolution": Vector2i(1600, 900),
	"frame_limit": 60,
	"vsync": true,
	"quality": "high",
	"ui_scale": 1.0,
	"warning_lines": true,
	"tooltip_delay": 0.5,
	"number_style": "space",         # "space": 1 500, "comma": 1,500
	"autosave_minutes": 5,
	"autosave_count": 5,            # autosave slots kept (SaveGame.rotate_autosaves), 1..10
	"volume_master": 1.0,          # linear 0..1 per audio bus (default_bus_layout.tres)
	"volume_music": 0.7,
	"volume_effects": 0.8,
	"volume_ambience": 0.7,
	"worker_names": "",              # one per line: new workers take these names first (WorkerNames.custom)
}
const BUSES := {"Master": "volume_master", "Music": "volume_music", "Effects": "volume_effects", "Ambience": "volume_ambience"}

var values := DEFAULTS.duplicate()
var _window_chosen := false

## Shown under the HUD: warning lines (no shortage of seeds, full barn, …).
var warning_lines: bool:
	get:
		return values["warning_lines"]


func _ready() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		for key: String in DEFAULTS:
			if cf.has_section_key("settings", key):
				var v: Variant = cf.get_value("settings", key)
				if typeof(v) == typeof(DEFAULTS[key]) or (DEFAULTS[key] is float and v is int):
					values[key] = v
		_window_chosen = cf.get_value("meta", "window_chosen", false)
	apply()


## Game seconds between autosaves, 0 = off.
func autosave_interval() -> float:
	return float(values["autosave_minutes"]) * 60.0


func set_values(new_values: Dictionary) -> void:
	if new_values.get("window_mode") != values["window_mode"] or new_values.get("resolution") != values["resolution"]:
		_window_chosen = true
	values.merge(new_values, true)
	apply()
	save()


func save() -> void:
	var cf := ConfigFile.new()
	for key: String in values:
		cf.set_value("settings", key, values[key])
	cf.set_value("meta", "window_chosen", _window_chosen)
	cf.save(PATH)


func apply() -> void:
	Defs.thousands_sep = "," if values["number_style"] == "comma" else " "
	ProjectSettings.set_setting("gui/timers/tooltip_delay_sec", values["tooltip_delay"])
	Engine.max_fps = values["frame_limit"]
	var root := get_tree().root
	root.content_scale_factor = values["ui_scale"]
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if values["vsync"] else DisplayServer.VSYNC_DISABLED)
		if _window_chosen:
			_apply_window()
	_apply_quality()
	_apply_audio()
	_apply_worker_names()
	changed.emit()


func _apply_window() -> void:
	match values["window_mode"]:
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		"borderless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var res: Vector2i = values["resolution"]
			var screen := DisplayServer.screen_get_usable_rect()
			res = res.min(screen.size)
			DisplayServer.window_set_size(res)
			DisplayServer.window_set_position(screen.position + (screen.size - res) / 2)


## High: the look the game is tuned for (MSAA 2x, soft 4k sun shadows). Medium drops MSAA, Low
## also halves the shadow map and makes the shadow edges hard.
func _apply_quality() -> void:
	var q: String = values["quality"]
	var root := get_tree().root
	root.msaa_3d = Viewport.MSAA_2X if q == "high" else Viewport.MSAA_DISABLED
	RenderingServer.directional_shadow_atlas_set_size(2048 if q == "low" else 4096, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		RenderingServer.SHADOW_QUALITY_HARD if q == "low" else RenderingServer.SHADOW_QUALITY_SOFT_LOW)


func _apply_audio() -> void:
	for bus: String in BUSES:
		var i := AudioServer.get_bus_index(bus)
		if i < 0:
			continue
		var v: float = values[BUSES[bus]]
		AudioServer.set_bus_mute(i, v <= 0.001)
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.001)))


## Names typed in Settings → Game, one per line, for new workers (WorkerNames.custom).
func worker_names() -> PackedStringArray:
	var out := PackedStringArray()
	for line in String(values["worker_names"]).split("\n", false):
		if line.strip_edges() != "":
			out.append(line.strip_edges())
	return out


func _apply_worker_names() -> void:
	const PATH_NAMES := "res://scripts/core/worker_names.gd"
	if ResourceLoader.exists(PATH_NAMES):
		var script: Script = load(PATH_NAMES)
		script.set("custom", worker_names())
