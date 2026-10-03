class_name PlacementTool
extends Node3D
## Ghost preview and placement of buildings (R rotates) and dragged two-way road strips.

signal changed

var world: World
var rig: CameraRig
var ground: GroundView
var def_id := &""
var rot := 2                      # front towards +y, i.e. towards the default camera

var _ghost: Node3D
var _marker: MeshInstance3D
var _ok_mat: StandardMaterial3D
var _bad_mat: StandardMaterial3D
var _cell := Vector2i.ZERO
var _drag_start: Variant = null
var _road_ghosts: Array[MeshInstance3D] = []


func setup(p_world: World, p_rig: CameraRig, p_ground: GroundView) -> void:
	world = p_world
	rig = p_rig
	ground = p_ground
	_ok_mat = Models.ghost_material(Color(0.55, 1.0, 0.55, 0.6))
	_bad_mat = Models.ghost_material(Color(1.0, 0.4, 0.35, 0.6))


func active() -> bool:
	return def_id != &""


func start(id: StringName) -> void:
	cancel()
	def_id = id
	ground.show_grid(true)
	if not Defs.is_road(def_id):
		_ghost = Node3D.new()
		var mi := Models.instance(Defs.def(def_id)["model"])
		_ghost.add_child(mi)
		add_child(_ghost)
		_marker = Models.instance("ui_access_point_marker")
		add_child(_marker)
	_refresh()
	changed.emit()


func cancel() -> void:
	def_id = &""
	_drag_start = null
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	if _marker:
		_marker.queue_free()
		_marker = null
	for g in _road_ghosts:
		g.queue_free()
	_road_ghosts.clear()
	if ground:
		ground.show_grid(false)
		ground.highlight(Rect2i(), true)
	changed.emit()


func hint() -> String:
	if not active():
		return ""
	if Defs.is_road(def_id):
		return "Drag to draw a road · right click to cancel"
	return "Click to place · R rotates · right click to cancel"


func _unhandled_input(event: InputEvent) -> void:
	if not active():
		return
	if event is InputEventMouseMotion:
		var p: Variant = rig.ground_point(event.position)
		if p != null:
			_cell = Defs.world_to_cell(p)
			_refresh()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			cancel()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if Defs.is_road(def_id):
				if event.pressed:
					_drag_start = _block_anchor(_cell)
				elif _drag_start != null:
					for b in _road_blocks():
						world.place_site(def_id, b, 0)
					_drag_start = null
			elif event.pressed:
				var anchor := _anchor()
				if world.place_site(def_id, anchor, rot):
					changed.emit()
			_refresh()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			rot = (rot + 1) % 4
			_refresh()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			cancel()
			get_viewport().set_input_as_handled()


func _anchor() -> Vector2i:
	var fs := Defs.footprint(def_id, rot)
	return _cell - Vector2i(fs.x / 2, fs.y / 2)


static func _block_anchor(c: Vector2i) -> Vector2i:
	return Vector2i(c.x & ~1, c.y & ~1)


## Road blocks of the current drag: a straight strip along the dominant axis.
func _road_blocks() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var end := _block_anchor(_cell)
	if _drag_start == null:
		out.append(end)
		return out
	var s: Vector2i = _drag_start
	var d := end - s
	var step := Vector2i(signi(d.x) * 2, 0) if absi(d.x) >= absi(d.y) else Vector2i(0, signi(d.y) * 2)
	var count := (maxi(absi(d.x), absi(d.y)) / 2) + 1
	for i in count:
		out.append(s + step * i)
	return out


func _refresh() -> void:
	if not active():
		return
	if Defs.is_road(def_id):
		var blocks := _road_blocks()
		while _road_ghosts.size() < blocks.size():
			var mi := Models.instance("road_dirt_twoway_straight")
			add_child(mi)
			_road_ghosts.append(mi)
		var all_ok := true
		var bounds := Rect2i(blocks[0], Vector2i(2, 2))
		for i in _road_ghosts.size():
			var g := _road_ghosts[i]
			g.visible = i < blocks.size()
			if not g.visible:
				continue
			var ok := world.can_place(def_id, blocks[i], 0) or world.road_blocks.has(blocks[i])
			all_ok = all_ok and ok
			g.position = Defs.footprint_center(blocks[i], Vector2i(2, 2)) + Vector3(0, 0.03, 0)
			g.material_override = _ok_mat if ok else _bad_mat
			bounds = bounds.merge(Rect2i(blocks[i], Vector2i(2, 2)))
		ground.highlight(bounds, all_ok)
		return
	var anchor := _anchor()
	var fs := Defs.footprint(def_id, rot)
	var ok := world.can_place(def_id, anchor, rot)
	_ghost.position = Defs.footprint_center(anchor, fs)
	_ghost.rotation.y = -rot * PI * 0.5
	(_ghost.get_child(0) as MeshInstance3D).material_override = _ok_mat if ok else _bad_mat
	_marker.position = Defs.cell_center(Defs.access_cell(def_id, anchor, rot)) + Vector3(0, 0.02, 0)
	_marker.rotation.y = _ghost.rotation.y
	ground.highlight(Rect2i(anchor, fs), ok)
