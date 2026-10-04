extends Node3D
## Showcase of the models listed in scripts/tools/model_showcase.json (written by the Blender
## export scripts in art/blender/scripts/p2_*.py). Run scenes/model_showcase.tscn (F6).
## Animals are shown in every animation state: idle, walk, eat, sleep.
## Camera as in the game: WASD, Q / E, wheel or trackpad. 1-9 / Tab: jump to a category,
## Space pauses the animation.
##   --snap=<file>   save a screenshot and quit
##   --cat=<n> --zoom=<size> --yaw=<deg> --at=<x>,<z>   framing for --snap

const MANIFEST := "res://scripts/tools/model_showcase.json"
const GAP := 1.2
const ROW_GAP := 3.5
const STATES := [["Idle", AnimalFigure.Action.IDLE], ["Walk", AnimalFigure.Action.WALK],
	["Eat", AnimalFigure.Action.EAT], ["Sleep", AnimalFigure.Action.SLEEP]]
const WALK_RADIUS := 0.9
const FACING := 140.0            # models turned three-quarters towards the camera
const CATEGORY := {"Fruit trees": "Trees", "Tractors": "Vehicles", "Combines": "Vehicles", "Pickups": "Vehicles",
	"Trailers": "Trailers & attachments", "Attachments": "Trailers & attachments"}

var _animals: Array = []         # [figure, action, slot position, radius, phase]
var _categories: Array = []      # [name, position, largest model size]
var _cat_i := 0
var _time := 0.0
var _paused := false
var _rig: CameraRig
var _width := 0.0


func _ready() -> void:
	_environment()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var z := 0.0
	var category := ""
	for g: Dictionary in data["groups"]:
		var name: String = g["name"]
		var cat := name.get_slice(":", 0) if ":" in name else name
		cat = CATEGORY.get(cat, cat)
		if cat != category:
			category = cat
			z += 4.0
			_label(cat, Vector3(-1.5, 0.1, z), 160, Color(1, 0.95, 0.75), false)
			_categories.append([cat, Vector3(0, 0, z + 6), 1.0])
			z += 4.0
		z = _row(g, z)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(_width + 60, z + 30)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.5, 0.68, 0.33)
	gm.roughness = 1.0
	ground.material_override = gm
	ground.position = Vector3(_width * 0.5 - 20, -0.02, z * 0.5)
	add_child(ground)

	_rig = CameraRig.new()
	add_child(_rig)
	_rig.bounds = Rect2(-40, -20, _width + 60, z + 40)
	_focus(0)
	_rig.set_yaw_degrees(0.0)
	_hud()
	await _cmdline()


func _environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
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
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


## One group as a row of models (animals: a block of all states per variant). Returns the next z.
func _row(g: Dictionary, z: float) -> float:
	var models: Array = g["models"]
	var animals := not models.is_empty() and String(models[0][0]).begins_with("animal_")
	var sizes := []
	var depth := 2.0
	for m: Array in models:
		var box := _aabb(m[0])
		sizes.append(box)
		depth = maxf(depth, box.size.z + box.size.y * 0.6)   # tall models reach into the next row on screen
	var row_depth := depth + (WALK_RADIUS * 2.0 if animals else 0.0)
	z += row_depth * 0.5 + 1.0
	_label(String(g["name"]).get_slice(":", 1).strip_edges() if ":" in g["name"] else g["name"],
		Vector3(-1.5, 0.1, z), 72, Color.WHITE, false)
	var x := 0.0
	for i in models.size():
		var m: Array = models[i]
		var box: AABB = sizes[i]
		var w := maxf(box.size.x, 1.0)
		if animals:
			var step := maxf(w, box.size.z) + WALK_RADIUS * 2.0 + 0.6
			for s in STATES.size():
				var p := Vector3(x + step * 0.5, 0, z)
				var fig := AnimalFigure.new()
				add_child(fig)
				fig.setup(m[0])
				fig.position = p
				fig.rotation_degrees.y = FACING
				_animals.append([fig, STATES[s][1], p, WALK_RADIUS if STATES[s][1] == AnimalFigure.Action.WALK else 0.0, randf() * 10.0])
				_label("%s · %s" % [m[1], STATES[s][0]], p + Vector3(0, 0.05, row_depth * 0.5 + 0.2), 28, Color.WHITE, false)
				x += step
			x += GAP * 2.0
		else:
			var mi := Models.instance(m[0])
			# turned around so the front (-Z) faces the camera
			mi.rotation.y = PI
			mi.position = Vector3(x + w * 0.5 + box.get_center().x, 0, z + box.get_center().z)
			add_child(mi)
			_label(m[1], Vector3(x + w * 0.5, 0.05, z + depth * 0.5 + 0.5), 32, Color.WHITE, false)
			x += w + GAP
	_width = maxf(_width, x)
	for box: AABB in sizes:
		_categories[-1][2] = maxf(_categories[-1][2], maxf(box.size.x, box.size.z))
	return z + row_depth * 0.5 + ROW_GAP


