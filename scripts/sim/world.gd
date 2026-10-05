class_name World
extends RefCounted
## The whole simulation state. Presentation reads it and listens to its signals;
## it never touches scene nodes.

signal tree_changed(cell: Vector2i)
signal building_added(b: Building)        # finished buildings, fields and construction sites
signal building_removed(b: Building)
signal site_changed(site: ConstructionSite)
signal road_changed(anchor: Vector2i)
signal worker_added(w: Worker)
signal worker_removed(w: Worker)
signal stock_changed
signal vehicle_added(v: Vehicle)
signal field_changed(f: Field)              # crop switched: the field view is rebuilt
signal tech_changed                        # a research node was unlocked
signal building_changed(b: Building)        # level raised (the view swaps the model)
signal tree_marked(cell: Vector2i)          # a tree was marked for felling or its mark removed
signal pile_added(s: Store)                 # a ground pile appeared (felled logs, goods dropped on the way)
signal pile_changed(s: Store)               # goods put on it or taken from it
signal pile_removed(s: Store)               # it was emptied (or moved out of a new building's way)

const SURFACES: Array[StringName] = [&"", &"dirt", &"gravel"]

var size: int
var seed_value: int
var time := 0.0
var money := Defs.START_MONEY
## Goods in their usual order (top bar chips, Dealer lists).
const GOODS: Array[StringName] = [&"wood", &"wheat", &"potato", &"corn", &"beet",
	&"seed_wheat", &"seed_potato", &"seed_corn", &"seed_beet", &"flour", &"planks", &"gravel", &"wheelbarrow"]
var loose := Store.new()           # goods with no store to go to (no barn yet, a save being loaded)
var _stores: Array[Building] = []  # finished storage buildings (cache)
var _access_cells := {}             # access tiles of all buildings, sites and fields (cache)
var _access_dirty := true
var auto_sell := {}                # resource -> {"on": bool, "keep": float}
var orders := {}                   # seed resource -> amount ordered at the Dealer, not yet collected
var hires_wanted := 0               # workers hired at the Dealer, waiting to be picked up
var _hire_fees: Array[int] = []    # prepaid fee of each waiting hire (refunded on cancel)
var trip_status := "In the garage"
var category_order: Array = Task.DEFAULT_ORDER.duplicate()   # player-ranked task categories, first = most urgent
var category_off := {}             # Task.Category -> true: workers ignore these tasks
var ledger := {}                   # "sales: wheat", "seeds", "hiring", "building", ... -> money in (+) / out (-)
var unlocked := {}                 # research node id -> true (see Tech)
var instant_build := false          # developer cheat (F12): sites cost nothing and finish at once; not saved
var farm_name := ""                 # chosen by the player for the save (display only)

var tree_kind: PackedByteArray     # Defs.TreeKind per tile
var tree_stage: PackedByteArray    # Defs.TreeStage per tile
var occupant: PackedInt32Array     # id of the building / site / field on the tile, 0 = free
var road: PackedByteArray          # index into SURFACES for built road tiles
var water: PackedByteArray         # Defs.Water per tile (river runs in 2x2 blocks on the road lattice)
var road_blocks := {}              # Vector2i anchor -> surface (built two-way road blocks)
var marked := {}                    # Vector2i tree -> its felling task (CHOP, category FELLING)
var ground_piles: Array[Store] = []  # goods lying on the ground (Store.Kind.GROUND), see drop_goods
var _pile_at := {}                 # Vector2i -> its ground pile

var buildings := {}                # id -> Building (including construction sites and fields)
var fields: Array[Field] = []
var workers: Array[Worker] = []
var vehicles: Array[Vehicle] = []
var tasks := TaskQueue.new()
var planner: Planner               # carry legs between places, planned about once a second
var nav: Nav
var road_nav: RoadNav

var _trip_task: Task = null
var _trip_check := 0.0
var _force_trip := false

var _next_id := 1


func _init(p_size: int, p_seed: int) -> void:
	size = p_size
	seed_value = p_seed
	var n := size * size
	tree_kind.resize(n)
	tree_stage.resize(n)
	occupant.resize(n)
	road.resize(n)
	water.resize(n)
	nav = Nav.new(size)
	road_nav = RoadNav.new(self)
	planner = Planner.new(self)
	for res: StringName in Defs.SELL_PRICE:
		auto_sell[res] = {"on": not Defs.AUTO_SELL_OFF.has(res), "keep": 0.0}


# --- tiles -------------------------------------------------------------------

func idx(c: Vector2i) -> int:
	return c.y * size + c.x


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < size and c.y < size


## Unclearable boundary forest.
func is_locked(c: Vector2i) -> bool:
	return c.x < Defs.BORDER or c.y < Defs.BORDER or c.x >= size - Defs.BORDER or c.y >= size - Defs.BORDER


func has_tree(c: Vector2i) -> bool:
	return in_bounds(c) and tree_kind[idx(c)] != Defs.TreeKind.NONE


func is_water(c: Vector2i) -> bool:
	return in_bounds(c) and water[idx(c)] != Defs.Water.NONE


## World generation only: water replaces trees and blocks walking (bridges excepted).
func set_water(c: Vector2i, kind: int) -> void:
	var i := idx(c)
	water[i] = kind
	tree_kind[i] = Defs.TreeKind.NONE
	_refresh_nav(c)


## River flow at a 2x2 block: 0 along x, 1 along y, -1 not a straight river block (bend, end, pond, land).
func river_axis(anchor: Vector2i) -> int:
	if not _river_block(anchor) or not in_bounds(anchor):
		return -1
	var step := Defs.ROAD_BLOCK
	var ew := _river_block(anchor + Vector2i(-step, 0)) and _river_block(anchor + Vector2i(step, 0))
	var ns := _river_block(anchor + Vector2i(0, -step)) and _river_block(anchor + Vector2i(0, step))
	if ew == ns:
		return -1
	# at the map edge the river leaves the map: an end block counts as straight
	return 0 if ew else 1


## Every tile of the 2x2 block is river (outside the map counts as river: it flows on).
func _river_block(anchor: Vector2i) -> bool:
	for y in Defs.ROAD_BLOCK:
		for x in Defs.ROAD_BLOCK:
			var c := anchor + Vector2i(x, y)
			if in_bounds(c) and water[idx(c)] != Defs.Water.RIVER:
				return false
	return true


## A bridge block: across a straight river block, banks on both sides, and no other road on the
## river next to it (a bridge never runs along the river or over several blocks).
func bridge_ok(anchor: Vector2i) -> bool:
	var axis := river_axis(anchor)
	if axis == -1:
		return false
	var along := Vector2i(Defs.ROAD_BLOCK, 0) if axis == 0 else Vector2i(0, Defs.ROAD_BLOCK)
	var across := Vector2i(along.y, along.x)
	for side in [-1, 1]:
		var bank: Vector2i = anchor + across * side
		for y in Defs.ROAD_BLOCK:
			for x in Defs.ROAD_BLOCK:
				var c := bank + Vector2i(x, y)
				if not in_bounds(c) or is_water(c) or is_locked(c):
					return false
		var next: Vector2i = anchor + along * side
		var site := building_at(next) as ConstructionSite
		if in_bounds(next) and (road[idx(next)] != 0 or (site != null and site.is_road())):
			return false
	return true


func is_bridge(anchor: Vector2i) -> bool:
	return is_water(anchor)


# --- wide road curves ------------------------------------------------------------
# A road corner with a straight block before and after it and free tiles on the inside of the
# bend is a wide curve over those 2x2 blocks (one model, the road runs between 2 and 4 tiles from
# the far corner of the inside block). The arc covers three tiles of the inside block, which can't
# be built on any more, and leaves the outer tile of the elbow block as grass, which can.

const CURVE_ELBOW := 0b0110        # the wide curve model turns from S to E at rotation 0
const CURVE_R := Vector2(2.0, 4.0) # inner / outer edge of the road, in tiles from the arc centre

var _curves := {}
var _curve_covered := {}           # tile -> true: inside-block tiles under the arc
var _curve_free := {}              # tile -> elbow anchor: elbow-block tiles the arc leaves free
var _curves_dirty := true


## elbow anchor -> [rotation, the two straight blocks it swallows, the inside block,
## covered inside tiles, free elbow tiles]
func wide_curves() -> Dictionary:
	if _curves_dirty:
		_curves_dirty = false
		_curves = _find_wide_curves()
		_curve_covered.clear()
		_curve_free.clear()
		for e: Vector2i in _curves:
			for t: Vector2i in _curves[e][3]:
				_curve_covered[t] = true
			for t: Vector2i in _curves[e][4]:
				_curve_free[t] = e
	return _curves


## Does the arc of a wide curve run over this tile (on the inside of the bend)?
func in_curve(c: Vector2i) -> bool:
	wide_curves()
	return _curve_covered.has(c)


## A road tile of a curve's elbow block that the arc leaves as grass (it can be built on).
func curve_free(c: Vector2i) -> bool:
	wide_curves()
	return _curve_free.has(c)


## Is something built on the free corner of the wide curve whose inside block or road blocks
## include `block`? Changing that block's road would turn the curve back into a small corner
## right under it.
func _curve_corner_used(block: Vector2i) -> bool:
	for e: Vector2i in wide_curves():
		var cv: Array = _curves[e]
		var n1: Vector2i = cv[1][0]
		var n2: Vector2i = cv[1][1]
		var d1 := n1 - e
		var d2 := n2 - e
		# blocks whose road change undoes the curve: its own, the road on past both ends, and the
		# blocks beside it where a new road would turn a curve block into a junction
		var parts: Array[Vector2i] = [e, n1, n2, cv[2], n1 + d1, n2 + d2, e - d1, e - d2, n1 - d2, n2 - d1]
		if not parts.has(block):
			continue
		for t: Vector2i in cv[4]:
			if occupant[idx(t)] != 0:
				return true
	return false


## [inside-block tiles the road band overlaps, elbow-block tiles it does not touch]
func _curve_tiles(e: Vector2i, inside: Vector2i) -> Array:
	var centre := Vector2(inside.x + (2 if inside.x > e.x else 0), inside.y + (2 if inside.y > e.y else 0))
	var covered: Array[Vector2i] = []
	var free: Array[Vector2i] = []
	for blk: Vector2i in [inside, e]:
		for y in Defs.ROAD_BLOCK:
			for x in Defs.ROAD_BLOCK:
				var t := blk + Vector2i(x, y)
				var lo := Vector2(t)
				var hi := lo + Vector2.ONE
				var near := Vector2(clampf(centre.x, lo.x, hi.x), clampf(centre.y, lo.y, hi.y)).distance_to(centre)
				var far := 0.0
				for p in [lo, hi, Vector2(lo.x, hi.y), Vector2(hi.x, lo.y)]:
					far = maxf(far, (p as Vector2).distance_to(centre))
				var on_road := near < CURVE_R.y - 0.05 and far > CURVE_R.x + 0.05
				if blk == inside and on_road:
					covered.append(t)
				elif blk == e and not on_road:
					free.append(t)
	return [covered, free]


func road_mask(anchor: Vector2i) -> int:
	var mask := 0
	for r in 4:
		if road_blocks.has(anchor + Defs.DIRS[r] * Defs.ROAD_BLOCK):
			mask |= 1 << r
	return mask


func _find_wide_curves() -> Dictionary:
	var out := {}
	var used := {}
	var anchors: Array = road_blocks.keys()
	anchors.sort()
	for e: Vector2i in anchors:
		if used.has(e) or is_bridge(e):
			continue
		var m := road_mask(e)
		var r := -1
		for k in 4:
			if Defs.rotate_mask(CURVE_ELBOW, k) == m:
				r = k
		if r == -1:
			continue
		var d1: Vector2i = Defs.DIRS[(1 + r) % 4] * Defs.ROAD_BLOCK
		var d2: Vector2i = Defs.DIRS[(2 + r) % 4] * Defs.ROAD_BLOCK
		var n1 := e + d1
		var n2 := e + d2
		var inside := e + d1 + d2
		if used.has(n1) or used.has(n2) or not _straight_along(n1, d1) or not _straight_along(n2, d2):
			continue
		var tiles := _curve_tiles(e, inside)
		if not _curve_inside_free(tiles[0]):
			continue
		out[e] = [r, [n1, n2], inside, tiles[0], tiles[1]]
		for b in [e, n1, n2]:
			used[b] = true
	return out


## A straight road block running along `d` (connected both ways along it, nothing sideways).
func _straight_along(anchor: Vector2i, d: Vector2i) -> bool:
	if not road_blocks.has(anchor) or is_bridge(anchor):
		return false
	var want := 0
	for r in 4:
		var dir: Vector2i = Defs.DIRS[r] * Defs.ROAD_BLOCK
		if dir == d or dir == -d:
			want |= 1 << r
	return road_mask(anchor) == want


