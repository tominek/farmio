extends SceneTree
## Checks of the river rules: where bridges may be built, that water blocks walking except over a
## bridge, and that water survives a save.
##   Godot --headless --path . --script scripts/tools/river_test.gd


func _init() -> void:
	var w := WorldGen.generate(256, 7)
	w.money = 100000
	var ok := true
	var straight: Array[Vector2i] = []
	var bends: Array[Vector2i] = []
	for y in range(Defs.BORDER + 2, w.size - Defs.BORDER - 2, Defs.ROAD_BLOCK):
		for x in range(Defs.BORDER + 2, w.size - Defs.BORDER - 2, Defs.ROAD_BLOCK):
			var a := Vector2i(x, y)
			if w.water[w.idx(a)] != Defs.Water.RIVER or w.road_blocks.has(a):
				continue
			if w.river_axis(a) == -1:
				bends.append(a)
			elif w.bridge_ok(a):
				straight.append(a)
	ok = _check("straight river blocks that take a bridge", not straight.is_empty()) and ok
	ok = _check("no bridge on a bend", bends.all(func(a: Vector2i) -> bool: return not w.can_place(&"road_dirt", a, 0))) and ok

	var a: Vector2i = straight[straight.size() / 2]
	var axis := w.river_axis(a)
	var along := Vector2i(Defs.ROAD_BLOCK, 0) if axis == 0 else Vector2i(0, Defs.ROAD_BLOCK)
	var across := Vector2i(along.y, along.x)
	var bank_a := a - across + Vector2i(0, 0)
	var bank_b := a + across
	ok = _check("no path across the river before the bridge", w.nav.find_path(bank_a, bank_b).size() == 0
		or w.nav.find_path(bank_a, bank_b).size() > 20) and ok
	var money := w.money
	var site := w.place_site(&"road_dirt", a, 0)
	ok = _check("bridge site placed, costs road + bridge", site != null and money - w.money == Defs.BRIDGE_COST[&"dirt"]) and ok
	ok = _check("bridge takes longer to build", site != null and site.work_total == Defs.def(&"road_dirt")["build_work"] * Defs.BRIDGE_WORK) and ok
	# a pair of straight blocks next to each other along the flow: the second can't be bridged too
	var pair_found := false
	for s: Vector2i in straight:
		var ax := w.river_axis(s)
		var nx: Vector2i = s + (Vector2i(Defs.ROAD_BLOCK, 0) if ax == 0 else Vector2i(0, Defs.ROAD_BLOCK))
		if s != a and straight.has(nx) and nx != a:
			w.place_site(&"road_dirt", s, 0)
			ok = _check("no second bridge block along the river", not w.can_place(&"road_dirt", nx, 0)) and ok
			pair_found = true
			break
	ok = _check("found two straight blocks in a row to test", pair_found) and ok
	var t := 0.0
	while not w.road_blocks.has(a) and t < 900.0:
		w.tick(0.1)
		t += 0.1
	ok = _check("workers built the bridge (%d s)" % t, w.road_blocks.has(a) and w.is_bridge(a)) and ok
	var path := w.nav.find_path(bank_a, bank_b)
	ok = _check("workers cross over the bridge (%d steps)" % path.size(), path.size() > 0 and path.size() <= 6) and ok

	var pond := -1
	for i in w.water.size():
		if w.water[i] == Defs.Water.POND:
			pond = i
			break
	if pond >= 0:
		var c := Vector2i(pond % w.size, pond / w.size)
		ok = _check("nothing is built on a pond", not w.can_place(&"road_dirt", Vector2i(c.x & ~1, c.y & ~1), 0)
			and not w.can_place(&"storage_barn", c, 0)) and ok

	# wide curve: an L of road blocks on open land; nothing may be built on the inside block
	var spot := Vector2i(-1, -1)
	for y in range(Defs.BORDER + 10, w.size - Defs.BORDER - 20, 2):
		for x in range(Defs.BORDER + 10, w.size - Defs.BORDER - 20, 2):
			var free := true
			for dy in 8:
				for dx in 8:
					var c := Vector2i(x + dx, y + dy)
					if w.has_tree(c) or w.is_water(c) or w.occupant[w.idx(c)] != 0 or w.road[w.idx(c)] != 0:
						free = false
			if free and spot.x < 0:
				spot = Vector2i(x, y)
	if spot.x >= 0:
		# elbow at spot+(2,2), straight blocks south (spot+(2,4)) and east (spot+(4,2)), inside spot+(4,4)
		for b in [spot + Vector2i(2, 2), spot + Vector2i(2, 4), spot + Vector2i(2, 6), spot + Vector2i(4, 2), spot + Vector2i(6, 2)]:
			w.add_road_block(b, &"dirt")
		ok = _check("an L of roads becomes a wide curve", w.wide_curves().has(spot + Vector2i(2, 2))) and ok
		# a vehicle drives the arc, not the corner of the elbow block
		var centre := Vector2(spot + Vector2i(6, 6))
		var on_arc := 0
		var off := false
		var r := PackedVector2Array()
		# through the curve, and starting / ending inside it (in the swallowed blocks or the elbow)
		for ends in [[Vector2i(2, 6), Vector2i(6, 2)], [Vector2i(2, 4), Vector2i(6, 2)], [Vector2i(2, 6), Vector2i(4, 2)],
				[Vector2i(2, 2), Vector2i(6, 2)], [Vector2i(4, 2), Vector2i(2, 6)]]:
			r.append_array(w.road_nav.route(spot + ends[0], spot + ends[1]))
		for p in r:
			var dist := p.distance_to(centre)
			if p.x > centre.x - 4.01 and p.y > centre.y - 4.01 and p.x < centre.x and p.y < centre.y:
				if absf(dist - 3.0) <= 0.51:
					on_arc += 1
				else:
					off = true
		ok = _check("vehicles follow the wide arc (%d points)" % on_arc, on_arc >= 20 and not off) and ok
		ok = _check("nothing can be built inside the wide curve",
			not w.can_place(&"storage_barn", spot + Vector2i(4, 4), 0) and w.in_curve(spot + Vector2i(4, 4))
			and not w.in_curve(spot + Vector2i(5, 5))) and ok
		ok = _check("a road can still be built there", w.can_place(&"road_dirt", spot + Vector2i(4, 4), 0)) and ok
		# the outer tile of the elbow block is grass: a barn (4x3) whose corner covers only it fits
		var corner := spot + Vector2i(2, 2)
		ok = _check("the elbow's outer corner is free", w.curve_free(corner) and not w.curve_free(corner + Vector2i(1, 1))) and ok
		var barn_at := corner - Vector2i(3, 2)
		ok = _check("a barn may cover the free corner", w.can_place(&"storage_barn", barn_at, 0)) and ok
		ok = _check("but not a road tile of the curve", not w.can_place(&"storage_barn", barn_at + Vector2i(1, 1), 0)) and ok
		var barn := w.place_site(&"storage_barn", barn_at, 0)
		ok = _check("with it there, the curve can't be undone", barn != null and not w.can_place(&"road_dirt", spot + Vector2i(4, 4), 0)
			and w.road_blocker(spot + Vector2i(2, 4)) != "") and ok
	else:
		ok = _check("found open land for the curve test", false) and ok

	SaveGame.save(w, "river_test")
	var w2 := SaveGame.load_world("river_test")
	ok = _check("water survives a save", w2 != null and w2.water == w.water and w2.is_bridge(a)) and ok

	# the river runs well away from the farm, but within reach (nearest river tile to the barn)
	var dists: Array[int] = []
	for s in [1, 3, 7, 11, 42, 99, 123, 500, 2024, 31337]:
		var wm := WorldGen.generate(256, s)
		var barn := Vector2i.ZERO
		for b: Building in wm.buildings.values():
			if b.def_id == &"storage_barn":
				barn = b.anchor
		var near := INF
		for i in wm.water.size():
			if wm.water[i] == Defs.Water.RIVER:
				near = minf(near, Vector2(barn).distance_to(Vector2(i % wm.size, i / wm.size)))
		dists.append(roundi(near))
	print("  river distances from the barn: ", dists)
	ok = _check("the river is 45-90 tiles from the farm on every seed",
		dists.all(func(d: int) -> bool: return d >= 45 and d <= 90)) and ok
	print("RIVER TEST ", "OK" if ok else "FAILED")
	quit()


func _check(what: String, cond: bool) -> bool:
	print("%s %s" % ["  ok " if cond else "FAIL", what])
	return cond
