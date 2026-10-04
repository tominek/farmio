class_name LoadingScreen
extends Control
## Loading screen between the menus and the game. The world is generated (new game) or read from
## a save on a thread while this screen shows; then the game scene starts with it.
##
## World generation reports no progress of its own, so the bar follows the time the last run took
## (it never runs ahead of the real work: it waits at the last step until the world is ready).

const SCENE := "res://scenes/loading.tscn"
const GAME_SCENE := "res://scenes/game.tscn"
const GameScript := preload("res://scripts/game.gd")

const NEW_STEPS := ["Shaping the land", "Letting the river find its way", "Planting trees",
	"Building your first barn", "Waking up the workers"]
const LOAD_STEPS := ["Reading the save", "Placing buildings and workers", "Waking up the workers"]
const MIN_SHOW_MS := 1500.0           # the screen stays at least this long, so a fast load doesn't just flash
const TIPS := [
	"Fields need seeds. Order them at the Dealer; the pickup brings them to the barn on its next trip.",
	"The Priorities panel (P) sets which kind of work your workers pick first.",
	"Research (T) unlocks new buildings, upgrades and tools like the wheelbarrow.",
	"Space pauses the game; 1, 2 and 3 set the speed.",
	"Q and E turn the camera, W A S D move it, the wheel zooms.",
	"F5 quicksaves at any time; F9 loads the newest save.",
	"Pick a field's next crop in its info panel: it is sown once the current crop is gone.",
	"With wheelbarrows in the barn, workers carry big harvests in fewer trips.",
	"Demolishing something you built gives back the quacks it cost.",
]

static var _mode := "new"            # "new" or "load"
static var _slot := ""
static var _farm := ""
static var _seed := -1
static var _size := 256
static var _expected_ms := {"new": 1200.0, "load": 700.0}

var _thread: Thread
var _result: World
var _extra := {}
var _t0 := 0
var _done := false
var _bar: ProgressBar
var _step_label: Label
var _pct: Label
var _steps: VBoxContainer
var _meta := {}


## Starts a new game: generates a world (random seed unless given) named `farm_name`.
static func start_new(tree: SceneTree, farm_name: String, seed_value := -1, size := 256) -> void:
	_mode = "new"
	_farm = farm_name
	_seed = seed_value
	_size = size
	tree.paused = false
	tree.change_scene_to_file.call_deferred(SCENE)


static func start_load(tree: SceneTree, slot: String) -> void:
	_mode = "load"
	_slot = slot
	tree.paused = false
	tree.change_scene_to_file.call_deferred(SCENE)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _mode == "load":
		_meta = SaveGame.meta(_slot)
		_build_load()
	else:
		_build_new()
	_set_progress(0.0)
	_t0 = Time.get_ticks_msec()
	_thread = Thread.new()
	_thread.start(_work)


func _work() -> void:
	if " --loading-snap=" in " " + " ".join(OS.get_cmdline_user_args()):
		OS.delay_msec(400)            # screenshots of the screen itself: keep it up a moment
	if _mode == "load":
		var extra := {}
		var w := SaveGame.load_world(_slot, extra)
		_extra = extra
		_extra["meta"] = _meta
		_result = w
	else:
		var s := _seed if _seed >= 0 else randi()
		var w := WorldGen.generate(_size, s)
		if "farm_name" in w:
			w.set("farm_name", _farm)
		_extra = {"name": _farm}
		_result = w


func _process(_delta: float) -> void:
	if _done:
		return
	var t := float(Time.get_ticks_msec() - _t0)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--loading-snap=") and t > 1000.0:
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--loading-snap="))
			get_tree().quit()
			return
	var steps := NEW_STEPS if _mode == "new" else LOAD_STEPS
	var last := float(steps.size() - 1) / steps.size()   # the last step starts when the world is ready
	if _thread.is_alive() or t < MIN_SHOW_MS:
		_set_progress(minf(last - 0.02, last * (1.0 - exp(-2.2 * t / _expected_ms[_mode]))))
		return
	_thread.wait_to_finish()
	_done = true
	_expected_ms[_mode] = lerpf(_expected_ms[_mode], t, 0.7)
	if _result == null:
		_fail()
		return
	_set_progress(last + 0.5 / steps.size())
	# draw "Waking up the workers" once, then build the game scene (that frame stays on screen)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	GameScript.pending_world = _result
	GameScript.pending_extra = _extra
	get_tree().change_scene_to_file(GAME_SCENE)


func _fail() -> void:
	_step_label.text = "This save could not be read (it may be from an older version)."
	_step_label.add_theme_color_override("font_color", UiStyle.SHORT)
	var back := Button.new()
	back.text = "Back to the main menu"
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	_step_label.get_parent().add_child(back)


func _set_progress(p: float) -> void:
	_bar.value = p
	_pct.text = "%d %%" % roundi(p * 100.0)
	var steps := NEW_STEPS if _mode == "new" else LOAD_STEPS
	var current := mini(int(p * steps.size()), steps.size() - 1)
	_step_label.text = steps[current]
	if _steps == null:
		return
	for i in _steps.get_child_count():
		var row := _steps.get_child(i) as HBoxContainer
		var dot := row.get_child(0) as Control
		var l := row.get_child(1) as Label
		dot.set_meta("state", 2 if i < current else (1 if i == current else 0))
		dot.queue_redraw()
		l.add_theme_color_override("font_color", UiStyle.INK if i <= current else UiStyle.INK_SOFT)
		l.add_theme_font_override("font", UiStyle.body_font(i == current))


# --- layout ------------------------------------------------------------------------------------

