class_name Planner
extends RefCounted
## The central logistics planner. Every Defs.PLANNER_INTERVAL seconds of game time it reads what
## places want (Need: a site's missing material, a mill's room for raw goods) and what must leave
## them (Clear: mill products, the harvest at a field gate, ground piles) and turns that into carry
## legs: from the source that is cheapest to bring from to the destination, with the goods reserved
## at the source and the room at the destination. Needs come first, so a clear can feed a need
## directly (wheat at a gate into a mill); the rest of a clear goes to the cheapest barn.
##
## Route by cost (_route): a carry is walked (one CARRY leg), or, when it is long and a vehicle can
## run trips, goes via the pickup when that costs less: walked to a hand-off by the road (the store
## itself when it is a vehicle stop, else a road pile), driven to a hand-off by the destination
## (RIDE), walked the rest. Such a chain of legs is linked by Task.next: only the first leg is queued,
## the later ones already hold the room at their destination and open as the goods arrive
## (World._open_next).
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
var _handoffs := {}         # Store -> itself (a vehicle stop), a road pile spot (Vector2i) or null, until the grid or the road changes
var _handoffs_key := Vector3i(-1, -1, -1)   # nav version, road version, vehicle block the hand-offs were found for
var _joins := {}            # Vector2i spot -> {res -> road pile to join or the spot}, for one run
var _road_piles: Array[Store] = []  # ground piles of origin ROAD, for one run
var _vblock: Variant = null # the road block of a vehicle that can run trips, for one run (null: none)


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
	_vblock = world.drive_block()
	var key := Vector3i(world.nav.version, world.road_nav.version, (_vblock.x << 16) | _vblock.y if _vblock != null else -1)
	if key != _handoffs_key or _handoffs.size() > 4000:
		_handoffs.clear()
		_handoffs_key = key
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
				if s.origin == Store.Origin.ROAD and s.kind == Store.Kind.GROUND:
					_road_piles.append(s)
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
	_joins.clear()
	_road_piles.clear()
	_sweep_piles()
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
		if t.kind == Task.Kind.RIDE and t.trip == null and t.fetch_from != null and t.dst != null:
			# a waiting ride whose ends are no stops any more, or not connected
			var a: Variant = world.stop_block(t.fetch_from)
			var b: Variant = world.stop_block(t.dst)
			if a == null or b == null or _vblock == null or world.road_nav.drive_cost(a, b) == INF:
				world.tasks.remove(t)
			continue
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


## Empty ground piles nothing is on its way to (a road pile whose goods were taken, or whose legs
## were dropped) go away. O(piles).
func _sweep_piles() -> void:
	for s in world.ground_piles.duplicate():
		if s.contents.is_empty() and s.reserved_in.is_empty():
			world._remove_pile(s)


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
			var route := _source(d, res, least, suppliers, barns)
			if route.is_empty():
				break
			var src: Store = route["src"]
			var free := src.available(res)
			var load := minf(minf(_load_cap(src, d, res, route), want), free + _takeable_amount(src, res))
			if Defs.is_piece(res):
				load = floorf(load + 0.000001)
			if load < least - 0.000001:
				break
			if load > free + 0.000001:
				_take_over(src, res, load - free)
			_send(src, d, res, load, route)
			want -= load


## The supplier of `res` cheapest to bring from to `d` (by route, see _route): its route with the
## source under "src", or {} (also when the lookup budget runs out). A source that has to be cleared
## anyway (mill output, gate, ground pile) is worth the walk to its cheapest barn less, which it
## saves; its goods in waiting clear legs count too. A moved building's own pile supplies only its
## own site, and is tried first.
func _source(d: Store, res: StringName, least: float, suppliers: Array[Store],
		barns: Array[Store]) -> Dictionary:
	var site := d.owner as ConstructionSite
	if site and site.moved and site.pile_store.available(res) >= least - 0.000001:
		var r := _route(site.pile_store, d, res)
		if starved:
			return {}
		if r["cost"] < INF:
			r["src"] = site.pile_store
			return r
	var best := {}
	var best_cost := INF
	for s in suppliers:
		if s.available(res) + _takeable_amount(s, res) < least - 0.000001 or (s.owner == d.owner and s.owner != null):
			continue
		var r := _route(s, d, res)
		var c: float = r["cost"]
		if c < INF:
			c -= _saves(s, res, barns) / Defs.WALK_SPEED * Defs.WALK_COST
		if starved:
			return {}
		if c < best_cost:
			best_cost = c
			best = r
			best["src"] = s
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