## The tiles the arc would run over on the inside of the bend are free (the far tile may be used).
func _curve_inside_free(tiles: Array[Vector2i]) -> bool:
	for c in tiles:
		if not in_bounds(c) or road[idx(c)] != 0 or occupant[idx(c)] != 0 or is_water(c) or has_tree(c):
			return false
	return true


func road_at(c: Vector2i) -> StringName:
	return SURFACES[road[idx(c)]] if in_bounds(c) else &""


func speed_factor(c: Vector2i) -> float:
	var s := road_at(c)
	if s != &"":
		return Defs.ROAD_SPEED[s]
	if building_at(c) is Field:
		return Defs.FIELD_SPEED
	return 1.0


func set_tree(c: Vector2i, kind: int, stage: int) -> void:
	var i := idx(c)
	tree_kind[i] = kind
	tree_stage[i] = stage
	_refresh_nav(c)
	tree_changed.emit(c)


func remove_tree(c: Vector2i) -> void:
	set_tree(c, Defs.TreeKind.NONE, 0)


func building_at(c: Vector2i) -> Building:
	if not in_bounds(c):
		return null
	return buildings.get(occupant[idx(c)])


func _refresh_nav(c: Vector2i) -> void:
	_curves_dirty = true                 # any change of a tile may make or break a wide curve
	var i := idx(c)
	var b: Building = buildings.get(occupant[i])
	# fields are fenced: walked into only through the gate (Nav pens)
	var blocked_by_building := b != null and not (b is ConstructionSite)
	# water: only bridges (and bridge sites, where the builders stand) can be walked on
	var wet := water[i] != Defs.Water.NONE and road[i] == 0 and not (b is ConstructionSite)
	nav.set_solid(c, tree_kind[i] != Defs.TreeKind.NONE or blocked_by_building or wet)
	nav.set_cost(c, 1.0 / speed_factor(c))


# --- placement -----------------------------------------------------------------

## Price of an object; a road block placed on the river (`anchor` given) also pays for the bridge
## (an upgraded bridge for the difference to the old one).
func cost_of(def_id: StringName, base_size := Vector2i.ZERO, anchor := Vector2i(-1, -1)) -> int:
	if Defs.is_field(def_id):
		return Defs.field_cost(base_size)
	var cost: int = Defs.def(def_id)["cost"]
	if Defs.is_road(def_id) and is_water(anchor):
		cost += Defs.BRIDGE_COST[Defs.def(def_id)["road"]]
		if road_blocks.has(anchor):
			cost -= Defs.BRIDGE_COST.get(road_blocks[anchor], 0)
	return cost


func can_place(def_id: StringName, anchor: Vector2i, rot: int, base_size := Vector2i.ZERO) -> bool:
	if not building_unlocked(def_id):
		return false
	if base_size == Vector2i.ZERO:
		base_size = Defs.def(def_id)["size"]
	if Defs.is_field(def_id) and not Defs.field_size_ok(base_size):
		return false
	if not instant_build and money < cost_of(def_id, base_size, anchor):
		return false
	var fs := Defs.rotated(base_size, rot)
	var road_def := Defs.is_road(def_id)
	if road_def and road_blocks.has(anchor):
		return _upgrade_ok(def_id, anchor)
	var wet := false
	for y in fs.y:
		for x in fs.x:
			var c := anchor + Vector2i(x, y)
			if not in_bounds(c) or is_locked(c) or occupant[idx(c)] != 0:
				return false
			# nothing stands on another building's door or a field's gate (a road may lead to it)
			if not road_def and _access_taken(c):
				return false
			# road tiles are taken, except the grass a wide curve leaves in its elbow block
			if road[idx(c)] != 0 and (road_def or not curve_free(c)):
				return false
			wet = wet or is_water(c)
	if road_def:
		# a road inside a wide curve would undo it: not while something stands in the curve's free corner
		if _curve_corner_used(anchor):
			return false
		return not wet or bridge_ok(anchor)
	if Defs.def(def_id).get("river_side", false):
		if not river_side_ok(anchor, fs, rot):
			return false
	elif wet:
		return false
	# the arc of a wide road curve runs through the block on the inside of the bend
	for y in fs.y:
		for x in fs.x:
			if in_curve(anchor + Vector2i(x, y)):
				return false
	var a := Defs.access_for(base_size, anchor, rot)
	return in_bounds(a) and not is_locked(a) and occupant[idx(a)] == 0 and not is_water(a)


## Water Mill: the footprint column on the wheel side (model +x, turned with the building) lies
## on the river, every other tile on land.
func river_side_ok(anchor: Vector2i, fs: Vector2i, rot: int) -> bool:
	var d := Defs.DIRS[(1 + rot) % 4]
	for y in fs.y:
		for x in fs.x:
			var wheel := (d.x > 0 and x == fs.x - 1) or (d.x < 0 and x == 0) \
				or (d.y > 0 and y == fs.y - 1) or (d.y < 0 and y == 0)
			var c := anchor + Vector2i(x, y)
			if wheel != (water[idx(c)] == Defs.Water.RIVER) or (not wheel and is_water(c)):
				return false
	return true


## A better surface placed over a built road block (no demolishing): only upwards, one site at a time.
func _upgrade_ok(def_id: StringName, anchor: Vector2i) -> bool:
	if SURFACES.find(Defs.def(def_id)["road"]) <= SURFACES.find(road_blocks[anchor]):
		return false
	for y in Defs.ROAD_BLOCK:
		for x in Defs.ROAD_BLOCK:
			if occupant[idx(anchor + Vector2i(x, y))] != 0:
				return false
	return true


## Pays for the object and places a construction site that workers will clear and build.
func place_site(def_id: StringName, anchor: Vector2i, rot: int, base_size := Vector2i.ZERO, crop := &"wheat") -> ConstructionSite:
	if not can_place(def_id, anchor, rot, base_size):
		return null
	var site := ConstructionSite.new(_take_id(), def_id, anchor, rot, base_size)
	site.crop = crop
	if not site.is_road():
		site.number = _next_number(def_id)
	site.paid = 0 if instant_build else cost_of(def_id, site.base_size, anchor)
	if site.is_road() and is_water(anchor):
		site.work_total *= Defs.BRIDGE_WORK
	money -= site.paid
	book("fields" if site.is_field() else ("roads" if site.is_road() else "buildings"), -site.paid)
	stock_changed.emit()
	_open_site(site)
	if instant_build:
		_finish_instantly(site)
	return site


## Developer cheat: a fresh site is done at once: its trees are gone, no work and no material.
func _finish_instantly(site: ConstructionSite) -> void:
	for t in tasks.tasks.duplicate():
		if t.site == site:
			tasks.remove(t)
			if t.worker:
				t.worker.abort(self)
			if t.kind == Task.Kind.CHOP and has_tree(t.cell):
				remove_tree(t.cell)
	_finish_site(site)


## Puts the site on the grid and queues clearing (then delivery / building).
func _open_site(site: ConstructionSite) -> void:
	_occupy(site)
	building_added.emit(site)
	# the footprint and the area around the access point (so it never ends up walled in by forest)
	var clear := site.cells()
	if not site.is_road():
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var a := site.access + Vector2i(dx, dy)
				if in_bounds(a) and not is_locked(a) and not site.rect().has_point(a) and not clear.has(a):
					clear.append(a)
	for c in clear:
		if has_tree(c):
			var t: Task = marked.get(c)
			if t:
				# a tree marked for felling: its task now clears the site
				marked.erase(c)
				t.category = Task.Category.CONSTRUCTION
				site.open_tasks.append(t)
				tree_marked.emit(c)
			else:
				t = Task.new(Task.Kind.CHOP, c, Defs.CHOP_TIME, time)
				_add_site_task(site, t)
			t.site = site
	if site.open_tasks.is_empty():
		_after_clearing(site)


## Instantly adds a finished building (world generation, completed sites).
func add_building(def_id: StringName, anchor: Vector2i, rot: int, level := 1) -> Building:
	var b := Building.new(_take_id(), def_id, anchor, rot)
	b.level = level
	if not Defs.is_road(def_id):
		b.number = _next_number(def_id)
	_register_store(b)
	_occupy(b)
	building_added.emit(b)
	if b.store:
		settle_loose()       # goods waiting for a barn move in
	return b


## Gives a finished storage building its Store (new, or loaded from a save) and caches it in
## `_stores`; a no-op for a building whose def is not storage. Used by `add_building` and the save
## loader so both set a barn's store up the same way.
func _register_store(b: Building, saved := {}) -> void:
	if not Defs.def(b.def_id).get("storage", false):
		return
	b.store = Store.from_dict(saved)
	b.store.kind = Store.Kind.STORAGE
	b.store.owner = b
	b.store.cell = b.access
	_stores.append(b)


func add_field(anchor: Vector2i, rot: int, base_size: Vector2i, crop: StringName, paid := 0) -> Field:
	var f := Field.new(_take_id(), anchor, rot, base_size, crop)
	f.number = _next_number(f.def_id)
	f.paid = paid
	_occupy(f)
	fields.append(f)
	building_added.emit(f)
	for r in f.size.y:
		_queue_row(f, r, Field.RowStep.CULTIVATE)
	return f


func add_road_block(anchor: Vector2i, surface: StringName) -> void:
	road_blocks[anchor] = surface
	road_nav.add_block(anchor)
	var s := SURFACES.find(surface)
	for y in Defs.ROAD_BLOCK:
		for x in Defs.ROAD_BLOCK:
			var c := anchor + Vector2i(x, y)
			road[idx(c)] = s
			_refresh_nav(c)
	road_changed.emit(anchor)


func _occupy(b: Building) -> void:
	buildings[b.id] = b
	_access_dirty = true
	for c in b.cells():
		occupant[idx(c)] = b.id
		_refresh_nav(c)
	if b is Field:
		nav.set_pen(b.id, b.rect(), b.access)
	for c in b.cells() + [b.access]:
		if _pile_at.has(c):
			_move_pile(_pile_at[c])       # out of the new building's way


func _release(b: Building) -> void:
	_stores.erase(b)
	buildings.erase(b.id)
	_access_dirty = true
	if b is ConstructionSite and b.upgrade_of:
		b.upgrade_of.upgrading = null       # an upgrade site takes no tiles
		return
	for c in b.cells():
		occupant[idx(c)] = 0
		_refresh_nav(c)
	if b is Field:
		nav.remove_pen(b.id)


## True when `c` is the access tile (door, field gate) of a building, site or field.
func _access_taken(c: Vector2i) -> bool:
	if _access_dirty:
		_access_dirty = false
		_access_cells.clear()
		for b: Building in buildings.values():
			_access_cells[b.access] = true
	return _access_cells.has(c)


func _take_id() -> int:
	_next_id += 1
	return _next_id - 1


## The lowest positive number not already used by a building, site or field with this def_id
## ("Storage Barn 2" once another Storage Barn holds 1). Roads are not numbered.
func _next_number(def_id: StringName) -> int:
	var used := {}
	for b: Building in buildings.values():
		if b.def_id == def_id:
			used[b.number] = true
	var n := 1
	while used.has(n):
		n += 1
	return n


# --- construction --------------------------------------------------------------

func _add_site_task(site: ConstructionSite, t: Task) -> void:
	site.open_tasks.append(t)
	tasks.add(t)


## Cleared: the material is brought first (the planner plans carry legs while the site is in
## DELIVERY, see `wanted`), then the building starts.
func _after_clearing(site: ConstructionSite) -> void:
	if site.partner or site.by_pickup or not _site_supplied(site):
		# a moved building also waits until the old building is down (and the pickup has brought its materials)
		site.stage = ConstructionSite.Stage.DELIVERY
		site_changed.emit(site)
	else:
		_start_building(site)


## All the site's material is there.
func _site_supplied(site: ConstructionSite) -> bool:
	var mat := site.material()
	for res: StringName in mat:
		if mat[res] - site.delivered.get(res, 0.0) > 0.01:
			return false
	return true


func _start_building(site: ConstructionSite) -> void:
	site.stage = ConstructionSite.Stage.BUILDING
	site_changed.emit(site)
	var n := maxi(1, ceili(site.work_total / Defs.BUILD_CHUNK))
	var spots := _site_spots(site)
	for i in n:
		var spot: Vector2i = spots[i % spots.size()] if not spots.is_empty() else site.anchor
		var t := Task.new(Task.Kind.BUILD, spot, site.work_total / n, time)
		t.site = site
		_add_site_task(site, t)


## Where workers stand while building: roads and fields on the site itself, buildings around it.
func _site_spots(site: ConstructionSite) -> Array[Vector2i]:
	if site.is_road():
		return site.cells()
	var out: Array[Vector2i] = []
	# fences are built from the edge tiles inside the field, walls from the tiles around
	var r := site.rect() if site.is_field() else site.rect().grow(1)
	for x in range(r.position.x, r.end.x):
		out.append(Vector2i(x, r.position.y))
		out.append(Vector2i(x, r.end.y - 1))
	for y in range(r.position.y + 1, r.end.y - 1):
		out.append(Vector2i(r.position.x, y))
		out.append(Vector2i(r.end.x - 1, y))
	out.shuffle()
	return out


