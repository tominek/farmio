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
	ok = _test_sellable_keeps() and ok
	ok = _test_field_demolish_pile() and ok
	ok = _test_pile_origin() and ok
	ok = _test_short_walk_direct() and ok
	ok = _test_far_pile_chain() and ok
	ok = _test_chain_break() and ok
	ok = _test_carry_now() and ok
	ok = _test_pickup_brings_pile() and ok
	ok = _test_multi_stop() and ok
	ok = _test_field_pickup_trip() and ok
	ok = _test_stop_demolished() and ok
	ok = _test_save_mid_trip() and ok
	ok = _test_road_cut_pile() and ok
	ok = _test_cut_off_ride() and ok
	ok = _test_stale_handoff() and ok
	ok = _test_available_chain() and ok
	ok = _test_urgent_kept() and ok
	ok = _test_spot_nearest() and ok
	ok = _test_dealer_stop() and ok
	ok = _test_order_collected() and ok
	ok = _test_hire_stop() and ok
	ok = _test_one_trip_mixed() and ok
	ok = _test_trip_category() and ok
	ok = _test_route_per_load() and ok
	ok = _test_helper_reach() and ok
	ok = _test_trip_cleanup() and ok
	ok = _test_partial_load() and ok
	ok = _test_pickup_off() and ok
	ok = _test_road_pile_names() and ok
	ok = _test_carry_blocker_cheap() and ok
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
		# a leg (walking or riding) and the later legs of its chain, not opened yet, hold room on the way
		var l: Task = t if t.kind == Task.Kind.CARRY or t.kind == Task.Kind.RIDE else null
		while l:
			if l.dst and l.dst_reserved > 0.0:
				_add(want_in, l.dst, l.fetch, l.dst_reserved)
			l = l.next
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


## Opening a tile (a felled tree) keeps the memoised walk costs; an INF one is looked up again only
## Defs.UNREACHABLE_RETRY seconds after it was found and only if a tile opened since. Closing a
## tile flushes the memo.
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
	ok = _check("felling a tree keeps a memoised INF", w.nav.has_cost(a, boxed) and w.nav.walk_cost(a, boxed) == INF) and ok
	w.nav.clock += Defs.UNREACHABLE_RETRY
	ok = _check("an INF is looked up again after a while when a tile opened since", not w.nav.has_cost(a, boxed)) and ok
	ok = _check("... and is still INF while the box is closed", w.nav.walk_cost(a, boxed) == INF) and ok
	w.nav.clock += Defs.UNREACHABLE_RETRY
	ok = _check("with no opening since, an INF stays memoised", w.nav.has_cost(a, boxed)) and ok
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
	w.tick(1.5)
	ok = _check("the game time drives the memo clock", w.nav.clock == w.time) and ok
	return ok


## Auto-sell keeps the "keep" amount: goods legs have promised to a mill are not sellable.
func _test_sellable_keeps() -> bool:
	var ok := true
	var w := World.new(64, 1)
	var barn := w.add_building(&"storage_barn", Vector2i(10, 10), 0)
	var mill := w.add_building(&"hand_mill", Vector2i(20, 10), 0)
	barn.store.put(&"wheat", 400.0)
	w.auto_sell[&"wheat"] = {"on": true, "keep": 100.0}
	w.planner.tick()
	var promised: float = barn.store.reserved_out.get(&"wheat", 0.0)
	ok = _check("the mill's wheat is promised (%.0f kg)" % promised, promised >= float(mill.recipe()["in_cap"]) - 0.001) and ok
	ok = _check("only the unpromised wheat above the keep is sellable (%.0f kg)" % w.sellable(&"wheat"),
		absf(w.sellable(&"wheat") - (400.0 - promised - 100.0)) < 0.001) and ok
	return ok


## Demolishing a field leaves the harvest at its gate as a ground pile: nothing is lost.
func _test_field_demolish_pile() -> bool:
	var ok := true
	var w := World.new(64, 1)
	w.add_building(&"storage_barn", Vector2i(4, 4), 0)
	var f := w.add_field(Vector2i(20, 20), 0, Vector2i(6, 6), &"wheat")
	f.pile = 120.0
	var gate := f.access
	ok = _check("the field is demolished", w.demolish(f)) and ok
	var on_ground := 0.0
	for s: Store in w.ground_piles:
		on_ground += s.amount(&"wheat")
	ok = _check("its gate harvest lies as a ground pile near the gate (%.0f kg)" % on_ground, absf(on_ground - 120.0) < 0.001
		and w.ground_piles.all(func(s: Store) -> bool: return Vector2(s.cell).distance_to(gate) <= Defs.GROUND_PILE_SEARCH * 1.5)) and ok
	ok = _check("and the barn did not get it", w.total(&"wheat") == 0.0) and ok
	return ok


## A ground pile knows why it lies there (the info panel's "Why it's here"): felled for a Cut trees
## order, cleared for a site, or dropped with a reason; drops of another origin don't join it, and
## the origin survives a save.
func _test_pile_origin() -> bool:
	var ok := true
	var w := World.new(64, 1)
	w.money = 100000
	var barn := w.add_building(&"storage_barn", Vector2i(10, 10), 0)
	var wk := w.add_worker(barn.access, Worker.Look.MALE)
	wk.name = "Bo"
	var tree := Vector2i(30, 24)
	w.set_tree(tree, Defs.TreeKind.DECIDUOUS, Defs.TreeStage.FULL)
	w.mark_trees(Rect2i(tree, Vector2i.ONE))
	_run(w, 300.0, func() -> bool: return not w.ground_piles.is_empty())
	var felled: Store = w.ground_piles[0] if not w.ground_piles.is_empty() else null
	ok = _check("a marked tree's logs lie as felled", felled != null and felled.origin == Store.Origin.FELLED
		and felled.reason == "" and felled.site_name == "") and ok
	if felled:
		var other := w.drop_goods(&"wood", 1.0, felled.cell, felled.category, Store.Origin.DROPPED, "test")
		ok = _check("a drop of another origin does not join a felled pile", other != null and other != felled
			and other.origin == Store.Origin.DROPPED and other.reason == "test") and ok
	# a site over a tree: its log is cleared for the site
	var w2 := World.new(64, 1)
	w2.money = 100000
	var barn2 := w2.add_building(&"storage_barn", Vector2i(10, 10), 0)
	w2.add_worker(barn2.access, Worker.Look.FEMALE)
	var at := Vector2i(30, 30)
	w2.set_tree(at, Defs.TreeKind.CONIFER, Defs.TreeStage.FULL)
	var site := w2.place_site(&"garage", at, 0)
	_run(w2, 300.0, func() -> bool: return not w2.ground_piles.is_empty())
	var cleared: Store = w2.ground_piles[0] if not w2.ground_piles.is_empty() else null
	ok = _check("a site's tree lies as cleared for it", site != null and cleared != null
		and cleared.origin == Store.Origin.CLEARED and cleared.site_name == site.base_name()) and ok
	# a worker carrying to a site that is cancelled puts the goods down and says why
	var w3 := WorldGen.generate(256, 7)
	w3.money = 100000
	for res in w3.auto_sell:
		w3.auto_sell[res]["on"] = false
	var home: Building = w3.stores()[0]
	w3.set_stock(&"planks", 200.0)
	var s3 := w3.place_site(&"storage_barn", _spot(w3, &"storage_barn", home.access), 2)
	var carrier: Array = [null]
	_run(w3, 600.0, func() -> bool:
		for x in w3.workers:
			if x.task and x.task.site == s3 and x.carrying == &"planks" and x.phase == Worker.Phase.TO_TASK:
				carrier[0] = x
				return true
		return false)
	var name := s3.base_name()
	w3.demolish(s3)
	var dropped: Store = null
	for p in w3.ground_piles:
		if p.amount(&"planks") > 0.0:
			dropped = p
	var who: String = (carrier[0] as Worker).who() if carrier[0] else "?"
	ok = _check("a cancelled site's planks are dropped with the reason (%s)" % (dropped.reason if dropped else "none"),
		dropped != null and dropped.origin == Store.Origin.DROPPED and dropped.site_name == name
		and dropped.reason.begins_with("the %s site was cancelled. %s had it" % [name, who])) and ok
	# a demolished field's gate harvest
	var w4 := World.new(64, 1)
	w4.add_building(&"storage_barn", Vector2i(4, 4), 0)
	var f := w4.add_field(Vector2i(20, 20), 0, Vector2i(6, 6), &"wheat")
	f.pile = 50.0
	var fname := f.display_name()
	w4.demolish(f)
	ok = _check("a demolished field's harvest says so", w4.ground_piles.size() == 1
		and w4.ground_piles[0].origin == Store.Origin.DROPPED and w4.ground_piles[0].reason.begins_with("%s was demolished" % fname)) and ok
	# the origin survives a save
	var p2 := w4.drop_goods(&"wood", 2.0, Vector2i(40, 40), Task.Category.CONSTRUCTION, Store.Origin.CLEARED, "", "Sawmill 2")
	var d := w4.drop_goods(&"planks", 3.0, Vector2i(50, 50), Task.Category.TRANSPORT, Store.Origin.DROPPED, "the Garage site was cancelled. Bo had it and put it down here.", "Garage")
	SaveGame.save(w4, "logistics_test")
	var l := SaveGame.load_world("logistics_test")
	SaveGame.delete("logistics_test")
	var by_cell := {}
	if l:
		for s in l.ground_piles:
			by_cell[s.cell] = s
	var lp: Store = by_cell.get(p2.cell)
	var ld: Store = by_cell.get(d.cell)
	ok = _check("the origin of a pile survives a save", lp != null and ld != null
		and lp.origin == Store.Origin.CLEARED and lp.site_name == "Sawmill 2" and lp.reason == ""
		and ld.origin == Store.Origin.DROPPED and ld.site_name == "Garage" and ld.reason == d.reason) and ok
	return ok


