extends SceneTree
## Save / load round trip: plays a while, saves in the middle of a pickup trip, loads and compares,
## then keeps the loaded world running to check that work continues.
##
##   Godot --headless --path . --script scripts/tools/save_test.gd

const STEP := 0.1


func _init() -> void:
	var w := WorldGen.generate(256, 42)
	var barn: Building
	for b: Building in w.buildings.values():
		if b.def_id == &"storage_barn":
			barn = b
	var placed := 0
	for dy in range(4, 30):
		for dx in range(-20, 20):
			if placed < 3 and w.place_site(&"field", barn.anchor + Vector2i(dx, dy), 0, Vector2i(8, 6), [&"wheat", &"potato", &"corn"][placed]):
				placed += 1
	w.place_site(&"storage_barn", barn.anchor + Vector2i(-12, -8), 2)
	for c in [&"wheat", &"potato", &"corn"]:
		w.order(Defs.seed_of(c), Defs.seed_per_tile(c) * 120.0)
	w.order(&"wheelbarrow", 1)
	w.hire(2)
	w.fields.size()
	_run(w, 420.0)
	# wait until the pickup is out with something in it
	var waited := 0.0
	while waited < 900.0 and (w.vehicles[0].parked or w.vehicles[0].cargo.is_empty()):
		_run(w, 1.0)
		waited += 1.0
	print("saving at t=%d, pickup: %s, cargo %s" % [w.time, w.trip_status, w.vehicles[0].cargo])
	var before := _summary(w)
	var err := SaveGame.save(w, "test")
	print("save: ", error_string(err))
	var w2 := SaveGame.load_world("test")
	var after := _summary(w2)
	var ok := true
	for k in before:
		var same: bool = str(before[k]) == str(after[k])
		if not same:
			ok = false
		print("%s %-14s %s%s" % ["  " if same else "!!", k, before[k], "" if same else "  ->  %s" % after[k]])
	# keep both running: the loaded one should keep producing like the original
	_run(w, 600.0)
	_run(w2, 600.0)
	print("after 10 more minutes  original: %d qk sold %s   loaded: %d qk sold %s" % [w.money, _sold(w), w2.money, _sold(w2)])
	print("loaded world: %s, tasks %d, idle %d/%d, pickup: %s" % [w2.fields[0].status(), w2.tasks.tasks.size(), w2.idle_workers(), w2.workers.size(), w2.trip_status])
	print("ROUND TRIP ", "OK" if ok else "DIFFERS")
	quit()


func _run(w: World, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		w.tick(STEP)
		t += STEP


func _sold(w: World) -> int:
	var n := 0
	for k: String in w.ledger:
		if k.begins_with("sales"):
			n += w.ledger[k]
	return n


## Things that must survive a save exactly (carried / loaded goods are counted as stored).
func _summary(w: World) -> Dictionary:
	var stock := {}
	for k in w.totals():
		stock[k] = snappedf(w.total(k), 0.001)
	for wk in w.workers:
		# a load being moved between the pickup and a place is still counted where it came from
		var shuttling := wk.task != null and (wk.task.kind == Task.Kind.TRIP or wk.task.kind == Task.Kind.HELP)
		if wk.carrying != &"" and not shuttling:
			stock[wk.carrying] = snappedf(stock.get(wk.carrying, 0.0) + wk.carry_amount, 0.001)
		if wk.equipment != &"":
			stock[wk.equipment] = stock.get(wk.equipment, 0.0) + 1.0
	for res in w.vehicles[0].cargo:
		stock[res] = snappedf(stock.get(res, 0.0) + w.vehicles[0].cargo[res], 0.001)
	var fields := []
	for f in w.fields:
		fields.append("%s %s %s pile %.0f" % [f.crop, f.anchor, f.status(), f.pile])
	var sites := []
	for b: Building in w.buildings.values():
		if b is ConstructionSite:
			sites.append("%s %.0f%% %d tasks" % [b.def_id, b.progress() * 100.0, b.open_tasks.size()])
	var kinds := {}
	for t in w.tasks.tasks:
		if t.kind != Task.Kind.TRIP and t.kind != Task.Kind.HELP and t.kind != Task.Kind.CARRY and t.kind != Task.Kind.RIDE:   # planned again after loading
			kinds[Task.Kind.keys()[t.kind]] = kinds.get(Task.Kind.keys()[t.kind], 0) + 1
	var trees := 0
	for k in w.tree_kind:
		if k != 0:
			trees += 1
	return {"time": snappedf(w.time, 0.01), "money": w.money, "stock": stock, "workers": w.workers.size(),
		"buildings": w.buildings.size(), "roads": w.road_blocks.size(), "trees": trees, "fields": fields,
		"sites": sites, "tasks": kinds, "hires waiting": w.hires_wanted, "ledger": w.ledger}
