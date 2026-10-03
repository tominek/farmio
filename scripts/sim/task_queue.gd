class_name TaskQueue
extends RefCounted
## Global queue of pending tasks. Free workers pick by category → distance → age.

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


## Finds and claims a task for the worker. Returns the task with `path` filled, or null.
func pick(world: World, worker: Worker) -> Task:
	var candidates: Array[Task] = []
	for t in tasks:
		if t.worker == null and t.retry_at <= world.time:
			candidates.append(t)
	if candidates.is_empty():
		return null
	var from := worker.cell()
	candidates.sort_custom(func(a: Task, b: Task) -> bool:
		if a.category != b.category:
			return a.category < b.category
		var da := from.distance_squared_to(a.cell)
		var db := from.distance_squared_to(b.cell)
		if da != db:
			return da < db
		return a.created < b.created)
	for i in mini(MAX_TRIES, candidates.size()):
		var t := candidates[i]
		var spot: Variant = world.work_spot(t, from)
		if spot == null:
			t.retry_at = world.time + 2.0
			continue
		var path := world.nav.find_path(from, spot)
		if path.is_empty():
			t.retry_at = world.time + 3.0
			continue
		t.worker = worker
		worker.set_path(path)
		return t
	return null
