extends Node3D

## A single worker. Picks tasks from the queue and walks to perform them.

const TILE_SIZE: float = 3.0

@export var move_speed: float = 6.0
@export var work_duration: float = 3.0  # seconds to complete a task

enum WorkerState {
	IDLE,
	WALKING,
	WORKING,
}

var state: int = WorkerState.IDLE
var _target_position: Vector3 = Vector3.ZERO
var _path: Array[Vector2i] = []
var _path_index: int = 0
var _current_task: Variant = null  # TaskQueue.Task or null
var _work_timer: float = 0.0
var _task_check_timer: float = 0.0

@onready var _status_mesh: MeshInstance3D = $Status


func _ready() -> void:
	_target_position = position
	_set_status(WorkerState.IDLE)
	_create_carry_visual()


func _create_carry_visual() -> void:
	pass  # Created dynamically when picking up


func _show_carrying(resource_type: int) -> void:
	_hide_carrying()

	# Load the actual crate scene for this crop type
	var crate_path := "res://assets/fields/crops/harvest_crate.tscn"
	var crop_scenes: Dictionary = {
		ResourceManager.ResourceType.POTATOES: "res://assets/fields/crops/potatoes/crate_potatoes.tscn",
		ResourceManager.ResourceType.WHEAT: "res://assets/fields/crops/wheat/crate_wheat.tscn",
		ResourceManager.ResourceType.CORN: "res://assets/fields/crops/corn/crate_corn.tscn",
		ResourceManager.ResourceType.SUGAR_BEET: "res://assets/fields/crops/sugar_beet/crate_sugar_beet.tscn",
	}
	if crop_scenes.has(resource_type):
		crate_path = crop_scenes[resource_type]

	var scene: PackedScene = load(crate_path) as PackedScene
	_carry_visual = scene.instantiate()
	_carry_visual.position = Vector3(0, 0.8, 0.6)
	_carry_visual.scale = Vector3(0.5, 0.5, 0.5)
	add_child(_carry_visual)


func _hide_carrying() -> void:
	if _carry_visual:
		_carry_visual.queue_free()
		_carry_visual = null


func _process(delta: float) -> void:
	match state:
		WorkerState.IDLE:
			_check_for_tasks(delta)
		WorkerState.WALKING:
			_move_along_path(delta)
		WorkerState.WORKING:
			_do_work(delta)


func _check_for_tasks(delta: float) -> void:
	_task_check_timer += delta
	if _task_check_timer < 0.5:  # check twice per second
		return
	_task_check_timer = 0.0

	var my_tile := GridManager.world_to_tile(position)
	var task = TaskQueue.get_best_task(my_tile)
	if task == null:
		return

	# Claim the task
	_current_task = task
	task.assigned_worker = self

	# Already at the task tile — start working immediately
	if my_tile == task.tile:
		_path.clear()
		_work_timer = 0.0
		_set_status(WorkerState.WORKING)
		return

	# Pathfind to the task tile — fences will naturally route through the gate
	var path := _find_path(my_tile, task.tile)
	if path.is_empty():
		TaskQueue.cancel_task(task)
		_current_task = null
		return

	_path = path
	_path_index = 0
	_advance_path()
	_set_status(WorkerState.WALKING)


func _move_along_path(delta: float) -> void:
	var dir := (_target_position - position)
	dir.y = 0
	var dist := dir.length()

	if dist < 0.1:
		position.x = _target_position.x
		position.z = _target_position.z
		_advance_path()
		return

	# Rotate to face movement direction
	var move_dir := dir.normalized()
	rotation.y = atan2(move_dir.x, move_dir.z)

	var step := move_speed * delta
	if step > dist:
		step = dist
	position += move_dir * step


func _advance_path() -> void:
	if _path_index >= _path.size():
		_path.clear()

		# Check if delivering to barn
		if _carrying_resource >= 0 and _delivery_barn:
			if _delivery_barn.has_method("receive_resource"):
				_delivery_barn.receive_resource(_carrying_resource, _carrying_amount)
			_carrying_resource = -1
			_carrying_amount = 0
			_delivery_barn = null
			_hide_carrying()
			_set_status(WorkerState.IDLE)
			return

		# Arrived at task location — start working
		if _current_task != null:
			_work_timer = 0.0
			_set_status(WorkerState.WORKING)
		else:
			_set_status(WorkerState.IDLE)
		return

	_target_position = GridManager.tile_to_world(_path[_path_index])
	_target_position.y = 0
	_path_index += 1


