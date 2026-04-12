extends Control

## Debug menu toggled with F12. Clickable GUI panel for testing.

var _panel: PanelContainer
var _visible: bool = false


func _ready() -> void:
	visible = false
	_build_menu()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F12:
		_visible = !_visible
		visible = _visible
		get_viewport().set_input_as_handled()


func _build_menu() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_panel.position = Vector2(-300, -300)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.9)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(15)
	_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "Debug Menu [F12]"
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)

	_add_separator(vbox, "Workers")
	_add_button(vbox, "Spawn 1 Worker", _spawn_workers.bind(1))
	_add_button(vbox, "Spawn 5 Workers", _spawn_workers.bind(5))
	_add_button(vbox, "Spawn 10 Workers", _spawn_workers.bind(10))

	_add_separator(vbox, "Resources")
	_add_button(vbox, "Add $1000", _add_money.bind(1000))
	_add_button(vbox, "Add $10000", _add_money.bind(10000))

	_add_separator(vbox, "Field")
	_add_button(vbox, "Force Grow All 50%", _force_grow.bind(0.5))
	_add_button(vbox, "Force Grow All 100%", _force_grow.bind(1.0))

	_add_separator(vbox, "Research")
	_add_button(vbox, "Unlock All", _unlock_all)

	_add_separator(vbox, "Time")
	_add_button(vbox, "Speed 20x", _set_speed.bind(20))
	_add_button(vbox, "Speed 50x", _set_speed.bind(50))

	_add_separator(vbox, "Camera")
	_add_button(vbox, "Go to Dealer", _go_to_dealer)
	_add_button(vbox, "Go to Farm", _go_to_farm)

	add_child(_panel)


func _add_button(parent: Node, text: String, callback: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(250, 45)
	btn.add_theme_font_size_override("font_size", 22)
	btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	btn.pressed.connect(callback)
	parent.add_child(btn)


func _add_separator(parent: Node, text: String) -> void:
	var label := Label.new()
	label.text = "— %s —" % text
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	parent.add_child(label)


func _spawn_workers(count: int) -> void:
	var worker_manager: Node3D = get_node_or_null("/root/Main/WorkerManager")
	if not worker_manager:
		return

	var world_gen: Node3D = get_node_or_null("/root/Main/WorldGenerator")
	var origin := Vector2i.ZERO
	if world_gen:
		origin = world_gen.farm_origin

	worker_manager.spawn_family_workers(origin, count)


func _add_money(amount: int) -> void:
	# TODO: connect to economy system
	print("Added $%d (economy not implemented yet)" % amount)


func _force_grow(target: float) -> void:
	var fields: Node3D = get_node_or_null("/root/Main/Fields")
	if not fields:
		return

	for field in fields.get_children():
		if field.has_method("get_tile_growth"):
			for tile_pos in field._tiles:
				var tile_data: Dictionary = field._tiles[tile_pos]
				tile_data["growth"] = target
			if target >= 1.0:
				field._phase = field.FieldPhase.HARVEST
				field._reset_done_flags()
				field._generate_all_tasks(TaskQueue.TaskType.HARVEST)


func _unlock_all() -> void:
	# TODO: connect to research system
	print("Unlock all (research not implemented yet)")


func _set_speed(speed: int) -> void:
	Engine.time_scale = speed


func _go_to_dealer() -> void:
	var world_gen: Node3D = get_node_or_null("/root/Main/WorldGenerator")
	var camera_rig: Node3D = get_node_or_null("/root/Main/CameraRig")
	if world_gen and camera_rig:
		var pos: Vector3 = GridManager.tile_to_world(world_gen.dealer_position)
		camera_rig.position = Vector3(pos.x, 0, pos.z)


func _go_to_farm() -> void:
	var world_gen: Node3D = get_node_or_null("/root/Main/WorldGenerator")
	var camera_rig: Node3D = get_node_or_null("/root/Main/CameraRig")
	if world_gen and camera_rig:
		var pos: Vector3 = GridManager.tile_to_world(world_gen.farm_origin)
		camera_rig.position = Vector3(pos.x, 0, pos.z)
