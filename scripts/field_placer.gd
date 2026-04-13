extends Node3D

## Handles field placement on the grid.
## Phase 1: Click to set first corner of crop area.
## Phase 2: Drag to set field size, click to confirm.
## Phase 3: Click outside the field edge to place the gate.
##
## The field has a 1-tile fence border around the crop area.
## A 4x4 crop area has a 6x6 total footprint.
## Workers pathfind through the gate naturally.

const TILE_SIZE: float = 3.0
const MIN_CROP_SIZE: int = 4
const MAX_CROP_SIZE: int = 16

signal field_placed(origin: Vector2i, size: Vector2i)

enum Phase { NONE, PLACE_CORNER, DRAW_SIZE, PLACE_GATE }

var _phase: int = Phase.NONE
var _start_tile: Vector2i = Vector2i.ZERO

var _preview_nodes: Array[Node3D] = []
var _crop_size: Vector2i = Vector2i.ZERO  # inner crop area
var _crop_origin: Vector2i = Vector2i.ZERO  # inner crop area origin
var _total_origin: Vector2i = Vector2i.ZERO  # including fence border
var _total_size: Vector2i = Vector2i.ZERO  # including fence border

# Phase 3: gate placement
var _field_node: Node3D = null
var _gate_candidates: Array[Vector2i] = []  # outer tiles where gate can go
var _gate_ghost: MeshInstance3D = null

var _cursor_ghost: MeshInstance3D = null
var _size_label: Label = null

var _valid_material: StandardMaterial3D
var _invalid_material: StandardMaterial3D
var _fence_material_preview: StandardMaterial3D
var _gate_material: StandardMaterial3D

var _soil_scene: PackedScene = preload("res://assets/fields/soil/bare_soil.tscn")
var _fence_segment_scene: PackedScene = preload("res://assets/fields/fences/fence_segment.tscn")
var _fence_corner_scene: PackedScene = preload("res://assets/fields/fences/fence_corner.tscn")
var _fence_gate_scene: PackedScene = preload("res://assets/fields/fences/fence_gate.tscn")

@onready var _fields_container: Node3D = _get_or_create_fields_container()


func _ready() -> void:
	_valid_material = StandardMaterial3D.new()
	_valid_material.albedo_color = Color(0.5, 1, 0.5, 0.5)
	_valid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_valid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_invalid_material = StandardMaterial3D.new()
	_invalid_material.albedo_color = Color(1, 0.3, 0.3, 0.4)
	_invalid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_invalid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_fence_material_preview = StandardMaterial3D.new()
	_fence_material_preview.albedo_color = Color(0.42, 0.26, 0.15, 0.3)
	_fence_material_preview.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fence_material_preview.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_gate_material = StandardMaterial3D.new()
	_gate_material.albedo_color = Color(1, 0.85, 0, 0.7)
	_gate_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_gate_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_create_cursor_ghost()
	_create_gate_ghost()
	_create_size_label()


func _process(_delta: float) -> void:
	if _phase == Phase.NONE:
		return

	var mouse_pos = _get_mouse_world_position()
	if mouse_pos == null:
		return

	var cursor_tile := GridManager.world_to_tile(mouse_pos)

	if _phase == Phase.PLACE_CORNER:
		_cursor_ghost.position = GridManager.tile_to_world(cursor_tile)
		_cursor_ghost.position.y = 0.04
		_cursor_ghost.visible = true
		_gate_ghost.visible = false
		_size_label.visible = false

	elif _phase == Phase.DRAW_SIZE:
		_cursor_ghost.visible = false
		_gate_ghost.visible = false
		_update_size_preview(cursor_tile)

	elif _phase == Phase.PLACE_GATE:
		_cursor_ghost.visible = false
		_size_label.visible = false
		if cursor_tile in _gate_candidates:
			_gate_ghost.position = GridManager.tile_to_world(cursor_tile)
			_gate_ghost.position.y = 0.06
			_gate_ghost.visible = true
		else:
			_gate_ghost.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if _phase == Phase.NONE:
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel_placement()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _phase == Phase.PLACE_CORNER:
				var mouse_pos = _get_mouse_world_position()
				if mouse_pos == null:
					return
				_start_tile = GridManager.world_to_tile(mouse_pos)
				_phase = Phase.DRAW_SIZE

			elif _phase == Phase.DRAW_SIZE:
				if _is_valid_placement():
					_confirm_field()

			elif _phase == Phase.PLACE_GATE:
				var mouse_pos = _get_mouse_world_position()
				if mouse_pos == null:
					return
				var tile := GridManager.world_to_tile(mouse_pos)
				if tile in _gate_candidates:
					_place_gate(tile)

			get_viewport().set_input_as_handled()

		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if _phase == Phase.DRAW_SIZE:
				_phase = Phase.PLACE_CORNER
				_clear_preview()
				_size_label.visible = false
			elif _phase == Phase.PLACE_GATE:
				if _field_node:
					_field_node.queue_free()
					GridManager.clear_area(_total_origin, _total_size)
				_phase = Phase.PLACE_CORNER
				_gate_ghost.visible = false
				_gate_candidates.clear()
			else:
				cancel_placement()
			get_viewport().set_input_as_handled()


