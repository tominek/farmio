class_name PileView
extends Node3D
## Ground piles (felled logs, goods put down when a leg broke): a small heap of the good's carried
## model (logs, crates, sacks), one per hand load up to four, rebuilt only when the pile changes
## (no per-frame work).

const SPOTS: Array[Vector3] = [Vector3(-0.32, 0.0, -0.2), Vector3(0.3, 0.0, -0.12), Vector3(-0.02, 0.0, 0.3)]
const TURNS: Array[float] = [0.3, -0.5, 1.4, 0.9]

var world: World
var _nodes := {}           # Store -> Node3D


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


func _update(s: Store) -> void:
	var node: Node3D = _nodes.get(s)
	if node == null:
		return
	for child in node.get_children():
		child.queue_free()
	if s.contents.is_empty():
		return
	var res: StringName = s.contents.keys()[0]
	var model: String = WorkerFigure.CARRY_MODEL.get(res, "carry_sack")
	var count := clampi(ceili(s.weight() / Defs.CARRY_CAPACITY - 0.001), 1, SPOTS.size() + 1)
	var box := Models.mesh(model).get_aabb()
	var long := box.size.x > 2.0 * box.size.z       # logs, planks: stacked side by side
	for i in count:
		var p := Models.instance(model)
		if long:
			var row := 0 if i < 3 else 1            # three at the bottom, the last one on top
			var side := (float(i) - 1.0) if row == 0 else 0.0
			p.position = Vector3(0.05 * side, row * box.size.y * 0.85 - box.position.y, side * box.size.z * 0.95)
			p.rotation.y = 0.06 * side
		else:
			if i < SPOTS.size():
				p.position = SPOTS[i] + Vector3(0.0, -box.position.y, 0.0)
			else:
				p.position = Vector3(0.0, box.size.y * 0.8 - box.position.y, -0.02)   # the last one on top
			p.rotation.y = TURNS[i]
		node.add_child(p)
