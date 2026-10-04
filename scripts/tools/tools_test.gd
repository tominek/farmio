extends SceneTree
## Checks of the dock tools: marking trees for felling (Felling tasks, logs to the barn, saved),
## moving a building (taken down, materials carried from the old spot to the new site, level and
## priority kept, cancel cases, blockers, the pickup hauling on longer moves, a garage with its
## pickup), the demolish / cut / move modes of the PlacementTool, moving a field's gate and
## worker names.
##   Godot --headless --path . --script scripts/tools/tools_test.gd

var ok := true


func _initialize() -> void:
	var w := WorldGen.generate(256, 7)
	w.money = 100000
	for id in [&"hand_mill", &"sawmill"]:
		w.unlock(id)
	for res in w.auto_sell:
		w.auto_sell[res]["on"] = false
	var barn: Building = _first(w, &"storage_barn")
	_felling(w, barn)
	_moving(w, barn)
	_garage(w, barn)
	_pickup_haul(w, barn)
	_field_gate(w, barn)
	_tool_api(w, barn)
	_names(w)
	print("TOOLS TEST ", "OK" if ok else "FAILED")
	quit()


# --- felling -------------------------------------------------------------------

func _felling(w: World, barn: Building) -> void:
	var r := _tree_rect(w, barn.access, 3)
	var want := w.trees_to_mark(r).size()
	var n := w.mark_trees(r)
	_check("marked %d trees in %s" % [n, r], n == want and n >= 3 and w.marked.size() == n)
	var felling := w.tasks.tasks.filter(func(t: Task) -> bool: return t.category == Task.Category.FELLING)
	_check("one Felling task per marked tree", felling.size() == n and w.category_counts()[Task.Category.FELLING][0] == n)
	_check("Felling comes after Construction by default",
		Task.DEFAULT_ORDER.find(Task.Category.FELLING) == Task.DEFAULT_ORDER.find(Task.Category.CONSTRUCTION) + 1
		and Task.CATEGORY_NAMES[Task.Category.FELLING][0] == "Felling")
	_check("marking again changes nothing", w.mark_trees(r) == 0)
	_check("the locked border forest can't be marked", w.mark_trees(Rect2i(0, 0, Defs.BORDER, Defs.BORDER)) == 0)

	# unmark one tree: its task is gone
	var c: Vector2i = w.marked.keys()[0]
	_check("unmarking removes the waiting task", w.unmark_trees(Rect2i(c, Vector2i.ONE)) == 1
		and not w.marked.has(c) and w.tasks.tasks.filter(func(t: Task) -> bool: return t.category == Task.Category.FELLING).size() == n - 1)
	n -= 1

	# a site placed over a marked tree takes the felling task over
	var r2 := _tree_rect(w, barn.access + Vector2i(0, 12), 1)
	w.mark_trees(r2)
	var t0: Vector2i = w.trees_to_mark(r2, true)[0]
	var spot := Vector2i(-1, -1)
	for dy in range(-1, 1):
		for dx in range(-1, 1):
			if spot.x < 0 and w.can_place(&"hand_mill", t0 + Vector2i(dx, dy), 2):
				spot = t0 + Vector2i(dx, dy)
	if spot.x >= 0:
		var site := w.place_site(&"hand_mill", spot, 2)
		var taken := site.open_tasks.filter(func(t: Task) -> bool: return t.cell == t0)
		_check("a site over a marked tree clears it with the felling task", not w.marked.has(t0) and taken.size() == 1
			and taken[0].category == Task.Category.CONSTRUCTION)
		w.demolish(site)
	w.unmark_trees(r2)
	_check("unmarked the second patch", w.marked.size() == n)

	# saved and loaded
	SaveGame.save(w, "tools_test")
	var w2 := SaveGame.load_world("tools_test")
	_check("marks survive a save (%d)" % w2.marked.size(), w2.marked.size() == n
		and w2.marked.values().all(func(t: Task) -> bool: return t.category == Task.Category.FELLING and w2.tasks.tasks.has(t)))

	# the workers chop them and carry the logs to the barn
	var wood: float = w.stock[&"wood"]
	var cells: Array = w.marked.keys()
	var t := _run(w, 900.0, func() -> bool: return w.marked.is_empty() and _carried(w, &"wood") == 0.0)
	_check("marked trees felled and %d logs in the barn (%d s)" % [w.stock[&"wood"] - wood, t],
		w.marked.is_empty() and w.stock[&"wood"] - wood == n * Defs.WOOD_PER_TREE
		and cells.all(func(x: Vector2i) -> bool: return not w.has_tree(x)))