# --- step 3: routes by cost, chains of legs, road piles -----------------------------

const ROAD_Y := 20
const ROAD_X0 := 10


## A blank 256² map with a dirt road of `blocks` blocks running east from the farm, the barn at its
## west end and, with `pickup`, the garage with its pickup (laid out as WorldGen does).
func _road_world(blocks: int, pickup := true) -> World:
	var w := World.new(256, 1)
	w.money = 100000
	for res in w.auto_sell:
		w.auto_sell[res]["on"] = false
	w.add_building(&"storage_barn", Vector2i(ROAD_X0 + 2, ROAD_Y - 3), 2)
	for i in blocks:
		w.add_road_block(Vector2i(ROAD_X0 + i * Defs.ROAD_BLOCK, ROAD_Y), &"dirt")
	if pickup:
		w.add_vehicle(w.add_building(&"garage", Vector2i(ROAD_X0 + 8, ROAD_Y - 4), 2))
	return w


## Every leg of every chain: queued legs (walking and riding) and the later legs they hold.
func _chain_legs(w: World) -> Array[Task]:
	var out: Array[Task] = []
	for t in w.tasks.tasks:
		var l: Task = t if t.kind == Task.Kind.CARRY or t.kind == Task.Kind.RIDE else null
		while l:
			out.append(l)
			l = l.next
	return out


func _road_piles(w: World) -> Array[Store]:
	var out: Array[Store] = []
	for s in w.ground_piles:
		if s.origin == Store.Origin.ROAD:
			out.append(s)
	return out


## A far tree 6 tiles off the road, marked, and a worker at the barn. Returns the tree.
func _far_tree(w: World) -> Vector2i:
	var tree := Vector2i(ROAD_X0 + 170, ROAD_Y + 8)
	w.set_tree(tree, Defs.TreeKind.DECIDUOUS, Defs.TreeStage.FULL)
	w.add_worker(w.stores()[0].access, Worker.Look.MALE)
	w.mark_trees(Rect2i(tree, Vector2i.ONE))
	return tree


## Runs until the felled log's pile has its legs planned; returns that pile (null if never).
func _until_felled_and_planned(w: World, tree: Vector2i) -> Store:
	var felled: Array = [null]
	_run(w, 600.0, func() -> bool:
		for s in w.ground_piles:
			if s.origin == Store.Origin.FELLED:
				felled[0] = s
		if felled[0] == null:
			return false
		for t in w.tasks.tasks:
			if t.fetch_from == felled[0] or (t.worker and t.worker.carrying == &"wood"):
				return true
		return false)
	if felled[0] == null:
		print("    the tree at %s was not felled" % tree)
	return felled[0]


## A ground pile a short walk from the barn goes straight there by hand, even with the pickup and
## a road beside it: no road pile, no ride.
func _test_short_walk_direct() -> bool:
	var ok := true
	var w := _road_world(20)
	var barn: Building = w.stores()[0]
	var p := w.drop_goods(&"wheat", 40.0, barn.access + Vector2i(15, 3), Task.Category.TRANSPORT)
	ok = _check("a pile 15 tiles from the barn, the pickup can drive (%.0f tiles)" % w.nav.walk_cost(p.cell, barn.access),
		p != null and w.can_drive() and w.nav.walk_cost(p.cell, barn.access) < Defs.ROUTE_MIN_WALK) and ok
	w.planner.tick()
	var legs := _chain_legs(w)
	ok = _check("one walking leg straight to the barn (%d legs)" % legs.size(), legs.size() == 1
		and legs[0].kind == Task.Kind.CARRY and legs[0].src == p and legs[0].dst == barn.store and legs[0].next == null) and ok
	ok = _check("no road pile", _road_piles(w).is_empty() and w.ground_piles == [p]) and ok
	return ok


## A log felled far from the barn, near a road the pickup drives: it is walked to a road pile beside
## the road and waits there for the pickup (a ride leg opens); the barn's room is promised all the
## way. Without a pickup the same log is walked straight to the barn.
func _test_far_pile_chain() -> bool:
	var ok := true
	var w := _road_world(90)
	var barn: Building = w.stores()[0]
	var tree := _far_tree(w)
	var walk := w.nav.walk_cost(barn.access, tree)
	ok = _check("the tree is far from the barn (%.0f tiles)" % walk, walk >= 80.0) and ok
	var felled := _until_felled_and_planned(w, tree)
	var piles := _road_piles(w)
	var rp: Store = piles[0] if piles.size() == 1 else null
	ok = _check("a road pile appears beside the road, nearer the tree than the barn", felled != null and rp != null
		and w.is_road_pile(rp) and w.road_block_at(rp.cell) == null and rp.filter.has(&"wood")
		and Vector2(rp.cell).distance_to(tree) < Vector2(rp.cell).distance_to(barn.access)) and ok
	if rp == null:
		return false
	var first: Task = null
	for t in _chain_legs(w):
		if t.src == felled:
			first = t
	ok = _check("the log is walked to the road pile, then rides to the barn", first != null and first.kind == Task.Kind.CARRY
		and first.dst == rp and first.next != null and first.next.kind == Task.Kind.RIDE and first.next.src == rp
		and first.next.dst == barn.store and first.next.fetch_from == null and first.plan.size() == 2
		and first.final_dst() == barn.store and first.next.plan == first.plan and first.next.leg_i == 1
		and first.category == Task.Category.FELLING and first.next.category == Task.Category.FELLING) and ok
	ok = _check("the barn's room and the road pile's room are promised", absf(barn.store.reserved_in.get(&"wood", 0.0) - 1.0) < 0.001
		and absf(rp.reserved_in.get(&"wood", 0.0) - 1.0) < 0.001) and ok
	var bad := {"wood": 0, "claims": 0, "barn": 0}
	var t := _run(w, 600.0, func() -> bool:
		if absf(_everywhere(w, &"wood") - 1.0) > 0.001:
			bad["wood"] += 1
		if not _reservations_match(w):
			bad["claims"] += 1
		if absf(barn.store.reserved_in.get(&"wood", 0.0) - 1.0) > 0.001:
			bad["barn"] += 1
		return w.tasks.tasks.any(func(x: Task) -> bool: return x.kind == Task.Kind.RIDE))
	var rides := w.tasks.tasks.filter(func(x: Task) -> bool: return x.kind == Task.Kind.RIDE)
	ok = _check("at the road pile the ride opens (%d s)" % t, rides.size() == 1 and rides[0].fetch_from == rp
		and absf(rp.amount(&"wood") - 1.0) < 0.001 and absf(rp.reserved_out.get(&"wood", 0.0) - 1.0) < 0.001
		and rp.reserved_in.is_empty() and w.tasks.pending_count() == 0) and ok
	ok = _check("the log is conserved and the claims match every tick (%d, %d bad)" % [bad["wood"], bad["claims"]],
		bad["wood"] == 0 and bad["claims"] == 0) and ok
	ok = _check("the barn's room stays promised from planning to now", bad["barn"] == 0) and ok
	for i in 5:
		w.tick(1.0)
	ok = _check("the waiting ride is not planned again", _chain_legs(w).size() == 1
		and absf(barn.store.reserved_in.get(&"wood", 0.0) - 1.0) < 0.001 and _reservations_match(w)) and ok
	ok = _check("the ride counts as available for needs", absf(w.available(&"wood") - 1.0) < 0.001) and ok

	var w2 := _road_world(90, false)
	var barn2: Building = w2.stores()[0]
	var felled2 := _until_felled_and_planned(w2, _far_tree(w2))
	var legs2 := _chain_legs(w2).filter(func(x: Task) -> bool: return x.src == felled2)
	ok = _check("without a pickup the log is walked straight to the barn", felled2 != null and legs2.size() == 1
		and legs2[0].kind == Task.Kind.CARRY and legs2[0].dst == barn2.store and legs2[0].next == null
		and _road_piles(w2).is_empty()) and ok
	return ok


