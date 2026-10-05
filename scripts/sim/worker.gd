class_name Worker
extends RefCounted
## A worker unit: picks tasks from the queue, walks, works and delivers output.

enum Phase { IDLE, TO_FETCH, TO_TASK, WORKING, TO_DELIVER, TO_TOOL }
enum Look { MALE, FEMALE, MALE_VAR, FEMALE_VAR }

var id: int
var look: Look
var name := ""               # short first name, chosen when hired (WorkerNames), the player may rename
var pos: Vector2            # in tile units (cell centre = cell + 0.5)
var heading := 0.0          # radians, 0 = facing grid -y
var phase := Phase.IDLE
var task: Task = null
var carrying := &""         # resource carried by hand
var carry_amount := 0.0
var equipment := &""        # tool taken from the barn for this task (wheelbarrow)
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
	return phase == Phase.TO_FETCH or phase == Phase.TO_TASK or phase == Phase.TO_DELIVER or phase == Phase.TO_TOOL


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
				var t := world.tasks.pick(world, self)
				if t:
					start(world, t)
		Phase.TO_TOOL:
			# a carry leg with a wheelbarrow: take it from the barn, then on to the goods
			if _walk(world, dt):
				world.take_tool(task, self)
				var spot: Variant = world.store_spot(task.fetch_from) if task.fetch_from else null
				if spot == null or not _path_to(world, spot):
					abort(world)
				else:
					phase = Phase.TO_FETCH
		Phase.TO_FETCH:
			if _walk(world, dt):
				if world.take_fetch(task, self):
					var spot: Variant = world.work_spot(task, cell())
					if task.kind == Task.Kind.CARRY:
						if spot == null or not _path_to(world, spot):
							abort(world)       # the destination can't be reached any more
							return
					elif spot != null:
						set_path(world.nav.find_path(cell(), spot))
					phase = Phase.TO_TASK
				elif task.kind == Task.Kind.CARRY:
					abort(world)               # the goods are gone: the planner plans again
				else:
					world.release_fetch(task)
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


## Starts a task it has been given (its worker set, the path to it set): to the barn for a
## wheelbarrow first, else to the goods to fetch or to the work.
func start(_world: World, t: Task) -> void:
	task = t
	if t.tool_from:
		phase = Phase.TO_TOOL
	else:
		phase = Phase.TO_FETCH if t.fetch != &"" else Phase.TO_TASK


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


## The task was called off (e.g. its field was demolished): bring back what it carries. A carry
## leg is dropped with all its claims and its goods are put down where the worker stands (the
## planner plans them again; `why` and `site_name` go with the pile, see World.drop_goods); a
## wheelbarrow still goes back to a barn.
func abort(world: World, why := "", site_name := "") -> void:
	if task:
		if task.kind == Task.Kind.CARRY:
			world.tasks.remove(task)
			# what it carries is put down as a ground pile (the planner plans it again)
			if carrying != &"" and world.drop_goods(carrying, carry_amount, cell(), task.category,
					Store.Origin.DROPPED, _drop_reason(why), site_name):
				carrying = &""
				carry_amount = 0.0
		world.release_fetch(task)
	task = null
	path.clear()
	_go_deliver(world)


## Why a ground pile lies where this worker put it down: "the Garage site was cancelled. Bo had it
## in the wheelbarrow and put it down here."
func _drop_reason(why: String) -> String:
	var had := "had it in the wheelbarrow" if equipment == &"wheelbarrow" else "had it"
	if why == "":
		return "%s %s when the trip was called off and put it down here." % [who(), had]
	return "%s. %s %s and put it down here." % [why, who(), had]


## The name for sentences: "Bo", or "A worker" when it has none.
func who() -> String:
	return name if name != "" else "A worker"


func _go_deliver(world: World) -> void:
	if carrying == &"" and equipment == &"":
		phase = Phase.IDLE
		return
	var target: Variant = world.delivery_target(cell(), carrying)
	if target != null:
		set_path(world.nav.find_path(cell(), target))
	if target != null and not path.is_empty():
		phase = Phase.TO_DELIVER
	else:
		world.deliver(self)   # nowhere to bring it: count it directly
		phase = Phase.IDLE


## Sets the path to `to`; false when it can't be reached.
func _path_to(world: World, to: Vector2i) -> bool:
	var p := world.nav.find_path(cell(), to)
	if p.is_empty():
		return false
	set_path(p)
	return true


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
