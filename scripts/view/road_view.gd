class_name RoadView
extends Node3D
## Built two-way road blocks: picks straight / corner / T / cross / end by neighbour blocks;
## a block on the river is a bridge across it. Wide curves (World.wide_curves) are drawn as one
## model over their 2x2 blocks.

# connection bits in rotation order: N (-y), E (+x), S (+y), W (-x)
const PIECES := { "straight": 0b0101, "corner": 0b0011, "t": 0b0111, "cross": 0b1111, "end": 0b0100 }

var world: World
var _nodes := {}           # anchor -> MeshInstance3D
var _dirty := true
var _tinted: Variant = null  # block shown red by the demolish tool
var _tint_mat: StandardMaterial3D


func setup(p_world: World) -> void:
	world = p_world
	add_to_group("road_view")
	_tint_mat = Models.ghost_material(Color(0.95, 0.3, 0.2, 0.55))
	world.road_changed.connect(func(_a: Vector2i) -> void: _dirty = true)
	# a building on the inside of a wide curve turns it back into small corners
	world.building_added.connect(func(_b: Building) -> void: _dirty = true)
	world.building_removed.connect(func(_b: Building) -> void: _dirty = true)
	world.tree_changed.connect(func(_c: Vector2i) -> void: _dirty = true)
	_rebuild()


func _process(_delta: float) -> void:
	if _dirty:
		_rebuild()


func _rebuild() -> void:
	_dirty = false
	for a in _nodes.keys():
		if not world.road_blocks.has(a):
			(_nodes[a] as Node3D).queue_free()
			_nodes.erase(a)
	var curves := world.wide_curves()     # elbow anchor -> [rotation, swallowed blocks, inside block]
	var hidden := {}
	for elbow: Vector2i in curves:
		for m: Vector2i in curves[elbow][1]:
			hidden[m] = true
	for anchor: Vector2i in world.road_blocks:
		var mi: MeshInstance3D = _nodes.get(anchor)
		if mi == null:
			mi = MeshInstance3D.new()
			mi.material_override = Models.palette
			add_child(mi)
			_nodes[anchor] = mi
		var surface: StringName = world.road_blocks[anchor]
		mi.visible = not hidden.has(anchor)
		if curves.has(anchor):
			var inside: Vector2i = curves[anchor][2]
			# one model over three blocks: it shows the lowest of their surfaces until all are upgraded
			for m: Vector2i in curves[anchor][1]:
				if World.SURFACES.find(world.road_blocks[m]) < World.SURFACES.find(surface):
					surface = world.road_blocks[m]
			mi.mesh = Models.mesh("road_%s_twoway_curve_wide" % surface)
			mi.position = Defs.footprint_center(Vector2i(mini(anchor.x, inside.x), mini(anchor.y, inside.y)), Vector2i(4, 4))
			mi.rotation.y = -curves[anchor][0] * PI * 0.5
			continue
		var choice := _piece_for(world.road_mask(anchor))
		var model := "road_%s_twoway_%s" % [surface, choice[0]]
		if world.is_bridge(anchor):
			model = "bridge_%s_twoway" % surface
			choice = ["bridge", bridge_rotation(world, anchor)]
		mi.mesh = Models.mesh(model)
		mi.position = Defs.footprint_center(anchor, Vector2i(2, 2))
		mi.rotation.y = -choice[1] * PI * 0.5


## The bridge model runs along N-S; across a river flowing N-S it turns to E-W.
static func bridge_rotation(w: World, anchor: Vector2i) -> int:
	return 1 if w.river_axis(anchor) == 1 else 0


## [piece name, rotation] whose openings match the mask.
static func _piece_for(mask: int) -> Array:
	if mask == 0:
		return ["straight", 0]
	if mask == 0b0001 or mask == 0b0100 or mask == 0b0010 or mask == 0b1000:
		var r: int = [2, 3, 0, 1][[0b0001, 0b0010, 0b0100, 0b1000].find(mask)]
		return ["end", r]
	for piece in PIECES:
		for r in 4:
			if Defs.rotate_mask(PIECES[piece], r) == mask:
				return [piece, r]
	return ["cross", 0]


## Tints one block red (the demolish tool's target); null clears it.
func tint(anchor: Variant) -> void:
	if anchor == _tinted:
		return
	if _tinted != null and _nodes.has(_tinted):
		(_nodes[_tinted] as MeshInstance3D).material_overlay = null
	_tinted = anchor
	if anchor != null and _nodes.has(anchor):
		(_nodes[anchor] as MeshInstance3D).material_overlay = _tint_mat