## A chain breaks: the barn it goes to is demolished while the first leg is walked (the leg still
## ends at the road pile, every later claim is let go, and the log is planned again from there); or
## the worker of the first leg is called off (the log lies where he stood, every claim let go).
func _test_chain_break() -> bool:
	var ok := true
	var w := _road_world(90)
	var b2 := w.add_building(&"storage_barn", Vector2i(ROAD_X0 + 20, ROAD_Y - 3), 2)
	var tree := _far_tree(w)
	var wk: Worker = w.workers[0]
	_run(w, 900.0, func() -> bool: return wk.carrying == &"wood" and wk.task != null and wk.task.next != null)
	var leg := wk.task
	ok = _check("the log is on its way to a road pile", leg != null and leg.next != null and leg.dst.origin == Store.Origin.ROAD) and ok
	if leg == null or leg.next == null:
		return false
	var rp := leg.dst
	var dest := leg.final_dst().owner
	var other: Building = b2 if dest != b2 else w.stores()[0]
	ok = _check("its destination is demolished", w.demolish(dest)) and ok
	ok = _check("the walking leg goes on to the road pile, the rest of the chain is let go", wk.task == leg
		and leg.next == null and wk.carrying == &"wood" and other.store.reserved_in.is_empty()
		and absf(rp.reserved_in.get(&"wood", 0.0) - 1.0) < 0.001 and _reservations_match(w)) and ok
	var bad := [0]
	var t := _run(w, 300.0, func() -> bool:
		if absf(_everywhere(w, &"wood") - 1.0) > 0.001 or not _reservations_match(w):
			bad[0] += 1
		return wk.task != leg and _chain_legs(w).any(func(x: Task) -> bool: return x.fetch_from == rp))
	ok = _check("the log lies on the road pile and is planned again (%d s)" % t, absf(rp.amount(&"wood") - 1.0) < 0.001
		and _chain_legs(w).any(func(x: Task) -> bool: return x.fetch_from == rp and x.final_dst() == other.store)) and ok
	ok = _check("nothing lost, claims matched (%d bad ticks)" % bad[0], bad[0] == 0) and ok

	var w2 := _road_world(90)
	var barn2: Building = w2.stores()[0]
	_far_tree(w2)
	var wk2: Worker = w2.workers[0]
	_run(w2, 900.0, func() -> bool: return wk2.carrying == &"wood" and wk2.task != null and wk2.task.next != null)
	var rp2: Store = wk2.task.dst if wk2.task else null
	wk2.abort(w2)
	var dropped := w2.ground_piles.filter(func(s: Store) -> bool: return s.origin == Store.Origin.DROPPED and s.amount(&"wood") > 0.0)
	ok = _check("an aborted first leg drops the log where the worker stands", rp2 != null and wk2.carrying == &""
		and dropped.size() == 1 and absf(_everywhere(w2, &"wood") - 1.0) < 0.001) and ok
	ok = _check("and every claim of the chain is let go", barn2.store.reserved_in.is_empty() and rp2 != null
		and rp2.reserved_in.is_empty() and _chain_legs(w2).is_empty() and _reservations_match(w2)) and ok
	return ok


## "Carry to the barn now" on a road pile: its ride is dropped, an idle worker takes an urgent leg
## at once (with the barn's wheelbarrow) and the pile ends in the barn by hand, never by the pickup.
func _test_carry_now() -> bool:
	var ok := true
	var w := _road_world(90)
	var barn: Building = w.stores()[0]
	barn.store.put(&"wheelbarrow", 1.0)
	var spot: Variant = w.road_pile_spot(Vector2i(ROAD_X0 + 160, ROAD_Y + 5))
	ok = _check("a spot for a road pile beside the road", spot != null and w.road_block_at(spot) == null
		and w.road_nav.block_near(spot, Defs.STOP_REACH) != null) and ok
	if spot == null:
		return false
	var empty := w.add_road_pile(Vector2i(ROAD_X0 + 120, ROAD_Y + 2), &"wheat", Task.Category.TRANSPORT)
	ok = _check("an empty road pile has nothing to carry", w.carry_now_blocker(empty) == "Nothing to carry"
		and not w.carry_now(empty)) and ok
	var p := w.add_road_pile(spot, &"wheat", Task.Category.TRANSPORT)
	p.put(&"wheat", 120.0)
	ok = _check("a road pile is labelled so (%s)" % p.label(), p.label().begins_with("road pile") and w.is_road_pile(p)) and ok
	w.planner.tick()
	ok = _check("the empty road pile is swept away", not w.ground_piles.has(empty)) and ok
	var rides := _chain_legs(w).filter(func(x: Task) -> bool: return x.kind == Task.Kind.RIDE and x.fetch_from == p)
	ok = _check("the pickup is to bring it (one ride, all of it)", rides.size() == 1
		and absf(rides[0].fetch_amount - 120.0) < 0.001 and rides[0].next == null) and ok
	var wk := w.add_worker(Vector2i(ROAD_X0 + 150, ROAD_Y + 3), Worker.Look.FEMALE)
	ok = _check("nothing blocks carrying it now", w.carry_now_blocker(p) == "") and ok
	ok = _check("carry it to the barn now", w.carry_now(p)) and ok
	var leg := wk.task
	ok = _check("an idle worker takes an urgent leg at once, with the wheelbarrow", leg != null and leg.urgent
		and leg.kind == Task.Kind.CARRY and leg.worker == wk and leg.tool_from == barn.store and leg.dst == barn.store
		and wk.phase == Worker.Phase.TO_TOOL and absf(leg.fetch_amount - 120.0) < 0.001) and ok
	ok = _check("the ride is dropped, the pile is carried by hand", p.hand_only
		and not _chain_legs(w).any(func(x: Task) -> bool: return x.kind == Task.Kind.RIDE) and _reservations_match(w)) and ok
	var bad := {"ride": 0, "wheat": 0, "claims": 0}
	var t := _run(w, 900.0, func() -> bool:
		if _chain_legs(w).any(func(x: Task) -> bool: return x.kind == Task.Kind.RIDE):
			bad["ride"] += 1
		if absf(_everywhere(w, &"wheat") - 120.0) > 0.001:
			bad["wheat"] += 1
		if not _reservations_match(w):
			bad["claims"] += 1
		return not w.ground_piles.has(p) and _carried(w, &"wheat") == 0.0)
	ok = _check("the pile ends in the barn (%d s)" % t, not w.ground_piles.has(p)
		and absf(barn.store.amount(&"wheat") - 120.0) < 0.001 and barn.store.amount(&"wheelbarrow") == 1.0) and ok
	ok = _check("no ride planned from it, wheat conserved, claims matched (%d, %d, %d)" % [bad["ride"], bad["wheat"], bad["claims"]],
		bad["ride"] == 0 and bad["wheat"] == 0 and bad["claims"] == 0) and ok
	return ok


# --- step 3: pickup trips -------------------------------------------------------------

## Goods of `res` anywhere, a load being moved between the pickup and a place counted once (it is
## still at its store, or in the cargo, until it arrives).
func _total(w: World, res: StringName) -> float:
	return _everywhere(w, res) - _shuttled(w, res)


