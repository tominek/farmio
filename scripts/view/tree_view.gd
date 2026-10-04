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
var _preview := {}         # tree the cut drag would mark -> Sprite3D (fainter badge)
var _unmark_tex: Texture2D


func setup(p_world: World) -> void:
	world = p_world
	add_to_group("tree_view")
	var n := ceili(float(world.size) / CHUNK)
	for cy in n:
		for cx in n:
			_rebuild(Vector2i(cx, cy))
	world.tree_changed.connect(func(c: Vector2i) -> void: _dirty[c / CHUNK] = true)
	_badge_tex = badge_texture("#4E7D38", "#36592A")
	_unmark_tex = badge_texture("#E2683F", "#A23E22")
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
	s = _badge(c, _badge_tex)
	_badges[c] = s
	if _preview.has(c):
		(_preview[c] as Node).queue_free()
		_preview.erase(c)


func _badge(c: Vector2i, tex: Texture2D) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = tex
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.no_depth_test = true
	s.render_priority = 1
	s.pixel_size = 2.2 / tex.get_width()       # about two metres across
	var i := world.idx(c)
	var key := Vector2i(world.tree_kind[i], world.tree_stage[i])
	var top := Models.mesh(MODELS[key]).get_aabb().end.y if MODELS.has(key) else 4.0
	s.position = _transform(c).origin + Vector3(0.0, top + 0.7, 0.0)
	add_child(s)
	return s


## Axe badges of the trees a cut drag would mark (or, unmarking, orange ones on the marked trees).
func preview(cells: Array, unmark: bool) -> void:
	var want := {}
	for c: Vector2i in cells:
		want[c] = true
	for c: Vector2i in _preview.keys():
		if not want.has(c) or (_preview[c] as Sprite3D).texture != (_unmark_tex if unmark else _badge_tex):
			(_preview[c] as Node).queue_free()
			_preview.erase(c)
	for c: Vector2i in want:
		if _preview.has(c) or (_badges.has(c) and not unmark):
			continue
		var s := _badge(c, _unmark_tex if unmark else _badge_tex)
		s.modulate.a = 0.85
		s.render_priority = 2
		if unmark:
			s.position.y += 0.05
		_preview[c] = s


## Kit tree badge: a cream disc with a coloured ring and a drop, the axe icon inside.
static func badge_texture(ring: String, drop: String) -> Texture2D:
	# the axe of assets/ui/icons/kit/cut.svg (the raw svg is not exported, only its import)
	var inner := ('<circle cx="12" cy="12" r="11" fill="#4E7D38"/><rect x="11" y="5" width="2.2" height="14" rx="1" '
		+ 'transform="rotate(-30 12 12)" fill="#C9A06A"/><path d="M9.2 5.4 L14.6 4 A4.6 4.6 0 0 1 13.6 11 Z" fill="#FFFAF0"/>')
	var svg := ('<svg xmlns="http://www.w3.org/2000/svg" width="34" height="36" viewBox="0 0 34 36">'
		+ '<circle cx="17" cy="19" r="15" fill="%s"/>' % drop
		+ '<circle cx="17" cy="17" r="14" fill="#FFFAF0" stroke="%s" stroke-width="2"/>' % ring
		+ '<g transform="translate(7 7) scale(0.8333)">%s</g></svg>' % inner)
	var img := Image.new()
	img.load_svg_from_string(svg, 4.0)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


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
