extends SceneTree
## Logistics checks: stores, goods in places, the planner and its carry legs (cheapest source by
## path, needs before clearing, reservations), delivery to the reached barn, conservation.
##   Godot --headless --path . --script scripts/tools/logistics_test.gd


func _init() -> void:
	var ok := true
	ok = _store_checks() and ok
	ok = _world_checks() and ok
	ok = _conservation_checks() and ok
	ok = _claim_checks() and ok
	ok = _split_checks() and ok
	ok = _removed_barn_checks() and ok
	ok = _release_checks() and ok
	ok = _wheelbarrow_checks() and ok
	ok = _save_checks() and ok
	ok = _test_places() and ok
	ok = _test_walk_cost() and ok
	ok = _test_cheapest_source() and ok
	ok = _test_gate_to_mill() and ok
	ok = _test_demolish_in_flight() and ok
	ok = _test_long_run() and ok
	ok = _test_ground_piles() and ok
	ok = _test_felled_pile() and ok
	ok = _test_felled_to_sawmill() and ok
	ok = _test_abort_drops() and ok
	ok = _test_pile_save() and ok
	ok = _test_stranded_leg() and ok
	ok = _test_wheelbarrow_backlog() and ok
	ok = _test_nav_version() and ok
	ok = _test_take_over_clear() and ok
	ok = _test_pile_to_sawmill() and ok
	ok = _test_lazy_pick() and ok
	ok = _test_save_mid_transfer() and ok
	ok = _test_planner_budget() and ok
	ok = _test_open_keeps_memo() and ok
	print("LOGISTICS TEST ", "OK" if ok else "FAILED")
	quit()


func _store_checks() -> bool:
	var ok := true
	var s := Store.new()
	s.put(&"wheat", 120.0)
	s.put(&"planks", 5.0)
	ok = _check("a store keeps what is put in", s.amount(&"wheat") == 120.0 and s.amount(&"planks") == 5.0) and ok
	ok = _check("weight counts pieces by their weight", absf(s.weight() - (120.0 + 5.0 * Defs.PLANK_WEIGHT)) < 0.001) and ok
	var got := s.reserve_out(&"wheat", 100.0)
	ok = _check("a reservation holds goods back", got == 100.0 and s.available(&"wheat") == 20.0 and s.amount(&"wheat") == 120.0) and ok
	ok = _check("a reservation never exceeds what is there", s.reserve_out(&"wheat", 50.0) == 20.0 and s.available(&"wheat") == 0.0) and ok
	s.release_out(&"wheat", 120.0)
	ok = _check("released goods are available again", s.available(&"wheat") == 120.0) and ok
	ok = _check("take never takes more than there is", s.take(&"planks", 9.0) == 5.0 and s.amount(&"planks") == 0.0
		and not s.contents.has(&"planks")) and ok
	s.filter = {&"wood": true}
	ok = _check("a filter limits what a store accepts", s.accepts(&"wood") and not s.accepts(&"wheat")) and ok
	s.filter = {}
	s.capacity = 200.0
	ok = _check("room is capacity minus weight", absf(s.room() - 80.0) < 0.001) and ok
	var back := Store.from_dict(s.to_dict())
	ok = _check("a store survives to_dict / from_dict", back.amount(&"wheat") == 120.0 and back.capacity == 200.0) and ok
	return ok


func _world_checks() -> bool:
	var ok := true
	var w := WorldGen.generate(256, 7)
	var barn: Building = w.stores()[0]
	ok = _check("the start barn has a store", w.stores().size() == 1 and barn.store != null) and ok
	w.set_stock(&"planks", 40.0)
	ok = _check("set_stock puts goods in the barn", barn.store.amount(&"planks") == 40.0 and w.total(&"planks") == 40.0) and ok
	w.put_goods(&"wheat", 100.0)
	ok = _check("put_goods adds to the barn", w.total(&"wheat") == 100.0) and ok
	ok = _check("take_goods takes what there is", w.take_goods(&"wheat", 150.0) == 100.0 and w.total(&"wheat") == 0.0) and ok
	ok = _check("totals lists every good in order", w.totals().keys().slice(0, World.GOODS.size()) == World.GOODS) and ok
	ok = _check("the split names the barn", w.stock_split(&"planks") == [[Defs.def(&"storage_barn")["name"], 40.0]]) and ok
	return ok


## A site's need is met even when no single barn holds all of it: legs come from both barns, and
## the site never starts building short of its material.
func _split_checks() -> bool:
	var ok := true
	var w := WorldGen.generate(256, 7)
	w.money = 100000
	w.unlocked[Tech.node_for_building(&"hand_mill")] = true
	var a: Building = w.stores()[0]
	var b := _second_barn(w)
	w.set_stock(&"planks", 0.0)
	a.store.put(&"planks", 20.0)
	b.store.put(&"planks", 15.0)
	var before := w.total(&"planks")
	var site := w.place_site(&"hand_mill", _spot(w, &"hand_mill", a.access), 2)
	ok = _check("a site waiting for planks", site != null and site.stage == ConstructionSite.Stage.DELIVERY) and ok
	if site == null:
		return false
	var started_short := false
	var elapsed := 0.0
	while elapsed < 300.0 and site.delivered.get(&"planks", 0.0) < 29.999:
		w.tick(0.1)
		elapsed += 0.1
		if site.stage == ConstructionSite.Stage.BUILDING and site.delivered.get(&"planks", 0.0) < 29.999:
			started_short = true
	ok = _check("planks from two barns reach the site (%d s)" % elapsed,
		absf(site.delivered.get(&"planks", 0.0) - 30.0) < 0.001) and ok
	ok = _check("the site never starts building short of its material", not started_short) and ok
	ok = _check("totals and delivered are conserved",
		absf(w.total(&"planks") + site.delivered.get(&"planks", 0.0) + _carried(w, &"planks") - before) < 0.001) and ok
	return ok


## Goods survive a barn move; a leg never claims goods promised to someone else.
func _conservation_checks() -> bool:
	var ok := true
	var w := World.new(64, 1)
	var barn1 := w.add_building(&"storage_barn", Vector2i(10, 10), 0)
	w.add_building(&"storage_barn", Vector2i(20, 10), 0)
	w.set_stock(&"wheat", 200.0)
	var moved := w.move_building(barn1, Vector2i(30, 10), 0)
	ok = _check("moving a barn keeps its goods", moved != null and w.total(&"wheat") == 200.0) and ok

	var w2 := World.new(64, 1)
	var barn2 := w2.add_building(&"storage_barn", Vector2i(10, 10), 0)
	var mill := w2.add_building(&"hand_mill", Vector2i(10, 30), 0)
	w2.set_stock(&"wheat", 50.0)
	barn2.store.reserve_out(&"wheat", 40.0)         # 40 of it already promised elsewhere
	w2.planner.tick()
	var planned := 0.0
	for t in _legs(w2, mill.input_store):
		planned += t.fetch_amount
	ok = _check("legs only claim what is not promised yet (%.0f kg)" % planned, absf(planned - 10.0) < 0.001
		and barn2.store.available(&"wheat") == 0.0) and ok
	return ok


## A second barn next to the first one, by the same road.
func _second_barn(w: World) -> Building:
	var first: Building = w.stores()[0]
	for r in range(4, 40):
		for dy in range(-r, r + 1):
			for dx in [-r, r]:
				var a: Vector2i = first.anchor + Vector2i(dx, dy)
				if w.can_place(&"storage_barn", a, first.rot) \
						and not w.nav.find_path(first.access, Defs.access_cell(&"storage_barn", a, first.rot)).is_empty():
					return w.add_building(&"storage_barn", a, first.rot)
	return null


