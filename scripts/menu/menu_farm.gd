class_name MenuFarm
extends Node3D
## The live farm behind the main menu: a small generated map with a farm some hours into
## a game, made and run ahead a little on a thread, then shown with the normal views, ticking at 2x under a
## slowly orbiting camera.

const SEED := 7
const SIZE := 128
const PREWARM := 600.0              # game seconds run before the farm is shown
const FIELDS := 6
const GRAVEL_BLOCKS := 6
const EXTRA_WORKERS := 6
## Buildings of a farm well into the game (see _build).
const SHOWCASE: Array[StringName] = [&"hand_mill", &"sawmill", &"water_mill", &"garage"]
const SPEED := 2.0
const ORBIT := 2.5                  # degrees per second
const ROAD_PILE_RESTOCK := 60.0     # game seconds between topping up the demo road piles
## Extra road blocks laid beyond the generated map's farthest connected one, so the walk from the
## demo road piles to the barn clears the cost model's break-even for the pickup (not just
## Defs.ROUTE_MIN_WALK: with both ends already vehicle stops, a direct walk is cheaper than a ride
## up to roughly 80 tiles — the two fixed handlings and the wait outweigh a short drive). Cheap:
## a few dozen road tiles, done once, no new trees or buildings nearby to clear but stray ones.
const ROAD_PILE_EXTEND := 16
const ROAD_PILE_SETTLE_MAX := 120.0 # game seconds _build may run past PREWARM waiting for a driver
const CAMERA_SIZE := 70.0           # a little wider than the barn close-up so the garage and the
                                     # road leaving towards the piles both stay in view

signal ready_to_show

var world: World
var camera: Camera3D
var _thread: Thread
var _center := Vector3.ZERO
var _yaw := 30.0
var _running := false
var _road_pile_cells: Dictionary = {}   # resource -> cell, the pickup's two demo road piles
var _restock_t := 0.0
var _view_center := Vector2.ZERO        # grid coords midway between the barn and the road piles


func _ready() -> void:
	_setup_environment()
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = CAMERA_SIZE
	camera.near = 1.0
	camera.far = 800.0
	add_child(camera)
	_place_camera()
	_thread = Thread.new()
	_thread.start(_build)


## On the thread: a farm some hours into a game, so the menu shows what the game grows into —
## fields of every crop, the mills and the sawmill at work, gravel roads, a crew of workers with
## wheelbarrows. Built at once (World.instant_build), then run ahead. Touches no nodes.
## Keep SHOWCASE up to date: new buildings and machines (tractors, carts, combines…) belong here.
func _build() -> void:
	var t0 := Time.get_ticks_msec()
	var w := WorldGen.generate(SIZE, SEED)
	w.unlock_all()
	w.instant_build = true
	var c := _barn_cell(w)
	var crops := Defs.CROPS.keys()
	var fields := 0
	for r in range(4, 40):
		for dx in range(-r, r + 1, 2):
			for dy in [r, -r]:
				var a: Vector2i = c + Vector2i(dx, dy)
				var rect := Rect2i(a, Vector2i(7, 5))
				var side := w.field_gate_side(rect)      # the gate towards the road, as when drawn in the game
				if fields < FIELDS and w.place_site(&"field", a, side, Defs.rotated(rect.size, side), crops[fields % crops.size()]):
					fields += 1
	for id: StringName in SHOWCASE:
		_place_near(w, id, c)
	# the road blocks nearest the barn get gravel
	var blocks: Array = w.road_blocks.keys()
	blocks.sort_custom(func(p: Vector2i, q: Vector2i) -> bool: return p.distance_squared_to(c) < q.distance_squared_to(c))
	for a: Vector2i in blocks.slice(0, GRAVEL_BLOCKS):
		w.place_site(&"road_gravel", a, 0)
	w.instant_build = false
	var looks := Worker.Look.values()
	for i in EXTRA_WORKERS:
		w.add_worker(c, looks[i % looks.size()])
	w.set_stock(&"wheelbarrow", 2.0)
	w.set_stock(&"wheat", 300.0)
	w.set_stock(&"wood", 12.0)
	w.set_stock(&"planks", 60.0)
	for crop: StringName in Defs.CROPS:
		w.set_stock(Defs.seed_of(crop), Defs.seed_per_tile(crop) * 120.0)
	w.money += 5000
	# the pickup earns its keep: two road piles down a spur laid past the far end of the generated
	# road (_extend_road), far enough that the planner routes them via the pickup instead of a
	# walking leg, re-stocked while the farm runs. The camera leans a little off the barn towards the road
	# leaving for the piles (_view_center), enough to catch the pickup coming and going.
	var near_block: Vector2i = _extend_road(w, blocks.back(), c, ROAD_PILE_EXTEND)
	_view_center = Vector2(c).lerp(Vector2(near_block), 0.12)   # mostly the barn; a hint of the road out
	_road_pile_cells = _seed_road_piles(w, near_block)
	var t := 0.0
	var restock_at := ROAD_PILE_RESTOCK
	while t < PREWARM:
		w.tick(0.1)
		t += 0.1
		if t >= restock_at:
			_restock_piles(w)
			restock_at += ROAD_PILE_RESTOCK
	# the dispatcher alternates the pickup between rides and a driver-less wait (TASK_AGING); run a
	# little past PREWARM, if need be, so the farm is shown with the pickup out, not mid-wait.
	var settle := 0.0
	while settle < ROAD_PILE_SETTLE_MAX and _vehicle_idle(w):
		w.tick(0.1)
		settle += 0.1
	print("MenuFarm._build: %d ms (prewarm %.0f game s + %.0f settle)" % [Time.get_ticks_msec() - t0, PREWARM, settle])
	world = w