func _finish_site(site: ConstructionSite) -> void:
	if site.upgrade_of:
		_finish_upgrade(site)
		return
	_release(site)
	building_removed.emit(site)
	if site.dismantle:
		_finish_dismantle(site)
	elif site.is_road():
		add_road_block(site.anchor, Defs.def(site.def_id)["road"])
	elif site.is_field():
		var f := add_field(site.anchor, site.rot, site.base_size, site.crop, site.paid)
		f.number = site.number
		f.custom_name = site.custom_name
	else:
		var b := add_building(site.def_id, site.anchor, site.rot, site.level)
		b.number = site.number
		b.custom_name = site.custom_name
		b.paid = site.paid
		b.materials = site.delivered.duplicate()
		if site.moved:
			b.priority = site.priority
			_rehome_vehicles(site, b)
			for res: StringName in site.pile:
				put_goods(res, site.pile[res], site.access)   # a rest of the pile (if any) to the barn
			stock_changed.emit()


# --- fields --------------------------------------------------------------------

func _queue_row(f: Field, row: int, step: Field.RowStep) -> void:
	f.row_step[row] = step
	f.row_task[row] = null
	if step == Field.RowStep.GROW:
		return
	if step == Field.RowStep.SEED and f.next_crop != f.crop:
		_try_switch_crop(f)       # the row waits until the whole field can switch to the new crop
		return
	var key: StringName = [&"cultivate", &"seed", &"", &"harvest"][step]
	var cells := f.row_cells(row)
	if step == Field.RowStep.HARVEST:
		cells = cells.filter(func(c: Vector2i) -> bool: return f.tile_state[f.local(c)] == Field.TileState.PLANTED)
	var t := Task.new(Task.Kind.FIELD, cells[0], Defs.FIELD_WORK[key], time)
	t.category = Task.Category.HARVEST if step == Field.RowStep.HARVEST else Task.Category.PLANTING
	t.field = f
	t.step = key
	t.row = row
	t.cells = cells
	if step == Field.RowStep.SEED:
		t.fetch = Defs.seed_of(f.crop)
		t.fetch_amount = cells.size() * Defs.seed_per_tile(f.crop)
	f.row_task[row] = t
	tasks.add(t)


func field_cell_done(t: Task, c: Vector2i) -> void:
	var f := t.field
	var i := f.local(c)
	match t.step:
		&"cultivate":
			f.tile_state[i] = Field.TileState.CULTIVATED
		&"seed":
			f.tile_state[i] = Field.TileState.PLANTED
			f.growth[i] = 0.0
		&"harvest":
			f.tile_state[i] = Field.TileState.STUBBLE
			f.growth[i] = 0.0
			f.pile += Defs.CROPS[f.crop]["yield"]      # the planner has it carried away (Planner._plan_clear)
	f.dirty = true


func _grow_fields(dt: float) -> void:
	for f in fields:
		var rate := dt / float(Defs.CROPS[f.crop]["grow_time"])
		for i in f.growth.size():
			if f.tile_state[i] == Field.TileState.PLANTED and f.growth[i] < 1.0:
				f.growth[i] = minf(1.0, f.growth[i] + rate)
		for r in f.size.y:
			if f.row_step[r] == Field.RowStep.GROW and f.row_ripe(r):
				_queue_row(f, r, Field.RowStep.HARVEST)
			elif f.row_step[r] == Field.RowStep.SEED and _sown_part_ripe(f, r):
				# a partly sown row (seed ran out): the ripe part is harvested, the rest waits for next time
				tasks.remove(f.row_task[r])
				_queue_row(f, r, Field.RowStep.HARVEST)


## Partly sown row whose sown tiles are all ripe and nobody is sowing the rest right now.
func _sown_part_ripe(f: Field, r: int) -> bool:
	var t: Task = f.row_task[r]
	if t == null or t.worker != null:
		return false
	var planted := false
	for c in f.row_cells(r):
		var i := f.local(c)
		if f.tile_state[i] == Field.TileState.PLANTED:
			if f.growth[i] < 1.0:
				return false
			planted = true
	return planted


## Crop for the next sowing (info panel). The switch happens once the current crop is gone.
func set_field_crop(f: Field, crop: StringName) -> void:
	f.next_crop = crop
	_try_switch_crop(f)


## Access tile of the field's gate on this side (side = rotation, like R when placing).
func field_gate_cell(f: Field, side: int) -> Vector2i:
	return Defs.access_for(Defs.rotated(f.size, side), f.anchor, side)


## The gate can go on this side: the tile in front of it is on the map, outside the border forest
## and walkable (no tree, building or water). Not while the pickup is collecting the harvest here.
func field_gate_ok(f: Field, side: int) -> bool:
	var a := field_gate_cell(f, side)
	if not in_bounds(a) or is_locked(a) or nav.is_solid(a) or occupant[idx(a)] != 0:
		return false
	return not (_trip_task and _trip_task.field == f)


## The side for a new field's gate: of the sides whose gate tile is free (on the map, no building,
## water or other gate), the one nearest a road, or nearest a barn when there is no road yet.
## `fallback` when no side is free.
func field_gate_side(r: Rect2i, fallback := 0) -> int:
	var best := fallback
	var best_d := INF
	for side in 4:
		var a := Defs.access_for(Defs.rotated(r.size, side), r.position, side)
		if not in_bounds(a) or is_locked(a) or occupant[idx(a)] != 0 or is_water(a) or _access_taken(a):
			continue
		var d := INF
		for anchor: Vector2i in road_blocks:
			d = minf(d, Vector2(a).distance_squared_to(Vector2(anchor) + Vector2.ONE))
		if road_blocks.is_empty():
			for b in _stores:
				d = minf(d, Vector2(a).distance_squared_to(b.access))
		if d < best_d:
			best_d = d
			best = side
	return best

## Moves the field's gate to another side. The harvest pile moves with it (it is one heap at the
## gate); carry legs fetch it at the new gate. Returns false if the side is not possible.
func set_field_gate(f: Field, side: int) -> bool:
	side = posmod(side, 4)
	if side == f.rot:
		return true
	if not field_gate_ok(f, side):
		return false
	f.rot = side
	f.base_size = Defs.rotated(f.size, side)
	f.access = field_gate_cell(f, side)
	f.gate_store.cell = f.access
	_access_dirty = true
	nav.set_pen(f.id, f.rect(), f.access)
	f.dirty = true
	field_changed.emit(f)
	return true


## Switches the field to its next crop when nothing of the old one is left: no growing row,
## no pile at the gate and nobody sowing right now. Rows waiting for seed are re-queued;
## tiles of a partly sown row are sown again with the new crop.
func _try_switch_crop(f: Field) -> void:
	if f.next_crop == f.crop or f.pile > 0.01:
		return
	for r in f.size.y:
		if f.row_step[r] == Field.RowStep.GROW or f.row_step[r] == Field.RowStep.HARVEST:
			return
	for r in f.size.y:
		var t: Task = f.row_task[r]
		if t and t.step == &"seed" and t.worker:
			return
	var rest := f.pile                 # a crumb below the switch threshold stays as the new crop's
	f.gate_store.contents.clear()
	f.crop = f.next_crop
	f.pile = rest
	for r in f.size.y:
		if f.row_step[r] != Field.RowStep.SEED:
			continue
		for c in f.row_cells(r):
			if f.tile_state[f.local(c)] == Field.TileState.PLANTED:
				f.tile_state[f.local(c)] = Field.TileState.CULTIVATED
				f.growth[f.local(c)] = 0.0
		var t: Task = f.row_task[r]
		if t:
			tasks.remove(t)
		_queue_row(f, r, Field.RowStep.SEED)
	f.dirty = true
	field_changed.emit(f)


# --- demolition ----------------------------------------------------------------

## Why the building can't be demolished right now, or "" if it can.
func demolish_blocker(b: Building) -> String:
	if b.def_id == &"dealer":
		return "The Dealer is not yours"
	if b is ConstructionSite:
		if b.partner == null and _has_vehicle(b):
			return "The pickup waits for this garage"   # the old garage is already taken down
		return ""
	if Defs.def(b.def_id).get("storage", false) and _stores.size() <= 1:
		return "The farm needs at least one Storage Barn"
	for v in vehicles:
		if v.garage == b:
			return "The pickup belongs to this garage"
	if b is Field and _trip_task and _trip_task.field == b:
		return "The pickup is collecting the harvest here"
	return ""


## A store is leaving `_stores` (demolished or moved away): empty it for real into the other stores
## (or loose), and free anyone who had claimed goods in it, so their task is re-picked instead of a
## worker fetching from (or walking to) a barn that is no longer there.
func _empty_store(b: Building) -> void:
	if b.store == null:
		return
	_stores.erase(b)                    # first, so nobody brings anything back here
	_drop_legs(b)
	var held := b.store.contents.duplicate()
	for res: StringName in held:
		put_goods(res, b.store.take(res, held[res]), b.access)      # to the nearest other barn, or loose
	for t in tasks.tasks:
		if t.fetch_from == b.store:
			release_fetch(t)
			if t.worker:
				var w := t.worker
				t.worker = null
				t.retry_at = time + 3.0
				w.task = null
				w.path.clear()
				w.phase = Worker.Phase.IDLE


## The places of `b` are going away: carry legs still to fetch from them, bring to them or take a
## wheelbarrow from them are dropped with all their claims, and their workers bring back what they
## carry. A worker who already has goods from such a place carries them on to their destination.
func _drop_legs(b: Building) -> void:
	for t in tasks.tasks.duplicate():
		if t.kind != Task.Kind.CARRY:
			continue
		if (t.fetch_from and t.fetch_from.owner == b) or (t.dst and t.dst.owner == b) \
				or (t.tool_from and t.tool_from.owner == b):
			tasks.remove(t)
			if t.worker:
				t.worker.abort(self)


## Demolishes instantly with a full refund of what was paid. Work on it is called off;
## crops and the pile at the gate are lost. Returns false if it is not allowed.
func demolish(b: Building) -> bool:
	if demolish_blocker(b) != "":
		return false
	if b is ConstructionSite and b.partner:
		_cancel_move(b)
		return true
	if b.store == null:
		_drop_legs(b)                   # a barn drops its legs once it is out of the stores (_empty_store)
	for t in tasks.tasks.duplicate():
		if t.kind == Task.Kind.TRIP and t.site == b:
			continue                    # a pickup haul for a moved building brings its load to the barn instead
		if t.site == b or t.field == b or t.building == b:
			tasks.remove(t)
			if t.worker:
				t.worker.abort(self)
	money += b.paid
	book("refunds", b.paid)
	if b is ConstructionSite:
		for res: StringName in b.delivered:
			put_goods(res, b.delivered[res], b.access)   # material on the site goes back to the barn
		for res: StringName in b.pile:
			put_goods(res, b.pile[res], b.access)        # and so does a moved building's pile
		b.pile.clear()
	else:
		if b.upgrading:
			demolish(b.upgrading)
		for res: StringName in b.materials:
			put_goods(res, b.materials[res], b.access)   # so do the building's materials
		var r := b.recipe()
		if not r.is_empty():
			# and the goods inside a mill (nothing is ever lost)
			put_goods(r["in"], b.input, b.access)
			put_goods(r["out"], b.output, b.access)
	_empty_store(b)
	_release(b)
	if b is Field:
		fields.erase(b)
	building_removed.emit(b)
	stock_changed.emit()
	return true


func road_blocker(anchor: Vector2i) -> String:
	for v in vehicles:
		if not v.parked:
			return "Wait until the pickup is back in the garage"
	if building_at(anchor) is ConstructionSite:
		return "The road is being upgraded — cancel the construction first"
	if _curve_corner_used(anchor):
		return "Something stands in the bend of this road"
	return ""


func demolish_road(anchor: Vector2i) -> bool:
	if not road_blocks.has(anchor) or road_blocker(anchor) != "":
		return false
	road_blocks.erase(anchor)
	road_nav.remove_block(anchor)
	for y in Defs.ROAD_BLOCK:
		for x in Defs.ROAD_BLOCK:
			var c := anchor + Vector2i(x, y)
			road[idx(c)] = 0
			_refresh_nav(c)
	road_changed.emit(anchor)
	return true


# --- felling -------------------------------------------------------------------
# The player marks trees with the axe (Cut trees tool). Each marked tree is a CHOP task in the
# Felling category: a worker chops it and carries the log to the barn. Always possible, so it is
# the fallback income (docs 06, bankruptcy protection).

## Trees in the rectangle that marking (unmark: unmarking) would change: marking takes trees
## outside the locked border forest that are not marked yet and not being cleared for a site.
func trees_to_mark(r: Rect2i, unmark := false) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var site_chops := {}
	if not unmark:
		for t in tasks.tasks:
			if t.kind == Task.Kind.CHOP and t.site:
				site_chops[t.cell] = true
	var area := r.intersection(Rect2i(0, 0, size, size))
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var c := Vector2i(x, y)
			if unmark:
				if marked.has(c):
					out.append(c)
			elif has_tree(c) and not is_locked(c) and not marked.has(c) and not site_chops.has(c):
				out.append(c)
	return out