## A spot for the building near `near` with no trees on or around it, reachable from there.
func _spot(w: World, id: StringName, near: Vector2i, rot := 2) -> Vector2i:
	var fs := Defs.footprint(id, rot)
	for r in range(3, 60):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var a := near + Vector2i(dx, dy)
				if w.can_place(id, a, rot) and not _trees(w, Rect2i(a - Vector2i(2, 2), fs + Vector2i(4, 4))) \
						and w.nav.find_path(near, Defs.access_cell(id, a, rot)).size() > 0:
					return a
	return near


func _trees(w: World, r: Rect2i) -> bool:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if w.has_tree(Vector2i(x, y)):
				return true
	return false


func _claim_checks() -> bool:
	var ok := true
	var w := WorldGen.generate(256, 7)
	w.money = 100000
	w.unlocked[Tech.node_for_building(&"hand_mill")] = true
	var a: Building = w.stores()[0]
	var b := _second_barn(w)
	ok = _check("a second barn gets its own store", b != null and w.stores().size() == 2 and b.store != null) and ok
	w.set_stock(&"planks", 0.0)
	b.store.put(&"planks", 30.0)
	var s1 := w.place_site(&"hand_mill", _spot(w, &"hand_mill", b.access), 2)
	var s2 := w.place_site(&"hand_mill", _spot(w, &"hand_mill", b.access + Vector2i(8, 0)), 2)
	w.planner.tick()
	var reserved := 0.0
	for t in _legs(w):
		reserved += t.fetch_reserved
	ok = _check("legs go to the barn that has the goods", _legs(w).size() > 0
		and _legs(w).all(func(t: Task) -> bool: return t.fetch_from == b.store)) and ok
	ok = _check("claimed goods are not claimed twice (%.0f of 30)" % reserved, absf(reserved - 30.0) < 0.001
		and b.store.available(&"planks") == 0.0 and s1 != null and s2 != null) and ok
	ok = _check("reservations match the legs", _reservations_match(w)) and ok
	var t0: Task = _legs(w)[0]
	t0.release()
	t0.release()
	w.tasks.remove(t0)
	ok = _check("releasing twice is harmless", absf(b.store.available(&"planks") - t0.fetch_amount) < 0.001
		and _reservations_match(w)) and ok
	for t in _legs(w):
		w.tasks.remove(t)
	ok = _check("a removed leg releases its claims", b.store.available(&"planks") == 30.0
		and s1.supply.reserved_in.is_empty() and s2.supply.reserved_in.is_empty()) and ok

	# a worker standing on barn B's access tile delivers into B
	var wk: Worker = w.workers[0]
	wk.pos = Vector2(b.access) + Vector2(0.5, 0.5)
	wk.carrying = &"wood"
	wk.carry_amount = 2.0
	w.deliver(wk)
	ok = _check("delivery goes into the barn the worker reached", b.store.amount(&"wood") == 2.0 and a.store.amount(&"wood") == 0.0) and ok

	# demolishing B moves its goods to A
	w.planner.tick()
	var before := w.total(&"planks") + w.total(&"wood")
	w.demolish(b)
	ok = _check("a demolished barn's goods move to the other barn", w.stores() == [a]
		and absf(a.store.amount(&"planks") + a.store.amount(&"wood") - before) < 0.001) and ok
	ok = _check("and its legs are gone, every claim released", _legs(w).all(func(t: Task) -> bool: return t.fetch_from != b.store)
		and _reservations_match(w)) and ok
	return ok


## A leg from a barn, and a worker on the way to it, must let go of both when the barn is removed —
## instead of duplicating the goods or sending the worker to a barn that no longer exists; the need
## is then planned again from where the goods went.
func _removed_barn_checks() -> bool:
	var ok := true
	var w := WorldGen.generate(256, 7)
	w.money = 100000
	w.unlocked[Tech.node_for_building(&"hand_mill")] = true
	var a: Building = w.stores()[0]
	var b := _second_barn(w)
	w.set_stock(&"planks", 0.0)
	b.store.put(&"planks", 30.0)
	var site := w.place_site(&"hand_mill", _spot(w, &"hand_mill", b.access), 2)
	w.planner.tick()
	var legs := _legs(w, site.supply)
	ok = _check("legs from barn B", legs.size() > 0 and legs.all(func(t: Task) -> bool: return t.fetch_from == b.store)) and ok
	var t: Task = legs[0]
	var worker: Worker = w.workers[0]
	t.worker = worker
	worker.task = t
	worker.phase = Worker.Phase.TO_FETCH
	worker.set_path([b.access])
	var before := _everywhere(w, &"planks")

	w.demolish(b)
	ok = _check("demolishing a barn drops the legs from it", _legs(w).all(func(x: Task) -> bool: return x.fetch_from != b.store)
		and not w.tasks.tasks.has(t)) and ok
	ok = _check("demolishing a claimed barn frees its worker", worker.task == null and worker.phase == Worker.Phase.IDLE) and ok
	ok = _check("every claim is released", _reservations_match(w) and site.supply.reserved_in.is_empty()) and ok
	ok = _check("demolishing a claimed barn neither loses nor duplicates its goods", absf(_everywhere(w, &"planks") - before) < 0.001) and ok
	w.planner.tick()
	legs = _legs(w, site.supply)
	ok = _check("the need is planned again from the barn that has the goods", legs.size() > 0
		and legs.all(func(x: Task) -> bool: return x.fetch_from == a.store)) and ok
	return ok


## Every way a worker can come off a leg lets go of its claims, so goods never stay reserved.
func _release_checks() -> bool:
	var ok := true
	for how in ["fetch fails", "abort", "remove_worker"]:
		var w := World.new(64, 1)
		var barn := w.add_building(&"storage_barn", Vector2i(10, 10), 0)
		var mill := w.add_building(&"hand_mill", Vector2i(10, 30), 0)
		barn.store.put(&"wheat", 10.0)
		w.planner.tick()
		var wk := w.add_worker(barn.access, Worker.Look.MALE)
		wk.tick(w, 0.1)
		var t := wk.task
		ok = _check("%s: the worker took the leg" % how, t != null and t.kind == Task.Kind.CARRY) and ok
		match how:
			"fetch fails":
				barn.store.contents.erase(&"wheat")      # the goods vanish behind the leg's back
				for i in 10:
					wk.tick(w, 0.1)
			"abort":
				wk.abort(w)
			"remove_worker":
				w.remove_worker()
		ok = _check("%s: the leg is gone and its claims released" % how, not w.tasks.tasks.has(t)
			and barn.store.reserved_out.is_empty() and mill.input_store.reserved_in.is_empty() and wk.task == null) and ok

	# a moved building's pile sealed off on every side: nobody can reach it, so no leg is planned
	# from it (and with no barn stock, none at all)
	var w4 := World.new(64, 1)
	w4.add_building(&"storage_barn", Vector2i(10, 10), 0)
	var site := ConstructionSite.new(999, &"storage_barn", Vector2i(40, 40), 0)
	site.moved = true
	site.needs = {&"planks": 20.0}
	site.stage = ConstructionSite.Stage.DELIVERY
	site.pile[&"planks"] = 20.0
	site.pile_cell = Vector2i(50, 50)
	w4.buildings[site.id] = site
	for d in Defs.DIRS:
		w4.nav.set_solid(site.pile_cell + d, true)
	w4.planner.tick()
	ok = _check("no leg from a pile nobody can reach", _legs(w4).is_empty() and site.pile_store.reserved_out.is_empty()) and ok
	return ok


