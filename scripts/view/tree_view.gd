class_name TreeView
extends Node3D
## Natural trees as MultiMeshes in chunks; a chunk is rebuilt when one of its trees changes.
## Trees marked for felling carry a small axe badge above the crown.

const CHUNK := 32
const MODELS := {
	Vector2i(Defs.TreeKind.DECIDUOUS, Defs.TreeStage.SAPLING): "tree_deciduous_sapling",
	Vector2i(Defs.TreeKind.DECIDUOUS, Defs.TreeStage.SMALL): "tree_deciduous_small",
	Vector2i(Defs.TreeKind.DECIDUOUS, Defs.TreeStage.FULL): "tree_deciduous_full",
	Vector2i(Defs.TreeKind.CONIFER, Defs.TreeStage.SAPLING): "tree_conifer_sapling",
	Vector2i(Defs.TreeKind.CONIFER, Defs.TreeStage.SMALL): "tree_conifer_small",
	Vector2i(Defs.TreeKind.CONIFER, Defs.TreeStage.FULL): "tree_conifer_full",
}

var world: World
var _chunks := {}          # Vector2i chunk -> { model key -> MultiMeshInstance3D }
var _dirty := {}
var _badges := {}          # marked tree -> Sprite3D
var _badge_tex: Texture2D


func setup(p_world: World) -> void:
	world = p_world
	var n := ceili(float(world.size) / CHUNK)
	for cy in n:
		for cx in n:
			_rebuild(Vector2i(cx, cy))
	world.tree_changed.connect(func(c: Vector2i) -> void: _dirty[c / CHUNK] = true)
	_badge_tex = load("res://assets/ui/icons/kit/cut.svg")
	for c: Vector2i in world.marked:
		_update_badge(c)
	world.tree_marked.connect(_update_badge)


## Shows or removes the axe badge of a tree.
func _update_badge(c: Vector2i) -> void:
	var s: Sprite3D = _badges.get(c)
	if not world.marked.has(c):
		if s:
			s.queue_free()
			_badges.erase(c)
		return
	if s:
		return
	s = Sprite3D.new()
	s.texture = _badge_tex
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.no_depth_test = true
	s.render_priority = 1
	s.pixel_size = 1.8 / _badge_tex.get_width()       # almost two metres across
	var i := world.idx(c)
	var key := Vector2i(world.tree_kind[i], world.tree_stage[i])
	var top := Models.mesh(MODELS[key]).get_aabb().end.y if MODELS.has(key) else 4.0
	s.position = _transform(c).origin + Vector3(0.0, top + 0.7, 0.0)
	add_child(s)
	_badges[c] = s


func _process(_delta: float) -> void:
	for ch in _dirty:
		_rebuild(ch)
	_dirty.clear()


func _rebuild(ch: Vector2i) -> void:
	var lists := {}
	for key in MODELS:
		lists[key] = []
	var x0 := ch.x * CHUNK
	var y0 := ch.y * CHUNK
	for y in range(y0, mini(y0 + CHUNK, world.size)):
		for x in range(x0, mini(x0 + CHUNK, world.size)):
			var i := y * world.size + x
			var k := world.tree_kind[i]
			if k == Defs.TreeKind.NONE:
				continue
			lists[Vector2i(k, world.tree_stage[i])].append(_transform(Vector2i(x, y)))
	var nodes: Dictionary = _chunks.get(ch, {})
	for key in MODELS:
		var xforms: Array = lists[key]
		var mmi: MultiMeshInstance3D = nodes.get(key)
		if xforms.is_empty():
			if mmi:
				mmi.queue_free()
				nodes.erase(key)
			continue
		if mmi == null:
			mmi = MultiMeshInstance3D.new()
			mmi.multimesh = MultiMesh.new()
			mmi.multimesh.transform_format = MultiMesh.TRANSFORM_3D
			mmi.multimesh.mesh = Models.mesh(MODELS[key])
			mmi.material_override = Models.palette
			add_child(mmi)
			nodes[key] = mmi
		mmi.multimesh.instance_count = xforms.size()
		for j in xforms.size():
			mmi.multimesh.set_instance_transform(j, xforms[j])
	_chunks[ch] = nodes


func _transform(c: Vector2i) -> Transform3D:
	var h := hash(c)
	var angle := float(h % 360) * PI / 180.0
	var s := 0.88 + float((h >> 9) % 100) / 100.0 * 0.26
	var jitter := Vector3(float((h >> 3) % 100) / 100.0 - 0.5, 0.0, float((h >> 13) % 100) / 100.0 - 0.5) * 0.9
	return Transform3D(Basis(Vector3.UP, angle).scaled(Vector3.ONE * s), Defs.cell_center(c) + jitter)