## Marks the trees in the rectangle for felling; returns how many.
func mark_trees(r: Rect2i) -> int:
	var cells := trees_to_mark(r)
	for c in cells:
		var t := Task.new(Task.Kind.CHOP, c, Defs.CHOP_TIME, time)
		t.category = Task.Category.FELLING
		marked[c] = t
		tasks.add(t)
		tree_marked.emit(c)
	return cells.size()


## Removes the marks (and their tasks) in the rectangle; returns how many.
func unmark_trees(r: Rect2i) -> int:
	var cells := trees_to_mark(r, true)
	for c in cells:
		var t: Task = marked[c]
		marked.erase(c)
		tasks.remove(t)
		if t.worker:
			t.worker.abort(self)
		tree_marked.emit(c)
	return cells.size()


# --- moving buildings ----------------------------------------------------------
# A building moves in two linked construction sites (see docs 02 "Moving buildings"): a dismantle
# site on the old spot (build work = taking it down) and a site on the new spot that needs the
# materials the building is made of. Taking it down leaves those materials as a pile at the old
# spot; workers carry them straight to the new site (the pickup hauls them on longer moves).
# The finished building keeps its level and priority. Nothing is charged.

## Why the building can't be moved right now, or "" if it can.
func move_blocker(b: Building) -> String:
	if b.def_id == &"dealer":
		return "The Dealer is not yours"
	if b is Field:
		return "Fields can't be moved"
	if b is ConstructionSite:
		return "Finish or cancel the construction first"
	if b.upgrading:
		return "Being upgraded — wait for the upgrade or cancel it"
	if Defs.def(b.def_id).get("storage", false) and _stores.size() <= 1:
		return "The farm needs another Storage Barn to keep the goods meanwhile"
	for v in vehicles:
		if v.garage == b and (not v.parked or (_trip_task != null and _trip_task.worker != null)):
			return "Wait until the pickup is back in the garage"
	return ""


## The building can move to this spot (same placement rules as building it; not over its old spot).
func can_move(b: Building, anchor: Vector2i, rot: int) -> bool:
	return move_blocker(b) == "" and can_place(b.def_id, anchor, rot)


## Starts moving the building. Its goods go to the barn and its work is called off; returns the
## new site (its partner is the dismantle site on the old spot), or null if not possible.
func move_building(b: Building, anchor: Vector2i, rot: int) -> ConstructionSite:
	if not can_move(b, anchor, rot):
		return null
	if b.store == null:
		_drop_legs(b)                   # a barn: see _empty_store
	for t in tasks.tasks.duplicate():
		if t.building == b:
			tasks.remove(t)
			if t.worker:
				t.worker.abort(self)
	var r := b.recipe()
	if not r.is_empty():
		put_goods(r["in"], b.input, b.access)
		put_goods(r["out"], b.output, b.access)
	if _trip_task and _trip_task.worker == null and _trip_task.vehicle.garage == b:
		tasks.remove(_trip_task)            # a trip nobody has started waits for the new garage
		_trip_task = null
	_empty_store(b)
	_release(b)
	building_removed.emit(b)
	var old := ConstructionSite.new(_take_id(), b.def_id, b.anchor, b.rot)
	old.dismantle = true
	old.level = b.level
	old.materials = b.materials.duplicate()
	old.priority = b.priority
	old.number = b.number                # the moved building keeps its number and name: the new
	old.custom_name = b.custom_name       # site gets them, the dismantle site shows them too
	old.work_total = float(Defs.def(b.def_id)["build_work"]) * Defs.DISMANTLE_WORK
	var site := ConstructionSite.new(_take_id(), b.def_id, anchor, rot)
	site.moved = true
	site.needs = b.materials.duplicate()
	site.level = b.level
	site.paid = b.paid                  # refunded if the moved building is demolished later
	site.priority = b.priority
	site.number = b.number
	site.custom_name = b.custom_name
	old.partner = site
	site.partner = old
	_occupy(old)
	building_added.emit(old)
	_start_building(old)
	_rehome_vehicles(b, old)
	_open_site(site)
	stock_changed.emit()
	return site


## The old building is down: its materials lie at the old spot for the new site.
func _finish_dismantle(old: ConstructionSite) -> void:
	var site := old.partner
	if site == null:
		return
	site.partner = null
	site.pile = old.materials.duplicate()
	site.pile_cell = old.access
	_rehome_vehicles(old, site)
	site.by_pickup = _pickup_hauls(site)
	site_changed.emit(site)
	if site.open_tasks.is_empty() and not site.by_pickup:
		_after_clearing(site)


## Cancels a move whose old building still stands (either of the two sites): the building is put
## back as it was, with its level, materials and priority.
func _cancel_move(s: ConstructionSite) -> void:
	var old := s if s.dismantle else s.partner
	var site := old.partner
	_drop_legs(site)
	for t in tasks.tasks.duplicate():
		if t.site == old or t.site == site:
			tasks.remove(t)
			if t.worker:
				t.worker.abort(self)
	for res: StringName in site.delivered:
		put_goods(res, site.delivered[res], site.access)
	for x: ConstructionSite in [old, site]:
		_release(x)
		building_removed.emit(x)
	var b := add_building(old.def_id, old.anchor, old.rot, old.level)
	b.number = old.number
	b.custom_name = old.custom_name
	b.materials = old.materials
	b.paid = site.paid
	b.priority = old.priority
	_rehome_vehicles(old, b)
	stock_changed.emit()


func _has_vehicle(b: Building) -> bool:
	for v in vehicles:
		if v.garage == b:
			return true
	return false


## The pickup belongs to the garage in its new place (the old one, the sites, the new building).
func _rehome_vehicles(from: Building, to: Building) -> void:
	for v in vehicles:
		if v.garage != from:
			continue
		v.garage = to
		if v.parked:
			var block: Variant = road_nav.block_near(to.access)
			v.block = block if block != null else to.access
			v.pos = v.parking_pos()
			var d := Vector2(Defs.DIRS[to.rot])
			v.heading = atan2(d.x, -d.y)
		if not (to is ConstructionSite) and _trip_task == null:
			trip_status = "In the garage"


## Longer moves: the pickup hauls the pile when both spots are by a road it can reach and the
## walk between them is longer than Defs.MOVE_PICKUP_WALK.
func _pickup_hauls(site: ConstructionSite) -> bool:
	if vehicles.is_empty() or site.pile.is_empty():
		return false
	var v := vehicles[0]
	if v.garage is ConstructionSite:
		return false
	var a: Variant = road_nav.block_near(site.pile_cell)
	var b: Variant = road_nav.block_near(site.access)
	if a == null or b == null or road_nav.route(v.block, a).is_empty() or road_nav.route(a, b).is_empty():
		return false
	return nav.find_path(site.pile_cell, site.access).size() > Defs.MOVE_PICKUP_WALK


## A moved building whose pile waits for the pickup, or null.
func _site_for_pickup() -> ConstructionSite:
	for b: Building in buildings.values():
		if b is ConstructionSite and b.by_pickup and not b.pile.is_empty():
			return b
	return null


## Pickup run for a moved building: old spot → new site, back to the garage.
func _plan_haul(t: Task) -> bool:
	var v := t.vehicle
	var s := t.site
	var a: Variant = road_nav.block_near(s.pile_cell)
	var b: Variant = road_nav.block_near(s.access)
	if not buildings.has(s.id) or a == null or b == null or road_nav.route(v.block, a).is_empty() \
			or road_nav.route(a, b).is_empty():
		trip_status = "Can't reach the moved building by road"
		return false
	t.steps.append({"type": "board"})
	t.steps.append({"type": "drive", "block": a, "status": "Driving to the old spot of the %s" % s.display_name().get_slice(" (", 0)})
	t.steps.append({"type": "load_pile"})
	t.steps.append({"type": "drive", "block": b, "status": "Bringing the materials to the new site"})
	t.steps.append({"type": "unload_site"})
	t.steps.append({"type": "drive", "block": v.block, "status": "Returning to the garage"})
	t.steps.append({"type": "park"})
	return true


## The pickup is done with (or can't do) a moved building's pile: the rest goes by hand.
func _after_pickup(site: ConstructionSite) -> void:
	site.by_pickup = false
	if buildings.has(site.id) and site.open_tasks.is_empty() and site.stage != ConstructionSite.Stage.BUILDING:
		_after_clearing(site)


## Walkable tile where a worker stands to put goods into the store or take them out, or null: its
## cell, next to it if something was built there meanwhile (a moved building's pile); material for
## a construction site is put down on the site itself (its anchor tile), else at one of the usual
## site spots.
func store_spot(s: Store) -> Variant:
	if s.kind == Store.Kind.SITE and s.owner and nav.is_walkable(s.owner.anchor):
		return s.owner.anchor
	if nav.is_walkable(s.cell):
		return s.cell
	if s.kind == Store.Kind.SITE and s.owner is ConstructionSite:
		for c in _site_spots(s.owner):
			if nav.is_walkable(c):
				return c
		return null
	for d in Defs.DIRS:
		if nav.is_walkable(s.cell + d):
			return s.cell + d
	return null


## What a seed row can fetch right now: its claim, or the most any single store can give.
func fetch_have(t: Task) -> float:
	if t.fetch_from:
		return t.fetch_reserved
	var best := 0.0
	for b in _stores:
		best = maxf(best, b.store.available(t.fetch))
	return best


## Claims the seed row's seed and returns the access tile to fetch it from: the store cheapest to
## walk from to the row (Nav.walk_cost) holding the whole `fetch_amount`, failing that one with at
## least `fetch_min`. Null when nothing fits.
func claim_fetch(t: Task, from: Vector2i) -> Variant:
	release_fetch(t)
	var b := _nearest_store(t, from, t.fetch_amount)
	if b == null and fetch_min(t) < t.fetch_amount:
		b = _nearest_store(t, from, fetch_min(t))
	if b == null:
		return null
	t.fetch_from = b.store
	t.fetch_reserved = b.store.reserve_out(t.fetch, t.fetch_amount)
	return b.access


## The store holding at least `need` of the task's good that is cheapest to walk from to the task,
## and that the worker can reach.
func _nearest_store(t: Task, from: Vector2i, need: float) -> Building:
	var order := _stores.filter(func(b: Building) -> bool:
		return b.store.available(t.fetch) >= need - 0.000001 and nav.walk_cost(b.access, t.cell) < INF)
	order.sort_custom(func(a: Building, b: Building) -> bool:
		return nav.walk_cost(a.access, t.cell) < nav.walk_cost(b.access, t.cell))
	for b: Building in order:
		if not nav.find_path(from, b.access).is_empty():
			return b
	return null


## A worker takes a waiting carry leg: the way to its goods (or first to a barn for a wheelbarrow,
## see `_take_wheelbarrow`) is set as the worker's path. False when the worker can't get there.
func claim_leg(t: Task, w: Worker, from: Vector2i) -> bool:
	if t.fetch_from == null:
		return false
	var spot: Variant = store_spot(t.fetch_from)
	if spot == null:
		return false
	var path := nav.find_path(from, spot)
	if path.is_empty():
		return false
	if t.fetch_from.kind == Store.Kind.GATE and t.tool_from == null:
		var barn_path := _take_wheelbarrow(t, from)
		if not barn_path.is_empty():
			path = barn_path
	w.set_path(path)
	return true


## A leg from a field gate with a backlog of at least two hand loads: claims a wheelbarrow in the
## barn nearest the gate and takes over other waiting legs from the same gate to the same place up
## to the wheelbarrow's capacity (with their claims). Returns the worker's path to that barn, or
## an empty path when it does not pay off or there is no wheelbarrow to have.
func _take_wheelbarrow(t: Task, from: Vector2i) -> Array[Vector2i]:
	var none: Array[Vector2i] = []
	var src := t.fetch_from
	var backlog := src.available(t.fetch)
	for o in tasks.tasks:
		if o.kind == Task.Kind.CARRY and o.worker == null and o.fetch_from == src:
			backlog += o.fetch_reserved
	if backlog < 2.0 * Defs.hand_load(t.fetch) - 0.01:
		return none
	var gate: Variant = store_spot(src)
	var barn: Building = null
	var best := INF
	for b in _stores:
		if b.store.available(&"wheelbarrow") >= 1.0 - 0.000001:
			var c := nav.walk_cost(b.access, gate)
			if c < best:
				best = c
				barn = b
	if barn == null:
		return none
	var path := nav.find_path(from, barn.access)
	if path.is_empty():
		return none
	barn.store.reserve_out(&"wheelbarrow", 1.0)
	t.tool_from = barn.store
	for o in tasks.tasks.duplicate():
		if o != t and o.kind == Task.Kind.CARRY and o.worker == null and o.fetch_from == src and o.dst == t.dst \
				and o.fetch == t.fetch and t.fetch_amount + o.fetch_amount <= Defs.WHEELBARROW_CAPACITY + 0.01:
			t.fetch_amount += o.fetch_amount
			t.fetch_reserved += o.fetch_reserved
			t.dst_reserved += o.dst_reserved
			o.fetch_from = null             # the claims move over to this leg
			o.dst = null
			tasks.remove(o)
	return path