## The far log of _test_far_pile_chain goes on: the pickup collects the road pile on a trip and
## unloads it at the barn; the road pile goes away. The log is conserved and the claims match every
## tick, through loading, the drive and unloading.
func _test_pickup_brings_pile() -> bool:
	var ok := true
	var w := _road_world(90)
	var barn: Building = w.stores()[0]
	var v := w.vehicles[0]
	_far_tree(w)
	var seen := {"felled": false, "rp": null, "bad_wood": 0, "bad_claims": 0}
	var t := _run(w, 1500.0, func() -> bool:
		var n := _total(w, &"wood")
		if n > 0.001:
			seen["felled"] = true
		if seen["felled"] and absf(n - Defs.WOOD_PER_TREE) > 0.001:
			seen["bad_wood"] += 1
		if not _reservations_match(w):
			seen["bad_claims"] += 1
		if v.trip:
			for st: Dictionary in v.trip.stops:
				var s: Store = st["store"]
				if s and s.origin == Store.Origin.ROAD and not st["load"].is_empty():
					seen["rp"] = s
		return absf(barn.store.amount(&"wood") - Defs.WOOD_PER_TREE) < 0.001 and v.parked and v.trip == null)
	var rp: Store = seen["rp"]
	ok = _check("a pickup trip loads at the road pile", rp != null) and ok
	ok = _check("the log ends in the barn and the pickup is back (%d s)" % t, absf(barn.store.amount(&"wood") - Defs.WOOD_PER_TREE) < 0.001
		and v.parked and v.cargo.is_empty()) and ok
	ok = _check("the road pile is gone, nothing waits", rp != null and not w.ground_piles.has(rp) and _road_piles(w).is_empty()
		and _chain_legs(w).is_empty() and barn.store.reserved_in.is_empty()) and ok
	ok = _check("the log is conserved and the claims match every tick (%d, %d bad)" % [seen["bad_wood"], seen["bad_claims"]],
		seen["bad_wood"] == 0 and seen["bad_claims"] == 0) and ok
	return ok


## A field 5×4 with its gate by the road at `x` tiles along it (rows not worked: Planting is off).
func _road_field(w: World, x: int) -> Field:
	w.set_category_on(Task.Category.PLANTING, false)
	return w.add_field(Vector2i(ROAD_X0 + x, ROAD_Y + 3), 0, Vector2i(5, 4), &"wheat")


## Runs planner runs until `n` rides wait (so the dispatcher sees them all at once).
func _plan_rides(w: World, n: int) -> int:
	var rides := 0
	for i in 20:
		w.planner.tick()
		rides = w.tasks.tasks.filter(func(x: Task) -> bool: return x.kind == Task.Kind.RIDE).size()
		if rides >= n:
			break
	return rides


## Two road piles along one road and a field gate by the same road, the barn at its end: one trip
## with a stop at each and one at the barn, the load never over the pickup's capacity, everything
## ends in the barn.
func _test_multi_stop() -> bool:
	var ok := true
	var w := _road_world(90)
	var barn: Building = w.stores()[0]
	var v := w.vehicles[0]
	w.add_worker(barn.access, Worker.Look.MALE)
	w.add_worker(barn.access, Worker.Look.FEMALE)
	var p1 := w.add_road_pile(w.road_pile_spot(Vector2i(ROAD_X0 + 100, ROAD_Y + 4)), &"wood", Task.Category.TRANSPORT)
	p1.put(&"wood", 3.0)
	var p2 := w.add_road_pile(w.road_pile_spot(Vector2i(ROAD_X0 + 165, ROAD_Y + 4)), &"wheat", Task.Category.TRANSPORT)
	p2.put(&"wheat", 100.0)
	var f := _road_field(w, 130)
	f.pile = 200.0
	ok = _check("two road piles and a field gate by the road, far from the barn", w.is_road_pile(p1) and w.is_road_pile(p2)
		and w.stop_block(f.gate_store) != null and w.nav.walk_cost(f.access, barn.access) >= Defs.ROUTE_MIN_WALK) and ok
	ok = _check("three rides wait", _plan_rides(w, 3) == 3) and ok
	var trips := {}
	var most := [0]
	var bad := {"over": 0, "goods": 0, "claims": 0}
	var t := _run(w, 900.0, func() -> bool:
		if v.trip:
			trips[v.trip] = true
			most[0] = maxi(most[0], v.trip.stops.size())
		if v.cargo_weight() > Defs.PICKUP_CAPACITY + 0.001:
			bad["over"] += 1
		if absf(_total(w, &"wood") - 3.0) > 0.001 or absf(_total(w, &"wheat") - 300.0) > 0.001:
			bad["goods"] += 1
		if not _reservations_match(w):
			bad["claims"] += 1
		return barn.store.amount(&"wood") > 3.0 - 0.001 and barn.store.amount(&"wheat") > 300.0 - 0.001 and v.parked and v.trip == null)
	ok = _check("one trip with a stop at each pile, the gate and the barn (%d trips, %d stops)" % [trips.size(), most[0]],
		trips.size() == 1 and most[0] >= 4) and ok
	ok = _check("everything ends in the barn (%d s)" % t, barn.store.amount(&"wood") > 3.0 - 0.001
		and barn.store.amount(&"wheat") > 300.0 - 0.001 and f.pile < 0.001 and _road_piles(w).is_empty()) and ok
	ok = _check("never over capacity, goods conserved, claims matched (%d, %d, %d bad)" % [bad["over"], bad["goods"], bad["claims"]],
		bad["over"] == 0 and bad["goods"] == 0 and bad["claims"] == 0) and ok
	return ok


## A field gate by the road far from the barn: its harvest goes by a pickup trip, never by a
## walking leg to the barn.
func _test_field_pickup_trip() -> bool:
	var ok := true
	var w := _road_world(90)
	var barn: Building = w.stores()[0]
	var v := w.vehicles[0]
	w.add_worker(barn.access, Worker.Look.MALE)
	var f := _road_field(w, 120)
	f.pile = 120.0
	ok = _check("the gate is by the road, a long walk from the barn (%.0f tiles)" % w.nav.walk_cost(f.access, barn.access),
		w.stop_block(f.gate_store) != null and w.nav.walk_cost(f.access, barn.access) >= Defs.ROUTE_MIN_WALK) and ok
	var seen := {"walked": 0, "trip": false}
	var t := _run(w, 900.0, func() -> bool:
		for x in w.tasks.tasks:
			if x.kind == Task.Kind.CARRY and x.src == f.gate_store:
				seen["walked"] += 1
			if x.kind == Task.Kind.RIDE and x.src == f.gate_store and x.trip:
				seen["trip"] = true
		return barn.store.amount(&"wheat") > 120.0 - 0.001 and v.parked)
	ok = _check("the harvest is in the barn (%d s), brought by a trip" % t, barn.store.amount(&"wheat") > 120.0 - 0.001
		and seen["trip"]) and ok
	ok = _check("never by a walking leg (%d)" % seen["walked"], seen["walked"] == 0) and ok
	return ok


## The barn a ride unloads at is demolished while its goods are aboard: they stay aboard and go to
## the barn nearest the garage at the end of the trip. Nothing is lost.
func _test_stop_demolished() -> bool:
	var ok := true
	var w := _road_world(90)
	var barn: Building = w.stores()[0]
	var v := w.vehicles[0]
	w.add_worker(barn.access, Worker.Look.MALE)
	var b2 := w.add_building(&"storage_barn", Vector2i(ROAD_X0 + 30, ROAD_Y - 3), 2)
	var p := w.add_road_pile(w.road_pile_spot(Vector2i(ROAD_X0 + 170, ROAD_Y + 4)), &"wheat", Task.Category.TRANSPORT)
	p.put(&"wheat", 200.0)
	var ride: Array = [null]
	var t := _run(w, 600.0, func() -> bool:
		for x in w.tasks.tasks:
			if x.kind == Task.Kind.RIDE and x.trip:
				ride[0] = x
		return v.cargo.get(&"wheat", 0.0) > 200.0 - 0.001 and v.trip and v.trip.steps[v.trip.step_i]["type"] == "drive")
	ok = _check("the wheat is aboard on its way to the nearer barn (%d s)" % t, ride[0] != null and ride[0].dst == b2.store
		and v.cargo.get(&"wheat", 0.0) > 200.0 - 0.001) and ok
	ok = _check("that barn can be demolished meanwhile", w.demolish_blocker(b2) == "" and w.demolish(b2)) and ok
	ok = _check("its ride is dropped, the wheat stays aboard", not w.tasks.tasks.has(ride[0])
		and v.cargo.get(&"wheat", 0.0) > 200.0 - 0.001 and _reservations_match(w)) and ok
	var bad := [0]
	t = _run(w, 600.0, func() -> bool:
		if absf(_total(w, &"wheat") - 200.0) > 0.001 or not _reservations_match(w):
			bad[0] += 1
		return v.parked and v.trip == null)
	ok = _check("the rest is unloaded at the barn by the garage (%d s)" % t, absf(barn.store.amount(&"wheat") - 200.0) < 0.001
		and v.cargo.is_empty()) and ok
	ok = _check("nothing lost, claims matched (%d bad ticks)" % bad[0], bad[0] == 0) and ok
	return ok


