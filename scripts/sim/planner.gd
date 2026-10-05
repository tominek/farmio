class_name Planner
extends RefCounted
## The central logistics planner. Every Defs.PLANNER_INTERVAL seconds of game time it reads what
## places want (Need: a site's missing material, a mill's room for raw goods) and what must leave
## them (Clear: mill products, the harvest at a field gate, ground piles) and turns that into carry
## legs (Task.Kind.CARRY): from the source that is cheapest to walk from (Nav.walk_cost) to the
## destination, with the goods reserved at the source and the room at the destination. Needs come
## first, so a clear can feed a need directly (wheat at a gate into a mill); the rest of a clear
## goes to the cheapest barn.
##
## Cost per run: one pass over World.places(), and walk_cost lookups only for sources that hold
## the good (memoised in Nav until the grid changes).

var world: World
var ticks := 0              # measurements: runs, total and worst time of tick() in µs
var usec_total := 0
var usec_max := 0
var _timer := 0.0
var _spots := {}            # Store -> cell to stand at (or null), for one run


func _init(w: World) -> void:
	world = w


func update(dt: float) -> void:
	_timer -= dt
	if _timer <= 0.0:
		_timer = maxf(_timer + Defs.PLANNER_INTERVAL, 0.0)
		tick()


func tick() -> void:
	var t0 := Time.get_ticks_usec()
	var suppliers: Array[Store] = []
	var barns: Array[Store] = []
	var needs: Array[Store] = []
	var clears: Array[Store] = []
	for s: Store in world.places():
		match s.kind:
			Store.Kind.STORAGE:
				suppliers.append(s)
				barns.append(s)
			Store.Kind.OUTPUT, Store.Kind.GATE, Store.Kind.GROUND:
				suppliers.append(s)
				clears.append(s)
			Store.Kind.SITE, Store.Kind.INPUT:
				if not world.wanted(s).is_empty():
					needs.append(s)
	# High priority buildings get scarce goods first, then the oldest
	needs.sort_custom(func(a: Store, b: Store) -> bool:
		if a.owner.priority != b.owner.priority:
			return a.owner.priority > b.owner.priority
		return a.owner.id < b.owner.id)
	for d in needs:
		_plan_need(d, suppliers)
	if not barns.is_empty():
		for s in clears:
			_plan_clear(s, barns)
	_spots.clear()
	var took := Time.get_ticks_usec() - t0
	ticks += 1
	usec_total += took
	usec_max = maxi(usec_max, took)


# --- needs ---------------------------------------------------------------------

func _plan_need(d: Store, suppliers: Array[Store]) -> void:
	var dspot: Variant = _spot(d)
	if dspot == null:
		return
	var wanted := world.wanted(d)
	for res: StringName in wanted:
		var want: float = wanted[res]
		# a mill takes whole kilos (a smaller rest is not worth a walk), a site everything it lacks
		var least := 1.0 if Defs.is_piece(res) or d.kind == Store.Kind.INPUT else 0.01
		while want >= least - 0.000001:
			var src := _source(d, res, dspot, least, suppliers)
			if src == null:
				break
			var load := minf(minf(Defs.hand_load(res), want), src.available(res))
			if Defs.is_piece(res):
				load = floorf(load + 0.000001)
			if load < least - 0.000001:
				break
			_leg(src, d, res, load, dspot)
			want -= load


## The supplier of `res` cheapest to walk from to `dspot`. A moved building's own pile supplies
## only its own site, and is tried first.
func _source(d: Store, res: StringName, dspot: Vector2i, least: float, suppliers: Array[Store]) -> Store:
	var site := d.owner as ConstructionSite
	if site and site.moved and site.pile_store.available(res) >= least - 0.000001 \
			and _cost(site.pile_store, dspot) < INF:
		return site.pile_store
	var best: Store = null
	var best_cost := INF
	for s in suppliers:
		if s.available(res) < least - 0.000001 or (s.owner == d.owner and s.owner != null):
			continue
		var c := _cost(s, dspot)
		if c < best_cost:
			best_cost = c
			best = s
	return best


