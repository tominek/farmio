class_name WorkerView
extends Node3D
## Worker figures following the simulation: animated parts, tools, carried goods, status gem.

var world: World
var _nodes := {}           # worker id -> { root, figure, gem, status, last }


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
	var figure := WorkerFigure.new()
	root.add_child(figure)
	figure.setup(w.look)
	var gem := Models.instance("ui_status_idle")
	gem.position.y = 2.45
	root.add_child(gem)
	_nodes[w.id] = {"root": root, "figure": figure, "gem": gem, "status": "", "last": w.pos, "speed": 0.0}
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
	# walking is read from the actual movement, so field rows and loading shuttles walk too
	var moved: float = (w.pos - (n["last"] as Vector2)).length() / maxf(delta, 0.0001)
	n["last"] = w.pos
	n["speed"] = lerpf(n["speed"], moved, minf(1.0, delta * 8.0))
	var figure: WorkerFigure = n["figure"]
	var action := WorkerFigure.action_of(w)
	# the chopper stands on the next tile: step up to the trunk so the axe reaches it
	figure.position.z = -1.3 if action == WorkerFigure.Action.CHOP else 0.0
	figure.pose(action, world.time + w.id * 0.37, n["speed"] > 0.15, w.carrying)

	var status := "working" if w.phase == Worker.Phase.WORKING else ("walking" if w.is_walking() else "idle")
	if status != n["status"]:
		n["status"] = status
		(n["gem"] as MeshInstance3D).mesh = Models.mesh("ui_status_" + status)
	var gem: Node3D = n["gem"]
	gem.rotation.y += delta * 1.5
