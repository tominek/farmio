class_name SettingsPanel
extends Control
## Settings (from the main menu and the game menu): tabs on the left, rows on the right. Changes are
## kept as a draft until Apply; Cancel / ✕ drop them. Values live in the Settings autoload.

signal closed

const TABS := ["Game", "Display", "Audio", "Controls", "Accessibility"]
## Keys shown in Controls (read-only), in two columns: the left column first, then the right one.
const KEYS := [
	["B", "Build list"], ["C", "Cut trees"], ["R", "Rotate (while placing)"], ["T", "Research"],
	["Space", "Pause"], ["F5", "Quicksave"], ["Esc", "Menu · cancel"], ["W A S D", "Move the camera"],
	["M", "Move a building"], ["X", "Demolish"], ["Tab", "Crop while drawing a field"], ["P", "Priorities"],
	["1 2 3", "Game speed"], ["F9", "Load the newest save"], ["Del", "Demolish the selection"], ["Q E", "Turn the camera"],
]
const MOUSE := "Mouse: left click selects / places · right click cancels · wheel zooms · middle drag turns the camera"
const RING := Color("#CFE0F0")           # focus ring around a text field

var _draft := {}
var _tab := 1
var _tab_buttons: Array[Button] = []
var _scroll: ScrollContainer
var _content: VBoxContainer
var _changes: Label
var _apply_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_to_group("debug_show")
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var p := UiStyle.make_panel("Settings")
	var root: PanelContainer = p["root"]
	root.custom_minimum_size = Vector2(960, 860)
	center.add_child(root)
	MenuKit.header_size(p, 58, 24)
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
	var rail_sb := UiStyle.box(UiStyle.PAPER_DEEP, UiStyle.WOOD, 0, 0)
	rail_sb.border_width_right = 2
	rail_sb.corner_radius_bottom_left = UiStyle.PANEL_RADIUS - 2
	rail_sb.content_margin_left = 14
	rail_sb.content_margin_right = 0
	rail_sb.content_margin_top = 16
	rail_sb.content_margin_bottom = 16
	rail.add_theme_stylebox_override("panel", rail_sb)
	rail.custom_minimum_size.x = 210
	cols.add_child(rail)
	var tabs := VBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	rail.add_child(tabs)
	var group := ButtonGroup.new()
	# the open tab is paper and runs over the rail's edge into the page
	var on := UiStyle.box(UiStyle.PAPER, UiStyle.WOOD, 10, 2)
	on.border_width_right = 0
	on.corner_radius_top_right = 0
	on.corner_radius_bottom_right = 0
	on.expand_margin_right = 2
	var off := UiStyle.box(Color.TRANSPARENT, Color.TRANSPARENT, 10, 2)
	var off_h := UiStyle.box(Color(1, 1, 1, 0.4), Color.TRANSPARENT, 10, 2)
	for sb: StyleBoxFlat in [on, off, off_h]:
		sb.content_margin_left = 14
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
		b.add_theme_color_override("font_hover_color", UiStyle.INK)
		b.add_theme_color_override("font_pressed_color", UiStyle.INK)
		b.add_theme_color_override("font_hover_pressed_color", UiStyle.INK)
		b.pressed.connect(func() -> void: _show_tab(i))
		tabs.add_child(b)
		_tab_buttons.append(b)
	var page := MarginContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		page.add_theme_constant_override("margin_" + side, 28)
	page.add_theme_constant_override("margin_top", 6)
	page.add_theme_constant_override("margin_bottom", 16)
	cols.add_child(page)
	var page_col := VBoxContainer.new()
	page_col.add_theme_constant_override("separation", 14)
	page.add_child(page_col)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page_col.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 0)
	_scroll.add_child(_content)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	page_col.add_child(foot)
	var reset := MenuKit.button("Reset to defaults", "GhostButton", 42)
	reset.add_theme_color_override("font_color", UiStyle.INK_SOFT)
	reset.add_theme_color_override("font_hover_color", UiStyle.INK)
	reset.pressed.connect(_reset)
	foot.add_child(reset)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(sp)
	_changes = MenuKit.label("", "", 14, UiStyle.SHORT)
	_changes.add_theme_font_override("font", UiStyle.body_font(true))
	_changes.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_changes)
	var cancel := MenuKit.button("Cancel", "", 42)
	cancel.pressed.connect(_cancel)
	foot.add_child(cancel)
	_apply_button = MenuKit.button("Apply", "PrimaryButton", 42)
	_apply_button.pressed.connect(_apply)
	foot.add_child(_apply_button)
	hide()


