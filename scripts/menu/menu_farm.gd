class_name MenuFarm
extends Node3D
## The live farm behind the main menu: a small generated map with a few fields and a mill, made
## and run ahead a little on a thread, then shown with the normal views, ticking at 2x under a
## slowly orbiting camera.

const SEED := 7
const SIZE := 128
const PREWARM := 300.0              # game seconds run before the farm is shown
const SPEED := 2.0
const ORBIT := 2.5                  # degrees per second

signal ready_to_show

var world: World
var camera: Camera3D
var _thread: Thread
var _center := Vector3.ZERO
var _yaw := 30.0
var _running := false


func _ready() -> void:
	_setup_environment()
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 62.0
	camera.near = 1.0
	camera.far = 800.0
	add_child(camera)
	_place_camera()
	_thread = Thread.new()
	_thread.start(_build)


## On the thread: the map, the farm and the first minutes of work. Touches no nodes.
func _build() -> void:
	var w := WorldGen.generate(SIZE, SEED)
	w.money += 20000
	for id: StringName in Tech.NODES:
		w.unlock(id)
	w.stock[&"planks"] = 120.0
	w.stock[&"wheat"] = 200.0
	for crop: StringName in Defs.CROPS:
		w.stock[Defs.seed_of(crop)] = Defs.seed_per_tile(crop) * 80.0
	var c := _barn_cell(w)
	var crops := Defs.CROPS.keys()
	var placed := 0
	for r in range(4, 30):
		for dx in range(-r, r + 1, 2):
			for dy in [r, -r]:
				var a: Vector2i = c + Vector2i(dx, dy)
				if placed < 3 and w.place_site(&"field", a, 0, Vector2i(7, 5), crops[placed % crops.size()]):
					placed += 1
	for r in range(4, 30):
		var done := false
		for dx in range(-r, r + 1):
			var a: Vector2i = c + Vector2i(dx, r)
			if not done and w.can_place(&"hand_mill", a, 2):
				var b := w.add_building(&"hand_mill", a, 2)
				for cell in b.cells():
					if w.has_tree(cell):
						w.remove_tree(cell)
				done = true
		if done:
			break
	w.hire(2)
	var t := 0.0
	while t < PREWARM:
		w.tick(0.1)
		t += 0.1
	world = w


func _barn_cell(w: World) -> Vector2i:
	for b: Building in w.buildings.values():
		if b.def_id == &"storage_barn":
			return b.anchor + Vector2i(4, 3)
	return Vector2i(w.size / 2, w.size / 2)


func _process(delta: float) -> void:
	if not _running:
		if _thread.is_started() and not _thread.is_alive():
			_thread.wait_to_finish()
			_show_world()
		return
	_yaw += ORBIT * delta
	_place_camera()


func _physics_process(delta: float) -> void:
	if not _running:
		return
	var dt := delta * SPEED
	var steps := maxi(1, ceili(dt / 0.05))
	for i in steps:
		world.tick(dt / steps)


func _show_world() -> void:
	var ground := GroundView.new()
	add_child(ground)
	ground.setup(world)
	for view: Node3D in [WaterView.new(), TreeView.new(), RoadView.new(), FieldView.new(), BuildingView.new(), VehicleView.new(), WorkerView.new()]:
		add_child(view)
		view.setup(world)
	var c := _barn_cell(world)
	_center = Vector3((c.x + 2) * Defs.TILE, 0, (c.y + 4) * Defs.TILE)
	_running = true
	_place_camera()
	ready_to_show.emit()


## Orbit around the farm; the view is shifted so the farm sits right of the menu.
func _place_camera() -> void:
	var tilt := deg_to_rad(45.0)
	var yaw := deg_to_rad(_yaw)
	var back := Vector3(sin(yaw), 0, cos(yaw)) * 160.0 * cos(tilt)
	camera.position = _center + back + Vector3(0, 160.0 * sin(tilt), 0)
	camera.look_at(_center, Vector3.UP)
	camera.h_offset = -camera.size * 0.32


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
	env.background_color = UiStyle.GRASS
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.74, 0.88)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _exit_tree() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
