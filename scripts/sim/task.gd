class_name Task
extends RefCounted
## One unit of work in the global task queue.

enum Kind { CHOP, BUILD, FIELD, HAUL, TRIP, HELP, DELIVER, PROCESS }
enum Category { HARVEST, DEALER, PLANTING, CONSTRUCTION, TRANSPORT, PROCESSING }
const DEFAULT_ORDER: Array = [Category.HARVEST, Category.DEALER, Category.PLANTING, Category.CONSTRUCTION,
	Category.PROCESSING, Category.TRANSPORT]

const CATEGORY_NAMES := {
	Category.HARVEST: ["Harvest", "harvesting field rows"],
	Category.DEALER: ["Dealer trips", "pickup trips to sell, buy and hire, and loading for them"],
	Category.PLANTING: ["Planting", "cultivating and sowing field rows"],
	Category.CONSTRUCTION: ["Construction", "chopping trees on sites, bringing material and building"],
	Category.TRANSPORT: ["Transport", "carrying harvest and products to the barn, raw goods to mills, pickup runs from fields"],
	Category.PROCESSING: ["Processing", "grinding grain at mills, sawing logs"],
}

var kind: Kind
var category := Category.CONSTRUCTION
var site: ConstructionSite          # CHOP / BUILD / DELIVER
var field: Field                    # FIELD / HAUL
var building: Building              # DELIVER (supply), PROCESS, HAUL: a processing building
var step := &""                     # FIELD: cultivate / seed / harvest
var row := -1                       # FIELD: row index
var cells: Array[Vector2i] = []     # FIELD: cells in working order
var amount := 0.0                   # HAUL: units to carry
var fetch := &""                    # FIELD seed rows, DELIVER: resource fetched from storage first
var fetch_amount := 0.0
var vehicle: Vehicle                # TRIP
var steps: Array[Dictionary] = []   # TRIP: planned legs
var step_i := 0
var timer := 0.0
var route := PackedVector2Array()
var route_i := 0
var help_step: Dictionary = {}     # HELP: the trip step being loaded / unloaded
var help_trip: Task                 # HELP: the pickup trip it belongs to
var help_state := {}                # HELP: this helper's current load
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
			return "Carry %s to storage" % (Defs.resource_name(building.recipe()["out"]) if building else Defs.CROPS[field.crop]["name"])
		Kind.TRIP:
			return "Drive the pickup to the field" if field else "Drive the pickup to the Dealer"
		Kind.HELP:
			return "Help load the pickup"
		Kind.DELIVER:
			if building:
				return "Bring %s to the %s" % [Defs.resource_name(fetch).to_lower(), building.display_name()]
			return "Bring %s to the %s site" % [Defs.resource_name(fetch).to_lower(), Defs.def(site.def_id)["name"]]
		Kind.PROCESS:
			return "Make %s at the %s" % [Defs.resource_name(building.recipe()["out"]).to_lower(), building.display_name()]
	return "?"
