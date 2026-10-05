class_name PileView
extends Node3D
## Ground piles (felled logs, goods put down when a leg broke, road piles beside a road): the
## pile's look by fill level (weight / capacity): up to ⅓, up to ⅔, full (design 17d). Logs and
## sacks/crates grow from one to three to six of the good's carried model (`WorkerFigure.CARRY_MODEL`);
## planks grow from one thin stack to a tall crossed stack of the same model; gravel (no carried
## model) is a small procedural mound, grey, built once and shared. Rebuilt only on pile signals,
## and only when the good or fill level actually changed (`_keys` caches the last one per pile) —
## no per-frame work.

const SPOTS: Array[Vector3] = [Vector3(-0.32, 0.0, -0.2), Vector3(0.3, 0.0, -0.12), Vector3(-0.02, 0.0, 0.3)]
const TURNS: Array[float] = [0.3, -0.5, 1.4, 0.9, -1.1, 2.0]
const LEVEL_FRAC := [1.0 / 3.0, 2.0 / 3.0]   # boundaries of "up to ⅓" / "up to ⅔"; above is "full"
const LOG_COUNTS := [1, 3, 6]
const SACK_COUNTS := [1, 3, 6]
const PLANK_COUNTS := [1, 2, 4]
const GRAVEL_RADIUS := [0.22, 0.32, 0.42]

var world: World
var _nodes := {}           # Store -> Node3D
var _keys := {}            # Store -> last "<res>#<level>" built, "" when empty
var _gravel_material: StandardMaterial3D
var _gravel_mesh: Array[SphereMesh] = []


func _init() -> void:
	_gravel_material = StandardMaterial3D.new()
	_gravel_material.albedo_color = Color("#8C8C8C")
	_gravel_material.roughness = 1.0
	_gravel_material.metallic_specular = 0.0
	for r in GRAVEL_RADIUS:
		var m := SphereMesh.new()
		m.radius = r
		m.height = r
		m.is_hemisphere = true
		m.radial_segments = 12
		m.rings = 6
		_gravel_mesh.append(m)


func setup(p_world: World) -> void:
	world = p_world
	for s in world.ground_piles:
		_on_added(s)
	world.pile_added.connect(_on_added)
	world.pile_changed.connect(_update)
	world.pile_removed.connect(_on_removed)


func _on_added(s: Store) -> void:
	var node := Node3D.new()
	node.position = Defs.cell_center(s.cell)
	node.rotation.y = float(hash(s.cell) % 628) * 0.01   # piles don't all lie the same way
	add_child(node)
	_nodes[s] = node
	_update(s)


func _on_removed(s: Store) -> void:
	var node: Node3D = _nodes.get(s)
	if node:
		node.queue_free()
	_nodes.erase(s)
	_keys.erase(s)


func _level(frac: float) -> int:
	if frac <= LEVEL_FRAC[0] + 0.0005:
		return 0
	if frac <= LEVEL_FRAC[1] + 0.0005:
		return 1
	return 2


func _update(s: Store) -> void:
	var node: Node3D = _nodes.get(s)
	if node == null:
		return
	if s.contents.is_empty():
		if _keys.get(s, "") != "":
			for child in node.get_children():
				child.queue_free()
			_keys[s] = ""
		return
	var res: StringName = s.contents.keys()[0]
	var level := _level(s.weight() / maxf(s.capacity, 1.0))
	var key := "%s#%d" % [res, level]
	if _keys.get(s, "") == key:
		return
	_keys[s] = key
	for child in node.get_children():
		child.queue_free()
	if res == &"gravel":
		var mi := MeshInstance3D.new()
		mi.mesh = _gravel_mesh[level]
		mi.material_override = _gravel_material
		node.add_child(mi)
		return
	var model: String = WorkerFigure.CARRY_MODEL.get(res, "carry_sack")
	var box := Models.mesh(model).get_aabb()
	match model:
		"carry_logs":
			_place_stack(node, model, box, LOG_COUNTS[level])
		"carry_planks":
			_place_planks(node, model, box, PLANK_COUNTS[level])
		_:
			_place_sacks(node, model, box, SACK_COUNTS[level])


## Logs: rows of up to three, side by side, a second row stacked on top (1, 3 or 6 pieces).
func _place_stack(node: Node3D, model: String, box: AABB, count: int) -> void:
	var per_row := 3
	for i in count:
		var row := i / per_row
		var in_row := mini(per_row, count - row * per_row)
		var col := i % per_row
		var side := float(col) - float(in_row - 1) * 0.5
		var p := Models.instance(model)
		p.position = Vector3(0.05 * side, row * box.size.y * 0.85 - box.position.y, side * box.size.z * 0.95)
		p.rotation.y = 0.06 * side
		node.add_child(p)


## Planks: one stack; two stacks side by side; two layers of two, the top layer crossed over the
## bottom (a tall crossed stack, as real lumber is stacked to tie it together).
func _place_planks(node: Node3D, model: String, box: AABB, count: int) -> void:
	var cols := 1 if count == 1 else 2
	var layers := count / cols
	for layer in layers:
		for col in cols:
			var side := float(col) - float(cols - 1) * 0.5
			var p := Models.instance(model)
			p.position = Vector3(0.0, layer * box.size.y * 0.9 - box.position.y, side * box.size.z * 1.1)
			p.rotation.y = PI * 0.5 if layers >= 2 and layer % 2 == 1 else 0.0
			node.add_child(p)


## Sacks / crates: the three ground spots, a second layer (shrunk in, raised) for a full pile.
func _place_sacks(node: Node3D, model: String, box: AABB, count: int) -> void:
	for i in count:
		var layer := i / SPOTS.size()
		var base := i % SPOTS.size()
		var squeeze := 1.0 - 0.15 * layer
		var p := Models.instance(model)
		p.position = SPOTS[base] * squeeze + Vector3(0.0, layer * box.size.y * 0.85 - box.position.y, 0.0)
		p.rotation.y = TURNS[i]
		node.add_child(p)
