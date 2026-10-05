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
## A clear source (mill output, gate, ground pile) counts as cheaper for a need by the walk it saves
## (to its barn), so logs go straight to a sawmill; a need may also take over goods from a clear leg
## nobody has picked up yet. Waiting legs whose ends can no longer be reached are dropped (their
## claims released) so the goods are planned again.
##
## Cost per run: one pass over World.places() and the waiting legs, and walk_cost lookups only for
## sources that hold the good (memoised in Nav, see Nav._cost_memo). Lookups that are not memoised
## yet stop once the run has spent Defs.PLANNER_BUDGET_USEC (one is always allowed); the rest
## waits for the next run. Which part goes first (needs, clears, the stranded check) rotates every
## run, so none of them waits for good when the budget keeps running out.

var world: World
var ticks := 0              # measurements: runs, total and worst time of tick() in µs
var usec_total := 0
var usec_max := 0
var usec_last := 0          # time of the last run in µs
var paths := 0              # walk_cost lookups that were not memoised, in the last run
var lookup_usec_max := 0    # the longest of them in µs
var starved := false        # the time budget of this run is spent: the rest waits for the next run
var _timer := 0.0
var _t0 := 0                # start of this run (Time.get_ticks_usec)
var _sweep_at := 0          # where the stranded check goes on in the next run, when it ran out of budget
var _spots := {}            # Store -> cell to stand at (or null), for one run
var _takeable := {}         # Store -> {res -> Array[Task]}: waiting clear legs from it, for one run
var _saved := {}            # Store -> {res -> walk it saves a need to take from this clear source}


func _init(w: World) -> void:
	world = w


func update(dt: float) -> void:
	_timer -= dt
	if _timer <= 0.0:
		_timer = maxf(_timer + Defs.PLANNER_INTERVAL, 0.0)
		tick()


func tick() -> void:
	_t0 = Time.get_ticks_usec()
	paths = 0
	lookup_usec_max = 0
	starved = false
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
	for t in world.tasks.tasks:
		if world.waiting_clear(t):
			if not _takeable.has(t.fetch_from):
				_takeable[t.fetch_from] = {}
			if not _takeable[t.fetch_from].has(t.fetch):
				_takeable[t.fetch_from][t.fetch] = []
			_takeable[t.fetch_from][t.fetch].append(t)
	# High priority buildings get scarce goods first, then the oldest
	needs.sort_custom(func(a: Store, b: Store) -> bool:
		if a.owner.priority != b.owner.priority:
			return a.owner.priority > b.owner.priority
		return a.owner.id < b.owner.id)
	for i in 3:
		match (ticks + i) % 3:
			0:
				for d in needs:
					if starved:
						break
					_plan_need(d, suppliers, barns)
			1:
				if not barns.is_empty():
					for s in clears:
						if starved:
							break
						_plan_clear(s, barns)
			2:
				_drop_stranded()
	_spots.clear()
	_takeable.clear()
	_saved.clear()
	usec_last = Time.get_ticks_usec() - _t0
	ticks += 1
	usec_total += usec_last
	usec_max = maxi(usec_max, usec_last)


## Waiting legs whose source or destination has nowhere to stand or can't be walked between any
## more (walled off since they were planned) are dropped with their claims, so the goods and the
## need are planned again from places that can be reached. Out of budget, it still checks the legs
## with memoised costs and goes on from the first one it skipped in the next run.
func _drop_stranded() -> void:
	var legs := world.tasks.tasks.duplicate()
	var n := legs.size()
	var start := _sweep_at % maxi(n, 1)
	_sweep_at = 0
	var skipped := false
	for i in n:
		var t: Task = legs[(start + i) % n]
		if t.kind != Task.Kind.CARRY or t.worker != null or t.fetch_from == null or t.dst == null:
			continue
		var from: Variant = _spot(t.fetch_from)
		var to: Variant = _spot(t.dst)
		if from != null and to != null:
			var c := _walk(from, to)
			if c == INF and starved and not world.nav.has_cost(from, to):
				if not skipped:
					skipped = true
					_sweep_at = (start + i) % n
				continue
			if c < INF:
				continue
		_forget_takeable(t)
		world.tasks.remove(t)


## A dropped leg can no longer be taken over by a need in this run.
func _forget_takeable(t: Task) -> void:
	if _takeable.has(t.fetch_from) and _takeable[t.fetch_from].has(t.fetch):
		_takeable[t.fetch_from][t.fetch].erase(t)


# --- needs ---------------------------------------------------------------------