## A big pile at a gate: a worker fetches a wheelbarrow and takes several hand loads at once; a
## wheelbarrow promised to someone else is never handed out too.
func _wheelbarrow_checks() -> bool:
	var ok := true
	var w := World.new(64, 1)
	var barn := w.add_building(&"storage_barn", Vector2i(4, 4), 0)
	var f := w.add_field(Vector2i(30, 30), 0, Vector2i(6, 6), &"wheat")
	w.set_category_on(Task.Category.PLANTING, false)
	barn.store.put(&"wheelbarrow", 1.0)
	f.pile = 200.0
	w.planner.tick()
	ok = _check("a gate pile is carried in hand loads (%d legs)" % _legs(w).size(), _legs(w).size() == 4
		and _legs(w).all(func(t: Task) -> bool: return t.dst == barn.store and t.fetch_amount == Defs.CARRY_CAPACITY)) and ok
	barn.store.reserve_out(&"wheelbarrow", 1.0)    # the only wheelbarrow is promised elsewhere
	var wk := w.add_worker(barn.access, Worker.Look.MALE)
	var t := w.tasks.pick(w, wk)
	ok = _check("a claimed wheelbarrow is never also handed out", t != null and t.kind == Task.Kind.CARRY and t.tool_from == null) and ok
	wk.task = t
	wk.phase = Worker.Phase.TO_FETCH
	barn.store.release_out(&"wheelbarrow", 1.0)
	var wk2 := w.add_worker(barn.access, Worker.Look.FEMALE)
	var t2 := w.tasks.pick(w, wk2)
	ok = _check("with a backlog the next worker takes the wheelbarrow and the other loads (%.0f kg)" % (t2.fetch_amount if t2 else 0.0),
		t2 != null and t2.tool_from == barn.store and t2.fetch_amount > Defs.CARRY_CAPACITY + 0.01
		and t2.fetch_amount <= Defs.WHEELBARROW_CAPACITY + 0.01 and _legs(w).size() == 2) and ok
	ok = _check("merged legs keep their claims", _reservations_match(w)) and ok
	if t2:
		wk2.task = t2
		wk2.phase = Worker.Phase.TO_TOOL
	var pushed := [false]
	_run(w, 600.0, func() -> bool:
		pushed[0] = pushed[0] or (wk2.equipment == &"wheelbarrow" and wk2.carrying == &"wheat")
		return f.pile < 0.01 and _carried(w, &"wheat") == 0.0 and wk2.equipment == &"" and _legs(w).is_empty())
	ok = _check("the wheelbarrow was pushed full", pushed[0]) and ok
	ok = _check("all wheat in the barn, the wheelbarrow back, nothing reserved", barn.store.amount(&"wheat") == 200.0
		and barn.store.amount(&"wheelbarrow") == 1.0 and _reservations_match(w) and barn.store.reserved_out.is_empty()) and ok
	return ok


# --- planner ---------------------------------------------------------------------------

## A need is served from the source that is cheapest to walk from, not the nearest in a straight line.
func _test_cheapest_source() -> bool:
	var ok := true
	var w := World.new(64, 1)
	var mill := w.add_building(&"hand_mill", Vector2i(30, 44), 0)
	var a := w.add_building(&"storage_barn", Vector2i(30, 28), 0)    # close by, but behind a wall
	var b := w.add_building(&"storage_barn", Vector2i(4, 44), 0)     # farther, in the open
	for x in range(0, 57):
		w.set_tree(Vector2i(x, 37), Defs.TreeKind.CONIFER, Defs.TreeStage.FULL)
	a.store.put(&"wheat", 500.0)
	b.store.put(&"wheat", 500.0)
	var sa := Vector2(a.access).distance_to(mill.access)
	var sb := Vector2(b.access).distance_to(mill.access)
	ok = _check("the walled-off barn is closer in a straight line (%.0f < %.0f)" % [sa, sb], sa < sb) and ok
	w.planner.tick()
	var legs := _legs(w, mill.input_store)
	ok = _check("the mill's need is planned (%d legs)" % legs.size(), legs.size() > 0) and ok
	ok = _check("every leg comes from the barn that is cheaper to walk from",
		legs.all(func(t: Task) -> bool: return t.fetch_from == b.store)) and ok
	var planned := 0.0
	for t in legs:
		planned += t.fetch_amount
	ok = _check("the mill is promised what it holds and no more (%.0f kg)" % planned, absf(planned - 200.0) < 0.01
		and absf(mill.input_store.reserved_in.get(&"wheat", 0.0) - 200.0) < 0.01
		and absf(b.store.reserved_out.get(&"wheat", 0.0) - 200.0) < 0.01) and ok
	w.planner.tick()
	ok = _check("planning again adds nothing", _legs(w, mill.input_store).size() == legs.size()) and ok
	ok = _check("a leg reads where it goes: %s" % legs[0].label(),
		legs[0].label() == "Carry wheat from %s to %s" % [b.store.label(), mill.input_store.label()]) and ok
	return ok


## Needs are planned before clearing: wheat at a gate goes straight into a mill that wants it, the
## rest to the barn, and the mill never holds more than it can.
func _test_gate_to_mill() -> bool:
	var ok := true
	var w := World.new(64, 1)
	var barn := w.add_building(&"storage_barn", Vector2i(4, 4), 0)
	var f := w.add_field(Vector2i(20, 4), 0, Vector2i(6, 6), &"wheat")
	var mill := w.add_building(&"hand_mill", Vector2i(20, 20), 0)
	w.set_category_on(Task.Category.PLANTING, false)
	f.pile = 150.0
	w.planner.tick()
	var from_gate := _legs(w).filter(func(t: Task) -> bool: return t.fetch_from == f.gate_store)
	ok = _check("wheat at the gate is planned (%d legs)" % from_gate.size(), from_gate.size() == 3) and ok
	ok = _check("and goes straight into the mill, not into the empty barn",
		from_gate.all(func(t: Task) -> bool: return t.dst == mill.input_store)) and ok
	f.pile += 400.0
	for i in 3:
		w.add_worker(barn.access, Worker.Look.MALE)
	var over := [false]
	var t := _run(w, 1200.0, func() -> bool:
		if mill.input + mill.input_store.reserved_in.get(&"wheat", 0.0) > float(mill.recipe()["in_cap"]) + 0.001:
			over[0] = true
		return f.pile < 0.01 and _carried(w, &"wheat") == 0.0)
	ok = _check("the gate is cleared (%d s), the rest is in the barn (%.0f kg)" % [t, barn.store.amount(&"wheat")],
		f.pile < 0.01 and barn.store.amount(&"wheat") > 0.0) and ok
	ok = _check("the mill input never goes above what it holds", not over[0]) and ok
	return ok


## A site demolished while its planks are on the way: every claim is released, nothing is lost.
func _test_demolish_in_flight() -> bool:
	var ok := true
	var w := WorldGen.generate(256, 7)
	w.money = 100000
	for res in w.auto_sell:
		w.auto_sell[res]["on"] = false
	var barn: Building = w.stores()[0]
	w.set_stock(&"planks", 200.0)
	var site := w.place_site(&"storage_barn", _spot(w, &"storage_barn", barn.access), 2)
	var before := _everywhere(w, &"planks")
	var t := _run(w, 600.0, func() -> bool:
		for wk in w.workers:
			if wk.task and wk.task.site == site and wk.carrying == &"planks":
				return true
		return false)
	ok = _check("planks on their way to the site (%d s)" % t, _carried(w, &"planks") > 0.0) and ok
	w.demolish(site)
	ok = _check("no leg is left for the demolished site", _legs(w).all(func(x: Task) -> bool: return x.site != site and x.dst != site.supply)) and ok
	ok = _check("every claim is released", _reservations_match(w)) and ok
	_run(w, 300.0, func() -> bool: return _carried(w, &"planks") == 0.0 and w.ground_piles.is_empty())
	ok = _check("nothing lost or duplicated (%.0f planks)" % _everywhere(w, &"planks"), absf(_everywhere(w, &"planks") - before) < 0.001
		and absf(w.total(&"planks") - before) < 0.001) and ok
	return ok


