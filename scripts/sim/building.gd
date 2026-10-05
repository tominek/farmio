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
var priority := 0           # player override: +1 High, 0 Normal, -1 Low (one category level each)
var level := 1              # upgrades raise it to 2 and 3 (processing buildings)
var materials := {}         # materials that went into it (building and upgrades), returned when demolished
var upgrading: ConstructionSite = null   # running upgrade, the building does not work meanwhile
# processing buildings (mills, sawmill): goods inside, see Defs "process"
var input_store: Store = null       # raw goods brought in, waiting to be processed
var output_store: Store = null      # products waiting to be carried to storage
## Amount of the recipe's raw good in `input_store`.
var input: float:
	get:
		return input_store.amount(_good("in")) if input_store else 0.0
	set(v):
		if input_store:
			_set_amount(input_store, _good("in"), v)
var incoming := 0.0         # raw goods on their way from storage (supply tasks)
## Amount of the recipe's product in `output_store`.
var output: float:
	get:
		return output_store.amount(_good("out")) if output_store else 0.0
	set(v):
		if output_store:
			_set_amount(output_store, _good("out"), v)
var out_reserved := 0.0     # part of the output already taken by carry tasks
var process_task: Task = null
var store: Store = null             # storage buildings: the goods kept here


func _init(p_id: int, p_def_id: StringName, p_anchor: Vector2i, p_rot: int, p_base_size := Vector2i.ZERO) -> void:
	id = p_id
	def_id = p_def_id
	anchor = p_anchor
	rot = p_rot
	base_size = p_base_size if p_base_size != Vector2i.ZERO else Defs.def(def_id)["size"]
	size = Defs.rotated(base_size, rot)
	access = Defs.access_for(base_size, anchor, rot)
	var r: Dictionary = Defs.def(def_id).get("process", {})
	if not r.is_empty():
		input_store = Store.new(Store.Kind.INPUT, self, access)
		input_store.filter = {r["in"]: true}
		output_store = Store.new(Store.Kind.OUTPUT, self, access)
		output_store.filter = {r["out"]: true}


## The recipe's raw good ("in") or product ("out").
func _good(key: String) -> StringName:
	return Defs.def(def_id)["process"][key]

## Sets the amount of `res` in a store (used by the buffer properties of buildings, fields, sites).
static func _set_amount(s: Store, res: StringName, v: float) -> void:
	if v > 0.0:
		s.contents[res] = v
	else:
		s.contents.erase(res)


func rect() -> Rect2i:
	return Rect2i(anchor, size)


func cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in size.y:
		for x in size.x:
			out.append(anchor + Vector2i(x, y))
	return out


## The processing recipe of the building at its level, or {} (see Defs.BUILDINGS "process"):
## higher levels work faster and hold more.
func recipe() -> Dictionary:
	var r: Dictionary = Defs.def(def_id).get("process", {})
	if r.is_empty() or level == 1:
		return r
	r = r.duplicate()
	r["work"] *= Defs.LEVEL_WORK[level]
	r["in_cap"] *= Defs.LEVEL_ROOM[level]
	r["out_cap"] *= Defs.LEVEL_ROOM[level]
	return r


## Model of the building at its level.
func model() -> String:
	var m: String = Defs.def(def_id)["model"]
	return m if level == 1 else "%s_l%d" % [m, level]


func display_name() -> String:
	return Defs.def(def_id)["name"]