## At the barn: the worker takes the claimed wheelbarrow (none if it is gone; the leg goes on by hand).
func take_tool(t: Task, w: Worker) -> void:
	var s := t.tool_from
	if s == null:
		return
	s.release_out(&"wheelbarrow", 1.0)
	t.tool_from = null
	var got := s.take(&"wheelbarrow", 1.0)
	if got >= 1.0 - 0.000001:
		w.equipment = &"wheelbarrow"
		stock_changed.emit()
	elif got > 0.0:
		s.put(&"wheelbarrow", got)        # a partial take: give it back, no phantom tool


func release_fetch(t: Task) -> void:
	if t.fetch_from:
		t.fetch_from.release_out(t.fetch, t.fetch_reserved)
	t.fetch_from = null
	t.fetch_reserved = 0.0


## Built road block containing the tile, or null.
func road_block_at(c: Vector2i) -> Variant:
	var b := Vector2i(c.x & ~1, c.y & ~1)
	return b if road_blocks.has(b) else null


# --- tasks ---------------------------------------------------------------------

## A walkable tile from which the task can be done, or null.
func work_spot(t: Task, from: Vector2i) -> Variant:
	match t.kind:
		Task.Kind.CHOP:
			var best: Variant = null
			var best_d := INF
			for d in Defs.DIRS:
				var c := t.cell + d
				if nav.is_walkable(c):
					var dist := Vector2(from).distance_squared_to(c)
					if dist < best_d:
						best_d = dist
						best = c
			return best
		Task.Kind.BUILD:
			if nav.is_walkable(t.cell):
				return t.cell
			if t.site == null:
				return null
			for c in _site_spots(t.site):
				if nav.is_walkable(c):
					t.cell = c
					return c
		Task.Kind.CARRY:
			if nav.is_walkable(t.cell):
				return t.cell
			var spot: Variant = store_spot(t.dst) if t.dst else null
			if spot != null:
				t.cell = spot
			return spot
		Task.Kind.FIELD, Task.Kind.TRIP, Task.Kind.HELP, Task.Kind.PROCESS:
			if nav.is_walkable(t.cell):
				return t.cell
	return null


func complete_task(t: Task, w: Worker) -> void:
	tasks.remove(t)
	match t.kind:
		Task.Kind.CHOP:
			if t.site == null:
				marked.erase(t.cell)            # a tree marked for felling
				tree_marked.emit(t.cell)
			remove_tree(t.cell)
			# the logs are left on the ground for the planner; with nowhere to put them down the
			# worker carries them to the barn
			var cat := Task.Category.CONSTRUCTION if t.site else Task.Category.FELLING
			if drop_goods(&"wood", Defs.WOOD_PER_TREE, w.cell(), cat) == null:
				w.carrying = &"wood"
				w.carry_amount = Defs.WOOD_PER_TREE
			if t.site:
				t.site.open_tasks.erase(t)
				if t.site.open_tasks.is_empty():
					_after_clearing(t.site)
		Task.Kind.CARRY:
			_put_carried(t, w)
		Task.Kind.PROCESS:
			var b := t.building
			b.input -= t.amount
			b.output += t.amount * float(b.recipe()["yield"])
			b.process_task = null
			_update_building(b)
		Task.Kind.BUILD:
			t.site.open_tasks.erase(t)
			t.site.work_done += t.work
			site_changed.emit(t.site)
			if t.site.open_tasks.is_empty():
				_finish_site(t.site)
		Task.Kind.FIELD:
			var f := t.field
			match t.step:
				&"cultivate":
					_queue_row(f, t.row, Field.RowStep.SEED)
				&"seed":
					if f.row_task[t.row] == t:   # otherwise the rest of the row still waits for seed
						_queue_row(f, t.row, Field.RowStep.GROW)
					w.carrying = &""          # the seed sack is used up
					w.carry_amount = 0.0
				&"harvest":
					_queue_row(f, t.row, Field.RowStep.CULTIVATE)
					_try_switch_crop(f)


## The end of a carry leg: the goods go into the destination (its claim was released with the
## task) and its owner reacts: a site with all its material starts building, a mill gets to work.
## A wheelbarrow brought to a barn stays there. A destination that is gone meanwhile: the goods go
## to the nearest barn.
func _put_carried(t: Task, w: Worker) -> void:
	var d := t.dst
	var res := w.carrying
	var n := w.carry_amount
	w.carrying = &""
	w.carry_amount = 0.0
	var owner := d.owner
	var here: bool = owner != null and buildings.get(owner.id) == owner
	match d.kind:
		Store.Kind.SITE:
			if here:
				d.put(res, n)
				var site := owner as ConstructionSite
				site_changed.emit(site)
				if site.stage == ConstructionSite.Stage.DELIVERY and not site.partner and not site.by_pickup \
						and site.open_tasks.is_empty() and _site_supplied(site):
					_start_building(site)
			else:
				put_goods(res, n, w.cell())
		Store.Kind.INPUT:
			if here and owner.input_store == d:
				d.put(res, n)
				_update_building(owner)
			else:
				put_goods(res, n, w.cell())
		Store.Kind.STORAGE:
			if _stores.has(owner):
				d.put(res, n)
				if w.equipment != &"":
					d.put(w.equipment, 1.0)
					w.equipment = &""
			else:
				put_goods(res, n, w.cell())
		_:
			d.put(res, n)
	stock_changed.emit()


# --- goods in places -----------------------------------------------------------

## Every place on the map that holds goods: barns, site supplies and moved buildings' piles, mill
## inputs and outputs, field gate piles, ground piles. Built on demand (not cached).
func places() -> Array[Store]:
	var out: Array[Store] = []
	for b: Building in buildings.values():
		if b is ConstructionSite:
			out.append(b.supply)
			if b.moved:
				out.append(b.pile_store)
		elif b is Field:
			out.append(b.gate_store)
		else:
			for s: Store in [b.store, b.input_store, b.output_store]:
				if s:
					out.append(s)
	out.append_array(ground_piles)
	return out


## Puts goods down on the ground at `cell` (felled logs, what a worker carried when the leg broke):
## onto a pile of the same good and category within GROUND_PILE_REACH tiles that has room, else
## onto a new pile on the nearest free tile within GROUND_PILE_SEARCH (not on a building, site or
## field, water or a door / gate; roads are fine). The planner clears ground piles like any other
## place. Returns the pile, or null when there is no free tile near (the caller keeps the goods).
func drop_goods(res: StringName, n: float, cell: Vector2i, category: int) -> Store:
	if n <= 0.0:
		return null
	var kg := Defs.weight(res, n)
	var pile: Store = null
	var best := INF
	var reach := Defs.GROUND_PILE_REACH
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var s: Store = _pile_at.get(cell + Vector2i(dx, dy))
			if s and s.category == category and s.accepts(res) and s.room() >= kg - 0.000001 \
					and dx * dx + dy * dy < best:
				best = dx * dx + dy * dy
				pile = s
	if pile:
		pile.put(res, n)
		pile_changed.emit(pile)
		return pile
	var spot: Variant = _pile_spot(cell)
	if spot == null:
		return null
	pile = Store.new(Store.Kind.GROUND, null, spot)
	pile.capacity = Defs.GROUND_PILE_CAPACITY
	pile.filter = {res: true}
	pile.category = category
	pile.put(res, n)
	add_ground_pile(pile)
	return pile


## Registers a ground pile (a new one, or one loaded from a save).
func add_ground_pile(s: Store) -> void:
	ground_piles.append(s)
	_pile_at[s.cell] = s
	pile_added.emit(s)


## The nearest tile to `cell` a new ground pile may lie on, or null.
func _pile_spot(cell: Vector2i) -> Variant:
	for r in Defs.GROUND_PILE_SEARCH + 1:
		var best: Variant = null
		var best_d := INF
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue                    # only the ring at distance r
				var c := cell + Vector2i(dx, dy)
				var d := float(dx * dx + dy * dy)
				if d < best_d and _pile_ok(c):
					best_d = d
					best = c
		if best != null:
			return best
	return null


func _pile_ok(c: Vector2i) -> bool:
	if not in_bounds(c) or _pile_at.has(c):
		return false
	var i := idx(c)
	return occupant[i] == 0 and water[i] == Defs.Water.NONE and nav.is_walkable(c) and not _access_taken(c)


## After goods were taken from a ground pile: an empty pile is removed.
func _pile_taken(s: Store) -> void:
	if s.contents.is_empty():
		_remove_pile(s)
	else:
		pile_changed.emit(s)


## The pile goes away: legs still to fetch from it are dropped (their claims released, the
## planner plans again).
func _remove_pile(s: Store) -> void:
	ground_piles.erase(s)
	_pile_at.erase(s.cell)
	for t in tasks.tasks.duplicate():
		if t.kind == Task.Kind.CARRY and (t.fetch_from == s or t.dst == s):
			tasks.remove(t)
			if t.worker:
				t.worker.abort(self)
	pile_removed.emit(s)


## A building (site, field) now stands on the pile's tile: the goods are put down again beside it
## (into the barn when there is no free tile near).
func _move_pile(s: Store) -> void:
	_remove_pile(s)
	for res: StringName in s.contents.keys():
		var n := s.take(res, INF)
		if drop_goods(res, n, s.cell, s.category) == null:
			put_goods(res, n, s.cell)


## Do not modify the returned array — it is `_stores` itself, not a copy.
func stores() -> Array[Building]:
	return _stores


func total(res: StringName) -> float:
	var n := loose.amount(res)
	for b in _stores:
		n += b.store.amount(res)
	return n


func totals() -> Dictionary:
	var out := {}
	for res in GOODS:
		out[res] = total(res)
	for s: Store in [loose] + _stores.map(func(b: Building) -> Store: return b.store):
		for res: StringName in s.contents:
			if not out.has(res):
				out[res] = total(res)
	return out


## Where the good is: [[place name, amount], …] (the top bar chip tooltip).
func stock_split(res: StringName) -> Array:
	var out := []
	for b in _stores:
		if b.store.amount(res) > 0.0005:
			out.append([b.display_name(), b.store.amount(res)])
	if loose.amount(res) > 0.0005:
		out.append(["Not stored", loose.amount(res)])
	return out


## The storage building that would take `res` nearest to `near` (any store for near < 0), or null.
func _store_for(res: StringName, near: Vector2i) -> Building:
	var best: Building = null
	var best_d := INF
	for b in _stores:
		if not b.store.accepts(res) or b.store.room() <= 0.0:
			continue
		var d := 0.0 if near.x < 0 else Vector2(near).distance_squared_to(b.access)
		if d < best_d:
			best_d = d
			best = b
	return best


func put_goods(res: StringName, n: float, near := Vector2i(-1, -1)) -> void:
	var b := _store_for(res, near)
	(b.store if b else loose).put(res, n)


func take_goods(res: StringName, n: float, near := Vector2i(-1, -1)) -> float:
	var got := loose.take(res, n)
	var order := _stores.duplicate()
	if near.x >= 0:
		order.sort_custom(func(a: Building, b: Building) -> bool:
			return Vector2(near).distance_squared_to(a.access) < Vector2(near).distance_squared_to(b.access))
	for b: Building in order:
		if got >= n - 0.000001:
			break
		got += b.store.take(res, minf(n - got, b.store.available(res)))
	return got


## Debug and tests: exactly `n` of `res` on the farm, all of it in the first store.
func set_stock(res: StringName, n: float) -> void:
	loose.take(res, INF)
	for b in _stores:
		b.store.take(res, INF)
	put_goods(res, n)
	stock_changed.emit()


func store_at(cell: Vector2i) -> Building:
	for b in _stores:
		if b.access == cell:
			return b
	return null


func settle_loose() -> void:
	if _stores.is_empty():
		return
	for res: StringName in loose.contents.keys():
		put_goods(res, loose.take(res, INF))


## Access tile of the nearest reachable storage building that accepts `res` (any store when empty).
func delivery_target(from: Vector2i, res := &"") -> Variant:
	var order := _stores.duplicate()
	order.sort_custom(func(a: Building, b: Building) -> bool:
		return Vector2(from).distance_squared_to(a.access) < Vector2(from).distance_squared_to(b.access))
	for b: Building in order:
		if res != &"" and not b.store.accepts(res):
			continue
		if not nav.find_path(from, b.access).is_empty():
			return b.access
	return null


