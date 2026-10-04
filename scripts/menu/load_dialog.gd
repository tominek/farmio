class_name LoadDialog
extends Control
## Load game (main menu, game menu): saves on the left (filter All / Manual / Auto & quick), the
## selected one on the right with its picture and numbers, Delete (asks twice) and Load.

signal load_requested(slot: String)
signal closed

const FILTERS := ["All", "Manual", "Auto & quick"]

var in_game := false              # shows the "unsaved progress" warning
var _filter := 0
var _selected := ""
var _list: VBoxContainer
var _details: VBoxContainer
var _warning: PanelContainer
var _delete: Button
var _load: Button
var _armed := false
var _seg: PanelContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_to_group("debug_show")
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var p := UiStyle.make_panel("Load game")
	var root: PanelContainer = p["root"]
	root.custom_minimum_size = Vector2(1256, 0)
	center.add_child(root)
	(p["close"] as Button).pressed.connect(close)
	var body: VBoxContainer = p["body"]
	var margin := body.get_parent() as MarginContainer
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 0)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 0)
	body.add_child(cols)

	var left := MarginContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		left.add_theme_constant_override("margin_" + side, 20)
	cols.add_child(left)
	var lc := VBoxContainer.new()
	lc.add_theme_constant_override("separation", 12)
	left.add_child(lc)
	var bar := HBoxContainer.new()
	lc.add_child(bar)
	_seg = MenuKit.segmented(FILTERS, 0, func(i: int) -> void:
		_filter = i
		_refresh())
	bar.add_child(_seg)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp)
	var newest := MenuKit.label("Newest first", "", 14, UiStyle.INK)
	newest.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(newest)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(796, 600)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lc.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)

	var edge := ColorRect.new()
	edge.color = Color("#EADCC1")
	edge.custom_minimum_size.x = 2
	cols.add_child(edge)
	var right := MarginContainer.new()
	right.custom_minimum_size.x = 418
	for side in ["left", "right", "top", "bottom"]:
		right.add_theme_constant_override("margin_" + side, 20)
	cols.add_child(right)
	var rc := VBoxContainer.new()
	rc.add_theme_constant_override("separation", 10)
	right.add_child(rc)
	_details = VBoxContainer.new()
	_details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_details.add_theme_constant_override("separation", 10)
	rc.add_child(_details)
	_warning = PanelContainer.new()
	var wsb := UiStyle.box(UiStyle.WARN_PAPER, UiStyle.WARN, 8, 2)
	wsb.content_margin_top = 8
	wsb.content_margin_bottom = 8
	_warning.add_theme_stylebox_override("panel", wsb)
	var wh := HBoxContainer.new()
	wh.add_theme_constant_override("separation", 10)
	_warning.add_child(wh)
	wh.add_child(UiStyle.icon_rect(UiStyle.icon("warning"), 20))
	wh.add_child(MenuKit.label("Unsaved progress in the current game will be lost.", "", 15, UiStyle.INK))
	rc.add_child(_warning)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	rc.add_child(buttons)
	_delete = Button.new()
	_delete.text = "Delete"
	_delete.theme_type_variation = "DangerButton"
	_delete.focus_mode = Control.FOCUS_NONE
	_delete.custom_minimum_size = Vector2(76, 48)
	_delete.pressed.connect(_on_delete)
	buttons.add_child(_delete)
	_load = Button.new()
	_load.text = "Load"
	_load.theme_type_variation = "PrimaryButton"
	_load.focus_mode = Control.FOCUS_NONE
	_load.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_load.custom_minimum_size.y = 48
	_load.pressed.connect(func() -> void:
		if _selected != "":
			load_requested.emit(_selected))
	buttons.add_child(_load)
	hide()


func open(p_in_game: bool) -> void:
	in_game = p_in_game
	_warning.visible = in_game
	_filter = 0
	MenuKit.set_segment(_seg, 0)
	_selected = ""
	_refresh()
	show()


func close() -> void:
	hide()
	closed.emit()


func _shown(m: Dictionary) -> bool:
	match _filter:
		1:
			return m["kind"] == "manual"
		2:
			return m["kind"] != "manual"
	return true


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	var shown: Array[Dictionary] = []
	for m in SaveGame.list():
		if _shown(m):
			shown.append(m)
	if not shown.any(func(m: Dictionary) -> bool: return m["slot"] == _selected):
		_selected = shown[0]["slot"] if not shown.is_empty() else ""
	for m in shown:
		var r := MenuKit.slot_row(m)
		var row: Button = r["root"]
		row.button_pressed = m["slot"] == _selected
		row.pressed.connect(func() -> void: _select(m["slot"]))
		_list.add_child(row)
	if shown.is_empty():
		_list.add_child(MenuKit.label("No saves here yet.", "SoftLabel"))
	_show_details()


func _select(slot: String) -> void:
	_selected = slot
	_armed = false
	for row: Node in _list.get_children():
		if row is Button:
			(row as Button).set_pressed_no_signal(false)
	_refresh()


func _show_details() -> void:
	for c in _details.get_children():
		c.queue_free()
	_armed = false
	_delete.text = "Delete"
	_delete.disabled = _selected == ""
	_load.disabled = _selected == ""
	if _selected == "":
		return
	var m := SaveGame.meta(_selected)
	_details.add_child(MenuKit.thumb(SaveGame.thumbnail(_selected), Vector2(378, 212)))
	var title := MenuKit.head(m.get("name", _selected), 26, 700)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.add_child(title)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	line.add_child(MenuKit.badge(m.get("kind", "manual")))
	var t := MenuKit.when(int(m.get("saved", 0)))
	if m.get("farm", "") != "" and not String(m.get("name", "")).begins_with(m["farm"]):
		t = "%s · %s" % [m["farm"], t]
	if float(m.get("played", 0.0)) > 0.0:
		t += " · played " + MenuKit.duration(m["played"])
	line.add_child(MenuKit.label(t, "", 14, UiStyle.INK_SOFT))
	_details.add_child(line)
	if not m.has("quacks"):
		return
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_details.add_child(grid)
	if int(m.get("day", 0)) > 0:
		_tile(grid, "Day", str(int(m["day"])))
	_tile(grid, "Quacks", UiStyle.money_number(m["quacks"]), true)
	_tile(grid, "Workers", str(int(m["workers"])))
	_tile(grid, "Fields", "%d · %d tiles" % [m["fields"], m["tiles"]])
	_tile(grid, "Buildings", str(int(m["buildings"])))
	_tile(grid, "Research", "%d of %d" % [m["research"], m["research_total"]])


func _tile(grid: GridContainer, title: String, value: String, coin := false) -> void:
	var p := PanelContainer.new()
	p.theme_type_variation = "Well"
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	p.add_child(v)
	v.add_child(MenuKit.label(title, "", 14, UiStyle.INK_SOFT))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	v.add_child(h)
	var l := MenuKit.label(value, "", 19, UiStyle.INK)
	l.add_theme_font_override("font", UiStyle.body_font(true))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL if not coin else Control.SIZE_FILL
	h.add_child(l)
	if coin:
		h.add_child(UiStyle.icon_rect(UiStyle.icon("qk"), 18))
	grid.add_child(p)


func _on_delete() -> void:
	if _selected == "":
		return
	if not _armed:
		_armed = true
		_delete.text = "Delete?"
		return
	SaveGame.delete(_selected)
	_selected = ""
	_refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()


func debug_show(what: String, _game: Node) -> void:
	if what == "load":
		open(true)