## A long run with sites, two barns and a gate pile: planks and wheat are never lost or duplicated,
## the reservations always match the legs, and the planner stays cheap.
func _test_long_run() -> bool:
	var ok := true
	var w := WorldGen.generate(256, 7)
	w.money = 100000
	for res in w.auto_sell:
		w.auto_sell[res]["on"] = false
	for crop: StringName in Defs.CROPS:
		w.set_stock(Defs.seed_of(crop), 0.0)       # nothing is sown, so no new harvest
	var barn: Building = w.stores()[0]
	var b2 := _second_barn(w)
	w.set_stock(&"planks", 150.0)
	b2.store.put(&"planks", 60.0)
	for i in 2:
		w.place_site(&"storage_barn", _spot(w, &"storage_barn", barn.access + Vector2i(10 * i, 12)), 2)
	var f := w.add_field(_field_spot(w, barn.access), 0, Vector2i(5, 5), &"wheat")
	f.pile = 220.0
	w.planner.ticks = 0
	w.planner.usec_total = 0
	w.planner.usec_max = 0
	var planks := _everywhere(w, &"planks") + _built_planks(w)
	var wheat := _everywhere(w, &"wheat")
	var bad := {"planks": 0.0, "wheat": 0.0, "claims": 0}
	_run(w, 1500.0, func() -> bool:
		bad["planks"] = maxf(bad["planks"], absf(_everywhere(w, &"planks") + _built_planks(w) - planks))
		bad["wheat"] = maxf(bad["wheat"], absf(_everywhere(w, &"wheat") - wheat))
		if not _reservations_match(w):
			bad["claims"] += 1
		return false)
	ok = _check("planks conserved over the run (worst %.4f)" % bad["planks"], bad["planks"] < 0.001) and ok
	ok = _check("wheat conserved over the run (worst %.4f)" % bad["wheat"], bad["wheat"] < 0.001) and ok
	ok = _check("reservations always match the legs (%d bad ticks)" % bad["claims"], bad["claims"] == 0) and ok
	var sites := w.buildings.values().filter(func(b: Building) -> bool: return b is ConstructionSite)
	ok = _check("the sites were built and the gate cleared (%d sites left, %.0f kg at the gate)" % [sites.size(), f.pile],
		sites.is_empty() and f.pile < 0.01) and ok
	var avg := float(w.planner.usec_total) / maxi(1, w.planner.ticks)
	print("  planner: %d ticks, average %.0f µs, max %d µs" % [w.planner.ticks, avg, w.planner.usec_max])
	ok = _check("the planner stays well under 1 ms on average", avg < 1000.0) and ok
	return ok


## A free 5x5 field spot near `near` (no trees around), gate reachable.
func _field_spot(w: World, near: Vector2i) -> Vector2i:
	for r in range(6, 60):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var a := near + Vector2i(dx, dy)
				if w.can_place(&"field", a, 0, Vector2i(5, 5)) and not _trees(w, Rect2i(a - Vector2i(2, 2), Vector2i(9, 9))) \
						and w.nav.find_path(near, Defs.access_for(Vector2i(5, 5), a, 0)).size() > 0:
					return a
	return near


## Planks built into finished buildings.
func _built_planks(w: World) -> float:
	var n := 0.0
	for b: Building in w.buildings.values():
		if not (b is ConstructionSite):
			n += b.materials.get(&"planks", 0.0)
	return n


## Carry legs (waiting or running), optionally only those into `dst`.
func _legs(w: World, dst: Store = null) -> Array[Task]:
	var out: Array[Task] = []
	for t in w.tasks.tasks:
		if t.kind == Task.Kind.CARRY and (dst == null or t.dst == dst):
			out.append(t)
	return out


## Every place's reservations are exactly what the tasks hold: out = claimed goods (and claimed
## wheelbarrows), in = goods on their way.
func _reservations_match(w: World) -> bool:
	var want_out := {}
	var want_in := {}
	for t in w.tasks.tasks:
		if t.fetch_from and t.fetch_reserved > 0.0:
			_add(want_out, t.fetch_from, t.fetch, t.fetch_reserved)
		if t.kind == Task.Kind.CARRY and t.dst and t.dst_reserved > 0.0:
			_add(want_in, t.dst, t.fetch, t.dst_reserved)
		if t.tool_from:
			_add(want_out, t.tool_from, &"wheelbarrow", 1.0)
	for s: Store in w.places():
		for pair in [[s.reserved_out, want_out.get(s, {})], [s.reserved_in, want_in.get(s, {})]]:
			var have: Dictionary = pair[0]
			var want: Dictionary = pair[1]
			for res in have.keys() + want.keys():
				if absf(have.get(res, 0.0) - want.get(res, 0.0)) > 0.001:
					print("    reservation mismatch at %s: %s %s vs %s" % [s.label(), res, have.get(res, 0.0), want.get(res, 0.0)])
					return false
	return true


func _add(d: Dictionary, s: Store, res: StringName, n: float) -> void:
	if not d.has(s):
		d[s] = {}
	d[s][res] = d[s].get(res, 0.0) + n


## Goods of `res` anywhere: in places, carried, loose, in the pickup.
func _everywhere(w: World, res: StringName) -> float:
	var n := w.loose.amount(res)
	for s: Store in w.places():
		n += s.amount(res)
	for wk in w.workers:
		if wk.carrying == res:
			n += wk.carry_amount
		if wk.equipment == res:
			n += 1.0
	for v in w.vehicles:
		n += v.cargo.get(res, 0.0)
	return n


func _carried(w: World, res: StringName) -> float:
	var n := 0.0
	for wk in w.workers:
		if wk.carrying == res:
			n += wk.carry_amount
	return n


func _run(w: World, limit: float, done: Callable) -> float:
	var t := 0.0
	while t < limit and not done.call():
		w.tick(0.1)
		t += 0.1
	return t


func _save_checks() -> bool:
	var ok := true
	var w := WorldGen.generate(256, 7)
	var a: Building = w.stores()[0]
	var b := _second_barn(w)
	a.store.put(&"wheat", 300.0)
	b.store.put(&"planks", 25.0)
	var wk: Worker = w.workers[0]
	wk.carrying = &"wood"
	wk.carry_amount = 3.0
	var before := w.totals()
	before[&"wood"] += 3.0                 # carried goods land in a store when loaded
	SaveGame.save(w, "logistics_test")
	var w2 := SaveGame.load_world("logistics_test")
	var b2: Building = w2.buildings.get(b.id)
	ok = _check("each barn keeps its own goods", b2 != null and b2.store.amount(&"planks") == 25.0
		and w2.buildings[a.id].store.amount(&"wheat") == 300.0) and ok
	ok = _check("totals survive a save, carried goods included", w2.totals() == before) and ok
	ok = _check("nothing is left loose after loading", w2.loose.contents.is_empty()) and ok
	SaveGame.delete("logistics_test")
	return ok