func deliver(w: Worker) -> void:
	var at := store_at(w.cell())
	if w.equipment != &"":
		if at:
			at.store.put(w.equipment, 1.0)          # the wheelbarrow goes back to the barn
		else:
			put_goods(w.equipment, 1.0, w.cell())
		w.equipment = &""
	if w.carrying != &"":
		if at and at.store.accepts(w.carrying):
			at.store.put(w.carrying, w.carry_amount)
		else:
			put_goods(w.carrying, w.carry_amount, w.cell())
	w.carrying = &""
	w.carry_amount = 0.0
	stock_changed.emit()


# --- workers & time ------------------------------------------------------------

func add_worker(cell: Vector2i, look: Worker.Look) -> Worker:
	var w := Worker.new(_take_id(), cell, look)
	w.name = WorkerNames.pick(self, look)
	workers.append(w)
	worker_added.emit(w)
	return w


## Renames a worker (trimmed, at most WorkerNames.MAX_LENGTH characters). False if the name is empty.
func rename_worker(w: Worker, name: String) -> bool:
	var n := WorkerNames.clean(name)
	if n == "":
		return false
	w.name = n
	return true


## Renames a building (trimmed, at most 24 characters); an empty name resets it to the default.
func rename_building(b: Building, name: String) -> bool:
	b.custom_name = name.strip_edges().left(24).strip_edges()
	building_changed.emit(b)
	return true


## Removes a worker (prefers idle ones). Its unfinished task goes back to the queue,
## anything it carries is put into storage. The pickup driver is never removed mid-trip.
func remove_worker() -> bool:
	var pick: Worker = null
	for w in workers:
		if w.in_vehicle or (w.task and w.task.kind == Task.Kind.TRIP and w.phase == Worker.Phase.WORKING):
			continue
		if pick == null or (w.phase == Worker.Phase.IDLE and pick.phase != Worker.Phase.IDLE):
			pick = w
	if pick == null:
		return false
	var t := pick.task
	if t and t.kind == Task.Kind.CARRY:
		tasks.remove(t)                 # a carry leg is planned again; what it carries is put down
		if pick.carrying != &"" and drop_goods(pick.carrying, pick.carry_amount, pick.cell(), t.category):
			pick.carrying = &""
			pick.carry_amount = 0.0
	elif t:
		release_fetch(t)
		t.worker = null
		if t.kind == Task.Kind.HELP and t.help_state.has("chunk"):
			(t.help_step["queue"] as Array).push_front(t.help_state["chunk"])
			t.help_step["in_flight"] -= 1
			t.help_state.clear()
			pick.carrying = &""
		if t.kind == Task.Kind.FIELD and pick.phase == Worker.Phase.WORKING and pick.strip_i > 0:
			t.cells = t.cells.slice(mini(pick.strip_i, t.cells.size() - 1))
			t.cell = t.cells[0]
			if t.fetch != &"":
				t.fetch_amount = t.cells.size() * Defs.seed_per_tile(t.field.crop)
	if pick.carrying != &"" or pick.equipment != &"":
		deliver(pick)
	pick.task = null
	workers.erase(pick)
	worker_removed.emit(pick)
	return true


func idle_workers() -> int:
	var n := 0
	for w in workers:
		if w.phase == Worker.Phase.IDLE and not w.in_vehicle:
			n += 1
	return n


## In-game day (display only), starting at 1.
func day() -> int:
	return floori(time / Defs.DAY_LENGTH) + 1


func tick(dt: float) -> void:
	time += dt
	_grow_fields(dt)
	_trip_check -= dt
	if _trip_check <= 0.0:
		_trip_check = 1.0
		_maybe_queue_trip()
		for b: Building in buildings.values():
			if not (b is ConstructionSite) and not b.recipe().is_empty():
				_update_building(b)
	planner.update(dt)
	for w in workers:
		w.tick(self, dt)


# --- research ------------------------------------------------------------------

func is_unlocked(id: StringName) -> bool:
	return unlocked.has(id)


## All prerequisites unlocked, not yet unlocked, not "coming later" (money is checked separately).
func unlock_ready(id: StringName) -> bool:
	if is_unlocked(id) or Tech.is_later(id):
		return false
	for n: StringName in Tech.node(id)["needs"]:
		if not is_unlocked(n):
			return false
	return true


func can_unlock(id: StringName) -> bool:
	return unlock_ready(id) and money >= int(Tech.node(id)["cost"])


## Pays for a research node and unlocks it at once. False if it is not possible.
func unlock(id: StringName) -> bool:
	if not can_unlock(id):
		return false
	var cost: int = Tech.node(id)["cost"]
	money -= cost
	book("research", -cost)
	unlocked[id] = true
	tech_changed.emit()
	stock_changed.emit()
	return true


## Developer cheat: every node of the tree that exists (not the "coming later" ones), for free.
func unlock_all() -> void:
	for id: StringName in Tech.NODES:
		if not Tech.is_later(id):
			unlocked[id] = true
	tech_changed.emit()
	stock_changed.emit()


## Buildings without a node in the tree are available from the start.
func building_unlocked(def_id: StringName) -> bool:
	var id := Tech.node_for_building(def_id)
	return id == &"" or is_unlocked(id)


## Dealer goods without a node in the tree are always for sale.
func item_unlocked(res: StringName) -> bool:
	var id := Tech.node_for_item(res)
	return id == &"" or is_unlocked(id)


## Highest level the research allows for this kind of building (1 without upgrades).
func max_level(def_id: StringName) -> int:
	var lvl := 1
	for l in [2, 3]:
		var id := Tech.node_for_level(def_id, l)
		if id != &"" and is_unlocked(id):
			lvl = l
	return lvl


# --- building upgrades -----------------------------------------------------------
# An upgrade is a construction site that takes no tiles: workers bring the planks and rebuild the
# building, which does not work meanwhile and keeps what is inside. Finishing raises its level.

## Why the building can't be upgraded now, or "" if it can.
func upgrade_blocker(b: Building) -> String:
	if not Defs.def(b.def_id).has("upgrade") or b is ConstructionSite:
		return "This building has no upgrades"
	if b.level >= 3:
		return "Highest level"
	if b.upgrading:
		return "Being upgraded"
	if max_level(b.def_id) <= b.level:
		return "Unlock %s in research" % Tech.node(Tech.node_for_level(b.def_id, b.level + 1))["name"]
	return ""


func start_upgrade(b: Building) -> ConstructionSite:
	if upgrade_blocker(b) != "":
		return null
	var site := ConstructionSite.new(_take_id(), b.def_id, b.anchor, b.rot)
	site.upgrade_of = b
	site.priority = b.priority
	site.work_total = float(Defs.def(b.def_id)["build_work"]) * Defs.UPGRADE_WORK
	b.upgrading = site
	if b.process_task and b.process_task.worker == null:
		tasks.remove(b.process_task)        # a batch nobody has started waits for the new level
		b.process_task = null
	buildings[site.id] = site
	building_added.emit(site)
	if instant_build:
		_finish_instantly(site)
		return site
	_after_clearing(site)
	return site


func _finish_upgrade(site: ConstructionSite) -> void:
	var b := site.upgrade_of
	buildings.erase(site.id)
	b.upgrading = null
	b.level += 1
	for res: StringName in site.delivered:
		b.materials[res] = b.materials.get(res, 0.0) + site.delivered[res]
	building_removed.emit(site)
	building_changed.emit(b)


# --- processing ----------------------------------------------------------------
# A mill / sawmill holds a few loads of raw goods and products. The planner has workers bring the
# raw goods (transport, a Need of the input), work a batch at the building (processing) and carry
# the products away (transport, a Clear of the output). A full output stops the processing;
# nothing is ever lost.

## Queues the next batch (called every second and after a batch and a delivery).
func _update_building(b: Building) -> void:
	if b.upgrading:
		return                          # rebuilt meanwhile
	var r := b.recipe()
	var res_in: StringName = r["in"]
	# one batch at a time; a smaller rest only when nothing more is coming
	if b.process_task == null and b.input > 0.0001:
		var amount := minf(float(r["batch"]), b.input)
		var more_coming: bool = total(res_in) >= 1.0 or b.input_store.reserved_in.get(res_in, 0.0) > 0.0001
		var room: bool = b.output + amount * float(r["yield"]) <= float(r["out_cap"]) + 0.0001
		if room and (amount >= float(r["batch"]) - 0.0001 or not more_coming):
			var t := Task.new(Task.Kind.PROCESS, b.access, float(r["work"]) * amount / float(r["batch"]), time)
			t.category = Task.Category.PROCESSING
			t.building = b
			t.amount = amount
			tasks.add(t)
			b.process_task = t


## Room left in the processing buildings for a raw good: auto-sell leaves this much in the barn.
func processing_demand(res: StringName) -> float:
	var n := 0.0
	for b: Building in buildings.values():
		var r := b.recipe()
		if not (b is ConstructionSite) and not r.is_empty() and r["in"] == res:
			n += maxf(0.0, float(r["in_cap"]) - b.input - b.input_store.reserved_in.get(res, 0.0))
	return n


## What the building is doing, for the info panel.
func process_status(b: Building) -> String:
	var r := b.recipe()
	if b.upgrading:
		return "Upgrading to level %d" % (b.level + 1)
	if b.process_task and b.process_task.worker and b.process_task.worker.phase == Worker.Phase.WORKING:
		return "Working"
	if b.process_task:
		return "Waiting for a worker"
	if b.output + minf(float(r["batch"]), maxf(b.input, 0.0)) * float(r["yield"]) > float(r["out_cap"]) + 0.0001:
		return "Halted: full, waiting for the %s to be carried away" % Defs.resource_name(r["out"]).to_lower()
	if b.input < 0.0001 and b.input_store.reserved_in.get(r["in"], 0.0) < 0.0001:
		return "Idle: no %s in storage" % Defs.resource_name(r["in"]).to_lower()
	return "Waiting for %s" % Defs.resource_name(r["in"]).to_lower()


# --- wants (needs of places) ---------------------------------------------------

## What the place still wants brought, resource -> amount (beyond what is there and on its way):
## a construction site in DELIVERY its missing material (a moved building only once its old
## building is down and the pickup is not hauling its pile), a working mill raw goods up to what
## its input holds. Other places want nothing.
func wanted(s: Store) -> Dictionary:
	var out := {}
	var owner := s.owner
	if owner == null or buildings.get(owner.id) != owner:
		return out
	if s.kind == Store.Kind.SITE:
		var site := owner as ConstructionSite
		if site.stage != ConstructionSite.Stage.DELIVERY or site.partner or site.by_pickup or not site.open_tasks.is_empty():
			return out
		var mat := site.material()
		for res: StringName in mat:
			var n: float = mat[res] - s.amount(res) - s.reserved_in.get(res, 0.0)
			if n > 0.01:
				out[res] = n
	elif s.kind == Store.Kind.INPUT and owner.input_store == s and not owner.upgrading:
		var r := owner.recipe()
		var n: float = float(r["in_cap"]) - s.amount(r["in"]) - s.reserved_in.get(r["in"], 0.0)
		if n > 0.0001:
			out[r["in"]] = n
	return out


## How much more of `res` the place takes: its want, or for a barn the room it has.
func want(s: Store, res: StringName) -> float:
	if s.kind == Store.Kind.STORAGE:
		return s.room() / Defs.weight(res, 1.0) if s.accepts(res) else 0.0
	return wanted(s).get(res, 0.0)


## Goods of `res` that the planner could still hand out: what is not promised yet in barns, mill
## outputs, gate and ground piles, and loose goods.
func available(res: StringName) -> float:
	var n := loose.amount(res)
	for s: Store in places():
		if s.kind == Store.Kind.STORAGE or s.kind == Store.Kind.OUTPUT or s.kind == Store.Kind.GATE \
				or s.kind == Store.Kind.GROUND:
			n += s.available(res)
	return n


## [site, resource, amount] for every material a construction site still wants that is not on its
## way yet (a moved building's own pile counts as on its way).
func site_needs() -> Array:
	var out := []
	for b: Building in buildings.values():
		if b is ConstructionSite:
			var wants := wanted(b.supply)
			for res: StringName in wants:
				var n: float = wants[res] - (b.pile_store.available(res) if b.moved else 0.0)
				if n > 0.01:
					out.append([b, res, n])
	return out


# --- seeds ---------------------------------------------------------------------

## Least amount a seed row can start with: one tile's worth (it is sown partly), pieces one.
func fetch_min(t: Task) -> float:
	if Defs.is_piece(t.fetch):
		return 1.0
	if t.step == &"seed":
		return Defs.seed_per_tile(t.field.crop) - 0.000001
	return t.fetch_amount


