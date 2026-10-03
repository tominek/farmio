class_name PlacementTool
extends Node3D
## Ghost preview and placement of buildings (R rotates), dragged fields (R moves the gate)
## and dragged two-way road strips.

signal changed

var world: World
var rig: CameraRig
var ground: GroundView
var def_id := &""
var rot := 2                      # front towards +y, i.e. towards the default camera
var crop := &"wheat"              # crop for new fields

var _ghost: Node3D
var _marker: MeshInstance3D
var _ok_mat: StandardMaterial3D
var _bad_mat: StandardMaterial3D
var _cell := Vector2i.ZERO
var _drag_start: Variant = null
var _road_ghosts: Array[MeshInstance3D] = []
var _gate_manual := false          # fields: the player moved the gate with R


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
	_gate_manual = false
	ground.show_grid(true)
	if not Defs.is_road(def_id):
		if not Defs.is_field(def_id):
			_ghost = Node3D.new()
			_ghost.add_child(Models.instance(Defs.def(def_id)["model"]))
			add_child(_ghost)
		_marker = Models.instance("ui_access_point_marker")
		add_child(_marker)
	_refresh()
	changed.emit()


func set_crop(c: StringName) -> void:
	crop = c
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
	if Defs.is_field(def_id):
		if _drag_start == null:
			return "%s field · press and drag from a corner (sides %d–%d tiles) · Tab changes the crop · right click to cancel" % [
				Defs.CROPS[crop]["name"], Defs.FIELD_MIN_DIM, Defs.FIELD_MAX_DIM]
		var r := _field_rect()
		var size_ok := Defs.field_size_ok(r.size)
		return "%s field %d × %d  $%d%s · Tab changes the crop · R moves the gate · right click to cancel" % [
			Defs.CROPS[crop]["name"], r.size.x, r.size.y, Defs.field_cost(r.size),
			"" if size_ok else "  (sides %d–%d tiles, max %d tiles)" % [Defs.FIELD_MIN_DIM, Defs.FIELD_MAX_DIM, Defs.FIELD_MAX_AREA]]
	return "Click to place · R rotates · right click to cancel"


func _unhandled_input(event: InputEvent) -> void:
	if not active():
		return
	if event is InputEventMouseMotion:
		var p: Variant = rig.ground_point(event.position)
		if p != null:
			var c := Defs.world_to_cell(p)
			if c != _cell:
				_cell = c
				_refresh()
				changed.emit()
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
			elif Defs.is_field(def_id):
				if event.pressed:
					_drag_start = _cell
				elif _drag_start != null:
					var r := _field_rect()
					world.place_site(def_id, r.position, rot, Defs.rotated(r.size, rot), crop)
					_drag_start = null
			elif event.pressed:
				world.place_site(def_id, _anchor(), rot)
			_refresh()
			changed.emit()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			rot = (rot + 1) % 4
			_gate_manual = true
			_refresh()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_TAB and Defs.is_field(def_id):
			var crops := Defs.CROPS.keys()
			set_crop(crops[(crops.find(crop) + (crops.size() - 1 if event.shift_pressed else 1)) % crops.size()])
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			cancel()
			get_viewport().set_input_as_handled()


func _anchor() -> Vector2i:
	var fs := Defs.footprint(def_id, rot)
	return _cell - Vector2i(fs.x / 2, fs.y / 2)


## Field rectangle: dragged from the press point; before the press just the corner tile under the cursor.
func _field_rect() -> Rect2i:
	if _drag_start == null:
		return Rect2i(_cell, Vector2i.ONE)
	var s: Vector2i = _drag_start
	var lo := Vector2i(mini(s.x, _cell.x), mini(s.y, _cell.y))
	var hi := Vector2i(maxi(s.x, _cell.x), maxi(s.y, _cell.y))
	return Rect2i(lo, hi - lo + Vector2i.ONE)


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
		_refresh_road()
	elif Defs.is_field(def_id):
		var r := _field_rect()
		if not _gate_manual and _drag_start != null:
			rot = _gate_towards_road(r)
		var base := Defs.rotated(r.size, rot)
		var ok := world.can_place(def_id, r.position, rot, base)
		_marker.visible = _drag_start != null
		if _drag_start == null:
			ok = world.in_bounds(_cell) and not world.is_locked(_cell) and world.occupant[world.idx(_cell)] == 0
		_marker.position = Defs.cell_center(Defs.access_for(base, r.position, rot)) + Vector3(0, 0.02, 0)
		_marker.rotation.y = -rot * PI * 0.5
		ground.highlight(r, ok)
	else:
		var anchor := _anchor()
		var fs := Defs.footprint(def_id, rot)
		var ok := world.can_place(def_id, anchor, rot)
		_ghost.position = Defs.footprint_center(anchor, fs)
		_ghost.rotation.y = -rot * PI * 0.5
		(_ghost.get_child(0) as MeshInstance3D).material_override = _ok_mat if ok else _bad_mat
		_marker.position = Defs.cell_center(Defs.access_cell(def_id, anchor, rot)) + Vector3(0, 0.02, 0)
		_marker.rotation.y = _ghost.rotation.y
		ground.highlight(Rect2i(anchor, fs), ok)


func _refresh_road() -> void:
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


## Gate side closest to a road (default until the player rotates it with R).
func _gate_towards_road(r: Rect2i) -> int:
	var best := rot
	var best_d := INF
	for side in 4:
		var a := Defs.access_for(Defs.rotated(r.size, side), r.position, side)
		for anchor: Vector2i in world.road_blocks:
			var d := Vector2(a).distance_squared_to(Vector2(anchor) + Vector2(0.5, 0.5))
			if d < best_d:
				best_d = d
				best = side
	return best


## Whether the crop picker floats above the drawn field (below it when the gate is on top).
func picker_above() -> bool:
	return not (_drag_start != null and rot == 0)


## World point at the field edge where the crop picker floats.
func picker_anchor() -> Vector3:
	var r := _field_rect()
	var y := r.position.y if picker_above() else r.end.y
	return Vector3((r.position.x + r.size.x * 0.5) * Defs.TILE, 0.0, y * Defs.TILE)
