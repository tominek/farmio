extends Node3D
## Game root: generates the world, wires presentation to the simulation and runs time.
##
## User args (after `--`):
##   --seed=<n>       map seed (default random)
##   --size=<n>       map size in tiles (default 256 = Small)
##   --shots=<dir>    run a scripted scenario, save screenshots, then quit
##   --load=<slot>    start from a saved game (quicksave, autosave)
##   --snap=<file>    save one screenshot after start, then quit (checks a loaded game)
##
## F5 saves (quicksave), F9 loads the newest save; the game autosaves every AUTOSAVE_INTERVAL.

const AUTOSAVE_INTERVAL := 300.0   # game seconds

static var pending_load := ""      # slot to load when the scene restarts

var world: World
var rig: CameraRig
var ground: GroundView
var tool: PlacementTool
var hud: Hud
var speed := 1.0
var paused := false

var _shots_dir := ""
var _autosave_at := AUTOSAVE_INTERVAL


func _ready() -> void:
	var seed_value := randi()
	var size := 256
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_value = int(arg.trim_prefix("--seed="))
		elif arg.begins_with("--size="):
			size = int(arg.trim_prefix("--size="))
		elif arg.begins_with("--shots="):
			_shots_dir = arg.trim_prefix("--shots=")
		elif arg.begins_with("--load=") and pending_load == "":
			pending_load = arg.trim_prefix("--load=")

	var t0 := Time.get_ticks_msec()
	var saved := {}
	if pending_load != "":
		world = SaveGame.load_world(pending_load, saved)
		print("loaded %s in %d ms" % [pending_load, Time.get_ticks_msec() - t0])
		pending_load = ""
	if world == null:
		world = WorldGen.generate(size, seed_value)
		print("world %d x %d seed %d generated in %d ms" % [size, size, seed_value, Time.get_ticks_msec() - t0])
	else:
		size = world.size
	_autosave_at = world.time + AUTOSAVE_INTERVAL

	_setup_environment()
	rig = CameraRig.new()
	add_child(rig)
	rig.bounds = Rect2(0, 0, size * Defs.TILE, size * Defs.TILE)

	ground = GroundView.new()
	add_child(ground)
	ground.setup(world)
	for view: Node3D in [WaterView.new(), TreeView.new(), RoadView.new(), FieldView.new(), BuildingView.new(), VehicleView.new(), WorkerView.new()]:
		add_child(view)
		view.setup(world)

	tool = PlacementTool.new()
	add_child(tool)
	tool.setup(world, rig, ground)
	hud = Hud.new()
	add_child(hud)
	hud.setup(world, tool)
	hud.build_requested.connect(tool.start)
	hud.speed_requested.connect(_set_speed)
	_set_speed(1.0)

	if saved.has("camera"):
		var cam: Array = saved["camera"]
		rig.focus(cam[0], cam[1])
		rig.set_yaw_degrees(cam[2])
	else:
		rig.focus(_farm_center(), 50.0)
	hud.save_requested.connect(save_game)
	hud.load_requested.connect(load_game)
	print("setup done in %d ms" % (Time.get_ticks_msec() - t0))
	if _shots_dir != "":
		_run_shots()
	for arg in OS.get_cmdline_user_args():
		# framing for --snap: --at=<tile x>,<tile y> or --at=bridge, --zoom=<size>, --yaw=<deg>
		if arg == "--at=bridge":
			for a: Vector2i in world.road_blocks:
				if world.is_bridge(a):
					rig.focus(Defs.footprint_center(a, Vector2i(2, 2)))
		elif arg == "--at=pond":
			for i in world.water.size():
				if world.water[i] == Defs.Water.POND:
					rig.focus(Vector3((i % size + 0.5) * Defs.TILE, 0, (i / size + 3.5) * Defs.TILE))
					break
		elif arg.begins_with("--at="):
			var v := arg.trim_prefix("--at=").split(",")
			rig.focus(Vector3((float(v[0]) + 0.5) * Defs.TILE, 0, (float(v[1]) + 0.5) * Defs.TILE))
		elif arg.begins_with("--zoom="):
			rig.focus(rig.position, float(arg.trim_prefix("--zoom=")))
		elif arg.begins_with("--yaw="):
			rig.set_yaw_degrees(float(arg.trim_prefix("--yaw=")))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snap="):
			for i in 30:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--snap="))
			get_tree().quit()


