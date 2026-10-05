class_name Store
extends RefCounted
## Goods kept in one place: a barn, a site's supply, a mill's input or output, a field's gate pile,
## a moved building's pile, a ground pile (felled logs, goods dropped on the way). Holds what is
## there, how much fits (kg; pieces count by their weight), which goods it takes, and what legs
## have promised to take away or bring (reservations), so nothing is taken twice and nothing
## overfills.

enum Kind { STORAGE, SITE, INPUT, OUTPUT, GATE, MOVE_PILE, GROUND, DEALER }
## How the goods of a ground pile came to lie there (the info panel says why).
enum Origin { DROPPED, FELLED, CLEARED, ROAD }

var kind := Kind.STORAGE
var cell := Vector2i(-1, -1)  # where a worker stands to put goods in or take them out
var owner: Building = null    # the building, field or site it belongs to (null: a ground pile)
var contents := {}            # resource -> amount (kg, or pieces for piece goods)
var capacity := INF           # kg
var filter := {}              # resource -> true; empty: takes everything
var reserved_out := {}        # resource -> amount promised to someone taking it away
var reserved_in := {}         # resource -> amount on its way here
var category: int = Task.Category.TRANSPORT  # GROUND: what its legs count as (Felling for felled logs)
var origin := Origin.DROPPED   # GROUND: felled for a Cut trees order, cleared for a site, or put down
var reason := ""              # GROUND, dropped: why, in words ("the Garage site was cancelled. Bo had it…")
var site_name := ""           # GROUND: the site it was cleared for, or the cancelled site it was meant for
var hand_only := false        # GROUND: a road pile the player asked to carry to the barn by hand (not saved)


func _init(p_kind := Kind.STORAGE, p_owner: Building = null, p_cell := Vector2i(-1, -1)) -> void:
	kind = p_kind
	owner = p_owner
	cell = p_cell


## Name of the place for task labels and panels.
func label() -> String:
	if kind == Kind.DEALER:
		return "Dealer"
	if owner == null:
		return "road pile" if origin == Origin.ROAD else "ground pile"
	if kind == Kind.MOVE_PILE:
		return "%s (old spot)" % (owner as ConstructionSite).base_name()
	return owner.display_name()


## Only a vehicle can bring goods here or take them away (the Dealer).
func vehicle_only() -> bool:
	return kind == Kind.DEALER


func amount(res: StringName) -> float:
	return contents.get(res, 0.0)


## What is here and not promised to anyone.
func available(res: StringName) -> float:
	return maxf(0.0, amount(res) - reserved_out.get(res, 0.0))


func accepts(res: StringName) -> bool:
	return filter.is_empty() or filter.has(res)


func weight() -> float:
	var kg := 0.0
	for res: StringName in contents:
		kg += Defs.weight(res, contents[res])
	return kg


## Kg that still fit, counting what is on its way.
func room() -> float:
	var kg := weight()
	for res: StringName in reserved_in:
		kg += Defs.weight(res, reserved_in[res])
	return maxf(0.0, capacity - kg)


func put(res: StringName, n: float) -> void:
	if n <= 0.0:
		return
	contents[res] = amount(res) + n


## Takes up to `n`; returns what was taken.
func take(res: StringName, n: float) -> float:
	var got := minf(n, amount(res))
	if got <= 0.0:
		return 0.0
	contents[res] = amount(res) - got
	if contents[res] < 0.000001:
		contents.erase(res)
	return got


## Promises up to `n` of what is available; returns the promised amount.
func reserve_out(res: StringName, n: float) -> float:
	var got := minf(n, available(res))
	if got > 0.0:
		reserved_out[res] = reserved_out.get(res, 0.0) + got
	return got


func release_out(res: StringName, n: float) -> void:
	var left: float = reserved_out.get(res, 0.0) - n
	if left < 0.000001:
		reserved_out.erase(res)
	else:
		reserved_out[res] = left


## Promises room for `n` on its way here (callers check `room()` first).
func reserve_in(res: StringName, n: float) -> void:
	if n > 0.0:
		reserved_in[res] = reserved_in.get(res, 0.0) + n


func release_in(res: StringName, n: float) -> void:
	var left: float = reserved_in.get(res, 0.0) - n
	if left < 0.000001:
		reserved_in.erase(res)
	else:
		reserved_in[res] = left


func to_dict() -> Dictionary:
	return {"contents": contents.duplicate(), "capacity": capacity, "filter": filter.keys()}


## Reservations are not saved: claims are made again after loading.
static func from_dict(d: Dictionary) -> Store:
	var s := Store.new()
	for res in d.get("contents", {}):
		s.contents[StringName(res)] = float(d["contents"][res])
	s.capacity = float(d.get("capacity", INF))
	for res in d.get("filter", []):
		s.filter[StringName(res)] = true
	return s
