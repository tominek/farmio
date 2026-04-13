extends Node3D

## Generates the world: trees, dealer, pickup point, dirt road.

const TILE_SIZE: float = 3.0

# Scenes
var _tree_scenes: Array[PackedScene] = [
	preload("res://assets/environment/trees/full_tree.tscn"),
	preload("res://assets/environment/trees/conifer_full.tscn"),
]
var _dealer_scene: PackedScene = preload("res://assets/buildings/special/dealer.tscn")
var _pickup_point_scene: PackedScene = preload("res://assets/buildings/special/pickup_point.tscn")

# Containers
var _trees_container: Node3D
var _buildings_container: Node3D
var _roads_container: Node3D

# Generated positions
var farm_origin: Vector2i = Vector2i.ZERO
var dealer_position: Vector2i = Vector2i.ZERO

# Noise for tree generation
var _noise: FastNoiseLite


func generate(map_size: int, seed_value: int) -> void:
	_setup_containers()
	_setup_noise(seed_value)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	# Place farm origin near center
	farm_origin = Vector2i(
		rng.randi_range(-5, 5),
		rng.randi_range(-5, 5)
	)

	# Place dealer at random position
	_place_dealer(rng, map_size / 2)

	# Place pickup point at farm origin
	_place_pickup_point()

	# Generate dirt road first (so we can avoid trees on the path)
	var road_path := _generate_road()

	# Generate trees only in a playable radius, skip road tiles
	_generate_trees(map_size / 2, rng, road_path)

	# Clear area around farm origin and dealer
	_clear_area(farm_origin, 8)
	_clear_area(dealer_position, 5)


func _setup_containers() -> void:
	_trees_container = Node3D.new()
	_trees_container.name = "Trees"
	add_child(_trees_container)

	_roads_container = Node3D.new()
	_roads_container.name = "Roads"
	add_child(_roads_container)

	_buildings_container = get_node_or_null("../Buildings")
	if not _buildings_container:
		_buildings_container = Node3D.new()
		_buildings_container.name = "Buildings"
		add_child(_buildings_container)


func _setup_noise(seed_value: int) -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.seed = seed_value
	_noise.frequency = 0.03
	_noise.fractal_octaves = 3


## Each building has an entrance tile (relative to its origin) where the road connects.
var _pickup_entrance: Vector2i = Vector2i.ZERO
var _dealer_entrance: Vector2i = Vector2i.ZERO
var _dealer_rotated_size: Vector2i = Vector2i.ZERO


func _place_dealer(rng: RandomNumberGenerator, half: int) -> void:
	# Place dealer at a fixed distance from farm, random angle on circle
	var distance: int = GameSettings.dealer_distance
	var angle := rng.randf() * TAU
	dealer_position = Vector2i(
		farm_origin.x + roundi(cos(angle) * distance),
		farm_origin.y + roundi(sin(angle) * distance)
	)
	dealer_position.x = clampi(dealer_position.x, -half + 10, half - 10)
	dealer_position.y = clampi(dealer_position.y, -half + 10, half - 10)

	# Dealer always faces south (positive Z) so the sign is visible from the camera
	var dealer_size := Vector2i(4, 3)
	var rot := 0
	var rotated_size := dealer_size if rot % 2 == 0 else Vector2i(dealer_size.y, dealer_size.x)

	var dealer := _dealer_scene.instantiate()
	var offset := Vector3(
		(rotated_size.x - 1) * TILE_SIZE * 0.5,
		0,
		(rotated_size.y - 1) * TILE_SIZE * 0.5
	)
	dealer.position = GridManager.tile_to_world(dealer_position) + offset
	dealer.rotation.y = -rot * PI / 2.0
	_buildings_container.add_child(dealer)
	GridManager.set_area(dealer_position, rotated_size, GridManager.TileState.BUILDING, dealer)

	# Register 1-tile border
	var border_origin := Vector2i(dealer_position.x - 1, dealer_position.y - 1)
	var border_size := Vector2i(rotated_size.x + 2, rotated_size.y + 2)
	for x in range(border_origin.x, border_origin.x + border_size.x):
		for y in range(border_origin.y, border_origin.y + border_size.y):
			if x >= dealer_position.x and x < dealer_position.x + rotated_size.x \
				and y >= dealer_position.y and y < dealer_position.y + rotated_size.y:
				continue
			var tile := Vector2i(x, y)
			if GridManager.is_tile_empty(tile):
				GridManager.set_tile(tile, GridManager.TileState.BUILDING_BORDER, dealer)

	_dealer_rotated_size = rotated_size
	_dealer_entrance = _get_entrance_for_rotation(dealer_position, rotated_size, rot)

	# Store metadata
	dealer.set_meta("building_origin", dealer_position)
	dealer.set_meta("building_size", rotated_size)
	dealer.set_meta("entrance_tile", _dealer_entrance)


