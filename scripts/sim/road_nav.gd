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
	return _wide_curves(pts, out)


## Wide road curves (World.wide_curves): the vehicle never turns in a corner there. Every run of
## route points inside one curve (its elbow and the two blocks it swallows) is replaced by points on
## the arc (centre line 3 tiles from the arc centre, the lane half a tile to the right) — also when
## the route starts or ends inside the curve: those ends are projected onto the arc.
func _wide_curves(pts: Array[Vector2], lanes: PackedVector2Array) -> PackedVector2Array:
	var curves := world.wide_curves()
	var curve_of := {}                   # block anchor -> elbow anchor
	for e: Vector2i in curves:
		curve_of[e] = e
		for m: Vector2i in curves[e][1]:
			curve_of[m] = e
	var out := PackedVector2Array()
	var i := 0
	while i < pts.size():
		var e: Variant = curve_of.get(Vector2i(pts[i] - Vector2.ONE))
		var j := i
		while e != null and j + 1 < pts.size() and curve_of.get(Vector2i(pts[j + 1] - Vector2.ONE)) == e:
			j += 1
		if e == null or j == i:
			out.append(lanes[i])
			i += 1
			continue
		# entering from straight road: start at the curve's outer edge, else at the start point itself
		var centre := _arc_centre(e, curves[e][2])
		var from: Vector2 = pts[i] + (pts[i] - pts[i - 1]).normalized() * -1.0 if i > 0 else pts[i]
		var to: Vector2 = pts[j] + (pts[j + 1] - pts[j]).normalized() if j + 1 < pts.size() else pts[j]
		out.append_array(_arc(centre, from, to))
		i = j + 1
	return out


## The far corner of the inside block: the centre of a wide curve's arc.
static func _arc_centre(elbow: Vector2i, inside: Vector2i) -> Vector2:
	return Vector2(inside.x + (2 if inside.x > elbow.x else 0), inside.y + (2 if inside.y > elbow.y else 0))


## Lane points on the arc around `centre` from the direction of `from` to the direction of `to`.
func _arc(centre: Vector2, from: Vector2, to: Vector2) -> PackedVector2Array:
	var a0 := (from - centre).angle()
	var span := wrapf((to - centre).angle() - a0, -PI, PI)
	var out := PackedVector2Array()
	var steps := maxi(2, ceili(absf(span) / (PI * 0.5) * 8.0))
	for k in steps + 1:
		var ang := a0 + span * k / steps
		var p := centre + Vector2.from_angle(ang) * 3.0
		var tangent := Vector2.from_angle(ang + signf(span) * PI * 0.5)
		out.append(p + _right(tangent) * LANE_OFFSET)
	return out


static func _right(d: Vector2) -> Vector2:
	return Vector2(-d.y, d.x)