func open(tab := 1) -> void:
	_draft = Settings.values.duplicate()
	show()
	_show_tab(tab)


func _show_tab(i: int) -> void:
	_tab = i
	_tab_buttons[i].set_pressed_no_signal(true)
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	_scroll.scroll_vertical = 0
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
			_accessibility_tab()
	_update_changes()


## A section heading with the space above it (14 px for the first one on a page, 18 after rows).
func _section(text: String, above := 18) -> void:
	_gap(above)
	_content.add_child(MenuKit.section(text))


func _gap(px: int) -> void:
	var gap := Control.new()
	gap.custom_minimum_size.y = px
	_content.add_child(gap)


func _game_tab() -> void:
	_section("Saving", 14)
	var opts := []
	for m: int in Settings.AUTOSAVE_MINUTES:
		opts.append("Off" if m == 0 else "%d min" % m)
	_content.add_child(MenuKit.setting_row("Autosave", "Game time between autosaves",
		MenuKit.segmented(opts, Settings.AUTOSAVE_MINUTES.find(_draft["autosave_minutes"]),
			func(i: int) -> void: _put("autosave_minutes", Settings.AUTOSAVE_MINUTES[i]))))
	var keep := _slider_with_value(1.0, 10.0, 1.0, _draft["autosave_count"], "%d", 1.0, "autosave_count")
	var keep_row := MenuKit.setting_row("Autosaves kept", _keep_hint(_draft["autosave_count"]), keep)
	var keep_hint: Label = keep_row.get_child(0).get_child(0).get_child(1)
	(keep.get_child(0) as HSlider).value_changed.connect(func(x: float) -> void: keep_hint.text = _keep_hint(x))
	_content.add_child(keep_row)
	_section("Worker names")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_gap(10)
	_content.add_child(row)
	var names := _names_editor()
	row.add_child(names["root"])
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 260
	side.add_theme_constant_override("separation", 10)
	row.add_child(side)
	side.add_child(MenuKit.info_box("", "New workers take these names first; leave empty for the built-in names."))
	var tip := MenuKit.label("Tip for streamers: paste your subscriber list here.", "", 14, UiStyle.INK_SOFT)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(tip)
	var clear := MenuKit.button("Clear the list", "", 36, 14)
	clear.pressed.connect(func() -> void:
		var edit: TextEdit = names["edit"]
		edit.text = ""
		edit.text_changed.emit())
	side.add_child(clear)


func _keep_hint(n: float) -> String:
	return "Keeps the newest autosave only" if int(n) <= 1 else "Keeps the %d newest autosaves; older ones are deleted" % int(n)


