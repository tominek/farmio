class_name BuildingView
extends Node3D
## Finished buildings and construction sites (staged model, planned roads as ghosts).

const SITE_MODEL_SIZE := Vector2(4, 3)   # construction_site_4x3_* is scaled to other footprints

var world: World
var _nodes := {}           # building id -> Node3D
var _stage := {}           # site id -> shown model name
var _road_ghost: StandardMaterial3D
var _piles := {}           # moved building's site id -> its material pile at the old spot


func setup(p_world: World) -> void:
	world = p_world
	_road_ghost = Models.ghost_material(Color(1.0, 0.95, 0.8, 0.45))
	for b in world.buildings.values():
		_on_added(b)
	world.building_added.connect(_on_added)
	world.building_removed.connect(_on_removed)
	world.site_changed.connect(_update_site)
	world.building_changed.connect(_on_changed)


func _on_added(b: Building) -> void:
	if b is Field or (b is ConstructionSite and b.upgrade_of):
		return
	var node := Node3D.new()
	node.position = Defs.footprint_center(b.anchor, b.size)
	node.rotation.y = -b.rot * PI * 0.5
	add_child(node)
	_nodes[b.id] = node
	if b is ConstructionSite:
		_update_site(b)
	else:
		node.add_child(Models.instance(b.model()))


## A new level: the model of the upgraded building.
func _on_changed(b: Building) -> void:
	var node: Node3D = _nodes.get(b.id)
	if node == null:
		return
	for child in node.get_children():
		child.queue_free()
	node.add_child(Models.instance(b.model()))


func _on_removed(b: Building) -> void:
	var node: Node3D = _nodes.get(b.id)
	if node:
		node.queue_free()
	_nodes.erase(b.id)
	_stage.erase(b.id)
	_set_pile(b, false)


func _update_site(site: ConstructionSite) -> void:
	var node: Node3D = _nodes.get(site.id)
	if node == null:
		return
	_set_pile(site, site.moved and not site.pile.is_empty())
	var model: String
	var bridge := site.is_road() and world.is_water(site.anchor)
	if bridge:
		model = "bridge_%s_twoway" % Defs.def(site.def_id)["road"]
	elif site.is_road():
		model = "road_%s_twoway_straight" % Defs.def(site.def_id)["road"]
	elif site.dismantle:
		# taken down: from the scaffolded frame to the bare footing
		model = "construction_site_4x3_stage3" if site.progress() < 0.5 else "construction_site_4x3_stage2"
	elif site.stage != ConstructionSite.Stage.BUILDING or site.is_field():
		model = "construction_site_4x3_stage1"
	elif site.progress() < 0.5:
		model = "construction_site_4x3_stage2"
	else:
		model = "construction_site_4x3_stage3"
	# material brought so far lies on the site in a pile (one size per quarter of the need)
	var pile := 0
	var mat := site.material()
	for res: StringName in mat:
		if site.stage == ConstructionSite.Stage.DELIVERY:
			pile = ceili(site.delivered.get(res, 0.0) / mat[res] * 4.0)
	var key := "%s:%d" % [model, pile]
	if _stage.get(site.id) == key:
		return
	_stage[site.id] = key
	for child in node.get_children():
		child.queue_free()
	var mi := Models.instance(model)
	if site.is_road():
		mi.material_override = _road_ghost
		mi.position.y = 0.03          # above the road it upgrades
		if bridge:
			mi.rotation.y = -RoadView.bridge_rotation(world, site.anchor) * PI * 0.5
	else:
		var s := site.base_size
		mi.scale = Vector3(s.x / SITE_MODEL_SIZE.x, 1.0, s.y / SITE_MODEL_SIZE.y)
	node.add_child(mi)
	for res: StringName in mat:
		if pile > 0:
			var p := Models.instance("pile_%s" % res)
			p.position = Vector3(-0.8, 0.0, -0.8)
			p.scale = Vector3.ONE * (0.5 + 0.125 * pile)
			node.add_child(p)

## The materials of a taken-down building lying at its old spot until they are carried to the new site.
func _set_pile(site: Building, show: bool) -> void:
	var node: Node3D = _piles.get(site.id)
	if not show:
		if node:
			node.queue_free()
			_piles.erase(site.id)
		return
	var s := site as ConstructionSite
	if node == null:
		node = Node3D.new()
		node.position = Defs.cell_center(s.pile_cell)
		add_child(node)
		_piles[site.id] = node
	for child in node.get_children():
		child.queue_free()
	for res: StringName in s.pile:
		var share: float = s.pile[res] / maxf(float(s.needs.get(res, s.pile[res])), 0.001)
		var p := Models.instance("pile_%s" % res)
		p.scale = Vector3.ONE * (0.5 + 0.5 * clampf(share, 0.0, 1.0))
		node.add_child(p)

