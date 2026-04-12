extends Control

## Temporary debug build menu. Press B to toggle, click a button to start placing.

@export var building_placer_path: NodePath
@export var road_placer_path: NodePath
@export var field_placer_path: NodePath
@export var demolisher_path: NodePath

var _building_placer: Node3D
var _road_placer: Node3D
var _field_placer: Node3D
var _demolisher: Node3D
var _visible: bool = false


func _ready() -> void:
	_building_placer = get_node(building_placer_path)
	_road_placer = get_node(road_placer_path)
	_field_placer = get_node(field_placer_path)
	_demolisher = get_node(demolisher_path)
	_build_buttons()
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_B:
		_visible = !_visible
		visible = _visible
		get_viewport().set_input_as_handled()


func _build_buttons() -> void:
	var vbox := VBoxContainer.new()
	vbox.position = Vector2(10, 10)

	var label := Label.new()
	label.text = "Build Menu [B]"
	label.add_theme_font_size_override("font_size", 28)
	vbox.add_child(label)

	# Buildings section
	var buildings_label := Label.new()
	buildings_label.text = "-- Buildings --"
	buildings_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(buildings_label)

	for key in _building_placer.get_building_keys():
		var btn := Button.new()
		btn.text = key.capitalize()
		btn.custom_minimum_size = Vector2(200, 45)
		btn.add_theme_font_size_override("font_size", 20)
		btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		btn.pressed.connect(_on_building_selected.bind(key))
		vbox.add_child(btn)

	# Fields section
	var fields_label := Label.new()
	fields_label.text = "-- Fields --"
	fields_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(fields_label)

	var field_btn := Button.new()
	field_btn.text = "Crop Field"
	field_btn.custom_minimum_size = Vector2(200, 45)
	field_btn.add_theme_font_size_override("font_size", 20)
	field_btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	field_btn.pressed.connect(_on_field_selected)
	vbox.add_child(field_btn)

	# Roads section
	var roads_label := Label.new()
	roads_label.text = "-- Roads --"
	roads_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(roads_label)

	for key in _road_placer.get_road_keys():
		var btn := Button.new()
		btn.text = key.capitalize()
		btn.custom_minimum_size = Vector2(200, 45)
		btn.add_theme_font_size_override("font_size", 20)
		btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		btn.pressed.connect(_on_road_selected.bind(key))
		vbox.add_child(btn)

	# Demolish section
	var demolish_label := Label.new()
	demolish_label.text = "-- Actions --"
	demolish_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(demolish_label)

	var demolish_btn := Button.new()
	demolish_btn.text = "Demolish"
	demolish_btn.custom_minimum_size = Vector2(200, 45)
	demolish_btn.add_theme_font_size_override("font_size", 20)
	demolish_btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	demolish_btn.pressed.connect(_on_demolish_selected)
	vbox.add_child(demolish_btn)

	add_child(vbox)


func _cancel_all() -> void:
	_building_placer.cancel_placement()
	_road_placer.cancel_placement()
	_field_placer.cancel_placement()
	_demolisher.cancel()


func _on_demolish_selected() -> void:
	_cancel_all()
	_demolisher.start()
	_visible = false
	visible = false


func _on_field_selected() -> void:
	_cancel_all()
	_field_placer.start_placement()
	_visible = false
	visible = false


func _on_building_selected(key: String) -> void:
	_cancel_all()
	_building_placer.start_placement(key)
	_visible = false
	visible = false


func _on_road_selected(key: String) -> void:
	_cancel_all()
	_road_placer.start_placement(key)
	_visible = false
	visible = false
