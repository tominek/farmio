class_name CameraRig
extends Node3D
## Angled orthographic camera: fixed tilt, free rotation (Q/E, middle mouse), WASD pan,
## smooth wheel zoom.

const TILT := 45.0
const DISTANCE := 160.0
const ZOOM_MIN := 10.0
const ZOOM_MAX := 260.0

var camera: Camera3D
var bounds := Rect2(0, 0, 768, 768)
var _target_size := 70.0
var _target_yaw := 0.0


func _ready() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = _target_size
	camera.near = 1.0
	camera.far = 800.0
	camera.rotation_degrees.x = -TILT
	camera.position = Vector3(0, DISTANCE * sin(deg_to_rad(TILT)), DISTANCE * cos(deg_to_rad(TILT)))
	add_child(camera)
	_target_yaw = rotation.y


func focus(p: Vector3, zoom := -1.0) -> void:
	position = Vector3(p.x, 0, p.z)
	if zoom > 0.0:
		_target_size = zoom
		camera.size = zoom


func set_yaw_degrees(deg: float) -> void:
	_target_yaw = deg_to_rad(deg)
	rotation.y = _target_yaw


func _process(delta: float) -> void:
	var rot := 0.0
	if Input.is_key_pressed(KEY_Q):
		rot += 1.0
	if Input.is_key_pressed(KEY_E):
		rot -= 1.0
	_target_yaw += rot * delta * 1.6
	rotation.y = lerp_angle(rotation.y, _target_yaw, minf(1.0, delta * 12.0))

	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		move.z -= 1
	if Input.is_key_pressed(KEY_S):
		move.z += 1
	if Input.is_key_pressed(KEY_A):
		move.x -= 1
	if Input.is_key_pressed(KEY_D):
		move.x += 1
	if move != Vector3.ZERO:
		position += (basis * move.normalized()) * delta * camera.size * 0.8
	position.x = clampf(position.x, bounds.position.x, bounds.end.x)
	position.z = clampf(position.z, bounds.position.y, bounds.end.y)

	camera.size = lerpf(camera.size, _target_size, minf(1.0, delta * 10.0))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_size = maxf(ZOOM_MIN, _target_size * 0.88)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_size = minf(ZOOM_MAX, _target_size * 1.14)
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		_target_yaw -= event.relative.x * 0.006
		rotation.y = _target_yaw


## Ground point (y = 0) under a screen position, or null.
func ground_point(screen: Vector2) -> Variant:
	var from := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return null
	var t := -from.y / dir.y
	return from + dir * t