## Worker picks up what a task needs: a carry leg its claimed goods (see `_take_carried`), a seed
## row its seed sack from storage. False if it is gone. With too little seed for the whole row, it
## takes what there is and sows that many tiles; the rest of the row becomes a new task that waits
## for more seed.
func take_fetch(t: Task, w: Worker) -> bool:
	if t.kind == Task.Kind.CARRY:
		return _take_carried(t, w)
	var have := fetch_have(t)
	if have < fetch_min(t):
		return false
	if t.step == &"seed" and have < t.fetch_amount - 0.000001:
		var per_tile := Defs.seed_per_tile(t.field.crop)
		var n := clampi(floori(have / per_tile + 0.000001), 1, t.cells.size() - 1)
		var rest := Task.new(Task.Kind.FIELD, t.cells[n], t.work, t.created)
		rest.category = t.category
		rest.field = t.field
		rest.step = t.step
		rest.row = t.row
		rest.cells = t.cells.slice(n)
		rest.fetch = t.fetch
		rest.fetch_amount = rest.cells.size() * per_tile
		rest.retry_at = time + 2.0
		t.cells = t.cells.slice(0, n)
		t.fetch_amount = n * per_tile
		t.field.row_task[t.row] = rest
		tasks.add(rest)
	var amount := minf(t.fetch_amount, floorf(have + 0.000001) if Defs.is_piece(t.fetch) else have)
	var store := t.fetch_from
	release_fetch(t)
	amount = store.take(t.fetch, amount) if store else take_goods(t.fetch, amount, w.cell())
	if amount < fetch_min(t) - 0.000001:
		if store:
			store.put(t.fetch, amount)
		else:
			put_goods(t.fetch, amount, w.cell())
		return false
	w.carrying = t.fetch
	w.carry_amount = amount
	stock_changed.emit()
	return true


## At the source of a carry leg: the worker takes the claimed goods, with a wheelbarrow also what
## has come since (up to its capacity and what the destination still takes). The source's owner
## reacts (a gate may switch its crop). False when nothing is left to take.
func _take_carried(t: Task, w: Worker) -> bool:
	var s := t.fetch_from
	if s == null:
		return false
	if w.equipment == &"wheelbarrow":
		var extra := minf(s.available(t.fetch), Defs.WHEELBARROW_CAPACITY - t.fetch_amount)
		extra = minf(extra, want(t.dst, t.fetch))
		if extra > 0.01:
			t.fetch_reserved += s.reserve_out(t.fetch, extra)
			t.fetch_amount += extra
			t.dst.reserve_in(t.fetch, extra)
			t.dst_reserved += extra
	var claimed := t.fetch_reserved
	release_fetch(t)
	var got := s.take(t.fetch, claimed)
	if got < claimed - 0.000001:
		t.dst.release_in(t.fetch, minf(t.dst_reserved, claimed - got))   # less arrives than promised
		t.dst_reserved = maxf(0.0, t.dst_reserved - (claimed - got))
	t.fetch_amount = got
	if got <= 0.000001:
		return false
	w.carrying = t.fetch
	w.carry_amount = got
	match s.kind:
		Store.Kind.GATE:
			var f := s.owner as Field
			f.dirty = true
			_try_switch_crop(f)
		Store.Kind.MOVE_PILE:
			site_changed.emit(s.owner)
		Store.Kind.GROUND:
			_pile_taken(s)
	stock_changed.emit()
	return true


## Seed (and site material) still needed beyond what could be handed out, per resource: waiting
## seed rows, and what sites want that is not on its way yet.
func seed_shortage() -> Dictionary:
	var need := {}
	for t in tasks.tasks:
		if t.step == &"seed" and t.worker == null:
			need[t.fetch] = need.get(t.fetch, 0.0) + t.fetch_amount
	for sn: Array in site_needs():
		need[sn[1]] = need.get(sn[1], 0.0) + sn[2]
	var out := {}
	for res: StringName in need:
		var missing: float = need[res] - available(res)
		if missing > 0.000001:
			out[res] = missing
	return out


# --- priorities ----------------------------------------------------------------

## Moves a category up (delta -1) or down (+1) in the player's order.
func move_category(cat: int, delta: int) -> void:
	var i := category_order.find(cat)
	var j := clampi(i + delta, 0, category_order.size() - 1)
	category_order.remove_at(i)
	category_order.insert(j, cat)


func set_category_on(cat: int, on: bool) -> void:
	if on:
		category_off.erase(cat)
	else:
		category_off[cat] = true


func reset_priorities() -> void:
	category_order = Task.DEFAULT_ORDER.duplicate()
	category_off.clear()


## [waiting, in progress] task counts per category.
func category_counts() -> Dictionary:
	var out := {}
	for c in Task.Category.values():
		out[c] = [0, 0]
	for t in tasks.tasks:
		out[t.category][0 if t.worker == null else 1] += 1
	return out


## Only road sites still want this material.
func _only_road_sites_need(res: StringName) -> bool:
	for sn: Array in site_needs():
		if sn[1] == res and not (sn[0] as ConstructionSite).is_road():
			return false
	return true


## Short warnings for the HUD.
func alerts() -> PackedStringArray:
	var out := PackedStringArray()
	var counts := category_counts()
	for c: int in category_off:
		if counts[c][0] > 0:
			var n: int = counts[c][0]
			out.append("%s is switched off — %d %s waiting (priorities: P)" % [Task.CATEGORY_NAMES[c][0], n, "task" if n == 1 else "tasks"])
	var short := seed_shortage()
	for res: StringName in short:
		var ordered: float = orders.get(res, 0.0)
		var who := "fields" if String(res).begins_with("seed_") else ("road sites" if _only_road_sites_need(res) else "construction sites")
		var line := "%s: %s need %s more" % [Defs.resource_name(res), who, Defs.format_amount(res, short[res])]
		if res == &"planks" and ordered < short[res]:
			out.append(line + " — order them at the Dealer or make them at a Sawmill")
			continue
		if ordered >= short[res]:
			line += " — the pickup will bring %s" % Defs.format_kg(ordered)
		elif ordered > 0.0:
			line += " — ordered %s, order %s more at the Dealer" % [Defs.format_kg(ordered), Defs.format_kg(short[res] - ordered)]
		else:
			line += " — order them at the Dealer"
		out.append(line)
	return out


# --- dealer & pickup -----------------------------------------------------------

func add_vehicle(garage: Building) -> Vehicle:
	var block: Variant = road_nav.block_near(garage.access)
	var v := Vehicle.new(_take_id(), garage, block if block != null else garage.access)
	vehicles.append(v)
	vehicle_added.emit(v)
	return v


func dealer() -> Building:
	for b: Building in buildings.values():
		if b.def_id == &"dealer":
			return b
	return null


func sellable(res: StringName) -> float:
	var rule: Dictionary = auto_sell.get(res, {})
	if rule.is_empty() or not rule["on"]:
		return 0.0
	# the mills and the sawmill get their raw goods first
	return maxf(0.0, floorf(total(res) - rule["keep"] - processing_demand(res)))


## Weight (kg) the pickup would take to the Dealer right now.
func sellable_weight() -> float:
	var n := 0.0
	for res in auto_sell:
		n += Defs.weight(res, sellable(res))
	return n


func orders_total() -> float:
	var n := 0.0
	for res in orders:
		n += orders[res]
	return n


## Seeds are paid when ordered; the pickup only collects them. False if there is not enough money.
func order(res: StringName, amount: float) -> bool:
	var cost := order_cost(res, amount)
	if amount <= 0.0 or cost > money or not item_unlocked(res):
		return false
	money -= cost
	book("seeds" if String(res).begins_with("seed_") else ("materials" if Defs.MATERIAL_PRICE.has(res) else "equipment"), -cost)
	orders[res] = orders.get(res, 0.0) + amount
	stock_changed.emit()
	return true


func order_cost(res: StringName, amount: float) -> int:
	return ceili(amount * Defs.buy_price(res))


## "Send the pickup now" from the Dealer panel: go even with a small load.
func request_trip() -> void:
	_force_trip = true
	_maybe_queue_trip()


## Fee for the next `count` hires, after the ones already waiting at the Dealer.
func hire_cost(count: int) -> int:
	var n := 0
	for i in count:
		n += Defs.hire_cost(workers.size() + hires_wanted + i + 1)
	return n


## Hires workers at the Dealer. Paid now, picked up by the pickup (free seats per trip).
## False if there is not enough money.
func hire(count: int) -> bool:
	if count <= 0:
		return false
	var fees: Array[int] = []
	for i in count:
		fees.append(Defs.hire_cost(workers.size() + hires_wanted + i + 1))
	var cost := 0
	for fee in fees:
		cost += fee
	if cost > money:
		return false
	money -= cost
	_hire_fees.append_array(fees)
	book("hiring", -cost)
	hires_wanted = _hire_fees.size()
	stock_changed.emit()
	return true


## Calls off the hires still waiting at the Dealer and refunds their fees.
func cancel_hires() -> void:
	for fee in _hire_fees:
		money += fee
		book("hiring", fee)
	_hire_fees.clear()
	hires_wanted = 0
	stock_changed.emit()


## At the Dealer: signs up waiting hires one by one while there are free seats. True when done.
func _hire_tick(t: Task, dt: float) -> bool:
	var v := t.vehicle
	if hires_wanted <= 0 or v.passengers.size() >= Defs.PICKUP_SEATS - 1:
		return true
	trip_status = "Hiring workers at the Dealer"
	if not _wait(t, dt, Defs.HIRE_TIME):
		return false
	t.timer = 0.0
	_hire_fees.pop_front()
	hires_wanted = _hire_fees.size()
	var looks := Worker.Look.values()
	var w := add_worker(Vector2i(v.pos), looks[(workers.size() - 1) % looks.size()])
	w.in_vehicle = true
	w.pos = v.pos
	v.passengers.append(w)
	stock_changed.emit()
	return false


## Passengers get off next to the given access cell and start working.
func _drop_passengers(v: Vehicle, at: Vector2i) -> void:
	for i in v.passengers.size():
		var p := v.passengers[i]
		p.in_vehicle = false
		p.pos = Vector2(at) + Vector2(0.5, 0.5) + Vector2(0.25 * i, 0.0)
	v.passengers.clear()


## Field pile waiting for the pickup (enough of it, gate next to a road), or null.
func _field_for_pickup() -> Field:
	var best: Field = null
	for f in fields:
		var free := f.gate_store.available(f.crop)
		if free >= Defs.PICKUP_HAUL_MIN and road_nav.block_near(f.access) != null:
			if best == null or free > best.gate_store.available(best.crop):
				best = f
	return best


func _maybe_queue_trip() -> void:
	if _trip_task != null or vehicles.is_empty():
		return
	var v := vehicles[0]
	if not v.parked:
		return
	if v.garage is ConstructionSite:
		trip_status = "Waiting for the garage to be moved"
		return
	var haul := _site_for_pickup()
	var sell := sellable_weight()
	var to_dealer := haul == null and (orders_total() > 0.0 or hires_wanted > 0 or sell >= Defs.MIN_TRIP_LOAD or (_force_trip and sell > 0.0))
	var field := _field_for_pickup() if not to_dealer and haul == null else null
	if not to_dealer and field == null and haul == null:
		return
	if haul == null:
		_force_trip = false
	var t := Task.new(Task.Kind.TRIP, v.garage.access, 0.0, time)
	t.category = Task.Category.CONSTRUCTION if haul else (Task.Category.DEALER if to_dealer else Task.Category.TRANSPORT)
	t.vehicle = v
	t.field = field
	t.site = haul
	_trip_task = t
	tasks.add(t)
	trip_status = "Waiting for a driver"


func _storage_for(v: Vehicle) -> Building:
	var best: Building = null
	var best_d := INF
	for b: Building in _stores:
		var d := Vector2(v.garage.access).distance_squared_to(b.access)
		if d < best_d:
			best_d = d
			best = b
	return best


func _plan_trip(t: Task) -> bool:
	var v := t.vehicle
	if t.site:
		return _plan_haul(t)
	var barn := _storage_for(v)
	var barn_block: Variant = road_nav.block_near(barn.access) if barn else null
	if barn_block == null:
		trip_status = "The barn is not by a road"
		return false
	t.steps.append({"type": "board"})
	if t.field:
		# harvest run: field gate → barn
		var gate_block: Variant = road_nav.block_near(t.field.access)
		if gate_block == null or road_nav.route(v.block, gate_block).is_empty():
			trip_status = "Can't reach the field by road"
			return false
		t.steps.append({"type": "drive", "block": gate_block, "status": "Driving to the field"})
		t.steps.append({"type": "pick_up"})
		t.steps.append({"type": "drive", "block": barn_block, "status": "Bringing the harvest to the barn"})
		t.steps.append({"type": "unload"})
	else:
		var d := dealer()
		var dealer_block: Variant = road_nav.block_near(d.access) if d else null
		if dealer_block == null or road_nav.route(v.block, dealer_block).is_empty():
			trip_status = "Can't reach the Dealer by road"
			return false
		if sellable_weight() > 0.0:
			t.steps.append({"type": "drive", "block": barn_block, "status": "Driving to the barn"})
			t.steps.append({"type": "load"})
		t.steps.append({"type": "drive", "block": dealer_block, "status": "Driving to the Dealer"})
		t.steps.append({"type": "sell"})
		t.steps.append({"type": "buy"})
		if hires_wanted > 0:
			t.steps.append({"type": "hire"})
		# goods bought (also orders placed after the trip was planned) go to the barn; skipped if empty
		t.steps.append({"type": "drive", "block": barn_block, "status": "Bringing goods to the barn", "cargo_only": true})
		t.steps.append({"type": "unload", "cargo_only": true})
	t.steps.append({"type": "drive", "block": v.block, "status": "Returning to the garage"})
	t.steps.append({"type": "park"})
	return true


