class_name ConstructionSite
extends Building
## Placed instead of the final building, field or road block. Generates clear → (deliver) → build
## tasks and is replaced by the finished object once all work is done.

enum Stage { CLEARING, DELIVERY, BUILDING }

var stage := Stage.CLEARING
var work_total := 0.0
var work_done := 0.0
var open_tasks: Array[Task] = []
var crop := &""             # fields: crop chosen on placement
var delivered := {}         # material resource -> amount brought to the site so far


func _init(p_id: int, p_def_id: StringName, p_anchor: Vector2i, p_rot: int, p_base_size := Vector2i.ZERO) -> void:
	super(p_id, p_def_id, p_anchor, p_rot, p_base_size)
	if is_field():
		work_total = (size.x + size.y) * 2 * Defs.FENCE_WORK_PER_TILE
	else:
		work_total = Defs.def(def_id)["build_work"]


func progress() -> float:
	return 0.0 if work_total <= 0.0 else clampf(work_done / work_total, 0.0, 1.0)


func is_road() -> bool:
	return Defs.is_road(def_id)


func is_field() -> bool:
	return Defs.is_field(def_id)


## Material the finished object needs (road materials), resource -> amount.
func material() -> Dictionary:
	return Defs.def(def_id).get("material", {})


func display_name() -> String:
	return "%s (construction)" % super()