## Task 1: Nav.walk_cost — cached path lengths.
func _test_walk_cost() -> bool:
	var ok := true
	var nav := Nav.new(30)
	ok = _check("open ground: a straight line of 10 tiles costs 10.0",
		absf(nav.walk_cost(Vector2i(0, 0), Vector2i(10, 0)) - 10.0) < 0.01) and ok
	ok = _check("walk_cost from a cell to itself is 0.0", nav.walk_cost(Vector2i(4, 4), Vector2i(4, 4)) == 0.0) and ok

	# a wall across the direct path, with the only gap far from the straight line: forces a detour
	for y in range(0, 9):
		nav.set_solid(Vector2i(5, y), true)
	var detour := nav.walk_cost(Vector2i(0, 5), Vector2i(10, 5))
	ok = _check("a wall that forces a detour costs more than the straight distance", detour > 10.0) and ok
	ok = _check("a second call returns the same memoised cost", nav.walk_cost(Vector2i(0, 5), Vector2i(10, 5)) == detour) and ok

	nav.set_solid(Vector2i(5, 5), false)
	ok = _check("opening a gap keeps the memoised (now a bit high) cost",
		nav.walk_cost(Vector2i(0, 5), Vector2i(10, 5)) == detour) and ok
	ok = _check("a new pair sees the gap", nav.walk_cost(Vector2i(0, 4), Vector2i(10, 5)) < detour) and ok

	# an unreachable target, boxed in on all eight sides
	var boxed := Vector2i(20, 20)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx != 0 or dy != 0:
				nav.set_solid(boxed + Vector2i(dx, dy), true)
	ok = _check("an unreachable target costs INF", nav.walk_cost(Vector2i(0, 0), boxed) == INF) and ok
	return ok


func _check(what: String, cond: bool) -> bool:
	print("%s %s" % ["  ok " if cond else "FAIL", what])
	return cond


## Every place that holds goods is a Store: barns, field gate piles, mill buffers, site supplies and
## a moved building's pile; the old fields read and write those stores.
func _test_places() -> bool:
	var ok := true
	var w := World.new(64, 1)
	w.money = 100000
	w.unlocked[Tech.node_for_building(&"hand_mill")] = true
	var barn := w.add_building(&"storage_barn", Vector2i(4, 4), 0)
	var f := w.add_field(Vector2i(20, 4), 0, Vector2i(6, 6), &"wheat")
	var mill := w.add_building(&"hand_mill", Vector2i(4, 20), 0)
	var site := w.place_site(&"storage_barn", Vector2i(20, 20), 0)
	var places: Array[Store] = w.places()
	ok = _check("a barn is a storage place", places.has(barn.store) and barn.store.kind == Store.Kind.STORAGE
		and barn.store.cell == barn.access and barn.store.owner == barn) and ok
	ok = _check("a field's gate pile is a place at the gate", places.has(f.gate_store)
		and f.gate_store.kind == Store.Kind.GATE and f.gate_store.cell == f.access and f.gate_store.owner == f) and ok
	ok = _check("a mill has an input and an output place", places.has(mill.input_store) and places.has(mill.output_store)
		and mill.input_store.kind == Store.Kind.INPUT and mill.output_store.kind == Store.Kind.OUTPUT
		and mill.input_store.cell == mill.access and mill.output_store.cell == mill.access) and ok
	ok = _check("a site's supply is a place", site != null and places.has(site.supply)
		and site.supply.kind == Store.Kind.SITE and site.supply.cell == site.access and site.supply.owner == site) and ok
	ok = _check("a place is labelled by its owner", mill.input_store.label() == mill.display_name()) and ok
	ok = _check("stores() stays barns only", w.stores() == [barn]) and ok

	f.pile = 12.0
	ok = _check("the field pile is the crop at the gate", f.gate_store.amount(&"wheat") == 12.0) and ok
	f.gate_store.put(&"wheat", 3.0)
	ok = _check("and reads back from the store", f.pile == 15.0) and ok
	mill.input = 40.0
	mill.output = 7.5
	ok = _check("mill buffers are the recipe goods", mill.input_store.amount(&"wheat") == 40.0
		and mill.output_store.amount(&"flour") == 7.5) and ok
	mill.input_store.take(&"wheat", 10.0)
	ok = _check("and read back", mill.input == 30.0) and ok
	site.delivered[&"planks"] = 5.0
	ok = _check("delivered is the supply's contents", site.supply.amount(&"planks") == 5.0) and ok
	site.supply.put(&"planks", 1.0)
	ok = _check("and reads back", site.delivered.get(&"planks", 0.0) == 6.0) and ok
	site.delivered = {&"gravel": 2.0}
	ok = _check("and can be replaced", site.supply.contents == {&"gravel": 2.0}) and ok

	ok = _check("a gate change moves the gate place", w.set_field_gate(f, 2) and f.gate_store.cell == f.access) and ok

	var s := w.move_building(mill, Vector2i(40, 40), 0)
	ok = _check("a moved building's pile is a place", s != null and w.places().has(s.pile_store)
		and s.pile_store.kind == Store.Kind.MOVE_PILE and s.pile_store.owner == s) and ok
	if s:
		s.pile_cell = Vector2i(9, 9)
		s.pile[&"planks"] = 4.0
		ok = _check("the pile lies at pile_cell", s.pile_store.cell == Vector2i(9, 9) and s.pile_store.amount(&"planks") == 4.0) and ok
	var st := Store.new()
	st.reserve_in(&"wheat", 10.0)
	st.release_in(&"wheat", 4.0)
	ok = _check("reservations in are kept and released", st.reserved_in.get(&"wheat", 0.0) == 6.0) and ok
	st.release_in(&"wheat", 6.0)
	ok = _check("and dropped when all released", st.reserved_in.is_empty()) and ok
	return ok


# --- ground piles ------------------------------------------------------------------

## Where a ground pile may lie: not on a building, site or field, not on water or a door / gate;
## a drop near a pile of the same good joins it while it has room.
func _test_ground_piles() -> bool:
	var ok := true
	var w := World.new(64, 1)
	var barn := w.add_building(&"storage_barn", Vector2i(10, 10), 0)
	var f := w.add_field(Vector2i(30, 10), 0, Vector2i(6, 6), &"wheat")
	var added := [0]
	w.pile_added.connect(func(_s: Store) -> void: added[0] += 1)
	var p := w.drop_goods(&"wood", 1.0, Vector2i(40, 40), Task.Category.FELLING)
	ok = _check("a drop makes a ground pile where it falls", p != null and p.kind == Store.Kind.GROUND
		and p.cell == Vector2i(40, 40) and p.amount(&"wood") == 1.0 and p.category == Task.Category.FELLING
		and w.ground_piles == [p] and w.places().has(p) and added[0] == 1) and ok
	var q := w.drop_goods(&"wood", 2.0, Vector2i(41, 42), Task.Category.FELLING)
	ok = _check("a drop within 2 tiles joins the pile", q == p and p.amount(&"wood") == 3.0 and w.ground_piles.size() == 1) and ok
	var r := w.drop_goods(&"wood", 2.0, Vector2i(40, 41), Task.Category.FELLING)
	ok = _check("a full pile (%d kg) starts a new one" % Defs.GROUND_PILE_CAPACITY, r != p and r != null
		and w.ground_piles.size() == 2 and p.weight() <= Defs.GROUND_PILE_CAPACITY + 0.001) and ok
	var o := w.drop_goods(&"wheat", 10.0, Vector2i(40, 40), Task.Category.TRANSPORT)
	ok = _check("another good makes its own pile on a free tile", o != null and o != p and o != r
		and o.cell != p.cell and o.cell != r.cell) and ok
	var in_barn := w.drop_goods(&"wheat", 5.0, barn.anchor + Vector2i(1, 1), Task.Category.TRANSPORT)
	ok = _check("never on a building", in_barn != null and w.building_at(in_barn.cell) == null) and ok
	var in_field := w.drop_goods(&"wheat", 5.0, f.anchor + Vector2i(1, 1), Task.Category.TRANSPORT)
	ok = _check("never inside a field", in_field != null and w.building_at(in_field.cell) == null) and ok
	var at_door := w.drop_goods(&"potato", 5.0, barn.access, Task.Category.TRANSPORT)
	ok = _check("never on a door", at_door != null and at_door.cell != barn.access) and ok
	var at_gate := w.drop_goods(&"corn", 5.0, f.access, Task.Category.TRANSPORT)
	ok = _check("never on a field gate", at_gate != null and at_gate.cell != f.access and w.building_at(at_gate.cell) == null) and ok
	for y in range(48, 52):
		for x in range(48, 52):
			w.set_water(Vector2i(x, y), Defs.Water.POND)
	var wet := w.drop_goods(&"beet", 5.0, Vector2i(49, 49), Task.Category.TRANSPORT)
	ok = _check("never on water", wet != null and not w.is_water(wet.cell)) and ok
	# a building placed over a pile moves the pile out of its way
	var spot := Vector2i(20, 30)
	var under := w.drop_goods(&"wood", 1.0, spot, Task.Category.FELLING)
	var removed := [false]
	w.pile_removed.connect(func(s: Store) -> void: removed[0] = removed[0] or s == under)
	w.add_building(&"storage_barn", spot - Vector2i(1, 1), 0)
	var moved_to: Array = w.ground_piles.filter(func(s: Store) -> bool: return s.amount(&"wood") == 1.0 and s.cell.distance_to(spot) < 6.0)
	ok = _check("a building over a pile moves the pile beside it", removed[0] and not w.ground_piles.has(under)
		and moved_to.size() == 1 and w.building_at((moved_to[0] as Store).cell) == null) and ok
	return ok


