extends SceneTree
## Checks of processing: a hand mill grinds wheat from the barn into flour, a sawmill saws logs into
## planks, auto-sell leaves the mills their raw goods, a water mill only fits on the river bank and
## needs planks carried to its site.
##   Godot --headless --path . --script scripts/tools/mill_test.gd


func _init() -> void:
	var w := WorldGen.generate(256, 7)
	w.money = 100000
	var ok := true
	var barn: Building = null
	for b: Building in w.buildings.values():
		if b.def_id == &"storage_barn":
			barn = b

	var mill := w.add_building(&"hand_mill", _free_spot(w, &"hand_mill", barn.access), 2)
	var saw := w.add_building(&"sawmill", _free_spot(w, &"sawmill", barn.access), 2)
	w.stock[&"wheat"] = 300.0
	w.stock[&"wood"] = 4.0
	ok = _check("auto-sell leaves the mill its wheat", w.sellable(&"wheat") == 100.0) and ok
	w.auto_sell[&"wheat"]["on"] = false
	w.auto_sell[&"flour"]["on"] = false
	w.auto_sell[&"wood"]["on"] = false
	var t := _run(w, 900.0, func() -> bool:
		return w.stock[&"wheat"] < 0.01 and mill.input < 0.01 and mill.output < 0.01 and w.stock[&"planks"] >= 12.0)
	var flour: float = w.stock[&"flour"]
	for wk in w.workers:
		if wk.carrying == &"flour":
			flour += wk.carry_amount
	ok = _check("all wheat ground into flour in the barn (%d s): %.1f kg" % [t, flour], absf(flour - 225.0) < 0.01) and ok
	ok = _check("logs sawn into planks: %d" % w.stock[&"planks"], w.stock[&"planks"] == 12.0 and w.stock[&"wood"] == 0.0) and ok
	ok = _check("nothing left in the mills", mill.process_task == null and saw.input == 0.0 and saw.output == 0.0) and ok
	ok = _check("planks are kept by default", not w.auto_sell[&"planks"]["on"]) and ok

	# a full mill stops: nobody carries flour away while transport is switched off
	w.set_category_on(Task.Category.TRANSPORT, false)
	mill.input = 260.0          # more than the output buffer can take
	_run(w, 600.0, func() -> bool: return false)
	ok = _check("a full mill halts (%s)" % w.process_status(mill), mill.output <= 150.0 + 0.01
		and mill.input > 0.0 and w.process_status(mill).begins_with("Halted")) and ok
	w.set_category_on(Task.Category.TRANSPORT, true)

	SaveGame.save(w, "mill_test")
	var w2 := SaveGame.load_world("mill_test")
	var m2: Building = w2.buildings.get(mill.id)
	ok = _check("mill contents survive a save", m2 != null and absf(m2.input - mill.input) < 0.01
		and absf(m2.output - mill.output) < 0.01) and ok

	# water mill: only with its wheel column on the river
	var spot := Vector2i(-1, -1)
	var spot_rot := 0
	var land := Vector2i(-1, -1)
	for y in range(Defs.BORDER, w.size - Defs.BORDER - 3):
		for x in range(Defs.BORDER, w.size - Defs.BORDER - 3):
			for r in 4:
				var a := Vector2i(x, y)
				if spot.x < 0 and w.can_place(&"water_mill", a, r):
					spot = a
					spot_rot = r
				if land.x < 0 and w.can_place(&"storage_barn", a, 0) and not w.is_water(a + Vector2i(3, 0)):
					land = a
	ok = _check("a river bank spot takes the water mill", spot.x >= 0 and w.river_side_ok(spot, Vector2i(3, 3), spot_rot)) and ok
	ok = _check("not on dry land", not w.can_place(&"water_mill", land, 0)) and ok
	ok = _check("not turned with the wheel away from the river", not w.can_place(&"water_mill", spot, (spot_rot + 2) % 4)) and ok
	var site := w.place_site(&"water_mill", spot, spot_rot)
	w.stock[&"planks"] = 0.0
	_run(w, 200.0, func() -> bool: return site.stage == ConstructionSite.Stage.DELIVERY)
	ok = _check("the site waits for planks", site.stage == ConstructionSite.Stage.DELIVERY
		and " ".join(w.alerts()).contains("Sawmill")) and ok
	w.stock[&"planks"] = 40.0
	t = _run(w, 1500.0, func() -> bool: return w.building_at(spot) != null and not (w.building_at(spot) is ConstructionSite))
	var wm := w.building_at(spot)
	ok = _check("workers brought planks and built the water mill (%d s)" % t, wm != null and wm.def_id == &"water_mill"
		and w.stock[&"planks"] < 0.01) and ok
	print("MILL TEST ", "OK" if ok else "FAILED")
	quit()


## A spot where the building fits, close to `near`.
func _free_spot(w: World, id: StringName, near: Vector2i) -> Vector2i:
	for r in range(3, 40):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var a := near + Vector2i(dx, dy)
				if w.can_place(id, a, 2) and not _trees(w, Rect2i(a, Defs.footprint(id, 2))) \
						and w.nav.find_path(near, Defs.access_cell(id, a, 2)).size() > 0:
					return a
	return near


func _trees(w: World, r: Rect2i) -> bool:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if w.has_tree(Vector2i(x, y)):
				return true
	return false


func _run(w: World, limit: float, done: Callable) -> float:
	var t := 0.0
	while t < limit and not done.call():
		w.tick(0.1)
		t += 0.1
	return t


func _check(what: String, cond: bool) -> bool:
	print("%s %s" % ["  ok " if cond else "FAIL", what])
	return cond
