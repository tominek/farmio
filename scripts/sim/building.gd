class_name Building
extends RefCounted
## A placed object on the grid: finished building, construction site (subclass) or the Dealer.

var id: int
var def_id: StringName
var anchor: Vector2i
var rot: int
var size: Vector2i
var access: Vector2i


func _init(p_id: int, p_def_id: StringName, p_anchor: Vector2i, p_rot: int) -> void:
	id = p_id
	def_id = p_def_id
	anchor = p_anchor
	rot = p_rot
	size = Defs.footprint(def_id, rot)
	access = Defs.access_cell(def_id, anchor, rot)


func rect() -> Rect2i:
	return Rect2i(anchor, size)


func cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in size.y:
		for x in size.x:
			out.append(anchor + Vector2i(x, y))
	return out


func display_name() -> String:
	return Defs.def(def_id)["name"]
