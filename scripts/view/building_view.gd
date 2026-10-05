class_name BuildingView
extends Node3D
## Finished buildings and construction sites (staged model, planned roads as ghosts). A collection
## point shows the good it holds most of on its deck, by fill level (the road pile looks, smaller);
## rebuilt on stock / filter signals only when that good or level changed.

const SITE_MODEL_SIZE := Vector2(4, 3)   # construction_site_4x3_* is scaled to other footprints
const COLLECT_DECK := 0.32               # top of the collection point's deck (model units)
const COLLECT_GOODS_SCALE := 0.6         # road pile goods scaled to fit the 1×1 deck (logs, planks)
const COLLECT_SMALL_SCALE := 0.9         # sacks and gravel: smaller looks, scaled less to read as well

var world: World
var _nodes := {}           # building id -> Node3D
var _stage := {}           # site id -> shown model name
var _road_ghost: StandardMaterial3D
var _piles := {}           # moved building's site id -> its material pile at the old spot
var _goods := {}           # collection point id -> "<res>#<level>" dressed, "" when empty
var _dresser: PileView     # lends its pile looks (never set up: no piles of its own)
var _patch: PlaneMesh      # shared dark patch under a collection point's goods
var _patch_mat: StandardMaterial3D


func setup(p_world: World) -> void:
	world = p_world
	_road_ghost = Models.ghost_material(Color(1.0, 0.95, 0.8, 0.45))
	for b in world.buildings.values():
		_on_added(b)
	world.building_added.connect(_on_added)
	world.building_removed.connect(_on_removed)
	world.site_changed.connect(_update_site)
	world.building_changed.connect(_on_changed)
	world.stock_changed.connect(_dress_collects)
	world.store_changed.connect(func(_s: Store) -> void: _dress_collects())


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
		_dress(b)


## A new level: the model of the upgraded building.
func _on_changed(b: Building) -> void:
	var node: Node3D = _nodes.get(b.id)
	if node == null:
		return
	for child in node.get_children():
		child.queue_free()
	node.add_child(Models.instance(b.model()))
	_goods.erase(b.id)
	_dress(b)


func _on_removed(b: Building) -> void:
	var node: Node3D = _nodes.get(b.id)
	if node:
		node.queue_free()
	_nodes.erase(b.id)
	_stage.erase(b.id)
	_goods.erase(b.id)
	_set_pile(b, false)


## Goods moved somewhere: re-dress the collection points (a handful) whose look changed.
func _dress_collects() -> void:
	for b in world.collects():
		_dress(b)


## A collection point's deck: the good it holds most of (by weight), at the road pile fill level of
## its whole load; nothing when empty. Only rebuilt when that good or level changed.
func _dress(b: Building) -> void:
	if b.store == null or b.store.kind != Store.Kind.COLLECT:
		return
	var node: Node3D = _nodes.get(b.id)
	if node == null:
		return
	var key := ""
	var res := &""
	var level := 0
	var most := 0.0
	for r: StringName in b.store.contents:
		var kg := Defs.weight(r, b.store.contents[r])
		if kg > most:
			most = kg
			res = r
	if res != &"":
		level = PileView.level_of(b.store.weight() / maxf(b.store.capacity, 1.0))
		key = "%s#%d" % [res, level]
	if _goods.get(b.id, "") == key:
		return
	_goods[b.id] = key
	var old := node.get_node_or_null(^"Goods")
	if old:
		node.remove_child(old)
		old.queue_free()
	if key == "":
		return
	if _dresser == null:
		_dresser = PileView.new()
		add_child(_dresser)
	var goods := Node3D.new()
	goods.name = &"Goods"
	goods.position.y = COLLECT_DECK
	node.add_child(goods)
	# a dark patch under the goods so pale goods (planks) read against the pale deck
	if _patch == null:
		var m := PlaneMesh.new()
		m.size = Vector2(2.0, 2.0)
		_patch = m
		_patch_mat = StandardMaterial3D.new()
		_patch_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_patch_mat.albedo_color = Color(0.16, 0.09, 0.04, 0.5)
		_patch_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var patch := MeshInstance3D.new()
	patch.mesh = _patch
	patch.material_override = _patch_mat
	patch.position.y = 0.01
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	goods.add_child(patch)
	var long: bool = WorkerFigure.CARRY_MODEL.get(res, "") in ["carry_logs", "carry_planks"]
	_dresser.dress(goods, res, level, COLLECT_GOODS_SCALE if long else COLLECT_SMALL_SCALE)


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

