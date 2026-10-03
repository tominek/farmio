class_name RoadView
extends Node3D
## Built two-way road blocks: picks straight / corner / T / cross / end by neighbour blocks.

# connection bits in rotation order: N (-y), E (+x), S (+y), W (-x)
const PIECES := { "straight": 0b0101, "corner": 0b0011, "t": 0b0111, "cross": 0b1111, "end": 0b0100 }

var world: World
var _nodes := {}           # anchor -> MeshInstance3D


func setup(p_world: World) -> void:
	world = p_world
	for a in world.road_blocks:
		_refresh(a)
	world.road_changed.connect(_on_road_changed)


func _on_road_changed(anchor: Vector2i) -> void:
	_refresh(anchor)
	for d in Defs.DIRS:
		_refresh(anchor + d * Defs.ROAD_BLOCK)


func _refresh(anchor: Vector2i) -> void:
	if not world.road_blocks.has(anchor):
		if _nodes.has(anchor):
			(_nodes[anchor] as Node3D).queue_free()
			_nodes.erase(anchor)
		return
	var mask := 0
	for r in 4:
		if world.road_blocks.has(anchor + Defs.DIRS[r] * Defs.ROAD_BLOCK):
			mask |= 1 << r
	var choice := _piece_for(mask)
	var surface: StringName = world.road_blocks[anchor]
	var mi: MeshInstance3D = _nodes.get(anchor)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.material_override = Models.palette
		add_child(mi)
		_nodes[anchor] = mi
	mi.mesh = Models.mesh("road_%s_twoway_%s" % [surface, choice[0]])
	mi.position = Defs.footprint_center(anchor, Vector2i(2, 2))
	mi.rotation.y = -choice[1] * PI * 0.5


## [piece name, rotation] whose openings match the mask.
static func _piece_for(mask: int) -> Array:
	if mask == 0:
		return ["straight", 0]
	if mask == 0b0001 or mask == 0b0100 or mask == 0b0010 or mask == 0b1000:
		var r: int = [2, 3, 0, 1][[0b0001, 0b0010, 0b0100, 0b1000].find(mask)]
		return ["end", r]
	for piece in PIECES:
		for r in 4:
			if _rotate_mask(PIECES[piece], r) == mask:
				return [piece, r]
	return ["cross", 0]


static func _rotate_mask(m: int, r: int) -> int:
	return ((m << r) | (m >> (4 - r))) & 0b1111
