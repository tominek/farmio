extends Node3D

## Field behavior. All tiles go through each phase together.
## All tiles must complete a phase before the next phase starts.

enum FieldPhase {
	CULTIVATE,
	SEED,
	GROWING,
	FERTILIZE,
	SPRAY,
	HARVEST,
	COLLECT,  # crates on field, waiting for workers to carry to barn
}

const FERTILIZE_THRESHOLD: float = 0.3
const SPRAY_THRESHOLD: float = 0.6

# Per-crop growth parameters: { growth_speed, max_height, color_young, color_mid, color_mature }
const CROP_PARAMS := {
	# Potatoes: ~90 days, fast, short bushes, 9 plants per tile
	ResourceManager.ResourceType.POTATOES: {
		"speed": 0.0028,       # ~6 min
		"height": 0.5,
		"yield": 32,           # ~32 kg per 9m² (real: ~35t/ha)
		"young": Color(0.3, 0.65, 0.2),
		"mid": Color(0.2, 0.55, 0.15),
		"mature": Color(0.45, 0.55, 0.2),
	},
	# Wheat: ~150 days, medium, tall stalks, each stalk = small grain bundle
	ResourceManager.ResourceType.WHEAT: {
		"speed": 0.00167,      # ~10 min
		"height": 1.8,
		"yield": 6,            # ~6 kg per 9m² (real: ~7t/ha)
		"young": Color(0.3, 0.7, 0.2),
		"mid": Color(0.25, 0.55, 0.15),
		"mature": Color(0.85, 0.75, 0.25),
	},
	# Corn: ~90 days, fast, very tall, 1-2 ears per stalk
	ResourceManager.ResourceType.CORN: {
		"speed": 0.0028,       # ~6 min
		"height": 3.5,
		"yield": 9,            # ~9 kg per 9m² (real: ~10t/ha)
		"young": Color(0.2, 0.6, 0.15),
		"mid": Color(0.25, 0.55, 0.12),
		"mature": Color(0.75, 0.7, 0.2),
	},
	# Sugar beet: ~170 days, slowest, 1 heavy beet per plant
	ResourceManager.ResourceType.SUGAR_BEET: {
		"speed": 0.0015,       # ~11 min
		"height": 0.5,
		"yield": 50,           # ~50 kg per 9m² (real: ~55t/ha)
		"young": Color(0.25, 0.6, 0.18),
		"mid": Color(0.2, 0.5, 0.12),
		"mature": Color(0.3, 0.55, 0.15),
	},
}

# Fallback defaults
const DEFAULT_SPEED: float = 0.00167
const DEFAULT_HEIGHT: float = 1.5
const DEFAULT_YIELD: int = 10  # kg per tile
const DEFAULT_YOUNG := Color(0.3, 0.7, 0.2)
const DEFAULT_MID := Color(0.25, 0.55, 0.15)
const DEFAULT_MATURE := Color(0.85, 0.75, 0.25)

var field_origin: Vector2i = Vector2i.ZERO
var field_size: Vector2i = Vector2i.ZERO
var entrance_tile: Vector2i = Vector2i.ZERO

var _phase: int = FieldPhase.CULTIVATE
var _tiles: Dictionary = {}  # Vector2i -> { done, growth, task }
var _tile_visuals: Dictionary = {}  # Vector2i -> Node3D
var _tile_crates: Dictionary = {}  # Vector2i -> Node3D (temporary crates after harvest)
var _initialized: bool = false
var _tasks_generated: bool = false
var _fertilize_triggered: bool = false
var _spray_triggered: bool = false
var _visual_update_timer: float = 0.0
const VISUAL_UPDATE_INTERVAL: float = 0.5  # update visuals twice per second, not every frame

var _bare_soil_scene: PackedScene = preload("res://assets/fields/soil/bare_soil.tscn")
var _cultivated_soil_scene: PackedScene = preload("res://assets/fields/soil/cultivated_soil.tscn")
var _generic_crop_scene: PackedScene = preload("res://assets/fields/crops/crop_generic.tscn")
var _generic_stubble_scene: PackedScene = preload("res://assets/fields/crops/stubble.tscn")
var _generic_crate_scene: PackedScene = preload("res://assets/fields/crops/harvest_crate.tscn")

