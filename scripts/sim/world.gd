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

const SURFACES: Array[StringName] = [&"", &"dirt", &"gravel"]

var size: int
var seed_value: int
var time := 0.0
var money := Defs.START_MONEY
var stock := {
	&"wood": 0.0, &"wheat": 0.0, &"potato": 0.0, &"corn": 0.0, &"beet": 0.0,
	&"seed_wheat": 0.0, &"seed_potato": 0.0, &"seed_corn": 0.0, &"seed_beet": 0.0,
}
var auto_sell := {}                # resource -> {"on": bool, "keep": float}
var orders := {}                   # seed resource -> amount ordered at the Dealer, not yet collected
var hires_wanted := 0               # workers hired at the Dealer, waiting to be picked up
var _hire_fees: Array[int] = []    # prepaid fee of each waiting hire (refunded on cancel)
var trip_status := "In the garage"

var tree_kind: PackedByteArray     # Defs.TreeKind per tile
var tree_stage: PackedByteArray    # Defs.TreeStage per tile
var occupant: PackedInt32Array     # id of the building / site / field on the tile, 0 = free
var road: PackedByteArray          # index into SURFACES for built road tiles
var road_blocks := {}              # Vector2i anchor -> surface (built two-way road blocks)

var buildings := {}                # id -> Building (including construction sites and fields)
var fields: Array[Field] = []
var workers: Array[Worker] = []
var vehicles: Array[Vehicle] = []
var tasks := TaskQueue.new()
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
	nav = Nav.new(size)
	road_nav = RoadNav.new(self)
	for res: StringName in Defs.SELL_PRICE:
		auto_sell[res] = {"on": true, "keep": 0.0}


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
	var i := idx(c)
	var b: Building = buildings.get(occupant[i])
	var blocked_by_building := b != null and not (b is ConstructionSite) and not (b is Field)
	nav.set_solid(c, tree_kind[i] != Defs.TreeKind.NONE or blocked_by_building)
	nav.set_cost(c, 1.0 / speed_factor(c))


# --- placement -----------------------------------------------------------------

func cost_of(def_id: StringName, base_size := Vector2i.ZERO) -> int:
	if Defs.is_field(def_id):
		return Defs.field_cost(base_size)
	return Defs.def(def_id)["cost"]


func can_place(def_id: StringName, anchor: Vector2i, rot: int, base_size := Vector2i.ZERO) -> bool:
	if base_size == Vector2i.ZERO:
		base_size = Defs.def(def_id)["size"]
	if Defs.is_field(def_id) and not Defs.field_size_ok(base_size):
		return false
	if money < cost_of(def_id, base_size):
		return false
	var fs := Defs.rotated(base_size, rot)
	for y in fs.y:
		for x in fs.x:
			var c := anchor + Vector2i(x, y)
			if not in_bounds(c) or is_locked(c) or occupant[idx(c)] != 0 or road[idx(c)] != 0:
				return false
	if Defs.is_road(def_id):
		return true
	var a := Defs.access_for(base_size, anchor, rot)
	return in_bounds(a) and not is_locked(a) and occupant[idx(a)] == 0


## Pays for the object and places a construction site that workers will clear and build.
func place_site(def_id: StringName, anchor: Vector2i, rot: int, base_size := Vector2i.ZERO, crop := &"wheat") -> ConstructionSite:
	if not can_place(def_id, anchor, rot, base_size):
		return null
	var site := ConstructionSite.new(_take_id(), def_id, anchor, rot, base_size)
	site.crop = crop
	site.paid = cost_of(def_id, site.base_size)
	money -= site.paid
	stock_changed.emit()
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
			var t := Task.new(Task.Kind.CHOP, c, Defs.CHOP_TIME, time)
			t.site = site
			_add_site_task(site, t)
	if site.open_tasks.is_empty():
		_start_building(site)
	return site


## Instantly adds a finished building (world generation, completed sites).
func add_building(def_id: StringName, anchor: Vector2i, rot: int) -> Building:
	var b := Building.new(_take_id(), def_id, anchor, rot)
	_occupy(b)
	building_added.emit(b)
	return b