func resume_gate_placement(field: Node3D) -> void:
	cancel_placement()
	_field_node = field
	_crop_origin = field.get_meta("field_origin") as Vector2i
	_crop_size = field.get_meta("field_size") as Vector2i
	_total_origin = Vector2i(_crop_origin.x - 1, _crop_origin.y - 1)
	_total_size = Vector2i(_crop_size.x + 2, _crop_size.y + 2)
	_build_gate_candidates()
	_phase = Phase.PLACE_GATE


func start_placement() -> void:
	cancel_placement()
	_phase = Phase.PLACE_CORNER

	var grid_visual := get_node_or_null("../GridVisual")
	if grid_visual:
		grid_visual.show_grid()


func cancel_placement() -> void:
	_phase = Phase.NONE
	_clear_preview()
	_cursor_ghost.visible = false
	_gate_ghost.visible = false
	_size_label.visible = false
	_gate_candidates.clear()
	_field_node = null


func _update_size_preview(cursor_tile: Vector2i) -> void:
	_clear_preview()

	# Click positions define the total footprint (fence included)
	var min_x: int = mini(_start_tile.x, cursor_tile.x)
	var min_y: int = mini(_start_tile.y, cursor_tile.y)
	var max_x: int = maxi(_start_tile.x, cursor_tile.x)
	var max_y: int = maxi(_start_tile.y, cursor_tile.y)

	_total_origin = Vector2i(min_x, min_y)
	_total_size = Vector2i(max_x - min_x + 1, max_y - min_y + 1)

	# Crop area is inset by 1 tile (fence border)
	_crop_origin = Vector2i(min_x + 1, min_y + 1)
	_crop_size = Vector2i(_total_size.x - 2, _total_size.y - 2)

	var is_valid := _is_valid_placement()
	var mat := _valid_material if is_valid else _invalid_material

	# Preview crop tiles
	for x in range(_crop_origin.x, _crop_origin.x + _crop_size.x):
		for y in range(_crop_origin.y, _crop_origin.y + _crop_size.y):
			var node := _create_preview_tile(Vector2i(x, y), mat)
			_preview_nodes.append(node)

	# Preview fence border
	for x in range(_total_origin.x, _total_origin.x + _total_size.x):
		for y in range(_total_origin.y, _total_origin.y + _total_size.y):
			# Skip inner crop area
			if x >= _crop_origin.x and x < _crop_origin.x + _crop_size.x \
				and y >= _crop_origin.y and y < _crop_origin.y + _crop_size.y:
				continue
			var node := _create_preview_tile(Vector2i(x, y), _fence_material_preview)
			_preview_nodes.append(node)

	var crop_w: int = maxi(_crop_size.x, 0)
	var crop_h: int = maxi(_crop_size.y, 0)
	_size_label.text = "%d x %d (crop: %d x %d)" % [_total_size.x, _total_size.y, crop_w, crop_h]
	if not is_valid:
		if crop_w < MIN_CROP_SIZE or crop_h < MIN_CROP_SIZE:
			_size_label.text += "  (min crop %dx%d)" % [MIN_CROP_SIZE, MIN_CROP_SIZE]
		elif crop_w > MAX_CROP_SIZE or crop_h > MAX_CROP_SIZE:
			_size_label.text += "  (max crop %dx%d)" % [MAX_CROP_SIZE, MAX_CROP_SIZE]
		else:
			_size_label.text += "  (blocked)"
	_size_label.visible = true


