extends SceneTree
## Checks of gravel roads: the site waits for gravel from the barn, workers carry it there and
## build; a dirt road (and a dirt bridge) is upgraded in place, never downgraded.
##   Godot --headless --path . --script scripts/tools/road_test.gd


func _init() -> void:
	var w := WorldGen.generate(256, 7)
	w.money = 100000
	var ok := true
	w.unlock(&"gravel_road")
	ok = _drive_cost(w) and ok
	ok = _collection_point(w) and ok

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

	w.set_stock(&"gravel", Defs.GRAVEL_PER_BLOCK)
	var t := _run(w, 600.0, func() -> bool: return w.road_blocks[dirt] == &"gravel")
	ok = _check("workers carried the gravel and built the road (%d s)" % t, w.road_blocks[dirt] == &"gravel"
		and w.road[w.idx(dirt)] == World.SURFACES.find(&"gravel")) and ok
	ok = _check("the gravel was used up", w.total(&"gravel") < 0.01) and ok
	ok = _check("gravel is faster than dirt", w.speed_factor(dirt) > Defs.ROAD_SPEED[&"dirt"]) and ok

	# a new gravel block next to the farm road, then cancelled: the gravel goes back to the barn
	w.set_stock(&"gravel", 1000.0)
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
		and absf(w.total(&"gravel") - 1000.0) < 0.01) and ok

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


## RoadNav.drive_cost: seconds along the block path, INF when not connected, the memo dropped when
## a block closes a gap. Uses a stretch of the road graph away from every road (removed afterwards).
func _drive_cost(w: World) -> bool:
	var ok := true
	var rn := w.road_nav
	var n := w.size / Defs.ROAD_BLOCK
	var start := Vector2i(-1, -1)
	for y in range(4, n - 4):
		for x in range(4, n - 10):
			if start.x >= 0:
				break
			var free := true
			for dy in range(-1, 2):
				for dx in range(-1, 7):
					if not rn.astar.is_point_solid(Vector2i(x + dx, y + dy)):
						free = false
			if free:
				start = Vector2i(x, y)
	var blocks: Array[Vector2i] = []
	for i in 6:
		blocks.append((start + Vector2i(i, 0)) * Defs.ROAD_BLOCK)
	for i in 6:
		if i != 3:
			rn.add_block(blocks[i])
	ok = _check("drive cost: no way across a gap", rn.drive_cost(blocks[0], blocks[5]) == INF) and ok
	ok = _check("drive cost: a block to itself is free", rn.drive_cost(blocks[1], blocks[1]) == 0.0) and ok
	rn.add_block(blocks[3])
	var want := 5.0 * Defs.ROAD_BLOCK / Defs.PICKUP_SPEED
	ok = _check("drive cost: 5 blocks along a straight road once the gap is closed (%.2f s)" % rn.drive_cost(blocks[0], blocks[5]),
		is_equal_approx(rn.drive_cost(blocks[0], blocks[5]), want)) and ok
	ok = _check("drive cost is the same both ways", is_equal_approx(rn.drive_cost(blocks[5], blocks[0]), want)) and ok
	for b in blocks:
		rn.remove_block(b)
	ok = _check("drive cost: INF again once the road is gone", rn.drive_cost(blocks[0], blocks[5]) == INF) and ok
	return ok


## A collection point goes only where its door is a built road tile; the placement ghost snaps to
## such a tile from 2 tiles away, not from 3. Uses a new road block in an empty stretch of land.
func _collection_point(w: World) -> bool:
	var ok := true
	w.unlock(&"collection_point")
	var a := Vector2i(-1, -1)
	for y in range(Defs.BORDER + 8, w.size - Defs.BORDER - 12, Defs.ROAD_BLOCK):
		for x in range(Defs.BORDER + 8, w.size - Defs.BORDER - 12, Defs.ROAD_BLOCK):
			if a.x < 0 and _clear(w, Rect2i(x - 7, y - 7, 16, 18)):
				a = Vector2i(x, y)
	if a.x < 0:
		return _check("collection point: an empty stretch of land", false)
	var t := a + Vector2i(0, 2)        # the tile below the block; its door (north) is the road tile a + (0, 1)
	ok = _check("collection point: not off the road", not w.can_place(&"collection_point", t, 0)) and ok
	w.add_road_block(a, &"dirt")
	ok = _check("collection point: not with its back to the road", not w.can_place(&"collection_point", t, 2)) and ok
	ok = _check("collection point: with its door on the road", w.can_place(&"collection_point", t, 0)) and ok
	var snap := w.road_snap(t + Vector2i(0, 2), 1)
	ok = _check("road snap from 2 tiles away: the touching tile (%s)" % snap, snap.get("anchor") == t and snap.get("rot") == 0
		and snap.get("edge") == a + Vector2i(0, 1) and w.road[w.idx(snap["edge"])] != 0) and ok
	ok = _check("road snap from 3 tiles away: nothing", w.road_snap(t + Vector2i(0, 3), 0).is_empty()) and ok
	w.road_blocks.erase(a)
	w.road_nav.remove_block(a)
	for dy in Defs.ROAD_BLOCK:
		for dx in Defs.ROAD_BLOCK:
			w.road[w.idx(a + Vector2i(dx, dy))] = 0
			w._refresh_nav(a + Vector2i(dx, dy))
	return ok


## No road, building, water or locked tile in `r`.
func _clear(w: World, r: Rect2i) -> bool:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			if not w.in_bounds(c) or w.is_locked(c) or w.is_water(c) or w.road[w.idx(c)] != 0 or w.occupant[w.idx(c)] != 0:
				return false
	return true


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