func add_field(anchor: Vector2i, rot: int, base_size: Vector2i, crop: StringName, paid := 0) -> Field:
	var f := Field.new(_take_id(), anchor, rot, base_size, crop)
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
	for c in b.cells():
		occupant[idx(c)] = b.id
		_refresh_nav(c)


func _release(b: Building) -> void:
	buildings.erase(b.id)
	for c in b.cells():
		occupant[idx(c)] = 0
		_refresh_nav(c)


func _take_id() -> int:
	_next_id += 1
	return _next_id - 1


# --- construction --------------------------------------------------------------

func _add_site_task(site: ConstructionSite, t: Task) -> void:
	site.open_tasks.append(t)
	tasks.add(t)


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
	_release(site)
	building_removed.emit(site)
	if site.is_road():
		add_road_block(site.anchor, Defs.def(site.def_id)["road"])
	elif site.is_field():
		add_field(site.anchor, site.rot, site.base_size, site.crop, site.paid)
	else:
		add_building(site.def_id, site.anchor, site.rot).paid = site.paid


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
			f.pile += Defs.CROPS[f.crop]["yield"]
			_queue_hauls(f, false)
	f.dirty = true


func _queue_hauls(f: Field, flush: bool) -> void:
	while true:
		var free := f.pile - f.pile_reserved
		if free < Defs.CARRY_CAPACITY and not (flush and free > 0.01):
			return
		var t := Task.new(Task.Kind.HAUL, f.access, Defs.LOAD_TIME, time)
		t.category = Task.Category.TRANSPORT
		t.field = f
		t.amount = minf(Defs.CARRY_CAPACITY, free)
		f.pile_reserved += t.amount
		tasks.add(t)


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
	f.crop = f.next_crop
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
		return ""
	if Defs.def(b.def_id).get("storage", false):
		var stores := 0
		for o: Building in buildings.values():
			if not (o is ConstructionSite) and Defs.def(o.def_id).get("storage", false):
				stores += 1
		if stores <= 1:
			return "The farm needs at least one Storage Barn"
	for v in vehicles:
		if v.garage == b:
			return "The pickup belongs to this garage"
	if b is Field and _trip_task and _trip_task.field == b:
		return "The pickup is collecting the harvest here"
	return ""


## Demolishes instantly with a full refund of what was paid. Work on it is called off;
## crops and the pile at the gate are lost. Returns false if it is not allowed.
func demolish(b: Building) -> bool:
	if demolish_blocker(b) != "":
		return false
	for t in tasks.tasks.duplicate():
		if t.site == b or t.field == b:
			tasks.remove(t)
			if t.worker:
				t.worker.abort(self)
	money += b.paid
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
				if not nav.is_solid(c):
					var dist := Vector2(from).distance_squared_to(c)
					if dist < best_d:
						best_d = dist
						best = c
			return best
		Task.Kind.BUILD:
			if not nav.is_solid(t.cell):
				return t.cell
			for c in _site_spots(t.site):
				if not nav.is_solid(c):
					t.cell = c
					return c
		Task.Kind.FIELD, Task.Kind.HAUL, Task.Kind.TRIP, Task.Kind.HELP:
			if not nav.is_solid(t.cell):
				return t.cell
	return null


func complete_task(t: Task, w: Worker) -> void:
	tasks.remove(t)
	match t.kind:
		Task.Kind.CHOP:
			t.site.open_tasks.erase(t)
			remove_tree(t.cell)
			w.carrying = &"wood"
			w.carry_amount = Defs.WOOD_PER_TREE
			if t.site.open_tasks.is_empty():
				_start_building(t.site)
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
					_queue_hauls(f, true)
					_try_switch_crop(f)
		Task.Kind.HAUL:
			var f := t.field
			f.pile -= t.amount
			f.pile_reserved -= t.amount
			f.dirty = true
			w.carrying = f.crop
			w.carry_amount = t.amount
			_try_switch_crop(f)


## Access tile of the nearest finished storage building that can be reached on foot.
func delivery_target(from: Vector2i) -> Variant:
	var stores: Array[Building] = []
	for b: Building in buildings.values():
		if not (b is ConstructionSite) and Defs.def(b.def_id).get("storage", false):
			stores.append(b)
	stores.sort_custom(func(a: Building, b: Building) -> bool:
		return Vector2(from).distance_squared_to(a.access) < Vector2(from).distance_squared_to(b.access))
	for b in stores:
		if not nav.find_path(from, b.access).is_empty():
			return b.access
	return null


