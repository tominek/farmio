class_name Defs
## Static game data and grid geometry helpers shared by simulation and presentation.

const TILE := 3.0                 # meters per grid tile
const BORDER := 6                 # width of the unclearable forest band at the map edge
const ROAD_BLOCK := 2             # two-way roads are built from 2x2-tile blocks

# grid directions in rotation order: rotation r makes the building front face DIRS[r]
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

enum TreeKind { NONE, DECIDUOUS, CONIFER }
enum Water { NONE, RIVER, POND }
enum TreeStage { SAPLING, SMALL, FULL }

# Balance values (later exposed in the debug "tweakable constants" panel).
const START_MONEY := 5000
const START_WORKERS := 3
const WALK_SPEED := 1.3           # tiles per second on grass
const FIELD_SPEED := 0.8          # walking across a field is slower
const ROAD_SPEED := { &"dirt": 1.1, &"gravel": 1.15 }  # walking on a path is only a bit easier; roads pay off for vehicles
# Bridges: a road block across a straight river block (always exactly one block, across the flow)
const BRIDGE_COST := { &"dirt": 300, &"gravel": 600 }   # on top of the road block
const BRIDGE_WORK := 6.0          # build work of a bridge block = road block work × this
# Building materials (bought at the Dealer or made, carried from the barn to the site before building)
const MATERIAL_PRICE := { &"gravel": 0.4, &"planks": 4.0 }   # per kg (gravel), per piece (planks)
const GRAVEL_PER_BLOCK := 300.0   # kg of gravel for a 2x2 road block (also when upgrading a dirt road)
# Building levels (upgrades unlocked in the research tree, see Tech): planks per upgrade to a level,
# processing work and room inside by level (index = level)
const UPGRADE_PLANKS := { 2: 50.0, 3: 100.0 }
const UPGRADE_WORK := 0.5         # an upgrade takes this part of the building's build work
const DISMANTLE_WORK := 0.5       # taking a building down to move it: this part of its build work
const LEVEL_WORK: Array[float] = [1.0, 1.0, 0.6, 0.4]
const LEVEL_ROOM: Array[float] = [1.0, 1.0, 1.5, 2.0]
const CHOP_TIME := 4.0            # worker seconds per tree
const BUILD_CHUNK := 8.0          # worker seconds per build task
const WOOD_PER_TREE := 1         # logs
const DAY_LENGTH := 600.0         # game seconds per in-game day (display only)
const CARRY_CAPACITY := 50.0      # kg carried by hand (a sack or crate)
const WHEELBARROW_CAPACITY := 150.0  # kg moved with a wheelbarrow (stored at the barn, bought at the Dealer)
const WHEELBARROW_PRICE := 150
const WHEELBARROW_WEIGHT := 20.0   # kg in the pickup
const LOAD_TIME := 1.0            # picking up a load
const PLANNER_INTERVAL := 1.0     # seconds of game time between runs of the logistics planner (carry legs)
const PLANNER_BUDGET_USEC := 2000  # µs a planner run may spend before it stops looking up walk costs not memoised yet; the rest waits a run
const UNREACHABLE_RETRY := 10.0  # seconds of game time before a memoised "no way there" walk cost is looked up again (only after a tile opened)
const GROUND_PILE_CAPACITY := 200.0  # kg on one ground pile (felled logs, goods dropped when a leg breaks)
const GROUND_PILE_REACH := 2      # a drop joins a pile of the same good this many tiles away
const GROUND_PILE_SEARCH := 4     # a new pile goes on the nearest free tile this many tiles away at most

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
const PLANK_WEIGHT := 10.0        # a plank; carried 5 at a time
# Dealer prices: per kg (per log for wood)
const SELL_PRICE := { &"wood": 3.0, &"wheat": 2.0, &"potato": 0.5, &"corn": 1.5, &"beet": 0.35, &"flour": 4.0, &"planks": 2.5 }
const AUTO_SELL_OFF: Array[StringName] = [&"planks"]   # kept for building by default
# Goods counted in pieces (everything else in kg): weight of one piece in kg
const PIECE_WEIGHT := { &"wood": LOG_WEIGHT, &"wheelbarrow": WHEELBARROW_WEIGHT, &"planks": PLANK_WEIGHT }
const SEED_PRICE := { &"wheat": 12.0, &"potato": 1.0, &"corn": 90.0, &"beet": 500.0 }
const PICKUP_CAPACITY := 800.0    # kg
const PICKUP_SEATS := 3           # driver + 2 passengers (new hires ride along)
const HIRE_TIME := 4.0            # seconds at the Dealer per hired worker
const HIRE_BASE_COST := 400       # the 4th worker; every next one costs HIRE_COST_GROWTH times more
const HIRE_COST_GROWTH := 1.25
const PICKUP_SPEED := 4.0         # tiles per second on a dirt road
const VEHICLE_ROAD_SPEED := { &"dirt": 1.0, &"gravel": 1.25 }
const MIN_TRIP_LOAD := 200.0      # kg: auto-sell waits for at least this much

