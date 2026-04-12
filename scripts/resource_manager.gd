extends Node

## Global resource tracking. Manages what resources exist and their amounts.

enum ResourceType {
	POTATOES,
	WHEAT,
	CORN,
	SUGAR_BEET,
	WOOD,
	PLANKS,
	FLOUR,
	SUGAR,
	BREAD,
	PASTA,
}

# Per-building inventory: node instance_id -> { resource_type: amount }
var _inventories: Dictionary = {}


func register_building(building: Node) -> void:
	_inventories[building.get_instance_id()] = {}


func unregister_building(building: Node) -> void:
	_inventories.erase(building.get_instance_id())


func add_resource(building: Node, resource_type: int, amount: int) -> void:
	var inv: Dictionary = _get_inventory(building)
	if inv.has(resource_type):
		inv[resource_type] = (inv[resource_type] as int) + amount
	else:
		inv[resource_type] = amount


func get_resource(building: Node, resource_type: int) -> int:
	var inv: Dictionary = _get_inventory(building)
	if inv.has(resource_type):
		return inv[resource_type] as int
	return 0


func get_all_resources(building: Node) -> Dictionary:
	return _get_inventory(building)


func get_total_resource(resource_type: int) -> int:
	var total := 0
	for inv in _inventories.values():
		var inv_dict: Dictionary = inv as Dictionary
		if inv_dict.has(resource_type):
			total += inv_dict[resource_type] as int
	return total


func _get_inventory(building: Node) -> Dictionary:
	var id: int = building.get_instance_id()
	if not _inventories.has(id):
		_inventories[id] = {}
	return _inventories[id]


func reset() -> void:
	_inventories.clear()


static func resource_name(res_type: int) -> String:
	match res_type:
		ResourceType.POTATOES: return "Potatoes"
		ResourceType.WHEAT: return "Wheat"
		ResourceType.CORN: return "Corn"
		ResourceType.SUGAR_BEET: return "Sugar Beet"
		ResourceType.WOOD: return "Wood"
		ResourceType.PLANKS: return "Planks"
		ResourceType.FLOUR: return "Flour"
		ResourceType.SUGAR: return "Sugar"
		ResourceType.BREAD: return "Bread"
		ResourceType.PASTA: return "Pasta"
		_: return "Unknown"
