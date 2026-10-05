class_name PileView
extends Node3D
## Ground piles (felled logs, goods put down when a leg broke, road piles beside a road): the
## pile's look by fill level (weight / capacity): up to ⅓, up to ⅔, full (design 17d) — big enough
## to read at the default zoom, up to most of the tile when full. Logs stack in a neat pyramid (one
## layer, two layers, three), all parallel, ends showing. Planks stack in neat aligned columns (a
## low stack, a taller stack, two tall stacks side by side). Sacks/crates (whatever good; the carry
## model from `WorkerFigure.CARRY_MODEL`) cluster tightly, a second layer on top when full. Gravel
## (no carried model) is a flattened procedural mound with a few darker stones on top, grey, built
## once and shared. A faint darker patch (also shared, built once) sits under every pile, like the
## tile base in the design. Rebuilt only on pile signals, and only when the good or fill level
## actually changed (`_keys` caches the last one per pile) — no per-frame work.

const LEVEL_FRAC: Array[float] = [1.0 / 3.0, 2.0 / 3.0]   # "up to ⅓" / "up to ⅔"; above is "full"

const PATCH_RADIUS: Array[float] = [0.65, 0.95, 1.3]
const LOG_SCALE := 2.2
const LOG_LAYERS: Array[int] = [1, 2, 3]      # pyramid layers by level
const LOG_BASE := 3                # logs in the bottom layer
const PLANK_SCALE := 1.9
const PLANK_COLS: Array[int] = [1, 1, 2]       # stacks side by side by level
const PLANK_ROWS: Array[int] = [1, 3, 4]       # planks stacked in each column by level
const SACK_SCALE := 2.1
const SACK_COUNTS: Array[int] = [1, 3, 6]
const GRAVEL_RADIUS: Array[float] = [0.55, 0.85, 1.2]
const GRAVEL_HEIGHT_FRAC := 0.5     # mound height = radius × this (flattened, not a full dome)
const GRAVEL_STONES: Array[int] = [0, 2, 4]

var world: World
var _nodes := {}           # Store -> Node3D
var _keys := {}            # Store -> last "<res>#<level>" built, "" when empty
var _patch_mesh: Array[Mesh] = []
var _patch_material: StandardMaterial3D
var _gravel_mesh: Array[SphereMesh] = []
var _gravel_material: StandardMaterial3D
var _stone_mesh: SphereMesh
var _stone_material: StandardMaterial3D


func _init() -> void:
	_patch_material = StandardMaterial3D.new()
	_patch_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_patch_material.albedo_color = Color(0.09, 0.13, 0.05, 0.18)
	_patch_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_patch_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for r in PATCH_RADIUS:
		var m := CylinderMesh.new()
		m.top_radius = r
		m.bottom_radius = r
		m.height = 0.02
		m.radial_segments = 16
		_patch_mesh.append(m)

	_gravel_material = StandardMaterial3D.new()
	_gravel_material.albedo_color = Color("#8C8C8C")
	_gravel_material.roughness = 1.0
	_gravel_material.metallic_specular = 0.0
	for r in GRAVEL_RADIUS:
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * GRAVEL_HEIGHT_FRAC
		m.is_hemisphere = true
		m.radial_segments = 14
		m.rings = 6
		_gravel_mesh.append(m)

	_stone_material = StandardMaterial3D.new()
	_stone_material.albedo_color = Color("#5C5C5C")
	_stone_material.roughness = 1.0
	_stone_material.metallic_specular = 0.0
	_stone_mesh = SphereMesh.new()
	_stone_mesh.radius = 0.11
	_stone_mesh.height = 0.16
	_stone_mesh.is_hemisphere = true
	_stone_mesh.radial_segments = 6
	_stone_mesh.rings = 3


func setup(p_world: World) -> void:
	world = p_world
	for s in world.ground_piles:
		_on_added(s)
	world.pile_added.connect(_on_added)
	world.pile_changed.connect(_update)
	world.pile_removed.connect(_on_removed)


func _on_added(s: Store) -> void:
	var node := Node3D.new()
	node.position = Defs.cell_center(s.cell)
	node.rotation.y = float(hash(s.cell) % 628) * 0.01   # piles don't all lie the same way
	add_child(node)
	_nodes[s] = node
	_update(s)


func _on_removed(s: Store) -> void:
	var node: Node3D = _nodes.get(s)
	if node:
		node.queue_free()
	_nodes.erase(s)
	_keys.erase(s)


## Fill level of a pile or store holding `frac` of its capacity: 0 up to ⅓, 1 up to ⅔, 2 full.
static func level_of(frac: float) -> int:
	if frac <= LEVEL_FRAC[0] + 0.0005:
		return 0
	if frac <= LEVEL_FRAC[1] + 0.0005:
		return 1
	return 2