# --- moving a building -----------------------------------------------------------

func _moving(w: World, barn: Building) -> void:
	var mill := w.add_building(&"hand_mill", _free_spot(w, &"hand_mill", barn.access, 2), 2)
	mill.level = 2
	mill.materials = {&"planks": 80.0}      # 30 to build + 50 for level 2
	mill.priority = 1
	mill.input = 100.0
	mill.output = 30.0

	# blockers
	_check("the Dealer can't be moved", w.move_blocker(w.dealer()) != "")
	_check("the only barn can't be moved", w.move_blocker(barn) != "")
	var f := w.add_field(_free_spot(w, &"field", barn.access + Vector2i(0, 10), 2), 2, Vector2i(4, 4), &"wheat")
	_check("fields can't be moved", w.move_blocker(f) != "")
	w.demolish(f)
	var site0 := w.place_site(&"sawmill", _free_spot(w, &"sawmill", barn.access, 2), 2)
	_check("sites can't be moved", w.move_blocker(site0) != "")
	w.demolish(site0)
	_check("the mill can", w.move_blocker(mill) == "")
	_check("not onto its own spot", not w.can_move(mill, mill.anchor, mill.rot))

	var money := w.money
	var planks: float = w.stock[&"planks"]
	var wheat: float = w.stock[&"wheat"]
	var flour: float = w.stock[&"flour"]
	var old_anchor := mill.anchor
	var to := _free_spot(w, &"hand_mill", barn.access + Vector2i(6, 0), 1)

	# cancel before the old one is down: the building comes back as it was
	var site := w.move_building(mill, to, 1)
	var old := w.building_at(old_anchor) as ConstructionSite
	_check("moving: a dismantle site on the old spot, the new site needs its materials", site != null and old != null
		and old.dismantle and old.partner == site and site.moved and site.needs == {&"planks": 80.0} and site.level == 2)
	_check("the mill's goods went to the barn", w.stock[&"wheat"] - wheat == 100.0 and w.stock[&"flour"] - flour == 30.0)
	_check("moving costs nothing", w.money == money)
	w.demolish(site)
	var back := w.building_at(old_anchor)
	_check("cancelling the new site puts the building back", back != null and not (back is ConstructionSite)
		and back.level == 2 and back.priority == 1 and back.materials == {&"planks": 80.0} and w.building_at(to) == null)
	site = w.move_building(back, to, 1)
	w.demolish(w.building_at(old_anchor))
	back = w.building_at(old_anchor)
	_check("cancelling the dismantle site does too", back != null and not (back is ConstructionSite) and back.level == 2
		and w.building_at(to) == null and w.stock[&"planks"] == planks)

	# the full move
	site = w.move_building(back, to, 1)
	var t := _run(w, 600.0, func() -> bool: return site.partner == null)
	_check("the old building is down (%d s), its materials lie at the old spot" % t, w.building_at(old_anchor) == null
		and site.pile == {&"planks": 80.0} and site.pile_cell.x >= 0 and w.stock[&"planks"] == planks)
	SaveGame.save(w, "tools_test")
	var w2 := SaveGame.load_world("tools_test")
	var s2 := w2.buildings.get(site.id) as ConstructionSite
	_check("a move survives a save", s2 != null and s2.moved and s2.level == 2 and s2.pile == site.pile
		and s2.pile_cell == site.pile_cell and s2.needs == site.needs)
	var from_barn := [0, 0]     # [fetches from elsewhere, fetches from the pile]
	t = _run(w, 900.0, func() -> bool:
		for wk in w.workers:
			if wk.task and wk.task.kind == Task.Kind.DELIVER and wk.task.site == site and wk.phase == Worker.Phase.TO_FETCH \
					and wk.path.size() > 0:
				from_barn[0 if wk.path[-1] != site.pile_cell else 1] += 1
		var b := w.building_at(to)
		return b != null and not (b is ConstructionSite))
	var moved := w.building_at(to)
	_check("moved and rebuilt (%d s): level %d, priority %d" % [t, moved.level if moved else 0, moved.priority if moved else 0],
		moved != null and moved.def_id == &"hand_mill" and moved.level == 2 and moved.priority == 1
		and moved.materials == {&"planks": 80.0} and moved.rot == 1)
	_check("the planks came from the old spot, not the barn", w.stock[&"planks"] == planks and site.pile.is_empty() and from_barn[0] == 0 and from_barn[1] > 0)
	_check("still free", w.money == money)

	# cancel after the old one is down: like a normal site, the materials go to the barn
	var to2 := _free_spot(w, &"hand_mill", barn.access + Vector2i(-6, 4), 2)
	site = w.move_building(moved, to2, 2)
	_run(w, 600.0, func() -> bool: return site.partner == null)
	_run(w, 20.0, func() -> bool: return false)      # some planks on their way / at the site
	w.demolish(site)
	_run(w, 60.0, func() -> bool: return _carried(w, &"planks") == 0.0)
	_check("cancelled after the old one is down: %d planks back in the barn" % (w.stock[&"planks"] - planks),
		w.stock[&"planks"] - planks == 80.0 and w.building_at(to2) == null)

	# a storage barn can move when there is another one
	var barn2 := w.add_building(&"storage_barn", _free_spot(w, &"storage_barn", barn.access + Vector2i(0, 8), 2), 2)
	_check("a barn can move when there is another", w.move_blocker(barn) == "" and w.move_blocker(barn2) == "")
	w.demolish(barn2)


