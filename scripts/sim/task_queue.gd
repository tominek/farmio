class_name TaskQueue
extends RefCounted
## Global queue of pending tasks. Free workers pick by priority → distance → age.
## Priority = rank of the task category in the player's order (priority panel), raised by
## waiting time (see priority()), so low categories never starve while fields keep generating work.

const MAX_TRIES := 8

var tasks: Array[Task] = []


func add(task: Task) -> void:
	tasks.append(task)


func remove(task: Task) -> void:
	tasks.erase(task)


func pending_count() -> int:
	var n := 0
	for t in tasks:
		if t.worker == null:
			n += 1
	return n


## Lower = sooner. Rank of the category in the player's order, raised one level for a High
## building (lowered for Low); one level is worth TASK_AGING seconds of waiting (at most
## TASK_AGING_MAX levels), so an old transport task catches up with fresh field work but a pile
## of old tasks can't block a fresh urgent one. 15 s buckets let distance decide between
## tasks of similar urgency.
func priority(world: World, t: Task) -> int:
	var level := world.category_order.find(t.category)
	var b: Building = t.site if t.site else t.field
	if b:
		level -= b.priority
	var waited := minf(world.time - t.created, Defs.TASK_AGING * Defs.TASK_AGING_MAX)
	return floori((level * Defs.TASK_AGING - waited) / 15.0)


## Finds and claims a task for the worker. Returns the task with the worker's path set, or null.
func pick(world: World, worker: Worker) -> Task:
	var candidates: Array[Task] = []
	for t in tasks:
		if t.worker == null and t.retry_at <= world.time and not world.category_off.has(t.category):
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
		var da := from.distance_squared_to(a.cell)
		var db := from.distance_squared_to(b.cell)
		if da != db:
			return da < db
		return a.created < b.created)
	for i in mini(MAX_TRIES, candidates.size()):
		var t := candidates[i]
		if t.kind == Task.Kind.HAUL:
			# take a wheelbarrow from the barn first when there is a lot to carry
			t.fetch = &"wheelbarrow" if world.wants_wheelbarrow(t) else &""
			t.fetch_amount = 1.0
		if t.fetch != &"" and world.stock.get(t.fetch, 0.0) < world.fetch_min(t):
			t.retry_at = now + 2.0          # e.g. no seeds in storage yet
			continue
		var spot: Variant = world.work_spot(t, from)
		if spot == null:
			t.retry_at = now + 2.0
			continue
		var target: Variant = spot
		if t.fetch != &"":
			target = world.delivery_target(from)
			if target == null:
				t.retry_at = now + 2.0
				continue
		var path := world.nav.find_path(from, target)
		if path.is_empty():
			t.retry_at = now + 3.0
			continue
		t.worker = worker
		if t.fetch == &"wheelbarrow":
			world.fill_wheelbarrow(t)
		worker.set_path(path)
		return t
	return null
