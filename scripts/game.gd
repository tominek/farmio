extends Node3D
## Game root: generates the world, wires presentation to the simulation and runs time.
##
## User args (after `--`):
##   --seed=<n>       map seed (default random)
##   --size=<n>       map size in tiles (default 256 = Small)
##   --shots=<dir>    run a scripted scenario, save screenshots, then quit

var world: World
var rig: CameraRig
var ground: GroundView
var tool: PlacementTool
var hud: Hud
var speed := 1.0
var paused := false

var _shots_dir := ""


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

	var t0 := Time.get_ticks_msec()
	world = WorldGen.generate(size, seed_value)
	print("world %d x %d seed %d generated in %d ms" % [size, size, seed_value, Time.get_ticks_msec() - t0])

	_setup_environment()
	rig = CameraRig.new()
	add_child(rig)
	rig.bounds = Rect2(0, 0, size * Defs.TILE, size * Defs.TILE)

	ground = GroundView.new()
	add_child(ground)
	ground.setup(world)
	for view: Node3D in [TreeView.new(), RoadView.new(), FieldView.new(), BuildingView.new(), WorkerView.new()]:
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

	rig.focus(_farm_center(), 50.0)
	print("setup done in %d ms" % (Time.get_ticks_msec() - t0))
	if _shots_dir != "":
		_run_shots()


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


func _step(dt: float) -> void:
	# large time steps (fast forward) are split so walking and work timers stay accurate
	var steps := maxi(1, ceili(dt / 0.05))
	for i in steps:
		world.tick(dt / steps)


func _unhandled_input(event: InputEvent) -> void:
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

	# place a barn in the forest edge next to the farm and a road towards it, then let workers work
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
	if placed.is_empty():
		return
	var center := Defs.footprint_center(placed[0].anchor, placed[0].size) + Vector3(18, 0, 0)
	await _shot("10_fields_placed", center, 50.0, 0.0)
	for step in [[90.0, "11_cultivating"], [150.0, "12_seeding"], [200.0, "13_growing"], [180.0, "14_ripe"], [60.0, "15_harvesting"], [200.0, "16_after_harvest"]]:
		_simulate(step[0])
		await _shot(step[1], center, 50.0, 0.0)
		print(step[1], "  ", world.fields[0].status() if not world.fields.is_empty() else "", "  stock ", world.stock)
		if step[1] == "13_growing" or step[1] == "14_ripe":
			await _shot(step[1] + "_close", center + Vector3(-8, 0, 2), 22.0, 30.0)
