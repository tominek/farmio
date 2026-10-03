class_name Task
extends RefCounted
## One unit of work in the global task queue.

enum Kind { CHOP, BUILD }
enum Category { CONSTRUCTION }

var kind: Kind
var category := Category.CONSTRUCTION
var site: ConstructionSite
var cell: Vector2i          # tree to chop / preferred work spot for building
var work: float             # worker seconds needed
var worker: Worker = null
var created: float
var retry_at := 0.0         # unreachable tasks are skipped until then


func _init(p_kind: Kind, p_site: ConstructionSite, p_cell: Vector2i, p_work: float, p_time: float) -> void:
	kind = p_kind
	site = p_site
	cell = p_cell
	work = p_work
	created = p_time


func label() -> String:
	match kind:
		Kind.CHOP:
			return "Chop tree"
		Kind.BUILD:
			return "Build %s" % Defs.def(site.def_id)["name"]
	return "?"