func _is_valid_placement() -> bool:
	if _crop_size.x < MIN_CROP_SIZE or _crop_size.y < MIN_CROP_SIZE:
		return false
	if _crop_size.x > MAX_CROP_SIZE or _crop_size.y > MAX_CROP_SIZE:
		return false
	if _total_size.x < 3 or _total_size.y < 3:
		return false
	return _is_area_buildable(_total_origin, _total_size)


func _is_area_buildable(origin: Vector2i, size: Vector2i) -> bool:
	for x in range(origin.x, origin.x + size.x):
		for y in range(origin.y, origin.y + size.y):
			var tile := Vector2i(x, y)
			if GridManager.is_tile_empty(tile):
				continue
			var data: Dictionary = GridManager.get_tile(tile)
			if data.has("state") and int(data["state"]) == GridManager.TileState.NATURAL_OBJECT:
				continue
			return false
	return true


func _confirm_field() -> void:
	_clear_preview()
	_size_label.visible = false

	var field_script: GDScript = preload("res://scripts/field.gd")
	_field_node = Node3D.new()
	_field_node.name = "Field"
	_field_node.set_script(field_script)
	_field_node.set_meta("field_origin", _crop_origin)
	_field_node.set_meta("field_size", _crop_size)
	_fields_container.add_child(_field_node)

	# Place soil tiles on inner crop area
	for x in range(_crop_origin.x, _crop_origin.x + _crop_size.x):
		for y in range(_crop_origin.y, _crop_origin.y + _crop_size.y):
			var tile := Vector2i(x, y)
			var soil := _soil_scene.instantiate()
			soil.position = GridManager.tile_to_world(tile)
			_field_node.add_child(soil)
			_field_node._tile_visuals[tile] = soil

	# Check if trees need clearing first
	if _has_trees_in_area(_total_origin, _total_size):
		_start_field_construction()
		return

	# Push any workers out of the field area before registering tiles
	_push_workers_out()

	# Register inner tiles as FIELD (walkable)
	GridManager.set_area(_crop_origin, _crop_size, GridManager.TileState.FIELD, _field_node)

	# Register fence border tiles as FENCE (non-walkable)
	_register_fence_tiles()

	# Place fence visuals
	_place_fences(_field_node)

	# Build gate candidate list (fence border tiles, excluding corners)
	_build_gate_candidates()

	_phase = Phase.PLACE_GATE


func _has_trees_in_area(origin: Vector2i, size: Vector2i) -> bool:
	for x in range(origin.x, origin.x + size.x):
		for y in range(origin.y, origin.y + size.y):
			var tile := Vector2i(x, y)
			var data: Dictionary = GridManager.get_tile(tile)
			if data.is_empty():
				continue
			if int(data["state"]) == GridManager.TileState.NATURAL_OBJECT:
				return true
	return false


func _start_field_construction() -> void:
	# Store field data for when construction completes
	var pending_data := {
		"crop_origin": _crop_origin,
		"crop_size": _crop_size,
		"total_origin": _total_origin,
		"total_size": _total_size,
	}

	var construction_script: GDScript = preload("res://scripts/construction_site.gd")
	var site := Node3D.new()
	site.name = "FieldConstructionSite"
	site.set_script(construction_script)
	_fields_container.add_child(site)
	site.setup("field", _crop_origin, _crop_size, 0)
	site.set_meta("pending_field", pending_data)
	site.construction_complete.connect(_on_field_construction_complete.bind(site))

	_field_node = null
	_phase = Phase.PLACE_CORNER


