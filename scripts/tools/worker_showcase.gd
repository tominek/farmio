extends Node3D
## Showcase of all worker looks in every animation state. Run scenes/worker_showcase.tscn (F6).
## Camera as in the game: WASD, Q / E, wheel or trackpad; Space pauses the animation.
##   --snap=<file>   save a screenshot and quit
##   --column=<n> --zoom=<size> --time=<s> --yaw=<deg>   look at one column (for checking a pose)

const COLUMNS := [
	["Idle", WorkerFigure.Action.IDLE, false, &""],
	["Walk", WorkerFigure.Action.WALK, true, &""],
	["Walk with seed", WorkerFigure.Action.WALK, true, &"seed_wheat"],
	["Carry logs", WorkerFigure.Action.CARRY, true, &"wood"],
	["Carry crate", WorkerFigure.Action.CARRY, true, &"potato"],
	["Carry sack", WorkerFigure.Action.CARRY, true, &"wheat"],
	["Wheelbarrow", WorkerFigure.Action.PUSH, true, &"potato"],
	["Chop", WorkerFigure.Action.CHOP, false, &""],
	["Build", WorkerFigure.Action.BUILD, false, &""],
	["Hoe (cultivate)", WorkerFigure.Action.HOE, false, &""],
	["Sow", WorkerFigure.Action.SOW, false, &"seed_wheat"],
	["Harvest", WorkerFigure.Action.HARVEST, false, &""],
	["Pick up", WorkerFigure.Action.PICK_UP, false, &""],
]
const LOOKS := [Worker.Look.MALE, Worker.Look.FEMALE, Worker.Look.MALE_VAR, Worker.Look.FEMALE_VAR]
const SPACING := Vector2(2.6, 3.2)
const FACING := -70.0            # figures turned sideways so arm swings read well from the camera

var _figures: Array = []        # [figure, column]
var _time := 0.0
var _paused := false


func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.74, 0.88)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.74, 0.88)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(COLUMNS.size() * SPACING.x + 4, LOOKS.size() * SPACING.y + 4)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.45, 0.62, 0.3)
	ground.material_override = gm
	ground.position = Vector3((COLUMNS.size() - 1) * SPACING.x * 0.5, 0, (LOOKS.size() - 1) * SPACING.y * 0.5)
	add_child(ground)

	for ci in COLUMNS.size():
		var label := Label3D.new()
		label.text = COLUMNS[ci][0]
		label.font_size = 48
		label.outline_size = 10
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(ci * SPACING.x, 2.9, -1.4)
		add_child(label)
		for li in LOOKS.size():
			var fig := WorkerFigure.new()
			add_child(fig)
			fig.setup(LOOKS[li])
			fig.position = Vector3(ci * SPACING.x, 0, li * SPACING.y)
			fig.rotation_degrees.y = FACING
			_figures.append([fig, ci])
		if COLUMNS[ci][1] == WorkerFigure.Action.CHOP:
			for li in LOOKS.size():
				var tree := Models.instance("tree_conifer_full")
				# in front of the figure
				tree.position = Vector3(ci * SPACING.x, 0, li * SPACING.y) + Basis.from_euler(Vector3(0, deg_to_rad(FACING), 0)) * Vector3(0, 0, -1.75)
				tree.scale = Vector3.ONE * 0.5
				add_child(tree)

	var rig := CameraRig.new()
	add_child(rig)
	rig.bounds = Rect2(-10, -10, COLUMNS.size() * SPACING.x + 20, LOOKS.size() * SPACING.y + 20)
	rig.focus(Vector3((COLUMNS.size() - 1) * SPACING.x * 0.5, 0, (LOOKS.size() - 1) * SPACING.y * 0.5), 20.0)
	rig.set_yaw_degrees(0.0)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--column="):
			rig.focus(Vector3(int(arg.trim_prefix("--column=")) * SPACING.x, 0, (LOOKS.size() - 1) * SPACING.y * 0.5))
		elif arg.begins_with("--zoom="):
			rig.focus(rig.position, float(arg.trim_prefix("--zoom=")))
		elif arg.begins_with("--yaw="):
			rig.set_yaw_degrees(float(arg.trim_prefix("--yaw=")))
		elif arg.begins_with("--time="):
			_time = float(arg.trim_prefix("--time="))
			_paused = true

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snap="):
			for i in 20:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--snap="))
			get_tree().quit()


func _process(delta: float) -> void:
	if not _paused:
		_time += delta
	for f in _figures:
		var col: Array = COLUMNS[f[1]]
		(f[0] as WorkerFigure).pose(col[1], _time + f[1] * 0.13, col[2], col[3])


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		_paused = not _paused
