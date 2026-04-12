extends Control

## Crop selection panel. Appears when a field needs a crop assigned.
## Click a crop button to assign it and start the field cycle.

signal crop_selected(crop_type: int, field: Node3D)

var _panel: PanelContainer
var _active_field: Node3D = null


func _ready() -> void:
	visible = false
	_build_panel()


func show_for_field(field: Node3D) -> void:
	_active_field = field
	visible = true

	# Position panel at center of screen
	_panel.position = Vector2(
		get_viewport_rect().size.x / 2.0 - 175,
		get_viewport_rect().size.y / 2.0 - 150
	)


func hide_panel() -> void:
	_active_field = null
	visible = false


func _build_panel() -> void:
	_panel = PanelContainer.new()

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.12, 0.95)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(20)
	_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.custom_minimum_size = Vector2(350, 0)
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "Select Crop"
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var crops := [
		["Potatoes", ResourceManager.ResourceType.POTATOES, Color(0.65, 0.55, 0.35)],
		["Wheat", ResourceManager.ResourceType.WHEAT, Color(0.85, 0.75, 0.25)],
		["Corn", ResourceManager.ResourceType.CORN, Color(0.9, 0.8, 0.2)],
		["Sugar Beet", ResourceManager.ResourceType.SUGAR_BEET, Color(0.55, 0.23, 0.38)],
	]

	for crop_data in crops:
		var crop_name: String = crop_data[0]
		var crop_type: int = crop_data[1]
		var crop_color: Color = crop_data[2]

		var btn := Button.new()
		btn.text = crop_name
		btn.custom_minimum_size = Vector2(350, 50)
		btn.add_theme_font_size_override("font_size", 24)
		btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		btn.pressed.connect(_on_crop_selected.bind(crop_type))

		# Color indicator
		var color_rect := ColorRect.new()
		color_rect.color = crop_color
		color_rect.custom_minimum_size = Vector2(20, 20)

		vbox.add_child(btn)

	# Cancel button
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(350, 45)
	cancel.add_theme_font_size_override("font_size", 22)
	cancel.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	cancel.pressed.connect(hide_panel)
	vbox.add_child(cancel)

	add_child(_panel)


func _on_crop_selected(crop_type: int) -> void:
	if _active_field:
		crop_selected.emit(crop_type, _active_field)
	hide_panel()
