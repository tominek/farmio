extends Control

## In-game pause menu. Press Escape when no other action is active.

var _panel: PanelContainer
var _is_open: bool = false
var _prev_time_scale: float = 1.0


func _ready() -> void:
	visible = false
	_build_menu()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _is_open:
			_close()
		else:
			_open()
		get_viewport().set_input_as_handled()


func _open() -> void:
	_is_open = true
	visible = true
	_prev_time_scale = Engine.time_scale
	Engine.time_scale = 0


func _close() -> void:
	_is_open = false
	visible = false
	Engine.time_scale = _prev_time_scale


func _build_menu() -> void:
	# Dim background
	var dimmer := ColorRect.new()
	dimmer.color = Color(0, 0, 0, 0.5)
	dimmer.set_anchors_preset(PRESET_FULL_RECT)
	add_child(dimmer)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(PRESET_CENTER)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.15, 0.95)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(30)
	_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	vbox.custom_minimum_size = Vector2(300, 0)
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer)

	_add_button(vbox, "Resume", _close)
	_add_button(vbox, "Main Menu", _main_menu)
	_add_button(vbox, "Quit", _quit)

	add_child(_panel)


func _add_button(parent: Node, text: String, callback: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(300, 55)
	btn.add_theme_font_size_override("font_size", 24)
	btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	btn.pressed.connect(callback)
	parent.add_child(btn)


func _main_menu() -> void:
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _quit() -> void:
	get_tree().quit()