func _plan_need(d: Store, suppliers: Array[Store], barns: Array[Store]) -> void:
	var dspot: Variant = _spot(d)
	if dspot == null:
		return
	var wanted := world.wanted(d)
	for res: StringName in wanted:
		var want: float = wanted[res]
		# a mill takes whole kilos (a smaller rest is not worth a walk), a site everything it lacks
		var least := 1.0 if Defs.is_piece(res) or d.kind == Store.Kind.INPUT else 0.01
		while want >= least - 0.000001:
			var src := _source(d, res, dspot, least, suppliers, barns)
			if src == null:
				break
			var free := src.available(res)
			var load := minf(minf(Defs.hand_load(res), want), free + _takeable_amount(src, res))
			if Defs.is_piece(res):
				load = floorf(load + 0.000001)
			if load < least - 0.000001:
				break
			if load > free + 0.000001:
				_take_over(src, res, load - free)
			_leg(src, d, res, load, dspot)
			want -= load


## The supplier of `res` cheapest to walk from to `dspot`. A source that has to be cleared anyway
## (mill output, gate, ground pile) is worth the walk to its cheapest barn less, which it saves;
## its goods in waiting clear legs count too. A moved building's own pile supplies only its own
## site, and is tried first. Null also when the lookup budget runs out.
func _source(d: Store, res: StringName, dspot: Vector2i, least: float, suppliers: Array[Store],
		barns: Array[Store]) -> Store:
	var site := d.owner as ConstructionSite
	if site and site.moved and site.pile_store.available(res) >= least - 0.000001:
		var c := _cost(site.pile_store, dspot)
		if starved:
			return null
		if c < INF:
			return site.pile_store
	var best: Store = null
	var best_cost := INF
	for s in suppliers:
		if s.available(res) + _takeable_amount(s, res) < least - 0.000001 or (s.owner == d.owner and s.owner != null):
			continue
		var c := _cost(s, dspot)
		if c < INF:
			c -= _saves(s, res, barns)
		if starved:
			return null
		if c < best_cost:
			best_cost = c
			best = s
	return best


## The walk a need saves by taking `res` from a clear source: from there to the cheapest barn that
## takes it (0 for a barn, or with no such barn).
func _saves(s: Store, res: StringName, barns: Array[Store]) -> float:
	if s.kind != Store.Kind.OUTPUT and s.kind != Store.Kind.GATE and s.kind != Store.Kind.GROUND:
		return 0.0
	if _saved.has(s) and _saved[s].has(res):
		return _saved[s][res]
	var best := INF
	for b in barns:
		if world.want(b, res) < 1.0 - 0.000001:
			continue
		var bspot: Variant = _spot(b)
		if bspot == null:
			continue
		best = minf(best, _cost(s, bspot))
		if starved:
			return 0.0
	var saved := 0.0 if best == INF else best
	if not _saved.has(s):
		_saved[s] = {}
	_saved[s][res] = saved
	return saved


## Goods of `res` at `s` held by waiting clear legs that a need may take over.
func _takeable_amount(s: Store, res: StringName) -> float:
	var n := 0.0
	for t: Task in _takeable.get(s, {}).get(res, []):
		n += t.fetch_reserved
	return n


## Frees `n` of `res` at `s` from waiting clear legs (they shrink or go, their claims with them),
## for a need to claim right away.
func _take_over(s: Store, res: StringName, n: float) -> void:
	var legs: Array = _takeable.get(s, {}).get(res, [])
	while n > 0.000001 and not legs.is_empty():
		var t: Task = legs.back()
		var x := minf(n, t.fetch_reserved)
		n -= x
		if t.fetch_reserved - x < (1.0 if Defs.is_piece(res) else 0.01) - 0.000001:
			world.tasks.remove(t)       # all its claims let go
			legs.pop_back()
			continue
		s.release_out(res, x)
		t.fetch_reserved -= x
		t.fetch_amount -= x
		t.dst.release_in(res, x)
		t.dst_reserved -= x


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
			var c := _walk(sspot, bspot)
			if c < best_cost:
				best_cost = c
				barn = b
		if barn == null or starved:
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
	if src.kind == Store.Kind.GROUND and d.kind != Store.Kind.SITE:
		t.category = src.category       # felled logs count as Felling wherever they go
	world.tasks.add(t)


func _spot(s: Store) -> Variant:
	if not _spots.has(s):
		_spots[s] = world.store_spot(s)
	return _spots[s]


## Walking cost from the store to `to`, INF when there is nowhere to stand or no way.
func _cost(s: Store, to: Vector2i) -> float:
	var from: Variant = _spot(s)
	return INF if from == null else _walk(from, to)


## Nav.walk_cost within the budget of this run: memoised costs always, others until the run has
## spent Defs.PLANNER_BUDGET_USEC (at least one per run). Then the run is starved (INF, callers
## stop) and the rest waits for the next run.
func _walk(from: Vector2i, to: Vector2i) -> float:
	if world.nav.has_cost(from, to):
		return world.nav.walk_cost(from, to)
	if starved or (paths > 0 and Time.get_ticks_usec() - _t0 >= Defs.PLANNER_BUDGET_USEC):
		starved = true
		return INF
	paths += 1
	var t := Time.get_ticks_usec()
	var c := world.nav.walk_cost(from, to)
	lookup_usec_max = maxi(lookup_usec_max, Time.get_ticks_usec() - t)
	return c
