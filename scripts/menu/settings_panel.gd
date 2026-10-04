class_name SettingsPanel
extends Control
## Settings (from the main menu and the game menu): tabs on the left, rows on the right. Changes are
## kept as a draft until Apply; Cancel / ✕ drop them. Values live in the Settings autoload.

signal closed

const TABS := ["Game", "Display", "Audio", "Controls", "Accessibility"]
const KEYS := [
	["Esc", "Close the open panel, then the game menu"],
	["Space", "Pause / resume"],
	["1  2  3", "Game speed 1x, 2x, 3x"],
	["W A S D", "Move the camera"],
	["Q  E", "Rotate the camera (or middle mouse drag)"],
	["Wheel", "Zoom (trackpad: two-finger scroll, pinch)"],
	["Left click", "Select a worker, building, field or road"],
	["Right click", "Clear the selection"],
	["Delete", "Demolish the selected thing (click twice)"],
	["T", "Research"],
	["P", "Priorities"],
	["F5", "Quicksave"],
	["F9", "Load the newest save"],
	["F12", "Developer menu"],
]

var _draft := {}
var _tab := 1
var _tab_buttons: Array[Button] = []
var _content: VBoxContainer
var _changes: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_to_group("debug_show")
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var p := UiStyle.make_panel("Settings")
	var root: PanelContainer = p["root"]
	root.custom_minimum_size = Vector2(956, 720)
	center.add_child(root)
	(p["close"] as Button).pressed.connect(_cancel)
	# the body gets two columns: the tab rail and the page
	var body: VBoxContainer = p["body"]
	var margin := body.get_parent() as MarginContainer
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 0)
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 0)
	body.add_child(cols)
	var rail := PanelContainer.new()
	var rail_sb := UiStyle.box(Color("#F3E8D6"), Color.TRANSPARENT, 0)
	rail_sb.corner_radius_bottom_left = UiStyle.PANEL_RADIUS
	rail_sb.content_margin_left = 14
	rail_sb.content_margin_right = 0
	rail_sb.content_margin_top = 18
	rail.add_theme_stylebox_override("panel", rail_sb)
	rail.custom_minimum_size.x = 208
	cols.add_child(rail)
	var tabs := VBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	rail.add_child(tabs)
	var group := ButtonGroup.new()
	var on := UiStyle.box(UiStyle.PAPER, UiStyle.WOOD, 8, 2)
	on.border_width_right = 0
	on.corner_radius_top_right = 0
	on.corner_radius_bottom_right = 0
	var off := UiStyle.box(Color.TRANSPARENT, Color.TRANSPARENT, 8, 2)
	var off_h := UiStyle.box(Color(1, 1, 1, 0.4), Color.TRANSPARENT, 8, 2)
	for i in TABS.size():
		var b := Button.new()
		b.text = TABS[i]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 46
		b.add_theme_font_size_override("font_size", 17)
		b.add_theme_stylebox_override("normal", off)
		b.add_theme_stylebox_override("hover", off_h)
		b.add_theme_stylebox_override("pressed", on)
		b.add_theme_stylebox_override("hover_pressed", on)
		b.add_theme_color_override("font_color", UiStyle.INK_SOFT)
		b.pressed.connect(func() -> void: _show_tab(i))
		tabs.add_child(b)
		_tab_buttons.append(b)
	var edge := ColorRect.new()
	edge.color = UiStyle.WOOD
	edge.custom_minimum_size.x = 2
	cols.add_child(edge)
	var page := MarginContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		page.add_theme_constant_override("margin_" + side, 28)
	page.add_theme_constant_override("margin_top", 18)
	page.add_theme_constant_override("margin_bottom", 16)
	cols.add_child(page)
	var page_col := VBoxContainer.new()
	page.add_child(page_col)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page_col.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 0)
	scroll.add_child(_content)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	page_col.add_child(foot)
	var reset := Button.new()
	reset.text = "Reset to defaults"
	reset.theme_type_variation = "GhostButton"
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(_reset)
	foot.add_child(reset)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(sp)
	_changes = MenuKit.label("", "", 15, UiStyle.SHORT)
	_changes.add_theme_font_override("font", UiStyle.head_font(600))
	foot.add_child(_changes)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.custom_minimum_size = Vector2(88, 44)
	cancel.pressed.connect(_cancel)
	foot.add_child(cancel)
	var apply := Button.new()
	apply.text = "Apply"
	apply.theme_type_variation = "PrimaryButton"
	apply.focus_mode = Control.FOCUS_NONE
	apply.custom_minimum_size = Vector2(82, 44)
	apply.pressed.connect(_apply)
	foot.add_child(apply)
	hide()


