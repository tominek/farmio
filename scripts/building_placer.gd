extends Node3D

## Handles building placement on the grid.
## Player selects a building from the menu, sees a ghost preview,
## clicks to place, R to rotate.

signal building_placed(building: Node3D, tile_pos: Vector2i)

const TILE_SIZE: float = 3.0

# Building definitions: name -> { scene, size_tiles }
var _building_defs: Dictionary = {}

var _current_building_key: String = ""
var _ghost: Node3D = null
var _ghost_material: StandardMaterial3D
var _rotation_index: int = 0  # 0=0°, 1=90°, 2=180°, 3=270°
var _is_placing: bool = false
var _can_place: bool = false
var _entrance_marker: MeshInstance3D = null
var _border_preview: Array[MeshInstance3D] = []
var _border_material: StandardMaterial3D
var _last_ghost_tile: Vector2i = Vector2i(-9999, -9999)

@onready var _buildings_container: Node3D = $"../Buildings"


func _ready() -> void:
	# Ghost material (semi-transparent)
	_ghost_material = StandardMaterial3D.new()
	_ghost_material.albedo_color = Color(1, 1, 1, 0.5)
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_border_material = StandardMaterial3D.new()
	_border_material.albedo_color = Color(0.4, 0.4, 0.4, 0.25)
	_border_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_border_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_create_entrance_marker()
	_register_buildings()


var _building_scripts: Dictionary = {
	"barn": preload("res://scripts/barn.gd"),
}


func _register_buildings() -> void:
	# entrance_offset is relative to building origin: where the door tile is (just outside the building)
	_register("barn", preload("res://assets/buildings/storage/barn.tscn"), Vector2i(4, 3), Vector2i(2, 3))
	_register("garage", preload("res://assets/buildings/storage/garage.tscn"), Vector2i(5, 4), Vector2i(2, 4))
	_register("hand_mill", preload("res://assets/buildings/processing/hand_mill.tscn"), Vector2i(2, 2), Vector2i(1, 2))
	_register("sawmill", preload("res://assets/buildings/processing/sawmill.tscn"), Vector2i(3, 2), Vector2i(1, 2))
	_register("dealer", preload("res://assets/buildings/special/dealer.tscn"), Vector2i(4, 3), Vector2i(2, 3))


func _register(key: String, scene: PackedScene, size_tiles: Vector2i, entrance: Vector2i) -> void:
	_building_defs[key] = { "scene": scene, "size": size_tiles, "entrance": entrance }


func _process(_delta: float) -> void:
	if not _is_placing:
		return

	_update_ghost_position()


func _unhandled_input(event: InputEvent) -> void:
	if not _is_placing:
		return

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R:
			_rotation_index = (_rotation_index + 1) % 4
			_update_ghost_rotation()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			cancel_placement()
			get_viewport().set_input_as_handled()

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and _can_place:
			_place_building()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cancel_placement()
			get_viewport().set_input_as_handled()


## Start placing a building by key name
func start_placement(building_key: String) -> void:
	if not _building_defs.has(building_key):
		push_warning("Unknown building: " + building_key)
		return

	cancel_placement()

	_current_building_key = building_key
	_rotation_index = 0
	_is_placing = true

	# Create ghost preview
	var def := _building_defs[_current_building_key] as Dictionary
	_ghost = def["scene"].instantiate()
	_apply_ghost_material(_ghost)
	add_child(_ghost)

	# Show grid during placement
	var grid_visual := get_node_or_null("../GridVisual")
	if grid_visual:
		grid_visual.show_grid()


## Cancel current placement
func cancel_placement() -> void:
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	_entrance_marker.visible = false
	_clear_border_preview()
	_last_ghost_tile = Vector2i(-9999, -9999)
	_is_placing = false
	_current_building_key = ""


## Get available building keys
func get_building_keys() -> Array:
	return _building_defs.keys()


func _create_entrance_marker() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.85, 0, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.9, 0.08, 2.9)
	mesh.material = mat

	_entrance_marker = MeshInstance3D.new()
	_entrance_marker.mesh = mesh
	_entrance_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_entrance_marker.visible = false
	add_child(_entrance_marker)


func _update_ghost_position() -> void:
	var mouse_pos = _get_mouse_world_position()
	if mouse_pos == null:
		return

	var tile_pos := GridManager.world_to_tile(mouse_pos)
	var size := _get_rotated_size()

	# Center the building on the tile grid
	var offset := Vector3(
		(size.x - 1) * TILE_SIZE * 0.5,
		0,
		(size.y - 1) * TILE_SIZE * 0.5
	)
	var world_pos := GridManager.tile_to_world(tile_pos) + offset
	_ghost.position = world_pos

	# Check if placement is valid (allow empty + natural objects, block buildings/roads/fields)
	var border_origin := Vector2i(tile_pos.x - 1, tile_pos.y - 1)
	var border_size := Vector2i(size.x + 2, size.y + 2)
	_can_place = _is_area_buildable(border_origin, border_size)
	_update_ghost_color()

	# Rebuild border preview if tile changed
	if tile_pos != _last_ghost_tile:
		_last_ghost_tile = tile_pos
		_rebuild_border_preview(tile_pos, size)

	# Position entrance marker
	var entrance_tile := _get_rotated_entrance(tile_pos)
	_entrance_marker.position = GridManager.tile_to_world(entrance_tile)
	_entrance_marker.position.y = 0.06
	_entrance_marker.visible = true


