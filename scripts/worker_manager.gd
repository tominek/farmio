extends Node3D

## Manages all workers. Spawns family workers at game start.
## Temporary: click on a tile to send all idle workers there.

const TILE_SIZE: float = 3.0

var _worker_scene: PackedScene = preload("res://assets/workers/worker.tscn")
var _worker_script: GDScript = preload("res://scripts/worker.gd")

var workers: Array[Node3D] = []


func spawn_family_workers(origin_tile: Vector2i, count: int = 3) -> void:
	var spawn_pos: Vector3 = GridManager.tile_to_world(origin_tile)

	for i in range(count):
		var worker := _worker_scene.instantiate()
		worker.set_script(_worker_script)
		worker.position = spawn_pos
		worker._task_check_timer = i * 0.15
		add_child(worker)
		workers.append(worker)
