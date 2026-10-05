class_name SaveGame
## Saves the simulation to a file and builds a World back from it.
##
## Saving never changes the running game. Work in progress is stored "settled": tasks are saved
## without their workers (field rows only with the cells still to do), anything a worker or the
## pickup carries goes to the barn, the pickup is parked and goods bought on an unfinished trip
## go back to the orders. Workers pick their tasks again after loading; carry legs and their claims
## are not saved, the planner plans them again.

const VERSION := 3             # 2: goods kept per store (Logistics step 1); 3: carry legs, not saved
const DIR := "user://saves/"


static func path(slot: String) -> String:
	return DIR + slot + ".save"


static func exists(slot: String) -> bool:
	return FileAccess.file_exists(path(slot))


## Unix time of the save, 0 if there is none.
static func modified(slot: String) -> int:
	return FileAccess.get_modified_time(path(slot)) if exists(slot) else 0


static func save(world: World, slot: String, extra := {}, header := {}) -> Error:
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(path(slot), FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	var data := _serialize(world)
	data["extra"] = extra
	data["meta"] = _full_meta(world, slot, header)
	f.store_var(data)
	_write_meta(slot, data["meta"])
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


# --- slots and metadata ----------------------------------------------------------------
# Each save has a small JSON header next to it (<slot>.meta: name, kind, time, stats) and maybe a
# thumbnail (<slot>.png), so the save / load dialogs can list saves without reading whole worlds.
# Slots: "quicksave" (F5), "autosave" (the newest autosave) with older ones in "autosave_2" …
# "autosave_<count>", and "manual_<unix time>" for named saves.

const KIND_NAMES := {"manual": "Manual", "autosave": "Autosave", "quicksave": "Quicksave"}


static func kind_of(slot: String) -> String:
	if slot == "quicksave":
		return slot
	return "autosave" if autosave_index(slot) > 0 else "manual"


## 1 for "autosave", n for "autosave_<n>", 0 for other slots.
static func autosave_index(slot: String) -> int:
	if slot == "autosave":
		return 1
	var n := slot.trim_prefix("autosave_")
	return int(n) if slot.begins_with("autosave_") and n.is_valid_int() and int(n) > 1 else 0


static func autosave_slot(index: int) -> String:
	return "autosave" if index <= 1 else "autosave_%d" % index


## Before a new autosave: the older ones move one slot down ("autosave" -> "autosave_2" …) and the
## ones beyond `keep` (including extras after the player lowered the count) are deleted, so after
## saving into "autosave" there are at most `keep`.
static func rotate_autosaves(keep: int) -> void:
	keep = maxi(1, keep)
	if DirAccess.dir_exists_absolute(DIR):
		for file in DirAccess.get_files_at(DIR):
			var i := autosave_index(file.get_basename())
			if file.ends_with(".save") and i >= keep:
				delete(file.get_basename())
	for i in range(keep - 1, 0, -1):
		if exists(autosave_slot(i)):
			_rename(autosave_slot(i), autosave_slot(i + 1))


static func _rename(from: String, to: String) -> void:
	delete(to)
	for ext in [".save", ".meta", ".png"]:
		if FileAccess.file_exists(DIR + from + ext):
			DirAccess.rename_absolute(DIR + from + ext, DIR + to + ext)


## A fresh slot for a named save.
static func new_manual_slot() -> String:
	var slot := "manual_%d" % int(Time.get_unix_time_from_system())
	while exists(slot):
		slot += "b"
	return slot


## The numbers shown with a save (also stored in its header).
static func stats(w: World) -> Dictionary:
	var tiles := 0
	for f in w.fields:
		tiles += f.size.x * f.size.y
	var buildings := 0
	for b: Building in w.buildings.values():
		if not b is Field and not b is ConstructionSite:
			buildings += 1
	return {"quacks": w.money, "workers": w.workers.size(), "fields": w.fields.size(), "tiles": tiles,
		"buildings": buildings, "research": w.unlocked.size(), "research_total": Tech.NODES.size(),
		"game_time": w.time, "seed": w.seed_value, "size": w.size,
		"farm": String(w.get("farm_name")) if "farm_name" in w else "", "day": int(w.call("day")) if w.has_method("day") else 0}


static func _full_meta(w: World, slot: String, header: Dictionary) -> Dictionary:
	var m := stats(w)
	m["slot"] = slot
	m["kind"] = kind_of(slot)
	m["name"] = m["farm"] if m["farm"] != "" else KIND_NAMES[m["kind"]]
	m["saved"] = int(Time.get_unix_time_from_system())
	m["played"] = 0.0
	m["version"] = VERSION
	m.merge(header, true)
	return m


static func _write_meta(slot: String, header: Dictionary) -> void:
	var f := FileAccess.open(DIR + slot + ".meta", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(header))


## Stores a small picture of the farm with the save (shown in the save / load dialogs).
static func save_thumbnail(slot: String, image: Image) -> void:
	if image == null or image.is_empty():
		return
	var img := image.duplicate() as Image
	var aspect := 16.0 / 9.0
	var w := img.get_width()
	var h := img.get_height()
	if float(w) / h > aspect:
		var cw := int(h * aspect)
		img = img.get_region(Rect2i((w - cw) / 2, 0, cw, h))
	else:
		var ch := int(w / aspect)
		img = img.get_region(Rect2i(0, (h - ch) / 2, w, ch))
	img.resize(384, 216, Image.INTERPOLATE_BILINEAR)
	DirAccess.make_dir_recursive_absolute(DIR)
	img.save_png(DIR + slot + ".png")


static func thumbnail(slot: String) -> Texture2D:
	var p := DIR + slot + ".png"
	if not FileAccess.file_exists(p):
		return null
	var img := Image.load_from_file(p)
	return ImageTexture.create_from_image(img) if img else null


## The header of a save: name, kind, saved (unix), played (s), quacks, workers, fields, tiles,
## buildings, research, research_total, game_time, bytes. Saves without one get name and time only.
static func meta(slot: String) -> Dictionary:
	var m := {}
	var p := DIR + slot + ".meta"
	if FileAccess.file_exists(p):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
		if parsed is Dictionary:
			m = parsed
	if m.is_empty():
		m = {"kind": kind_of(slot), "name": KIND_NAMES[kind_of(slot)], "saved": modified(slot)}
	m["slot"] = slot
	var f := FileAccess.open(path(slot), FileAccess.READ)
	m["bytes"] = f.get_length() if f else 0
	return m


## All saves, newest first.
static func list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(DIR):
		return out
	for file in DirAccess.get_files_at(DIR):
		var slot := file.get_basename()
		# player saves only (tools write their own slots, e.g. "test")
		if file.ends_with(".save") and (slot == "quicksave" or autosave_index(slot) > 0 or slot.begins_with("manual_")):
			var m := meta(slot)
			if int(m.get("version", 0)) == VERSION:      # saves of an older format can't be loaded
				out.append(m)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.get("saved", 0) > b.get("saved", 0))
	return out


