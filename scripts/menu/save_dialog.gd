class_name SaveDialog
extends Control
## Save game (from the game menu): type a name and save as a new slot, or overwrite a slot.
## The autosave slot is written by the game only. `save_requested(slot, name)` does the saving.

signal save_requested(slot: String, save_name: String)
signal closed

var world: World
var _name: LineEdit
var _list: VBoxContainer
var _footer: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_to_group("debug_show")
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var p := UiStyle.make_panel("Save game")
	var root: PanelContainer = p["root"]
	root.custom_minimum_size = Vector2(896, 0)
	center.add_child(root)
	(p["close"] as Button).pressed.connect(close)
	var body: VBoxContainer = p["body"]
	var margin := body.get_parent() as MarginContainer
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 0)
	body.add_theme_constant_override("separation", 0)

	# new save: name + Save as new, on a paper-deep band
	var top := PanelContainer.new()
	var top_sb := UiStyle.box(Color("#F3EBD8"), Color.TRANSPARENT, 0)
	top_sb.content_margin_left = 20
	top_sb.content_margin_right = 20
	top_sb.content_margin_top = 16
	top_sb.content_margin_bottom = 14
	top.add_theme_stylebox_override("panel", top_sb)
	body.add_child(top)
	var tc := VBoxContainer.new()
	tc.add_theme_constant_override("separation", 8)
	top.add_child(tc)
	tc.add_child(MenuKit.section("New save"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	tc.add_child(row)
	_name = LineEdit.new()
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.custom_minimum_size.y = 44
	_name.add_theme_font_size_override("font_size", 17)
	_name.max_length = 60
	_name.add_theme_color_override("font_selected_color", UiStyle.INK)
	_name.text_submitted.connect(func(_t: String) -> void: _save_new())
	row.add_child(_name)
	var save := Button.new()
	save.text = "Save as new"
	save.theme_type_variation = "PrimaryButton"
	save.focus_mode = Control.FOCUS_NONE
	save.custom_minimum_size.y = 44
	save.pressed.connect(_save_new)
	row.add_child(save)
	tc.add_child(MenuKit.label("Enter saves · F5 quicksaves without this dialog", "", 13, UiStyle.INK_SOFT))

	var mid := MarginContainer.new()
	for side in ["left", "right"]:
		mid.add_theme_constant_override("margin_" + side, 20)
	mid.add_theme_constant_override("margin_top", 16)
	mid.add_theme_constant_override("margin_bottom", 8)
	body.add_child(mid)
	var mc := VBoxContainer.new()
	mc.add_theme_constant_override("separation", 8)
	mid.add_child(mc)
	mc.add_child(MenuKit.section("Or overwrite"))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 520
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mc.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)

	var line := ColorRect.new()
	line.color = Color("#EFE4D0")
	line.custom_minimum_size.y = 2
	body.add_child(line)
	var foot := MarginContainer.new()
	for side in ["left", "right"]:
		foot.add_theme_constant_override("margin_" + side, 20)
	foot.add_theme_constant_override("margin_top", 10)
	foot.add_theme_constant_override("margin_bottom", 12)
	body.add_child(foot)
	var fh := HBoxContainer.new()
	foot.add_child(fh)
	_footer = MenuKit.label("", "", 14, UiStyle.INK_SOFT)
	_footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fh.add_child(_footer)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(close)
	fh.add_child(cancel)
	hide()


func open(p_world: World) -> void:
	world = p_world
	_name.text = MenuKit.default_save_name(world)
	_refresh()
	show()
	_name.grab_focus()
	_name.caret_column = _name.text.length()


func close() -> void:
	hide()
	closed.emit()


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	var saves := SaveGame.list()
	var bytes := 0
	var first := true
	for m in saves:
		bytes += int(m.get("bytes", 0))
		var r := MenuKit.slot_row(m)
		var row: Button = r["root"]
		row.button_pressed = first and m["kind"] != "autosave"
		if row.button_pressed:
			first = false
		_list.add_child(row)
		var right: HBoxContainer = r["right"]
		right.custom_minimum_size.x = 104
		right.alignment = BoxContainer.ALIGNMENT_CENTER
		if m["kind"] == "autosave":
			right.add_child(MenuKit.label("auto only", "", 14, UiStyle.INK_SOFT))
			row.disabled = true
		else:
			var b := Button.new()
			b.text = "Overwrite"
			b.focus_mode = Control.FOCUS_NONE
			b.theme_type_variation = "PrimaryButton" if row.button_pressed else ""
			b.pressed.connect(func() -> void: _overwrite(m))
			right.add_child(b)
			row.toggled.connect(func(on: bool) -> void:
				b.theme_type_variation = "PrimaryButton" if on else ""
				if on:
					for other in _list.get_children():
						if other != row:
							(other as Button).set_pressed_no_signal(false)
							_style_overwrite(other as Button))
	if saves.is_empty():
		_list.add_child(MenuKit.label("No saves yet.", "SoftLabel"))
	_footer.text = "%d save%s · %s" % [saves.size(), "" if saves.size() == 1 else "s", MenuKit.file_size(bytes)]


func _style_overwrite(row: Button) -> void:
	for b in row.find_children("*", "Button", true, false):
		(b as Button).theme_type_variation = ""


func _save_new() -> void:
	var n := _name.text.strip_edges()
	if n == "":
		n = MenuKit.default_save_name(world)
	save_requested.emit(SaveGame.new_manual_slot(), n)
	close()


func _overwrite(m: Dictionary) -> void:
	# a quicksave stays the quicksave; a manual slot keeps its name unless one was typed
	var n: String = m.get("name", "")
	save_requested.emit(m["slot"], n)
	close()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()


func debug_show(what: String, game: Node) -> void:
	if what == "save":
		open(game.world)