## Loads of `amount` from `s` to the barn cheapest to bring to (by route): hand loads, or a pickup
## load when the pickup takes it from door to door.
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
		var route := {}
		for b in barns:
			if world.want(b, res) < minf(load, 1.0):
				continue
			if _spot(b) == null:
				continue
			var r := _route(s, b, res)
			if r["cost"] < route.get("cost", INF):
				route = r
				barn = b
		if barn == null or starved:
			return
		load = minf(_load_cap(s, barn, res, route), amount)
		if Defs.is_piece(res):
			load = floorf(load + 0.000001)
		load = minf(load, world.want(barn, res))
		_send(s, barn, res, load, route)
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


# --- routes and legs -----------------------------------------------------------

## How to bring `res` from `src` to `dst`: {"cost": float, "a": Variant, "b": Variant}. Direct (a, b
## null): the walk in seconds × WALK_COST (INF when either end is vehicle-only or can't be walked).
## Via the pickup (a, b the hand-offs at the source and destination side: a Store, or a Vector2i
## road pile spot still to make): walk to a, load, drive to b, unload, walk on, plus the expected
## wait for the pickup. The via route is looked at only when a vehicle can run trips, the source
## is not carried by hand on purpose (Store.hand_only) and the walk is at least ROUTE_MIN_WALK
## tiles (or impossible); the cheaper one wins.
func _route(src: Store, dst: Store, res: StringName) -> Dictionary:
	var out := {"cost": INF, "a": null, "b": null}
	var walk := INF
	if not src.vehicle_only() and not dst.vehicle_only():
		var from: Variant = _spot(src)
		var to: Variant = _spot(dst)
		if from != null and to != null:
			walk = _walk(from, to)
			out["cost"] = walk / Defs.WALK_SPEED * Defs.WALK_COST
	if starved or _vblock == null or src.hand_only or walk < Defs.ROUTE_MIN_WALK:
		return out
	var a: Variant = _handoff(src, res)
	var b: Variant = _handoff(dst, res)
	if a == null or b == null or (typeof(a) == typeof(b) and a == b):
		return out
	var drive := world.road_nav.drive_cost(_block_of(a), _block_of(b))
	if drive == INF:
		return out
	var walks := _walk_between(src, a) + _walk_between(dst, b)
	if starved or walks == INF:
		return out
	var via := walks / Defs.WALK_SPEED * Defs.WALK_COST + 2.0 * Defs.HANDLING_COST \
		+ drive * Defs.DRIVE_COST + Defs.VEHICLE_WAIT_COST
	if via < out["cost"]:
		out = {"cost": via, "a": a, "b": b}
	return out


## The hand-off of a store for `res`: the store itself when it is a vehicle stop the pickup can
## reach, else an existing road pile of the good with room within ROAD_PILE_JOIN of the road pile
## spot nearest it, else that spot (Vector2i); null when there is no road near. Cached for the run.
func _handoff(s: Store, res: StringName) -> Variant:
	if not _handoffs.has(s):
		var block: Variant = world.stop_block(s)
		if block != null and world.road_nav.drive_cost(_vblock, block) < INF:
			_handoffs[s] = s
		elif s.vehicle_only() or _spot(s) == null:
			_handoffs[s] = null
		else:
			_handoffs[s] = world.road_pile_spot(_spot(s))
	var h: Variant = _handoffs[s]
	return _join(h, res) if h is Vector2i else h


## A road pile of `res` with room for a hand load within ROAD_PILE_JOIN of `spot` (nearest first),
## else the spot. O(road piles), memoised for the run.
func _join(spot: Vector2i, res: StringName) -> Variant:
	if not _joins.has(spot):
		_joins[spot] = {}
	if not _joins[spot].has(res):
		var best: Variant = spot
		var best_d := INF
		var kg := Defs.weight(res, Defs.hand_load(res))
		for p in _road_piles:
			var dc := p.cell - spot
			var d := dc.x * dc.x + dc.y * dc.y
			if maxi(absi(dc.x), absi(dc.y)) <= Defs.ROAD_PILE_JOIN and d < best_d and not p.hand_only \
					and p.accepts(res) and p.room() >= kg - 0.000001:
				best_d = d
				best = p
		_joins[spot][res] = best
	return _joins[spot][res]


## The road block a vehicle stops at for a hand-off (a store or a road pile spot).
func _block_of(h: Variant) -> Variant:
	return world.stop_block(h) if h is Store else world.road_nav.block_near(h, Defs.STOP_REACH)


## Walk between a store and its hand-off (0 when it is its own).
func _walk_between(s: Store, h: Variant) -> float:
	if h is Store and h == s:
		return 0.0
	var at: Variant = _spot(h) if h is Store else h
	return _cost(s, at) if at != null else INF


## How much one route carries at most: a pickup load when the pickup takes it from door to door,
## else a hand load.
func _load_cap(src: Store, d: Store, res: StringName, route: Dictionary) -> float:
	var a: Variant = route.get("a")
	var b: Variant = route.get("b")
	if a is Store and a == src and b is Store and b == d:
		return Defs.PICKUP_CAPACITY / Defs.weight(res, 1.0)
	return Defs.hand_load(res)


