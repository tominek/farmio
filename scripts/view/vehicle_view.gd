class_name VehicleView
extends Node3D
## Road vehicles following the simulation, with crates on the bed when loaded.

var world: World
var _nodes := {}           # vehicle id -> { root, load }


func setup(p_world: World) -> void:
	world = p_world
	for v in world.vehicles:
		_on_added(v)
	world.vehicle_added.connect(_on_added)


func _on_added(v: Vehicle) -> void:
	var root := Node3D.new()
	add_child(root)
	root.add_child(Models.instance("vehicle_pickup_light"))
	var load_node := Node3D.new()
	for i in 3:
		var crate := Models.instance("carry_crate" if i != 1 else "carry_sack")
		crate.position = Vector3(-0.45 + i * 0.45, 0.85, 1.25)
		load_node.add_child(crate)
	root.add_child(load_node)
	_nodes[v.id] = {"root": root, "load": load_node}
	_sync(v, 1.0)


func _process(delta: float) -> void:
	for v in world.vehicles:
		_sync(v, delta)


func _sync(v: Vehicle, delta: float) -> void:
	var n: Dictionary = _nodes[v.id]
	var root: Node3D = n["root"]
	root.position = Vector3(v.pos.x * Defs.TILE, 0.0, v.pos.y * Defs.TILE)
	root.rotation.y = lerp_angle(root.rotation.y, -v.heading, minf(1.0, delta * 8.0))
	(n["load"] as Node3D).visible = v.cargo_total() > 0.0
