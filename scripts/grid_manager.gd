extends Node

## Manages the game grid. Tracks what occupies each tile.
## 1 tile = 3m x 3m. Coordinates are in tile space (integers).
## Includes AStarGrid2D for pathfinding.

const TILE_SIZE: float = 3.0

enum TileState {
	EMPTY,
	BUILDING,
	BUILDING_BORDER,  # 1-tile buffer around buildings, walkable but blocks placement
	ROAD,
	FIELD,
	FENCE,
	NATURAL_OBJECT,
	PENDING_CONSTRUCTION,
}

# Dictionary mapping Vector2i (tile coords) to tile data
var _tiles: Dictionary = {}

# Pathfinding
var _astar: AStarGrid2D
var _grid_offset: Vector2i  # offset to convert tile coords to astar coords (astar uses positive indices)
var _grid_size: int = 0


func reset() -> void:
	_tiles.clear()
	_astar = null
	_grid_offset = Vector2i.ZERO
	_grid_size = 0


func initialize_pathfinding(map_size: int) -> void:
	_grid_size = map_size
	var half := map_size / 2
	_grid_offset = Vector2i(half, half)

	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(0, 0, map_size, map_size)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.update()


## Find a path between two tile positions. Returns array of tile coords.
func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if _astar == null:
		return []

	var astar_from := from + _grid_offset
	var astar_to := to + _grid_offset

	# Check bounds
	if not _is_in_bounds(astar_from) or not _is_in_bounds(astar_to):
		return []

	# Temporarily make the destination walkable if it's a field tile
	# (worker needs to reach it)
	var dest_was_solid := _astar.is_point_solid(astar_to)
	if dest_was_solid:
		var data := get_tile(to)
		if not data.is_empty() and data["state"] == TileState.FIELD:
			_astar.set_point_solid(astar_to, false)

	var astar_path := _astar.get_id_path(astar_from, astar_to)

	# Restore destination state
	if dest_was_solid:
		_astar.set_point_solid(astar_to, dest_was_solid)

	# Convert back to tile coords
	var result: Array[Vector2i] = []
	for i in range(1, astar_path.size()):  # skip first (current position)
		result.append(astar_path[i] - _grid_offset)

	return result


## Convert world position (Vector3) to tile coordinates (Vector2i)
func world_to_tile(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		floori(world_pos.x / TILE_SIZE + 0.5),
		floori(world_pos.z / TILE_SIZE + 0.5)
	)


## Convert tile coordinates (Vector2i) to world position (Vector3, center of tile)
func tile_to_world(tile_pos: Vector2i) -> Vector3:
	return Vector3(
		tile_pos.x * TILE_SIZE,
		0.0,
		tile_pos.y * TILE_SIZE
	)


## Get tile data at a position.
func get_tile(tile_pos: Vector2i) -> Dictionary:
	if _tiles.has(tile_pos):
		return _tiles[tile_pos]
	return {}


## Check if a tile is empty
func is_tile_empty(tile_pos: Vector2i) -> bool:
	if not _tiles.has(tile_pos):
		return true
	return _tiles[tile_pos]["state"] == TileState.EMPTY


## Check if a rectangular area is fully empty
func is_area_empty(origin: Vector2i, size: Vector2i) -> bool:
	for x in range(origin.x, origin.x + size.x):
		for y in range(origin.y, origin.y + size.y):
			if not is_tile_empty(Vector2i(x, y)):
				return false
	return true


## Occupy a single tile. walkable overrides default walkability for that state.
func set_tile(tile_pos: Vector2i, state: TileState, ref: Node = null, walkable: bool = false) -> void:
	_tiles[tile_pos] = { "state": state, "ref": ref, "walkable": walkable }
	_update_astar_tile(tile_pos, state, walkable)


## Occupy a rectangular area of tiles
func set_area(origin: Vector2i, size: Vector2i, state: TileState, ref: Node = null, walkable: bool = false) -> void:
	for x in range(origin.x, origin.x + size.x):
		for y in range(origin.y, origin.y + size.y):
			set_tile(Vector2i(x, y), state, ref, walkable)


## Free a single tile
func clear_tile(tile_pos: Vector2i) -> void:
	_tiles.erase(tile_pos)
	_update_astar_tile(tile_pos, TileState.EMPTY)


## Free a rectangular area
func clear_area(origin: Vector2i, size: Vector2i) -> void:
	for x in range(origin.x, origin.x + size.x):
		for y in range(origin.y, origin.y + size.y):
			clear_tile(Vector2i(x, y))


## Get all occupied tiles
func get_all_tiles() -> Dictionary:
	return _tiles


func _update_astar_tile(tile_pos: Vector2i, state: TileState, walkable_override: bool = false) -> void:
	if _astar == null:
		return

	var astar_pos := tile_pos + _grid_offset
	if not _is_in_bounds(astar_pos):
		return

	# Default walkability by state
	# Walkable: EMPTY, ROAD, FIELD, BUILDING_BORDER
	# Solid: BUILDING, FENCE, NATURAL_OBJECT, PENDING_CONSTRUCTION
	var is_solid: bool = state != TileState.EMPTY and state != TileState.ROAD \
		and state != TileState.FIELD and state != TileState.BUILDING_BORDER

	# Override: building can declare specific tiles as walkable
	if walkable_override:
		is_solid = false

	_astar.set_point_solid(astar_pos, is_solid)

	# Set weight for road speed bonus
	match state:
		TileState.ROAD:
			_astar.set_point_weight_scale(astar_pos, 0.5)  # roads are faster
		TileState.FIELD:
			_astar.set_point_weight_scale(astar_pos, 1.0)
		_:
			_astar.set_point_weight_scale(astar_pos, 1.0)


func _is_in_bounds(astar_pos: Vector2i) -> bool:
	return astar_pos.x >= 0 and astar_pos.x < _grid_size \
		and astar_pos.y >= 0 and astar_pos.y < _grid_size