## Sends `load` of `res` from `src` to `d` along the route: one carry leg (direct), or a chain of
## legs via the pickup (walk to hand-off A, ride A → B, walk on; a road pile spot becomes a road
## pile now). Only the first leg is queued, holding the goods at `src`; every leg holds the room at
## its destination. A ride-only chain grows a waiting ride with the same ends instead, up to a
## pickup load.
func _send(src: Store, d: Store, res: StringName, load: float, route: Dictionary) -> void:
	if route.get("a") == null:
		_leg(src, d, res, load, _spot(d))
		return
	var cat := _category(src, d)
	var a := _hand_store(route["a"], res, load, src, cat)
	var b := _hand_store(route["b"], res, load, d, cat)
	if a == null or b == null:
		_leg(src, d, res, load, _spot(d) if _spot(d) != null else d.cell)
		return
	var plan: Array[Dictionary] = []
	if a != src:
		plan.append({"by": &"walk", "from": src, "to": a})
	plan.append({"by": &"ride", "from": a, "to": b})
	if b != d:
		plan.append({"by": &"walk", "from": b, "to": d})
	if plan.size() == 1:
		for t in world.tasks.tasks:
			if t.kind == Task.Kind.RIDE and t.trip == null and t.plan.size() == 1 and t.fetch_from == src \
					and t.dst == d and t.fetch == res and t.fetch_amount + load <= _load_cap(src, d, res, route) + 0.000001:
				t.fetch_reserved += src.reserve_out(res, load)
				t.fetch_amount += load
				d.reserve_in(res, load)
				t.dst_reserved += load
				return
	var prev: Task = null
	for i in plan.size():
		var leg: Dictionary = plan[i]
		var to: Store = leg["to"]
		var spot: Variant = _spot(to)
		var t := Task.new(Task.Kind.CARRY if leg["by"] == &"walk" else Task.Kind.RIDE,
			spot if spot != null else to.cell, Defs.LOAD_TIME, world.time)
		t.fetch = res
		t.fetch_amount = load
		t.src = leg["from"]
		t.dst = to
		t.dst_reserved = load
		to.reserve_in(res, load)
		t.plan = plan
		t.leg_i = i
		_serve(t, src, d)
		if prev:
			prev.next = t
		else:
			t.fetch_from = src
			t.fetch_reserved = src.reserve_out(res, load)
			world.tasks.add(t)
		prev = t


## The store a hand-off stands for: the store itself, a road pile with room for the load, or a new
## road pile on its spot (on the next free spot by the road when it is taken). Null if none.
func _hand_store(h: Variant, res: StringName, load: float, end: Store, category: int) -> Store:
	if h is Store:
		var s: Store = h
		if s == end or s.room() >= Defs.weight(res, load) - 0.000001:
			return s
		h = null
	if h == null or world.ground_pile_at(h) != null:
		var spot: Variant = _spot(end)
		h = world.road_pile_spot(spot) if spot != null else null
		if h == null:
			return null
	_joins.clear()
	var pile := world.add_road_pile(h, res, category)
	_road_piles.append(pile)
	return pile


## A carry leg of `load` from `src` to `d`, reserved at both ends (see _serve).
func _leg(src: Store, d: Store, res: StringName, load: float, dspot: Vector2i) -> Task:
	var t := Task.new(Task.Kind.CARRY, dspot, Defs.LOAD_TIME, world.time)
	t.fetch = res
	t.fetch_amount = load
	t.src = src
	t.fetch_from = src
	t.fetch_reserved = src.reserve_out(res, load)
	t.dst = d
	t.dst_reserved = load
	d.reserve_in(res, load)
	_serve(t, src, d)
	world.tasks.add(t)
	return t


## Category and served owner of a leg (every leg of a chain alike) bringing goods from `src` to
## `d`: the destination's owner for a need, the source's owner for a clear (Priorities and the
## panels follow that); felled logs count as Felling wherever they go.
func _serve(t: Task, src: Store, d: Store) -> void:
	t.category = _category(src, d)
	match d.kind:
		Store.Kind.SITE:
			t.site = d.owner
		Store.Kind.INPUT:
			t.building = d.owner
		_:
			if src.kind == Store.Kind.GATE:
				t.field = src.owner
			elif src.kind == Store.Kind.OUTPUT:
				t.building = src.owner


func _category(src: Store, d: Store) -> int:
	if d.kind == Store.Kind.SITE:
		return Task.Category.CONSTRUCTION
	if src.kind == Store.Kind.GROUND:
		return src.category
	return Task.Category.TRANSPORT


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
