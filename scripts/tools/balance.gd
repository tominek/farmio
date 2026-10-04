extends SceneTree
## Headless balance run: a simple bot plays the early game and prints the economy over time.
##
##   Godot --headless --path . --script scripts/tools/balance.gd -- [options]
##     --crop=<wheat|potato|corn|beet|mix>   crop of the fields (mix = rotate through all four)
##     --size=<w>x<h>                        field size (default 10x10)
##     --fields=<n>                          fields placed at the start (default 1)
##     --grow                                keep placing fields and hiring while money allows
##     --minutes=<n>                         game time (default 30)
##     --seed=<n>                            map seed (default 42)

const STEP := 0.1

var world: World
var crop := &"wheat"
var crops: Array[StringName] = []
var field_size := Vector2i(10, 10)
var grow := false
var _placed := 0
var _events := {}         # first-time milestones -> game time
var _debug_at := -1.0


func _init() -> void:
	var minutes := 30.0
	var seed_value := 42
	var start_fields := 1
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=")
		match kv[0]:
			"crop": crop = StringName(kv[1])
			"size": field_size = Vector2i(int(kv[1].split("x")[0]), int(kv[1].split("x")[1]))
			"fields": start_fields = int(kv[1])
			"grow": grow = true
			"minutes": minutes = float(kv[1])
			"seed": seed_value = int(kv[1])
			"debug": _debug_at = float(kv[1]) * 60.0
	if crop == &"mix":
		crops.assign([&"wheat", &"potato", &"corn", &"beet"])
	else:
		crops.assign([crop])
	world = WorldGen.generate(256, seed_value)
	for i in start_fields:
		_place_field()

	var phases := {"idle": 0, "walking": 0, "working": 0, "driving": 0}
	var next_report := 0.0
	var next_think := 0.0
	print("crop %s  field %dx%d  start fields %d  grow %s" % [crop, field_size.x, field_size.y, start_fields, grow])
	print(" min   money  fields workers  sales(qk)   idle walk work drive")
	while world.time < minutes * 60.0:
		world.tick(STEP)
		if world.time >= next_think:
			next_think = world.time + 5.0
			_think()
		if fmod(world.time, 1.0) < STEP:
			for w in world.workers:
				if w.in_vehicle:
					phases["driving"] += 1
				elif w.phase == Worker.Phase.IDLE:
					phases["idle"] += 1
				elif w.phase == Worker.Phase.WORKING:
					phases["working"] += 1
				else:
					phases["walking"] += 1
		_milestones()
		if _debug_at > 0.0 and world.time >= _debug_at:
			_debug_at = -1.0
			_dump()
		if world.time >= next_report:
			next_report += 300.0
			var total := maxf(1.0, phases["idle"] + phases["walking"] + phases["working"] + phases["driving"])
			print("%4d  %6d  %6d  %7d  %8d   %3d%% %3d%% %3d%% %3d%%" % [
				roundi(world.time / 60.0), world.money, world.fields.size(), world.workers.size(), _sold(),
				roundi(100.0 * phases["idle"] / total), roundi(100.0 * phases["walking"] / total),
				roundi(100.0 * phases["working"] / total), roundi(100.0 * phases["driving"] / total)])
			for k in phases:
				phases[k] = 0
	for e in _events:
		print("   %-30s %d:%02d" % [e, int(_events[e]) / 60, int(_events[e]) % 60])
	print("ledger:")
	var keys := world.ledger.keys()
	keys.sort()
	for k in keys:
		print("   %-22s %7d" % [k, world.ledger[k]])
	quit()


func _sold() -> int:
	var n := 0
	for k: String in world.ledger:
		if k.begins_with("sales"):
			n += world.ledger[k]
	return n


## The bot: orders missing seed, and in grow mode places fields / hires while money allows.
func _think() -> void:
	var short := world.seed_shortage()
	for res: StringName in short:
		var missing: float = short[res] - world.orders.get(res, 0.0)
		if missing > 0.0:
			world.order(res, missing)
	if not grow:
		return
	# keep money for one sowing of every field (a player who spends it all can't buy seed)
	var reserve := 300
	for f in world.fields:
		reserve += world.order_cost(Defs.seed_of(f.crop), f.size.x * f.size.y * Defs.seed_per_tile(f.crop))
	var cost := Defs.field_cost(field_size)
	var idle := world.idle_workers()
	if idle == 0 and world.tasks.pending_count() > 6 and world.money > world.hire_cost(1) + cost + reserve:
		world.hire(1)
	elif idle > 0 and world.money > cost + reserve + 200:
		_place_field()


func _place_field() -> void:
	var c := Vector2i.ZERO
	for b: Building in world.buildings.values():
		if b.def_id == &"storage_barn":
			c = b.anchor
	var want: StringName = crops[_placed % crops.size()]
	# like a player: first try spots whose gate is next to a road (the pickup collects the harvest)
	for r in range(3, 40):
		for dy in [r, -r]:
			for dx in range(-r, r + 1):
				for rot in [0, 2]:
					var a := c + Vector2i(dx, dy)
					if world.can_place(&"field", a, rot, field_size) \
							and world.road_nav.block_near(Defs.access_for(field_size, a, rot)) != null:
						world.place_site(&"field", a, rot, field_size, want)
						_placed += 1
						return
	for r in range(3, 60):
		for dy in [r, -r]:
			for dx in range(-r, r + 1):
				for rot in [0, 2]:
					if world.place_site(&"field", c + Vector2i(dx, dy), rot, field_size, want):
						_placed += 1
						return


func _milestones() -> void:
	if world.fields.is_empty():
		return
	var f := world.fields[0]
	var counts := [0, 0, 0, 0]
	for r in f.size.y:
		counts[f.row_step[r]] += 1
	_mark("field built", true)
	_mark("seed in the barn", world.total(Defs.seed_of(f.crop)) > 0.0)
	_mark("first field fully sown", counts[Field.RowStep.GROW] == f.size.y)
	_mark("first row ripe", counts[Field.RowStep.HARVEST] > 0)
	_mark("first field harvested", _events.has("first row ripe") and counts[Field.RowStep.HARVEST] == 0 and counts[Field.RowStep.GROW] == 0)
	_mark("first money from sales", _sold() > 0)


func _mark(e: String, cond: bool) -> void:
	if cond and not _events.has(e):
		_events[e] = world.time


func _dump() -> void:
	print("--- t=%d s  stock %s  orders %s  pickup: %s" % [world.time, world.totals(), world.orders, world.trip_status])
	for w in world.workers:
		var t := w.task
		print("   w%d %s at %s carrying %s %.1f eq %s task %s" % [w.id, Worker.Phase.keys()[w.phase], w.cell(), w.carrying, w.carry_amount, w.equipment,
			"-" if t == null else "%s %s fetch %s %.3f retry %.0f cell %s path %d/%d" % [Task.Kind.keys()[t.kind], t.step, t.fetch, t.fetch_amount, t.retry_at, t.cell, w.path_i, w.path.size()]])
	for f in world.fields:
		print("   field %s %s %s pile %.0f" % [f.crop, f.anchor, f.status(), f.pile])
