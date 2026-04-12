extends Control

## Top bar HUD: money, planks, workers, game speed controls.

var _speed_buttons: Array[Button] = []
var _speed_values: Array[int] = []
var _current_speed: int = 1
var _money_label: Label
var _workers_label: Label
var _tasks_label: Label


func _ready() -> void:
	_build_hud()
	_set_speed(1)


func _process(_delta: float) -> void:
	_update_labels()


func _build_hud() -> void:
	# Background bar
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.1, 0.75)
	bg.custom_minimum_size = Vector2(0, 70)
	bg.set_anchors_preset(PRESET_TOP_WIDE)
	bg.size = Vector2(0, 70)
	add_child(bg)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(PRESET_TOP_WIDE)
	hbox.size = Vector2(0, 70)
	hbox.add_theme_constant_override("separation", 30)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(hbox)

	# Money
	_money_label = _create_label(hbox, "$ 1000")

	# Workers
	_workers_label = _create_label(hbox, "Workers: 0/0")

	# Tasks
	_tasks_label = _create_label(hbox, "Tasks: 0")

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	# Speed controls
	var speed_label := Label.new()
	speed_label.text = "Speed:"
	speed_label.add_theme_font_size_override("font_size", 24)
	speed_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(speed_label)

	var speeds := [
		["||", 0],
		["1x", 1],
		["3x", 3],
		["5x", 5],
		["10x", 10],
	]

	for speed_data in speeds:
		var label: String = speed_data[0]
		var speed: int = speed_data[1]
		var btn := Button.new()
		btn.text = label
		btn.custom_minimum_size = Vector2(65, 45)
		btn.add_theme_font_size_override("font_size", 22)
		btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		btn.pressed.connect(_on_speed_pressed.bind(speed))
		hbox.add_child(btn)
		_speed_buttons.append(btn)
		_speed_values.append(speed)

	# Right padding
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(20, 0)
	hbox.add_child(pad)


func _create_label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 24)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(label)
	return label


func _on_speed_pressed(speed: int) -> void:
	_set_speed(speed)


func _set_speed(speed: int) -> void:
	_current_speed = speed
	Engine.time_scale = speed

	# Highlight active button
	for i in range(_speed_buttons.size()):
		if _speed_values[i] == speed:
			_speed_buttons[i].modulate = Color(0.5, 1, 0.5)
		else:
			_speed_buttons[i].modulate = Color.WHITE


func _update_labels() -> void:
	# TODO: connect to actual economy system
	_money_label.text = "$ 1000"

	# Worker count
	var worker_manager := get_node_or_null("/root/Main/WorkerManager")
	if worker_manager:
		var total: int = worker_manager.workers.size()
		var idle := 0
		for worker in worker_manager.workers:
			if worker.state == worker.WorkerState.IDLE:
				idle += 1
		_workers_label.text = "Workers: %d idle / %d" % [idle, total]

	# Task count + stored resources
	var parts: Array[String] = ["Tasks: %d" % TaskQueue.get_pending_count()]

	var resource_types := [
		ResourceManager.ResourceType.POTATOES,
		ResourceManager.ResourceType.WHEAT,
		ResourceManager.ResourceType.CORN,
		ResourceManager.ResourceType.SUGAR_BEET,
		ResourceManager.ResourceType.WOOD,
		ResourceManager.ResourceType.PLANKS,
	]
	for res_type in resource_types:
		var amount: int = ResourceManager.get_total_resource(res_type)
		if amount > 0:
			var name: String = ResourceManager.resource_name(res_type)
			parts.append("%s: %d kg" % [name, amount])

	_tasks_label.text = "  |  ".join(parts)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_SPACE:
				if _current_speed == 0:
					_set_speed(1)
				else:
					_set_speed(0)
				get_viewport().set_input_as_handled()
			KEY_1:
				_set_speed(1)
				get_viewport().set_input_as_handled()
			KEY_3:
				_set_speed(3)
				get_viewport().set_input_as_handled()
			KEY_5:
				_set_speed(5)
				get_viewport().set_input_as_handled()