const CROP_SCENES := {
	ResourceManager.ResourceType.POTATOES: {
		"crop": "res://assets/fields/crops/potatoes/crop_potatoes.tscn",
		"crate": "res://assets/fields/crops/potatoes/crate_potatoes.tscn",
		"stubble": "res://assets/fields/crops/potatoes/stubble_potatoes.tscn",
	},
	ResourceManager.ResourceType.WHEAT: {
		"crop": "res://assets/fields/crops/wheat/crop_wheat.tscn",
		"crate": "res://assets/fields/crops/wheat/crate_wheat.tscn",
		"stubble": "res://assets/fields/crops/wheat/stubble_wheat.tscn",
	},
	ResourceManager.ResourceType.CORN: {
		"crop": "res://assets/fields/crops/corn/crop_corn.tscn",
		"crate": "res://assets/fields/crops/corn/crate_corn.tscn",
		"stubble": "res://assets/fields/crops/corn/stubble_corn.tscn",
	},
	ResourceManager.ResourceType.SUGAR_BEET: {
		"crop": "res://assets/fields/crops/sugar_beet/crop_sugar_beet.tscn",
		"crate": "res://assets/fields/crops/sugar_beet/crate_sugar_beet.tscn",
		"stubble": "res://assets/fields/crops/sugar_beet/stubble_sugar_beet.tscn",
	},
}

## What crop this field produces (-1 = not selected yet)
var crop_type: int = -1


func _ready() -> void:
	if has_meta("field_origin"):
		field_origin = get_meta("field_origin") as Vector2i
	if has_meta("field_size"):
		field_size = get_meta("field_size") as Vector2i


func initialize_entrance(tile: Vector2i) -> void:
	entrance_tile = tile
	set_meta("entrance_tile", tile)

	for x in range(field_origin.x, field_origin.x + field_size.x):
		for y in range(field_origin.y, field_origin.y + field_size.y):
			var t := Vector2i(x, y)
			_tiles[t] = {
				"done": false,
				"growth": 0.0,
				"task": null,
			}

	_initialized = true
	# Don't start cycle yet — wait for crop selection


func set_crop_type(type: int) -> void:
	crop_type = type
	set_meta("crop_type", type)
	if _initialized and _phase == FieldPhase.CULTIVATE:
		_start_phase(FieldPhase.CULTIVATE)


func _get_crop_scene() -> PackedScene:
	if CROP_SCENES.has(crop_type):
		return load(CROP_SCENES[crop_type]["crop"]) as PackedScene
	return _generic_crop_scene


func _get_crate_scene() -> PackedScene:
	if CROP_SCENES.has(crop_type):
		return load(CROP_SCENES[crop_type]["crate"]) as PackedScene
	return _generic_crate_scene


func _get_stubble_scene() -> PackedScene:
	if CROP_SCENES.has(crop_type):
		return load(CROP_SCENES[crop_type]["stubble"]) as PackedScene
	return _generic_stubble_scene


func _get_param(key: String) -> Variant:
	if CROP_PARAMS.has(crop_type):
		var params: Dictionary = CROP_PARAMS[crop_type] as Dictionary
		if params.has(key):
			return params[key]
	# Fallback
	match key:
		"speed": return DEFAULT_SPEED
		"height": return DEFAULT_HEIGHT
		"yield": return DEFAULT_YIELD
		"young": return DEFAULT_YOUNG
		"mid": return DEFAULT_MID
		"mature": return DEFAULT_MATURE
		_: return null


func _process(delta: float) -> void:
	if not _initialized:
		return

	if _phase == FieldPhase.GROWING:
		_update_growth(delta)