func _update_ghost_rotation() -> void:
	if _ghost:
		_ghost.rotation.y = -_rotation_index * PI / 2.0
		_last_ghost_tile = Vector2i(-9999, -9999)  # force border rebuild


func _update_ghost_color() -> void:
	if _can_place:
		_ghost_material.albedo_color = Color(0.5, 1, 0.5, 0.5)  # green = valid
	else:
		_ghost_material.albedo_color = Color(1, 0.3, 0.3, 0.5)  # red = invalid


func _place_building() -> void:
	var def := _building_defs[_current_building_key] as Dictionary
	var size := _get_rotated_size()

	# Get tile position from ghost
	var mouse_pos = _get_mouse_world_position()
	if mouse_pos == null:
		return
	var tile_pos := GridManager.world_to_tile(mouse_pos)

	# Double-check validity
	var border_origin := Vector2i(tile_pos.x - 1, tile_pos.y - 1)
	var border_check := Vector2i(size.x + 2, size.y + 2)
	if not _is_area_buildable(border_origin, border_check):
		return

	# Check if there are trees that need clearing
	if _has_trees_in_area(border_origin, border_check):
		_start_construction_site(tile_pos, size)
		return

	# Instantiate actual building and attach behavior script if available
	var building: Node3D = def["scene"].instantiate()
	if _building_scripts.has(_current_building_key):
		building.set_script(_building_scripts[_current_building_key])
	var offset := Vector3(
		(size.x - 1) * TILE_SIZE * 0.5,
		0,
		(size.y - 1) * TILE_SIZE * 0.5
	)
	building.position = GridManager.tile_to_world(tile_pos) + offset
	building.rotation.y = -_rotation_index * PI / 2.0
	_buildings_container.add_child(building)

	# Register building tiles
	GridManager.set_area(tile_pos, size, GridManager.TileState.BUILDING, building)

	# Register 1-tile border around building
	_register_building_border(tile_pos, size, building)

	# Store entrance tile as metadata
	var entrance_tile := _get_rotated_entrance(tile_pos)
	building.set_meta("entrance_tile", entrance_tile)
	building.set_meta("building_origin", tile_pos)
	building.set_meta("building_size", size)

	# Place dirt road on entrance tile (overrides the border tile)
	_place_entrance_road(entrance_tile)

	_clear_border_preview()
	_last_ghost_tile = Vector2i(-9999, -9999)

	building_placed.emit(building, tile_pos)


func _is_area_buildable(origin: Vector2i, size: Vector2i) -> bool:
	for x in range(origin.x, origin.x + size.x):
		for y in range(origin.y, origin.y + size.y):
			var tile := Vector2i(x, y)
			if GridManager.is_tile_empty(tile):
				continue
			var data: Dictionary = GridManager.get_tile(tile)
			if data.has("state"):
				var state: int = int(data["state"])
				if state == GridManager.TileState.NATURAL_OBJECT:
					continue
			return false
	return true


func _has_trees_in_area(origin: Vector2i, size: Vector2i) -> bool:
	for x in range(origin.x, origin.x + size.x):
		for y in range(origin.y, origin.y + size.y):
			var tile := Vector2i(x, y)
			if GridManager.is_tile_empty(tile):
				continue
			var data: Dictionary = GridManager.get_tile(tile)
			if data.has("state") and int(data["state"]) == GridManager.TileState.NATURAL_OBJECT:
				return true
	return false


func _start_construction_site(tile_pos: Vector2i, size: Vector2i) -> void:
	var construction_script: GDScript = preload("res://scripts/construction_site.gd")
	var site := Node3D.new()
	site.name = "ConstructionSite"
	site.set_script(construction_script)
	_buildings_container.add_child(site)
	site.setup(_current_building_key, tile_pos, size, _rotation_index)
	site.construction_complete.connect(_on_construction_complete)

	_clear_border_preview()
	_last_ghost_tile = Vector2i(-9999, -9999)


