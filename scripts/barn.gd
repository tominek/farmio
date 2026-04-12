extends Node3D

## Storage barn. Receives resources from workers and tracks inventory.


func _ready() -> void:
	ResourceManager.register_building(self)


func _exit_tree() -> void:
	ResourceManager.unregister_building(self)


func receive_resource(resource_type: int, amount: int) -> void:
	ResourceManager.add_resource(self, resource_type, amount)


func get_inventory() -> Dictionary:
	return ResourceManager.get_all_resources(self)