## The worker names box: numbered lines over a strip with the count. { root, edit }.
func _names_editor() -> Dictionary:
	var box := PanelContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.custom_minimum_size.y = 300
	var normal := UiStyle.box(UiStyle.PAPER, UiStyle.WOOD, 10, 2)
	normal.set_content_margin_all(2)
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = UiStyle.SELECT
	box.add_theme_stylebox_override("panel", normal)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	box.add_child(col)
	var edit := CodeEdit.new()           # CodeEdit for the line numbers
	edit.text = _draft["worker_names"]
	edit.placeholder_text = "Tilda\nBo\nIda"
	edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	edit.gutters_draw_line_numbers = true
	var pad := StyleBoxEmpty.new()
	pad.content_margin_left = 6
	pad.content_margin_right = 12
	pad.content_margin_top = 10
	pad.content_margin_bottom = 10
	for s in ["normal", "focus", "read_only"]:
		edit.add_theme_stylebox_override(s, pad)
	edit.add_theme_constant_override("line_spacing", 10)
	edit.add_theme_color_override("font_color", UiStyle.INK)
	edit.add_theme_color_override("font_placeholder_color", Color("#A39A8A"))
	edit.add_theme_color_override("line_number_color", Color("#A39A8A"))
	edit.add_theme_color_override("caret_color", UiStyle.SELECT)
	edit.add_theme_color_override("selection_color", UiStyle.SELECT_PAPER)
	edit.add_theme_color_override("current_line_color", Color.TRANSPARENT)
	col.add_child(edit)
	var strip := PanelContainer.new()
	var ssb := UiStyle.box(UiStyle.PAPER_DEEP, Color.TRANSPARENT, 0)
	ssb.corner_radius_bottom_left = 8
	ssb.corner_radius_bottom_right = 8
	ssb.content_margin_top = 5
	ssb.content_margin_bottom = 6
	strip.add_theme_stylebox_override("panel", ssb)
	col.add_child(strip)
	var sh := HBoxContainer.new()
	sh.add_theme_constant_override("separation", 4)
	strip.add_child(sh)
	var hint := MenuKit.label("one name per line", "", 13, UiStyle.INK_SOFT)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sh.add_child(hint)
	var count := MenuKit.label("", "", 13, UiStyle.INK)
	count.add_theme_font_override("font", UiStyle.body_font(true))
	sh.add_child(count)
	var unit := MenuKit.label("", "", 13, UiStyle.INK_SOFT)
	sh.add_child(unit)
	var recount := func() -> void:
		var n := 0
		for line in edit.text.split("\n", false):
			if line.strip_edges() != "":
				n += 1
		count.text = str(n)
		unit.text = "name" if n == 1 else "names"
	recount.call()
	edit.text_changed.connect(func() -> void:
		recount.call()
		_put("worker_names", edit.text))
	# the kit's focus look: blue edge and a light blue ring around the box
	edit.focus_entered.connect(func() -> void:
		box.add_theme_stylebox_override("panel", focus)
		box.queue_redraw())
	edit.focus_exited.connect(func() -> void:
		box.add_theme_stylebox_override("panel", normal)
		box.queue_redraw())
	box.draw.connect(func() -> void:
		if edit.has_focus():
			var ring := UiStyle.box(Color.TRANSPARENT, RING, 13, 3)
			box.draw_style_box(ring, Rect2(Vector2(-3, -3), box.size + Vector2(6, 6))))
	return {"root": box, "edit": edit}


func _display_tab() -> void:
	_section("Screen", 14)
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
	_section("Interface")
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
	_gap(16)
	var note := MenuKit.dashed_box(UiStyle.LOCKED, 10, 14, 10)
	var nh := HBoxContainer.new()
	nh.add_theme_constant_override("separation", 10)
	note.add_child(nh)
	var icon := UiStyle.icon_rect(UiStyle.icon("idle"), 22)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nh.add_child(icon)
	var nl := MenuKit.label("No sounds in the game yet — these levels will apply once audio arrives.", "", 15, MenuKit.MUTED)
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nh.add_child(nl)
	_content.add_child(note)
	_section("Volume")
	for bus: String in Settings.BUSES:
		var key: String = Settings.BUSES[bus]
		_content.add_child(MenuKit.setting_row(bus, "River, wind, birds" if bus == "Ambience" else "",
			_slider_with_value(0.0, 1.0, 0.05, _draft[key], "%d %%", 100.0, key)))