## Saved while loading at a road pile (a load on its way into the pickup) and while driving with
## cargo: the goods are the same after loading.
func _test_save_mid_trip() -> bool:
	var ok := true
	var w := _road_world(90)
	var barn: Building = w.stores()[0]
	var v := w.vehicles[0]
	w.add_worker(barn.access, Worker.Look.MALE)
	w.add_worker(barn.access, Worker.Look.FEMALE)
	var p := w.add_road_pile(w.road_pile_spot(Vector2i(ROAD_X0 + 160, ROAD_Y + 4)), &"wheat", Task.Category.TRANSPORT)
	p.put(&"wheat", 300.0)
	var t := _run(w, 600.0, func() -> bool:
		return _shuttled(w, &"wheat") > 0.0 and v.trip and v.trip.steps[v.trip.step_i]["type"] == "load_stop")
	ok = _check("a load is on its way into the pickup at the road pile (%d s)" % t, _shuttled(w, &"wheat") > 0.0) and ok
	ok = _save_same(w, "loading") and ok
	t = _run(w, 600.0, func() -> bool:
		return not v.cargo.is_empty() and v.trip and v.trip.steps[v.trip.step_i]["type"] == "drive")
	ok = _check("driving with %.0f kg aboard (%d s)" % [v.cargo_weight(), t], v.cargo_weight() > 0.0) and ok
	ok = _save_same(w, "driving") and ok
	return ok


func _save_same(w: World, when: String) -> bool:
	var before := _total(w, &"wheat")
	SaveGame.save(w, "logistics_test")
	var w2 := SaveGame.load_world("logistics_test")
	SaveGame.delete("logistics_test")
	var after := _everywhere(w2, &"wheat") if w2 else -1.0
	return _check("saved while %s: the wheat survives exactly (%.0f -> %.0f kg)" % [when, before, after], absf(after - before) < 0.001)


# --- step 3: Task 2 review fixes ------------------------------------------------------

## A road pile whose road beside it is demolished is no stop any more: it is not used as a hand-off
## (no script error), and its goods are planned again (walked, or to a road pile the pickup reaches).
func _test_road_cut_pile() -> bool:
	var ok := true
	var w := _road_world(90)
	var p := w.add_road_pile(w.road_pile_spot(Vector2i(ROAD_X0 + 150, ROAD_Y + 5)), &"wood", Task.Category.FELLING)
	p.put(&"wood", 2.0)
	for x in range(ROAD_X0 + 140, ROAD_X0 + 162, 2):
		w.demolish_road(Vector2i(x, ROAD_Y))
	ok = _check("the road beside the road pile is gone", w.stop_block(p) == null) and ok
	for i in 3:
		w.nav.clock += 1.0
		w.planner.tick()
	var legs := _chain_legs(w).filter(func(x: Task) -> bool: return x.fetch_from == p)
	ok = _check("its goods are planned again (%d legs), never a ride from it" % legs.size(), not legs.is_empty()
		and legs.all(func(x: Task) -> bool: return x.kind == Task.Kind.CARRY) and _reservations_match(w)) and ok
	return ok


## A waiting ride whose ends the pickup can no longer reach (the road between was demolished) is
## dropped with its claims, and the goods are walked instead.
func _test_cut_off_ride() -> bool:
	var ok := true
	var w := _road_world(90)
	var b2 := w.add_building(&"storage_barn", Vector2i(ROAD_X0 + 50, ROAD_Y - 3), 2)
	var p := w.drop_goods(&"wood", 2.0, Vector2i(ROAD_X0 + 175, ROAD_Y + 3), Task.Category.FELLING)
	for i in 3:
		w.planner.tick()
	var rides := _chain_legs(w).filter(func(x: Task) -> bool: return x.kind == Task.Kind.RIDE and x.fetch_from == p)
	ok = _check("the pile rides to the far barn", rides.size() == 1 and rides[0].dst == b2.store) and ok
	for x in range(ROAD_X0 + 26, ROAD_X0 + 36, 2):
		w.demolish_road(Vector2i(x, ROAD_Y))
	for i in 10:
		w.nav.clock += 1.0
		w.planner.tick()
	var legs := _chain_legs(w).filter(func(x: Task) -> bool: return x.fetch_from == p)
	ok = _check("the ride is dropped, the logs are walked instead", not _chain_legs(w).any(func(x: Task) -> bool: return x.kind == Task.Kind.RIDE)
		and not legs.is_empty() and legs.all(func(x: Task) -> bool: return x.kind == Task.Kind.CARRY and x.next == null)
		and _reservations_match(w)) and ok
	return ok


## A hand-off spot remembered by the planner is checked again before a road pile is made there: not
## inside a construction site placed on it meanwhile.
func _test_stale_handoff() -> bool:
	var ok := true
	var w := _road_world(90)
	var p := w.drop_goods(&"wood", 1.0, Vector2i(ROAD_X0 + 150, ROAD_Y + 12), Task.Category.FELLING)
	w.planner.tick()
	var spot: Variant = w.planner._handoffs.get(p)
	ok = _check("the planner remembers a road pile spot for the pile", spot is Vector2i) and ok
	if not (spot is Vector2i):
		return false
	for t in w.tasks.tasks.duplicate():
		w.tasks.remove(t)
	w.planner._sweep_piles()
	var site: ConstructionSite = null
	for dy in range(-6, 1):
		for dx in range(-6, 1):
			for rot in 4:
				var a := Vector2i(spot.x + dx, spot.y + dy)
				if site == null and w.can_place(&"storage_barn", a, rot):
					var s := w.place_site(&"storage_barn", a, rot)
					if s and s.cells().has(spot):
						site = s
					elif s:
						w.demolish(s)
	ok = _check("a site now covers the spot", site != null) and ok
	w.planner.tick()
	var inside := w.ground_piles.filter(func(s: Store) -> bool: return w.occupant[w.idx(s.cell)] != 0)
	ok = _check("no road pile is made inside the site", inside.is_empty() and _reservations_match(w)) and ok
	return ok


## Goods walking to a road pile on their way to a barn still count as available (no false alerts).
func _test_available_chain() -> bool:
	var ok := true
	var w := _road_world(90)
	w.drop_goods(&"wood", 1.0, Vector2i(ROAD_X0 + 170, ROAD_Y + 8), Task.Category.FELLING, Store.Origin.FELLED)
	w.planner.tick()
	var first := _chain_legs(w).filter(func(x: Task) -> bool: return x.kind == Task.Kind.CARRY and x.next != null)
	ok = _check("a walk to a road pile, then a ride (not under way yet)", first.size() == 1 and first[0].worker == null) and ok
	ok = _check("the log counts as available (%.0f)" % w.available(&"wood"), absf(w.available(&"wood") - 1.0) < 0.001) and ok
	return ok


## "Carry to the barn now" legs stay urgent: not taken over by a need, urgent again when planned
## again, and taken even when their category is switched off.
func _test_urgent_kept() -> bool:
	var ok := true
	var w := _road_world(90)
	var p := w.add_road_pile(w.road_pile_spot(Vector2i(ROAD_X0 + 160, ROAD_Y + 5)), &"wheat", Task.Category.TRANSPORT)
	p.put(&"wheat", 120.0)
	w.planner.tick()
	ok = _check("carry it to the barn now", w.carry_now(p)) and ok
	var legs := w.tasks.tasks.filter(func(x: Task) -> bool: return x.fetch_from == p)
	ok = _check("its legs are urgent and no need may take them over", not legs.is_empty()
		and legs.all(func(x: Task) -> bool: return x.urgent and not w.waiting_clear(x))) and ok
	for t in legs:
		w.tasks.remove(t)
	w.planner.tick()
	legs = w.tasks.tasks.filter(func(x: Task) -> bool: return x.fetch_from == p)
	ok = _check("planned again, they are still urgent (%d legs)" % legs.size(), not legs.is_empty()
		and legs.all(func(x: Task) -> bool: return x.urgent and x.kind == Task.Kind.CARRY)) and ok
	w.set_category_on(Task.Category.TRANSPORT, false)
	var wk := w.add_worker(w.stores()[0].access, Worker.Look.MALE)
	w.tick(1.0)
	ok = _check("a worker takes one with Transport switched off", wk.task != null and wk.task.urgent) and ok
	return ok


## The road pile spot is the nearest one in a straight line, also when a farther ring of road blocks
## has a nearer tile than the first ring with one.
func _test_spot_nearest() -> bool:
	var w := World.new(64, 1)
	for b: Vector2i in [Vector2i(10, 10), Vector2i(12, 10), Vector2i(14, 10), Vector2i(14, 8), Vector2i(14, 6),
			Vector2i(14, 4), Vector2i(14, 2), Vector2i(14, 0)]:
		w.add_road_block(b, &"dirt")
	var spot: Variant = w._find_road_pile_spot(Vector2i(0, 0), Vector2i(10, 10))
	return _check("the nearest road pile spot (%s)" % spot, spot == Vector2i(13, 0))


