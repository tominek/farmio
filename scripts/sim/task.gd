class_name Task
extends RefCounted
## One unit of work in the global task queue.

enum Kind { CHOP, BUILD, FIELD, HAUL }
enum Category { HARVEST, PLANTING, CONSTRUCTION, TRANSPORT }   # default priority order

var kind: Kind
var category := Category.CONSTRUCTION
var site: ConstructionSite          # CHOP / BUILD
var field: Field                    # FIELD / HAUL
var step := &""                     # FIELD: cultivate / seed / harvest
var row := -1                       # FIELD: row index
var cells: Array[Vector2i] = []     # FIELD: cells in working order
var amount := 0.0                   # HAUL: units to carry
var cell: Vector2i                  # tree to chop / work spot / first cell / pick-up spot
var work: float                     # worker seconds needed (per cell for FIELD)
var worker: Worker = null
var created: float
var retry_at := 0.0                 # unreachable tasks are skipped until then


func _init(p_kind: Kind, p_cell: Vector2i, p_work: float, p_time: float) -> void:
	kind = p_kind
	cell = p_cell
	work = p_work
	created = p_time


func label() -> String:
	match kind:
		Kind.CHOP:
			return "Chop tree"
		Kind.BUILD:
			return "Build %s" % Defs.def(site.def_id)["name"]
		Kind.FIELD:
			return "%s field row" % String(step).capitalize()
		Kind.HAUL:
			return "Carry %s to storage" % Defs.CROPS[field.crop]["name"]
	return "?"