func _on_field_construction_complete(_key: String, _origin: Vector2i, _rot: int, site: Node3D) -> void:
	if not site.has_meta("pending_field"):
		return

	var data: Dictionary = site.get_meta("pending_field") as Dictionary
	_crop_origin = data["crop_origin"] as Vector2i
	_crop_size = data["crop_size"] as Vector2i
	_total_origin = data["total_origin"] as Vector2i
	_total_size = data["total_size"] as Vector2i

	# Now build the actual field
	var field_script: GDScript = preload("res://scripts/field.gd")
	_field_node = Node3D.new()
	_field_node.name = "Field"
	_field_node.set_script(field_script)
	_field_node.set_meta("field_origin", _crop_origin)
	_field_node.set_meta("field_size", _crop_size)
	_fields_container.add_child(_field_node)

	# Place soil tiles
	for x in range(_crop_origin.x, _crop_origin.x + _crop_size.x):
		for y in range(_crop_origin.y, _crop_origin.y + _crop_size.y):
			var tile := Vector2i(x, y)
			var soil := _soil_scene.instantiate()
			soil.position = GridManager.tile_to_world(tile)
			_field_node.add_child(soil)
			_field_node._tile_visuals[tile] = soil

	_push_workers_out()

	GridManager.set_area(_crop_origin, _crop_size, GridManager.TileState.FIELD, _field_node)
	_register_fence_tiles()
	_place_fences(_field_node)
	_build_gate_candidates()

	# Go to gate placement phase
	_phase = Phase.PLACE_GATE


func _clear_trees_in_area(origin: Vector2i, size: Vector2i) -> void:
	for x in range(origin.x, origin.x + size.x):
		for y in range(origin.y, origin.y + size.y):
			var tile := Vector2i(x, y)
			var data: Dictionary = GridManager.get_tile(tile)
			if data.is_empty():
				continue
			if int(data["state"]) == GridManager.TileState.NATURAL_OBJECT:
				var tree_node: Node = data["ref"]
				if tree_node:
					tree_node.queue_free()
				GridManager.clear_tile(tile)


func _push_workers_out() -> void:
	var worker_manager: Node3D = get_node_or_null("../WorkerManager")
	if not worker_manager:
		return

	# Find a safe empty tile outside the field
	var safe_tile := Vector2i.ZERO
	var found := false
	for radius in range(1, 10):
		for x in range(_total_origin.x - radius, _total_origin.x + _total_size.x + radius):
			for y in [_total_origin.y - radius, _total_origin.y + _total_size.y - 1 + radius]:
				var tile := Vector2i(x, y)
				if GridManager.is_tile_empty(tile):
					safe_tile = tile
					found = true
					break
			if found:
				break
		if not found:
			for y in range(_total_origin.y - radius, _total_origin.y + _total_size.y + radius):
				for x in [_total_origin.x - radius, _total_origin.x + _total_size.x - 1 + radius]:
					var tile := Vector2i(x, y)
					if GridManager.is_tile_empty(tile):
						safe_tile = tile
						found = true
						break
				if found:
					break
		if found:
			break

	for worker in worker_manager.workers:
		var worker_tile: Vector2i = GridManager.world_to_tile(worker.position)
		# Check if worker is inside the total field footprint (crop + fence)
		if worker_tile.x >= _total_origin.x and worker_tile.x < _total_origin.x + _total_size.x \
			and worker_tile.y >= _total_origin.y and worker_tile.y < _total_origin.y + _total_size.y:
			worker.position = GridManager.tile_to_world(safe_tile)
			# Cancel any current task so they re-evaluate
			if worker._current_task != null:
				TaskQueue.cancel_task(worker._current_task)
				worker._current_task = null
				worker.state = worker.WorkerState.IDLE


func _register_fence_tiles() -> void:
	for x in range(_total_origin.x, _total_origin.x + _total_size.x):
		for y in range(_total_origin.y, _total_origin.y + _total_size.y):
			if x >= _crop_origin.x and x < _crop_origin.x + _crop_size.x \
				and y >= _crop_origin.y and y < _crop_origin.y + _crop_size.y:
				continue
			GridManager.set_tile(Vector2i(x, y), GridManager.TileState.FENCE, _field_node)


