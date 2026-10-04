extends SceneTree
## Logistics checks: stores, goods in places, fetch claims, delivery to the reached barn.
##   Godot --headless --path . --script scripts/tools/logistics_test.gd


func _init() -> void:
	var ok := true
	ok = _store_checks() and ok
	ok = _world_checks() and ok
	ok = _conservation_checks() and ok
	ok = _claim_checks() and ok
	ok = _removed_barn_checks() and ok
	ok = _release_checks() and ok
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


## Round-1 review fixes: goods must survive a barn move, and a fetch may never carry more than
## what take_goods actually handed over (a claim made elsewhere in the meantime must shrink it).
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
	w2.set_stock(&"wheat", 50.0)
	barn2.store.reserve_out(&"wheat", 40.0)         # 40 of it already claimed elsewhere
	var worker := w2.add_worker(Vector2i(11, 14), Worker.Look.MALE)
	var t := Task.new(Task.Kind.DELIVER, Vector2i(11, 14), 1.0, 0.0)
	t.fetch = &"wheat"
	t.fetch_amount = 50.0
	ok = _check("take_fetch only carries what take_goods actually gave",
		w2.take_fetch(t, worker) and worker.carry_amount == 10.0 and w2.total(&"wheat") == 40.0) and ok

	var w3 := World.new(64, 1)
	var barn3 := w3.add_building(&"storage_barn", Vector2i(10, 10), 0)
	w3.set_stock(&"wheelbarrow", 1.0)
	barn3.store.reserve_out(&"wheelbarrow", 1.0)    # the only wheelbarrow is already claimed elsewhere
	var worker2 := w3.add_worker(Vector2i(11, 14), Worker.Look.MALE)
	var t2 := Task.new(Task.Kind.HAUL, Vector2i(11, 14), 1.0, 0.0)
	t2.fetch = &"wheelbarrow"
	t2.fetch_amount = 1.0
	ok = _check("a claimed wheelbarrow is never also handed out",
		not w3.take_fetch(t2, worker2) and worker2.equipment == &"" and w3.total(&"wheelbarrow") == 1.0) and ok
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


func _claim_checks() -> bool:
	var ok := true
	var w := WorldGen.generate(256, 7)
	var a: Building = w.stores()[0]
	var b := _second_barn(w)
	ok = _check("a second barn gets its own store", b != null and w.stores().size() == 2 and b.store != null) and ok
	b.store.put(&"planks", 30.0)
	var t := Task.new(Task.Kind.DELIVER, b.access, 1.0, 0.0)
	t.fetch = &"planks"
	t.fetch_amount = 20.0
	var target: Variant = w.claim_fetch(t, a.access)
	ok = _check("a claim goes to the barn that has the goods", target == b.access and t.fetch_from == b.store
		and b.store.available(&"planks") == 10.0) and ok
	var t2 := Task.new(Task.Kind.DELIVER, b.access, 1.0, 0.0)
	t2.fetch = &"planks"
	t2.fetch_amount = 20.0
	w.claim_fetch(t2, a.access)
	ok = _check("claimed goods are not claimed twice", t2.fetch_reserved == 10.0) and ok
	w.release_fetch(t)
	w.release_fetch(t)
	ok = _check("releasing twice is harmless", b.store.available(&"planks") == 30.0 - t2.fetch_reserved) and ok
	w.tasks.add(t2)
	w.tasks.remove(t2)
	ok = _check("a removed task releases its claim", b.store.available(&"planks") == 30.0 and t2.fetch_from == null) and ok

	# a worker standing on barn B's access tile delivers into B
	var wk: Worker = w.workers[0]
	wk.pos = Vector2(b.access) + Vector2(0.5, 0.5)
	wk.carrying = &"wood"
	wk.carry_amount = 2.0
	w.deliver(wk)
	ok = _check("delivery goes into the barn the worker reached", b.store.amount(&"wood") == 2.0 and a.store.amount(&"wood") == 0.0) and ok

	# demolishing B moves its goods to A
	var before := w.total(&"planks") + w.total(&"wood")
	w.demolish(b)
	ok = _check("a demolished barn's goods move to the other barn", w.stores() == [a]
		and absf(a.store.amount(&"planks") + a.store.amount(&"wood") - before) < 0.001) and ok
	return ok


