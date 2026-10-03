class_name Defs
## Static game data and grid geometry helpers shared by simulation and presentation.

const TILE := 3.0                 # meters per grid tile
const BORDER := 6                 # width of the unclearable forest band at the map edge
const ROAD_BLOCK := 2             # two-way roads are built from 2x2-tile blocks

# grid directions in rotation order: rotation r makes the building front face DIRS[r]
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

enum TreeKind { NONE, DECIDUOUS, CONIFER }
enum TreeStage { SAPLING, SMALL, FULL }

# Balance values (later exposed in the debug "tweakable constants" panel).
const START_MONEY := 5000
const START_WORKERS := 3
const WALK_SPEED := 1.3           # tiles per second on grass
const FIELD_SPEED := 0.8          # walking across a field is slower
const ROAD_SPEED := { &"dirt": 1.5, &"gravel": 1.8 }
const CHOP_TIME := 4.0            # worker seconds per tree
const BUILD_CHUNK := 8.0          # worker seconds per build task
const WOOD_PER_TREE := 1
const CARRY_CAPACITY := 4         # units carried by hand
const LOAD_TIME := 1.0            # picking up a load

# Fields (Small tier only for now)
const FIELD_MIN_DIM := 4
const FIELD_MAX_DIM := 16
const FIELD_MAX_AREA := 256
const FIELD_COST_PER_TILE := 4
const FENCE_WORK_PER_TILE := 0.5  # worker seconds per perimeter tile
const FIELD_WORK := {             # worker seconds per tile, by hand
	&"cultivate": 1.6,
	&"seed": 1.0,
	&"harvest": 2.0,
}

const CROPS := {
	&"wheat": {"name": "Wheat", "grow_time": 300.0, "yield": 2.0},
	&"potato": {"name": "Potatoes", "grow_time": 240.0, "yield": 3.0},
	&"corn": {"name": "Corn", "grow_time": 330.0, "yield": 2.0},
	&"beet": {"name": "Sugar Beet", "grow_time": 330.0, "yield": 3.0},
}

const BUILDINGS := {
	&"storage_barn": {
		"name": "Storage Barn", "size": Vector2i(4, 3), "cost": 1500, "build_work": 48.0,
		"model": "building_storage_barn_eu", "buildable": true, "storage": true,
	},
	&"garage": {
		"name": "Garage", "size": Vector2i(5, 4), "cost": 2500, "build_work": 64.0,
		"model": "building_garage", "buildable": true,
	},
	&"dealer": {
		"name": "Dealer", "size": Vector2i(4, 4), "cost": 0, "build_work": 0.0,
		"model": "building_dealer", "buildable": false,
	},
	&"field": {
		"name": "Field", "size": Vector2i(8, 8), "cost": 0, "build_work": 0.0,
		"field": true, "buildable": true,
	},
	&"road_dirt": {
		"name": "Dirt Road", "size": Vector2i(2, 2), "cost": 0, "build_work": 3.0,
		"road": &"dirt", "buildable": true,
	},
}


static func def(id: StringName) -> Dictionary:
	return BUILDINGS[id]


static func is_road(id: StringName) -> bool:
	return BUILDINGS[id].has("road")


static func is_field(id: StringName) -> bool:
	return BUILDINGS[id].has("field")


static func field_cost(size: Vector2i) -> int:
	return size.x * size.y * FIELD_COST_PER_TILE


static func field_size_ok(size: Vector2i) -> bool:
	return mini(size.x, size.y) >= FIELD_MIN_DIM and maxi(size.x, size.y) <= FIELD_MAX_DIM \
		and size.x * size.y <= FIELD_MAX_AREA


## Footprint size on the grid after rotation (base_size = unrotated size).
static func rotated(base_size: Vector2i, rot: int) -> Vector2i:
	return Vector2i(base_size.y, base_size.x) if rot % 2 == 1 else base_size


static func footprint(id: StringName, rot: int) -> Vector2i:
	return rotated(BUILDINGS[id]["size"], rot)


## Rotates a grid offset by r quarter turns; matches a Godot rotation.y of -r * 90°.
static func rotate_offset(p: Vector2, r: int) -> Vector2:
	for i in r:
		p = Vector2(-p.y, p.x)
	return p


## The tile just in front of the access side (unrotated: centre of the -y edge).
static func access_for(base_size: Vector2i, anchor: Vector2i, rot: int) -> Vector2i:
	var s := base_size
	var local_center := Vector2(s.x - 1, s.y - 1) * 0.5
	var local_access := Vector2(s.x / 2, -1)
	var fs := rotated(s, rot)
	var center := Vector2(anchor) + Vector2(fs.x - 1, fs.y - 1) * 0.5
	var p := center + rotate_offset(local_access - local_center, rot)
	return Vector2i(roundi(p.x), roundi(p.y))


static func access_cell(id: StringName, anchor: Vector2i, rot: int) -> Vector2i:
	return access_for(BUILDINGS[id]["size"], anchor, rot)


## World-space centre of a footprint (models have their origin there).
static func footprint_center(anchor: Vector2i, size: Vector2i) -> Vector3:
	return Vector3((anchor.x + size.x * 0.5) * TILE, 0.0, (anchor.y + size.y * 0.5) * TILE)


static func cell_center(cell: Vector2i) -> Vector3:
	return Vector3((cell.x + 0.5) * TILE, 0.0, (cell.y + 0.5) * TILE)


static func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / TILE), floori(p.z / TILE))