func _build_gate_candidates() -> void:
	_gate_candidates.clear()
	# Fence border tiles that are on edges (not corners)
	# Top fence row
	for x in range(_crop_origin.x, _crop_origin.x + _crop_size.x):
		_gate_candidates.append(Vector2i(x, _total_origin.y))
	# Bottom fence row
	for x in range(_crop_origin.x, _crop_origin.x + _crop_size.x):
		_gate_candidates.append(Vector2i(x, _total_origin.y + _total_size.y - 1))
	# Left fence column
	for y in range(_crop_origin.y, _crop_origin.y + _crop_size.y):
		_gate_candidates.append(Vector2i(_total_origin.x, y))
	# Right fence column
	for y in range(_crop_origin.y, _crop_origin.y + _crop_size.y):
		_gate_candidates.append(Vector2i(_total_origin.x + _total_size.x - 1, y))


func _place_gate(gate_tile: Vector2i) -> void:
	# Mark gate tile as walkable (remove FENCE state)
	GridManager.clear_tile(gate_tile)

	# Determine which edge the gate is on
	var gate_edge: int = -1
	if gate_tile.y == _total_origin.y:
		gate_edge = 0  # top
	elif gate_tile.y == _total_origin.y + _total_size.y - 1:
		gate_edge = 1  # bottom
	elif gate_tile.x == _total_origin.x:
		gate_edge = 2  # left
	elif gate_tile.x == _total_origin.x + _total_size.x - 1:
		gate_edge = 3  # right

	# Gate position at crop edge (same as fence positions)
	var gate_world := GridManager.tile_to_world(gate_tile)
	var gate_pos := Vector3.ZERO
	match gate_edge:
		0:  # top — gate at top edge of crop area
			gate_pos = Vector3(gate_tile.x * TILE_SIZE, 0, (_crop_origin.y) * TILE_SIZE - TILE_SIZE * 0.5)
		1:  # bottom
			gate_pos = Vector3(gate_tile.x * TILE_SIZE, 0, (_crop_origin.y + _crop_size.y - 1) * TILE_SIZE + TILE_SIZE * 0.5)
		2:  # left
			gate_pos = Vector3((_crop_origin.x) * TILE_SIZE - TILE_SIZE * 0.5, 0, gate_tile.y * TILE_SIZE)
		3:  # right
			gate_pos = Vector3((_crop_origin.x + _crop_size.x - 1) * TILE_SIZE + TILE_SIZE * 0.5, 0, gate_tile.y * TILE_SIZE)

	# Remove fence visual at gate position
	_remove_fence_at(gate_pos, gate_edge)

	# Place gate visual
	var gate := _fence_gate_scene.instantiate()
	gate.position = gate_pos
	match gate_edge:
		2, 3:
			gate.rotation.y = PI / 2.0
	_field_node.add_child(gate)

	# Store entrance and initialize field
	_field_node.set_meta("entrance_tile", gate_tile)
	if _field_node.has_method("initialize_entrance"):
		_field_node.initialize_entrance(gate_tile)

	# Place dirt road on entrance tile
	_place_entrance_road(gate_tile)

	_gate_ghost.visible = false
	_gate_candidates.clear()

	# Show crop selector
	var crop_selector: Control = get_node_or_null("../UI/CropSelector")
	if crop_selector:
		crop_selector.show_for_field(_field_node)

	field_placed.emit(_crop_origin, _crop_size)

	# Exit placement mode after placing (hold Shift to continue)
	if not Input.is_key_pressed(KEY_SHIFT):
		_phase = Phase.NONE
	else:
		_phase = Phase.PLACE_CORNER
	_field_node = null


func _remove_fence_at(fence_pos: Vector3, gate_edge: int) -> void:
	for child in _field_node.get_children():
		var pos: Vector3 = child.position
		if absf(pos.x - fence_pos.x) < 0.1 and absf(pos.z - fence_pos.z) < 0.1:
			if _is_fence_node(child):
				child.queue_free()
				return
				return