static func newest() -> Dictionary:
	var all := list()
	return all[0] if not all.is_empty() else {}


static func delete(slot: String) -> void:
	for ext in [".save", ".meta", ".png"]:
		if FileAccess.file_exists(DIR + slot + ext):
			DirAccess.remove_absolute(DIR + slot + ext)


# --- saving --------------------------------------------------------------------

static func _serialize(w: World) -> Dictionary:
	var loose := Store.from_dict(w.loose.to_dict())
	var orders: Dictionary = w.orders.duplicate()
	# carried goods and the pickup's cargo are saved as loose goods; loading puts them in a barn
	for wk in w.workers:
		if wk.carrying != &"":
			loose.put(wk.carrying, wk.carry_amount)
		if wk.equipment != &"":
			loose.put(wk.equipment, 1.0)
	for v in w.vehicles:
		for res in v.cargo:
			loose.put(res, v.cargo[res])
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
			"paid": b.paid, "priority": b.priority, "number": b.number, "name": b.custom_name}
		if b is ConstructionSite:
			d["type"] = "site"
			d["stage"] = b.stage
			d["work_done"] = b.work_done
			d["crop"] = b.crop
			d["delivered"] = b.delivered.duplicate()
			d["upgrade_of"] = b.upgrade_of.id if b.upgrade_of else 0
			d["work_total"] = b.work_total
			if b.dismantle or b.moved:         # a building being moved (see World.move_building)
				d["move"] = {"dismantle": b.dismantle, "moved": b.moved, "needs": b.needs.duplicate(), "level": b.level,
					"materials": b.materials.duplicate(), "pile": b.pile.duplicate(), "pile_cell": b.pile_cell,
					"by_pickup": b.by_pickup, "partner": b.partner.id if b.partner else 0}
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
			d["level"] = b.level
			d["materials"] = b.materials.duplicate()
		if b.store:
			d["store"] = b.store.to_dict()
		buildings.append(d)

	var tasks := []
	for t in w.tasks.tasks:
		if t.kind == Task.Kind.TRIP or t.kind == Task.Kind.HELP or t.kind == Task.Kind.CARRY or t.building:
			continue                    # pickup trips, carry legs and mill work are planned again after loading
		var cells := t.cells
		var fetch_amount := t.fetch_amount
		if t.kind == Task.Kind.FIELD and t.worker and t.worker.phase == Worker.Phase.WORKING and t.worker.strip_i > 0:
			cells = cells.slice(mini(t.worker.strip_i, cells.size() - 1))
			if t.fetch != &"":
				fetch_amount = cells.size() * Defs.seed_per_tile(t.field.crop)
		tasks.append({"kind": t.kind, "category": t.category, "cell": cells[0] if not cells.is_empty() else t.cell,
			"work": t.work, "created": t.created, "site": t.site.id if t.site else 0,
			"field": t.field.id if t.field else 0, "step": t.step, "row": t.row, "cells": cells,
			"amount": t.amount, "fetch": t.fetch, "fetch_amount": fetch_amount})

	var workers := []
	for wk in w.workers:
		var pos := wk.pos
		if wk.in_vehicle:
			var v: Vehicle = w.vehicles[0] if not w.vehicles.is_empty() else null
			if v:
				pos = Vector2(v.garage.access) + Vector2(0.5, 0.5)
		workers.append({"id": wk.id, "look": wk.look, "name": wk.name, "pos": pos, "heading": wk.heading})

	var piles := []
	for s in w.ground_piles:
		piles.append({"cell": s.cell, "category": s.category, "store": s.to_dict()})

	var vehicles := []
	for v in w.vehicles:
		vehicles.append({"id": v.id, "kind": v.kind, "garage": v.garage.id})

	return {
		"version": VERSION, "size": w.size, "seed": w.seed_value, "time": w.time, "money": w.money,
		"next_id": w._next_id, "loose": loose.to_dict(), "orders": orders, "auto_sell": w.auto_sell.duplicate(true),
		"hire_fees": w._hire_fees.duplicate(), "category_order": w.category_order.duplicate(),
		"category_off": w.category_off.duplicate(), "ledger": w.ledger.duplicate(), "unlocked": w.unlocked.keys(),
		"tree_kind": w.tree_kind, "tree_stage": w.tree_stage, "water": w.water, "roads": w.road_blocks.duplicate(),
		"buildings": buildings, "tasks": tasks, "workers": workers, "vehicles": vehicles, "ground_piles": piles,
		"farm_name": w.farm_name,
	}