# --- step 3: the Dealer as trip stops (Task 4) ----------------------------------------

## The road world with the Dealer by the road `x` tiles east of the barn.
func _dealer_world(x := 120) -> World:
	var w := _road_world(90)
	w.add_building(&"dealer", Vector2i(ROAD_X0 + x, ROAD_Y - 4), 2)
	return w


## 600 kg wheat in the barn, keep 100, auto-sell on: one trip sells 500 kg at the Dealer (money up
## by 500 × the price), the barn keeps 100; the sale is a ride from the barn to the Dealer's store.
func _test_dealer_stop() -> bool:
	var ok := true
	var w := _dealer_world()
	var barn: Building = w.stores()[0]
	var v := w.vehicles[0]
	w.add_worker(barn.access, Worker.Look.MALE)
	ok = _check("the Dealer is a store, a stop by the road", w.dealer_store.kind == Store.Kind.DEALER
		and w.dealer_store.owner == w.dealer() and w.stop_block(w.dealer_store) != null and w.places().has(w.dealer_store)) and ok
	barn.store.put(&"wheat", 600.0)
	w.auto_sell[&"wheat"] = {"on": true, "keep": 100.0}
	var money := w.money
	var seen := {"trips": {}, "sale": false, "dealer_stop": false, "bad": 0}
	var t := _run(w, 900.0, func() -> bool:
		if v.trip:
			seen["trips"][v.trip] = true
			for st: Dictionary in v.trip.stops:
				if st["store"] == w.dealer_store and st["dealer"]:
					seen["dealer_stop"] = true
		for x in w.tasks.tasks:
			if x.kind == Task.Kind.RIDE and x.dst == w.dealer_store and x.src == barn.store:
				seen["sale"] = true
		if absf(_total(w, &"wheat") + (w.money - money) / Defs.SELL_PRICE[&"wheat"] - 600.0) > 0.001 or not _reservations_match(w):
			seen["bad"] += 1
		return w.money > money and v.parked and v.trip == null)
	ok = _check("a ride from the barn to the Dealer, on a trip with a Dealer stop", seen["sale"] and seen["dealer_stop"]) and ok
	ok = _check("one trip sells 500 kg (%d s, %d trips, +%d qk)" % [t, seen["trips"].size(), w.money - money],
		seen["trips"].size() == 1 and w.money - money == roundi(500.0 * Defs.SELL_PRICE[&"wheat"])) and ok
	ok = _check("the barn keeps 100 kg (%.0f), nothing stored at the Dealer" % barn.store.amount(&"wheat"),
		absf(barn.store.amount(&"wheat") - 100.0) < 0.001 and w.dealer_store.contents.is_empty()
		and w.dealer_store.reserved_in.is_empty()) and ok
	ok = _check("wheat + money conserved, claims matched every tick (%d bad)" % seen["bad"], seen["bad"] == 0) and ok
	ok = _check("booked as sales", w.ledger.get("sales: wheat", 0) == roundi(500.0 * Defs.SELL_PRICE[&"wheat"])) and ok
	return ok


## Ordered goods are the Dealer store's contents: 40 planks ordered → a trip collects them and they
## end in the barn. With a construction site by the road that wants planks, they go straight there.
func _test_order_collected() -> bool:
	var ok := true
	var w := _dealer_world()
	var barn: Building = w.stores()[0]
	var v := w.vehicles[0]
	w.add_worker(barn.access, Worker.Look.MALE)
	ok = _check("order 40 planks", w.order(&"planks", 40.0)) and ok
	ok = _check("the order is in the Dealer's store", absf(w.dealer_store.amount(&"planks") - 40.0) < 0.001
		and absf(w.orders.get(&"planks", 0.0) - 40.0) < 0.001 and absf(w.orders_total() - 40.0) < 0.001) and ok
	var bad := [0]
	var t := _run(w, 900.0, func() -> bool:
		if absf(_total(w, &"planks") - 40.0) > 0.001 or not _reservations_match(w):
			bad[0] += 1
		return absf(barn.store.amount(&"planks") - 40.0) < 0.001 and v.parked)
	ok = _check("a trip collects them, they end in the barn (%d s)" % t, absf(barn.store.amount(&"planks") - 40.0) < 0.001
		and w.orders.is_empty() and v.cargo.is_empty()) and ok
	ok = _check("planks conserved, claims matched (%d bad)" % bad[0], bad[0] == 0) and ok

	var w2 := _dealer_world()
	var barn2: Building = w2.stores()[0]
	var v2 := w2.vehicles[0]
	w2.add_worker(barn2.access, Worker.Look.MALE)
	w2.add_worker(barn2.access, Worker.Look.FEMALE)
	var site := w2.place_site(&"storage_barn", Vector2i(ROAD_X0 + 80, ROAD_Y - 3), 2)
	ok = _check("a barn site by the road wants planks", site != null and site.material().has(&"planks")) and ok
	if site == null:
		return false
	var need: float = site.material()[&"planks"]
	w2.order(&"planks", need)
	var seen := {"straight": false}
	t = _run(w2, 1500.0, func() -> bool:
		for x in w2.tasks.tasks:
			if x.kind == Task.Kind.RIDE and x.src == w2.dealer_store and x.final_dst() == site.supply:
				seen["straight"] = true
		return site.stage != ConstructionSite.Stage.DELIVERY or not w2.buildings.has(site.id))
	ok = _check("the planks ride from the Dealer straight to the site (%d s)" % t, seen["straight"]
		and absf(barn2.store.amount(&"planks")) < 0.001 and w2.orders.is_empty()) and ok
	return ok


## Hire 1 → a trip with a Dealer stop brings the worker; the worker count goes up by one.
func _test_hire_stop() -> bool:
	var ok := true
	var w := _dealer_world()
	var barn: Building = w.stores()[0]
	var v := w.vehicles[0]
	w.add_worker(barn.access, Worker.Look.MALE)
	var n := w.workers.size()
	ok = _check("hire one", w.hire(1)) and ok
	var seen := {"stop": false, "status": false}
	var t := _run(w, 600.0, func() -> bool:
		if v.trip:
			for st: Dictionary in v.trip.stops:
				if st["dealer"] and st.get("hires", 0) == 1:
					seen["stop"] = true
		seen["status"] = seen["status"] or v.status == "Hiring workers at the Dealer"
		return w.workers.size() == n + 1 and v.parked and v.passengers.is_empty())
	ok = _check("a trip with a Dealer stop hires and brings the worker (%d s)" % t, seen["stop"] and seen["status"]
		and w.workers.size() == n + 1 and w.hires_wanted == 0) and ok
	return ok


## A road pile, a sale and an order at once: one trip with a load stop at the road pile, the Dealer
## stop and an unload stop at the barn.
func _test_one_trip_mixed() -> bool:
	var ok := true
	var w := _dealer_world(150)
	var barn: Building = w.stores()[0]
	var v := w.vehicles[0]
	w.add_worker(barn.access, Worker.Look.MALE)
	var p := w.add_road_pile(w.road_pile_spot(Vector2i(ROAD_X0 + 100, ROAD_Y + 4)), &"wood", Task.Category.TRANSPORT)
	p.put(&"wood", 3.0)
	barn.store.put(&"wheat", 300.0)
	w.auto_sell[&"wheat"] = {"on": true, "keep": 0.0}
	w.order(&"seed_wheat", 20.0)
	_plan_rides(w, 3)
	w._dispatch()
	var t := v.trip
	ok = _check("one trip is made", t != null) and ok
	if t == null:
		return false
	var kinds := []
	for st: Dictionary in t.stops:
		var s: Store = st["store"]
		kinds.append("dealer" if st["dealer"] else ("road pile" if s == p else ("barn" if s == barn.store else s.label())))
	var di := kinds.find("dealer")
	ok = _check("it loads at the road pile, stops at the Dealer and unloads at the barn (%s)" % [kinds],
		kinds.has("road pile") and di >= 0 and kinds.rfind("barn") > di and t.stops[di]["unload"].size() >= 1
		and t.stops[di]["load"].size() >= 1 and t.category == Task.Category.PICKUP) and ok
	var money := w.money
	_run(w, 900.0, func() -> bool: return v.parked and v.trip == null)
	ok = _check("all done: logs and seed in the barn, wheat sold", absf(barn.store.amount(&"wood") - 3.0) < 0.001
		and absf(barn.store.amount(&"seed_wheat") - 20.0) < 0.001 and barn.store.amount(&"wheat") < 0.001
		and w.money - money == roundi(300.0 * Defs.SELL_PRICE[&"wheat"])) and ok
	return ok


