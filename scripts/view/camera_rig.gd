class_name CameraRig
extends Node3D
## Angled orthographic camera: fixed tilt, free rotation (Q/E, middle mouse), WASD pan,
## smooth wheel zoom. Trackpad (macOS): two-finger scroll up / down zooms, left / right rotates,
## pinch zooms too; the map is panned with WASD.

const TILT := 45.0
const DISTANCE := 160.0
const ZOOM_MIN := 10.0
const ZOOM_MAX := 260.0
const GESTURE_ZOOM := 0.03          # trackpad two-finger scroll: zoom per unit up / down
const GESTURE_ROTATE := 0.04        # radians per unit left / right

var camera: Camera3D
var bounds := Rect2(0, 0, 768, 768)
var _target_size := 50.0
var _target_yaw := 0.0
var _follow: Variant = null          # a Worker or a Vehicle (anything with pos) kept centred until the player pans or zooms


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


## Keeps a worker or a vehicle in the centre until the player pans or zooms (null stops).
func follow(t: Variant) -> void:
	_follow = t


func focus(p: Vector3, zoom := -1.0) -> void:
	_follow = null
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
		_follow = null
		position += (basis * move.normalized()) * delta * camera.size * 0.8
	if _follow:
		position = Vector3(_follow.pos.x * Defs.TILE, 0.0, _follow.pos.y * Defs.TILE)
	position.x = clampf(position.x, bounds.position.x, bounds.end.x)
	position.z = clampf(position.z, bounds.position.y, bounds.end.y)

	camera.size = lerpf(camera.size, _target_size, minf(1.0, delta * 10.0))


func _unhandled_input(event: InputEvent) -> void:
	# wheel and trackpad scrolling over a panel scroll the panel, never the map
	if (event is InputEventMouseButton or event is InputEventPanGesture or event is InputEventMagnifyGesture) \
			and _over_ui():
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(0.88)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(1.14)
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		_target_yaw -= event.relative.x * 0.006
		rotation.y = _target_yaw
	elif event is InputEventMagnifyGesture:
		_zoom_by(1.0 / event.factor)
	elif event is InputEventPanGesture:
		# the dominant direction wins, so a slightly diagonal swipe doesn't zoom and rotate at once
		if absf(event.delta.y) >= absf(event.delta.x):
			_zoom_by(1.0 + event.delta.y * GESTURE_ZOOM)
		else:
			_target_yaw -= event.delta.x * GESTURE_ROTATE
		get_viewport().set_input_as_handled()


## True when the mouse is over a control that takes the mouse (a panel, the bar, the dock).
func _over_ui() -> bool:
	var c := get_viewport().gui_get_hovered_control()
	return c != null and c.mouse_filter != Control.MOUSE_FILTER_IGNORE


## Ground point (y = 0) under a screen position, or null.
func ground_point(screen: Vector2) -> Variant:
	var from := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return null
	var t := -from.y / dir.y
	return from + dir * t


func _zoom_by(factor: float) -> void:
	_follow = null
	_target_size = clampf(_target_size * factor, ZOOM_MIN, ZOOM_MAX)
