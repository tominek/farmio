class_name ConstructionSite
extends Building
## Placed instead of the final building (or road block). Generates clear → (deliver) → build
## tasks and is replaced by the finished object once all work is done.

enum Stage { CLEARING, DELIVERY, BUILDING }

var stage := Stage.CLEARING
var work_total := 0.0
var work_done := 0.0
var open_tasks: Array[Task] = []


func _init(p_id: int, p_def_id: StringName, p_anchor: Vector2i, p_rot: int) -> void:
	super(p_id, p_def_id, p_anchor, p_rot)
	work_total = Defs.def(def_id)["build_work"]


func progress() -> float:
	return 0.0 if work_total <= 0.0 else clampf(work_done / work_total, 0.0, 1.0)


func is_road() -> bool:
	return Defs.is_road(def_id)


func display_name() -> String:
	return "%s (construction)" % super()
