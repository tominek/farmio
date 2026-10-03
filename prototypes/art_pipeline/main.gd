extends Node3D
## Art pipeline test: Blender GLBs in Godot with the game camera, the shared
## palette material and continuous wheat growth on a MultiMesh.
##
## User args (after `--`):
##   --shots=<dir>    save screenshots from several camera angles, then quit
##   --perf=<n>       build an n x n wheat field only, print FPS and primitives, then quit

const MODELS := "res://models/"
const TILE := 3.0
const ROW_OFFSETS: PackedFloat32Array = [-1.2, -0.6, 0.0, 0.6, 1.2]

var palette_mat: StandardMaterial3D
var wheat_mat: ShaderMaterial
var cam_pivot: Node3D
var camera: Camera3D
var wheat_mm: MultiMesh
var wheat_order: PackedFloat32Array
var growth_time := 0.0
var growth_speed := 0.05

var shots_dir := ""
var perf_size := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots_dir = arg.trim_prefix("--shots=")
		elif arg.begins_with("--perf="):
			perf_size = int(arg.trim_prefix("--perf="))

	palette_mat = StandardMaterial3D.new()
	palette_mat.albedo_texture = load("res://palette.png")
	palette_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	palette_mat.roughness = 1.0
	palette_mat.metallic_specular = 0.0

	wheat_mat = ShaderMaterial.new()
	wheat_mat.shader = load("res://wheat.gdshader")

	_setup_environment()
	_setup_camera()

	if perf_size > 0:
		_build_wheat_field(Vector3(0, 0, 0), perf_size, perf_size)
		cam_pivot.position = Vector3(perf_size * TILE * 0.5, 0, -perf_size * TILE * 0.5)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		camera.size = perf_size * TILE * 1.1
		_set_field_growth_uniform(1.0)
		_run_perf()
		return

	_build_scene()
	if shots_dir != "":
		_take_shots()


