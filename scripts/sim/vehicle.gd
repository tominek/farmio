class_name Vehicle
extends RefCounted
## A road vehicle (Light Pickup for now). Parked in its garage until a worker drives it.

var id: int
var kind := &"pickup_light"
var garage: Building
var pos: Vector2            # tile units
var heading := 0.0          # radians, 0 = facing grid -y
var block: Vector2i         # road block the vehicle is on (or next to, when parked)
var parked := true
var driver: Worker = null
var cargo := {}             # resource -> amount
var passengers: Array[Worker] = []   # new hires riding to the farm


func _init(p_id: int, p_garage: Building, p_block: Vector2i) -> void:
	id = p_id
	garage = p_garage
	block = p_block
	pos = parking_pos()
	var d := Vector2(Defs.DIRS[garage.rot])
	heading = atan2(d.x, -d.y)


func parking_pos() -> Vector2:
	var center := Vector2(garage.anchor) + Vector2(garage.size) * 0.5
	return center + Vector2(Defs.DIRS[garage.rot]) * 0.5


func cargo_total() -> float:
	var n := 0.0
	for k in cargo:
		n += cargo[k]
	return n
