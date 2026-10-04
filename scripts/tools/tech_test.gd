extends SceneTree
## Checks of the research tree: what is available from the start, unlock rules, buildings paid in
## planks (carried to the site, returned on demolition) and mill upgrades.
##   Godot --headless --path . --script scripts/tools/tech_test.gd


func _init() -> void:
	var w := WorldGen.generate(256, 7)
	var ok := true
	var barn: Building = null
	for b: Building in w.buildings.values():
		if b.def_id == &"storage_barn":
			barn = b

	# start: barn, garage, fields, dirt road; the rest is locked
	var spot := _free_spot(w, &"garage", barn.access)
	ok = _check("a garage can be placed from the start", w.can_place(&"garage", spot, 2)) and ok
	for id in [&"hand_mill", &"sawmill", &"water_mill", &"road_gravel"]:
		ok = _check("%s is locked at the start" % id, not w.building_unlocked(id)) and ok
	ok = _check("no wheelbarrows or gravel at the Dealer yet", not w.order(&"wheelbarrow", 1) and not w.order(&"gravel", 50)) and ok
	ok = _check("planks can be bought", w.item_unlocked(&"planks")) and ok

	# unlocking
	w.money = 100
	ok = _check("no unlock without the money", not w.unlock(&"hand_mill") and not w.is_unlocked(&"hand_mill")) and ok
	w.money = 10000
	ok = _check("no Water Mill before both mills", not w.unlock(&"water_mill")) and ok
	ok = _check("Hand Mill unlocked for its price", w.unlock(&"hand_mill") and w.money == 10000 - 300
		and w.building_unlocked(&"hand_mill")) and ok
	ok = _check("only once", not w.unlock(&"hand_mill") and w.money == 9700) and ok
	ok = _check("still no Water Mill without the Sawmill", not w.can_unlock(&"water_mill")) and ok
	w.unlock(&"sawmill")
	ok = _check("Water Mill after both", w.unlock(&"water_mill")) and ok
	ok = _check("coming-later nodes are never unlocked", not w.unlock(&"bakery") and not w.can_unlock(&"chicken_coop")) and ok
	ok = _check("research is booked", w.ledger.get("research", 0) == -2100) and ok

	# a garage is paid in planks: the site waits for them, workers carry them, demolition returns them
	var money := w.money
	var site := w.place_site(&"garage", spot, 2)
	ok = _check("the garage costs no quacks", site != null and w.money == money) and ok
	_run(w, 300.0, func() -> bool: return site.stage == ConstructionSite.Stage.DELIVERY)
	ok = _check("its site waits for planks", site.stage == ConstructionSite.Stage.DELIVERY
		and " ".join(w.alerts()).contains("Planks")) and ok
	w.set_stock(&"planks", 100.0)
	var t := _run(w, 1200.0, func() -> bool: return w.building_at(spot) != null and not (w.building_at(spot) is ConstructionSite))
	var garage := w.building_at(spot)
	ok = _check("workers brought 80 planks and built it (%d s)" % t, garage != null and garage.def_id == &"garage"
		and absf(w.total(&"planks") - 20.0) < 0.01 and garage.materials.get(&"planks", 0.0) == 80.0) and ok
	w.demolish(garage)
	ok = _check("demolishing returns the planks", absf(w.total(&"planks") - 100.0) < 0.01) and ok

	# mill upgrade
	var mill := w.add_building(&"hand_mill", _free_spot(w, &"hand_mill", barn.access), 2)
	ok = _check("no upgrade before Mill gear II", w.upgrade_blocker(mill).contains("Mill gear II")
		and w.start_upgrade(mill) == null) and ok
	w.unlock(&"mill_gear_2")
	ok = _check("Mill gear II allows level 2, not 3", w.max_level(&"hand_mill") == 2 and w.max_level(&"water_mill") == 2
		and w.max_level(&"sawmill") == 1) and ok
	mill.input = 100.0
	w.auto_sell[&"wheat"]["on"] = false
	w.set_stock(&"planks", 0.0)
	var up := w.start_upgrade(mill)
	ok = _check("the upgrade waits for planks and takes no tiles", up != null and up.stage == ConstructionSite.Stage.DELIVERY
		and w.building_at(mill.anchor) == mill and mill.upgrading == up) and ok
	_run(w, 60.0, func() -> bool: return false)
	ok = _check("the mill does not work while upgrading", mill.input == 100.0 and mill.process_task == null
		and w.process_status(mill).begins_with("Upgrading")) and ok
	ok = _check("a second upgrade is refused", w.start_upgrade(mill) == null) and ok

	SaveGame.save(w, "tech_test")
	var w2 := SaveGame.load_world("tech_test")
	var m2: Building = w2.buildings.get(mill.id)
	ok = _check("a save keeps unlocks and the running upgrade", w2 != null and w2.is_unlocked(&"mill_gear_2")
		and m2 != null and m2.upgrading != null and m2.upgrading.upgrade_of == m2 and w2.building_at(mill.anchor) == m2) and ok

	w.set_stock(&"planks", 50.0)
	t = _run(w, 900.0, func() -> bool: return mill.level == 2)
	ok = _check("workers brought 50 planks and upgraded it (%d s)" % t, mill.level == 2 and mill.upgrading == null
		and mill.materials.get(&"planks", 0.0) == 50.0) and ok
	var base: Dictionary = Defs.def(&"hand_mill")["process"]
	ok = _check("level 2 grinds faster and holds more", absf(mill.recipe()["work"] - base["work"] * 0.6) < 0.01
		and absf(mill.recipe()["in_cap"] - base["in_cap"] * 1.5) < 0.01) and ok
	ok = _check("level 3 needs Mill gear III", w.upgrade_blocker(mill).contains("Mill gear III")) and ok

	# a cancelled upgrade returns its planks
	w.unlock(&"mill_gear_3")
	w.set_stock(&"planks", 100.0)
	up = w.start_upgrade(mill)
	_run(w, 120.0, func() -> bool: return up.delivered.get(&"planks", 0.0) >= 10.0)
	w.demolish(up)
	_run(w, 60.0, func() -> bool: return false)
	ok = _check("cancelling an upgrade returns the planks", absf(w.total(&"planks") - 100.0) < 0.01
		and mill.upgrading == null and mill.level == 2) and ok

	# developer cheats (F12): everything unlocked, sites free and done at once
	var wc := WorldGen.generate(256, 7)
	wc.unlock_all()
	ok = _check("unlock all: every existing node, none of the later ones",
		Tech.NODES.keys().all(func(id: StringName) -> bool: return wc.is_unlocked(id) != Tech.is_later(id))) and ok
	wc.instant_build = true
	wc.money = 0
	wc.set_stock(&"planks", 0.0)
	var placed: Building = null
	for y in range(Defs.BORDER, wc.size - Defs.BORDER - 4):
		for x in range(Defs.BORDER, wc.size - Defs.BORDER - 4):
			if placed == null and wc.can_place(&"sawmill", Vector2i(x, y), 0):
				wc.place_site(&"sawmill", Vector2i(x, y), 0)
				placed = wc.building_at(Vector2i(x, y))
	ok = _check("instant build: a sawmill stands at once with no money or planks",
		placed != null and not (placed is ConstructionSite) and placed.def_id == &"sawmill" and wc.money == 0) and ok
	if placed:
		wc.start_upgrade(placed)
	ok = _check("instant build: upgrades finish at once", placed != null and placed.level == 2 and placed.upgrading == null) and ok
	print("TECH TEST ", "OK" if ok else "FAILED")
	quit()


## A spot without trees where the building fits, reachable from `near`.
func _free_spot(w: World, id: StringName, near: Vector2i) -> Vector2i:
	for r in range(3, 40):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var a := near + Vector2i(dx, dy)
				var rect := Rect2i(a, Defs.footprint(id, 2))
				if w.can_place(id, a, 2) and not _trees(w, rect.grow(1)) and _free(w, rect.grow(1)) \
						and w.nav.find_path(near, Defs.access_cell(id, a, 2)).size() > 0:
					return a
	return near


func _trees(w: World, r: Rect2i) -> bool:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if w.has_tree(Vector2i(x, y)):
				return true
	return false


func _free(w: World, r: Rect2i) -> bool:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if w.occupant[w.idx(Vector2i(x, y))] != 0:
				return false
	return true


func _run(w: World, limit: float, done: Callable) -> float:
	var t := 0.0
	while t < limit and not done.call():
		w.tick(0.1)
		t += 0.1
	return t


func _check(what: String, cond: bool) -> bool:
	print("%s %s" % ["  ok " if cond else "FAIL", what])
	return cond