## Every trip and its loading helpers are "Pickup trips" (high by default), whatever the rides are:
## a trip of road piles is not starved by fresh work of higher categories.
func _test_trip_category() -> bool:
	var ok := true
	ok = _check("the category is called Pickup trips", Task.CATEGORY_NAMES[Task.Category.PICKUP][0] == "Pickup trips"
		and Task.DEFAULT_ORDER.find(Task.Category.PICKUP) == 1) and ok
	var w := _road_world(90)
	var barn: Building = w.stores()[0]
	var v := w.vehicles[0]
	for i in 3:
		w.add_worker(barn.access, Worker.Look.MALE)
	var p := w.add_road_pile(w.road_pile_spot(Vector2i(ROAD_X0 + 100, ROAD_Y + 4)), &"wheat", Task.Category.TRANSPORT)
	p.put(&"wheat", 300.0)
	var seen := {"trip": -1, "helpers": {}}
	_run(w, 600.0, func() -> bool:
		if v.trip:
			seen["trip"] = v.trip.category
		for x in w.tasks.tasks:
			if x.kind == Task.Kind.HELP:
				seen["helpers"][x.category] = true
		return absf(barn.store.amount(&"wheat") - 300.0) < 0.001 and v.parked)
	ok = _check("the trip of a Transport pile is a Pickup trip, its helpers too (%s, %s)" % [seen["trip"], seen["helpers"].keys()],
		seen["trip"] == Task.Category.PICKUP and seen["helpers"].keys() == [Task.Category.PICKUP]) and ok
	return ok


## The route cost is per hand load on both sides: the drive and the wait for the pickup are shared by
## the hand loads of a trip. A short carry is walked; a long one along the road goes by the pickup;
## the break-even on a straight road is printed.
func _test_route_per_load() -> bool:
	var ok := true
	var w := _road_world(90)
	var barn: Building = w.stores()[0]
	var near := w.drop_goods(&"wheat", 50.0, barn.access + Vector2i(20, 0), Task.Category.TRANSPORT)
	w.planner._vblock = w.drive_block()
	var r := w.planner._route(near, barn.store, &"wheat")
	ok = _check("20 tiles along the road are walked", r["a"] == null and r["cost"] < INF) and ok
	var even := -1
	for x in range(20, 170, 2):
		var s := Store.new(Store.Kind.GATE, null, barn.access + Vector2i(x, 0))
		w.planner._handoffs.clear()
		w.planner._t0 = Time.get_ticks_usec()
		w.planner.starved = false
		var rr := w.planner._route(s, barn.store, &"wheat")
		if rr["a"] != null:
			even = x
			break
	var loads := Defs.PICKUP_CAPACITY / Defs.weight(&"wheat", Defs.hand_load(&"wheat"))
	print("    break-even door to door on a straight dirt road: %d tiles (walk cost %.0f), %.0f hand loads per trip"
		% [even, w.nav.walk_cost(barn.access, barn.access + Vector2i(even, 0)), loads])
	ok = _check("from about %d tiles along the road the pickup is cheaper" % even, even >= int(Defs.ROUTE_MIN_WALK) and even <= 90) and ok
	return ok


## Helpers only join a stop they can reach within Defs.HELPER_REACH tiles: workers at the farm do
## not walk out to a far road pile (the driver loads alone there); a worker near it helps.
func _test_helper_reach() -> bool:
	var ok := true
	var w := _road_world(90)
	var barn: Building = w.stores()[0]
	var v := w.vehicles[0]
	for i in 3:
		w.add_worker(barn.access, Worker.Look.MALE)
	var far := w.add_road_pile(w.road_pile_spot(Vector2i(ROAD_X0 + 160, ROAD_Y + 4)), &"wheat", Task.Category.TRANSPORT)
	far.put(&"wheat", 300.0)
	var seen := {"far_help": 0, "barn_help": 0}
	_run(w, 900.0, func() -> bool:
		for x in w.tasks.tasks:
			if x.kind == Task.Kind.HELP and x.worker:
				if Vector2(x.cell).distance_to(far.cell) < 10.0:
					seen["far_help"] += 1
				else:
					seen["barn_help"] += 1
		return absf(barn.store.amount(&"wheat") - 300.0) < 0.001 and v.parked)
	ok = _check("nobody walks out from the farm to help at the far pile (%d)" % seen["far_help"], seen["far_help"] == 0
		and absf(barn.store.amount(&"wheat") - 300.0) < 0.001) and ok
	ok = _check("workers at the farm help unload at the barn (%d)" % seen["barn_help"], seen["barn_help"] > 0) and ok

	var w2 := _road_world(90)
	var barn2: Building = w2.stores()[0]
	var v2 := w2.vehicles[0]
	w2.add_worker(barn2.access, Worker.Look.MALE)
	var far2 := w2.add_road_pile(w2.road_pile_spot(Vector2i(ROAD_X0 + 160, ROAD_Y + 4)), &"wheat", Task.Category.TRANSPORT)
	far2.put(&"wheat", 300.0)
	w2.set_category_on(Task.Category.TRANSPORT, false)
	var local := w2.add_worker(far2.cell + Vector2i(-8, 0), Worker.Look.FEMALE)
	var helped := [false]
	_run(w2, 900.0, func() -> bool:
		if local.task and local.task.kind == Task.Kind.HELP:
			helped[0] = true
		return absf(barn2.store.amount(&"wheat") - 300.0) < 0.001 and v2.parked)
	ok = _check("a worker near the far pile helps load there", helped[0]) and ok
	return ok


# --- step 3 review fixes -------------------------------------------------------------

## A trip with a far road pile (helpers called there who never come) and an unload at the barn:
## every load and unload step finishes (helpers not needed any more go), the driver is aboard
## whenever the pickup drives, and no "Help load the pickup" task is left behind.
func _test_trip_cleanup() -> bool:
	var ok := true
	var w := _road_world(90)
	var barn: Building = w.stores()[0]
	var v := w.vehicles[0]
	for i in 3:
		w.add_worker(barn.access, Worker.Look.MALE)
	var far := w.add_road_pile(w.road_pile_spot(Vector2i(ROAD_X0 + 160, ROAD_Y + 4)), &"wheat", Task.Category.TRANSPORT)
	far.put(&"wheat", 300.0)
	var seen := {"trip": null, "drives": 0, "left": 0, "helps": 0}
	var t := _run(w, 900.0, func() -> bool:
		var tr := v.trip
		if tr and tr.worker and tr.step_i < tr.steps.size():
			seen["trip"] = tr
			if tr.steps[tr.step_i]["type"] == "drive" and not v.parked:
				seen["drives"] += 1
				if not tr.worker.in_vehicle or tr.worker.pos.distance_to(v.pos) > 0.5:
					seen["left"] += 1
		for x in w.tasks.tasks:
			if x.kind == Task.Kind.HELP:
				seen["helps"] += 1
		return absf(barn.store.amount(&"wheat") - 300.0) < 0.001 and v.parked and v.trip == null)
	var tr: Task = seen["trip"]
	var unfinished := 0
	var transfers := 0
	if tr:
		for s: Dictionary in tr.steps:
			if s.has("queue"):
				transfers += 1
				if not s.get("finished", false):
					unfinished += 1
	ok = _check("the wheat is in the barn and the pickup back (%d s)" % t, absf(barn.store.amount(&"wheat") - 300.0) < 0.001
		and v.parked and seen["helps"] > 0) and ok
	ok = _check("every load and unload step finishes (%d of %d not)" % [unfinished, transfers], tr != null and transfers >= 2
		and unfinished == 0) and ok
	ok = _check("the driver rides with the pickup between stops (%d of %d frames not)" % [seen["left"], seen["drives"]],
		seen["drives"] > 0 and seen["left"] == 0) and ok
	var helps := w.tasks.tasks.filter(func(x: Task) -> bool: return x.kind == Task.Kind.HELP)
	ok = _check("no helper task is left after the trip (%d)" % helps.size(), helps.is_empty()
		and w.category_counts()[Task.Category.PICKUP] == [0, 0]) and ok
	return ok