func _place_pickup_point() -> void:
	# Pickup point always faces south (sign visible from camera)
	var pickup_size := Vector2i(3, 3)

	var pickup := _pickup_point_scene.instantiate()
	var offset := Vector3(
		(pickup_size.x - 1) * TILE_SIZE * 0.5,
		0,
		(pickup_size.y - 1) * TILE_SIZE * 0.5
	)
	pickup.position = GridManager.tile_to_world(farm_origin) + offset
	_buildings_container.add_child(pickup)

	# Register building tiles (walkable)
	GridManager.set_area(farm_origin, pickup_size, GridManager.TileState.BUILDING, pickup, true)

	# No border for pickup point — player needs to build roads around it

	# Entrance at south center
	_pickup_entrance = Vector2i(farm_origin.x + pickup_size.x / 2, farm_origin.y + pickup_size.y)

	# Store metadata
	pickup.set_meta("building_origin", farm_origin)
	pickup.set_meta("building_size", pickup_size)
	pickup.set_meta("entrance_tile", _pickup_entrance)


## Returns rotation index (0-3) so building entrance (model's +Z side) faces toward target
func _get_facing_rotation(building_pos: Vector2i, target_pos: Vector2i) -> int:
	var dx: int = target_pos.x - building_pos.x
	var dy: int = target_pos.y - building_pos.y

	# Model door is at +Z. In world space, +Z = positive tile Y.
	# rot=0: door faces +Z (south), rot=1: door faces +X (east)
	# rot=2: door faces -Z (north), rot=3: door faces -X (west)
	if absi(dy) >= absi(dx):
		return 0 if dy > 0 else 2
	else:
		return 1 if dx > 0 else 3


## Returns the entrance tile position for a given rotation
## Entrance is always at the center of the "front" edge, one tile outside the building
func _get_entrance_for_rotation(origin: Vector2i, size: Vector2i, rot: int) -> Vector2i:
	match rot:
		0:  # entrance at bottom (positive Y)
			return Vector2i(origin.x + size.x / 2, origin.y + size.y)
		1:  # entrance at right (positive X)
			return Vector2i(origin.x + size.x, origin.y + size.y / 2)
		2:  # entrance at top (negative Y)
			return Vector2i(origin.x + size.x / 2, origin.y - 1)
		3:  # entrance at left (negative X)
			return Vector2i(origin.x - 1, origin.y + size.y / 2)
		_:
			return Vector2i(origin.x + size.x / 2, origin.y + size.y)


func _generate_trees(half: int, rng: RandomNumberGenerator, road_tiles: Dictionary) -> void:
	# Only generate trees within a reasonable radius to keep it fast
	var gen_radius := mini(half, 100)

	for x in range(-gen_radius, gen_radius):
		for y in range(-gen_radius, gen_radius):
			var tile := Vector2i(x, y)

			if not GridManager.is_tile_empty(tile):
				continue

			if road_tiles.has(tile):
				continue

			var noise_val := _noise.get_noise_2d(float(x), float(y))

			if noise_val > 0.25 and rng.randf() < 0.4:
				_spawn_tree(tile, rng)
			elif noise_val > 0.1 and rng.randf() < 0.08:
				_spawn_tree(tile, rng)


func _spawn_tree(tile: Vector2i, rng: RandomNumberGenerator) -> void:
	var scene_idx := rng.randi_range(0, _tree_scenes.size() - 1)
	var tree := _tree_scenes[scene_idx].instantiate()

	var jitter := Vector3(
		rng.randf_range(-0.5, 0.5),
		0,
		rng.randf_range(-0.5, 0.5)
	)
	tree.position = GridManager.tile_to_world(tile) + jitter

	var scale_var := rng.randf_range(0.8, 1.2)
	tree.scale = Vector3(scale_var, scale_var, scale_var)
	tree.rotation.y = rng.randf() * TAU

	_trees_container.add_child(tree)
	GridManager.set_tile(tile, GridManager.TileState.NATURAL_OBJECT, tree)


func _clear_area(center: Vector2i, radius: int) -> void:
	for x in range(center.x - radius, center.x + radius + 1):
		for y in range(center.y - radius, center.y + radius + 1):
			var tile := Vector2i(x, y)
			var data := GridManager.get_tile(tile)
			if data.is_empty():
				continue
			if data["state"] == GridManager.TileState.NATURAL_OBJECT:
				var tree_node: Node = data["ref"]
				if tree_node:
					tree_node.queue_free()
				GridManager.clear_tile(tile)