## Round-1 review fix: a task that has claimed goods in a barn, and a worker on the way to fetch
## them, must let go of both when the barn is removed — instead of duplicating the goods (the store
## was never actually emptied) or sending the worker to a barn that no longer exists.
func _removed_barn_checks() -> bool:
	var ok := true
	var w := WorldGen.generate(256, 7)
	var a: Building = w.stores()[0]
	var b := _second_barn(w)
	b.store.put(&"planks", 30.0)
	var before := w.total(&"planks")

	var t := Task.new(Task.Kind.DELIVER, b.access, 1.0, 0.0)
	t.fetch = &"planks"
	t.fetch_amount = 20.0
	w.tasks.add(t)
	w.claim_fetch(t, a.access)
	var worker: Worker = w.workers[0]
	t.worker = worker
	worker.task = t
	worker.phase = Worker.Phase.TO_FETCH
	worker.set_path([b.access])

	w.demolish(b)
	ok = _check("demolishing a claimed barn releases the claim", t.fetch_from == null) and ok
	ok = _check("demolishing a claimed barn frees its worker", t.worker == null and worker.task == null
		and worker.phase == Worker.Phase.IDLE) and ok
	ok = _check("demolishing a claimed barn neither loses nor duplicates its goods", w.total(&"planks") == before) and ok

	# the task is still queued and can be picked up again, now from the barn that holds the goods
	t.retry_at = 0.0
	worker.pos = Vector2(a.access) + Vector2(0.5, 0.5)
	var picked: Task = w.tasks.pick(w, worker)
	ok = _check("the released task is pickable again, from the barn that has the goods",
		picked == t and t.fetch_from == a.store) and ok
	return ok


## Round-1 review fix: every place that can take a worker off a claimed fetch must let go of the
## claim, so the goods stay available for someone else instead of sitting reserved forever.
func _release_checks() -> bool:
	var ok := true

	var w1 := World.new(64, 1)
	var barn1 := w1.add_building(&"storage_barn", Vector2i(10, 10), 0)
	barn1.store.put(&"wheat", 10.0)
	var worker1 := w1.add_worker(Vector2i(11, 14), Worker.Look.MALE)
	var t1 := Task.new(Task.Kind.DELIVER, Vector2i(11, 14), 1.0, 0.0)
	t1.fetch = &"wheat"
	t1.fetch_amount = 5.0
	t1.fetch_from = barn1.store
	t1.fetch_reserved = barn1.store.reserve_out(&"wheat", 0.5)   # less than fetch_min: the fetch must fail
	t1.worker = worker1
	worker1.task = t1
	worker1.phase = Worker.Phase.TO_FETCH
	worker1.set_path([])
	worker1.tick(w1, 0.1)
	ok = _check("a failed fetch releases its claim", t1.fetch_from == null and t1.worker == null
		and worker1.task == null and worker1.phase == Worker.Phase.IDLE) and ok

	var w2 := World.new(64, 1)
	var barn2 := w2.add_building(&"storage_barn", Vector2i(10, 10), 0)
	barn2.store.put(&"wheat", 10.0)
	var worker2 := w2.add_worker(Vector2i(11, 14), Worker.Look.MALE)
	var t2 := Task.new(Task.Kind.DELIVER, Vector2i(11, 14), 1.0, 0.0)
	t2.fetch = &"wheat"
	t2.fetch_amount = 5.0
	t2.fetch_from = barn2.store
	t2.fetch_reserved = barn2.store.reserve_out(&"wheat", 5.0)
	worker2.task = t2
	worker2.abort(w2)
	ok = _check("Worker.abort releases a held claim", t2.fetch_from == null
		and barn2.store.available(&"wheat") == 10.0) and ok

	var w3 := World.new(64, 1)
	var barn3 := w3.add_building(&"storage_barn", Vector2i(10, 10), 0)
	barn3.store.put(&"wheat", 10.0)
	var worker3 := w3.add_worker(Vector2i(11, 14), Worker.Look.MALE)
	var t3 := Task.new(Task.Kind.DELIVER, Vector2i(11, 14), 1.0, 0.0)
	t3.fetch = &"wheat"
	t3.fetch_amount = 5.0
	t3.fetch_from = barn3.store
	t3.fetch_reserved = barn3.store.reserve_out(&"wheat", 5.0)
	t3.worker = worker3
	worker3.task = t3
	worker3.phase = Worker.Phase.TO_FETCH
	w3.remove_worker()
	ok = _check("remove_worker releases a held claim", t3.fetch_from == null
		and barn3.store.available(&"wheat") == 10.0) and ok

	# a moved building's pile that _pile_spot thinks is walkable but is actually sealed off: pick's
	# own path.is_empty() check must still run release_fetch (a no-op here: a pile holds no claim)
	var w4 := World.new(64, 1)
	w4.add_building(&"storage_barn", Vector2i(10, 10), 0)
	var site := ConstructionSite.new(999, &"storage_barn", Vector2i(40, 40), 0)
	site.moved = true
	site.pile[&"planks"] = 20.0
	site.pile_cell = Vector2i(50, 50)
	for d in Defs.DIRS:
		w4.nav.set_solid(site.pile_cell + d, true)
	var worker4 := w4.add_worker(Vector2i(11, 14), Worker.Look.MALE)
	var t4 := Task.new(Task.Kind.DELIVER, site.pile_cell, 1.0, 0.0)
	t4.site = site
	t4.fetch = &"planks"
	t4.fetch_amount = 20.0
	w4.tasks.add(t4)
	var picked4: Task = w4.tasks.pick(w4, worker4)
	ok = _check("pick finds no path to a sealed-off pile and leaves nothing claimed",
		picked4 == null and t4.fetch_from == null and t4.worker == null) and ok
	return ok


func _check(what: String, cond: bool) -> bool:
	print("%s %s" % ["  ok " if cond else "FAIL", what])
	return cond