## On the nearest free spot around `c` (any turn); a water mill only fits on a river bank and is
## left out when the river runs off this small map.
func _place_near(w: World, id: StringName, c: Vector2i) -> void:
	for r in range(5, 50):
		for dy in range(-r, r + 1):
			var xs: Array = range(-r, r + 1) if absi(dy) == r else [-r, r]
			for dx: int in xs:
				for rot in 4:
					if w.place_site(id, c + Vector2i(dx, dy), rot):
						return


func _barn_cell(w: World) -> Vector2i:
	for b: Building in w.buildings.values():
		if b.def_id == &"storage_barn":
			return b.anchor + Vector2i(4, 3)
	return Vector2i(w.size / 2, w.size / 2)


## Lays `steps` more road blocks past `from`, straight on from `away` (the barn, so the spur keeps
## leading farther from it rather than turning back), clearing any trees in the way; returns the
## new far end. Run once, on the build thread, before any worker or view exists — the map stays
## SIZE, only its road grows a dead-end spur past the generated one so the demo road piles are far
## enough down it for the pickup to be worth it (see ROAD_PILE_EXTEND).
func _extend_road(w: World, from: Vector2i, away: Vector2i, steps: int) -> Vector2i:
	var d := from - away
	var dir := Vector2i(0, signi(d.y)) if absi(d.x) < absi(d.y) else Vector2i(signi(d.x), 0)
	if dir == Vector2i.ZERO:
		dir = Vector2i(0, 1)
	var b := from
	for i in steps:
		var nb := b + dir * Defs.ROAD_BLOCK
		if not w.in_bounds(nb) or not w.in_bounds(nb + Vector2i(Defs.ROAD_BLOCK - 1, Defs.ROAD_BLOCK - 1)):
			break
		for y in Defs.ROAD_BLOCK:
			for x in Defs.ROAD_BLOCK:
				var cc := nb + Vector2i(x, y)
				if w.has_tree(cc):
					w.remove_tree(cc)
		if not w.road_blocks.has(nb):
			w.add_road_block(nb, &"dirt")
		b = nb
	return b


## Two road piles (logs, wheat sacks) by the road near `near`. Returns the cells used, so
## _restock_piles can find them again. `near` already lies on a road connected to the pickup's
## garage (the far end of the spur laid by _extend_road), so road_pile_spot finds a free tile right
## away — cheap, done once.
func _seed_road_piles(w: World, near: Vector2i) -> Dictionary:
	var cells := {}
	for res: StringName in [&"wood", &"wheat"]:
		var spot: Variant = w.road_pile_spot(near)
		if spot == null:
			continue
		var pile := w.add_road_pile(spot, res, Task.Category.TRANSPORT)
		pile.put(res, Defs.GROUND_PILE_CAPACITY * 0.6)
		cells[res] = spot
	return cells


## Tops the demo road piles back up once the pickup has mostly cleared them, so a new multi-stop
## run keeps coming up instead of the pickup parking for good after the first one. Cheap: two
## dictionary lookups and a put() every ROAD_PILE_RESTOCK game seconds.
func _restock_piles(w: World) -> void:
	for res: StringName in _road_pile_cells:
		var cell: Vector2i = _road_pile_cells[res]
		var pile: Store = w.ground_pile_at(cell)
		if pile == null:
			pile = w.add_road_pile(cell, res, Task.Category.TRANSPORT)
		elif pile.amount(res) > Defs.GROUND_PILE_CAPACITY * 0.3:
			continue
		var n := minf(Defs.GROUND_PILE_CAPACITY * 0.6, pile.room())
		if n > 0.5:
			pile.put(res, n)
			w.pile_changed.emit(pile)


## True while the pickup is parked or sitting on an assembled trip with nobody driving it yet
## (the farm's workers are busy elsewhere and Transport hasn't aged past them) — the uninteresting
## moments to catch it at.
func _vehicle_idle(w: World) -> bool:
	var s := w.vehicles[0].status if not w.vehicles.is_empty() else ""
	return s == "In the garage" or s.begins_with("Waiting")


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
	_restock_t += dt
	if _restock_t >= ROAD_PILE_RESTOCK:
		_restock_t = 0.0
		_restock_piles(world)


func _show_world() -> void:
	var ground := GroundView.new()
	add_child(ground)
	ground.setup(world)
	for view: Node3D in [WaterView.new(), TreeView.new(), RoadView.new(), FieldView.new(), BuildingView.new(), PileView.new(), VehicleView.new(), WorkerView.new()]:
		add_child(view)
		view.setup(world)
	_center = Vector3((_view_center.x + 2) * Defs.TILE, 0, (_view_center.y + 4) * Defs.TILE)
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
