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
	world.tree_changed.connect(_on_tree_changed)


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
