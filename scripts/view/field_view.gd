class_name FieldView
extends Node3D
## Fields: soil (shader + tile data texture), fence with gate, crops on a MultiMesh with
## continuous growth, stubble and the harvest pile at the gate.

const UPDATE_INTERVAL := 0.1
const CROP_Y := -0.08                  # crop meshes are authored on furrows ~0.1 m high

# shader parameters per crop (see crop.gdshader)
const CROP_LOOK := {
	&"wheat": {},
	&"potato": {
		"leaf_use_palette": 1.0, "leaf_full": 0.7, "leaf_wither": 0.3, "stalk_range": Vector2(0.0, 0.05),
		"ripe_plant": Color(0.72, 0.66, 0.33), "turning": Color(0.62, 0.66, 0.3), "ripe_range": Vector2(0.8, 0.98),
		"fruit_use_palette": 1.0, "fruit_range": Vector2(0.45, 0.55), "fruit_fade": 0.8,
	},
	&"corn": {
		"leaf_use_palette": 1.0, "leaf_full": 0.6, "leaf_wither": 0.0, "stalk_range": Vector2(0.15, 0.9),
		"ripe_plant": Color(0.80, 0.70, 0.45), "turning": Color(0.66, 0.68, 0.36), "ripe_range": Vector2(0.82, 0.98),
		"fruit_young": Color(0.5, 0.65, 0.3), "fruit_ripe": Color(0.85, 0.72, 0.42), "fruit_range": Vector2(0.6, 0.9),
		"sway_strength": 0.015,
	},
	&"beet": {
		"leaf_use_palette": 1.0, "leaf_full": 0.65, "leaf_wither": 0.0, "stalk_range": Vector2(0.0, 0.05),
		"ripe_plant": Color(0.55, 0.62, 0.28), "turning": Color(0.45, 0.6, 0.27), "ripe_range": Vector2(0.85, 1.0),
		"ripe_amount": 0.4, "fruit_use_palette": 1.0, "fruit_range": Vector2(0.5, 0.9),
	},
}
const SOIL_TINT := {
	&"wheat": [Color(0.42, 0.6, 0.25), Color(0.8, 0.67, 0.33)],
	&"potato": [Color(0.36, 0.55, 0.24), Color(0.6, 0.56, 0.32)],
	&"corn": [Color(0.38, 0.56, 0.23), Color(0.72, 0.64, 0.4)],
	&"beet": [Color(0.3, 0.5, 0.22), Color(0.36, 0.52, 0.24)],
}

var world: World
var _views := {}           # field id -> Dictionary of nodes
var _crop_materials := {}
var _accum := 0.0


func setup(p_world: World) -> void:
	world = p_world
	for b in world.buildings.values():
		_on_added(b)
	world.building_added.connect(_on_added)
	world.building_removed.connect(func(b: Building) -> void:
		if _views.has(b.id):
			(_views[b.id]["root"] as Node3D).queue_free()
			_views.erase(b.id))


func _crop_material(crop: StringName) -> ShaderMaterial:
	if not _crop_materials.has(crop):
		var m := ShaderMaterial.new()
		m.shader = load("res://assets/shaders/crop.gdshader")
		m.set_shader_parameter("palette", Models.palette.albedo_texture)
		var look: Dictionary = CROP_LOOK[crop]
		for k in look:
			m.set_shader_parameter(k, look[k])
		_crop_materials[crop] = m
	return _crop_materials[crop]


func _on_added(b: Building) -> void:
	if not (b is Field):
		return
	var f := b as Field
	var root := Node3D.new()
	add_child(root)
	var v := {"root": root}

	# soil
	var soil := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(f.size.x, f.size.y) * Defs.TILE
	soil.mesh = plane
	soil.position = Defs.footprint_center(f.anchor, f.size) + Vector3(0, 0.03, 0)
	var sm := ShaderMaterial.new()
	sm.shader = load("res://assets/shaders/soil.gdshader")
	sm.set_shader_parameter("field_origin", Vector2(f.anchor))
	sm.set_shader_parameter("field_size", Vector2(f.size))
	sm.set_shader_parameter("tile", Defs.TILE)
	sm.set_shader_parameter("crop_green", SOIL_TINT[f.crop][0])
	sm.set_shader_parameter("crop_ripe", SOIL_TINT[f.crop][1])
	var img := Image.create(f.size.x, f.size.y, false, Image.FORMAT_RG8)
	var tex := ImageTexture.create_from_image(img)
	sm.set_shader_parameter("tiles", tex)
	soil.material_override = sm
	root.add_child(soil)
	v["img"] = img
	v["tex"] = tex

	# crops + stubble share per-tile transforms (rows along x, random 180° flip)
	var crop_mm := _multimesh("crop_%s_full" % f.crop, f, true)
	var crops := MultiMeshInstance3D.new()
	crops.multimesh = crop_mm
	crops.material_override = _crop_material(f.crop)
	root.add_child(crops)
	var stubble_mm := _multimesh("crop_%s_stubble" % f.crop, f, false)
	var stubble := MultiMeshInstance3D.new()
	stubble.multimesh = stubble_mm
	stubble.material_override = Models.palette
	root.add_child(stubble)
	v["crops"] = crop_mm
	v["stubble"] = stubble_mm
	v["xforms"] = _tile_transforms(f)

	_build_fence(f, root)

	var pile := Models.instance("harvest_pile_%s" % f.crop)
	pile.position = Defs.cell_center(f.access)
	pile.rotation.y = -f.rot * PI * 0.5
	pile.visible = false
	root.add_child(pile)
	v["pile"] = pile

	_views[f.id] = v
	f.dirty = true
	_update(f)