func deliver(w: Worker) -> void:
	if w.carrying != &"":
		stock[w.carrying] = stock.get(w.carrying, 0.0) + w.carry_amount
	w.carrying = &""
	w.carry_amount = 0.0
	stock_changed.emit()


# --- workers & time ------------------------------------------------------------

func add_worker(cell: Vector2i, look: Worker.Look) -> Worker:
	var w := Worker.new(_take_id(), cell, look)
	workers.append(w)
	worker_added.emit(w)
	return w


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
	if t:
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
	if pick.carrying != &"":
		deliver(pick)
	workers.erase(pick)
	worker_removed.emit(pick)
	return true


func idle_workers() -> int:
	var n := 0
	for w in workers:
		if w.phase == Worker.Phase.IDLE and not w.in_vehicle:
			n += 1
	return n


func tick(dt: float) -> void:
	time += dt
	_grow_fields(dt)
	_trip_check -= dt
	if _trip_check <= 0.0:
		_trip_check = 1.0
		_maybe_queue_trip()
	for w in workers:
		w.tick(self, dt)


# --- seeds ---------------------------------------------------------------------

## Least amount a task can start with: seed rows can be sown partly (one tile's worth).
func fetch_min(t: Task) -> float:
	if t.step == &"seed":
		return Defs.seed_per_tile(t.field.crop) - 0.000001
	return t.fetch_amount


## Worker picks up what a task needs from storage (seed sack). False if it is gone.
## With too little seed for the whole row, it takes what there is and sows that many tiles;
## the rest of the row becomes a new task that waits for more seed.
func take_fetch(t: Task, w: Worker) -> bool:
	var have: float = stock.get(t.fetch, 0.0)
	if have < fetch_min(t):
		return false
	if have < t.fetch_amount - 0.000001:
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
	var amount := minf(t.fetch_amount, have)
	stock[t.fetch] = have - amount
	w.carrying = t.fetch
	w.carry_amount = amount
	stock_changed.emit()
	return true


## Seed still needed by waiting rows beyond what is in storage, per seed resource.
func seed_shortage() -> Dictionary:
	var need := {}
	for t in tasks.tasks:
		if t.fetch != &"" and t.worker == null:
			need[t.fetch] = need.get(t.fetch, 0.0) + t.fetch_amount
	var out := {}
	for res: StringName in need:
		var missing: float = need[res] - stock.get(res, 0.0)
		if missing > 0.000001:
			out[res] = missing
	return out


## Short warnings for the HUD.
func alerts() -> PackedStringArray:
	var out := PackedStringArray()
	var short := seed_shortage()
	for res: StringName in short:
		var ordered: float = orders.get(res, 0.0)
		var line := "%s: fields need %s more" % [Defs.resource_name(res), Defs.format_kg(short[res])]
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
	return maxf(0.0, floorf(stock.get(res, 0.0) - rule["keep"]))


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
	if amount <= 0.0 or cost > money:
		return false
	money -= cost
	orders[res] = orders.get(res, 0.0) + amount
	stock_changed.emit()
	return true


func order_cost(res: StringName, amount: float) -> int:
	return ceili(amount * Defs.SEED_PRICE[StringName(String(res).trim_prefix("seed_"))])


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
	hires_wanted = _hire_fees.size()
	stock_changed.emit()
	return true


## Calls off the hires still waiting at the Dealer and refunds their fees.
func cancel_hires() -> void:
	for fee in _hire_fees:
		money += fee
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
		var free := f.pile - f.pile_reserved
		if free >= Defs.PICKUP_HAUL_MIN and road_nav.block_near(f.access) != null:
			if best == null or free > best.pile - best.pile_reserved:
				best = f
	return best


