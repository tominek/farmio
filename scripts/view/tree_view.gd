class_name TreeView
extends Node3D
## Natural trees as MultiMeshes in chunks; a chunk is rebuilt when one of its trees changes.

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


func setup(p_world: World) -> void:
	world = p_world
	var n := ceili(float(world.size) / CHUNK)
	for cy in n:
		for cx in n:
			_rebuild(Vector2i(cx, cy))
	world.tree_changed.connect(func(c: Vector2i) -> void: _dirty[c / CHUNK] = true)


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