func _farm_center() -> Vector3:
	for b: Building in world.buildings.values():
		if b.def_id == &"storage_barn":
			return Defs.footprint_center(b.anchor, b.size) + Vector3(8, 0, 6)
	return Vector3(world.size * Defs.TILE * 0.5, 0, world.size * Defs.TILE * 0.5)


func _set_speed(s: float) -> void:
	paused = s <= 0.0
	if not paused:
		speed = s
	hud.set_speed_text("Paused" if paused else "%dx" % speed)


func _physics_process(delta: float) -> void:
	if paused or _shots_dir != "":
		return
	_step(delta * speed)
	if world.time >= _autosave_at:
		_autosave_at = world.time + AUTOSAVE_INTERVAL
		save_game("autosave")


func _step(dt: float) -> void:
	# large time steps (fast forward) are split so walking and work timers stay accurate
	var steps := maxi(1, ceili(dt / 0.05))
	for i in steps:
		world.tick(dt / steps)


func _unhandled_input(event: InputEvent) -> void:
	if tool.active():
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var p: Variant = rig.ground_point(event.position)
			if p != null:
				_select_at(p)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			hud.info.clear()
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				_set_speed(speed if paused else 0.0)
			KEY_1:
				_set_speed(1.0)
			KEY_2:
				_set_speed(2.0)
			KEY_3:
				_set_speed(3.0)
			KEY_F12:
				hud.toggle_dev_menu()
			KEY_P:
				hud.toggle_priorities()
			KEY_T:
				hud.toggle_research()
			KEY_F5:
				save_game()
			KEY_F9:
				load_game()
			KEY_ESCAPE:
				hud.info.clear()
			KEY_DELETE, KEY_BACKSPACE:
				hud.info.press_action()


## Worker under the cursor first (they are small), then building / field / site, then road.
func _select_at(p: Vector3) -> void:
	var at := Vector2(p.x, p.z) / Defs.TILE
	var best: Worker = null
	var best_d := 0.8 * 0.8
	for w in world.workers:
		var d := w.pos.distance_squared_to(at)
		if not w.in_vehicle and d < best_d:
			best_d = d
			best = w
	if best:
		hud.info.select(best)
		return
	var c := Defs.world_to_cell(p)
	var b := world.building_at(c)
	if b and b.def_id == &"dealer":
		hud.info.clear()
		hud.toggle_dealer()
	elif b:
		hud.info.select(b)
	elif world.road_block_at(c) != null:
		hud.info.select(world.road_block_at(c))
	else:
		hud.info.clear()


func _process(_delta: float) -> void:
	if not tool.active():
		ground.highlight_color(hud.info.highlight_rect(), Color(1.0, 0.85, 0.35))


func _setup_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 300.0
	add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.74, 0.88)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.74, 0.88)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


# --- scripted screenshots ------------------------------------------------------