func _update(s: Store) -> void:
	var node: Node3D = _nodes.get(s)
	if node == null:
		return
	if s.contents.is_empty():
		if _keys.get(s, "") != "":
			for child in node.get_children():
				child.queue_free()
			_keys[s] = ""
		return
	var res: StringName = s.contents.keys()[0]
	var level := level_of(s.weight() / maxf(s.capacity, 1.0))
	var key := "%s#%d" % [res, level]
	if _keys.get(s, "") == key:
		return
	_keys[s] = key
	for child in node.get_children():
		child.queue_free()

	var patch := MeshInstance3D.new()
	patch.mesh = _patch_mesh[level]
	patch.material_override = _patch_material
	patch.position.y = 0.01
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(patch)
	dress(node, res, level)


## Puts the goods of one pile look (logs, planks, sacks / crates or gravel at `level`) on `node`,
## in a child scaled by `goods_scale`: ground piles use 1.0, a building dresses goods on itself
## smaller (a collection point). The caller clears old dressing first.
func dress(node: Node3D, res: StringName, level: int, goods_scale := 1.0) -> void:
	var goods := Node3D.new()
	goods.scale = Vector3.ONE * goods_scale
	node.add_child(goods)
	if res == &"gravel":
		_place_gravel(goods, level)
		return
	var model: String = WorkerFigure.CARRY_MODEL.get(res, "carry_sack")
	var box := Models.mesh(model).get_aabb()
	match model:
		"carry_logs":
			_place_logs(goods, model, box, level)
		"carry_planks":
			_place_planks(goods, model, box, level)
		_:
			_place_sacks(goods, model, box, level)


## Logs: a pyramid of parallel logs, lying side by side, ends showing — one layer, two, three.
func _place_logs(node: Node3D, model: String, box: AABB, level: int) -> void:
	var layers := LOG_LAYERS[level]
	var spacing := box.size.z * LOG_SCALE * 0.92   # snug: slightly less than a full diameter apart
	var rise := box.size.y * LOG_SCALE * 0.85
	var base_y := -box.position.y * LOG_SCALE
	for layer in layers:
		var n := LOG_BASE - layer
		for col in n:
			var side := float(col) - float(n - 1) * 0.5
			var p := Models.instance(model)
			p.scale = Vector3.ONE * LOG_SCALE
			p.rotation.y = PI * 0.5   # length away from the camera, round ends toward it (unlike planks)
			p.position = Vector3(side * spacing, base_y + layer * rise, 0.0)
			node.add_child(p)


## Planks: neat aligned columns, no crossing — a low stack, a taller stack, two tall stacks.
func _place_planks(node: Node3D, model: String, box: AABB, level: int) -> void:
	var cols := PLANK_COLS[level]
	var rows := PLANK_ROWS[level]
	var col_spacing := box.size.z * PLANK_SCALE * 1.05
	var rise := box.size.y * PLANK_SCALE * 0.92
	var base_y := -box.position.y * PLANK_SCALE
	for row in rows:
		for col in cols:
			var side := float(col) - float(cols - 1) * 0.5
			var p := Models.instance(model)
			p.scale = Vector3.ONE * PLANK_SCALE
			p.position = Vector3(0.0, base_y + row * rise, side * col_spacing)
			node.add_child(p)


## Sacks / crates: a tight cluster (one, a triangle of three), a second layer on top when full.
func _place_sacks(node: Node3D, model: String, box: AABB, level: int) -> void:
	var count := SACK_COUNTS[level]
	var base_y := -box.position.y * SACK_SCALE
	if count == 1:
		var p := Models.instance(model)
		p.scale = Vector3.ONE * SACK_SCALE
		p.position = Vector3(0.0, base_y, 0.0)
		node.add_child(p)
		return
	var radius := box.size.x * SACK_SCALE * 0.38
	var rise := box.size.y * SACK_SCALE * 0.8
	for i in count:
		var layer := i / 3
		var idx := i % 3
		var ang := idx * TAU / 3.0 + PI / 6.0 + layer * 0.3
		var r := radius * (1.0 - 0.12 * layer)
		var p := Models.instance(model)
		p.scale = Vector3.ONE * SACK_SCALE
		p.position = Vector3(cos(ang) * r, base_y + layer * rise, sin(ang) * r)
		p.rotation.y = ang
		node.add_child(p)


## Gravel: a flattened mound, grey, growing per level; a few darker stones scattered on top.
func _place_gravel(node: Node3D, level: int) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _gravel_mesh[level]
	mi.material_override = _gravel_material
	node.add_child(mi)
	var r := GRAVEL_RADIUS[level]
	var top := r * GRAVEL_HEIGHT_FRAC
	var n := GRAVEL_STONES[level]
	for i in n:
		var ang := (float(i) / n) * TAU + float(i) * 0.9
		var rr := r * 0.35 * (0.6 + 0.4 * float(i % 3) / 2.0)   # toward the middle, where the mound is tall
		var ratio := rr / r
		var surface_y := top * sqrt(maxf(0.0, 1.0 - ratio * ratio))   # sit on the dome, not buried in it
		var sp := MeshInstance3D.new()
		sp.mesh = _stone_mesh
		sp.material_override = _stone_material
		sp.position = Vector3(cos(ang) * rr, surface_y, sin(ang) * rr)
		node.add_child(sp)
