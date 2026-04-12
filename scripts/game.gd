extends Node3D

## Main game script. Sets up the world on load.

@onready var world_generator: Node3D = $WorldGenerator
@onready var camera_rig: Node3D = $CameraRig
@onready var worker_manager: Node3D = $WorkerManager


func _ready() -> void:
	GridManager.reset()
	TaskQueue.reset()
	ResourceManager.reset()
	GridManager.initialize_pathfinding(GameSettings.map_size)
	_create_ground(GameSettings.map_size)
	world_generator.generate(GameSettings.map_size, GameSettings.seed_value)

	# Center camera on the farm origin
	var farm_world := GridManager.tile_to_world(world_generator.farm_origin)
	camera_rig.position = Vector3(farm_world.x, 0, farm_world.z)

	# Spawn family workers near the pickup point
	worker_manager.spawn_family_workers(world_generator.farm_origin)

	# Connect crop selector
	var crop_selector: Control = $UI/CropSelector
	crop_selector.crop_selected.connect(_on_crop_selected)


func _on_crop_selected(crop_type: int, field: Node3D) -> void:
	if field.has_method("set_crop_type"):
		field.set_crop_type(crop_type)


func _create_ground(map_size: int) -> void:
	var ground_size := map_size * 3.0  # tiles to meters
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.55, 0.2, 1)

	var mesh := PlaneMesh.new()
	mesh.size = Vector2(ground_size, ground_size)
	mesh.material = mat

	var ground := MeshInstance3D.new()
	ground.mesh = mesh
	ground.name = "Ground"
	add_child(ground)