func _run_shots() -> void:
	DirAccess.make_dir_recursive_absolute(_shots_dir)
	var farm := _farm_center()
	await _shot("01_farm", farm, 70.0, 0.0)
	await _shot("02_farm_rotated", farm, 45.0, 140.0)
	var dealer: Building
	for b: Building in world.buildings.values():
		if b.def_id == &"dealer":
			dealer = b
	await _shot("03_dealer", Defs.footprint_center(dealer.anchor, dealer.size), 60.0, 0.0)
	await _shot("04_overview", farm, 240.0, 0.0)
	hud.toggle_dev_menu()
	var dev: DevMenu = hud.dev_menu
	dev._add_worker()
	dev._add_worker()
	world.remove_worker()
	dev.refresh()
	await _shot("04b_dev_menu", farm, 50.0, 0.0)
	print("workers after +2 -1: ", world.workers.size())
	hud.toggle_dev_menu()
	hud._on_build_pressed(&"field")
	tool.set_crop(&"potato")
	tool._cell = Defs.world_to_cell(farm) + Vector2i(0, 4)
	tool._refresh()
	await _shot("09b_field_corner", farm, 50.0, 0.0)
	tool._drag_start = tool._cell
	tool._cell += Vector2i(6, 4)
	tool._refresh()
	hud._refresh()
	await _shot("09c_field_drag", farm, 50.0, 0.0)
	tool.cancel()
	await _road_scenario(farm)

	# place a barn in the forest edge next to the farm and a road towards it, then let workers work
	world.stock[&"planks"] = 200.0
	var site := _place_near_trees(&"storage_barn", farm)
	if site:
		var c := Defs.footprint_center(site.anchor, site.size)
		await _shot("05_site_placed", c, 40.0, 20.0)
		_simulate(25.0)
		await _shot("06_clearing", c, 40.0, 20.0)
		_simulate(60.0)
		await _shot("07_building", c, 40.0, 20.0)
		_simulate(120.0)
		await _shot("08_done", c, 40.0, 20.0)
	await _field_scenario(farm)
	print("stock ", world.stock, " money ", world.money, " tasks ", world.tasks.tasks.size())
	get_tree().quit()


## Gravel road ghost dragged across the river (a bridge), then a gravel upgrade of the farm road.
func _road_scenario(farm: Vector3) -> void:
	world.money += 5000
	for id in [&"gravel_road", &"hand_mill", &"sawmill", &"water_mill", &"mill_gear_2"]:
		world.unlock(id)
	var spot := Vector2i(-1, -1)
	for a: Vector2i in world.road_blocks:
		if world.is_bridge(a):
			continue
		for y in range(Defs.BORDER + 2, world.size - Defs.BORDER - 2, Defs.ROAD_BLOCK):
			for x in range(Defs.BORDER + 2, world.size - Defs.BORDER - 2, Defs.ROAD_BLOCK):
				var b := Vector2i(x, y)
				if spot.x < 0 and world.bridge_ok(b) and b.distance_to(a) < 40:
					spot = b
	if spot.x >= 0:
		var across := Vector2i(Defs.ROAD_BLOCK, 0) if world.river_axis(spot) == 1 else Vector2i(0, Defs.ROAD_BLOCK)
		hud._on_build_pressed(&"road_gravel")
		tool._drag_start = spot - across * 2
		tool._cell = spot + across * 2
		tool._refresh()
		hud._refresh()
		await _shot("09d_bridge_ghost", Defs.footprint_center(spot, Vector2i(2, 2)), 35.0, 20.0)
		tool.cancel()
	# upgrade the road blocks closest to the farm
	var blocks: Array = world.road_blocks.keys()
	var fc := Defs.world_to_cell(farm)
	blocks.sort_custom(func(p: Vector2i, q: Vector2i) -> bool: return p.distance_squared_to(fc) < q.distance_squared_to(fc))
	world.stock[&"gravel"] = Defs.GRAVEL_PER_BLOCK * 3.5
	for b: Vector2i in blocks.slice(0, 5):
		world.place_site(&"road_gravel", b, 0)
	var at := Defs.footprint_center(blocks[0], Vector2i(2, 2))
	_simulate(40.0)
	await _shot("09e_gravel_delivery", at, 40.0, 20.0)
	_simulate(200.0)
	await _shot("09f_gravel_done", at, 40.0, 20.0)
	print("gravel blocks: ", world.road_blocks.values().count(&"gravel"), " alerts: ", world.alerts())
	# a water mill on the river bank closest to the farm, a hand mill and a sawmill by the barn
	var best := INF
	var wm := Vector2i(-1, -1)
	var wm_rot := 0
	for y in range(Defs.BORDER, world.size - Defs.BORDER - 3):
		for x in range(Defs.BORDER, world.size - Defs.BORDER - 3):
			for r in 4:
				var d := Vector2(x, y).distance_squared_to(fc)
				if d < best and world.can_place(&"water_mill", Vector2i(x, y), r):
					best = d
					wm = Vector2i(x, y)
					wm_rot = r
	if wm.x >= 0:
		for y in range(-1, 4):
			for x in range(-1, 4):
				if world.has_tree(wm + Vector2i(x, y)):
					world.remove_tree(wm + Vector2i(x, y))
		world.add_building(&"water_mill", wm, wm_rot)
		await _shot("09g_water_mill", Defs.footprint_center(wm, Vector2i(3, 3)), 30.0, 30.0)
		await _shot("09h_water_mill_side", Defs.footprint_center(wm, Vector2i(3, 3)), 25.0, 120.0)
		# the research tree and the mill's info panel with the upgrade
		hud.show_research(&"mill_gear_3")
		await _shot("09i_research", Defs.footprint_center(wm, Vector2i(3, 3)), 25.0, 120.0)
		hud.research.hide()
		hud.info.select(world.building_at(wm))
		await _shot("09j_mill_info", Defs.footprint_center(wm, Vector2i(3, 3)), 25.0, 120.0)
		world.stock[&"planks"] = 50.0
		world.start_upgrade(world.building_at(wm))
		_simulate(240.0)
		await _shot("09k_mill_level2", Defs.footprint_center(wm, Vector2i(3, 3)), 25.0, 120.0)
		hud.info.clear()


