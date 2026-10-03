class_name WorkerView
extends Node3D
## Worker figures following the simulation, with status gem and carried goods.

const CARRY_MODEL := { &"wood": "carry_logs", &"potato": "carry_crate", &"beet": "carry_crate" }
const BODY := {
	Worker.Look.MALE: ["worker_male", "worker_male_carry"],
	Worker.Look.FEMALE: ["worker_female", "worker_female_carry"],
	Worker.Look.MALE_VAR: ["worker_male_var", "worker_male_var"],
	Worker.Look.FEMALE_VAR: ["worker_female_var", "worker_female_var"],
}

var world: World
var _nodes := {}           # worker id -> { root, body, gem, load }


func setup(p_world: World) -> void:
	world = p_world
	for w in world.workers:
		_on_added(w)
	world.worker_added.connect(_on_added)
	world.worker_removed.connect(func(w: Worker) -> void:
		(_nodes[w.id]["root"] as Node3D).queue_free()
		_nodes.erase(w.id))


func _on_added(w: Worker) -> void:
	var root := Node3D.new()
	add_child(root)
	var body := Models.instance(BODY[w.look][0])
	root.add_child(body)
	var gem := Models.instance("ui_status_idle")
	gem.position.y = 2.45
	root.add_child(gem)
	var load_node := MeshInstance3D.new()
	load_node.material_override = Models.palette
	load_node.position = Vector3(0.0, 1.0, -0.42)
	load_node.visible = false
	root.add_child(load_node)
	_nodes[w.id] = {"root": root, "body": body, "gem": gem, "load": load_node, "status": ""}
	_sync(w, 1.0)


func _process(delta: float) -> void:
	for w in world.workers:
		_sync(w, delta)


func _sync(w: Worker, delta: float) -> void:
	var n: Dictionary = _nodes[w.id]
	var root: Node3D = n["root"]
	root.visible = not w.in_vehicle
	root.position = Vector3(w.pos.x * Defs.TILE, 0.0, w.pos.y * Defs.TILE)
	root.rotation.y = lerp_angle(root.rotation.y, -w.heading, minf(1.0, delta * 10.0))
	var carrying := w.carrying != &""
	(n["body"] as MeshInstance3D).mesh = Models.mesh(BODY[w.look][1 if carrying else 0])
	var load_node: MeshInstance3D = n["load"]
	load_node.visible = carrying
	if carrying:
		load_node.mesh = Models.mesh(CARRY_MODEL.get(w.carrying, "carry_sack"))
	var status := "working" if w.phase == Worker.Phase.WORKING else ("walking" if w.is_walking() else "idle")
	if status != n["status"]:
		n["status"] = status
		(n["gem"] as MeshInstance3D).mesh = Models.mesh("ui_status_" + status)
	var gem: Node3D = n["gem"]
	gem.rotation.y += delta * 1.5
	# simple walk bob / chopping nod until real animations exist
	var body: Node3D = n["body"]
	if w.is_walking():
		body.position.y = absf(sin(world.time * 9.0 + w.id)) * 0.08
		body.rotation.x = 0.0
	elif w.phase == Worker.Phase.WORKING:
		body.position.y = 0.0
		body.rotation.x = sin(world.time * 7.0 + w.id) * 0.12
	else:
		body.position.y = 0.0
		body.rotation.x = 0.0
