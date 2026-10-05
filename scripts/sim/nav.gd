class_name Nav
extends RefCounted
## Tile pathfinding for walking units (AStarGrid2D with per-tile cost).
##
## Fenced fields ("pens") are solid on the grid: a unit gets in and out only through the gate.
## A path that starts or ends inside a pen is joined from a straight walk inside the fence, the
## step through the gate and the grid path outside.

var astar := AStarGrid2D.new()
var _pens := {}               # id -> {"rect": Rect2i, "out": Vector2i (gate tile outside), "in": Vector2i (inside)}
var _pen_at := {}             # cell -> pen id

## Bumped whenever the grid really changes (solid, cost, pens).
var version := 0
## walk_cost memo. Opening a tile (solid -> walkable, a cost going down) only makes paths shorter
## or possible: the finite costs stay (at worst a bit high, fine for choosing between sources), the
## INF ones go. Closing a tile (walkable -> solid, a cost going up, pens) flushes it all.
var _cost_memo := {}          # Vector4i(from.x, from.y, to.x, to.y) -> float
var _inf_keys := {}           # keys of _cost_memo holding INF

const COST_MEMO_CAP := 20000


func _init(size: int) -> void:
	astar.region = Rect2i(0, 0, size, size)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()


func set_solid(cell: Vector2i, solid: bool) -> void:
	if astar.is_point_solid(cell) == solid:
		return
	astar.set_point_solid(cell, solid)
	_changed(not solid)


## Solid for walking past (pens included: a pen is entered by its gate, see find_path).
func is_solid(cell: Vector2i) -> bool:
	return not astar.region.has_point(cell) or astar.is_point_solid(cell)


## A unit can stand here: open ground, or inside a pen (reached through its gate).
func is_walkable(cell: Vector2i) -> bool:
	return not is_solid(cell) or _pen_at.has(cell)


func set_cost(cell: Vector2i, cost: float) -> void:
	var was := astar.get_point_weight_scale(cell)
	if is_equal_approx(was, cost):
		return
	astar.set_point_weight_scale(cell, cost)
	_changed(cost < was)


## A fenced area entered only through its gate: `gate` is the tile in front of it, outside.
## Its cells must be solid on the grid (the World does that for fields).
func set_pen(id: int, rect: Rect2i, gate: Vector2i) -> void:
	remove_pen(id)
	var inside := Vector2i(clampi(gate.x, rect.position.x, rect.end.x - 1), clampi(gate.y, rect.position.y, rect.end.y - 1))
	_pens[id] = {"rect": rect, "out": gate, "in": inside}
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			_pen_at[Vector2i(x, y)] = id
	_changed(false)


func remove_pen(id: int) -> void:
	if not _pens.has(id):
		return
	var rect: Rect2i = _pens[id]["rect"]
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			_pen_at.erase(Vector2i(x, y))
	_pens.erase(id)
	_changed(false)


## Path of cells from `from` to `to` (both included). Empty if unreachable.
## A unit standing on a solid tile (e.g. a building just finished around it) can still walk out.
## Into and out of pens only through their gates.
func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not astar.region.has_point(from) or not astar.region.has_point(to):
		return out
	var pf: int = _pen_at.get(from, -1)
	var pt: int = _pen_at.get(to, -1)
	if pf != -1 and pf == pt:
		return _inside(from, to)
	var start := from
	if pf != -1:
		out = _inside(from, _pens[pf]["in"])
		start = _pens[pf]["out"]
	var goal: Vector2i = _pens[pt]["out"] if pt != -1 else to
	var mid := _grid_path(start, goal)
	if mid.is_empty():
		return [] as Array[Vector2i]
	out.append_array(mid)
	if pt != -1:
		out.append_array(_inside(_pens[pt]["in"], to))
	return out


## walk_cost(from, to) is memoised: no path search needed.
func has_cost(from: Vector2i, to: Vector2i) -> bool:
	return from == to or _cost_memo.has(Vector4i(from.x, from.y, to.x, to.y))


## Length of find_path(from, to) in tiles: straight step 1.0, diagonal step sqrt(2), each step
## multiplied by the weight scale of the tile stepped onto (pen tiles always count 1.0).
## INF when unreachable, 0.0 when from == to. Memoised (see _cost_memo).
func walk_cost(from: Vector2i, to: Vector2i) -> float:
	if from == to:
		return 0.0
	var key := Vector4i(from.x, from.y, to.x, to.y)
	if _cost_memo.has(key):
		return _cost_memo[key]
	var path := find_path(from, to)
	var cost := INF
	if not path.is_empty():
		cost = 0.0
		for i in range(1, path.size()):
			var step: Vector2i = path[i] - path[i - 1]
			var step_len := 1.0 if (step.x == 0 or step.y == 0) else sqrt(2.0)
			var scale := 1.0 if _pen_at.has(path[i]) else astar.get_point_weight_scale(path[i])
			cost += step_len * scale
	if _cost_memo.size() >= COST_MEMO_CAP:
		_cost_memo.clear()
		_inf_keys.clear()
	_cost_memo[key] = cost
	if cost == INF:
		_inf_keys[key] = true
	return cost


## A real change of the grid: an opening drops the memoised INF costs, a closing all of them.
func _changed(opened: bool) -> void:
	version += 1
	if not opened:
		_cost_memo.clear()
	else:
		for key: Vector4i in _inf_keys:
			_cost_memo.erase(key)
	_inf_keys.clear()


func _grid_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if is_solid(to):
		return out
	if from == to:
		out.append(from)
		return out
	var start_solid := astar.is_point_solid(from)
	if start_solid:
		astar.set_point_solid(from, false)
	out = astar.get_id_path(from, to)
	if start_solid:
		astar.set_point_solid(from, true)
	return out


## Inside a pen nothing is in the way: diagonal steps, then straight on.
static func _inside(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = [from]
	var c := from
	while c != to:
		c += Vector2i(signi(to.x - c.x), signi(to.y - c.y))
		out.append(c)
	return out
