class_name GroundView
extends MeshInstance3D
## Flat grass ground for the whole map, shaded procedurally; darker floor under forest.

var world: World
var material: ShaderMaterial
var _forest_img: Image
var _forest_tex: ImageTexture
var _dirty := false


func setup(p_world: World) -> void:
	world = p_world
	var plane := PlaneMesh.new()
	var extent := world.size * Defs.TILE
	plane.size = Vector2(extent, extent)
	mesh = plane
	position = Vector3(extent * 0.5, 0.0, extent * 0.5)
	material = ShaderMaterial.new()
	material.shader = load("res://assets/shaders/ground.gdshader")
	material.set_shader_parameter("map_size", float(world.size))
	material.set_shader_parameter("tile", Defs.TILE)
	material_override = material

	_forest_img = Image.create(world.size, world.size, false, Image.FORMAT_R8)
	for y in world.size:
		for x in world.size:
			_write(Vector2i(x, y))
	_forest_tex = ImageTexture.create_from_image(_forest_img)
	material.set_shader_parameter("forest_map", _forest_tex)
	material.set_shader_parameter("water_map", ImageTexture.create_from_image(water_image(world)))
	world.tree_changed.connect(_on_tree_changed)


const WATER_RES := 4             # water mask texels per tile


## Smoothed water mask: 1 on water tiles, blurred over about a tile (binomial 1-4-6-4-1 in both
## directions) so the shoreline rounds off the steps of the river blocks, then scaled up with cubic
## interpolation. Shared with WaterView so the grass cut and the bed use the very same data.
## The middle of a 2-tile river reaches ~0.62; the original water edge lies at ~0.45.
static func water_image(w: World) -> Image:
	var n := w.size
	var a := PackedFloat32Array()
	a.resize(n * n)
	for i in n * n:
		a[i] = 1.0 if w.water[i] != Defs.Water.NONE else 0.0
	var k := [1.0 / 16.0, 4.0 / 16.0, 6.0 / 16.0, 4.0 / 16.0, 1.0 / 16.0]
	for axis in 2:
		var b := PackedFloat32Array()
		b.resize(n * n)
		for y in n:
			for x in n:
				var s := 0.0
				for o in range(-2, 3):
					var xx := clampi(x + o, 0, n - 1) if axis == 0 else x
					var yy := clampi(y + o, 0, n - 1) if axis == 1 else y
					s += a[yy * n + xx] * k[o + 2]
				b[y * n + x] = s
		a = b
	var bytes := PackedByteArray()
	bytes.resize(n * n)
	for i in n * n:
		bytes[i] = int(round(a[i] * 255.0))
	var img := Image.create_from_data(n, n, false, Image.FORMAT_R8, bytes)
	img.resize(n * WATER_RES, n * WATER_RES, Image.INTERPOLATE_CUBIC)
	return img


func show_grid(on: bool) -> void:
	material.set_shader_parameter("grid_strength", 0.35 if on else 0.0)


func highlight(rect: Rect2i, ok: bool) -> void:
	highlight_color(rect, Color(0.45, 0.95, 0.45) if ok else Color(0.95, 0.35, 0.3))


func highlight_color(rect: Rect2i, color: Color) -> void:
	material.set_shader_parameter("highlight_rect", Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))
	material.set_shader_parameter("highlight_color", color)


func _write(c: Vector2i) -> void:
	var i := world.idx(c)
	var v := 0.0
	if world.tree_kind[i] != Defs.TreeKind.NONE:
		v = [0.35, 0.7, 1.0][world.tree_stage[i]]
	_forest_img.set_pixel(c.x, c.y, Color(v, 0, 0))


func _on_tree_changed(c: Vector2i) -> void:
	_write(c)
	_dirty = true


func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		_forest_tex.update(_forest_img)
