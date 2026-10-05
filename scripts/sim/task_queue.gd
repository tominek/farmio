class_name TaskQueue
extends RefCounted
## Global queue of pending tasks. Free workers pick by priority → distance → age.
## Priority = rank of the task category in the player's order (priority panel), raised by
## waiting time (see priority()), so low categories never starve while fields keep generating work.

const MAX_TRIES := 8

var tasks: Array[Task] = []


func add(task: Task) -> void:
	tasks.append(task)


## Removes the task and lets go of its claims (goods, room, wheelbarrow).
func remove(task: Task) -> void:
	task.release()
	tasks.erase(task)


func pending_count() -> int:
	var n := 0
	for t in tasks:
		if t.worker == null and t.kind != Task.Kind.RIDE:
			n += 1
	return n


## Lower = sooner. Rank of the category in the player's order, raised one level for a High
## building (lowered for Low); one level is worth TASK_AGING seconds of waiting (at most
## TASK_AGING_MAX levels), so an old transport task catches up with fresh field work but a pile
## of old tasks can't block a fresh urgent one. 15 s buckets let distance decide between
## tasks of similar urgency. An urgent task ("Carry to the barn now") goes before everything else.
func priority(world: World, t: Task) -> int:
	if t.urgent:
		return -1000
	var level := world.category_order.find(t.category)
	var b: Building = t.site if t.site else (t.field if t.field else t.building)
	if b:
		level -= b.priority
	var waited := minf(world.time - t.created, Defs.TASK_AGING * Defs.TASK_AGING_MAX)
	return floori((level * Defs.TASK_AGING - waited) / 15.0)


## Where a worker first walks for the task: a carry leg's goods (so the worker near a field takes its
## legs), else the task's cell.
static func _near(t: Task) -> Vector2i:
	return t.src.cell if t.kind == Task.Kind.CARRY and t.src else t.cell


## Finds and claims a task for the worker. Returns the task with the worker's path set, or null.
func pick(world: World, worker: Worker) -> Task:
	var candidates: Array[Task] = []
	for t in tasks:
		# rides are done by pickup trips, not picked by a worker
		if t.worker == null and t.kind != Task.Kind.RIDE and t.retry_at <= world.time \
				and (t.urgent or not world.category_off.has(t.category)) \
				and (t.kind != Task.Kind.HELP or worker.cell().distance_squared_to(t.cell) <= Defs.HELPER_REACH * Defs.HELPER_REACH):
			candidates.append(t)
	if candidates.is_empty():
		return null
	var from := worker.cell()
	var now := world.time
	candidates.sort_custom(func(a: Task, b: Task) -> bool:
		var pa := priority(world, a)
		var pb := priority(world, b)
		if pa != pb:
			return pa < pb
		var da := from.distance_squared_to(_near(a))
		var db := from.distance_squared_to(_near(b))
		if da != db:
			return da < db
		return a.created < b.created)
	for i in mini(MAX_TRIES, candidates.size()):
		var t := candidates[i]
		if t.kind == Task.Kind.CARRY:
			# a carry leg holds its claims already: only the way to it is checked
			if world.claim_leg(t, worker, from):
				t.worker = worker
				return t
			t.retry_at = now + 3.0
			continue
		if t.fetch != &"" and world.fetch_have(t) < world.fetch_min(t):
			t.retry_at = now + 2.0          # e.g. no seeds in storage yet
			continue
		var spot: Variant = world.work_spot(t, from)
		if spot == null:
			t.retry_at = now + 2.0
			continue
		var target: Variant = spot
		if t.fetch != &"":
			target = world.claim_fetch(t, from)
			if target == null:
				t.retry_at = now + 2.0
				continue
		var path := world.nav.find_path(from, target)
		if t.kind == Task.Kind.HELP and path.size() > Defs.HELPER_REACH:
			continue                        # too far to walk to the pickup stop: others help, or the driver alone
		if path.is_empty():
			if t.fetch != &"":
				world.release_fetch(t)
			t.retry_at = now + 3.0
			continue
		t.worker = worker
		worker.set_path(path)
		return t
	return null