func _garage(w: World, barn: Building) -> void:
	var garage := _first(w, &"garage")
	var v := w.vehicles[0]
	v.parked = false
	_check("the garage waits for its pickup", w.move_blocker(garage) != "")
	v.parked = true
	var spot := _road_spot(w, &"garage", garage.access + Vector2i(0, 12), 0)
	var to: Vector2i = spot[0]
	var site := w.move_building(garage, to, spot[1])
	_check("moving the garage: the pickup stays, no trips meanwhile", site != null and v.garage is ConstructionSite and v.parked)
	w.orders[&"seed_wheat"] = 10.0
	var t := _run(w, 900.0, func() -> bool:
		return not (v.garage is ConstructionSite))
	_check("the garage is rebuilt (%d s), the pickup belongs to it" % t, v.garage == w.building_at(to) and v.parked
		and v.pos.distance_to(Vector2(to) + Vector2(v.garage.size) * 0.5) < 2.0)
	t = _run(w, 600.0, func() -> bool: return w.orders.is_empty() and v.parked)
	_check("and drives from there again (%d s)" % t, w.orders.is_empty())


func _pickup_haul(w: World, barn: Building) -> void:
	# a mill by the road, moved to a spot by the road far away
	var a: Array = _road_spot(w, &"hand_mill", barn.access, 0)
	var mill := w.add_building(&"hand_mill", a[0], a[1])
	mill.materials = {&"planks": 30.0}
	var b: Array = _road_spot(w, &"hand_mill", mill.access, Defs.MOVE_PICKUP_WALK + 10)
	var far: Vector2i = b[0]
	var site := w.move_building(mill, far, b[1])
	_run(w, 600.0, func() -> bool: return site.partner == null)
	_check("a longer move along the road: the pickup hauls the pile", site.by_pickup)
	var saw := [false]          # lambdas capture by value: a shared array
	var t := _run(w, 1200.0, func() -> bool:
		saw[0] = saw[0] or w.trip_status == "Loading building materials at the old spot"
		var x := w.building_at(far)
		return x != null and not (x is ConstructionSite))
	_check("the pickup brought the planks and the mill stands (%d s)" % t, saw[0] and site.pile.is_empty()
		and w.building_at(far) != null and not (w.building_at(far) is ConstructionSite))
	w.demolish(w.building_at(far))


