extends Node3D

## Manages a construction site.
## Phase 1: Workers clear obstacles (trees). Logs appear.
## Phase 2: Workers collect logs and carry to barn (if barn exists).
## Phase 3: Building auto-constructs when area is clear and workers leave.

signal construction_complete(building_key: String, tile_pos: Vector2i, rotation: int)

enum Phase { CLEARING, COLLECTING, WAITING_WORKERS_LEAVE }

var building_key: String = ""
var tile_origin: Vector2i = Vector2i.ZERO
var building_size: Vector2i = Vector2i.ZERO
var rotation_index: int = 0

var _phase: int = Phase.CLEARING
var _trees_to_clear: Dictionary = {}
var _tape_nodes: Array[Node3D] = []
var _log_nodes: Dictionary = {}  # Vector2i -> log visual
var _trees_remaining: int = 0
var _logs_remaining: int = 0
var _collect_tasks_generated: bool = false
var _check_timer: float = 0.0

var _tape_scene: PackedScene = preload("res://assets/buildings/special/construction_tape.tscn")
var _log_scene: PackedScene = preload("res://assets/fields/crops/wood_logs.tscn")
var _ground_nodes: Array[MeshInstance3D] = []

const TILE_SIZE: float = 3.0

var _ground_material: StandardMaterial3D


func setup(p_key: String, p_origin: Vector2i, p_size: Vector2i, p_rotation: int) -> void:
	building_key = p_key
	tile_origin = p_origin
	building_size = p_size
	rotation_index = p_rotation

	var border_origin := Vector2i(p_origin.x - 1, p_origin.y - 1)
	var border_size := Vector2i(p_size.x + 2, p_size.y + 2)

	# Find all trees
	for x in range(border_origin.x, border_origin.x + border_size.x):
		for y in range(border_origin.y, border_origin.y + border_size.y):
			var tile := Vector2i(x, y)
			var data := GridManager.get_tile(tile)
			if not data.is_empty() and int(data["state"]) == GridManager.TileState.NATURAL_OBJECT:
				var tree_node: Node = data["ref"]
				_trees_to_clear[tile] = tree_node
				_trees_remaining += 1

	# Place ground tiles for the whole area
	_place_ground(border_origin, border_size)

	# Place construction tape
	_place_tape(border_origin, border_size)

	# Register ALL tiles as PENDING_CONSTRUCTION (walkable)
	for x in range(border_origin.x, border_origin.x + border_size.x):
		for y in range(border_origin.y, border_origin.y + border_size.y):
			var tile := Vector2i(x, y)
			GridManager.set_tile(tile, GridManager.TileState.PENDING_CONSTRUCTION, self, true)

	# Generate clear tasks
	if _trees_remaining > 0:
		_phase = Phase.CLEARING
		for tile in _trees_to_clear:
			TaskQueue.add_task(TaskQueue.TaskType.CLEAR_OBSTACLE, self, tile)
	else:
		call_deferred("_complete_construction")


func _process(delta: float) -> void:
	_check_timer += delta
	if _check_timer < 0.5:
		return
	_check_timer = 0.0

	match _phase:
		Phase.CLEARING:
			pass  # waiting for all trees to be chopped
		Phase.COLLECTING:
			if _logs_remaining <= 0:
				_phase = Phase.WAITING_WORKERS_LEAVE
			else:
				# Retry generating collect tasks if barn was built after clearing
				_try_generate_collect_tasks()
		Phase.WAITING_WORKERS_LEAVE:
			if not _workers_in_area():
				_complete_construction()


func on_tile_task_completed(tile_pos: Vector2i, task_type: int) -> void:
	if task_type == TaskQueue.TaskType.CLEAR_OBSTACLE:
		# Remove tree, place log
		if _trees_to_clear.has(tile_pos):
			var tree_node: Node = _trees_to_clear[tile_pos]
			if tree_node:
				tree_node.queue_free()
			_trees_to_clear.erase(tile_pos)

		# Place log visual
		var log_visual: Node3D = _log_scene.instantiate()
		log_visual.position = GridManager.tile_to_world(tile_pos)
		add_child(log_visual)
		_log_nodes[tile_pos] = log_visual

		_trees_remaining -= 1
		_logs_remaining += 1

		# All trees chopped — start collecting phase
		if _trees_remaining <= 0:
			_start_collecting()

	elif task_type == TaskQueue.TaskType.COLLECT:
		_logs_remaining -= 1


func remove_log_visual(tile_pos: Vector2i) -> void:
	if _log_nodes.has(tile_pos):
		var log_node: Node3D = _log_nodes[tile_pos]
		log_node.queue_free()
		_log_nodes.erase(tile_pos)


