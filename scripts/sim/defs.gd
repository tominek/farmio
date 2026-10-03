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
const WOOD_PER_TREE := 1         # logs
const CARRY_CAPACITY := 50.0      # kg carried by hand (a sack or crate)
const WHEELBARROW_CAPACITY := 150.0  # kg moved with a wheelbarrow (stored at the barn, bought at the Dealer)
const WHEELBARROW_PRICE := 150
const WHEELBARROW_WEIGHT := 20.0   # kg in the pickup
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

# Amounts: crops and seeds in kg, wood in logs (a log weighs LOG_WEIGHT kg in a vehicle).
const LOG_WEIGHT := 50.0
# Dealer prices: per kg (per log for wood)
const SELL_PRICE := { &"wood": 3.0, &"wheat": 2.0, &"potato": 0.35, &"corn": 1.5, &"beet": 0.25 }
const SEED_PRICE := { &"wheat": 12.0, &"potato": 1.0, &"corn": 90.0, &"beet": 500.0 }
const PICKUP_CAPACITY := 800.0    # kg
const PICKUP_SEATS := 3           # driver + 2 passengers (new hires ride along)
const HIRE_TIME := 4.0            # seconds at the Dealer per hired worker
const HIRE_BASE_COST := 400       # the 4th worker; every next one costs HIRE_COST_GROWTH times more
const HIRE_COST_GROWTH := 1.25
const PICKUP_HAUL_MIN := 300.0    # kg in a field pile before the pickup comes for it
const PICKUP_SPEED := 4.0         # tiles per second on a dirt road
const VEHICLE_ROAD_SPEED := { &"dirt": 1.0, &"gravel": 1.25 }
const MIN_TRIP_LOAD := 200.0      # kg: auto-sell waits for at least this much
const TASK_AGING := 45.0          # seconds of waiting that raise a task by one priority level

const CROPS := {
	# per 3x3 m tile, from real rates: seed (kg/ha) and yield (t/ha) × 0.0009 ha
	&"wheat": {"name": "Wheat", "seeds": "Wheat seeds", "grow_time": 300.0, "seed": 0.16, "yield": 6.3},
	&"potato": {"name": "Potatoes", "seeds": "Seed potatoes", "grow_time": 240.0, "seed": 2.25, "yield": 36.0},
	&"corn": {"name": "Corn", "seeds": "Corn seeds", "grow_time": 330.0, "seed": 0.0225, "yield": 9.0},
	&"beet": {"name": "Sugar Beet", "seeds": "Sugar beet seeds", "grow_time": 330.0, "seed": 0.0036, "yield": 60.0},
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


static func seed_of(crop: StringName) -> StringName:
	return StringName("seed_" + crop)


static func resource_name(res: StringName) -> String:
	if res == &"wheelbarrow":
		return "Wheelbarrows"
	var s := String(res)
	if s.begins_with("seed_"):
		return CROPS[StringName(s.trim_prefix("seed_"))]["seeds"]
	if CROPS.has(res):
		return CROPS[res]["name"]
	return s.capitalize()


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


## One-time fee for the n-th worker (1-based); the family workers are free.
static func hire_cost(n: int) -> int:
	if n <= START_WORKERS:
		return 0
	return snappedi(roundi(HIRE_BASE_COST * pow(HIRE_COST_GROWTH, n - START_WORKERS - 1)), 50)


## Weight in kg of an amount of a resource (wood is counted in logs).
static func weight(res: StringName, amount: float) -> float:
	if res == &"wood":
		return amount * LOG_WEIGHT
	if res == &"wheelbarrow":
		return amount * WHEELBARROW_WEIGHT
	return amount


## Pieces (logs, wheelbarrows) are carried one at a time, everything else in sacks / crates.
static func hand_load(res: StringName) -> float:
	return 1.0 if is_piece(res) else CARRY_CAPACITY


static func is_piece(res: StringName) -> bool:
	return res == &"wood" or res == &"wheelbarrow"


## Dealer price of one unit (kg of seed, one wheelbarrow).
static func buy_price(res: StringName) -> float:
	if res == &"wheelbarrow":
		return WHEELBARROW_PRICE
	return SEED_PRICE[StringName(String(res).trim_prefix("seed_"))]


static func seed_per_tile(crop: StringName) -> float:
	return CROPS[crop]["seed"]


## "36 kg", "1.2 t", "450 g", "3 logs".
static func format_amount(res: StringName, amount: float) -> String:
	if res == &"wood":
		return "%d log%s" % [amount, "" if int(amount) == 1 else "s"]
	if res == &"wheelbarrow":
		return "%d" % amount
	return format_kg(amount)


static func format_kg(kg: float) -> String:
	if kg >= 1000.0:
		return "%.1f t" % (kg / 1000.0)
	if kg >= 10.0:
		return "%d kg" % roundi(kg)
	if kg >= 1.0:
		return "%.1f kg" % kg
	return "%d g" % roundi(kg * 1000.0)


static func format_price(res: StringName, price: float) -> String:
	var unit := "log" if res == &"wood" else ("piece" if res == &"wheelbarrow" else "kg")
	return ("$%.2f/%s" if price < 10.0 and price != floorf(price) else "$%d/%s") % [price, unit]