## [anchor, rotation] of a spot for the building with its access next to a road block the pickup
## can reach, at least `min_walk` tiles of walking from `near`, the nearest such spot.
func _road_spot(w: World, id: StringName, near: Vector2i, min_walk: int) -> Array:
	var v := w.vehicles[0]
	var anchors: Array = w.road_blocks.keys()
	anchors.sort_custom(func(p: Vector2i, q: Vector2i) -> bool:
		return Vector2(p).distance_squared_to(near) < Vector2(q).distance_squared_to(near))
	for blk: Vector2i in anchors:
		for y in range(-1, 3):
			for x in range(-1, 3):
				var acc := blk + Vector2i(x, y)
				if Rect2i(blk, Vector2i(2, 2)).has_point(acc) or w.nav.is_solid(acc):
					continue
				for r in 4:
					var spot := acc - Defs.access_cell(id, Vector2i.ZERO, r)
					if not w.can_place(id, spot, r) or _trees(w, Rect2i(spot - Vector2i.ONE, Defs.footprint(id, r) + Vector2i(2, 2))):
						continue
					var bn: Variant = w.road_nav.block_near(acc)
					if bn == null or w.road_nav.route(v.block, bn).is_empty():
						continue
					if min_walk > 0 and w.nav.find_path(near, acc).size() <= min_walk:
						continue
					return [spot, r]
	_check("a spot by the road for the %s" % id, false)
	return [near, 0]


# --- field gate ------------------------------------------------------------------

func _field_gate(w: World, barn: Building) -> void:
	var spot := _free_spot(w, &"field", barn.access + Vector2i(10, 10), 2)
	var f := w.add_field(spot, 2, Vector2i(5, 4), &"wheat")
	var size := f.size
	f.pile = 120.0
	w._queue_hauls(f, true)
	_check("gate on side 2 at first", f.access == Defs.access_for(f.base_size, f.anchor, 2))
	var side := -1
	for s in [1, 3, 0]:
		if side < 0 and w.field_gate_ok(f, s):
			side = s
	_check("a free side for the gate (%d)" % side, side >= 0 and w.set_field_gate(f, side))
	var hauls := w.tasks.tasks.filter(func(t: Task) -> bool: return t.kind == Task.Kind.HAUL and t.field == f)
	_check("the gate moved, the field kept its tiles, the carry tasks go to the new gate", f.rot == side and f.size == size
		and f.access == w.field_gate_cell(f, side) and not f.rect().has_point(f.access) and hauls.size() > 0
		and hauls.all(func(t: Task) -> bool: return t.cell == f.access))
	# a building in front of a side blocks it
	var other := (side + 2) % 4
	var cell := w.field_gate_cell(f, other)
	var blocker := w.add_building(&"hand_mill", cell, 0) if w.can_place(&"hand_mill", cell, 0) else null
	if blocker:
		_check("a blocked side is refused", not w.field_gate_ok(f, other) and not w.set_field_gate(f, other) and f.rot == side)
		w.demolish(blocker)
	SaveGame.save(w, "tools_test")
	var f2 := SaveGame.load_world("tools_test").buildings.get(f.id) as Field
	_check("the gate is saved", f2 != null and f2.rot == side and f2.access == f.access and f2.size == size)
	_run(w, 300.0, func() -> bool: return f.pile < 0.01 and _carried(w, &"wheat") == 0.0)
	_check("the pile was carried from the new gate", f.pile < 0.01)
	w.demolish(f)


