class_name RoadNav
extends RefCounted
## Pathfinding for road vehicles on the graph of two-way road blocks (2x2 tiles).
## Vehicles keep to the right-hand lane.

const LANE_OFFSET := 0.5    # tiles from the block centre line

var astar := AStarGrid2D.new()
var world: World


func _init(p_world: World) -> void:
	world = p_world
	var n := world.size / Defs.ROAD_BLOCK
	astar.region = Rect2i(0, 0, n, n)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	astar.fill_solid_region(astar.region, true)


func add_block(anchor: Vector2i) -> void:
	astar.set_point_solid(anchor / Defs.ROAD_BLOCK, false)


func remove_block(anchor: Vector2i) -> void:
	astar.set_point_solid(anchor / Defs.ROAD_BLOCK, true)


## Road block next to a tile (a building's access point), or null.
func block_near(cell: Vector2i) -> Variant:
	var best: Variant = null
	var best_d := INF
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var c := cell + Vector2i(dx, dy)
			var b := Vector2i(c.x & ~1, c.y & ~1)
			if not world.road_blocks.has(b):
				continue
			var center := Vector2(b) + Vector2.ONE
			var d := center.distance_squared_to(Vector2(cell) + Vector2(0.5, 0.5))
			if d < best_d:
				best_d = d
				best = b
	return best


## Lane waypoints (tile units) from one block to another; empty if not connected.
func route(from: Vector2i, to: Vector2i) -> PackedVector2Array:
	var out := PackedVector2Array()
	var ids := astar.get_id_path(from / Defs.ROAD_BLOCK, to / Defs.ROAD_BLOCK)
	if ids.is_empty():
		return out
	var pts: Array[Vector2] = []
	for p in ids:
		pts.append(Vector2(p * Defs.ROAD_BLOCK) + Vector2.ONE)
	if pts.size() == 1:
		out.append(pts[0])
		return out
	for i in pts.size():
		var d_in := (pts[i] - pts[i - 1]).normalized() if i > 0 else Vector2.ZERO
		var d_out := (pts[i + 1] - pts[i]).normalized() if i < pts.size() - 1 else Vector2.ZERO
		var off := Vector2.ZERO
		if d_in == Vector2.ZERO:
			off = _right(d_out)
		elif d_out == Vector2.ZERO or d_in == d_out:
			off = _right(d_in)
		else:
			off = _right(d_in) + _right(d_out)    # corner: meet both lanes
		out.append(pts[i] + off * LANE_OFFSET)
	return out


static func _right(d: Vector2) -> Vector2:
	return Vector2(-d.y, d.x)