## A ride that gets only part of its goods aboard (the pickup is nearly full) lets go of the rest
## when loading ends: the rest is planned again and comes on a later trip.
func _test_partial_load() -> bool:
	var ok := true
	var w := _road_world(90)
	var barn: Building = w.stores()[0]
	var v := w.vehicles[0]
	w.add_worker(barn.access, Worker.Look.MALE)
	var p := w.add_road_pile(w.road_pile_spot(Vector2i(ROAD_X0 + 160, ROAD_Y + 4)), &"wheat", Task.Category.TRANSPORT)
	p.put(&"wheat", 300.0)
	var extra := floorf((Defs.PICKUP_CAPACITY - 100.0) / Defs.weight(&"planks", 1.0))
	var room := Defs.PICKUP_CAPACITY - Defs.weight(&"planks", extra)
	var st := {"k": -1, "ride": null, "checked": false, "ok": false}
	var t := _run(w, 1800.0, func() -> bool:
		var tr := v.trip
		if tr and tr.worker and tr.step_i < tr.steps.size() and not st["checked"]:
			var s: Dictionary = tr.steps[tr.step_i]
			if st["k"] < 0 and s["type"] == "drive" and s.has("stop") and not tr.stops[s["stop"]]["load"].is_empty():
				v.cargo[&"planks"] = extra      # someone filled it up on the way
				st["ride"] = tr.stops[s["stop"]]["load"][0]
				for k in tr.steps.size():
					if tr.steps[k]["type"] == "load_stop" and tr.steps[k]["stop"] == s["stop"]:
						st["k"] = k
			elif st["k"] >= 0 and tr.step_i > st["k"]:
				var r: Task = st["ride"]
				st["checked"] = true
				st["ok"] = r.fetch_from == null and absf(r.loaded - room) < 0.001 and absf(r.fetch_amount - room) < 0.001 \
					and p.reserved_out.get(&"wheat", 0.0) < 0.001 and absf(p.amount(&"wheat") - (300.0 - room)) < 0.001
		return absf(barn.store.amount(&"wheat") - 300.0) < 0.001 and absf(barn.store.amount(&"planks") - extra) < 0.001 \
			and v.parked and v.trip == null)
	ok = _check("a ride only partly aboard lets go of the rest when loading ends (%.0f kg aboard)" % room,
		st["checked"] and st["ok"]) and ok
	ok = _check("the rest comes later, the planks go to the barn (%d s)" % t, absf(barn.store.amount(&"wheat") - 300.0) < 0.001
		and absf(barn.store.amount(&"planks") - extra) < 0.001 and _reservations_match(w)) and ok
	return ok


## Pickup trips switched off in Priorities: the planner plans no vehicle routes (no road piles, no
## rides), a trip nobody started is called off, rides that waited are dropped and the goods walked
## to the barn; the pickup stays in the garage, goods are conserved and claims let go.
func _test_pickup_off() -> bool:
	var ok := true
	var w := _road_world(90)
	var barn: Building = w.stores()[0]
	var v := w.vehicles[0]
	w.add_worker(barn.access, Worker.Look.MALE)
	var p := w.add_road_pile(w.road_pile_spot(Vector2i(ROAD_X0 + 120, ROAD_Y + 4)), &"wheat", Task.Category.TRANSPORT)
	p.put(&"wheat", 100.0)
	ok = _check("a ride waits", _plan_rides(w, 1) == 1) and ok
	w._force_trip = true
	w._dispatch()
	ok = _check("a trip waits for a driver", v.trip != null and v.trip.worker == null) and ok
	w.set_category_on(Task.Category.PICKUP, false)
	ok = _check("no vehicle routes while off", not w.can_drive()
		and w.road_pile_spot(Vector2i(ROAD_X0 + 160, ROAD_Y + 4)) == null) and ok
	var bad := {"left": 0, "ride": 0, "wheat": 0, "claims": 0, "time": 0.0}
	var t := _run(w, 1500.0, func() -> bool:
		bad["time"] += 0.1
		if not v.parked:
			bad["left"] += 1
		if bad["time"] > 2.05 and (v.trip != null or w.tasks.tasks.any(func(x: Task) -> bool: return x.kind == Task.Kind.RIDE)):
			bad["ride"] += 1
		if absf(_total(w, &"wheat") - 100.0) > 0.001:
			bad["wheat"] += 1
		if not _reservations_match(w):
			bad["claims"] += 1
		return absf(barn.store.amount(&"wheat") - 100.0) < 0.001)
	ok = _check("the trip is called off and the ride dropped (%d frames not)" % bad["ride"], bad["ride"] == 0
		and v.status == "Pickup trips are switched off") and ok
	ok = _check("the wheat is walked to the barn, the pickup never leaves (%d s, %d frames out)" % [t, bad["left"]],
		absf(barn.store.amount(&"wheat") - 100.0) < 0.001 and bad["left"] == 0) and ok
	ok = _check("wheat conserved, claims matched (%d, %d bad)" % [bad["wheat"], bad["claims"]],
		bad["wheat"] == 0 and bad["claims"] == 0 and barn.store.reserved_in.is_empty()) and ok

	# a walk to a road pile planned before: dropped, the goods walked all the way
	var w2 := _road_world(90)
	var barn2: Building = w2.stores()[0]
	var g := w2.drop_goods(&"wheat", 40.0, Vector2i(ROAD_X0 + 165, ROAD_Y + 9), Task.Category.TRANSPORT)
	w2.planner.tick()
	var via := _chain_legs(w2).filter(func(x: Task) -> bool: return x.src == g and x.next != null and x.next.kind == Task.Kind.RIDE)
	ok = _check("a far pile is to be walked to a road pile first", via.size() == 1) and ok
	w2.set_category_on(Task.Category.PICKUP, false)
	for i in 3:
		w2.planner.tick()
	var legs := _chain_legs(w2)
	ok = _check("switched off, it is walked straight to the barn (%d legs)" % legs.size(), not legs.is_empty()
		and legs.all(func(x: Task) -> bool: return x.kind == Task.Kind.CARRY and x.src == g and x.dst == barn2.store and x.next == null)
		and _reservations_match(w2)) and ok
	w2.set_category_on(Task.Category.PICKUP, true)
	ok = _check("switched on again, vehicle routes are planned", w2.can_drive()) and ok
	return ok


## Road piles are named by where they lie, with letters when two would read the same; the names
## show in a trip's stops and survive a save.
func _test_road_pile_names() -> bool:
	var ok := true
	var w := _road_world(90)
	var barn: Building = w.stores()[0]
	var v := w.vehicles[0]
	var f := _road_field(w, 120)
	var a := w.add_road_pile(w.road_pile_spot(Vector2i(ROAD_X0 + 122, ROAD_Y + 4)), &"wheat", Task.Category.TRANSPORT)
	ok = _check("a road pile by a field: %s" % a.label(), a.label() == "road pile by %s" % f.display_name()) and ok
	var b := w.add_road_pile(w.road_pile_spot(Vector2i(ROAD_X0 + 126, ROAD_Y + 4)), &"wheat", Task.Category.TRANSPORT)
	ok = _check("two by the same field get letters: %s, %s" % [a.label(), b.label()],
		a.label() == "road pile A by %s" % f.display_name() and b.label() == "road pile B by %s" % f.display_name()) and ok
	a.put(&"wheat", 50.0)
	b.put(&"wheat", 50.0)
	_plan_rides(w, 2)
	w._dispatch()
	var labels := PackedStringArray()
	for st: Dictionary in w.trip_preview(v)["stops"]:
		if st["kind"] == &"load":
			labels.append(st["label"])
	ok = _check("the trip's stops read apart: %s" % ", ".join(labels), labels.size() == 2 and labels[0] != labels[1]) and ok
	SaveGame.save(w, "logistics_test")
	var w2 := SaveGame.load_world("logistics_test")
	SaveGame.delete("logistics_test")
	var names := PackedStringArray()
	if w2:
		for s in w2.ground_piles:
			names.append(s.label())
	names.sort()
	ok = _check("the names survive a save", names == PackedStringArray([a.label(), b.label()])) and ok
	return ok


## The road pile panel asks carry_now_blocker a few times a second: it runs no path search (after
## a grid change the walk to the barn is not looked up); the click does.
func _test_carry_blocker_cheap() -> bool:
	var ok := true
	var w := _road_world(90)
	var barn: Building = w.stores()[0]
	var p := w.add_road_pile(w.road_pile_spot(Vector2i(ROAD_X0 + 160, ROAD_Y + 4)), &"wheat", Task.Category.TRANSPORT)
	p.put(&"wheat", 60.0)
	var spot: Vector2i = w.store_spot(p)
	w.add_building(&"storage_barn", Vector2i(ROAD_X0 + 40, ROAD_Y - 3), 2)     # the grid changes
	ok = _check("nothing blocks carrying it", w.carry_now_blocker(p) == "") and ok
	ok = _check("no path searched for the button", not w.nav.has_cost(spot, barn.access)) and ok
	ok = _check("the click plans the legs", w.carry_now(p) and w.nav.has_cost(spot, barn.access)) and ok
	return ok