func _controls_tab() -> void:
	_section("Keys · read-only for now", 14)
	_gap(6)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 0)
	_content.add_child(grid)
	var half := KEYS.size() / 2
	for r in half:
		for k: Array in [KEYS[r], KEYS[half + r]]:
			grid.add_child(_key_row(k[0], k[1]))
	_gap(14)
	var mouse := MenuKit.label(MOUSE, "", 14, UiStyle.INK_SOFT)
	mouse.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(mouse)


func _key_row(keys: String, what: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 0)
	var h := HBoxContainer.new()
	h.custom_minimum_size.y = 47
	h.add_theme_constant_override("separation", 12)
	v.add_child(h)
	var caps := HBoxContainer.new()
	caps.custom_minimum_size.x = 120
	caps.add_theme_constant_override("separation", 4)
	h.add_child(caps)
	for k in keys.split(" "):
		caps.add_child(_cap(k))
	var l := MenuKit.label(what, "", 16, UiStyle.INK)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	var line := ColorRect.new()
	line.color = MenuKit.ROW_LINE
	line.custom_minimum_size.y = 1
	v.add_child(line)
	return v


## A key cap as in the kit's Controls page: paper, timber edge with a deeper bottom.
func _cap(key: String) -> Label:
	var l := MenuKit.label(key, "", 13, UiStyle.INK)
	l.add_theme_font_override("font", UiStyle.body_font(true))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(24, 26)
	var sb := UiStyle.box(UiStyle.PAPER, UiStyle.WOOD, 6, 1, 2)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 0
	sb.content_margin_bottom = 2
	l.add_theme_stylebox_override("normal", sb)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


func _accessibility_tab() -> void:
	_gap(24)
	var box := MenuKit.dashed_box(Color("#F4EFE5"), 14, 32, 48)
	_content.add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(v)
	var icon := UiStyle.icon_rect(UiStyle.icon("tech"), 56)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.modulate.a = 0.5
	v.add_child(icon)
	var title := MenuKit.head("Coming later", 22, 600, MenuKit.MUTED)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var text := MenuKit.label("Planned: bigger text, colour-blind friendly states, reduced motion and hold-to-confirm. " +
		"UI scale, tooltip delay and the number style are under Display.", "", 16, MenuKit.MUTED)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.custom_minimum_size.x = 460
	text.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(text)


func _dropdown(options: Array, selected: int, changed: Callable) -> OptionButton:
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	o.custom_minimum_size = Vector2(240, 38)
	o.add_theme_font_override("font", UiStyle.body_font(true))
	o.add_theme_font_size_override("font_size", 15)
	for t: String in options:
		o.add_item(t)
	o.select(maxi(0, selected))
	o.item_selected.connect(changed)
	return o


func _slider_with_value(lo: float, hi: float, step: float, value: float, fmt: String, mul: float, key: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var v := MenuKit.label(fmt % (value * mul), "", 15, UiStyle.INK)
	v.add_theme_font_override("font", UiStyle.body_font(true))
	v.custom_minimum_size.x = 52
	var s := MenuKit.slider(lo, hi, step, value, func(x: float) -> void:
		v.text = fmt % (x * mul)
		_put(key, int(x) if step >= 1.0 else x))
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
	_apply_button.disabled = n == 0


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


## --show=settings opens the Display tab with two changes, like the design; settings_game,
## settings_audio, settings_controls and settings_access open the other tabs.
func debug_show(what: String, _game: Node) -> void:
	match what:
		"settings":
			open(1)
			_draft["ui_scale"] = 1.1
			_draft["tooltip_delay"] = 0.3
			_show_tab(1)
		"settings_game":
			open(0)
			_draft["worker_names"] = "Tilda\nBo\nIda\nMara\nKuba\nPixel_Pete\nLenka\nOskar"
			_show_tab(0)
		"settings_audio":
			open(2)
		"settings_controls":
			open(3)
		"settings_access":
			open(4)
