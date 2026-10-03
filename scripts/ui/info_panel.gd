class_name InfoPanel
extends PanelContainer
## Info about the selected field, building, construction site, road block or worker,
## with the crop choice for fields and demolition.

signal selection_changed

var world: World
var target: Variant = null      # Building, Worker or Vector2i (road block anchor)
var _title: Label
var _body: Label
var _crops: HBoxContainer
var _crop_buttons := {}
var _action: Button
var _reason: Label
var _armed := false             # demolish needs a second click
var _accum := 0.0


func setup(p_world: World) -> void:
	world = p_world
	custom_minimum_size = Vector2(420, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close := Button.new()
	close.text = "✕"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(clear)
	head.add_child(close)

	_body = Label.new()
	box.add_child(_body)

	_crops = HBoxContainer.new()
	_crops.add_theme_constant_override("separation", 6)
	box.add_child(_crops)
	var lbl := Label.new()
	lbl.text = "Next sowing:"
	_crops.add_child(lbl)
	for c: StringName in Defs.CROPS:
		var b := Button.new()
		b.icon = load("res://assets/ui/icons/crop_%s.png" % c)
		b.expand_icon = true
		b.custom_minimum_size = Vector2(52, 52)
		b.tooltip_text = Defs.CROPS[c]["name"]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void:
			if target is Field:
				world.set_field_crop(target, c)
				refresh())
		_crops.add_child(b)
		_crop_buttons[c] = b

	_action = Button.new()
	_action.focus_mode = Control.FOCUS_NONE
	_action.pressed.connect(press_action)
	box.add_child(_action)
	_reason = Label.new()
	_reason.modulate = Color(1, 0.75, 0.6)
	box.add_child(_reason)

	world.building_removed.connect(func(b: Building) -> void:
		if target == b:
			clear())
	world.worker_removed.connect(func(w: Worker) -> void:
		if target == w:
			clear())
	world.road_changed.connect(func(a: Vector2i) -> void:
		if target is Vector2i and target == a and not world.road_blocks.has(a):
			clear())
	hide()


func select(t: Variant) -> void:
	target = t
	_armed = false
	visible = t != null
	refresh()
	selection_changed.emit()


func clear() -> void:
	select(null)


## Grid rectangle to highlight on the ground, or an empty one.
func highlight_rect() -> Rect2i:
	if target is Building:
		return (target as Building).rect()
	if target is Worker:
		return Rect2i((target as Worker).cell(), Vector2i.ONE)
	if target is Vector2i:
		return Rect2i(target, Vector2i(Defs.ROAD_BLOCK, Defs.ROAD_BLOCK))
	return Rect2i()


## Demolish / cancel (Delete key or the button); the first press only asks for confirmation.
func press_action() -> void:
	if not visible or not _action.visible or _action.disabled:
		return
	if not _armed:
		_armed = true
		refresh()
		return
	if target is Building:
		world.demolish(target)
	elif target is Vector2i:
		world.demolish_road(target)
	clear()


func _process(delta: float) -> void:
	if not visible:
		return
	_accum += delta
	if _accum > 0.25:
		_accum = 0.0
		refresh()


func refresh() -> void:
	if target == null:
		return
	_crops.visible = target is Field
	_action.visible = false
	_reason.text = ""
	if target is Field:
		_show_field(target)
	elif target is ConstructionSite:
		_show_site(target)
	elif target is Building:
		_show_building(target)
	elif target is Worker:
		_show_worker(target)
	elif target is Vector2i:
		_show_road(target)
	_reason.visible = _reason.text != ""
	reset_size()
	# keep the bottom-right corner in place while the content changes height
	position = get_viewport_rect().size - size - Vector2(12, 12)


func _set_action(text: String, blocker: String) -> void:
	_action.visible = true
	_action.disabled = blocker != ""
	_action.text = "Click again to confirm: %s" % text if _armed else text
	_reason.text = blocker