# --- clears --------------------------------------------------------------------

func _plan_clear(s: Store, barns: Array[Store]) -> void:
	match s.kind:
		Store.Kind.OUTPUT:
			# full loads; the smaller rest once the mill has nothing left to do
			var mill := s.owner
			var r := mill.recipe()
			var idle: bool = mill.process_task == null and mill.input < 0.0001 \
				and mill.input_store.reserved_in.get(r["in"], 0.0) < 0.0001
			_clear(s, r["out"], s.available(r["out"]), idle, barns)
		Store.Kind.GATE:
			# fields the pickup can reach by road keep the pile for the pickup (from PICKUP_HAUL_MIN,
			# and while harvesting); a smaller rest goes by hand once nobody is harvesting
			var f := s.owner as Field
			var free := s.available(f.crop)
			if free < 0.01:
				return
			if world.pickup_collects(f) and (free >= Defs.PICKUP_HAUL_MIN or _rows_to_harvest(f)):
				return
			_clear(s, f.crop, free, not _harvest_running(f), barns)
		Store.Kind.GROUND:
			for res: StringName in s.contents.keys():
				_clear(s, res, s.available(res), true, barns)


## Hand loads of `amount` from `s` to the cheapest barn with room.
func _clear(s: Store, res: StringName, amount: float, rest: bool, barns: Array[Store]) -> void:
	var sspot: Variant = _spot(s)
	if sspot == null:
		return
	var hand := Defs.hand_load(res)
	while true:
		var load := minf(hand, amount)
		if Defs.is_piece(res):
			load = floorf(load + 0.000001)
		if load < 0.01 or (load < hand - 0.0001 and not rest):
			return
		var barn: Store = null
		var best_cost := INF
		for b in barns:
			if world.want(b, res) < minf(load, 1.0):
				continue
			var bspot: Variant = _spot(b)
			if bspot == null:
				continue
			var c := world.nav.walk_cost(sspot, bspot)
			if c < best_cost:
				best_cost = c
				barn = b
		if barn == null:
			return
		load = minf(load, world.want(barn, res))
		_leg(s, barn, res, load, _spot(barn))
		amount -= load


func _rows_to_harvest(f: Field) -> bool:
	for r in f.size.y:
		if f.row_step[r] == Field.RowStep.HARVEST:
			return true
	return false


func _harvest_running(f: Field) -> bool:
	for r in f.size.y:
		var t: Task = f.row_task[r]
		if t and t.step == &"harvest" and t.worker:
			return true
	return false


# --- legs ----------------------------------------------------------------------

## A carry leg of `load` from `src` to `d`, reserved at both ends. It serves the destination's
## owner for a need and the source's owner for a clear (Priorities and the panels follow that).
func _leg(src: Store, d: Store, res: StringName, load: float, dspot: Vector2i) -> void:
	var t := Task.new(Task.Kind.CARRY, dspot, Defs.LOAD_TIME, world.time)
	t.fetch = res
	t.fetch_amount = load
	t.src = src
	t.fetch_from = src
	t.fetch_reserved = src.reserve_out(res, load)
	t.dst = d
	t.dst_reserved = load
	d.reserve_in(res, load)
	t.category = Task.Category.TRANSPORT
	match d.kind:
		Store.Kind.SITE:
			t.site = d.owner
			t.category = Task.Category.CONSTRUCTION
		Store.Kind.INPUT:
			t.building = d.owner
		_:
			if src.kind == Store.Kind.GATE:
				t.field = src.owner
			elif src.kind == Store.Kind.OUTPUT:
				t.building = src.owner
	world.tasks.add(t)


func _spot(s: Store) -> Variant:
	if not _spots.has(s):
		_spots[s] = world.store_spot(s)
	return _spots[s]


## Walking cost from the store to `to`, INF when there is nowhere to stand or no way.
func _cost(s: Store, to: Vector2i) -> float:
	var from: Variant = _spot(s)
	return INF if from == null else world.nav.walk_cost(from, to)