func open(tab := 1) -> void:
	_draft = Settings.values.duplicate()
	show()
	_show_tab(tab)


func _show_tab(i: int) -> void:
	_tab = i
	_tab_buttons[i].set_pressed_no_signal(true)
	for j in _tab_buttons.size():
		_tab_buttons[j].add_theme_color_override("font_color", UiStyle.INK if j == i else UiStyle.INK_SOFT)
	for c in _content.get_children():
		c.queue_free()
	match TABS[i]:
		"Game":
			_game_tab()
		"Display":
			_display_tab()
		"Audio":
			_audio_tab()
		"Controls":
			_controls_tab()
		"Accessibility":
			_note("UI scale, tooltip delay and the number style are under Display. More options (colour-blind crop colours, larger text) are not in the game yet.")
	_update_changes()


func _game_tab() -> void:
	_content.add_child(MenuKit.section("Saving"))
	var opts := []
	for m: int in Settings.AUTOSAVE_MINUTES:
		opts.append("Off" if m == 0 else "%d min" % m)
	_content.add_child(MenuKit.setting_row("Autosave", "Every N minutes of game time (fast forward makes it come sooner)",
		_dropdown(opts, Settings.AUTOSAVE_MINUTES.find(_draft["autosave_minutes"]), func(i: int) -> void: _put("autosave_minutes", Settings.AUTOSAVE_MINUTES[i]))))
	var gap := Control.new()
	gap.custom_minimum_size.y = 14
	_content.add_child(gap)
	_content.add_child(MenuKit.section("Workers"))
	var names := TextEdit.new()
	names.text = _draft["worker_names"]
	names.placeholder_text = "One name per line"
	names.custom_minimum_size = Vector2(300, 180)
	names.add_theme_stylebox_override("normal", get_theme_stylebox("normal", "LineEdit"))
	names.add_theme_stylebox_override("focus", get_theme_stylebox("focus", "LineEdit"))
	names.add_theme_color_override("font_color", UiStyle.INK)
	names.add_theme_color_override("background_color", UiStyle.PAPER)
	names.text_changed.connect(func() -> void: _put("worker_names", names.text))
	var row := MenuKit.setting_row("Worker names", "New workers take these names first; leave empty for the built-in names", names)
	(row.get_child(0) as HBoxContainer).custom_minimum_size.y = 200
	_content.add_child(row)


func _display_tab() -> void:
	_content.add_child(MenuKit.section("Screen"))
	_content.add_child(MenuKit.setting_row("Window mode", "",
		MenuKit.segmented(["Fullscreen", "Borderless", "Windowed"], Settings.WINDOW_MODES.find(_draft["window_mode"]),
			func(i: int) -> void: _put("window_mode", Settings.WINDOW_MODES[i]))))
	var res_names := []
	for r: Vector2i in Settings.RESOLUTIONS:
		res_names.append("%d × %d" % [r.x, r.y])
	_content.add_child(MenuKit.setting_row("Resolution", "Window size in Windowed mode · wide 2560 × 1080 and 3440 × 1440 supported",
		_dropdown(res_names, Settings.RESOLUTIONS.find(_draft["resolution"]), func(i: int) -> void: _put("resolution", Settings.RESOLUTIONS[i]))))
	var fps := []
	for f: int in Settings.FRAME_LIMITS:
		fps.append("Unlimited" if f == 0 else "%d fps" % f)
	_content.add_child(MenuKit.setting_row("Frame limit", "",
		_dropdown(fps, Settings.FRAME_LIMITS.find(_draft["frame_limit"]), func(i: int) -> void: _put("frame_limit", Settings.FRAME_LIMITS[i]))))
	_content.add_child(MenuKit.setting_row("VSync", "", MenuKit.switch(_draft["vsync"], func(v: bool) -> void: _put("vsync", v))))
	_content.add_child(MenuKit.setting_row("Quality", "Anti-aliasing and sun shadows",
		MenuKit.segmented(["Low", "Medium", "High"], Settings.QUALITIES.find(_draft["quality"]),
			func(i: int) -> void: _put("quality", Settings.QUALITIES[i]))))
	var gap := Control.new()
	gap.custom_minimum_size.y = 14
	_content.add_child(gap)
	_content.add_child(MenuKit.section("Interface"))
	_content.add_child(MenuKit.setting_row("UI scale", "Panels, text and icons together",
		_slider_with_value(0.8, 1.5, 0.05, _draft["ui_scale"], "%d %%", 100.0, "ui_scale")))
	_content.add_child(MenuKit.setting_row("Warning lines under the HUD", "",
		MenuKit.switch(_draft["warning_lines"], func(v: bool) -> void: _put("warning_lines", v))))
	_content.add_child(MenuKit.setting_row("Tooltip delay", "",
		_slider_with_value(0.0, 1.5, 0.1, _draft["tooltip_delay"], "%.1f s", 1.0, "tooltip_delay")))
	_content.add_child(MenuKit.setting_row("Number style", "",
		MenuKit.segmented(["1 500", "1,500"], 1 if _draft["number_style"] == "comma" else 0,
			func(i: int) -> void: _put("number_style", "comma" if i == 1 else "space"))))


