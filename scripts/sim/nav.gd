class_name Nav
extends RefCounted
## Tile pathfinding for walking units (AStarGrid2D with per-tile cost).

var astar := AStarGrid2D.new()


func _init(size: int) -> void:
	astar.region = Rect2i(0, 0, size, size)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()


func set_solid(cell: Vector2i, solid: bool) -> void:
	astar.set_point_solid(cell, solid)


func is_solid(cell: Vector2i) -> bool:
	return not astar.region.has_point(cell) or astar.is_point_solid(cell)


func set_cost(cell: Vector2i, cost: float) -> void:
	astar.set_point_weight_scale(cell, cost)


## Path of cells from `from` to `to` (both included). Empty if unreachable.
## A unit standing on a solid tile (e.g. a building just finished around it) can still walk out.
func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if is_solid(to) or not astar.region.has_point(from):
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