func _start_collecting() -> void:
	_phase = Phase.COLLECTING
	_try_generate_collect_tasks()


func _try_generate_collect_tasks() -> void:
	if _collect_tasks_generated or _logs_remaining <= 0:
		return
	var barn: Node3D = _find_nearest_barn()
	if barn:
		for tile in _log_nodes:
			TaskQueue.add_task(TaskQueue.TaskType.COLLECT, self, tile)
		_collect_tasks_generated = true


func _find_nearest_barn() -> Node3D:
	var buildings: Node3D = get_node_or_null("/root/Main/Buildings")
	if not buildings:
		return null
	for child in buildings.get_children():
		if child.has_method("receive_resource"):
			return child
	return null


func _workers_in_area() -> bool:
	var worker_manager: Node3D = get_node_or_null("/root/Main/WorkerManager")
	if not worker_manager:
		return false

	for worker in worker_manager.workers:
		var wtile: Vector2i = GridManager.world_to_tile(worker.position)
		if wtile.x >= tile_origin.x - 1 and wtile.x < tile_origin.x + building_size.x + 1 \
			and wtile.y >= tile_origin.y - 1 and wtile.y < tile_origin.y + building_size.y + 1:
			return true
	return false


func _complete_construction() -> void:
	# Clean up ground, tape, and remaining logs
	for node in _ground_nodes:
		node.queue_free()
	_ground_nodes.clear()

	for node in _tape_nodes:
		node.queue_free()
	_tape_nodes.clear()

	for tile in _log_nodes:
		_log_nodes[tile].queue_free()
	_log_nodes.clear()

	# Clear pending construction tiles
	var border_origin := Vector2i(tile_origin.x - 1, tile_origin.y - 1)
	var border_size := Vector2i(building_size.x + 2, building_size.y + 2)
	for x in range(border_origin.x, border_origin.x + border_size.x):
		for y in range(border_origin.y, border_origin.y + border_size.y):
			var tile := Vector2i(x, y)
			var data := GridManager.get_tile(tile)
			if not data.is_empty():
				var state: int = int(data["state"])
				if state == GridManager.TileState.PENDING_CONSTRUCTION:
					if data["ref"] == self:
						GridManager.clear_tile(tile)

	construction_complete.emit(building_key, tile_origin, rotation_index)
	queue_free()


func _place_ground(border_origin: Vector2i, border_size: Vector2i) -> void:
	_ground_material = StandardMaterial3D.new()
	_ground_material.albedo_color = Color(0.45, 0.35, 0.2, 1)  # muddy construction dirt

	for x in range(border_origin.x, border_origin.x + border_size.x):
		for y in range(border_origin.y, border_origin.y + border_size.y):
			var mesh := BoxMesh.new()
			mesh.size = Vector3(3.0, 0.08, 3.0)
			mesh.material = _ground_material

			var node := MeshInstance3D.new()
			node.mesh = mesh
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.position = GridManager.tile_to_world(Vector2i(x, y))
			node.position.y = 0.02
			add_child(node)
			_ground_nodes.append(node)


func _place_tape(border_origin: Vector2i, border_size: Vector2i) -> void:
	# Top edge
	for x in range(border_origin.x, border_origin.x + border_size.x):
		var tape: Node3D = _tape_scene.instantiate()
		tape.position = GridManager.tile_to_world(Vector2i(x, border_origin.y))
		tape.position.z -= TILE_SIZE * 0.5
		_tape_nodes.append(tape)
		add_child(tape)

	# Bottom edge
	for x in range(border_origin.x, border_origin.x + border_size.x):
		var tape: Node3D = _tape_scene.instantiate()
		tape.position = GridManager.tile_to_world(Vector2i(x, border_origin.y + border_size.y - 1))
		tape.position.z += TILE_SIZE * 0.5
		_tape_nodes.append(tape)
		add_child(tape)

	# Left edge (full range including corners)
	for y in range(border_origin.y, border_origin.y + border_size.y):
		var tape: Node3D = _tape_scene.instantiate()
		tape.position = GridManager.tile_to_world(Vector2i(border_origin.x, y))
		tape.position.x -= TILE_SIZE * 0.5
		tape.rotation.y = PI / 2.0
		_tape_nodes.append(tape)
		add_child(tape)

	# Right edge (full range including corners)
	for y in range(border_origin.y, border_origin.y + border_size.y):
		var tape: Node3D = _tape_scene.instantiate()
		tape.position = GridManager.tile_to_world(Vector2i(border_origin.x + border_size.x - 1, y))
		tape.position.x += TILE_SIZE * 0.5
		tape.rotation.y = PI / 2.0
		_tape_nodes.append(tape)
		add_child(tape)