func _update_growth(delta: float) -> void:
	_visual_update_timer += delta
	if _visual_update_timer < VISUAL_UPDATE_INTERVAL:
		return

	var elapsed: float = _visual_update_timer
	_visual_update_timer = 0.0

	var min_growth: float = 1.0

	for tile_pos in _tiles:
		var tile_data: Dictionary = _tiles[tile_pos]
		var speed: float = _get_param("speed") as float
		tile_data["growth"] = (tile_data["growth"] as float) + elapsed * speed
		var growth_val: float = tile_data["growth"] as float

		if growth_val > 1.0:
			tile_data["growth"] = 1.0
			growth_val = 1.0

		_update_crop_visual(tile_pos, growth_val)

		if growth_val < min_growth:
			min_growth = growth_val

	# Check thresholds based on the slowest tile
	if min_growth >= FERTILIZE_THRESHOLD and not _fertilize_triggered:
		_fertilize_triggered = true
		_start_phase(FieldPhase.FERTILIZE)
	elif min_growth >= SPRAY_THRESHOLD and not _spray_triggered and _fertilize_triggered and _phase == FieldPhase.GROWING:
		_spray_triggered = true
		_start_phase(FieldPhase.SPRAY)
	elif min_growth >= 1.0 and _phase == FieldPhase.GROWING:
		_start_phase(FieldPhase.HARVEST)


func on_tile_task_completed(tile_pos: Vector2i, task_type: int) -> void:
	if not _tiles.has(tile_pos):
		return

	var tile_data: Dictionary = _tiles[tile_pos]
	tile_data["task"] = null
	tile_data["done"] = true

	# Visual updates per tile
	match task_type:
		TaskQueue.TaskType.CULTIVATE:
			_swap_tile_visual(tile_pos, _cultivated_soil_scene)
		TaskQueue.TaskType.SEED:
			_swap_tile_visual(tile_pos, _get_crop_scene())
		TaskQueue.TaskType.HARVEST:
			_swap_tile_visual(tile_pos, _get_stubble_scene())
			_add_crate(tile_pos)
		TaskQueue.TaskType.COLLECT:
			_remove_crate(tile_pos)

	# Check if all tiles completed this phase
	if _all_tiles_done():
		_advance_phase()


func _all_tiles_done() -> bool:
	for tile_pos in _tiles:
		var tile_data: Dictionary = _tiles[tile_pos]
		if not tile_data["done"] as bool:
			return false
	return true


func _reset_done_flags() -> void:
	for tile_pos in _tiles:
		_tiles[tile_pos]["done"] = false


func _start_phase(phase: int) -> void:
	_phase = phase
	_tasks_generated = false
	_reset_done_flags()

	var task_type: int = -1
	match phase:
		FieldPhase.CULTIVATE:
			task_type = TaskQueue.TaskType.CULTIVATE
		FieldPhase.SEED:
			task_type = TaskQueue.TaskType.SEED
		FieldPhase.FERTILIZE:
			task_type = TaskQueue.TaskType.FERTILIZE
		FieldPhase.SPRAY:
			task_type = TaskQueue.TaskType.SPRAY
		FieldPhase.HARVEST:
			task_type = TaskQueue.TaskType.HARVEST
		FieldPhase.COLLECT:
			task_type = TaskQueue.TaskType.COLLECT
		FieldPhase.GROWING:
			return  # no tasks during growing

	_generate_all_tasks(task_type)
	_tasks_generated = true


func _advance_phase() -> void:
	match _phase:
		FieldPhase.CULTIVATE:
			_start_phase(FieldPhase.SEED)
		FieldPhase.SEED:
			# Start growing — reset growth for all tiles
			for tile_pos in _tiles:
				_tiles[tile_pos]["growth"] = 0.0
			_fertilize_triggered = false
			_spray_triggered = false
			_phase = FieldPhase.GROWING
		FieldPhase.FERTILIZE:
			_phase = FieldPhase.GROWING
		FieldPhase.SPRAY:
			_phase = FieldPhase.GROWING
		FieldPhase.HARVEST:
			# Crates appear on field, wait for collection
			_start_phase(FieldPhase.COLLECT)
		FieldPhase.COLLECT:
			# All crates collected — reset and start new cycle
			for tile_pos in _tiles:
				_tiles[tile_pos]["growth"] = 0.0
			_start_phase(FieldPhase.CULTIVATE)