func _aabb(model: String) -> AABB:
	if model.begins_with("animal_"):
		var box := AABB()
		var first := true
		for part: Array in Models.parts(model).values():
			var b: AABB = (part[0] as Mesh).get_aabb()
			b.position += part[1]
			box = b if first else box.merge(b)
			first = false
		return box
	return Models.mesh(model).get_aabb()


func _label(text: String, pos: Vector3, size: int, color: Color, billboard: bool) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.outline_size = maxi(4, size / 6)
	l.modulate = color
	l.pixel_size = 0.01
	# row and category titles end left of the models
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if size >= 72 else HORIZONTAL_ALIGNMENT_CENTER
	if billboard:
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	else:
		l.rotation_degrees.x = -90.0       # lying on the ground, readable from the game camera
	l.position = pos
	add_child(l)


func _hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var l := Label.new()
	var lines := ["Model showcase — WASD move, Q/E rotate, wheel zoom, Space pause, Tab next"]
	for i in _categories.size():
		lines.append("%d  %s" % [i + 1, _categories[i][0]])
	l.text = "\n".join(lines)
	l.position = Vector2(12, 10)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	layer.add_child(l)


func _focus(i: int) -> void:
	if _categories.is_empty():
		return
	_cat_i = posmod(i, _categories.size())
	var p: Vector3 = _categories[_cat_i][1]
	var zoom := clampf(_categories[_cat_i][2] * 3.5, 24.0, 60.0)
	_rig.focus(Vector3(p.x + zoom * 0.3, 0, p.z + zoom * 0.25), zoom)


func _cmdline() -> void:
	var snap := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cat="):
			_focus(int(arg.trim_prefix("--cat=")) - 1)
		elif arg.begins_with("--at="):
			var v := arg.trim_prefix("--at=").split(",")
			_rig.focus(Vector3(float(v[0]), 0, float(v[1])))
		elif arg.begins_with("--zoom="):
			_rig.focus(_rig.position, float(arg.trim_prefix("--zoom=")))
		elif arg.begins_with("--yaw="):
			_rig.set_yaw_degrees(float(arg.trim_prefix("--yaw=")))
		elif arg.begins_with("--time="):
			_time = float(arg.trim_prefix("--time="))
		elif arg.begins_with("--snap="):
			snap = arg.trim_prefix("--snap=")
	if snap != "":
		for i in 30:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(snap)
		get_tree().quit()


func _process(delta: float) -> void:
	if not _paused:
		_time += delta
	for a in _animals:
		var fig: AnimalFigure = a[0]
		var t: float = _time + a[4]
		if a[3] > 0.0:
			# walkers circle around their slot, facing along the path
			var speed := 0.45 if fig.bird else 0.35
			var ang := t * speed
			fig.position = (a[2] as Vector3) + Vector3(cos(ang), 0, sin(ang)) * a[3]
			fig.rotation.y = -ang + PI
		fig.pose(a[1], t, delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var k := (event as InputEventKey).keycode
		if k == KEY_SPACE:
			_paused = not _paused
		elif k == KEY_TAB:
			_focus(_cat_i + 1)
		elif k >= KEY_1 and k <= KEY_9:
			_focus(k - KEY_1)