# --- the PlacementTool modes -------------------------------------------------------

func _tool_api(w: World, barn: Building) -> void:
	# loaded at run time: the views use the Models autoload, which --script only provides once running
	var ground: Node3D = load("res://scripts/view/ground_view.gd").new()
	root.add_child(ground)
	ground.setup(w)
	var tool: Node3D = load("res://scripts/view/placement_tool.gd").new()
	root.add_child(tool)
	tool.setup(w, null, ground)

	# cut: drag over trees
	var r := _tree_rect(w, barn.access + Vector2i(-10, 0), 2)
	var n := w.trees_to_mark(r).size()
	tool.start_mode(&"cut")
	_check("cut mode is active", tool.active() and tool.mode == &"cut" and tool.hint().begins_with("Drag over trees"))
	tool._cell = r.position
	tool._mode_click(true)
	tool._cell = r.end - Vector2i.ONE
	tool._refresh()
	var expect := "Drag over trees to mark them · %d tree%s · ≈ %d log%s · Shift unmarks · right click to finish" % [
		n, "" if n == 1 else "s", n * Defs.WOOD_PER_TREE, "" if n == 1 else "s"]
	_check("cut hint: %s" % tool.hint(), tool.hint() == expect)
	tool._mode_click(false)
	_check("the drag marked %d trees" % n, w.trees_to_mark(r, true).size() == n)
	tool._set_shift(true)
	tool._cell = r.position
	tool._mode_click(true)
	tool._cell = r.end - Vector2i.ONE
	tool._mode_click(false)
	tool._set_shift(false)
	_check("Shift + drag unmarks them", w.trees_to_mark(r, true).is_empty())
	tool.cancel()
	_check("cancel ends the mode", not tool.active() and tool.mode == &"" and tool.hint() == "")

	# move: pick a mill, put it elsewhere
	var mill := w.add_building(&"hand_mill", _free_spot(w, &"hand_mill", barn.access, 2), 2)
	var to := _free_spot(w, &"hand_mill", barn.access + Vector2i(4, 6), 2)
	tool.start_mode(&"move")
	tool._cell = mill.anchor
	tool._refresh()
	_check("move hint over the mill: %s" % tool.hint(), tool.hint().begins_with("Click to move the Hand Mill"))
	tool._mode_click(true)
	tool._cell = to + Vector2i(1, 1)          # the ghost is centred on the cursor
	tool._refresh()
	tool._mode_click(true)
	var site := w.building_at(to) as ConstructionSite
	_check("the move tool started the move", site != null and site.moved and tool.mode == &"move" and tool._moving == null)
	tool.cancel()

	# demolish: the new site (cancels the move), then the building, then a road block
	tool.start_mode(&"demolish")
	tool._cell = to
	tool._refresh()
	_check("demolish hint: %s" % tool.hint(), tool.hint().begins_with("Click to cancel moving the Hand Mill"))
	tool._mode_click(true)
	var back := w.building_at(mill.anchor)
	_check("demolish on the moving site cancels the move", w.building_at(to) == null and back != null and not (back is ConstructionSite))
	tool._cell = back.anchor
	tool._refresh()
	_check("demolish hint: %s" % tool.hint(), tool.hint().begins_with("Demolish Hand Mill") and tool.hint().ends_with("click to remove · right click to stop"))
	tool._mode_click(true)
	_check("the mill is demolished", w.building_at(back.anchor) == null)
	tool._cell = w.dealer().anchor
	tool._refresh()
	_check("the Dealer can't be: %s" % tool.problem(), tool.problem() == "Can’t remove the Dealer: the Dealer is not yours")
	var road: Vector2i = w.road_blocks.keys()[0]
	var blocks := w.road_blocks.size()
	tool._cell = road
	tool._refresh()
	tool._mode_click(true)
	_check("a road block is demolished", w.road_blocks.size() == blocks - 1 or w.road_blocker(road) != "")
	tool.cancel()

	# gate
	var f := w.add_field(_free_spot(w, &"field", barn.access + Vector2i(-12, 10), 2), 2, Vector2i(4, 4), &"wheat")
	tool.start_gate(f)
	var side := -1
	for s in [0, 1, 3]:
		if side < 0 and w.field_gate_ok(f, s):
			side = s
	tool._cell = w.field_gate_cell(f, side)
	tool._side = tool._nearest_side(f, tool._cell)
	tool._refresh()
	tool._mode_click(true)
	_check("the gate tool moved the gate to side %d" % side, f.rot == side and not tool.active())
	w.demolish(f)
	tool.queue_free()
	ground.queue_free()


