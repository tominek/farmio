extends Node3D

## Camera controller with perspective projection.
## WASD to pan, scroll wheel to zoom (moves camera height), edge scrolling optional.

@export var pan_speed: float = 30.0
@export var zoom_speed: float = 3.0
@export var min_height: float = 15.0
@export var max_height: float = 150.0
@export var edge_scroll_margin: int = 20
@export var edge_scroll_enabled: bool = false
@export var camera_angle: float = 50.0  # degrees from horizontal

@onready var camera: Camera3D = $Camera3D

var _target_height: float = 60.0
var _map_half_size: float = 0.0


func _ready() -> void:
	_target_height = camera.global_position.y
	_map_half_size = GameSettings.map_size * 3.0 * 0.5
	_update_camera_position()
	process_mode = Node.PROCESS_MODE_ALWAYS


func set_map_bounds(map_size: int) -> void:
	_map_half_size = map_size * 3.0 * 0.5


func _process(_delta: float) -> void:
	# Use real (unscaled) time so camera works even when paused
	var real_delta: float = _delta / maxf(Engine.time_scale, 0.001) if Engine.time_scale > 0 else 0.016
	_handle_pan(real_delta)
	_handle_zoom(real_delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_height = max(_target_height - zoom_speed, min_height)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_height = min(_target_height + zoom_speed, max_height)


func _handle_pan(delta: float) -> void:
	var direction := Vector3.ZERO

	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		direction.z -= 1
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		direction.z += 1
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		direction.x -= 1
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		direction.x += 1

	if edge_scroll_enabled:
		var viewport := get_viewport()
		var mouse_pos := viewport.get_mouse_position()
		var screen_size := viewport.get_visible_rect().size

		if mouse_pos.x < edge_scroll_margin:
			direction.x -= 1
		elif mouse_pos.x > screen_size.x - edge_scroll_margin:
			direction.x += 1
		if mouse_pos.y < edge_scroll_margin:
			direction.z -= 1
		elif mouse_pos.y > screen_size.y - edge_scroll_margin:
			direction.z += 1

	if direction != Vector3.ZERO:
		direction = direction.normalized()
		var zoom_factor := camera.global_position.y / 60.0
		position += direction * pan_speed * zoom_factor * delta

		if _map_half_size > 0:
			position.x = clampf(position.x, -_map_half_size, _map_half_size)
			position.z = clampf(position.z, -_map_half_size, _map_half_size)


func _handle_zoom(delta: float) -> void:
	var current_height := camera.position.y
	var new_height: float = lerp(current_height, _target_height, 10.0 * delta)
	camera.position.y = new_height

	# Adjust Z offset to maintain the viewing angle
	var angle_rad := deg_to_rad(camera_angle)
	camera.position.z = new_height / tan(angle_rad)


func _update_camera_position() -> void:
	var angle_rad := deg_to_rad(camera_angle)
	camera.position.y = _target_height
	camera.position.z = _target_height / tan(angle_rad)

	# Point camera at the rig's origin
	camera.rotation.x = -angle_rad - PI / 2.0 + PI / 2.0
	camera.look_at(global_position, Vector3.UP)
