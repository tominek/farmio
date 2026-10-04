class_name SaveGame
## Saves the simulation to a file and builds a World back from it.
##
## Saving never changes the running game. Work in progress is stored "settled": tasks are saved
## without their workers (field rows only with the cells still to do), anything a worker or the
## pickup carries goes to the barn, the pickup is parked and goods bought on an unfinished trip
## go back to the orders. Workers pick their tasks again after loading.

const VERSION := 1
const DIR := "user://saves/"


static func path(slot: String) -> String:
	return DIR + slot + ".save"


static func exists(slot: String) -> bool:
	return FileAccess.file_exists(path(slot))


## Unix time of the save, 0 if there is none.
static func modified(slot: String) -> int:
	return FileAccess.get_modified_time(path(slot)) if exists(slot) else 0


static func save(world: World, slot: String, extra := {}) -> Error:
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(path(slot), FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	var data := _serialize(world)
	data["extra"] = extra
	f.store_var(data)
	return OK


## The saved world, or null. `extra` receives presentation data stored with it (camera, speed).
static func load_world(slot: String, extra := {}) -> World:
	if not exists(slot):
		return null
	var f := FileAccess.open(path(slot), FileAccess.READ)
	var data: Variant = f.get_var()
	if not data is Dictionary or data.get("version", 0) != VERSION:
		push_error("Save %s is missing or from another version" % slot)
		return null
	extra.merge(data.get("extra", {}), true)
	return _deserialize(data)


# --- saving --------------------------------------------------------------------

static func _serialize(w: World) -> Dictionary:
	var stock: Dictionary = w.stock.duplicate()
	var orders: Dictionary = w.orders.duplicate()
	# carried goods and the pickup's cargo are stored as being in the barn
	for wk in w.workers:
		if wk.carrying != &"":
			stock[wk.carrying] = stock.get(wk.carrying, 0.0) + wk.carry_amount
		if wk.equipment != &"":
			stock[wk.equipment] = stock.get(wk.equipment, 0.0) + 1.0
	for v in w.vehicles:
		for res in v.cargo:
			stock[res] = stock.get(res, 0.0) + v.cargo[res]
	# goods of an unfinished purchase that are not in the pickup yet go back to the orders
	for t in w.tasks.tasks:
		if t.kind == Task.Kind.TRIP and t.step_i < t.steps.size():
			var s: Dictionary = t.steps[t.step_i]
			if s.get("type") == "buy" and s.has("queue"):
				var rest: Array = (s["queue"] as Array).duplicate(true)
				for st: Dictionary in [s.get("driver", {})] + (s["helpers"] as Array).map(func(h: Task) -> Dictionary: return h.help_state):
					if st.has("chunk"):
						rest.append(st["chunk"])
				for it in rest:
					orders[it[0]] = orders.get(it[0], 0.0) + it[1]

	var buildings := []
	for b: Building in w.buildings.values():
		var d := {"id": b.id, "def": b.def_id, "anchor": b.anchor, "rot": b.rot, "base": b.base_size,
			"paid": b.paid, "priority": b.priority}
		if b is ConstructionSite:
			d["type"] = "site"
			d["stage"] = b.stage
			d["work_done"] = b.work_done
			d["crop"] = b.crop
			d["delivered"] = b.delivered.duplicate()
		elif b is Field:
			d["type"] = "field"
			d["crop"] = b.crop
			d["next_crop"] = b.next_crop
			d["tiles"] = b.tile_state
			d["growth"] = b.growth
			d["rows"] = b.row_step
			d["pile"] = b.pile
		else:
			d["type"] = "building"
			d["input"] = b.input
			d["output"] = b.output
		buildings.append(d)

	var tasks := []
	for t in w.tasks.tasks:
		if t.kind == Task.Kind.TRIP or t.kind == Task.Kind.HELP or t.building:
			continue                    # pickup trips and mill work are planned again after loading
		var cells := t.cells
		var fetch_amount := t.fetch_amount
		if t.kind == Task.Kind.FIELD and t.worker and t.worker.phase == Worker.Phase.WORKING and t.worker.strip_i > 0:
			cells = cells.slice(mini(t.worker.strip_i, cells.size() - 1))
			if t.fetch != &"":
				fetch_amount = cells.size() * Defs.seed_per_tile(t.field.crop)
		tasks.append({"kind": t.kind, "category": t.category, "cell": cells[0] if not cells.is_empty() else t.cell,
			"work": t.work, "created": t.created, "site": t.site.id if t.site else 0,
			"field": t.field.id if t.field else 0, "step": t.step, "row": t.row, "cells": cells,
			"amount": t.amount, "fetch": t.fetch if t.kind != Task.Kind.HAUL else &"", "fetch_amount": fetch_amount})

	var workers := []
	for wk in w.workers:
		var pos := wk.pos
		if wk.in_vehicle:
			var v: Vehicle = w.vehicles[0] if not w.vehicles.is_empty() else null
			if v:
				pos = Vector2(v.garage.access) + Vector2(0.5, 0.5)
		workers.append({"id": wk.id, "look": wk.look, "pos": pos, "heading": wk.heading})

	var vehicles := []
	for v in w.vehicles:
		vehicles.append({"id": v.id, "kind": v.kind, "garage": v.garage.id})

	return {
		"version": VERSION, "size": w.size, "seed": w.seed_value, "time": w.time, "money": w.money,
		"next_id": w._next_id, "stock": stock, "orders": orders, "auto_sell": w.auto_sell.duplicate(true),
		"hire_fees": w._hire_fees.duplicate(), "category_order": w.category_order.duplicate(),
		"category_off": w.category_off.duplicate(), "ledger": w.ledger.duplicate(),
		"tree_kind": w.tree_kind, "tree_stage": w.tree_stage, "water": w.water, "roads": w.road_blocks.duplicate(),
		"buildings": buildings, "tasks": tasks, "workers": workers, "vehicles": vehicles,
	}


# --- loading -------------------------------------------------------------------

static func _deserialize(d: Dictionary) -> World:
	var w := World.new(d["size"], d["seed"])
	w.time = d["time"]
	w.money = d["money"]
	w.stock.merge(d["stock"], true)
	w.orders = d["orders"]
	w.auto_sell.merge(d["auto_sell"], true)
	w._hire_fees.assign(d["hire_fees"])
	w.hires_wanted = w._hire_fees.size()
	w.category_order = d["category_order"]
	for c: int in Task.DEFAULT_ORDER:          # categories added since the save was made
		if not w.category_order.has(c):
			w.category_order.insert(Task.DEFAULT_ORDER.find(c), c)
	w.category_off = d["category_off"]
	w.ledger = d["ledger"]

	w.tree_kind = d["tree_kind"]
	w.tree_stage = d["tree_stage"]
	if d.has("water"):                 # saves from before rivers have none
		w.water = d["water"]
	for y in w.size:
		for x in w.size:
			w._refresh_nav(Vector2i(x, y))
	for anchor: Vector2i in d["roads"]:
		w.add_road_block(anchor, d["roads"][anchor])

	var by_id := {}
	for bd: Dictionary in d["buildings"]:
		var b: Building
		match bd["type"]:
			"site":
				var s := ConstructionSite.new(bd["id"], bd["def"], bd["anchor"], bd["rot"], bd["base"])
				s.stage = bd["stage"]
				s.work_done = bd["work_done"]
				s.crop = bd["crop"]
				s.delivered = bd.get("delivered", {})
				b = s
			"field":
				var f := Field.new(bd["id"], bd["anchor"], bd["rot"], bd["base"], bd["crop"])
				f.next_crop = bd["next_crop"]
				f.tile_state = bd["tiles"]
				f.growth = bd["growth"]
				f.row_step = bd["rows"]
				f.pile = bd["pile"]
				w.fields.append(f)
				b = f
			_:
				b = Building.new(bd["id"], bd["def"], bd["anchor"], bd["rot"])
				b.input = bd.get("input", 0.0)
				b.output = bd.get("output", 0.0)
		b.paid = bd["paid"]
		b.priority = bd["priority"]
		w._occupy(b)
		by_id[b.id] = b

	for td: Dictionary in d["tasks"]:
		var t := Task.new(td["kind"], td["cell"], td["work"], td["created"])
		t.category = td["category"]
		t.step = td["step"]
		t.row = td["row"]
		t.cells.assign(td["cells"])
		t.amount = td["amount"]
		t.fetch = td["fetch"]
		t.fetch_amount = td["fetch_amount"]
		if td["site"]:
			t.site = by_id[td["site"]]
			t.site.open_tasks.append(t)
		if td["field"]:
			t.field = by_id[td["field"]]
			if t.kind == Task.Kind.FIELD:
				t.field.row_task[t.row] = t
			elif t.kind == Task.Kind.HAUL:
				t.field.pile_reserved += t.amount
		w.tasks.add(t)

	for vd: Dictionary in d["vehicles"]:
		var garage: Building = by_id[vd["garage"]]
		var block: Variant = w.road_nav.block_near(garage.access)
		var v := Vehicle.new(vd["id"], garage, block if block != null else garage.access)
		v.kind = vd["kind"]
		w.vehicles.append(v)

	for wd: Dictionary in d["workers"]:
		var wk := Worker.new(wd["id"], Vector2i(wd["pos"]), wd["look"])
		wk.pos = wd["pos"]
		wk.heading = wd["heading"]
		w.workers.append(wk)

	w._next_id = d["next_id"]
	return w