func _multimesh(model: String, f: Field, custom: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = custom
	mm.mesh = Models.mesh(model)
	mm.instance_count = f.size.x * f.size.y
	return mm


func _tile_transforms(f: Field) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for y in f.size.y:
		for x in f.size.x:
			var c := f.anchor + Vector2i(x, y)
			var angle := PI * 0.5 + (PI if hash(c) % 2 == 0 else 0.0)
			out.append(Transform3D(Basis(Vector3.UP, angle), Defs.cell_center(c) + Vector3(0, CROP_Y, 0)))
	return out


func _build_fence(f: Field, root: Node3D) -> void:
	var gate_cell := f.access - Defs.DIRS[f.rot]       # field tile behind the gate
	var r := f.rect()
	var t := Defs.TILE
	for x in range(r.position.x, r.end.x):
		for top in [true, false]:
			var y := r.position.y if top else r.end.y - 1
			var is_gate := Vector2i(x, y) == gate_cell and Defs.DIRS[f.rot].y == (-1 if top else 1)
			var node := Models.instance("fence_gate" if is_gate else "fence_segment")
			node.position = Vector3((x + 0.5) * t, 0, (r.position.y if top else r.end.y) * t)
			node.rotation.y = -f.rot * PI * 0.5 if is_gate else 0.0
			root.add_child(node)
	for y in range(r.position.y, r.end.y):
		for left in [true, false]:
			var x := r.position.x if left else r.end.x - 1
			var is_gate := Vector2i(x, y) == gate_cell and Defs.DIRS[f.rot].x == (-1 if left else 1)
			var node := Models.instance("fence_gate" if is_gate else "fence_segment")
			node.position = Vector3((r.position.x if left else r.end.x) * t, 0, (y + 0.5) * t)
			node.rotation.y = -f.rot * PI * 0.5 if is_gate else PI * 0.5
			root.add_child(node)
	for corner in [r.position, Vector2i(r.end.x, r.position.y), Vector2i(r.position.x, r.end.y), r.end]:
		var post := Models.instance("fence_corner")
		post.position = Vector3(corner.x * t, 0, corner.y * t)
		root.add_child(post)


func _process(delta: float) -> void:
	_accum += delta
	if _accum < UPDATE_INTERVAL:
		return
	_accum = 0.0
	for f in world.fields:
		_update(f)


func _update(f: Field) -> void:
	var v: Dictionary = _views.get(f.id, {})
	if v.is_empty():
		return
	var crop_mm: MultiMesh = v["crops"]
	var stubble_mm: MultiMesh = v["stubble"]
	var xforms: Array[Transform3D] = v["xforms"]
	var img: Image = v["img"]
	var hidden := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	for i in f.tile_state.size():
		var state := f.tile_state[i]
		var g := f.growth[i] if state == Field.TileState.PLANTED else 0.0
		crop_mm.set_instance_custom_data(i, Color(g, 0, 0, 0))
		if f.dirty:
			crop_mm.set_instance_transform(i, xforms[i] if state == Field.TileState.PLANTED else hidden)
			stubble_mm.set_instance_transform(i, xforms[i] if state == Field.TileState.STUBBLE else hidden)
		img.set_pixel(i % f.size.x, i / f.size.x, Color(state / 3.0, g, 0))
	(v["tex"] as ImageTexture).update(img)
	var pile: Node3D = v["pile"]
	pile.visible = f.pile > 0.01
	pile.scale = Vector3.ONE * clampf(0.45 + f.pile / 600.0, 0.45, 1.4)
	f.dirty = false