# Routes by cost (logistics step 3; all illustrative, tuned in step 5). The planner compares walking a
# carry with "walk to a road, let the pickup drive it, walk the rest" and takes the cheaper one.
const WALK_COST := 1.0            # per second a worker walks with a load
const DRIVE_COST := 0.15          # per second the pickup drives (shared by everything aboard)
const HANDLING_COST := 15.0       # per load into / unload from a vehicle
const VEHICLE_WAIT_COST := 30.0   # expected wait for the pickup
const ROUTE_MIN_WALK := 40.0      # tiles: a shorter walk is never split
const STOP_REACH := 2             # tiles from a road block that make a store a vehicle stop
const ROAD_PILE_SEARCH := 24      # tiles searched for a road to put a road pile by
const ROAD_PILE_JOIN := 4         # a road pile of the same good with room this near is used instead of a new one
const TRIP_MAX_WAIT := 60.0       # seconds the oldest waiting ride waits before the pickup goes with a small load
const TRIP_MAX_STOPS := 8         # stops in one pickup trip at most
const TRIP_DETOUR := 0.5          # a ride joins a trip when the extra driving is at most
const TRIP_DETOUR_MIN := 20.0     # max(TRIP_DETOUR_MIN, TRIP_DETOUR × its own drive) seconds
const HELPER_REACH := 25          # tiles: a worker farther (walking) from a pickup stop does not come to help load
const TASK_AGING := 45.0          # seconds of waiting that raise a task by one priority level
const TASK_AGING_MAX := 2.0       # waiting raises a task by at most this many levels, so a fresh task of a
                                  # higher category always wins over a pile of old low-category tasks

# Sheds and collection points (logistics step 4; illustrative, tuned in step 5)
const SHED_CAPACITY := 2000.0     # kg in a Shed
const COLLECT_CAPACITY := 400.0   # kg on a collection point
const COLLECT_PREFER := 8         # tiles a collection point may lie farther than the road pile spot and still be used instead of it
const COLLECT_SNAP := 2           # tiles within which the placement ghost jumps to a road edge

const CROPS := {
	# per 3x3 m tile, from real rates: seed (kg/ha) and yield (t/ha) × 0.0009 ha
	&"wheat": {"name": "Wheat", "seeds": "Wheat seeds", "grow_time": 240.0, "seed": 0.16, "yield": 6.3},
	&"potato": {"name": "Potatoes", "seeds": "Seed potatoes", "grow_time": 180.0, "seed": 2.25, "yield": 36.0},
	&"corn": {"name": "Corn", "seeds": "Corn seeds", "grow_time": 270.0, "seed": 0.0225, "yield": 9.0},
	&"beet": {"name": "Sugar Beet", "seeds": "Sugar beet seeds", "grow_time": 270.0, "seed": 0.0036, "yield": 60.0},
}