func _build_new() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#F3E9D6")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# the top part: a tractor on its way out to the fields
	var scene := LoadingTractor.new()
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene.anchor_bottom = 0.55
	add_child(scene)
	var logo := MenuKit.logo("board", 100)
	logo.position = Vector2(100, 70)
	add_child(logo)
	var line := ColorRect.new()
	line.color = UiStyle.WOOD
	line.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	line.anchor_top = 0.55
	line.anchor_bottom = 0.55
	line.offset_bottom = 2
	add_child(line)
	var bottom := MarginContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bottom.anchor_top = 0.55
	bottom.add_theme_constant_override("margin_left", 100)
	bottom.add_theme_constant_override("margin_right", 100)
	bottom.add_theme_constant_override("margin_top", 50)
	bottom.add_theme_constant_override("margin_bottom", 40)
	add_child(bottom)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 100)
	bottom.add_child(cols)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 640
	left.add_theme_constant_override("separation", 12)
	cols.add_child(left)
	left.add_child(MenuKit.head("Preparing %s…" % (_farm if _farm != "" else "a new farm"), 30, 700))
	_add_bar(left)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(sp)
	left.add_child(_tip_card())
	_steps = VBoxContainer.new()
	_steps.add_theme_constant_override("separation", 8)
	cols.add_child(_steps)
	for s: String in NEW_STEPS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var dot := Control.new()
		dot.custom_minimum_size = Vector2(20, 20)
		dot.draw.connect(_draw_dot.bind(dot))
		row.add_child(dot)
		row.add_child(MenuKit.label(s, "", 15, UiStyle.INK_SOFT))
		_steps.add_child(row)


func _build_load() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#F3E9D6")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# the same tractor on its way, above the card
	var scene := LoadingTractor.new()
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene.anchor_bottom = 0.7
	add_child(scene)
	var line := ColorRect.new()
	line.color = UiStyle.WOOD
	line.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	line.anchor_top = 0.7
	line.anchor_bottom = 0.7
	line.offset_bottom = 2
	add_child(line)
	var logo := MenuKit.logo("board", 100)
	logo.position = Vector2(100, 70)
	add_child(logo)
	var card := PanelContainer.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	card.offset_left = 100
	card.offset_right = -100
	card.offset_bottom = -50
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(card)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 24)
	card.add_child(m)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 60)
	m.add_child(cols)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 640
	left.add_theme_constant_override("separation", 10)
	cols.add_child(left)
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 14)
	left.add_child(title)
	title.add_child(MenuKit.head("Loading " + _meta.get("name", _slot), 30, 700))
	var sub := []
	if int(_meta.get("day", 0)) > 0:
		sub.append("Day %d" % int(_meta["day"]))
	sub.append("saved " + MenuKit.when(int(_meta.get("saved", 0))).replace("Today", "today").replace("Yesterday", "yesterday"))
	var sl := MenuKit.label(" · ".join(sub), "", 15, UiStyle.INK_SOFT)
	sl.size_flags_vertical = Control.SIZE_SHRINK_END
	title.add_child(sl)
	_add_bar(left)
	var tip := _tip_card()
	tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cols.add_child(tip)


func _add_bar(parent: Container) -> void:
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.max_value = 1.0
	_bar.step = 0.0
	_bar.custom_minimum_size.y = 20
	var bg := UiStyle.box(UiStyle.PAPER, UiStyle.WOOD, 10, 2)
	bg.set_content_margin_all(0)
	_bar.add_theme_stylebox_override("background", bg)
	var fill := UiStyle.box(UiStyle.GO, Color.TRANSPARENT, 8)
	fill.set_content_margin_all(0)
	_bar.add_theme_stylebox_override("fill", fill)
	parent.add_child(_bar)
	var h := HBoxContainer.new()
	parent.add_child(h)
	_step_label = MenuKit.label("", "", 14, UiStyle.INK_SOFT)
	_step_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(_step_label)
	_pct = MenuKit.label("", "NumberLabel")
	_pct.add_theme_font_size_override("font_size", 14)
	h.add_child(_pct)


func _tip_card() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UiStyle.box(Color("#FFFDF7"), Color("#D9B98A"), 10, 2)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	p.add_theme_stylebox_override("panel", sb)
	var t := RichTextLabel.new()
	t.bbcode_enabled = true
	t.fit_content = true
	t.scroll_active = false
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = 560
	t.add_theme_font_override("normal_font", UiStyle.body_font())
	t.add_theme_font_override("bold_font", UiStyle.body_font(true))
	t.add_theme_font_size_override("normal_font_size", 15)
	t.add_theme_font_size_override("bold_font_size", 15)
	t.add_theme_color_override("default_color", UiStyle.INK)
	t.text = "💡 [b]Tip:[/b] " + TIPS[randi() % TIPS.size()]
	p.add_child(t)
	return p


func _draw_dot(dot: Control) -> void:
	var state: int = dot.get_meta("state", 0)
	var c := dot.size * 0.5
	if state == 0:
		dot.draw_arc(c, 8.5, 0, TAU, 32, Color("#BDB5A6"), 1.5, true)
	else:
		dot.draw_circle(c, 9.5, UiStyle.GO)
		if state == 2:
			dot.draw_polyline(PackedVector2Array([c + Vector2(-4.5, 0), c + Vector2(-1.2, 3.5), c + Vector2(4.5, -3.5)]), UiStyle.PAPER, 2.2, true)
		else:
			dot.draw_circle(c, 3.5, UiStyle.PAPER)


func _exit_tree() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
