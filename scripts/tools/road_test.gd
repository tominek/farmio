extends SceneTree
## Checks of gravel roads: the site waits for gravel from the barn, workers carry it there and
## build; a dirt road (and a dirt bridge) is upgraded in place, never downgraded.
##   Godot --headless --path . --script scripts/tools/road_test.gd


func _init() -> void:
	var w := WorldGen.generate(256, 7)
	w.money = 100000
	var ok := true
	w.unlock(&"gravel_road")

	# a dirt block of the start road near the barn
	var barn: Building = null
	for b: Building in w.buildings.values():
		if Defs.def(b.def_id).get("storage", false):
			barn = b
	var dirt := Vector2i(-1, -1)
	var best := INF
	for a: Vector2i in w.road_blocks:
		var d := Vector2(a).distance_squared_to(barn.access)
		if not w.is_bridge(a) and d < best:
			best = d
			dirt = a
	ok = _check("dirt can't be placed over a built road", not w.can_place(&"road_dirt", dirt, 0)) and ok
	ok = _check("gravel can be placed over dirt", w.can_place(&"road_gravel", dirt, 0)) and ok
	var site := w.place_site(&"road_gravel", dirt, 0)
	ok = _check("the upgrade waits for gravel", site != null and site.stage == ConstructionSite.Stage.DELIVERY
		and w.road_blocks[dirt] == &"dirt") and ok
	ok = _check("the road stays usable meanwhile", w.road_blocks.has(dirt) and not w.nav.is_solid(dirt)) and ok
	ok = _check("no second upgrade on the same block", not w.can_place(&"road_gravel", dirt, 0)) and ok
	ok = _check("the road can't be demolished under its upgrade", w.road_blocker(dirt) != "") and ok
	_run(w, 30.0, func() -> bool: return false)
	ok = _check("without gravel nothing is carried", site.delivered.is_empty()) and ok
	ok = _check("an alert asks for gravel", " ".join(w.alerts()).contains("Gravel")) and ok

	w.stock[&"gravel"] = Defs.GRAVEL_PER_BLOCK
	var t := _run(w, 600.0, func() -> bool: return w.road_blocks[dirt] == &"gravel")
	ok = _check("workers carried the gravel and built the road (%d s)" % t, w.road_blocks[dirt] == &"gravel"
		and w.road[w.idx(dirt)] == World.SURFACES.find(&"gravel")) and ok
	ok = _check("the gravel was used up", w.stock[&"gravel"] < 0.01) and ok
	ok = _check("gravel is faster than dirt", w.speed_factor(dirt) > Defs.ROAD_SPEED[&"dirt"]) and ok

	# a new gravel block next to the farm road, then cancelled: the gravel goes back to the barn
	w.stock[&"gravel"] = 1000.0
	var spot := Vector2i(-1, -1)
	for a: Vector2i in w.road_blocks:
		for dir in Defs.DIRS:
			var n: Vector2i = a + dir * Defs.ROAD_BLOCK
			if spot.x < 0 and w.can_place(&"road_gravel", n, 0) and not w.has_tree(n) and not w.has_tree(n + Vector2i.ONE):
				spot = n
	var site2 := w.place_site(&"road_gravel", spot, 0)
	_run(w, 120.0, func() -> bool: return site2.delivered.get(&"gravel", 0.0) >= Defs.CARRY_CAPACITY)
	var brought: float = site2.delivered.get(&"gravel", 0.0)
	var in_hands := 0.0
	for wk in w.workers:
		if wk.carrying == &"gravel":
			in_hands += wk.carry_amount
	w.demolish(site2)
	_run(w, 60.0, func() -> bool: return false)
	ok = _check("cancelled site returns its gravel (%d kg brought)" % brought, brought > 0.0
		and absf(w.stock[&"gravel"] - 1000.0) < 0.01) and ok

	# a dirt bridge is upgraded for the price difference
	var bridge := Vector2i(-1, -1)
	for y in range(Defs.BORDER + 2, w.size - Defs.BORDER - 2, Defs.ROAD_BLOCK):
		for x in range(Defs.BORDER + 2, w.size - Defs.BORDER - 2, Defs.ROAD_BLOCK):
			if bridge.x < 0 and w.bridge_ok(Vector2i(x, y)) and not w.road_blocks.has(Vector2i(x, y)):
				bridge = Vector2i(x, y)
	w.add_road_block(bridge, &"dirt")
	ok = _check("gravel over a dirt bridge pays the difference",
		w.cost_of(&"road_gravel", Vector2i.ZERO, bridge) == Defs.BRIDGE_COST[&"gravel"] - Defs.BRIDGE_COST[&"dirt"]) and ok
	var money := w.money
	var site3 := w.place_site(&"road_gravel", bridge, 0)
	ok = _check("bridge upgrade placed", site3 != null and money - w.money == Defs.BRIDGE_COST[&"gravel"] - Defs.BRIDGE_COST[&"dirt"]) and ok

	SaveGame.save(w, "road_test")
	var w2 := SaveGame.load_world("road_test")
	var s2: ConstructionSite = w2.building_at(bridge) as ConstructionSite
	ok = _check("a site's gravel survives a save", s2 != null and s2.stage == site3.stage
		and s2.delivered == site3.delivered) and ok
	print("ROAD TEST ", "OK" if ok else "FAILED")
	quit()


## Ticks the world until `done` holds or `limit` seconds pass; returns the time taken.
func _run(w: World, limit: float, done: Callable) -> float:
	var t := 0.0
	while t < limit and not done.call():
		w.tick(0.1)
		t += 0.1
	return t


func _check(what: String, cond: bool) -> bool:
	print("%s %s" % ["  ok " if cond else "FAIL", what])
	return cond