## A marked tree is felled: its log lies on the ground until the planner has it carried to the
## barn, then the pile is gone. Nothing is lost on the way.
func _test_felled_pile() -> bool:
	var ok := true
	var w := World.new(64, 1)
	var barn := w.add_building(&"storage_barn", Vector2i(10, 10), 0)
	var tree := Vector2i(30, 24)
	w.set_tree(tree, Defs.TreeKind.DECIDUOUS, Defs.TreeStage.FULL)
	w.add_worker(barn.access, Worker.Look.MALE)
	ok = _check("a tree is marked", w.mark_trees(Rect2i(tree, Vector2i.ONE)) == 1) and ok
	var removed := [0]
	w.pile_removed.connect(func(_s: Store) -> void: removed[0] += 1)
	var t := _run(w, 300.0, func() -> bool: return not w.ground_piles.is_empty())
	var pile: Store = w.ground_piles[0] if not w.ground_piles.is_empty() else null
	ok = _check("the felled tree leaves a pile with its logs (%d s)" % t, pile != null and not w.has_tree(tree)
		and pile.amount(&"wood") == Defs.WOOD_PER_TREE and pile.category == Task.Category.FELLING
		and pile.cell.distance_to(tree) <= 2.0 and _carried(w, &"wood") == 0.0) and ok
	var legs := [false]
	var bad := [false]
	t = _run(w, 300.0, func() -> bool:
		for leg in _legs(w):
			if leg.src == pile:
				legs[0] = legs[0] or leg.category == Task.Category.FELLING
		if absf(_everywhere(w, &"wood") - Defs.WOOD_PER_TREE) > 0.001 or not _reservations_match(w):
			bad[0] = true
		return w.ground_piles.is_empty() and _carried(w, &"wood") == 0.0)
	ok = _check("the logs end in the barn and the pile is gone (%d s)" % t, w.ground_piles.is_empty()
		and barn.store.amount(&"wood") == Defs.WOOD_PER_TREE and removed[0] == 1) and ok
	ok = _check("the leg from the pile is a Felling task", legs[0]) and ok
	ok = _check("logs conserved and claims matched all the way", not bad[0]) and ok
	return ok


## With a sawmill wanting wood the felled logs go straight into it, not to the barn.
func _test_felled_to_sawmill() -> bool:
	var ok := true
	var w := World.new(64, 1)
	var barn := w.add_building(&"storage_barn", Vector2i(10, 10), 0)
	var mill := w.add_building(&"sawmill", Vector2i(24, 30), 0)
	w.auto_sell[&"wood"]["on"] = false
	for c: Vector2i in [Vector2i(30, 20), Vector2i(32, 20)]:
		w.set_tree(c, Defs.TreeKind.CONIFER, Defs.TreeStage.FULL)
	w.mark_trees(Rect2i(Vector2i(30, 20), Vector2i(3, 1)))
	for i in 2:
		w.add_worker(barn.access, Worker.Look.FEMALE)
	var in_barn := [false]
	var t := _run(w, 400.0, func() -> bool:
		in_barn[0] = in_barn[0] or barn.store.amount(&"wood") > 0.0
		return w.marked.is_empty() and w.ground_piles.is_empty() and _carried(w, &"wood") == 0.0)
	var y := float(mill.recipe()["yield"])
	var logs: float = mill.input + mill.output / y + barn.store.amount(&"planks") / y + _carried(w, &"planks") / y
	ok = _check("both logs went into the sawmill (%d s, %.1f logs' worth)" % [t, logs],
		w.ground_piles.is_empty() and absf(logs - 2.0) < 0.001) and ok
	ok = _check("and none went to the barn first", not in_barn[0]) and ok
	return ok


## A worker whose leg breaks while carrying (its destination is demolished) drops the goods as a
## ground pile with the leg's category; the planner has them carried on.
func _test_abort_drops() -> bool:
	var ok := true
	var w := WorldGen.generate(256, 7)
	w.money = 100000
	for res in w.auto_sell:
		w.auto_sell[res]["on"] = false
	var barn: Building = w.stores()[0]
	w.set_stock(&"planks", 200.0)
	var site := w.place_site(&"storage_barn", _spot(w, &"storage_barn", barn.access), 2)
	var before := _everywhere(w, &"planks")
	_run(w, 600.0, func() -> bool:
		for wk in w.workers:
			if wk.task and wk.task.site == site and wk.carrying == &"planks" and wk.phase == Worker.Phase.TO_TASK:
				return true
		return false)
	var carried := _carried(w, &"planks")
	ok = _check("planks on their way (%d)" % carried, carried > 0.0) and ok
	w.demolish(site)
	var on_ground := 0.0
	for s in w.ground_piles:
		on_ground += s.amount(&"planks")
	ok = _check("what was carried lies on the ground (%d planks)" % on_ground, absf(on_ground - carried) < 0.001
		and _carried(w, &"planks") == 0.0
		and w.ground_piles.all(func(s: Store) -> bool: return s.category == Task.Category.CONSTRUCTION)) and ok
	ok = _check("nothing lost on the drop", absf(_everywhere(w, &"planks") - before) < 0.001) and ok
	_run(w, 300.0, func() -> bool: return w.ground_piles.is_empty() and _carried(w, &"planks") == 0.0)
	ok = _check("and is carried to the barn", w.ground_piles.is_empty() and absf(w.total(&"planks") - before) < 0.001) and ok
	return ok


## A ground pile survives a save round trip with its cell, category and goods.
func _test_pile_save() -> bool:
	var ok := true
	var w := World.new(64, 1)
	w.add_building(&"storage_barn", Vector2i(10, 10), 0)
	var p := w.drop_goods(&"wood", 3.0, Vector2i(40, 40), Task.Category.FELLING)
	SaveGame.save(w, "logistics_test")
	var w2 := SaveGame.load_world("logistics_test")
	SaveGame.delete("logistics_test")
	var q: Store = w2.ground_piles[0] if w2 and w2.ground_piles.size() == 1 else null
	ok = _check("a ground pile survives a save", q != null and q.cell == p.cell and q.category == Task.Category.FELLING
		and q.amount(&"wood") == 3.0 and q.kind == Store.Kind.GROUND and w2.places().has(q)) and ok
	return ok


# --- fix round ---------------------------------------------------------------------

