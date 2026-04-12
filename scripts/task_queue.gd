extends Node

## Global task queue. Buildings generate tasks, workers pick them up.

enum TaskType {
	CULTIVATE,
	SEED,
	FERTILIZE,
	SPRAY,
	HARVEST,
	COLLECT,  # pick up harvested crate and bring to barn
	PROCESS,
	TRANSPORT,
}

enum TaskPriority {
	LOW,
	NORMAL,
	HIGH,
}

class Task:
	var type: int  # TaskType
	var priority: int  # TaskPriority
	var building: Node3D  # source building
	var tile: Vector2i  # where to perform the task
	var assigned_worker: Node3D = null
	var age: int = 0  # frames since created

	func _init(p_type: int, p_building: Node3D, p_tile: Vector2i, p_priority: int = TaskPriority.NORMAL) -> void:
		type = p_type
		building = p_building
		tile = p_tile
		priority = p_priority


var _tasks: Array = []  # Array of Task


func reset() -> void:
	_tasks.clear()


func add_task(type: int, building: Node3D, tile: Vector2i, priority: int = TaskPriority.NORMAL) -> Task:
	var task := Task.new(type, building, tile, priority)
	_tasks.append(task)
	return task


func get_best_task(worker_pos: Vector2i) -> Task:
	## Returns the highest priority unassigned task closest to the worker.
	## Penalizes buildings that already have workers assigned to spread workers out.
	var best_task: Task = null
	var best_score: float = INF

	# Count workers already assigned per building
	var workers_per_building: Dictionary = {}
	for task in _tasks:
		if task.assigned_worker != null and task.building != null:
			var building_id: int = task.building.get_instance_id()
			if workers_per_building.has(building_id):
				workers_per_building[building_id] = (workers_per_building[building_id] as int) + 1
			else:
				workers_per_building[building_id] = 1

	for task in _tasks:
		if task.assigned_worker != null:
			continue

		# Score: lower is better.
		var priority_score: float = (2 - task.priority) * 10000.0
		var dist: float = absi(task.tile.x - worker_pos.x) + absi(task.tile.y - worker_pos.y)
		var age_bonus: float = task.age * -0.1

		# Penalty for buildings that already have workers — encourages spreading
		var building_penalty: float = 0.0
		if task.building != null:
			var building_id: int = task.building.get_instance_id()
			var assigned_count: int = 0
			if workers_per_building.has(building_id):
				assigned_count = workers_per_building[building_id] as int
			building_penalty = assigned_count * 50.0

		var score: float = priority_score + dist + age_bonus + building_penalty

		if score < best_score:
			best_score = score
			best_task = task

	return best_task


func complete_task(task: Task) -> void:
	_tasks.erase(task)


func cancel_task(task: Task) -> void:
	task.assigned_worker = null


func remove_tasks_for_building(building: Node3D) -> void:
	var to_remove: Array = []
	for task in _tasks:
		if task.building == building:
			to_remove.append(task)
	for task in to_remove:
		_tasks.erase(task)


func get_pending_count() -> int:
	var count := 0
	for task in _tasks:
		if task.assigned_worker == null:
			count += 1
	return count


func get_total_count() -> int:
	return _tasks.size()


func _process(_delta: float) -> void:
	# Age all tasks
	for task in _tasks:
		task.age += 1


static func type_name(type: int) -> String:
	match type:
		TaskType.CULTIVATE: return "Cultivate"
		TaskType.SEED: return "Seed"
		TaskType.FERTILIZE: return "Fertilize"
		TaskType.SPRAY: return "Spray"
		TaskType.HARVEST: return "Harvest"
		TaskType.COLLECT: return "Collect"
		TaskType.PROCESS: return "Process"
		TaskType.TRANSPORT: return "Transport"
		_: return "Unknown"
