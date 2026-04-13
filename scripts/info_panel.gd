extends Control

## Info panel that shows details about clicked buildings and fields.
## Click on a building/field to open, click elsewhere or Escape to close.

var _panel: PanelContainer
var _content_vbox: VBoxContainer
var _title_label: Label
var _info_labels: Array[Label] = []
var _selected_node: Node3D = null
var _is_open: bool = false
var _update_timer: float = 0.0


func _ready() -> void:
	visible = false
	_build_panel()


func _process(delta: float) -> void:
	if not _is_open or _selected_node == null:
		return

	_update_timer += delta
	if _update_timer < 0.5:
		return
	_update_timer = 0.0

	_refresh_info()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Check if any placer is active — don't interfere
		var building_placer: Node3D = get_node_or_null("/root/Main/BuildingPlacer")
		var road_placer: Node3D = get_node_or_null("/root/Main/RoadPlacer")
		var field_placer: Node3D = get_node_or_null("/root/Main/FieldPlacer")
		var demolisher: Node3D = get_node_or_null("/root/Main/Demolisher")

		if building_placer and building_placer.get("_is_placing") and building_placer._is_placing:
			return
		if road_placer and road_placer.get("_is_placing") and road_placer._is_placing:
			return
		if field_placer and field_placer.get("_phase") != null and field_placer._phase != 0:
			return
		if demolisher and demolisher.has_method("is_active") and demolisher.is_active():
			return

		var mouse_pos = _get_mouse_world_position()
		if mouse_pos == null:
			return

		var tile: Vector2i = GridManager.world_to_tile(mouse_pos)
		var data: Dictionary = GridManager.get_tile(tile)

		if data.is_empty():
			_close()
			return

		var state: int = int(data["state"])
		var ref: Node = data["ref"]

		if ref and (state == GridManager.TileState.BUILDING or state == GridManager.TileState.FIELD \
			or state == GridManager.TileState.FENCE):
			_open(ref as Node3D)
			get_viewport().set_input_as_handled()
		else:
			_close()


func _build_panel() -> void:
	_panel = PanelContainer.new()

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.12, 0.92)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(20)
	_panel.add_theme_stylebox_override("panel", style)

	_content_vbox = VBoxContainer.new()
	_content_vbox.add_theme_constant_override("separation", 10)
	_content_vbox.custom_minimum_size = Vector2(340, 0)
	_panel.add_child(_content_vbox)

	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.add_theme_font_size_override("font_size", 28)
	_content_vbox.add_child(_title_label)

	# Action button (reusable for different actions)
	var _action_btn := Button.new()
	_action_btn.name = "ActionButton"
	_action_btn.custom_minimum_size = Vector2(0, 45)
	_action_btn.add_theme_font_size_override("font_size", 22)
	_action_btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_action_btn.visible = false
	_content_vbox.add_child(_action_btn)

	# Close button
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(0, 40)
	close_btn.add_theme_font_size_override("font_size", 22)
	close_btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	close_btn.pressed.connect(_close)
	_content_vbox.add_child(close_btn)

	add_child(_panel)


func _open(node: Node3D) -> void:
	_selected_node = node
	_is_open = true
	visible = true
	_update_timer = 0.0
	_refresh_info()
	_position_near_building()


func _position_near_building() -> void:
	if _selected_node == null:
		return

	var camera := get_viewport().get_camera_3d()
	if not camera:
		return

	# Calculate world center of the building/field
	var world_pos: Vector3
	if _selected_node.has_meta("field_origin") and _selected_node.has_meta("field_size"):
		var origin: Vector2i = _selected_node.get_meta("field_origin") as Vector2i
		var size: Vector2i = _selected_node.get_meta("field_size") as Vector2i
		var center_tile := Vector2i(origin.x + size.x / 2, origin.y + size.y / 2)
		world_pos = GridManager.tile_to_world(center_tile)
	elif _selected_node.has_meta("building_origin") and _selected_node.has_meta("building_size"):
		var origin: Vector2i = _selected_node.get_meta("building_origin") as Vector2i
		var size: Vector2i = _selected_node.get_meta("building_size") as Vector2i
		var center_tile := Vector2i(origin.x + size.x / 2, origin.y + size.y / 2)
		world_pos = GridManager.tile_to_world(center_tile)
	else:
		world_pos = _selected_node.global_position
	world_pos.y += 3.0
	var screen_pos: Vector2 = camera.unproject_position(world_pos)

	# Offset panel to the right of the click point
	var panel_size: Vector2 = _panel.size if _panel.size.x > 0 else Vector2(380, 300)
	var viewport_size: Vector2 = get_viewport_rect().size

	# Position to the right, or left if not enough space
	var pos := Vector2(screen_pos.x + 20, screen_pos.y - panel_size.y * 0.5)

	# Keep on screen
	if pos.x + panel_size.x > viewport_size.x:
		pos.x = screen_pos.x - panel_size.x - 20
	pos.y = clampf(pos.y, 80, viewport_size.y - panel_size.y - 10)

	_panel.position = pos