# Good groups of a store filter (the Shed / collection point panel grid, in its order); the icon is
# that of the first good. Wheelbarrows are in no group: only a store that takes everything takes them.
const FILTER_GROUPS: Array[Dictionary] = [
	{"id": &"wheat", "name": "Wheat", "goods": [&"wheat"]},
	{"id": &"potato", "name": "Potatoes", "goods": [&"potato"]},
	{"id": &"corn", "name": "Corn", "goods": [&"corn"]},
	{"id": &"beet", "name": "Sugar beet", "goods": [&"beet"]},
	{"id": &"seeds", "name": "Seeds", "goods": [&"seed_wheat", &"seed_potato", &"seed_corn", &"seed_beet"]},
	{"id": &"flour", "name": "Flour", "goods": [&"flour"]},
	{"id": &"wood", "name": "Logs", "goods": [&"wood"]},
	{"id": &"planks", "name": "Planks", "goods": [&"planks"]},
	{"id": &"gravel", "name": "Gravel", "goods": [&"gravel"]},
]

const BUILDINGS := {
	&"storage_barn": {
		"name": "Storage Barn", "size": Vector2i(4, 3), "cost": 0, "build_work": 48.0,
		"model": "building_storage_barn_eu", "buildable": true, "storage": true, "material": {&"planks": 60.0},
	},
	&"garage": {
		"name": "Garage", "size": Vector2i(5, 4), "cost": 0, "build_work": 64.0,
		"model": "building_garage", "buildable": true, "material": {&"planks": 80.0},
	},
	&"dealer": {
		"name": "Dealer", "size": Vector2i(4, 4), "cost": 0, "build_work": 0.0,
		"model": "building_dealer", "buildable": false,
	},
	&"field": {
		"name": "Field", "size": Vector2i(8, 8), "cost": 0, "build_work": 0.0,
		"field": true, "buildable": true,
	},
	&"hand_mill": {
		"name": "Hand Mill", "size": Vector2i(2, 2), "cost": 0, "build_work": 32.0,
		"model": "building_hand_mill", "buildable": true, "material": {&"planks": 30.0}, "upgrade": UPGRADE_PLANKS,
		"process": {"in": &"wheat", "out": &"flour", "batch": 50.0, "yield": 0.75, "work": 40.0, "in_cap": 200.0, "out_cap": 150.0},
	},
	&"water_mill": {
		"name": "Water Mill", "size": Vector2i(3, 3), "cost": 0, "build_work": 72.0,
		"model": "building_water_mill", "buildable": true, "river_side": true, "material": {&"planks": 80.0}, "upgrade": UPGRADE_PLANKS,
		"process": {"in": &"wheat", "out": &"flour", "batch": 50.0, "yield": 0.75, "work": 12.0, "in_cap": 400.0, "out_cap": 300.0},
		"hint": "on the river bank: the wheel side over the river",
	},
	&"sawmill": {
		"name": "Sawmill", "size": Vector2i(3, 2), "cost": 0, "build_work": 48.0,
		"model": "building_sawmill", "buildable": true, "material": {&"planks": 40.0}, "upgrade": UPGRADE_PLANKS,
		"process": {"in": &"wood", "out": &"planks", "batch": 1.0, "yield": 3.0, "work": 10.0, "in_cap": 10.0, "out_cap": 30.0},
	},
	&"shed": {
		"name": "Shed", "size": Vector2i(2, 2), "cost": 0, "build_work": 24.0,
		"model": "building_supply_storage", "buildable": true, "storage": true, "capacity": SHED_CAPACITY, "filter": true,
		"material": {&"planks": 60.0},
	},
	&"collection_point": {
		"name": "Collection point", "size": Vector2i(1, 1), "cost": 0, "build_work": 6.0,
		"model": "building_collection_point", "buildable": true, "collect": true, "capacity": COLLECT_CAPACITY, "filter": true,
		"by_road": true, "material": {&"planks": 20.0}, "hint": "it must touch a road: the pickup collects there",
	},
	&"road_dirt": {
		"name": "Dirt Road", "size": Vector2i(2, 2), "cost": 0, "build_work": 3.0,
		"road": &"dirt", "buildable": true,
	},
	&"road_gravel": {
		"name": "Gravel Road", "size": Vector2i(2, 2), "cost": 0, "build_work": 6.0,
		"road": &"gravel", "buildable": true, "material": {&"gravel": GRAVEL_PER_BLOCK},
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
	return BUILDINGS.get(id, {}).has("road")      # "" (no building, e.g. a tool mode) is neither


static func is_field(id: StringName) -> bool:
	return BUILDINGS.get(id, {}).has("field")


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


## Rotates a 4-bit connection mask (bits in DIRS order: N, E, S, W) by r quarter turns.
static func rotate_mask(m: int, r: int) -> int:
	return ((m << r) | (m >> (4 - r))) & 0b1111


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


## Weight in kg of an amount of a resource (pieces: logs, planks, wheelbarrows).
static func weight(res: StringName, amount: float) -> float:
	return amount * PIECE_WEIGHT.get(res, 1.0)


## Logs and wheelbarrows are carried one at a time, planks as many as fit a hand load,
## everything else in sacks / crates.
static func hand_load(res: StringName) -> float:
	if res == &"wheelbarrow":
		return 1.0
	if is_piece(res):
		return maxf(1.0, floorf(CARRY_CAPACITY / PIECE_WEIGHT[res]))
	return CARRY_CAPACITY


static func is_piece(res: StringName) -> bool:
	return PIECE_WEIGHT.has(res)


## Sold by the Dealer (seeds, road materials, equipment); planks are only made at the Sawmill.
static func buyable(res: StringName) -> bool:
	return res == &"wheelbarrow" or MATERIAL_PRICE.has(res) or String(res).begins_with("seed_")


## Dealer price of one unit (kg of seed, one wheelbarrow).
static func buy_price(res: StringName) -> float:
	if res == &"wheelbarrow":
		return WHEELBARROW_PRICE
	if MATERIAL_PRICE.has(res):
		return MATERIAL_PRICE[res]
	return SEED_PRICE[StringName(String(res).trim_prefix("seed_"))]


static func seed_per_tile(crop: StringName) -> float:
	return CROPS[crop]["seed"]


## "36 kg", "1.2 t", "450 g", "3 logs".
static func format_amount(res: StringName, amount: float) -> String:
	if res == &"wood":
		return "%d log%s" % [amount, "" if int(amount) == 1 else "s"]
	if res == &"planks":
		return "%d plank%s" % [amount, "" if int(amount) == 1 else "s"]
	if res == &"wheelbarrow":
		return "%d" % amount
	return format_kg(amount)


static func format_kg(kg: float) -> String:
	if kg < 0.0005:
		return "0 kg"
	if kg >= 1000.0:
		return "%.1f t" % (kg / 1000.0)
	if kg >= 10.0:
		return "%d kg" % roundi(kg)
	if kg >= 1.0:
		return "%.1f kg" % kg
	return "%d g" % roundi(kg * 1000.0)


## "300 kg gravel", "40 planks": an amount with what it is.
static func format_goods(res: StringName, amount: float) -> String:
	var text := format_amount(res, amount)
	return text if is_piece(res) else "%s %s" % [text, resource_name(res).to_lower()]


## Thousands separator of money ("1 500" or "1,500"), set from the player settings.
static var thousands_sep := " "


## The game's currency is Quacks: "1 500 qk", "-300 qk".
static func format_money(amount: float) -> String:
	var n := absi(roundi(amount))
	var digits := str(n)
	var text := ""
	while digits.length() > 3:
		text = thousands_sep + digits.right(3) + text
		digits = digits.left(digits.length() - 3)
	return "%s%s%s qk" % ["-" if amount < -0.5 else "", digits, text]


## "2 qk/kg", "0.40 qk/kg", "4 qk/plank".
static func format_price(res: StringName, price: float) -> String:
	var unit: String = {&"wood": "log", &"planks": "plank", &"wheelbarrow": "piece"}.get(res, "kg")
	if price < 10.0 and price != floorf(price):
		return "%.2f qk/%s" % [price, unit]
	return "%s/%s" % [format_money(price), unit]