func _do_work(delta: float) -> void:
	_work_timer += delta
	if _work_timer >= work_duration:
		_finish_task()


var _carrying_resource: int = -1  # ResourceManager.ResourceType or -1
var _carrying_amount: int = 0
var _delivery_barn: Node3D = null
var _carry_visual: Node3D = null


func _finish_task() -> void:
	if _current_task == null:
		_set_status(WorkerState.IDLE)
		return

	var task = _current_task
	var building: Node3D = task.building

	# COLLECT tasks: pick up crate, then deliver to barn
	if task.type == TaskQueue.TaskType.COLLECT and _carrying_resource == -1:
		# Pick up the resource
		if building and building.has_method("on_tile_task_completed"):
			building.on_tile_task_completed(task.tile, task.type)

		_carrying_resource = building.crop_type if building.get("crop_type") != null else 1
		var yield_amount: int = 2
		if building.has_method("_get_param"):
			yield_amount = building._get_param("yield") as int
		_carrying_amount = yield_amount
		_show_carrying(_carrying_resource)
		TaskQueue.complete_task(task)
		_current_task = null

		# Find nearest barn and walk to it
		_delivery_barn = _find_nearest_barn()
		if _delivery_barn:
			var barn_entrance: Vector2i = _delivery_barn.get_meta("entrance_tile") as Vector2i
			var my_tile: Vector2i = GridManager.world_to_tile(position)
			var path := _find_path(my_tile, barn_entrance)
			if not path.is_empty():
				_path = path
				_path_index = 0
				_advance_path()
				_set_status(WorkerState.WALKING)
				return

		# No barn found or can't reach — drop resource (lost for now)
		_carrying_resource = -1
		_carrying_amount = 0
		_delivery_barn = null
		_hide_carrying()
		_set_status(WorkerState.IDLE)
		return

	# Notify the building that the task is done
	if building and building.has_method("on_tile_task_completed"):
		building.on_tile_task_completed(task.tile, task.type)
	elif building and building.has_method("on_task_completed"):
		building.on_task_completed(task.type)

	# Remove from queue
	TaskQueue.complete_task(task)
	_current_task = null
	_set_status(WorkerState.IDLE)


func _set_status(new_state: int) -> void:
	state = new_state
	match state:
		WorkerState.IDLE:
			_set_status_color(Color(0.5, 0.5, 0.5))  # grey
		WorkerState.WALKING:
			_set_status_color(Color(1, 1, 0))  # yellow
		WorkerState.WORKING:
			_set_status_color(Color(0, 1, 0))  # green


func _set_status_color(color: Color) -> void:
	if _status_mesh:
		var mat := _status_mesh.get_surface_override_material(0)
		if mat == null:
			mat = StandardMaterial3D.new()
			_status_mesh.set_surface_override_material(0, mat)
		if mat is StandardMaterial3D:
			mat.albedo_color = color


func move_to_tile(tile: Vector2i) -> void:
	## Manual move (for debug/testing). Cancels current task.
	if _current_task != null:
		TaskQueue.cancel_task(_current_task)
		_current_task = null

	var path := _find_path(GridManager.world_to_tile(position), tile)
	if path.is_empty():
		return

	_path = path
	_path_index = 0
	_advance_path()
	_set_status(WorkerState.WALKING)


func _find_nearest_barn() -> Node3D:
	var buildings: Node3D = get_node_or_null("/root/Main/Buildings")
	if not buildings:
		return null

	var my_pos: Vector3 = position
	var nearest: Node3D = null
	var nearest_dist: float = INF

	for child in buildings.get_children():
		if child.has_method("receive_resource"):
			var dist: float = my_pos.distance_to(child.position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = child

	return nearest


func _find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	return GridManager.find_path(from, to)