func _close() -> void:
	_selected_node = null
	_is_open = false
	visible = false


func _refresh_info() -> void:
	if _selected_node == null:
		return

	# Remove old dynamic labels
	for label in _info_labels:
		label.queue_free()
	_info_labels.clear()

	var line := 0

	# Determine type
	var action_btn: Button = _content_vbox.get_node("ActionButton") as Button
	action_btn.visible = false
	# Disconnect any previous signals
	if action_btn.pressed.is_connected(_on_place_gate):
		action_btn.pressed.disconnect(_on_place_gate)

	if _selected_node.has_method("get_phase_name"):
		# It's a field
		_title_label.text = _get_field_title()

		# Check for missing gate
		if not _selected_node.has_meta("entrance_tile"):
			_set_line(line, "WARNING: No gate placed!"); line += 1
			_set_line(line, "Workers cannot enter this field."); line += 1
			action_btn.text = "Place Gate"
			action_btn.visible = true
			action_btn.pressed.connect(_on_place_gate)
		else:
			_set_line(line, "Phase: %s" % _selected_node.get_phase_name()); line += 1

		_set_line(line, "Size: %d x %d tiles" % [_selected_node.field_size.x, _selected_node.field_size.y]); line += 1

		var total_tiles: int = _selected_node.field_size.x * _selected_node.field_size.y
		_set_line(line, "Total tiles: %d" % total_tiles); line += 1

		if _selected_node.crop_type >= 0:
			var yield_per_tile: int = _selected_node._get_param("yield") as int
			_set_line(line, "Yield: %d kg/tile (%d kg total)" % [yield_per_tile, yield_per_tile * total_tiles]); line += 1

			var speed: float = _selected_node._get_param("speed") as float
			_set_line(line, "Growth time: ~%s" % Utils.format_time(int(1.0 / speed))); line += 1
		elif not _selected_node.has_meta("entrance_tile"):
			pass  # no crop info without gate
		else:
			_set_line(line, "No crop selected"); line += 1

	elif _selected_node.has_method("get_inventory"):
		# It's a barn
		_title_label.text = "Storage Barn"
		var inventory: Dictionary = _selected_node.get_inventory()
		if inventory.is_empty():
			_set_line(line, "Empty"); line += 1
		else:
			for res_type in inventory:
				var amount: int = inventory[res_type] as int
				var res_name: String = ResourceManager.resource_name(res_type as int)
				_set_line(line, "%s: %s" % [res_name, Utils.format_weight(amount)]); line += 1

	else:
		# Generic building
		_title_label.text = _get_building_name()
		if _selected_node.has_meta("building_size"):
			var size: Vector2i = _selected_node.get_meta("building_size") as Vector2i
			_set_line(line, "Size: %d x %d tiles" % [size.x, size.y]); line += 1


func _set_line(_index: int, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 22)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	# Insert before action button and close button
	var insert_pos: int = _title_label.get_index() + 1 + _info_labels.size()
	_content_vbox.add_child(label)
	_content_vbox.move_child(label, insert_pos)
	_info_labels.append(label)


func _on_place_gate() -> void:
	if _selected_node == null:
		return

	var field_placer: Node3D = get_node_or_null("/root/Main/FieldPlacer")
	if field_placer and field_placer.has_method("resume_gate_placement"):
		field_placer.resume_gate_placement(_selected_node)
		_close()


func _get_field_title() -> String:
	if _selected_node.crop_type >= 0:
		return "%s Field" % ResourceManager.resource_name(_selected_node.crop_type)
	return "Field (no crop)"


func _get_building_name() -> String:
	var node_name: String = _selected_node.name
	if "Barn" in node_name:
		return "Storage Barn"
	elif "Garage" in node_name:
		return "Garage"
	elif "Mill" in node_name:
		return "Hand Mill"
	elif "Sawmill" in node_name:
		return "Sawmill"
	elif "Dealer" in node_name:
		return "Dealer"
	elif "Pickup" in node_name:
		return "Pickup Point"
	return node_name


func _get_mouse_world_position() -> Variant:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return null
	var mouse_pos := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse_pos)
	var dir := camera.project_ray_normal(mouse_pos)
	if abs(dir.y) < 0.001:
		return null
	var t := -from.y / dir.y
	return from + dir * t