func _process(delta: float) -> void:
	if shots_dir != "" or perf_size > 0:
		return
	growth_time += delta * growth_speed
	_update_field_growth(growth_time)
	var rot := 0.0
	if Input.is_key_pressed(KEY_Q):
		rot += 1.0
	if Input.is_key_pressed(KEY_E):
		rot -= 1.0
	cam_pivot.rotate_y(rot * delta * 1.5)
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		move.z -= 1
	if Input.is_key_pressed(KEY_S):
		move.z += 1
	if Input.is_key_pressed(KEY_A):
		move.x -= 1
	if Input.is_key_pressed(KEY_D):
		move.x += 1
	cam_pivot.position += cam_pivot.basis * move * delta * camera.size * 0.6


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.size = max(8.0, camera.size * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.size = min(200.0, camera.size * 1.1)
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		cam_pivot.rotate_y(-event.relative.x * 0.005)


# --- environment & camera -------------------------------------------------

func _setup_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 250.0
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

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("86B85A")
	gm.roughness = 1.0
	gm.metallic_specular = 0.0
	ground.material_override = gm
	ground.position.y = -0.02
	add_child(ground)


func _setup_camera() -> void:
	cam_pivot = Node3D.new()
	add_child(cam_pivot)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 60.0
	camera.far = 600.0
	var dist := 120.0
	camera.rotation_degrees.x = -45.0
	camera.position = Vector3(0, dist * sin(deg_to_rad(45.0)), dist * cos(deg_to_rad(45.0)))
	cam_pivot.add_child(camera)
	cam_pivot.position = Vector3(6, 0, -10)
	cam_pivot.rotation_degrees.y = -35.0


# --- scene -----------------------------------------------------------------

func _place(model: String, pos: Vector3, rot_y := 0.0, scale_f := 1.0) -> Node3D:
	var node: Node3D = load(MODELS + model + ".glb").instantiate()
	node.position = pos
	node.rotation_degrees.y = rot_y
	node.scale = Vector3.ONE * scale_f
	_apply_palette(node)
	add_child(node)
	return node


func _apply_palette(node: Node) -> void:
	if node is MeshInstance3D:
		node.material_override = palette_mat
	for child in node.get_children():
		_apply_palette(child)


func _build_scene() -> void:
	# buildings (access point faces -Z = towards the road)
	_place("building_storage_barn_eu", Vector3(0, 0, 0))
	_place("building_dealer", Vector3(24, 0, 1.5))
	_place("building_garage", Vector3(-16, 0, 1.5))
	# two-way dirt road along X in front of the buildings
	for i in range(-4, 7):
		_place("road_dirt_twoway_straight", Vector3(i * 6.0 + 3.0, 0, -7.5), 90)
	_place("road_dirt_twoway_t", Vector3(9.0, 0, -7.5), 90)
	for j in range(1, 3):
		_place("road_dirt_twoway_straight", Vector3(9.0, 0, -7.5 - j * 6.0))
	# vehicles, workers, props
	_place("vehicle_pickup_light", Vector3(-4, 0, -6), -90)
	_place("worker_male", Vector3(2.5, 0, -5.4), 160)
	_place("worker_female", Vector3(-1.5, 0, -5.6), 200)
	_place("worker_male_var", Vector3(14, 0, -9), 90)
	_place("worker_female_var", Vector3(21, 0, -26), 20)
	_place("tool_wheelbarrow", Vector3(5.2, 0, -4.9), 180)
	_place("prop_log_pile", Vector3(-8.0, 0, -3.0), 90)
	# trees west of the farm
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var trees := ["tree_deciduous_full", "tree_deciduous_full", "tree_conifer_full", "tree_conifer_full", "tree_deciduous_small", "tree_conifer_small", "tree_stump"]
	for ix in range(-14, -8):
		for iz in range(-8, 6):
			if rng.randf() < 0.45:
				_place(trees[rng.randi() % trees.size()], Vector3(ix * TILE + rng.randf_range(-0.6, 0.6), 0, iz * TILE + rng.randf_range(-0.6, 0.6)), rng.randf_range(0, 360), rng.randf_range(0.9, 1.12))
	# grass tufts
	var tufts := ["grass_tuft_a", "grass_tuft_b", "grass_tuft_a", "grass_flowers_yellow"]
	for i in 260:
		var p := Vector3(rng.randf_range(-45, 60), 0, rng.randf_range(-60, 30))
		if _is_free(p):
			_place(tufts[rng.randi() % tufts.size()], p, rng.randf_range(0, 360), rng.randf_range(1.5, 2.3))
	# wheat field across the road: 14 x 10 tiles, fenced, gate towards the road
	var origin := Vector3(12.0, 0, -12.0)    # north-west corner (x grows east, -z grows away from the road)
	_build_wheat_field(origin, 14, 10)
	_build_fence(origin, 14, 10, 0)


func _is_free(p: Vector3) -> bool:
	var blocked := [
		Rect2(-7, -6, 14, 11), Rect2(17, -5, 14, 14), Rect2(-25, -6, 18, 14),
		Rect2(-15, -11, 54, 7), Rect2(5.5, -31, 7, 22), Rect2(11.5, -43, 43, 32), Rect2(-44, -26, 18, 46)]
	for r in blocked:
		if r.has_point(Vector2(p.x, p.z)):
			return false
	return true


# --- wheat field -------------------------------------------------------------

func _build_wheat_field(origin: Vector3, w: int, h: int) -> void:
	# soil + furrows
	var soil := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(w * TILE, 0.06, h * TILE)
	soil.mesh = box
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color("7A5236")
	sm.roughness = 1.0
	sm.metallic_specular = 0.0
	soil.material_override = sm
	soil.position = origin + Vector3(w * TILE * 0.5, 0.03, -h * TILE * 0.5)
	add_child(soil)
	var furrow_mm := MultiMesh.new()
	furrow_mm.transform_format = MultiMesh.TRANSFORM_3D
	var fbox := BoxMesh.new()
	fbox.size = Vector3(0.28, 0.06, h * TILE - 0.04)
	furrow_mm.mesh = fbox
	furrow_mm.instance_count = w * 5
	for i in w * 5:
		var x: float = origin.x + (i / 5) * TILE + 1.5 + ROW_OFFSETS[i % 5]
		furrow_mm.set_instance_transform(i, Transform3D(Basis(), Vector3(x, 0.08, origin.z - h * TILE * 0.5)))
	var furrows := MultiMeshInstance3D.new()
	furrows.multimesh = furrow_mm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("5C3D28")
	fm.roughness = 1.0
	fm.metallic_specular = 0.0
	furrows.material_override = fm
	add_child(furrows)

	# wheat tiles
	var src: Node = load(MODELS + "crop_wheat_full.glb").instantiate()
	var mesh: Mesh = _find_mesh(src)
	src.free()
	wheat_mm = MultiMesh.new()
	wheat_mm.transform_format = MultiMesh.TRANSFORM_3D
	wheat_mm.use_custom_data = true
	wheat_mm.mesh = mesh
	wheat_mm.instance_count = w * h
	wheat_order = PackedFloat32Array()
	wheat_order.resize(w * h)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for ix in w:
		for iz in h:
			var i := ix * h + iz
			var flip := Basis(Vector3.UP, PI) if rng.randf() < 0.5 else Basis()
			var pos := origin + Vector3(ix * TILE + 1.5, 0, -(iz * TILE + 1.5))
			wheat_mm.set_instance_transform(i, Transform3D(flip, pos))
			# seeding order: snake pattern like a tractor going up and down the columns
			var step := ix * h + (iz if ix % 2 == 0 else h - 1 - iz)
			wheat_order[i] = float(step) / float(w * h)
			wheat_mm.set_instance_custom_data(i, Color(0, 0, 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = wheat_mm
	mmi.material_override = wheat_mat
	add_child(mmi)


func _find_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D:
		return node.mesh
	for child in node.get_children():
		var m := _find_mesh(child)
		if m:
			return m
	return null


func _update_field_growth(t: float) -> void:
	# the field was seeded progressively; every tile grows at the same speed afterwards
	var cycle := fmod(t, 1.6)
	for i in wheat_mm.instance_count:
		var g := clampf(cycle - wheat_order[i] * 0.5, 0.0, 1.0)
		wheat_mm.set_instance_custom_data(i, Color(g, 0, 0, 0))


func _set_field_growth_uniform(g: float) -> void:
	for i in wheat_mm.instance_count:
		wheat_mm.set_instance_custom_data(i, Color(g, 0, 0, 0))


func _build_fence(origin: Vector3, w: int, h: int, gate_ix: int) -> void:
	for ix in w:
		var x := origin.x + ix * TILE + 1.5
		_place("fence_gate" if ix == gate_ix else "fence_segment", Vector3(x, 0, origin.z))
		_place("fence_segment", Vector3(x, 0, origin.z - h * TILE))
	for iz in h:
		var z := origin.z - iz * TILE - 1.5
		_place("fence_segment", Vector3(origin.x, 0, z), 90)
		_place("fence_segment", Vector3(origin.x + w * TILE, 0, z), 90)
	for c in [Vector3(origin.x + w * TILE, 0, origin.z), Vector3(origin.x + w * TILE, 0, origin.z - h * TILE), Vector3(origin.x, 0, origin.z - h * TILE)]:
		_place("fence_corner", c)


# --- screenshots & perf --------------------------------------------------------

func _take_shots() -> void:
	DirAccess.make_dir_recursive_absolute(shots_dir)
	var views := [
		["overview_a", Vector3(6, 0, -10), 95.0, -35.0, 0.62],
		["overview_b", Vector3(6, 0, -10), 95.0, 145.0, 0.62],
		["game_zoom", Vector3(4, 0, -4), 42.0, -30.0, 0.62],
		["field_growth", Vector3(33, 0, -27), 46.0, -20.0, 0.62],
		["field_ripe", Vector3(33, 0, -27), 46.0, -20.0, 1.55],
		["closeup_buildings", Vector3(14, 0, -2), 26.0, 155.0, 0.62],
	]
	for v in views:
		cam_pivot.position = v[1]
		camera.size = v[2]
		cam_pivot.rotation_degrees.y = v[3]
		_update_field_growth(v[4])
		for f in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(shots_dir.path_join("godot_" + v[0] + ".png"))
		print("saved ", v[0])
	get_tree().quit()


func _run_perf() -> void:
	for f in 30:
		await get_tree().process_frame
	var samples := 0.0
	var n := 0
	for f in 120:
		await get_tree().process_frame
		samples += 1000.0 * get_process_delta_time()
		n += 1
	var img := get_viewport().get_texture().get_image()
	img.save_png("/tmp/farmio_perf_%d.png" % perf_size)
	var prims := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var calls := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	print("PERF field=%dx%d tiles=%d avg_frame_ms=%.2f primitives=%d draw_calls=%d" % [perf_size, perf_size, perf_size * perf_size, samples / n, prims, calls])
	get_tree().quit()
