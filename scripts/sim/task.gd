class_name Task
extends RefCounted
## One unit of work in the global task queue.

enum Kind { CHOP, BUILD, FIELD, CARRY, TRIP, HELP, PROCESS, RIDE }
enum Category { HARVEST, DEALER, PLANTING, CONSTRUCTION, TRANSPORT, PROCESSING, FELLING }
const DEFAULT_ORDER: Array = [Category.HARVEST, Category.DEALER, Category.PLANTING, Category.CONSTRUCTION,
	Category.FELLING, Category.PROCESSING, Category.TRANSPORT]

const CATEGORY_NAMES := {
	Category.HARVEST: ["Harvest", "harvesting field rows"],
	Category.DEALER: ["Dealer trips", "pickup trips to sell, buy and hire, and loading for them"],
	Category.PLANTING: ["Planting", "cultivating and sowing field rows"],
	Category.CONSTRUCTION: ["Construction", "chopping trees on sites, bringing material and building"],
	Category.TRANSPORT: ["Transport", "carrying harvest and products to the barn, raw goods to mills, pickup runs from fields"],
	Category.PROCESSING: ["Processing", "grinding grain at mills, sawing logs"],
	Category.FELLING: ["Felling", "chopping trees marked with the axe and carrying their logs from the pile to the barn or a sawmill"],
}

var kind: Kind
var category := Category.CONSTRUCTION
var site: ConstructionSite          # CHOP (null: a tree marked for felling) / BUILD / CARRY: the site it serves
var field: Field                    # FIELD / CARRY: the field whose gate it clears
var building: Building              # PROCESS / CARRY: the mill it supplies or clears
var step := &""                     # FIELD: cultivate / seed / harvest
var row := -1                       # FIELD: row index
var cells: Array[Vector2i] = []     # FIELD: cells in working order
var amount := 0.0                   # PROCESS: raw goods in the batch; RIDE: goods it has put into dst so far
var fetch := &""                    # FIELD seed rows: seed fetched from storage first; CARRY: the good carried
var fetch_amount := 0.0
var fetch_from: Store = null        # the store whose goods this task has claimed (null once taken)
var fetch_reserved := 0.0
var src: Store = null               # CARRY: where the goods come from (claimed: fetch_from)
var dst: Store = null               # CARRY: where the goods go (room promised: dst_reserved)
var dst_reserved := 0.0
var tool_from: Store = null         # CARRY: barn whose wheelbarrow is claimed for this leg
var vehicle: Vehicle                # TRIP
var steps: Array[Dictionary] = []   # TRIP: planned legs
var step_i := 0
var timer := 0.0
var route := PackedVector2Array()
var route_i := 0
var help_step: Dictionary = {}     # HELP: the trip step being loaded / unloaded
var help_trip: Task                 # HELP: the pickup trip it belongs to
var help_state := {}                # HELP: this helper's current load
var cell: Vector2i                  # tree to chop / work spot / first cell / CARRY: where the goods go
var work: float                     # worker seconds needed (per cell for FIELD)
var worker: Worker = null
var created: float
var retry_at := 0.0                 # unreachable tasks are skipped until then
# chains of legs (CARRY walks, RIDE vehicle legs) and multi-stop trips
var next: Task = null               # the following leg of the chain, not queued yet (holds dst_reserved; fetch_from null until it opens)
var plan: Array[Dictionary] = []    # shared by all legs of one chain: {"by": &"walk" | &"ride", "from": Store, "to": Store} per leg
var leg_i := 0                      # index of this leg in plan
var trip: Task = null               # RIDE: the TRIP that carries it (null while waiting)
var loaded := 0.0                   # RIDE: amount of fetch in the vehicle
var urgent := false                 # "Carry to the barn now": goes before everything else
var stops: Array[Dictionary] = []   # TRIP: the stops (see World, "pickup trips")
var road_version := -1              # TRIP: World.roads_removed when it was planned (a road gone since: planned again)


func _init(p_kind: Kind, p_cell: Vector2i, p_work: float, p_time: float) -> void:
	kind = p_kind
	cell = p_cell
	work = p_work
	created = p_time


## Lets go of every claim: the goods at the source, the room at the destination, the wheelbarrow,
## and those of every later leg of the chain. Safe to call more than once.
func release() -> void:
	if next:
		next.release()
	if fetch_from:
		fetch_from.release_out(fetch, fetch_reserved)
	fetch_from = null
	fetch_reserved = 0.0
	if dst:
		dst.release_in(fetch, dst_reserved)
	dst_reserved = 0.0
	if tool_from:
		tool_from.release_out(&"wheelbarrow", 1.0)
	tool_from = null


func label() -> String:
	match kind:
		Kind.CHOP:
			return "Chop tree" if site else "Fell a marked tree"
		Kind.BUILD:
			if site.upgrade_of:
				return "Upgrade %s" % site.base_name()
			return ("Take down %s" if site.dismantle else "Build %s") % site.base_name()
		Kind.FIELD:
			return "%s field row" % String(step).capitalize()
		Kind.CARRY:
			return "Carry %s from %s to %s" % [Defs.resource_name(fetch).to_lower(), src.label(), dst.label()]
		Kind.TRIP:
			if stops.any(func(st: Dictionary) -> bool: return st["dealer"]):
				return "Drive the pickup to the Dealer"
			return "Drive the pickup · %d stop%s" % [stops.size(), "" if stops.size() == 1 else "s"]
		Kind.HELP:
			return "Help load the pickup"
		Kind.PROCESS:
			return "Make %s at the %s" % [Defs.resource_name(building.recipe()["out"]).to_lower(), building.display_name()]
		Kind.RIDE:
			return "Drive %s from %s to %s" % [Defs.resource_name(fetch).to_lower(), src.label(), dst.label()]
	return "?"


## Where the goods of the whole chain end up.
func final_dst() -> Store:
	return plan.back()["to"] if not plan.is_empty() else dst