func _maybe_queue_trip() -> void:
	if _trip_task != null or vehicles.is_empty():
		return
	var v := vehicles[0]
	if not v.parked:
		return
	var sell := sellable_weight()
	var to_dealer := orders_total() > 0.0 or hires_wanted > 0 or sell >= Defs.MIN_TRIP_LOAD or (_force_trip and sell > 0.0)
	var field := _field_for_pickup() if not to_dealer else null
	if not to_dealer and field == null:
		return
	_force_trip = false
	var t := Task.new(Task.Kind.TRIP, v.garage.access, 0.0, time)
	t.category = Task.Category.DEALER if to_dealer else Task.Category.TRANSPORT
	t.vehicle = v
	t.field = field
	_trip_task = t
	tasks.add(t)
	trip_status = "Waiting for a driver"


func _storage_for(v: Vehicle) -> Building:
	var best: Building = null
	var best_d := INF
	for b: Building in buildings.values():
		if b is ConstructionSite or not Defs.def(b.def_id).get("storage", false):
			continue
		var d := Vector2(v.garage.access).distance_squared_to(b.access)
		if d < best_d:
			best_d = d
			best = b
	return best


func _plan_trip(t: Task) -> bool:
	var v := t.vehicle
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
		if orders_total() > 0.0:
			t.steps.append({"type": "drive", "block": barn_block, "status": "Bringing goods to the barn"})
			t.steps.append({"type": "unload"})
	t.steps.append({"type": "drive", "block": v.block, "status": "Returning to the garage"})
	t.steps.append({"type": "park"})
	return true


## Runs the pickup trip for the driving worker; true when the trip is over.
func trip_tick(t: Task, w: Worker, dt: float) -> bool:
	var v := t.vehicle
	if t.steps.is_empty() and not _plan_trip(t):
		_trip_task = null
		_trip_check = 30.0          # don't retry an impossible trip every second
		return true
	var s: Dictionary = t.steps[t.step_i]
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
		"load", "pick_up", "sell", "buy", "unload":
			if not s.has("queue"):
				_prepare_transfer(t, w, s)
			if _transfer(t, w, s, dt):
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
	"sell": "Unloading at the Dealer", "buy": "Loading seeds at the Dealer", "unload": "Unloading at the barn",
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
			var n := minf(Defs.PICKUP_CAPACITY, f.pile - f.pile_reserved)
			if n > 0.0:
				f.pile_reserved += n          # nobody carries this part by hand any more
				items.append([f.crop, n])
		"sell":
			place = dealer().access
			dir = "out"
			for res in v.cargo:
				items.append([res, v.cargo[res]])
		"buy":
			place = dealer().access
			var space := Defs.PICKUP_CAPACITY
			for res in orders.keys():
				var n := minf(orders[res], space)
				if n > 0.0:
					items.append([res, n])
					orders[res] -= n
					space -= n
				if orders[res] <= 0.0001:
					orders.erase(res)
		"unload":
			place = _storage_for(v).access
			_drop_passengers(v, place)     # new hires get off and lend a hand
			dir = "out"
			for res in v.cargo:
				items.append([res, v.cargo[res]])
	s["queue"] = items
	s["dir"] = dir
	s["point"] = Vector2(place) + Vector2(0.5, 0.5)
	s["field"] = t.field
	s["in_flight"] = 0
	s["helpers"] = []
	# on the farm other workers come to help with bigger loads
	if s["type"] != "sell" and s["type"] != "buy":
		var loads := 0
		for it in items:
			loads += ceili(it[1] / (1.0 if it[0] == &"wood" else Defs.CARRY_CAPACITY))
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
		var n: float = minf(head[1], 1.0 if head[0] == &"wood" else Defs.CARRY_CAPACITY)
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
			stock[res] -= n
		"pick_up":
			var f: Field = s["field"]
			f.pile -= n
			f.pile_reserved -= n
			f.dirty = true
			_try_switch_crop(f)
		"buy":
			pass                        # paid when ordered
		"sell":
			money += roundi(n * Defs.SELL_PRICE.get(res, 0.0))
		"unload":
			stock[res] = stock.get(res, 0.0) + n
	if s["dir"] == "in":
		v.cargo[res] = v.cargo.get(res, 0.0) + n
	else:
		v.cargo[res] = v.cargo.get(res, 0.0) - n
		if v.cargo[res] <= 0.0001:
			v.cargo.erase(res)
	stock_changed.emit()
