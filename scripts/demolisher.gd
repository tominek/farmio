extends Node3D

## Handles demolishing buildings, fields, and roads.
## Press Delete key or select from build menu to enter demolish mode.
## Click on a structure to remove it and free the tiles.

var _is_active: bool = false
var _highlight: MeshInstance3D = null
var _highlight_material: StandardMaterial3D
var _current_tile: Vector2i = Vector2i.ZERO
var _has_target: bool = false


func _ready() -> void:
	_highlight_material = StandardMaterial3D.new()
	_highlight_material.albedo_color = Color(1, 0.15, 0.15, 0.6)
	_highlight_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_highlight_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_highlight_material.no_depth_test = true

	_create_highlight()


func _process(_delta: float) -> void:
	if not _is_active:
		return

	var mouse_pos = _get_mouse_world_position()
	if mouse_pos == null:
		_highlight.visible = false
		_has_target = false
		return

	var tile := GridManager.world_to_tile(mouse_pos)
	var data := GridManager.get_tile(tile)

	if data.is_empty():
		_highlight.visible = false
		_has_target = false
		return

	var state: int = data["state"] as int
	if state == GridManager.TileState.EMPTY:
		_highlight.visible = false
		_has_target = false
		return

	_current_tile = tile
	_has_target = true

	# Highlight the entire structure, not just the hovered tile
	var ref: Node = data["ref"]
	if ref and ref.has_meta("field_origin"):
		# Field — highlight the full field area including fence border
		var origin: Vector2i = ref.get_meta("field_origin") as Vector2i
		var size: Vector2i = ref.get_meta("field_size") as Vector2i
		var total_origin := Vector2i(origin.x - 1, origin.y - 1)
		var total_size := Vector2i(size.x + 2, size.y + 2)
		_resize_highlight(total_size)
		var center := GridManager.tile_to_world(total_origin) + Vector3(
			(total_size.x - 1) * 3.0 * 0.5, 0.1,
			(total_size.y - 1) * 3.0 * 0.5
		)
		_highlight.position = center
	elif ref and ref.has_meta("building_origin"):
		# Building
		var origin: Vector2i = ref.get_meta("building_origin") as Vector2i
		var size: Vector2i = ref.get_meta("building_size") as Vector2i
		_resize_highlight(size)
		var center := GridManager.tile_to_world(origin) + Vector3(
			(size.x - 1) * 3.0 * 0.5, 0.1,
			(size.y - 1) * 3.0 * 0.5
		)
		_highlight.position = center
	else:
		# Single tile (road, tree, etc.)
		_resize_highlight(Vector2i(1, 1))
		_highlight.position = GridManager.tile_to_world(tile)
		_highlight.position.y = 0.1

	_highlight.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if not _is_active:
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and _has_target:
			_demolish_at(_current_tile)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cancel()
			get_viewport().set_input_as_handled()

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel()
		get_viewport().set_input_as_handled()


func start() -> void:
	_is_active = true


func cancel() -> void:
	_is_active = false
	_highlight.visible = false
	_has_target = false


func is_active() -> bool:
	return _is_active


func _demolish_at(tile: Vector2i) -> void:
	var data := GridManager.get_tile(tile)
	if data.is_empty():
		return

	var state: int = data["state"] as int
	var ref: Node = data["ref"]

	match state:
		GridManager.TileState.ROAD:
			_demolish_single_tile(tile, ref)

		GridManager.TileState.NATURAL_OBJECT:
			_demolish_single_tile(tile, ref)

		GridManager.TileState.FIELD, GridManager.TileState.FENCE:
			_demolish_field(ref)

		GridManager.TileState.BUILDING:
			_demolish_building(ref)


func _demolish_single_tile(tile: Vector2i, ref: Node) -> void:
	if ref:
		ref.queue_free()
	GridManager.clear_tile(tile)


func _demolish_field(ref: Node) -> void:
	if not ref or not ref.has_meta("field_origin"):
		return

	var origin: Vector2i = ref.get_meta("field_origin") as Vector2i
	var size: Vector2i = ref.get_meta("field_size") as Vector2i
	var total_origin := Vector2i(origin.x - 1, origin.y - 1)
	var total_size := Vector2i(size.x + 2, size.y + 2)

	# Cancel all tasks for this field
	TaskQueue.remove_tasks_for_building(ref)

	# Clear all tiles (crop area + fence border)
	GridManager.clear_area(total_origin, total_size)

	# Also clear the entrance tile if it exists
	if ref.has_meta("entrance_tile"):
		var entrance: Vector2i = ref.get_meta("entrance_tile") as Vector2i
		GridManager.clear_tile(entrance)

	ref.queue_free()


func _demolish_building(ref: Node) -> void:
	if not ref or not ref.has_meta("building_origin"):
		return

	var origin: Vector2i = ref.get_meta("building_origin") as Vector2i
	var size: Vector2i = ref.get_meta("building_size") as Vector2i

	TaskQueue.remove_tasks_for_building(ref)
	GridManager.clear_area(origin, size)
	ref.queue_free()


func _create_highlight() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(3.0, 0.1, 3.0)

	_highlight = MeshInstance3D.new()
	_highlight.mesh = mesh
	_highlight.material_override = _highlight_material
	_highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_highlight.visible = false
	add_child(_highlight)


func _resize_highlight(size_tiles: Vector2i) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size_tiles.x * 3.0, 0.1, size_tiles.y * 3.0)
	_highlight.mesh = mesh


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
