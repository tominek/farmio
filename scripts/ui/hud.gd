class_name Hud
extends CanvasLayer
## Top bar (money, wood, workers, tasks, speed) and a minimal build bar.

signal build_requested(def_id: StringName)
signal speed_requested(speed: float)

var world: World
var tool: PlacementTool
var _stats: Label
var _hint: Label
var _speed_label: Label
var dealer_panel: DealerPanel
var dev_menu: DevMenu
var _alerts: Label
var _float: PanelContainer        # crop icons floating above the field being drawn
var _float_icons := {}
var _float_info: Label
var _accum := 0.0


func setup(p_world: World, p_tool: PlacementTool) -> void:
	world = p_world
	tool = p_tool

	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	add_child(top)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 16)
	top.add_child(bar)
	_stats = Label.new()
	_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_stats)
	var dealer_btn := Button.new()
	dealer_btn.text = "Dealer"
	dealer_btn.focus_mode = Control.FOCUS_NONE
	dealer_btn.pressed.connect(toggle_dealer)
	bar.add_child(dealer_btn)
	_speed_label = Label.new()
	bar.add_child(_speed_label)
	for s in [[0.0, "||"], [1.0, "1x"], [2.0, "2x"], [3.0, "3x"]]:
		var b := Button.new()
		b.text = s[1]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: speed_requested.emit(s[0]))
		bar.add_child(b)

	_alerts = Label.new()
	_alerts.position = Vector2(12, 44)
	_alerts.add_theme_color_override("font_color", Color(1.0, 0.82, 0.45))
	_alerts.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_alerts.add_theme_constant_override("outline_size", 4)
	add_child(_alerts)

	dealer_panel = DealerPanel.new()
	add_child(dealer_panel)
	dealer_panel.setup(world)
	dealer_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	dealer_panel.hide()

	dev_menu = DevMenu.new()
	add_child(dev_menu)
	dev_menu.setup(world)
	dev_menu.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	dev_menu.position += Vector2(-16, 44)
	dev_menu.speed_requested.connect(func(s: float) -> void: speed_requested.emit(s))
	dev_menu.hide()

	var bottom := VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.position += Vector2(12, -12)
	add_child(bottom)
	_hint = Label.new()
	bottom.add_child(_hint)
	_build_float()
	var builds := HBoxContainer.new()
	bottom.add_child(builds)
	for id: StringName in Defs.BUILDINGS:
		var d: Dictionary = Defs.BUILDINGS[id]
		if not d["buildable"]:
			continue
		var b := Button.new()
		b.text = "%s  $%d" % [d["name"], d["cost"]] if d["cost"] > 0 else d["name"]
		if d.has("field"):
			b.text = "%s  $%d/tile" % [d["name"], Defs.FIELD_COST_PER_TILE]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: _on_build_pressed(id))
		builds.add_child(b)
	tool.changed.connect(_refresh)
	world.stock_changed.connect(_refresh)
	_refresh()


func set_speed_text(text: String) -> void:
	_speed_label.text = text


func _process(delta: float) -> void:
	_update_float()
	_accum += delta
	if _accum > 0.25:
		_accum = 0.0
		_refresh()


func _refresh() -> void:
	var goods := ""
	for c: StringName in Defs.CROPS:
		if world.stock.get(c, 0.0) > 0.0:
			goods += "    %s %s" % [Defs.CROPS[c]["name"], Defs.format_kg(world.stock[c])]
	_stats.text = "$ %d    Wood %d%s    Workers %d idle / %d    Tasks %d waiting / %d" % [
		world.money, world.stock[&"wood"], goods, world.idle_workers(), world.workers.size(),
		world.tasks.pending_count(), world.tasks.tasks.size()]
	_hint.text = tool.hint()
	_alerts.text = "\n".join(world.alerts())


func _on_build_pressed(id: StringName) -> void:
	build_requested.emit(id)


func _build_float() -> void:
	_float = PanelContainer.new()
	_float.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_float.visible = false
	add_child(_float)
	var col := VBoxContainer.new()
	_float.add_child(col)
	_float_info = Label.new()
	_float_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_float_info.add_theme_font_size_override("font_size", 18)
	col.add_child(_float_info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	col.add_child(row)
	for c: StringName in Defs.CROPS:
		var box := VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon := TextureRect.new()
		icon.texture = load("res://assets/ui/icons/crop_%s.png" % c)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(64, 64)
		box.add_child(icon)
		var name := Label.new()
		name.text = Defs.CROPS[c]["name"]
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name.add_theme_font_size_override("font_size", 13)
		box.add_child(name)
		row.add_child(box)
		_float_icons[c] = box
	var tab := Label.new()
	tab.text = "Tab"
	tab.add_theme_font_size_override("font_size", 12)
	tab.modulate = Color(1, 1, 1, 0.7)
	row.add_child(tab)


func _update_float() -> void:
	var on := tool.active() and Defs.is_field(tool.def_id)
	_float.visible = on
	if not on:
		return
	for c: StringName in _float_icons:
		var box: Control = _float_icons[c]
		var selected: bool = c == tool.crop
		box.modulate = Color.WHITE if selected else Color(1, 1, 1, 0.4)
		box.scale = Vector2.ONE * (1.0 if selected else 0.85)
	var info := tool.field_info()
	_float_info.text = info
	_float_info.visible = info != ""
	_float.reset_size()
	var cam := tool.rig.camera
	var p := cam.unproject_position(tool.picker_anchor())
	var dy := -_float.size.y - 40.0 if tool.picker_above() else 24.0
	_float.position = p + Vector2(-_float.size.x * 0.5, dy)
	var screen := get_viewport().get_visible_rect().size
	_float.position = _float.position.clamp(Vector2(8, 40), screen - _float.size - Vector2(8, 40))


func toggle_dealer() -> void:
	dealer_panel.visible = not dealer_panel.visible
	if dealer_panel.visible:
		dealer_panel.refresh()


func toggle_dev_menu() -> void:
	dev_menu.visible = not dev_menu.visible
	if dev_menu.visible:
		dev_menu.refresh()
