extends Node3D

## Draws a visual grid overlay around the camera position.
## Shows tile boundaries to help with placement.

const TILE_SIZE: float = 3.0

@export var grid_radius: int = 60  # tiles in each direction from camera
@export var grid_color: Color = Color(1, 1, 1, 0.15)
@export var visible_by_default: bool = false
@export var hide_above_height: float = 100.0

var _mesh_instance: MeshInstance3D
var _material: StandardMaterial3D
var _last_camera_tile: Vector2i = Vector2i(-9999, -9999)


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.albedo_color = grid_color
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.no_depth_test = false

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_instance)

	visible = visible_by_default
	_rebuild_grid(Vector2i.ZERO)


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return

	# Auto-hide when zoomed out too far
	if camera.global_position.y > hide_above_height:
		_mesh_instance.visible = false
		return
	else:
		_mesh_instance.visible = visible

	if not visible:
		return

	var camera_tile := GridManager.world_to_tile(camera.global_position * Vector3(1, 0, 1) + Vector3(0, 0, camera.global_position.y * 0.5))
	# Simplified: just use the camera rig's position
	var rig := camera.get_parent()
	if rig:
		camera_tile = GridManager.world_to_tile(rig.global_position)

	if camera_tile != _last_camera_tile:
		_rebuild_grid(camera_tile)
		_last_camera_tile = camera_tile


func _unhandled_input(event: InputEvent) -> void:
	# Toggle grid with # key (NumberSign)
	if event is InputEventKey and event.pressed and event.keycode == KEY_NUMBERSIGN:
		visible = !visible


func _rebuild_grid(center: Vector2i) -> void:
	var im := ImmediateMesh.new()

	im.surface_begin(Mesh.PRIMITIVE_LINES)

	var half := grid_radius
	var start_x := (center.x - half) * TILE_SIZE - TILE_SIZE * 0.5
	var end_x := (center.x + half) * TILE_SIZE + TILE_SIZE * 0.5
	var start_z := (center.y - half) * TILE_SIZE - TILE_SIZE * 0.5
	var end_z := (center.y + half) * TILE_SIZE + TILE_SIZE * 0.5
	var y := 0.02  # slightly above ground to avoid z-fighting

	# Vertical lines (along Z)
	for x in range(center.x - half, center.x + half + 1):
		var wx := x * TILE_SIZE - TILE_SIZE * 0.5
		im.surface_add_vertex(Vector3(wx, y, start_z))
		im.surface_add_vertex(Vector3(wx, y, end_z))

	# Horizontal lines (along X)
	for z in range(center.y - half, center.y + half + 1):
		var wz := z * TILE_SIZE - TILE_SIZE * 0.5
		im.surface_add_vertex(Vector3(start_x, y, wz))
		im.surface_add_vertex(Vector3(end_x, y, wz))

	im.surface_end()
	im.surface_set_material(0, _material)

	_mesh_instance.mesh = im


func show_grid() -> void:
	visible = true


func hide_grid() -> void:
	visible = false
