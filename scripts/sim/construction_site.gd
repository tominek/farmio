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
var supply: Store           # material brought to the site so far
## Material resource -> amount brought so far: `supply`'s own contents (edits in place reach it).
var delivered: Dictionary:
	get:
		return supply.contents
	set(v):
		supply.contents = v
var upgrade_of: Building = null   # an upgrade of this building to its next level (the site takes no tiles)
# moving a building (see World.move_building): the old spot is taken down by a dismantle site while
# the new site waits; both are linked as partners until the old building is down
var dismantle := false      # taking the moved building down (level and materials: the old building's)
var moved := false          # the new site of a moved building: needs its materials, keeps its level
var needs := {}             # moved: materials of the old building (building and upgrades)
var partner: ConstructionSite = null
var pile_store: Store       # moved: materials of the taken-down building lying at the old spot
## Resource -> amount in `pile_store` (its own contents).
var pile: Dictionary:
	get:
		return pile_store.contents
	set(v):
		pile_store.contents = v
## Where that pile lies (the old access tile).
var pile_cell: Vector2i:
	get:
		return pile_store.cell
	set(v):
		pile_store.cell = v
var by_pickup := false      # moved: the pickup hauls the pile (a longer move along roads)


func _init(p_id: int, p_def_id: StringName, p_anchor: Vector2i, p_rot: int, p_base_size := Vector2i.ZERO) -> void:
	super(p_id, p_def_id, p_anchor, p_rot, p_base_size)
	input_store = null              # a site does not process; the finished building gets its own
	output_store = null
	supply = Store.new(Store.Kind.SITE, self, access)
	pile_store = Store.new(Store.Kind.MOVE_PILE, self)
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


## Material the finished object (or the upgrade) needs, resource -> amount.
func material() -> Dictionary:
	if upgrade_of:
		return {&"planks": Defs.def(def_id)["upgrade"][upgrade_of.level + 1]}
	if dismantle:
		return {}
	if moved:
		return needs
	return Defs.def(def_id).get("material", {})


## Name of what is built here: an upgrade goes by the upgraded building's name (renames included),
## other sites by their own number and name ("Sawmill 2", "North Mill").
func base_name() -> String:
	return upgrade_of.display_name() if upgrade_of else super.display_name()


func display_name() -> String:
	if upgrade_of:
		return "%s (upgrade to level %d)" % [base_name(), upgrade_of.level + 1]
	if dismantle:
		return "%s (taking down to move)" % base_name()
	if moved:
		return "%s (moving here)" % base_name()
	return "%s (construction)" % base_name()