func _is_fence_node(node: Node) -> bool:
	for child in node.get_children():
		if child is MeshInstance3D and absf(child.position.y - 0.5) < 0.2:
			return true
	return false


func _place_fences(field: Node3D) -> void:
	# Place fence visuals at the boundary between crop and border tiles
	var cx1: float = (_crop_origin.x) * TILE_SIZE - TILE_SIZE * 0.5  # left edge of crop area
	var cx2: float = (_crop_origin.x + _crop_size.x - 1) * TILE_SIZE + TILE_SIZE * 0.5  # right edge
	var cy1: float = (_crop_origin.y) * TILE_SIZE - TILE_SIZE * 0.5  # top edge
	var cy2: float = (_crop_origin.y + _crop_size.y - 1) * TILE_SIZE + TILE_SIZE * 0.5  # bottom edge

	# Top row
	for x in range(_crop_origin.x, _crop_origin.x + _crop_size.x):
		var fence := _fence_segment_scene.instantiate()
		fence.position = Vector3(x * TILE_SIZE, 0, cy1)
		field.add_child(fence)

	# Bottom row
	for x in range(_crop_origin.x, _crop_origin.x + _crop_size.x):
		var fence := _fence_segment_scene.instantiate()
		fence.position = Vector3(x * TILE_SIZE, 0, cy2)
		field.add_child(fence)

	# Left column
	for y in range(_crop_origin.y, _crop_origin.y + _crop_size.y):
		var fence := _fence_segment_scene.instantiate()
		fence.position = Vector3(cx1, 0, y * TILE_SIZE)
		fence.rotation.y = PI / 2.0
		field.add_child(fence)

	# Right column
	for y in range(_crop_origin.y, _crop_origin.y + _crop_size.y):
		var fence := _fence_segment_scene.instantiate()
		fence.position = Vector3(cx2, 0, y * TILE_SIZE)
		fence.rotation.y = PI / 2.0
		field.add_child(fence)



func _create_preview_tile(tile: Vector2i, mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.9, 0.08, 2.9)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.position = GridManager.tile_to_world(tile)
	node.position.y = 0.05
	add_child(node)
	return node


func _place_entrance_road(tile: Vector2i) -> void:
	if not GridManager.is_tile_empty(tile):
		return
	var road_scene: PackedScene = preload("res://assets/roads/dirt/dirt_road.tscn")
	var road: Node3D = road_scene.instantiate()
	road.position = GridManager.tile_to_world(tile)
	var roads_container: Node3D = get_node_or_null("../WorldGenerator/Roads")
	if roads_container:
		roads_container.add_child(road)
	else:
		add_child(road)
	GridManager.set_tile(tile, GridManager.TileState.ROAD, road)


func _create_cursor_ghost() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.9, 0.06, 2.9)
	_cursor_ghost = MeshInstance3D.new()
	_cursor_ghost.mesh = mesh
	_cursor_ghost.material_override = _valid_material
	_cursor_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cursor_ghost.visible = false
	add_child(_cursor_ghost)


func _create_gate_ghost() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.9, 0.08, 2.9)
	_gate_ghost = MeshInstance3D.new()
	_gate_ghost.mesh = mesh
	_gate_ghost.material_override = _gate_material
	_gate_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gate_ghost.visible = false
	add_child(_gate_ghost)


func _create_size_label() -> void:
	_size_label = Label.new()
	_size_label.add_theme_font_size_override("font_size", 24)
	_size_label.add_theme_color_override("font_color", Color.WHITE)
	_size_label.position = Vector2(10, 10)
	_size_label.visible = false
	call_deferred("_attach_label")


func _attach_label() -> void:
	var ui := get_node_or_null("../UI")
	if ui:
		ui.add_child(_size_label)


func _clear_preview() -> void:
	for node in _preview_nodes:
		node.queue_free()
	_preview_nodes.clear()


func _get_or_create_fields_container() -> Node3D:
	var container := get_node_or_null("../Fields")
	if not container:
		container = Node3D.new()
		container.name = "Fields"
		get_parent().add_child.call_deferred(container)
	return container


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