func _audio_tab() -> void:
	_content.add_child(MenuKit.section("Volume"))
	for bus: String in Settings.BUSES:
		var key: String = Settings.BUSES[bus]
		_content.add_child(MenuKit.setting_row(bus, "",
			_slider_with_value(0.0, 1.0, 0.05, _draft[key], "%d %%", 100.0, key)))
	var gap := Control.new()
	gap.custom_minimum_size.y = 14
	_content.add_child(gap)
	_note("No sounds in the game yet.")


func _controls_tab() -> void:
	_content.add_child(MenuKit.section("Keyboard and mouse"))
	for k: Array in KEYS:
		var cap := UiStyle.key_cap(k[0])
		cap.add_theme_font_size_override("font_size", 14)
		var row := MenuKit.setting_row(k[1], "", cap)
		row.get_child(0).custom_minimum_size.y = 40
		_content.add_child(row)


func _note(text: String) -> void:
	var l := MenuKit.label(text, "SoftLabel")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 600
	_content.add_child(l)


func _dropdown(options: Array, selected: int, changed: Callable) -> OptionButton:
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	o.custom_minimum_size = Vector2(240, 40)
	o.add_theme_font_override("font", UiStyle.body_font(true))
	for t: String in options:
		o.add_item(t)
	o.select(maxi(0, selected))
	o.item_selected.connect(changed)
	return o


func _slider_with_value(lo: float, hi: float, step: float, value: float, fmt: String, mul: float, key: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var v := MenuKit.label(fmt % (value * mul), "NumberLabel")
	v.custom_minimum_size.x = 56
	var s := MenuKit.slider(lo, hi, step, value, func(x: float) -> void:
		v.text = fmt % (x * mul)
		_put(key, x))
	h.add_child(s)
	h.add_child(v)
	return h


func _put(key: String, value: Variant) -> void:
	_draft[key] = value
	_update_changes()


func _count_changes() -> int:
	var n := 0
	for k: String in _draft:
		if not is_same_value(_draft[k], Settings.values[k]):
			n += 1
	return n


static func is_same_value(a: Variant, b: Variant) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		return absf(float(a) - float(b)) < 0.0001
	return a == b


func _update_changes() -> void:
	var n := _count_changes()
	_changes.text = "" if n == 0 else ("1 unsaved change" if n == 1 else "%d unsaved changes" % n)


func _apply() -> void:
	Settings.set_values(_draft)
	_draft = Settings.values.duplicate()
	_update_changes()


func _cancel() -> void:
	hide()
	closed.emit()


func _reset() -> void:
	_draft = Settings.DEFAULTS.duplicate()
	_show_tab(_tab)


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_cancel()


## --show=settings opens the Display tab with two changes, like the design.
func debug_show(what: String, _game: Node) -> void:
	if what == "settings":
		open(1)
		_draft["ui_scale"] = 1.1
		_draft["tooltip_delay"] = 0.3
		_show_tab(1)
