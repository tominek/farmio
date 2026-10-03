class_name Worker
extends RefCounted
## A worker unit: picks tasks from the queue, walks, works and delivers output.

enum Phase { IDLE, TO_FETCH, TO_TASK, WORKING, TO_DELIVER }
enum Look { MALE, FEMALE, MALE_VAR, FEMALE_VAR }

var id: int
var look: Look
var pos: Vector2            # in tile units (cell centre = cell + 0.5)
var heading := 0.0          # radians, 0 = facing grid -y
var phase := Phase.IDLE
var task: Task = null
var carrying := &""         # resource carried by hand
var carry_amount := 0.0
var work_timer := 0.0
var strip_i := 0            # FIELD tasks: index of the cell being worked
var in_vehicle := false
var path: Array[Vector2i] = []
var path_i := 0
var _poll := 0.0


func _init(p_id: int, p_cell: Vector2i, p_look: Look) -> void:
	id = p_id
	look = p_look
	pos = Vector2(p_cell) + Vector2(0.5, 0.5)


func cell() -> Vector2i:
	return Vector2i(floori(pos.x), floori(pos.y))


func is_walking() -> bool:
	return phase == Phase.TO_FETCH or phase == Phase.TO_TASK or phase == Phase.TO_DELIVER


func set_path(p: Array[Vector2i]) -> void:
	path = p
	path_i = 0


func tick(world: World, dt: float) -> void:
	match phase:
		Phase.IDLE:
			if in_vehicle:
				return          # a passenger: rides along until dropped off
			_poll -= dt
			if _poll <= 0.0:
				_poll = 0.5
				task = world.tasks.pick(world, self)
				if task:
					phase = Phase.TO_FETCH if task.fetch != &"" else Phase.TO_TASK
		Phase.TO_FETCH:
			if _walk(world, dt):
				if world.take_fetch(task, self):
					var spot: Variant = world.work_spot(task, cell())
					if spot != null:
						set_path(world.nav.find_path(cell(), spot))
					phase = Phase.TO_TASK
				else:
					task.worker = null
					task.retry_at = world.time + 3.0
					task = null
					phase = Phase.IDLE
		Phase.TO_TASK:
			if _walk(world, dt):
				phase = Phase.WORKING
				work_timer = 0.0
				strip_i = 0
				_face(_center(task.cell))
		Phase.WORKING:
			if task.kind == Task.Kind.FIELD:
				_work_strip(world, dt)
			elif task.kind == Task.Kind.TRIP:
				if world.trip_tick(task, self, dt):
					_finish(world)
			elif task.kind == Task.Kind.HELP:
				if world.help_tick(task, self, dt):
					_finish(world)
			else:
				work_timer += dt
				if work_timer >= task.work:
					_finish(world)
		Phase.TO_DELIVER:
			if _walk(world, dt):
				world.deliver(self)
				phase = Phase.IDLE


## Field rows: the worker moves along the row and every cell is done in turn.
func _work_strip(world: World, dt: float) -> void:
	work_timer += dt
	while work_timer >= task.work and strip_i < task.cells.size():
		work_timer -= task.work
		world.field_cell_done(task, task.cells[strip_i])
		strip_i += 1
	if strip_i >= task.cells.size():
		_finish(world)
		return
	var from := _center(task.cells[maxi(strip_i - 1, 0)])
	var to := _center(task.cells[strip_i])
	pos = from.lerp(to, clampf(work_timer / task.work, 0.0, 1.0)) if strip_i > 0 else to
	if strip_i > 0:
		_face(to)


func _finish(world: World) -> void:
	var t := task
	task = null
	world.complete_task(t, self)
	_go_deliver(world)


## The task was called off (e.g. its field was demolished): bring back what it carries.
func abort(world: World) -> void:
	task = null
	path.clear()
	_go_deliver(world)


func _go_deliver(world: World) -> void:
	if carrying == &"":
		phase = Phase.IDLE
		return
	var target: Variant = world.delivery_target(cell())
	if target != null:
		set_path(world.nav.find_path(cell(), target))
	if target != null and not path.is_empty():
		phase = Phase.TO_DELIVER
	else:
		world.deliver(self)   # nowhere to bring it: count it directly
		phase = Phase.IDLE


## Moves along the path; returns true when the end is reached.
func _walk(world: World, dt: float) -> bool:
	var budget := dt
	while budget > 0.0:
		if path_i >= path.size():
			return true
		var target := _center(path[path_i])
		var to := target - pos
		var dist := to.length()
		var speed := Defs.WALK_SPEED * world.speed_factor(cell())
		if dist <= speed * budget:
			pos = target
			budget -= dist / speed
			path_i += 1
		else:
			pos += to / dist * speed * budget
			_face(target)
			budget = 0.0
	return path_i >= path.size()


func _face(target: Vector2) -> void:
	var d := target - pos
	if d.length_squared() > 0.0001:
		heading = atan2(d.x, -d.y)


static func _center(c: Vector2i) -> Vector2:
	return Vector2(c) + Vector2(0.5, 0.5)