# --- worker names ------------------------------------------------------------------

func _names(w: World) -> void:
	var names := {}
	for wk in w.workers:
		names[wk.name] = true
	_check("every worker has a name, no duplicates (%s)" % ", ".join(names.keys()), names.size() == w.workers.size()
		and not names.has(""))
	WorkerNames.custom = PackedStringArray(["  Streamer Sam  ", w.workers[0].name])
	var wk := w.add_worker(w.workers[0].cell(), Worker.Look.FEMALE)
	var wk2 := w.add_worker(w.workers[0].cell(), Worker.Look.MALE)
	_check("custom names first (%s, %s)" % [wk.name, wk2.name], wk.name == "Streamer Sam" and wk2.name in WorkerNames.MALE)
	WorkerNames.custom = PackedStringArray()
	_check("renaming", w.rename_worker(wk, "  Kvido the Great and Powerful Ruler  ") and wk.name.length() <= WorkerNames.MAX_LENGTH
		and not w.rename_worker(wk, "   "))
	SaveGame.save(w, "tools_test")
	var w2 := SaveGame.load_world("tools_test")
	_check("names are saved", w2.workers.map(func(x: Worker) -> String: return x.name) == w.workers.map(func(x: Worker) -> String: return x.name))
	w.farm_name = "Duck Pond Farm"
	w.time = Defs.DAY_LENGTH * 2.5
	SaveGame.save(w, "tools_test")
	w2 = SaveGame.load_world("tools_test")
	_check("farm name and day", w2.farm_name == "Duck Pond Farm" and w2.day() == 3)


# --- helpers -------------------------------------------------------------------------

func _first(w: World, id: StringName) -> Building:
	for b: Building in w.buildings.values():
		if b.def_id == id and not (b is ConstructionSite):
			return b
	return null


## A small rectangle near `near` with at least `min_trees` markable trees.
func _tree_rect(w: World, near: Vector2i, min_trees: int) -> Rect2i:
	for r in range(4, 80):
		for dy in range(-r, r + 1, 3):
			for dx in range(-r, r + 1, 3):
				var rect := Rect2i(near + Vector2i(dx, dy), Vector2i(4, 4))
				if w.trees_to_mark(rect).size() >= min_trees:
					return rect
	return Rect2i()


## A spot where the building fits without trees, reachable from `near`.
func _free_spot(w: World, id: StringName, near: Vector2i, rot: int) -> Vector2i:
	var fs := Defs.footprint(id, rot) if not Defs.is_field(id) else Vector2i(5, 5)
	for r in range(3, 60):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var a := near + Vector2i(dx, dy)
				var ok := w.can_place(&"field", a, rot, Vector2i(5, 5)) if Defs.is_field(id) else w.can_place(id, a, rot)
				if ok and not _trees(w, Rect2i(a - Vector2i.ONE, fs + Vector2i(2, 2))) \
						and w.nav.find_path(near, Defs.access_for(fs if Defs.is_field(id) else Defs.def(id)["size"], a, rot)).size() > 0:
					return a
	return near


func _trees(w: World, r: Rect2i) -> bool:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if w.has_tree(Vector2i(x, y)):
				return true
	return false


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


func _check(what: String, cond: bool) -> void:
	print("%s %s" % ["  ok " if cond else "FAIL", what])
	ok = ok and cond