func _simulate(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		world.tick(0.05)
		t += 0.05


func _place_near_trees(def_id: StringName, near: Vector3) -> ConstructionSite:
	var center := Defs.world_to_cell(near)
	for r in range(10, 40):
		for dx in range(-r, r + 1):
			for dy in [-r, r]:
				var anchor: Vector2i = center + Vector2i(dx, dy)
				if not world.can_place(def_id, anchor, 2):
					continue
				var trees := 0
				var fs := Defs.footprint(def_id, 2)
				for y in fs.y:
					for x in fs.x:
						if world.has_tree(anchor + Vector2i(x, y)):
							trees += 1
				if trees >= 4:
					return world.place_site(def_id, anchor, 2)
	return null


func _shot(name: String, at: Vector3, zoom: float, yaw: float) -> void:
	rig.focus(at, zoom)
	rig.set_yaw_degrees(yaw)
	for f in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_shots_dir.path_join(name + ".png"))
	print("shot ", name)


## Four small fields (one per crop) south of the farm road, simulated through a full cycle.
func _field_scenario(farm: Vector3) -> void:
	var c := Defs.world_to_cell(farm)
	var placed: Array[ConstructionSite] = []
	var crops: Array[StringName] = [&"wheat", &"potato", &"corn", &"beet"]
	for dy in range(2, 20):
		for dx in range(-24, 8):
			if placed.size() == crops.size():
				break
			var anchor := c + Vector2i(dx, dy)
			var site := world.place_site(&"field", anchor, 0, Vector2i(7, 5), crops[placed.size()])
			if site:
				placed.append(site)
	print("fields placed: ", placed.size())
	for crop in crops:
		world.order(Defs.seed_of(crop), Defs.seed_per_tile(crop) * 40.0)
	world.unlock(&"wheelbarrow")
	print("wheelbarrows ordered: ", world.order(&"wheelbarrow", 2))
	print("order beyond budget accepted: ", world.order(&"seed_beet", 1000.0))
	print("hiring 3, cost qk ", world.hire_cost(3), " workers ", world.workers.size())
	world.hire(3)
	if placed.is_empty():
		return
	var center := Defs.footprint_center(placed[0].anchor, placed[0].size) + Vector3(18, 0, 0)
	await _shot("10_fields_placed", center, 50.0, 0.0)
	hud.toggle_dealer()
	_simulate(15.0)
	await _shot("10b_dealer_panel", center, 50.0, 0.0)
	hud.toggle_dealer()
	if not world.vehicles.is_empty():
		var v := world.vehicles[0]
		var waited := 0.0
		while not world.trip_status.contains("Dealer") and waited < 300.0:
			_simulate(1.0)
			waited += 1.0
		_simulate(6.0)
		await _shot("10c_pickup_driving", Vector3(v.pos.x, 0, v.pos.y) * Defs.TILE, 30.0, 20.0)
		print("pickup ", world.trip_status, " at ", v.pos)
		waited = 0.0
		while not world.trip_status.begins_with("Unloading at the Dealer") and waited < 300.0:
			_simulate(0.5)
			waited += 0.5
		_simulate(1.5)
		waited = 0.0
		while not world.trip_status.begins_with("Loading goods at the barn") and waited < 2000.0:
			_simulate(0.5)
			waited += 0.5
		_simulate(14.0)
		await _shot("10e_loading_with_helpers", Vector3(v.pos.x, 0, v.pos.y) * Defs.TILE, 22.0, 20.0)
		print("loading ", world.trip_status, " cargo ", v.cargo, " helpers busy: ", world.workers.filter(func(x: Worker) -> bool: return x.task != null and x.task.kind == Task.Kind.HELP).size())
		await _shot("10d_unloading_at_dealer", Vector3(v.pos.x, 0, v.pos.y) * Defs.TILE, 22.0, 20.0)
		print("dealer ", world.trip_status, " cargo ", v.cargo)
		print("passengers ", v.passengers.size(), " hires waiting ", world.hires_wanted, " workers ", world.workers.size(), " money ", world.money)
	for step in [[90.0, "11_cultivating"], [150.0, "12_seeding"], [200.0, "13_growing"], [180.0, "14_ripe"], [60.0, "15_harvesting"], [200.0, "16_after_harvest"]]:
		_simulate(step[0])
		await _shot(step[1], center, 50.0, 0.0)
		print(step[1], "  ", world.fields[0].status() if not world.fields.is_empty() else "", "  stock ", world.stock)
		var kinds := {}
		for t in world.tasks.tasks:
			var k := "%s%s" % [Task.Kind.keys()[t.kind], "*" if t.worker else ""]
			kinds[k] = kinds.get(k, 0) + 1
		var ph := []
		for w in world.workers:
			ph.append("%s@%s" % [Worker.Phase.keys()[w.phase], w.cell()])
		print("   tasks ", kinds, " workers ", ph, " seeds ", world.stock[&"seed_wheat"], "/", world.stock[&"seed_beet"])
		print("   money ", world.money, " pickup: ", world.trip_status, " alerts: ", world.alerts())
		if step[1] == "13_growing" or step[1] == "14_ripe":
			await _shot(step[1] + "_close", center + Vector3(-8, 0, 2), 22.0, 30.0)
		if step[1] == "11_cultivating":
			world.set_category_on(Task.Category.PLANTING, false)
			world.move_category(Task.Category.TRANSPORT, -4)
			_simulate(20.0)
			hud.toggle_priorities()
			await _shot("11b_priorities", center, 50.0, 0.0)
			print("planting off for 20 s: ", world.category_counts()[Task.Category.PLANTING], " order ", world.category_order, " alerts ", world.alerts())
			hud.toggle_priorities()
			world.reset_priorities()
		if step[1] == "15_harvesting" or step[1] == "14_ripe":
			var pusher: Worker = null
			for x in 600:
				for w in world.workers:
					if w.equipment == &"wheelbarrow" and w.carrying != &"" and w.is_walking():
						pusher = w
				if pusher:
					break
				_simulate(0.5)
			print("wheelbarrows in barn ", world.stock[&"wheelbarrow"], " pusher ", pusher.carrying if pusher else &"-", " ", pusher.carry_amount if pusher else 0.0)
			if pusher:
				hud.info.select(pusher)
				await _shot(step[1] + "_wheelbarrow", Vector3(pusher.pos.x, 0, pusher.pos.y) * Defs.TILE, 16.0, 30.0)
				hud.info.clear()
		if step[1] == "13_growing" and not world.fields.is_empty():
			world.set_field_crop(world.fields[0], &"corn")
			hud.info.select(world.fields[0])
			await _shot("13b_field_info", center, 50.0, 0.0)
			print("next crop ", world.fields[0].next_crop, " crop ", world.fields[0].crop)
	if world.fields.size() < 2:
		return
	print("field 0 crop after the cycle: ", world.fields[0].crop, " status ", world.fields[0].status())
	hud.info.select(world.workers[1])
	await _shot("17_worker_info", Vector3(world.workers[1].pos.x, 0, world.workers[1].pos.y) * Defs.TILE, 30.0, 0.0)
	for b: Building in world.buildings.values():
		if b.def_id == &"storage_barn":
			hud.info.select(b)
			print("barn blocker: '", world.demolish_blocker(b), "'")
			await _shot("18_barn_info", Defs.footprint_center(b.anchor, b.size), 40.0, 0.0)
			break
	# a bigger pile at a gate (below the pickup minimum): workers fetch wheelbarrows for it
	var f0 := world.fields[0]
	f0.pile += 250.0
	world._queue_hauls(f0, true)
	var pusher: Worker = null
	for x in 120:
		_simulate(0.5)
		for w in world.workers:
			if w.equipment == &"wheelbarrow" and w.carrying != &"":
				pusher = w
		if pusher:
			break
	print("big pile: pusher carries ", pusher.carry_amount if pusher else 0.0, " in barn ", world.stock[&"wheelbarrow"])
	if pusher:
		hud.info.select(pusher)
		await _shot("17b_wheelbarrow", Vector3(pusher.pos.x, 0, pusher.pos.y) * Defs.TILE, 16.0, 30.0)
		var yaw := rad_to_deg(-pusher.heading) + 90.0
		await _shot("17c_wheelbarrow_side", Vector3(pusher.pos.x, 0, pusher.pos.y) * Defs.TILE, 6.0, yaw)
	_simulate(90.0)
	print("after 90 s: pile ", f0.pile, " wheelbarrows in barn ", world.stock[&"wheelbarrow"])
	var f1 := world.fields[1]
	var before := world.money
	hud.info.select(f1)
	hud.info.press_action()
	await _shot("19_demolish_confirm", center, 50.0, 0.0)
	hud.info.press_action()
	print("demolished field: ", not world.fields.has(f1), " refund ", world.money - before, " paid ", f1.paid, " tasks left on it ",
		world.tasks.tasks.filter(func(t: Task) -> bool: return t.field == f1).size())
	_simulate(20.0)
	await _shot("20_after_demolish", center, 50.0, 0.0)


# --- save / load ---------------------------------------------------------------

func save_game(slot := "quicksave") -> void:
	var err := SaveGame.save(world, slot, {"camera": [rig.position, rig.camera.size, rad_to_deg(rig.rotation.y)]})
	if err != OK:
		hud.toast("Saving failed (%s)" % error_string(err))
	else:
		hud.toast("Game saved (F9 loads)" if slot == "quicksave" else "Autosaved")


## Loads the newest save (quicksave or autosave) by restarting the scene with it.
func load_game() -> void:
	var slot := "quicksave" if SaveGame.modified("quicksave") >= SaveGame.modified("autosave") else "autosave"
	if not SaveGame.exists(slot):
		hud.toast("No saved game yet (F5 saves)")
		return
	pending_load = slot
	get_tree().reload_current_scene()
