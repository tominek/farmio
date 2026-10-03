class_name DevMenu
extends PanelContainer
## Developer menu (F12): cheats and tools for testing. Not meant for release builds.

signal speed_requested(speed: float)

var world: World
var _workers: Label
var _accum := 0.0


func setup(p_world: World) -> void:
	world = p_world
	custom_minimum_size = Vector2(300, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var title := Label.new()
	title.text = "Developer (F12)"
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)

	_workers = Label.new()
	box.add_child(_workers)
	box.add_child(_row([
		["+ Worker", _add_worker],
		["− Worker", func() -> void: world.remove_worker()],
	]))

	box.add_child(_heading("Resources"))
	box.add_child(_row([
		["+ $1000", func() -> void: world.money += 1000; world.stock_changed.emit()],
		["+ seed for 100 tiles each", _add_seeds],
	]))

	box.add_child(_heading("Time"))
	var speeds := []
	for s in [5.0, 10.0, 50.0]:
		speeds.append(["%dx" % s, func() -> void: speed_requested.emit(s)])
	box.add_child(_row(speeds))
	refresh()


func _add_worker() -> void:
	var looks := Worker.Look.values()
	var barn: Variant = world.delivery_target(world.workers[0].cell()) if not world.workers.is_empty() else null
	var cell: Vector2i = barn if barn != null else Vector2i(world.size / 2, world.size / 2)
	world.add_worker(cell, looks[randi() % looks.size()])


func _add_seeds() -> void:
	for crop: StringName in Defs.CROPS:
		world.stock[Defs.seed_of(crop)] += Defs.seed_per_tile(crop) * 100.0
	world.stock_changed.emit()


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.modulate = Color(1, 0.92, 0.7)
	return l


func _row(buttons: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	for b in buttons:
		var btn := Button.new()
		btn.text = b[0]
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(b[1])
		row.add_child(btn)
	return row


func _process(delta: float) -> void:
	if not visible:
		return
	_accum += delta
	if _accum > 0.25:
		_accum = 0.0
		refresh()


func refresh() -> void:
	_workers.text = "Workers: %d (%d idle)" % [world.workers.size(), world.idle_workers()]
