class_name World
extends RefCounted
## The whole simulation state. Presentation reads it and listens to its signals;
## it never touches scene nodes.

signal tree_changed(cell: Vector2i)
signal building_added(b: Building)        # finished buildings and construction sites
signal building_removed(b: Building)
signal site_changed(site: ConstructionSite)
signal road_changed(anchor: Vector2i)
signal worker_added(w: Worker)
signal stock_changed

const SURFACES: Array[StringName] = [&"", &"dirt", &"gravel"]

var size: int
var seed_value: int
var time := 0.0
var money := Defs.START_MONEY
var stock := {&"wood": 0}

var tree_kind: PackedByteArray     # Defs.TreeKind per tile
var tree_stage: PackedByteArray    # Defs.TreeStage per tile
var occupant: PackedInt32Array     # id of the building / site on the tile, 0 = free
var road: PackedByteArray          # index into SURFACES for built road tiles
var road_blocks := {}              # Vector2i anchor -> surface (built two-way road blocks)

var buildings := {}                # id -> Building (including construction sites)
var workers: Array[Worker] = []
var tasks := TaskQueue.new()
var nav: Nav

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
	return Defs.ROAD_SPEED.get(s, 1.0)


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
	var blocked_by_building := b != null and not (b is ConstructionSite)
	nav.set_solid(c, tree_kind[i] != Defs.TreeKind.NONE or blocked_by_building)
	nav.set_cost(c, 1.0 / speed_factor(c))


# --- placement -----------------------------------------------------------------

func can_place(def_id: StringName, anchor: Vector2i, rot: int) -> bool:
	if money < Defs.def(def_id)["cost"]:
		return false
	var fs := Defs.footprint(def_id, rot)
	for y in fs.y:
		for x in fs.x:
			var c := anchor + Vector2i(x, y)
			if not in_bounds(c) or is_locked(c) or occupant[idx(c)] != 0 or road[idx(c)] != 0:
				return false
	if Defs.is_road(def_id):
		return true
	var a := Defs.access_cell(def_id, anchor, rot)
	return in_bounds(a) and not is_locked(a) and occupant[idx(a)] == 0


## Pays for the object and places a construction site that workers will clear and build.
func place_site(def_id: StringName, anchor: Vector2i, rot: int) -> ConstructionSite:
	if not can_place(def_id, anchor, rot):
		return null
	money -= Defs.def(def_id)["cost"]
	stock_changed.emit()
	var site := ConstructionSite.new(_take_id(), def_id, anchor, rot)
	_occupy(site)
	building_added.emit(site)
	for c in site.cells():
		if has_tree(c):
			_add_task(site, Task.new(Task.Kind.CHOP, site, c, Defs.CHOP_TIME, time))
	if site.open_tasks.is_empty():
		_start_building(site)
	return site


## Instantly adds a finished building (world generation, completed sites).
func add_building(def_id: StringName, anchor: Vector2i, rot: int) -> Building:
	var b := Building.new(_take_id(), def_id, anchor, rot)
	_occupy(b)
	building_added.emit(b)
	return b


func add_road_block(anchor: Vector2i, surface: StringName) -> void:
	road_blocks[anchor] = surface
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


# --- tasks ---------------------------------------------------------------------

func _add_task(site: ConstructionSite, t: Task) -> void:
	site.open_tasks.append(t)
	tasks.add(t)


func _start_building(site: ConstructionSite) -> void:
	site.stage = ConstructionSite.Stage.BUILDING
	site_changed.emit(site)
	var n := maxi(1, ceili(site.work_total / Defs.BUILD_CHUNK))
	var spots := _site_spots(site)
	for i in n:
		var spot: Vector2i = spots[i % spots.size()] if not spots.is_empty() else site.anchor
		_add_task(site, Task.new(Task.Kind.BUILD, site, spot, site.work_total / n, time))


## Where workers stand while building: roads on the block itself, buildings around the footprint.
func _site_spots(site: ConstructionSite) -> Array[Vector2i]:
	if site.is_road():
		return site.cells()
	var out: Array[Vector2i] = []
	var r := site.rect()
	for x in range(r.position.x, r.end.x):
		out.append(Vector2i(x, r.position.y - 1))
		out.append(Vector2i(x, r.end.y))
	for y in range(r.position.y, r.end.y):
		out.append(Vector2i(r.position.x - 1, y))
		out.append(Vector2i(r.end.x, y))
	out.shuffle()
	return out


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
	return null


func complete_task(t: Task, w: Worker) -> void:
	tasks.remove(t)
	var site := t.site
	site.open_tasks.erase(t)
	match t.kind:
		Task.Kind.CHOP:
			remove_tree(t.cell)
			w.carrying = &"wood"
			if site.open_tasks.is_empty():
				_start_building(site)
		Task.Kind.BUILD:
			site.work_done += t.work
			site_changed.emit(site)
			if site.open_tasks.is_empty():
				_finish_site(site)


func _finish_site(site: ConstructionSite) -> void:
	_release(site)
	building_removed.emit(site)
	if site.is_road():
		add_road_block(site.anchor, Defs.def(site.def_id)["road"])
	else:
		add_building(site.def_id, site.anchor, site.rot)


## Access tile of the nearest finished storage building.
func delivery_target(from: Vector2i) -> Variant:
	var best: Variant = null
	var best_d := INF
	for b: Building in buildings.values():
		if b is ConstructionSite or not Defs.def(b.def_id).get("storage", false):
			continue
		var d := Vector2(from).distance_squared_to(b.access)
		if d < best_d:
			best_d = d
			best = b.access
	return best


func deliver(w: Worker) -> void:
	if w.carrying == &"wood":
		stock[&"wood"] += Defs.WOOD_PER_TREE
	w.carrying = &""
	stock_changed.emit()


# --- workers & time ------------------------------------------------------------

func add_worker(cell: Vector2i, look: Worker.Look) -> Worker:
	var w := Worker.new(_take_id(), cell, look)
	workers.append(w)
	worker_added.emit(w)
	return w


func idle_workers() -> int:
	var n := 0
	for w in workers:
		if w.phase == Worker.Phase.IDLE:
			n += 1
	return n


func tick(dt: float) -> void:
	time += dt
	for w in workers:
		w.tick(self, dt)