func _generate_road() -> Dictionary:
	var road_scene := preload("res://assets/roads/dirt/dirt_road.tscn")
	var road_tiles: Dictionary = {}

	# Use A* for correct obstacle avoidance, then smooth into straight segments
	var raw_path: Array[Vector2i] = GridManager.find_path(_pickup_entrance, _dealer_entrance)
	if raw_path.is_empty():
		# Fallback
		raw_path = _build_road_path(_pickup_entrance, _dealer_entrance)

	# Add the start tile
	var path: Array[Vector2i] = [_pickup_entrance]
	path.append_array(raw_path)

	# Smooth the zig-zag path into straight segments
	path = _smooth_path(path)

	for tile in path:
		if road_tiles.has(tile):
			continue

		# Clear trees on the path
		var data := GridManager.get_tile(tile)
		if not data.is_empty() and data["state"] == GridManager.TileState.NATURAL_OBJECT:
			var tree_node: Node = data["ref"]
			if tree_node:
				tree_node.queue_free()
			GridManager.clear_tile(tile)

		# Skip building tiles
		if not data.is_empty() and data["state"] == GridManager.TileState.BUILDING:
			road_tiles[tile] = true
			continue

		var road := road_scene.instantiate()
		road.position = GridManager.tile_to_world(tile)
		_roads_container.add_child(road)
		GridManager.set_tile(tile, GridManager.TileState.ROAD, road)
		road_tiles[tile] = true

	return road_tiles


func _smooth_path(raw: Array[Vector2i]) -> Array[Vector2i]:
	## Simplify an A* path into straight segments.
	## Find key waypoints where direction must change, then walk L-shaped between them.
	if raw.size() < 3:
		return raw

	# Step 1: Find waypoints using line-of-sight simplification
	var waypoints: Array[Vector2i] = [raw[0]]
	var current_idx := 0

	while current_idx < raw.size() - 1:
		# Try to reach as far ahead as possible with a clear L-shaped path
		var best_idx := current_idx + 1
		for test_idx in range(raw.size() - 1, current_idx, -1):
			if _can_walk_l_shape(raw[current_idx], raw[test_idx]):
				best_idx = test_idx
				break
		waypoints.append(raw[best_idx])
		current_idx = best_idx

	# Step 2: Build smooth path by walking L-shaped between waypoints
	var result: Array[Vector2i] = [waypoints[0]]
	for i in range(1, waypoints.size()):
		var from := waypoints[i - 1]
		var to := waypoints[i]
		var current := from

		# Walk X first, then Y
		while current.x != to.x:
			current.x += signi(to.x - current.x)
			result.append(current)
		while current.y != to.y:
			current.y += signi(to.y - current.y)
			result.append(current)

	return result


func _can_walk_l_shape(from: Vector2i, to: Vector2i) -> bool:
	## Check if we can walk an L-shaped path (X then Y) without hitting buildings.
	var current := from

	# Walk X
	while current.x != to.x:
		current.x += signi(to.x - current.x)
		if _is_tile_blocked(current):
			return false

	# Walk Y
	while current.y != to.y:
		current.y += signi(to.y - current.y)
		if _is_tile_blocked(current):
			return false

	return true


func _get_approach_tile(entrance: Vector2i, building_origin: Vector2i, building_size: Vector2i) -> Vector2i:
	## Returns a tile one step away from the entrance, in the direction away from the building center.
	var bld_center := Vector2i(
		building_origin.x + building_size.x / 2,
		building_origin.y + building_size.y / 2
	)
	var dx: int = entrance.x - bld_center.x
	var dy: int = entrance.y - bld_center.y

	# Move one tile further from the building
	if absi(dx) > absi(dy):
		return Vector2i(entrance.x + signi(dx), entrance.y)
	else:
		return Vector2i(entrance.x, entrance.y + signi(dy))


func _build_road_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [from]
	var current := from
	var dx: int = to.x - from.x
	var dy: int = to.y - from.y

	# Pick 1-3 random bend points along the way using noise
	var bend_count := 2
	var segments: Array[Vector2i] = []

	# Create bend waypoints
	for i in range(bend_count):
		var t := float(i + 1) / float(bend_count + 1)
		var mid_x: int = from.x + roundi(dx * t)
		var mid_y: int = from.y + roundi(dy * t)

		# Offset the bend perpendicular to the main direction
		var noise_val := _noise.get_noise_2d(float(mid_x), float(mid_y))
		var offset: int = roundi(noise_val * 15.0)
		if absi(dx) > absi(dy):
			mid_y += offset
		else:
			mid_x += offset

		segments.append(Vector2i(mid_x, mid_y))

	segments.append(to)

	# Walk through each segment: go straight on one axis, then the other (L-shape)
	# Skip tiles occupied by buildings
	for waypoint in segments:
		# First walk X, then walk Y
		while current.x != waypoint.x:
			var next := Vector2i(current.x + signi(waypoint.x - current.x), current.y)
			if _is_tile_blocked(next):
				# Shift Y by one to go around
				current.y += 1
				path.append(current)
			else:
				current = next
				path.append(current)

		while current.y != waypoint.y:
			var next := Vector2i(current.x, current.y + signi(waypoint.y - current.y))
			if _is_tile_blocked(next):
				# Shift X by one to go around
				current.x += 1
				path.append(current)
			else:
				current = next
				path.append(current)

	return path


func _is_tile_blocked(tile: Vector2i) -> bool:
	var data := GridManager.get_tile(tile)
	if data.is_empty():
		return false
	var state: int = data["state"] as int
	return state == GridManager.TileState.BUILDING
