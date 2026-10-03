class_name Building
extends RefCounted
## A placed object on the grid: finished building, field, construction site (subclass) or the Dealer.

var id: int
var def_id: StringName
var anchor: Vector2i
var rot: int
var base_size: Vector2i     # unrotated size (fields choose it freely)
var size: Vector2i          # footprint on the grid
var access: Vector2i
var paid := 0               # money spent on it, refunded when demolished (starting buildings: 0)


func _init(p_id: int, p_def_id: StringName, p_anchor: Vector2i, p_rot: int, p_base_size := Vector2i.ZERO) -> void:
	id = p_id
	def_id = p_def_id
	anchor = p_anchor
	rot = p_rot
	base_size = p_base_size if p_base_size != Vector2i.ZERO else Defs.def(def_id)["size"]
	size = Defs.rotated(base_size, rot)
	access = Defs.access_for(base_size, anchor, rot)


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