func _show_field(f: Field) -> void:
	var crop: Dictionary = Defs.CROPS[f.crop]
	var tiles := f.size.x * f.size.y
	_title.text = "%s field" % crop["name"]
	var counts := [0, 0, 0, 0]
	for r in f.size.y:
		counts[f.row_step[r]] += 1
	var lines := PackedStringArray()
	lines.append("%d × %d tiles (%d)" % [f.size.x, f.size.y, tiles])
	lines.append("Rows: %d to cultivate · %d to sow · %d growing · %d to harvest" % counts)
	var planted := 0
	var growth := 0.0
	var least := 1.0
	for i in f.tile_state.size():
		if f.tile_state[i] == Field.TileState.PLANTED:
			planted += 1
			growth += f.growth[i]
			least = minf(least, f.growth[i])
	if planted > 0:
		var left := (1.0 - least) * float(crop["grow_time"])
		lines.append("Crop: %d %% grown · all ripe in %d:%02d" % [roundi(growth / planted * 100.0), floori(left / 60.0), int(left) % 60])
	var seed_res := Defs.seed_of(f.crop)
	lines.append("Seed per sowing: %s · in the barn %s" % [
		Defs.format_kg(tiles * Defs.seed_per_tile(f.crop)), Defs.format_kg(world.stock.get(seed_res, 0.0))])
	var harvest: float = tiles * crop["yield"]
	lines.append("Full harvest: ~%s (≈ $%d)" % [Defs.format_kg(harvest), roundi(harvest * Defs.SELL_PRICE.get(f.crop, 0.0))])
	if f.pile > 0.01:
		lines.append("At the gate: %s" % Defs.format_kg(f.pile))
	if f.next_crop != f.crop:
		lines.append("Switching to %s once the %s is harvested and carried away" % [
			Defs.CROPS[f.next_crop]["name"], String(crop["name"]).to_lower()])
	_body.text = "\n".join(lines)
	for c: StringName in _crop_buttons:
		var b: Button = _crop_buttons[c]
		b.modulate = Color.WHITE if c == f.next_crop else Color(1, 1, 1, 0.45)
	_set_action("Demolish field (refund $%d, crops are lost)" % f.paid, world.demolish_blocker(f))


func _show_site(s: ConstructionSite) -> void:
	_title.text = s.display_name()
	var lines := PackedStringArray()
	var workers := 0
	for t in s.open_tasks:
		if t.worker:
			workers += 1
	if s.stage == ConstructionSite.Stage.CLEARING:
		lines.append("Clearing: %d trees to chop" % s.open_tasks.size())
	else:
		lines.append("Building: %d %%" % roundi(s.progress() * 100.0))
	lines.append("Workers here: %d" % workers)
	_body.text = "\n".join(lines)
	_set_action("Cancel construction (refund $%d)" % s.paid, "")


func _show_building(b: Building) -> void:
	_title.text = b.display_name()
	var lines := PackedStringArray()
	if Defs.def(b.def_id).get("storage", false):
		lines.append("Stored:")
		for res: StringName in world.stock:
			if world.stock[res] > 0.0001:
				lines.append("   %s  %s" % [Defs.resource_name(res), Defs.format_amount(res, world.stock[res])])
		if lines.size() == 1:
			lines.append("   nothing yet")
	for v in world.vehicles:
		if v.garage == b:
			lines.append("Light Pickup: %s" % world.trip_status)
	_body.text = "\n".join(lines)
	_set_action("Demolish (refund $%d)" % b.paid, world.demolish_blocker(b))


func _show_worker(w: Worker) -> void:
	_title.text = "Worker %d" % (world.workers.find(w) + 1)
	var lines := PackedStringArray()
	lines.append(_worker_status(w))
	if w.carrying != &"":
		lines.append("Carrying: %s %s" % [Defs.format_amount(w.carrying, w.carry_amount), Defs.resource_name(w.carrying).to_lower()])
	_body.text = "\n".join(lines)


func _worker_status(w: Worker) -> String:
	if w.in_vehicle:
		return "Driving the pickup" if w.task else "Riding in the pickup"
	match w.phase:
		Worker.Phase.IDLE:
			return "Idle — waiting for work"
		Worker.Phase.TO_FETCH:
			return "Fetching %s for: %s" % [Defs.resource_name(w.task.fetch).to_lower(), w.task.label()]
		Worker.Phase.TO_TASK:
			return "Walking to: %s" % w.task.label()
		Worker.Phase.WORKING:
			return w.task.label()
		Worker.Phase.TO_DELIVER:
			return "Bringing it to the barn"
	return ""


func _show_road(anchor: Vector2i) -> void:
	_title.text = "%s" % Defs.def(&"road_%s" % world.road_blocks[anchor])["name"]
	_body.text = "Vehicles drive only on roads; workers walk faster on them."
	_set_action("Demolish road", world.road_blocker(anchor))
