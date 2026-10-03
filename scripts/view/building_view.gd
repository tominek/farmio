class_name BuildingView
extends Node3D
## Finished buildings and construction sites (staged model, planned roads as ghosts).

const SITE_MODEL_SIZE := Vector2(4, 3)   # construction_site_4x3_* is scaled to other footprints

var world: World
var _nodes := {}           # building id -> Node3D
var _stage := {}           # site id -> shown model name
var _road_ghost: StandardMaterial3D


func setup(p_world: World) -> void:
	world = p_world
	_road_ghost = Models.ghost_material(Color(1.0, 0.95, 0.8, 0.45))
	for b in world.buildings.values():
		_on_added(b)
	world.building_added.connect(_on_added)
	world.building_removed.connect(_on_removed)
	world.site_changed.connect(_update_site)


func _on_added(b: Building) -> void:
	if b is Field:
		return
	var node := Node3D.new()
	node.position = Defs.footprint_center(b.anchor, b.size)
	node.rotation.y = -b.rot * PI * 0.5
	add_child(node)
	_nodes[b.id] = node
	if b is ConstructionSite:
		_update_site(b)
	else:
		node.add_child(Models.instance(Defs.def(b.def_id)["model"]))
		if b.def_id == &"garage":
			var pickup := Models.instance("vehicle_pickup_light")
			pickup.position = Vector3(0.0, 0.0, -1.0)
			node.add_child(pickup)


func _on_removed(b: Building) -> void:
	var node: Node3D = _nodes.get(b.id)
	if node:
		node.queue_free()
	_nodes.erase(b.id)
	_stage.erase(b.id)


func _update_site(site: ConstructionSite) -> void:
	var node: Node3D = _nodes.get(site.id)
	if node == null:
		return
	var model: String
	if site.is_road():
		model = "road_%s_twoway_straight" % Defs.def(site.def_id)["road"]
	elif site.stage != ConstructionSite.Stage.BUILDING or site.is_field():
		model = "construction_site_4x3_stage1"
	elif site.progress() < 0.5:
		model = "construction_site_4x3_stage2"
	else:
		model = "construction_site_4x3_stage3"
	if _stage.get(site.id) == model:
		return
	_stage[site.id] = model
	for child in node.get_children():
		child.queue_free()
	var mi := Models.instance(model)
	if site.is_road():
		mi.material_override = _road_ghost
	else:
		var s := site.base_size
		mi.scale = Vector3(s.x / SITE_MODEL_SIZE.x, 1.0, s.y / SITE_MODEL_SIZE.y)
	node.add_child(mi)