## A waiting leg whose source is walled off after it was planned lets go of its claims, and the
## need is served from a barn that can be reached.
func _test_stranded_leg() -> bool:
	var ok := true
	var w := World.new(64, 1)
	w.money = 100000
	w.unlocked[Tech.node_for_building(&"hand_mill")] = true
	var far := w.add_building(&"storage_barn", Vector2i(4, 44), 0)
	var near := w.add_building(&"storage_barn", Vector2i(30, 24), 0)
	far.store.put(&"planks", 30.0)
	near.store.put(&"planks", 30.0)
	var site := w.place_site(&"hand_mill", Vector2i(30, 34), 0)
	w.planner.tick()
	var legs := _legs(w, site.supply)
	ok = _check("the site's planks are planned from the nearer barn", legs.size() > 0
		and legs.all(func(t: Task) -> bool: return t.fetch_from == near.store)) and ok
	# a ring of trees round the nearer barn and its door
	var ring := near.rect().merge(Rect2i(near.access, Vector2i.ONE)).grow(1)
	for y in range(ring.position.y, ring.end.y):
		for x in range(ring.position.x, ring.end.x):
			var c := Vector2i(x, y)
			if x == ring.position.x or y == ring.position.y or x == ring.end.x - 1 or y == ring.end.y - 1:
				w.set_tree(c, Defs.TreeKind.CONIFER, Defs.TreeStage.FULL)
	w.add_worker(far.access, Worker.Look.MALE)
	var t := _run(w, 400.0, func() -> bool: return site.supply.amount(&"planks") >= 29.999 or site.stage != ConstructionSite.Stage.DELIVERY)
	ok = _check("the walled-off barn's legs are dropped and the site gets its planks from the other (%d s)" % t,
		site.stage != ConstructionSite.Stage.DELIVERY or site.supply.amount(&"planks") >= 29.999) and ok
	ok = _check("nothing stays claimed in the walled-off barn", near.store.reserved_out.is_empty()
		and near.store.amount(&"planks") == 30.0) and ok
	return ok


## The wheelbarrow only pays off for loads that can ride along: legs to the same place, and what is
## still free for it. Two loads going to two places are two hand loads.
func _test_wheelbarrow_backlog() -> bool:
	var ok := true
	var w := World.new(64, 1)
	var barn := w.add_building(&"storage_barn", Vector2i(4, 4), 0)
	var f := w.add_field(Vector2i(30, 30), 0, Vector2i(6, 6), &"wheat")
	var mill := w.add_building(&"hand_mill", Vector2i(20, 20), 0)
	w.set_category_on(Task.Category.PLANTING, false)
	barn.store.put(&"wheelbarrow", 1.0)
	mill.input = float(mill.recipe()["in_cap"]) - Defs.CARRY_CAPACITY
	f.pile = 2.0 * Defs.CARRY_CAPACITY
	w.planner.tick()
	var from_gate := _legs(w).filter(func(t: Task) -> bool: return t.fetch_from == f.gate_store)
	ok = _check("one load to the mill, one to the barn", from_gate.size() == 2
		and from_gate.any(func(t: Task) -> bool: return t.dst == mill.input_store)
		and from_gate.any(func(t: Task) -> bool: return t.dst == barn.store)) and ok
	var wk := w.add_worker(barn.access, Worker.Look.MALE)
	var t := w.tasks.pick(w, wk)
	ok = _check("no wheelbarrow for loads that can't be merged", t != null and t.kind == Task.Kind.CARRY
		and t.tool_from == null and barn.store.reserved_out.is_empty()) and ok
	return ok


## The walk cost memo survives changes that change nothing.
func _test_nav_version() -> bool:
	var ok := true
	var nav := Nav.new(30)
	var v := nav.version
	nav.set_solid(Vector2i(3, 3), false)
	nav.set_cost(Vector2i(3, 3), 1.0)
	ok = _check("setting a tile to what it is keeps the memo", nav.version == v) and ok
	nav.set_solid(Vector2i(3, 3), true)
	nav.set_cost(Vector2i(4, 4), 2.0)
	ok = _check("a real change invalidates it", nav.version == v + 2) and ok
	var w := World.new(64, 1)
	w.nav.walk_cost(Vector2i(1, 1), Vector2i(20, 20))
	var wv := w.nav.version
	w._refresh_nav(Vector2i(10, 10))
	ok = _check("refreshing an unchanged tile keeps the memo", w.nav.version == wv
		and w.nav.has_cost(Vector2i(1, 1), Vector2i(20, 20))) and ok
	return ok


## Planks on their way from a sawmill to the barn, not picked up yet, still count as there for a
## new site (no "order them" alert), and the site takes them over.
func _test_take_over_clear() -> bool:
	var ok := true
	var w := World.new(64, 1)
	w.money = 100000
	w.unlocked[Tech.node_for_building(&"hand_mill")] = true
	var barn := w.add_building(&"storage_barn", Vector2i(4, 4), 0)
	var saw := w.add_building(&"sawmill", Vector2i(30, 30), 0)
	saw.output = 9.0
	w.planner.tick()
	var clears := _legs(w, barn.store)
	ok = _check("the sawmill's planks are on their way to the barn (%d legs)" % clears.size(), clears.size() > 0
		and absf(barn.store.reserved_in.get(&"planks", 0.0) - 9.0) < 0.001) and ok
	ok = _check("they still count as available (%.0f)" % w.available(&"planks"), absf(w.available(&"planks") - 9.0) < 0.001) and ok
	var site := w.place_site(&"hand_mill", Vector2i(36, 30), 0)
	var short: float = w.seed_shortage().get(&"planks", 0.0)
	ok = _check("the shortage counts them (%.0f short)" % short, absf(short - 21.0) < 0.001) and ok
	w.planner.tick()
	var to_site := 0.0
	for t in _legs(w, site.supply):
		if t.fetch_from == saw.output_store:
			to_site += t.fetch_amount
	ok = _check("the site takes the planks over (%.0f)" % to_site, absf(to_site - 9.0) < 0.001
		and _legs(w, barn.store).is_empty() and barn.store.reserved_in.is_empty()) and ok
	ok = _check("claims moved with them", _reservations_match(w)) and ok
	return ok


## Logs on a ground pile go straight to a sawmill that wants wood when that saves walking, even with
## wood in a barn next to the sawmill.
func _test_pile_to_sawmill() -> bool:
	var ok := true
	var w := World.new(64, 1)
	var barn := w.add_building(&"storage_barn", Vector2i(30, 20), 0)
	var saw := w.add_building(&"sawmill", Vector2i(30, 30), 0)
	barn.store.put(&"wood", 50.0)
	var pile := w.drop_goods(&"wood", 2.0, Vector2i(52, 32), Task.Category.FELLING)
	var to_mill := w.nav.walk_cost(pile.cell, saw.access)
	var from_barn := w.nav.walk_cost(barn.access, saw.access)
	ok = _check("the barn is nearer the sawmill than the pile (%.0f < %.0f)" % [from_barn, to_mill], from_barn < to_mill) and ok
	w.planner.tick()
	var from_pile := 0.0
	for t in _legs(w, saw.input_store):
		if t.fetch_from == pile:
			from_pile += t.fetch_amount
	ok = _check("the sawmill is fed from the pile (%.0f logs)" % from_pile, absf(from_pile - 2.0) < 0.001
		and _legs(w, barn.store).is_empty()) and ok
	return ok


