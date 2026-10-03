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
const ROAD_SPEED := { &"dirt": 1.5, &"gravel": 1.8 }
const CHOP_TIME := 4.0            # worker seconds per tree
const BUILD_CHUNK := 8.0          # worker seconds per build task
const WOOD_PER_TREE := 1

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
	&"road_dirt": {
		"name": "Dirt Road", "size": Vector2i(2, 2), "cost": 0, "build_work": 3.0,
		"road": &"dirt", "buildable": true,
	},
}


static func def(id: StringName) -> Dictionary:
	return BUILDINGS[id]


static func is_road(id: StringName) -> bool:
	return BUILDINGS[id].has("road")


## Footprint size on the grid after rotation.
static func footprint(id: StringName, rot: int) -> Vector2i:
	var s: Vector2i = BUILDINGS[id]["size"]
	return Vector2i(s.y, s.x) if rot % 2 == 1 else s


## Rotates a grid offset by r quarter turns; matches a Godot rotation.y of -r * 90°.
static func rotate_offset(p: Vector2, r: int) -> Vector2:
	for i in r:
		p = Vector2(-p.y, p.x)
	return p


## The tile just in front of the building's access side (unrotated: centre of the -y edge).
static func access_cell(id: StringName, anchor: Vector2i, rot: int) -> Vector2i:
	var s: Vector2i = BUILDINGS[id]["size"]
	var local_center := Vector2(s.x - 1, s.y - 1) * 0.5
	var local_access := Vector2(s.x / 2, -1)
	var fs := footprint(id, rot)
	var center := Vector2(anchor) + Vector2(fs.x - 1, fs.y - 1) * 0.5
	var p := center + rotate_offset(local_access - local_center, rot)
	return Vector2i(roundi(p.x), roundi(p.y))


## World-space centre of a footprint (models have their origin there).
static func footprint_center(anchor: Vector2i, size: Vector2i) -> Vector3:
	return Vector3((anchor.x + size.x * 0.5) * TILE, 0.0, (anchor.y + size.y * 0.5) * TILE)


static func cell_center(cell: Vector2i) -> Vector3:
	return Vector3((cell.x + 0.5) * TILE, 0.0, (cell.y + 0.5) * TILE)


static func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / TILE), floori(p.z / TILE))
