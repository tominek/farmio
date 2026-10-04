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
var upgrade_of: Building = null   # an upgrade of this building to its next level (the site takes no tiles)
# moving a building (see World.move_building): the old spot is taken down by a dismantle site while
# the new site waits; both are linked as partners until the old building is down
var dismantle := false      # taking the moved building down (level and materials: the old building's)
var moved := false          # the new site of a moved building: needs its materials, keeps its level
var needs := {}             # moved: materials of the old building (building and upgrades)
var partner: ConstructionSite = null
var pile := {}              # moved: materials of the taken-down building lying at the old spot
var pile_cell := Vector2i(-1, -1)   # where that pile lies (the old access tile)
var by_pickup := false      # moved: the pickup hauls the pile (a longer move along roads)


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


## Material the finished object (or the upgrade) needs, resource -> amount.
func material() -> Dictionary:
	if upgrade_of:
		return {&"planks": Defs.def(def_id)["upgrade"][upgrade_of.level + 1]}
	if dismantle:
		return {}
	if moved:
		return needs
	return Defs.def(def_id).get("material", {})


func display_name() -> String:
	if upgrade_of:
		return "%s (upgrade to level %d)" % [super(), upgrade_of.level + 1]
	if dismantle:
		return "%s (taking down to move)" % super()
	if moved:
		return "%s (moving here)" % super()
	return "%s (construction)" % super()