## Runs the pickup trip for the driving worker; true when the trip is over.
func trip_tick(t: Task, w: Worker, dt: float) -> bool:
	var v := t.vehicle
	if t.steps.is_empty() and not _plan_trip(t):
		_trip_task = null
		_trip_check = 30.0          # don't retry an impossible trip every second
		if t.site:
			_after_pickup(t.site)         # the materials are carried by hand instead
		return true
	var s: Dictionary = t.steps[t.step_i]
	if s.get("cargo_only", false) and v.cargo.is_empty():
		_next_step(t)
		return false
	match s["type"]:
		"board":
			v.parked = false
			v.driver = w
			w.in_vehicle = true
			_next_step(t)
		"drive":
			trip_status = s["status"]
			if t.route.is_empty():
				t.route = road_nav.route(v.block, s["block"])
				t.route_i = 0
				if t.route.is_empty():
					t.route.append(Vector2(s["block"]) + Vector2.ONE)
			if _drive(v, t, dt):
				v.block = s["block"]
				t.route = PackedVector2Array()
				_next_step(t)
		"load", "pick_up", "sell", "buy", "unload", "load_pile", "unload_site":
			if not s.has("queue"):
				_prepare_transfer(t, w, s)
			if _transfer(t, w, s, dt):
				if s["type"] == "unload_site":
					_after_pickup(t.site)         # a rest that did not fit goes by hand
				w.in_vehicle = true
				w.carrying = &""
				w.carry_amount = 0.0
				_next_step(t)
		"hire":
			if _hire_tick(t, dt):
				_next_step(t)
		"park":
			if t.route.is_empty():
				t.route = PackedVector2Array([v.parking_pos()])
				t.route_i = 0
			if _drive(v, t, dt):
				var d := Vector2(Defs.DIRS[v.garage.rot])
				v.heading = atan2(d.x, -d.y)
				v.parked = true
				v.driver = null
				w.in_vehicle = false
				w.pos = Vector2(v.garage.access) + Vector2(0.5, 0.5)
				_drop_passengers(v, v.garage.access)
				trip_status = "In the garage"
				_trip_task = null
				return true
	if w.in_vehicle:
		w.pos = v.pos
	for p in v.passengers:
		p.pos = v.pos
	return false


func _next_step(t: Task) -> void:
	t.step_i += 1
	t.timer = 0.0


func _wait(t: Task, dt: float, seconds: float) -> bool:
	t.timer += dt
	return t.timer >= seconds


func _drive(v: Vehicle, t: Task, dt: float) -> bool:
	var budget := dt
	while budget > 0.0 and t.route_i < t.route.size():
		var target := t.route[t.route_i]
		var to := target - v.pos
		var dist := to.length()
		var surface := road_at(Vector2i(floori(v.pos.x), floori(v.pos.y)))
		var speed := Defs.PICKUP_SPEED * float(Defs.VEHICLE_ROAD_SPEED.get(surface, 0.6))
		if dist <= speed * budget:
			v.pos = target
			budget -= dist / speed
			t.route_i += 1
		else:
			v.pos += to / dist * speed * budget
			budget = 0.0
		if dist > 0.001:
			v.heading = atan2(to.x, -to.y)
	return t.route_i >= t.route.size()


# --- loading & unloading by hand ---------------------------------------------

const MAX_HELPERS := 3

const TRANSFER_STATUS := {
	"load": "Loading goods at the barn", "pick_up": "Loading the harvest at the field",
	"sell": "Unloading at the Dealer", "buy": "Loading goods at the Dealer", "unload": "Unloading at the barn",
	"load_pile": "Loading building materials at the old spot", "unload_site": "Unloading materials at the new site",
}


## Works out what the driver will carry between the pickup and the barn / field pile / Dealer.
func _prepare_transfer(t: Task, w: Worker, s: Dictionary) -> void:
	var v := t.vehicle
	var items: Array = []           # [resource, amount] in order
	var place: Vector2i
	var dir := "in"
	match s["type"]:
		"load":
			place = _storage_for(v).access
			var space := Defs.PICKUP_CAPACITY
			for res in auto_sell:
				var n := minf(sellable(res), floorf(space / Defs.weight(res, 1.0)))
				if n > 0.0:
					items.append([res, n])
					space -= Defs.weight(res, n)
		"pick_up":
			var f := t.field
			place = f.access
			var n := f.gate_store.reserve_out(f.crop, minf(Defs.PICKUP_CAPACITY, f.gate_store.available(f.crop)))
			if n > 0.0:                     # nobody carries this part by hand any more
				items.append([f.crop, n])
		"sell":
			place = dealer().access
			dir = "out"
			for res in v.cargo:
				if Defs.SELL_PRICE.has(res):        # bought goods stay in the pickup
					items.append([res, v.cargo[res]])
		"buy":
			place = dealer().access
			var space := Defs.PICKUP_CAPACITY
			for res in orders.keys():
				var n := minf(orders[res], space / Defs.weight(res, 1.0))
				if Defs.is_piece(res):
					n = floorf(n)
				if n > 0.0:
					items.append([res, n])
					orders[res] -= n
					space -= Defs.weight(res, n)
				if orders[res] <= 0.0001:
					orders.erase(res)
		"unload":
			place = _storage_for(v).access
			_drop_passengers(v, place)     # new hires get off and lend a hand
			dir = "out"
			for res in v.cargo:
				items.append([res, v.cargo[res]])
		"load_pile":
			var spot: Variant = store_spot(t.site.pile_store)
			place = spot if spot != null else t.site.pile_cell
			var space := Defs.PICKUP_CAPACITY
			for res: StringName in t.site.pile:
				var n := minf(t.site.pile[res], floorf(space / Defs.weight(res, 1.0)))
				if n > 0.0:
					items.append([res, n])
					space -= Defs.weight(res, n)
		"unload_site":
			place = t.site.access
			dir = "out"
			for res in v.cargo:
				items.append([res, v.cargo[res]])
	s["queue"] = items
	s["dir"] = dir
	s["point"] = Vector2(place) + Vector2(0.5, 0.5)
	s["field"] = t.field
	s["site"] = t.site
	s["in_flight"] = 0
	s["helpers"] = []
	# on the farm other workers come to help with bigger loads
	if s["type"] != "sell" and s["type"] != "buy":
		var loads := 0
		for it in items:
			loads += ceili(it[1] / Defs.hand_load(it[0]))
		for i in mini(MAX_HELPERS, loads / 2):
			# helpers share the urgency (category and age) of the trip they help with
			var h := Task.new(Task.Kind.HELP, place, 0.0, t.created)
			h.category = t.category
			h.help_step = s
			h.help_trip = t
			s["helpers"].append(h)
			tasks.add(h)
	trip_status = TRANSFER_STATUS[s["type"]]
	w.in_vehicle = false
	w.pos = v.pos


## The driver carries loads between the pickup and the place; on the farm up to MAX_HELPERS
## other workers come and help. Returns true when everything is moved.
func _transfer(t: Task, w: Worker, s: Dictionary, dt: float) -> bool:
	if not s.has("driver"):
		s["driver"] = {}
	var done := _shuttle(s["driver"], s, w, t.vehicle, dt, false)
	if not done or s["in_flight"] > 0:
		return false
	# everything is in: helpers that have not arrived yet are not needed any more
	s["finished"] = true
	for h: Task in s["helpers"]:
		if h.worker == null:
			tasks.remove(h)
	w.pos = t.vehicle.pos
	return true


func help_tick(t: Task, w: Worker, dt: float) -> bool:
	var s := t.help_step
	if s.get("finished", false) or not s.has("queue"):
		return true
	return _shuttle(t.help_state, s, w, t.help_trip.vehicle, dt, true)


## One worker's rounds. Each round takes one load (50 kg or a log) off the shared queue.
## start_at_place: helpers start at the barn / pile, the driver at the pickup.
## Returns true when the queue is empty and this worker holds nothing.
func _shuttle(state: Dictionary, s: Dictionary, w: Worker, v: Vehicle, dt: float, start_at_place: bool) -> bool:
	var queue: Array = s["queue"]
	if not state.has("chunk"):
		if queue.is_empty():
			w.carrying = &""
			w.carry_amount = 0.0
			return true
		var head: Array = queue[0]
		var n: float = minf(head[1], Defs.hand_load(head[0]))
		head[1] -= n
		if head[1] <= 0.0001:
			queue.pop_front()
		state["chunk"] = [head[0], n]
		state["cycle"] = 0.0
		s["in_flight"] = s.get("in_flight", 0) + 1
	var res: StringName = state["chunk"][0]
	var n: float = state["chunk"][1]
	var a := v.pos - Vector2(sin(v.heading), -cos(v.heading)) * 1.0    # tailgate
	var b: Vector2 = s["point"]
	var round_time := 2.0 * a.distance_to(b) / Defs.WALK_SPEED + 1.0
	state["cycle"] += dt
	if state["cycle"] >= round_time:
		_move_chunk(s, v, res, n)
		state.erase("chunk")
		s["in_flight"] -= 1
		w.pos = b if start_at_place else a
		w.carrying = &""
		w.carry_amount = 0.0
		return false
	# out and back: phase 0 and 1 at the start point, 0.5 at the other end
	var phase: float = state["cycle"] / round_time
	var from := b if start_at_place else a
	var to := a if start_at_place else b
	var prev := w.pos
	w.pos = from.lerp(to, 1.0 - absf(2.0 * phase - 1.0))
	if w.pos.distance_squared_to(prev) > 0.000001:
		var d := w.pos - prev
		w.heading = atan2(d.x, -d.y)
	# loading: goods travel place → pickup; unloading: pickup → place
	var towards_pickup := (phase < 0.5) == start_at_place
	var loaded := towards_pickup if s["dir"] == "in" else not towards_pickup
	w.carrying = res if loaded else &""
	w.carry_amount = n if loaded else 0.0
	return false


func _move_chunk(s: Dictionary, v: Vehicle, res: StringName, n: float) -> void:
	match s["type"]:
		"load":
			var barn := _storage_for(v)
			n = take_goods(res, n, barn.access if barn else Vector2i(-1, -1))
		"pick_up":
			var f: Field = s["field"]
			f.gate_store.release_out(f.crop, n)
			f.gate_store.take(f.crop, n)
			f.dirty = true
			_try_switch_crop(f)
		"buy":
			pass                        # paid when ordered
		"sell":
			var earned := roundi(n * Defs.SELL_PRICE.get(res, 0.0))
			money += earned
			book("sales: %s" % Defs.resource_name(res).to_lower(), earned)
		"unload":
			var barn := _storage_for(v)
			put_goods(res, n, barn.access if barn else Vector2i(-1, -1))
		"load_pile":
			var site: ConstructionSite = s["site"]
			n = minf(n, site.pile.get(res, 0.0))      # the pile went to the barn if the move was cancelled
			site.pile[res] = site.pile.get(res, 0.0) - n
			if site.pile[res] < 0.0001:
				site.pile.erase(res)
			site_changed.emit(site)
		"unload_site":
			var site: ConstructionSite = s["site"]
			if buildings.has(site.id):
				site.delivered[res] = site.delivered.get(res, 0.0) + n
				site_changed.emit(site)
			else:
				put_goods(res, n, site.access)   # the site was cancelled meanwhile
	if s["dir"] == "in":
		v.cargo[res] = v.cargo.get(res, 0.0) + n
	else:
		v.cargo[res] = v.cargo.get(res, 0.0) - n
		if v.cargo[res] <= 0.0001:
			v.cargo.erase(res)
	stock_changed.emit()


## Records money in (+) or out (-) under a heading for the overview in the developer menu.
func book(kind: String, amount: int) -> void:
	ledger[kind] = ledger.get(kind, 0) + amount


## The pickup can collect this field's harvest: gate next to a road connected to the garage and the barn.
func pickup_collects(f: Field) -> bool:
	if vehicles.is_empty():
		return false
	var v := vehicles[0]
	if v.garage is ConstructionSite:
		return false                    # the garage is being moved: no trips meanwhile
	var gate: Variant = road_nav.block_near(f.access)
	var barn := _storage_for(v)
	if gate == null or barn == null:
		return false
	var barn_block: Variant = road_nav.block_near(barn.access)
	return barn_block != null and not road_nav.route(v.block, gate).is_empty() \
		and not road_nav.route(gate, barn_block).is_empty()