## A worker takes the carry leg whose goods are nearest, not the one whose destination is nearest.
func _test_lazy_pick() -> bool:
	var ok := true
	var w := World.new(64, 1)
	var a := w.add_building(&"storage_barn", Vector2i(4, 4), 0)
	var b := w.add_building(&"storage_barn", Vector2i(40, 46), 0)
	var p1 := w.drop_goods(&"wood", 1.0, Vector2i(41, 40), Task.Category.FELLING)
	var p2 := w.drop_goods(&"wood", 1.0, Vector2i(4, 30), Task.Category.FELLING)
	w.planner._leg(p1, a.store, &"wood", 1.0, a.access)
	w.planner._leg(p2, b.store, &"wood", 1.0, b.access)
	var wk := w.add_worker(Vector2i(40, 40), Worker.Look.FEMALE)
	var t := w.tasks.pick(w, wk)
	ok = _check("the worker takes the leg from the pile beside it", t != null and t.src == p1) and ok
	return ok


## Saving while the pickup is loaded neither duplicates nor loses the load being carried.
func _test_save_mid_transfer() -> bool:
	var ok := true
	var w := WorldGen.generate(256, 7)
	var barn: Building = w.stores()[0]
	w.set_stock(&"wheat", 400.0)
	w.auto_sell[&"wheat"] = {"on": true, "keep": 0.0}
	w.request_trip()
	var t := _run(w, 300.0, func() -> bool:
		for wk in w.workers:
			if wk.task and (wk.task.kind == Task.Kind.TRIP or wk.task.kind == Task.Kind.HELP) and wk.carrying == &"wheat":
				return true
		return false)
	var before := _everywhere(w, &"wheat") - _shuttled(w, &"wheat")
	ok = _check("a load of wheat is on its way into the pickup (%d s, %.0f kg)" % [t, _shuttled(w, &"wheat")],
		_shuttled(w, &"wheat") > 0.0) and ok
	SaveGame.save(w, "logistics_test")
	var w2 := SaveGame.load_world("logistics_test")
	SaveGame.delete("logistics_test")
	var after := _everywhere(w2, &"wheat") if w2 else -1.0
	ok = _check("the wheat survives the save exactly (%.0f -> %.0f kg)" % [before, after], absf(after - before) < 0.001) and ok
	return ok


## Goods held by workers carrying for the pickup (still counted at their source).
func _shuttled(w: World, res: StringName) -> float:
	var n := 0.0
	for wk in w.workers:
		if wk.task and (wk.task.kind == Task.Kind.TRIP or wk.task.kind == Task.Kind.HELP) and wk.carrying == res:
			n += wk.carry_amount
	return n


## On a 512² map with many ground piles far apart the planner, after a change of the grid, stays
## within Defs.PLANNER_BUDGET_USEC per run (plus the one lookup that crosses it) and gets through
## the rest, the stranded check included, in later runs.
func _test_planner_budget() -> bool:
	var ok := true
	var w := World.new(512, 1)
	w.money = 1000000
	w.unlocked[Tech.node_for_building(&"hand_mill")] = true
	var barn := w.add_building(&"storage_barn", Vector2i(250, 250), 0)
	barn.store.put(&"planks", 500.0)
	barn.store.put(&"wheat", 500.0)
	for i in 3:
		w.place_site(&"hand_mill", Vector2i(230 + 12 * i, 270), 0)
		w.add_building(&"hand_mill", Vector2i(230 + 12 * i, 230), 0)
		var f := w.add_field(Vector2i(200 + 30 * i, 300), 0, Vector2i(6, 6), &"wheat")
		f.pile = 100.0
	w.set_category_on(Task.Category.PLANTING, false)
	# forest belts with a gap every 64 tiles: detours, as round a real farm
	for row in range(40, 500, 40):
		for x in 512:
			if (x + row) % 64 > 6 and absi(row - 250) > 12:
				w.set_tree(Vector2i(x, row), Defs.TreeKind.CONIFER, Defs.TreeStage.FULL)
	var piles := 0
	for y in range(20, 500, 48):
		for x in range(20, 500, 48):
			if w.drop_goods(&"wood", 1.0, Vector2i(x, y), Task.Category.FELLING):
				piles += 1
	var stats := _run_until_fed(w)
	var legs := _legs(w).size()
	ok = _check("everything is planned within the budget (%d piles, %d legs, %d runs, %d ms, worst run %d µs)"
		% [piles, legs, stats[0], stats[1] / 1000, stats[2]],
		_legs(w).filter(func(t: Task) -> bool: return t.fetch_from.kind == Store.Kind.GROUND).size() == piles) and ok
	# closing a tile flushes the memo: each run stays within the budget plus the lookup crossing it
	w.nav.set_solid(Vector2i(1, 1), true)
	w.planner.tick()
	var p := w.planner
	print("  planner after a flush on 512²: %d path searches, %d µs (budget %d, longest search %d µs)"
		% [p.paths, p.usec_last, Defs.PLANNER_BUDGET_USEC, p.lookup_usec_max])
	ok = _check("a run after a flush stays within the budget plus one search",
		p.usec_last <= Defs.PLANNER_BUDGET_USEC + p.lookup_usec_max + 1000) and ok
	stats = _run_until_fed(w)
	print("  re-planned after the flush in %d more runs, %d ms, worst run %d µs" % [stats[0], stats[1] / 1000, stats[2]])
	ok = _check("later runs get through the rest, the stranded check too", not p.starved) and ok
	# felling a tree only opens a tile: the memo stays and the next run searches nothing
	w.remove_tree(Vector2i(100, 40))
	p.tick()
	ok = _check("a run after felling a tree needs no search (%d, %d µs)" % [p.paths, p.usec_last], p.paths == 0) and ok
	return ok


## Runs the planner until a run is not starved: [runs, total µs, worst run µs].
func _run_until_fed(w: World) -> Array:
	var runs := 0
	var total := 0
	var worst := 0
	while runs < 1000:
		w.planner.tick()
		runs += 1
		total += w.planner.usec_last
		worst = maxi(worst, w.planner.usec_last)
		if not w.planner.starved:
			break
	return [runs, total, worst]


## Opening a tile (a felled tree) keeps finite memoised walk costs and drops only the INF ones;
## closing a tile flushes the memo.
func _test_open_keeps_memo() -> bool:
	var ok := true
	var w := World.new(64, 1)
	var a := Vector2i(2, 2)
	var b := Vector2i(40, 30)
	var boxed := Vector2i(20, 50)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx != 0 or dy != 0:
				w.set_tree(boxed + Vector2i(dx, dy), Defs.TreeKind.CONIFER, Defs.TreeStage.FULL)
	w.set_tree(Vector2i(50, 10), Defs.TreeKind.CONIFER, Defs.TreeStage.FULL)
	var c := w.nav.walk_cost(a, b)
	ok = _check("a boxed-in cell is unreachable", w.nav.walk_cost(a, boxed) == INF) and ok
	w.remove_tree(Vector2i(50, 10))
	ok = _check("felling a tree keeps a finite cost", w.nav.has_cost(a, b) and w.nav.walk_cost(a, b) == c) and ok
	ok = _check("felling a tree drops a memoised INF", not w.nav.has_cost(a, boxed)) and ok
	w.remove_tree(boxed + Vector2i(1, 0))
	ok = _check("felling the tree in the way makes it reachable", w.nav.walk_cost(a, boxed) < INF) and ok
	w.set_tree(Vector2i(50, 10), Defs.TreeKind.CONIFER, Defs.TreeStage.FULL)
	ok = _check("a new tree (a tile made solid) flushes the memo", not w.nav.has_cost(a, b)
		and not w.nav.has_cost(a, boxed)) and ok
	w.nav.walk_cost(a, b)
	w.nav.set_cost(Vector2i(50, 11), 3.0)
	ok = _check("a cost going up flushes the memo", not w.nav.has_cost(a, b)) and ok
	w.nav.walk_cost(a, b)
	w.nav.set_cost(Vector2i(50, 11), 1.0)
	ok = _check("a cost going down keeps it", w.nav.has_cost(a, b)) and ok
	return ok
