extends Node3D

## Handles road placement on the grid.
## Click start point, move mouse to see straight road preview, click to confirm.
## Roads are always straight (horizontal or vertical). Right click to cancel.

const TILE_SIZE: float = 3.0

var _road_defs: Dictionary = {}

var _current_road_key: String = ""
var _is_placing: bool = false
var _has_start: bool = false
var _start_tile: Vector2i = Vector2i.ZERO
var _preview_nodes: Array[MeshInstance3D] = []
var _preview_tiles: Array[Vector2i] = []

var _ghost_material_valid: StandardMaterial3D
var _ghost_material_invalid: StandardMaterial3D
var _can_place: bool = false
var _cursor_ghost: MeshInstance3D = null

@onready var _roads_container: Node3D = _get_or_create_roads_container()


func _ready() -> void:
	_ghost_material_valid = StandardMaterial3D.new()
	_ghost_material_valid.albedo_color = Color(0.5, 1, 0.5, 0.4)
	_ghost_material_valid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material_valid.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_ghost_material_invalid = StandardMaterial3D.new()
	_ghost_material_invalid.albedo_color = Color(1, 0.3, 0.3, 0.4)
	_ghost_material_invalid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material_invalid.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_create_cursor_ghost()
	_register_roads()


func _register_roads() -> void:
	_register("dirt_road", preload("res://assets/roads/dirt/dirt_road.tscn"), 0)
	_register("gravel_road", preload("res://assets/roads/gravel/gravel_road.tscn"), 10)


func _register(key: String, scene: PackedScene, cost: int) -> void:
	_road_defs[key] = { "scene": scene, "cost": cost }


func _process(_delta: float) -> void:
	if not _is_placing:
		return

	var mouse_pos = _get_mouse_world_position()
	if mouse_pos == null:
		return

	var cursor_tile := GridManager.world_to_tile(mouse_pos)

	if _has_start:
		_update_preview(cursor_tile)
		_cursor_ghost.visible = false
	else:
		_cursor_ghost.position = GridManager.tile_to_world(cursor_tile)
		_cursor_ghost.position.y = 0.04
		_cursor_ghost.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if not _is_placing:
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if not _has_start:
				var mouse_pos = _get_mouse_world_position()
				if mouse_pos == null:
					return
				_start_tile = GridManager.world_to_tile(mouse_pos)
				_has_start = true
			elif _can_place:
				_confirm_placement()
			get_viewport().set_input_as_handled()

		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if _has_start:
				_has_start = false
				_clear_preview()
			else:
				cancel_placement()
			get_viewport().set_input_as_handled()

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel_placement()
		get_viewport().set_input_as_handled()


func start_placement(road_key: String) -> void:
	if not _road_defs.has(road_key):
		return

	cancel_placement()
	_current_road_key = road_key
	_is_placing = true

	var grid_visual := get_node_or_null("../GridVisual")
	if grid_visual:
		grid_visual.show_grid()


func cancel_placement() -> void:
	_is_placing = false
	_has_start = false
	_clear_preview()
	_cursor_ghost.visible = false
	_current_road_key = ""


func get_road_keys() -> Array:
	return _road_defs.keys()


func _update_preview(end_tile: Vector2i) -> void:
	_clear_preview()

	# Straight line: pick the axis with the larger delta
	var dx: int = end_tile.x - _start_tile.x
	var dy: int = end_tile.y - _start_tile.y

	_preview_tiles.clear()

	if absi(dx) >= absi(dy):
		# Horizontal road
		var step: int = signi(dx) if dx != 0 else 1
		var x: int = _start_tile.x
		while true:
			_preview_tiles.append(Vector2i(x, _start_tile.y))
			if x == end_tile.x:
				break
			x += step
	else:
		# Vertical road
		var step: int = signi(dy) if dy != 0 else 1
		var y: int = _start_tile.y
		while true:
			_preview_tiles.append(Vector2i(_start_tile.x, y))
			if y == end_tile.y:
				break
			y += step

	# Create preview meshes with per-tile validity check
	_can_place = true
	for tile in _preview_tiles:
		var tile_ok := _is_tile_placeable(tile)
		if not tile_ok:
			_can_place = false

		var mesh := BoxMesh.new()
		mesh.size = Vector3(2.9, 0.06, 2.9)

		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.material_override = _ghost_material_valid if tile_ok else _ghost_material_invalid
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.position = GridManager.tile_to_world(tile)
		node.position.y = 0.04
		add_child(node)
		_preview_nodes.append(node)


func _confirm_placement() -> void:
	var def := _road_defs[_current_road_key] as Dictionary

	for tile in _preview_tiles:
		var data := GridManager.get_tile(tile)

		# Allow placing on empty tiles and overriding existing roads
		if not data.is_empty():
			if data["state"] == GridManager.TileState.ROAD:
				# Remove old road
				var old_road: Node = data["ref"]
				if old_road:
					old_road.queue_free()
				GridManager.clear_tile(tile)
			else:
				# Skip non-road occupied tiles (buildings, trees)
				continue

		var road: Node3D = def["scene"].instantiate()
		road.position = GridManager.tile_to_world(tile)
		_roads_container.add_child(road)
		GridManager.set_tile(tile, GridManager.TileState.ROAD, road)

	_has_start = false
	_clear_preview()


func _is_tile_placeable(tile: Vector2i) -> bool:
	var data := GridManager.get_tile(tile)
	if data.is_empty():
		return true  # empty grass
	var state: int = data["state"] as int
	return state == GridManager.TileState.ROAD  # can only override existing roads


func _clear_preview() -> void:
	for node in _preview_nodes:
		node.queue_free()
	_preview_nodes.clear()
	_preview_tiles.clear()


func _create_cursor_ghost() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.9, 0.06, 2.9)

	_cursor_ghost = MeshInstance3D.new()
	_cursor_ghost.mesh = mesh
	_cursor_ghost.material_override = _ghost_material_valid
	_cursor_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cursor_ghost.visible = false
	add_child(_cursor_ghost)


func _get_or_create_roads_container() -> Node3D:
	var container := get_node_or_null("../WorldGenerator/Roads")
	if container:
		return container
	container = Node3D.new()
	container.name = "PlayerRoads"
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