# --- loading -------------------------------------------------------------------

static func _deserialize(d: Dictionary) -> World:
	var w := World.new(d["size"], d["seed"])
	w.time = d["time"]
	w.money = d["money"]
	w.orders = d["orders"]
	w.auto_sell.merge(d["auto_sell"], true)
	w._hire_fees.assign(d["hire_fees"])
	w.hires_wanted = w._hire_fees.size()
	w.category_order = d["category_order"]
	w.category_off = d["category_off"]
	w.ledger = d["ledger"]
	w.farm_name = d.get("farm_name", "")
	for c: int in Task.DEFAULT_ORDER:
		if not w.category_order.has(c):
			w.category_order.append(c)     # categories added since the save (Felling)
	for id: StringName in d["unlocked"]:
		w.unlocked[id] = true

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
				s.work_total = bd.get("work_total", s.work_total)
				var mv: Dictionary = bd.get("move", {})
				if not mv.is_empty():
					s.dismantle = mv["dismantle"]
					s.moved = mv["moved"]
					s.needs = mv["needs"]
					s.level = mv["level"]
					s.materials = mv["materials"]
					s.pile = mv["pile"]
					s.pile_cell = mv["pile_cell"]
					s.by_pickup = mv["by_pickup"]
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
				b.level = bd["level"]
				b.materials = bd["materials"]
				w._register_store(b, bd.get("store", {}))
		b.paid = bd["paid"]
		b.priority = bd["priority"]
		b.number = bd.get("number", 1)
		b.custom_name = bd.get("name", "")
		by_id[b.id] = b
		if bd.get("upgrade_of", 0):
			w.buildings[b.id] = b              # an upgrade site takes no tiles, linked below
		else:
			w._occupy(b)
	for bd: Dictionary in d["buildings"]:
		if bd.get("upgrade_of", 0):
			var s: ConstructionSite = by_id[bd["id"]]
			s.upgrade_of = by_id[bd["upgrade_of"]]
			s.upgrade_of.upgrading = s
			s.work_total = float(Defs.def(s.def_id)["build_work"]) * Defs.UPGRADE_WORK
		if bd.get("move", {}).get("partner", 0):
			by_id[bd["id"]].partner = by_id[bd["move"]["partner"]]

	for pd: Dictionary in d.get("ground_piles", []):
		var pile := Store.from_dict(pd["store"])
		pile.kind = Store.Kind.GROUND
		pile.cell = pd["cell"]
		pile.category = pd["category"]
		w.add_ground_pile(pile)

	w.loose = Store.from_dict(d["loose"])
	w.settle_loose()               # goods that have nowhere to go yet (no barn built)

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
		if t.kind == Task.Kind.CHOP and t.site == null:
			w.marked[t.cell] = t              # a tree marked for felling
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
		wk.name = wd.get("name", "")
		if wk.name == "":
			wk.name = WorkerNames.pick(w, wk.look)
		w.workers.append(wk)

	w._next_id = d["next_id"]
	return w