func _on_construction_complete(bld_key: String, tile_pos: Vector2i, rot: int) -> void:
	# Save and restore current state
	var saved_key := _current_building_key
	var saved_rotation := _rotation_index

	_current_building_key = bld_key
	_rotation_index = rot

	var def := _building_defs[bld_key] as Dictionary
	var size := def["size"] as Vector2i
	if rot % 2 != 0:
		size = Vector2i(size.y, size.x)

	var building: Node3D = def["scene"].instantiate()
	if _building_scripts.has(bld_key):
		building.set_script(_building_scripts[bld_key])
	var offset := Vector3(
		(size.x - 1) * TILE_SIZE * 0.5,
		0,
		(size.y - 1) * TILE_SIZE * 0.5
	)
	building.position = GridManager.tile_to_world(tile_pos) + offset
	building.rotation.y = -rot * PI / 2.0
	_buildings_container.add_child(building)

	GridManager.set_area(tile_pos, size, GridManager.TileState.BUILDING, building)
	_register_building_border(tile_pos, size, building)

	var entrance_tile := _get_rotated_entrance(tile_pos)
	building.set_meta("entrance_tile", entrance_tile)
	building.set_meta("building_origin", tile_pos)
	building.set_meta("building_size", size)
	_place_entrance_road(entrance_tile)

	_current_building_key = saved_key
	_rotation_index = saved_rotation


func _rebuild_border_preview(tile_pos: Vector2i, size: Vector2i) -> void:
	_clear_border_preview()

	var border_origin := Vector2i(tile_pos.x - 1, tile_pos.y - 1)
	var border_size := Vector2i(size.x + 2, size.y + 2)

	for x in range(border_origin.x, border_origin.x + border_size.x):
		for y in range(border_origin.y, border_origin.y + border_size.y):
			# Skip inner building tiles
			if x >= tile_pos.x and x < tile_pos.x + size.x \
				and y >= tile_pos.y and y < tile_pos.y + size.y:
				continue

			var mesh := BoxMesh.new()
			mesh.size = Vector3(2.9, 0.06, 2.9)

			var node := MeshInstance3D.new()
			node.mesh = mesh
			node.material_override = _border_material
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.position = GridManager.tile_to_world(Vector2i(x, y))
			node.position.y = 0.04
			add_child(node)
			_border_preview.append(node)


func _clear_border_preview() -> void:
	for node in _border_preview:
		node.queue_free()
	_border_preview.clear()


func _register_building_border(origin: Vector2i, size: Vector2i, building: Node3D) -> void:
	var border_origin := Vector2i(origin.x - 1, origin.y - 1)
	var border_size := Vector2i(size.x + 2, size.y + 2)

	for x in range(border_origin.x, border_origin.x + border_size.x):
		for y in range(border_origin.y, border_origin.y + border_size.y):
			# Skip inner building tiles (already registered)
			if x >= origin.x and x < origin.x + size.x \
				and y >= origin.y and y < origin.y + size.y:
				continue
			var tile := Vector2i(x, y)
			# Only register on empty tiles (don't override roads or other buildings)
			if GridManager.is_tile_empty(tile):
				GridManager.set_tile(tile, GridManager.TileState.BUILDING_BORDER, building)


func _place_entrance_road(tile: Vector2i) -> void:
	var data := GridManager.get_tile(tile)
	if not data.is_empty():
		var state: int = data["state"] as int
		if state != GridManager.TileState.BUILDING_BORDER:
			return
		# Clear the border tile to place road instead
		GridManager.clear_tile(tile)
	var road_scene: PackedScene = preload("res://assets/roads/dirt/dirt_road.tscn")
	var road: Node3D = road_scene.instantiate()
	road.position = GridManager.tile_to_world(tile)
	_buildings_container.add_child(road)
	GridManager.set_tile(tile, GridManager.TileState.ROAD, road)


func _get_rotated_size() -> Vector2i:
	var def := _building_defs[_current_building_key] as Dictionary
	var base_size := def["size"] as Vector2i
	if _rotation_index % 2 == 0:
		return base_size
	else:
		return Vector2i(base_size.y, base_size.x)


func _get_rotated_entrance(tile_origin: Vector2i) -> Vector2i:
	var def := _building_defs[_current_building_key] as Dictionary
	var entrance := def["entrance"] as Vector2i
	var size := def["size"] as Vector2i

	# Rotate entrance offset based on rotation index
	var rotated: Vector2i
	match _rotation_index:
		0: rotated = entrance
		1: rotated = Vector2i(size.y - 1 - entrance.y, entrance.x)
		2: rotated = Vector2i(size.x - 1 - entrance.x, size.y - 1 - entrance.y)
		3: rotated = Vector2i(entrance.y, size.x - 1 - entrance.x)
		_: rotated = entrance

	return tile_origin + rotated


func _apply_ghost_material(node: Node) -> void:
	if node is MeshInstance3D:
		for i in range(node.get_surface_override_material_count()):
			node.set_surface_override_material(i, _ghost_material)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_apply_ghost_material(child)


func _get_mouse_world_position() -> Variant:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return null

	var mouse_pos := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse_pos)
	var dir := camera.project_ray_normal(mouse_pos)

	# Intersect with Y=0 plane
	if abs(dir.y) < 0.001:
		return null

	var t := -from.y / dir.y
	return from + dir * t
