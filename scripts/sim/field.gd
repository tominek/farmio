class_name Field
extends Building
## A crop field. Every row (strip) runs its own cycle cultivate → seed → grow → harvest, so
## several workers can work side by side and the field shows a visible gradient.

enum TileState { BARE, CULTIVATED, PLANTED, STUBBLE }
enum RowStep { CULTIVATE, SEED, GROW, HARVEST }

var crop: StringName
var tile_state: PackedByteArray
var growth: PackedFloat32Array
var row_step: PackedByteArray       # RowStep per row
var row_task: Array = []             # open Task per row (or null)
var pile := 0.0                      # harvested units lying at the gate
var pile_reserved := 0.0             # part of the pile already claimed by haul tasks
var dirty := true                    # presentation hint: tiles changed


func _init(p_id: int, p_anchor: Vector2i, p_rot: int, p_base_size: Vector2i, p_crop: StringName) -> void:
	super(p_id, &"field", p_anchor, p_rot, p_base_size)
	crop = p_crop
	tile_state.resize(size.x * size.y)
	growth.resize(size.x * size.y)
	row_step.resize(size.y)
	row_task.resize(size.y)


func local(c: Vector2i) -> int:
	return (c.y - anchor.y) * size.x + (c.x - anchor.x)


## Cells of a row in working order (serpentine, like a tractor going back and forth).
func row_cells(row: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in size.x:
		var x := i if row % 2 == 0 else size.x - 1 - i
		out.append(anchor + Vector2i(x, row))
	return out


func row_ripe(row: int) -> bool:
	for x in size.x:
		if growth[row * size.x + x] < 1.0:
			return false
	return true


func status() -> String:
	var counts := [0, 0, 0, 0]
	for r in size.y:
		counts[row_step[r]] += 1
	return "cultivate %d · seed %d · growing %d · harvest %d rows" % counts