func _generate_all_tasks(task_type: int) -> void:
	for tile_pos in _tiles:
		var tile_data: Dictionary = _tiles[tile_pos]
		if tile_data["task"] != null:
			continue
		var task: Variant = TaskQueue.add_task(task_type, self, tile_pos)
		tile_data["task"] = task


func _update_crop_visual(tile_pos: Vector2i, growth: float) -> void:
	if not _tile_visuals.has(tile_pos):
		return

	var visual: Node3D = _tile_visuals[tile_pos]
	var crop_node: Node3D = visual.get_node_or_null("Crop")
	if crop_node == null:
		return

	var max_height: float = _get_param("height") as float
	var height: float = 0.05 + growth * max_height
	var scale_y: float = height / 0.05
	var pos_y: float = 0.075 + height / 2.0

	var color_young: Color = _get_param("young") as Color
	var color_mid: Color = _get_param("mid") as Color
	var color_mature: Color = _get_param("mature") as Color

	var color: Color
	if growth < 0.5:
		color = color_young.lerp(color_mid, growth * 2.0)
	else:
		color = color_mid.lerp(color_mature, (growth - 0.5) * 2.0)

	if crop_node is MeshInstance3D:
		# Single mesh crop
		crop_node.scale.y = scale_y
		crop_node.position.y = pos_y
		_set_mesh_color(crop_node, color)
	else:
		# Multi-mesh crop (Node3D parent with children)
		crop_node.scale.y = scale_y
		crop_node.position.y = pos_y
		for child in crop_node.get_children():
			if child is MeshInstance3D:
				_set_mesh_color(child, color)


func _set_mesh_color(mesh_inst: MeshInstance3D, color: Color) -> void:
	var mat: Material = mesh_inst.get_surface_override_material(0)
	if mat == null:
		mat = StandardMaterial3D.new()
		mesh_inst.set_surface_override_material(0, mat)
	if mat is StandardMaterial3D:
		mat.albedo_color = color


func _add_crate(tile_pos: Vector2i) -> void:
	var crate: Node3D = _get_crate_scene().instantiate()
	crate.position = GridManager.tile_to_world(tile_pos)
	add_child(crate)
	_tile_crates[tile_pos] = crate


func _remove_crate(tile_pos: Vector2i) -> void:
	if _tile_crates.has(tile_pos):
		var crate: Node3D = _tile_crates[tile_pos]
		crate.queue_free()
		_tile_crates.erase(tile_pos)


func _swap_tile_visual(tile_pos: Vector2i, scene: PackedScene) -> void:
	if _tile_visuals.has(tile_pos):
		var old_visual: Node3D = _tile_visuals[tile_pos]
		var world_pos: Vector3 = old_visual.position
		old_visual.queue_free()

		var new_visual: Node3D = scene.instantiate()
		new_visual.position = world_pos
		add_child(new_visual)
		_tile_visuals[tile_pos] = new_visual


func get_tile_growth(tile_pos: Vector2i) -> float:
	if _tiles.has(tile_pos):
		return _tiles[tile_pos]["growth"] as float
	return 0.0


func get_phase_name() -> String:
	match _phase:
		FieldPhase.CULTIVATE: return "Cultivating"
		FieldPhase.SEED: return "Seeding"
		FieldPhase.GROWING:
			var min_growth: float = 1.0
			for tile_pos in _tiles:
				var g: float = _tiles[tile_pos]["growth"] as float
				if g < min_growth:
					min_growth = g
			return "Growing (%d%%)" % [int(min_growth * 100)]
		FieldPhase.FERTILIZE: return "Fertilizing"
		FieldPhase.SPRAY: return "Spraying"
		FieldPhase.HARVEST: return "Harvesting"
		_: return "Unknown"
