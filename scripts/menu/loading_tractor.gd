class_name LoadingTractor
extends SubViewportContainer
## The loading screen's picture: a tractor with a grain cart driving along a field road, seen from
## the side, in its own little 3D world. It drives across and comes in again from the left.

const SPEED := 6.0            # m/s
const SPAN := 60.0            # m of road from one edge to the other (camera width)
const TREES := 14

var _rig: Node3D


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	add_child(vp)
	_build(vp)


func _build(vp: SubViewport) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#BFD9EE")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.78, 0.9)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	vp.add_child(sun)

	# grass, the field road, a field behind it and trees along the far edge
	vp.add_child(_plane(Vector3(0, 0, -10), Vector2(260, 100), UiStyle.GRASS))
	vp.add_child(_plane(Vector3(0, 0.02, 0), Vector2(220, 4.5), Color("#C9A06A")))
	vp.add_child(_plane(Vector3(0, 0.02, -8.5), Vector2(220, 8), UiStyle.WHEAT))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in TREES:
		var kind := "tree_deciduous_full" if rng.randf() < 0.6 else "tree_conifer_full"
		var tree := Models.instance(kind)
		tree.position = Vector3(-SPAN * 0.7 + i * SPAN * 1.4 / TREES + rng.randf_range(-1.5, 1.5), 0, -17 - rng.randf() * 4)
		tree.rotation.y = rng.randf() * TAU
		tree.scale = Vector3.ONE * rng.randf_range(0.9, 1.25)
		vp.add_child(tree)

	# tractor and cart (models face -z; turned to drive towards +x)
	_rig = Node3D.new()
	_rig.rotation.y = -PI * 0.5
	vp.add_child(_rig)
	var tractor := Models.instance("vehicle_tractor_basic_red")
	_rig.add_child(tractor)
	var cart := Models.instance("trailer_grain_cart_green")
	cart.position = Vector3(0, 0, 4.2)
	_rig.add_child(cart)
	_rig.position = Vector3(-SPAN * 0.5, 0, 0.6)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	# a low, nearly level look: the road in the lower part, sky above the tree line
	cam.rotation_degrees = Vector3(-10, 0, 0)
	cam.position = Vector3(0, 4.5, -8) + cam.basis.z * 40.0
	cam.size = SPAN
	vp.add_child(cam)


func _process(delta: float) -> void:
	_rig.position.x += SPEED * delta
	if _rig.position.x > SPAN * 0.5 + 8.0:
		_rig.position.x = -SPAN * 0.5 - 8.0


func _plane(at: Vector3, size: Vector2, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var p := PlaneMesh.new()
	p.size = size
	m.mesh = p
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	m.material_override = mat
	m.position = at
	return m
