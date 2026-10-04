class_name PlacementTool
extends Node3D
## Ghost preview and placement of buildings (R rotates), dragged fields (R moves the gate)
## and dragged two-way road strips; the dock modes (start_mode): cut trees (drag marks trees for
## felling, Shift unmarks), move a building (pick it, its ghost follows, R rotates, click confirms),
## demolish (click a building, site, field or road block); and moving a field's gate (start_gate).

signal changed

var world: World
var rig: CameraRig
var ground: GroundView
var def_id := &""
var rot := 2                      # front towards +y, i.e. towards the default camera
var crop := &"wheat"              # crop for new fields
var mode := &""                   # dock mode: &"cut", &"move", &"demolish", &"gate"; &"" while placing (start)

var _ghost: Node3D
var _marker: MeshInstance3D
var _ok_mat: StandardMaterial3D
var _bad_mat: StandardMaterial3D
var _cell := Vector2i.ZERO
var _drag_start: Variant = null
var _road_points: Array[Vector2i] = []   # roads: the clicked points (block anchors), drawn as straight legs
var _road_ghosts: Array[MeshInstance3D] = []
var _gate_manual := false          # fields: the player moved the gate with R
var _shift := false                # cut: Shift held (unmarks)
var _moving: Building = null       # move: the building picked, its ghost follows the cursor
var _move_rot := 0
var _gate_field: Field = null      # gate: the field whose gate moves
var _side := 0                     # gate: the side shown
var _debug_hold := false           # screenshots: the cursor stays where debug_show put it
var _road_mat: StandardMaterial3D
var _demolish_mat: StandardMaterial3D
var _tint: Node3D = null           # demolish: red copy over the building under the cursor
var _tinted: Building = null
var _want_tint: Building = null
var _want_road: Variant = null
var _roads: Node = null            # RoadView (tints a road block), TreeView (previews axe badges)
var _trees: Node = null
var _overlay: Control              # 2D marks over the 3D view: the road points


func setup(p_world: World, p_rig: CameraRig, p_ground: GroundView) -> void:
	world = p_world
	rig = p_rig
	ground = p_ground
	add_to_group("debug_show")
	_ok_mat = Models.ghost_material(Color(0.55, 1.0, 0.55, 0.6))
	_bad_mat = Models.ghost_material(Color(1.0, 0.4, 0.35, 0.6))
	_road_mat = Models.ghost_material(Color(1.0, 0.98, 0.94, 0.8))
	_demolish_mat = Models.ghost_material(Color(1.0, 0.25, 0.15, 0.6))
	if is_inside_tree():
		_roads = get_tree().get_first_node_in_group("road_view")
		_trees = get_tree().get_first_node_in_group("tree_view")
	var layer := CanvasLayer.new()
	add_child(layer)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_overlay)
	_overlay.draw.connect(_draw_overlay)


func _process(_delta: float) -> void:
	if _overlay and def_id != &"" and Defs.is_road(def_id):
		_overlay.queue_redraw()        # the camera may have moved

func active() -> bool:
	return def_id != &"" or mode != &""


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


## Starts a dock mode: &"cut", &"move" or &"demolish". Right click or Esc finishes it.
func start_mode(m: StringName) -> void:
	cancel()
	mode = m
	ground.show_grid(m == &"move")      # placing a building again; cutting and demolishing need no grid
	_refresh()
	changed.emit()


## Moves the gate of a placed field: the side nearest the cursor (R turns it), click confirms.
func start_gate(f: Field) -> void:
	cancel()
	mode = &"gate"
	_gate_field = f
	_side = f.rot
	_refresh()
	changed.emit()


func set_crop(c: StringName) -> void:
	crop = c
	changed.emit()


func cancel() -> void:
	def_id = &""
	mode = &""
	_moving = null
	_gate_field = null
	_drag_start = null
	_road_points.clear()
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
		ground.clear_marks()
	_want_tint = null
	_want_road = null
	_apply_tint()
	if _trees:
		_trees.call("preview", [], false)
	if _overlay:
		_overlay.queue_redraw()
	changed.emit()


## Hint line of the active tool as plain text (no markup).
func hint() -> String:
	return hint_rich().replace("**", "").replace("!!", "")


## Hint line with markup for the dock: **bold**, !!short (red bold)!!; numbers are bolded by the dock.
func hint_rich() -> String:
	match mode:
		&"cut":
			return _cut_hint()
		&"move":
			return _move_hint()
		&"demolish":
			return _demolish_hint()
		&"gate":
			return "Click to put the gate here · it jumps to the side nearest the cursor · **R** turns it · right click to cancel"
	if not active():
		return ""
	if Defs.is_road(def_id):
		if _road_points.is_empty():
			return "Click to start a road · right click to cancel"
		return "Click to add a bend · click the last point again to build%s · right click undoes a point" % _road_cost_text()
	if Defs.is_field(def_id):
		if _drag_start == null:
			return "%s field · press and drag from a corner (sides %d–%d tiles) · **Tab** changes the crop · right click to cancel" % [
				Defs.CROPS[crop]["name"], Defs.FIELD_MIN_DIM, Defs.FIELD_MAX_DIM]
		var r := _field_rect()
		var size_ok := Defs.field_size_ok(r.size)
		return "%s field %d × %d  %s%s · **Tab** changes the crop · **R** moves the gate · right click to cancel" % [
			Defs.CROPS[crop]["name"], r.size.x, r.size.y, Defs.format_money(Defs.field_cost(r.size)),
			"" if size_ok else "  (sides %d–%d tiles, max %d tiles)" % [Defs.FIELD_MIN_DIM, Defs.FIELD_MAX_DIM, Defs.FIELD_MAX_AREA]]
	var where: String = Defs.def(def_id).get("hint", "")
	return "Click to place%s · **R** rotates · right click to cancel" % (" " + where if where != "" else "")


## Second pill under the hint when the spot or the target is not possible: "Can't …: why" (the
## part up to the colon is shown red); empty when all is fine.
func problem() -> String:
	match mode:
		&"move":
			if _moving == null:
				var b := world.building_at(_cell)
				if b and world.move_blocker(b) != "":
					return "Can’t move the %s: %s" % [b.display_name(), _lower_first(world.move_blocker(b))]
			elif not world.can_move(_moving, _move_anchor(), _move_rot):
				return "Can’t go here: %s" % _place_reason(_moving.def_id, _move_anchor(), _move_rot, _moving.base_size)
		&"demolish":
			var b := world.building_at(_cell)
			if b:
				if world.demolish_blocker(b) != "":
					return "Can’t remove the %s: %s" % [b.display_name(), _lower_first(world.demolish_blocker(b))]
			elif world.road_block_at(_cell) != null and world.road_blocker(world.road_block_at(_cell)) != "":
				return "Can’t remove this road: %s" % _lower_first(world.road_blocker(world.road_block_at(_cell)))
		&"gate":
			if _side != _gate_field.rot and not world.field_gate_ok(_gate_field, _side):
				return "Can’t put the gate here: the way out on this side is blocked"
		&"":
			if def_id != &"" and not Defs.is_road(def_id) and not Defs.is_field(def_id) \
					and not world.can_place(def_id, _anchor(), rot):
				return "Can’t go here: %s" % _place_reason(def_id, _anchor(), rot)
	return ""


static func _lower_first(s: String) -> String:
	return s.left(1).to_lower() + s.substr(1)


## Why a building can't stand here (mirrors World.can_place, first reason found).
func _place_reason(id: StringName, anchor: Vector2i, r: int, base_size := Vector2i.ZERO) -> String:
	if not world.building_unlocked(id):
		return "not researched yet"
	if base_size == Vector2i.ZERO:
		base_size = Defs.def(id)["size"]
	if world.money < world.cost_of(id, base_size, anchor):
		return "not enough quacks"
	var fs := Defs.rotated(base_size, r)
	var river_side: bool = Defs.def(id).get("river_side", false)
	for y in fs.y:
		for x in fs.x:
			var c := anchor + Vector2i(x, y)
			if not world.in_bounds(c) or world.is_locked(c):
				return "off your land"
			if world.occupant[world.idx(c)] != 0:
				return "something stands there"
			if world.road[world.idx(c)] != 0 and not world.curve_free(c):
				return "on a road"
			if world.in_curve(c):
				return "in the bend of a road"
			if world.is_water(c) and not river_side:
				return "over the river"
	if river_side and not world.river_side_ok(anchor, fs, r):
		return Defs.def(id).get("hint", "it has to stand on the river bank")
	return "the door would be blocked"


func _unhandled_input(event: InputEvent) -> void:
	if not active():
		return
	if event is InputEventWithModifiers and mode == &"cut" and (event as InputEventWithModifiers).shift_pressed != _shift \
			and not (event is InputEventKey and event.keycode == KEY_SHIFT):
		_set_shift(event.shift_pressed)
	if event is InputEventMouseMotion:
		if _debug_hold:
			return
		var p: Variant = rig.ground_point(event.position)
		if p != null:
			var c := Defs.world_to_cell(p)
			if c != _cell:
				_cell = c
				if mode == &"gate":
					_side = _nearest_side(_gate_field, c)
				_refresh()
				changed.emit()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if mode == &"move" and _moving:
				_drop_moving()             # back to picking a building
			elif mode == &"" and Defs.is_road(def_id) and not _road_points.is_empty():
				_road_points.pop_back()     # undo the last point
				_refresh()
				changed.emit()
			else:
				cancel()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if mode != &"":
				_mode_click(event.pressed)
			elif Defs.is_road(def_id):
				if event.pressed:
					_road_click()
			elif Defs.is_field(def_id):
				if event.pressed:
					_drag_start = _cell
				elif _drag_start != null:
					var r := _field_rect()
					world.place_site(def_id, r.position, rot, Defs.rotated(r.size, rot), crop)
					_drag_start = null
			elif event.pressed:
				world.place_site(def_id, _anchor(), rot)
			if active():
				_refresh()
			changed.emit()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.keycode == KEY_SHIFT and mode == &"cut":
		_set_shift(event.pressed)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			if mode == &"move":
				_move_rot = (_move_rot + 1) % 4
			elif mode == &"gate":
				_side = (_side + 1) % 4
			elif mode == &"":
				rot = (rot + 1) % 4
				_gate_manual = true
			_refresh()
			changed.emit()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_TAB and mode == &"" and Defs.is_field(def_id):
			var crops := Defs.CROPS.keys()
			set_crop(crops[(crops.find(crop) + (crops.size() - 1 if event.shift_pressed else 1)) % crops.size()])
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			cancel()
			get_viewport().set_input_as_handled()


func _set_shift(on: bool) -> void:
	_shift = on
	_refresh()
	changed.emit()


## Left button in a dock mode (pressed or released).
func _mode_click(pressed: bool) -> void:
	match mode:
		&"cut":
			if pressed:
				_drag_start = _cell
			elif _drag_start != null:
				if _shift:
					world.unmark_trees(_field_rect())
				else:
					world.mark_trees(_field_rect())
				_drag_start = null
		&"move":
			if not pressed:
				return
			if _moving == null:
				var b := world.building_at(_cell)
				if b and world.move_blocker(b) == "":
					_pick_moving(b)
			elif world.move_building(_moving, _move_anchor(), _move_rot) != null:
				_drop_moving()
		&"demolish":
			if not pressed:
				return
			var b := world.building_at(_cell)
			if b:
				world.demolish(b)
			elif world.road_block_at(_cell) != null:
				world.demolish_road(world.road_block_at(_cell))
		&"gate":
			if pressed and world.set_field_gate(_gate_field, _side):
				cancel()


func _pick_moving(b: Building) -> void:
	_moving = b
	_move_rot = b.rot
	_ghost = Node3D.new()
	_ghost.add_child(Models.instance(b.model()))
	add_child(_ghost)
	_marker = Models.instance("ui_access_point_marker")
	add_child(_marker)


func _drop_moving() -> void:
	_moving = null
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	if _marker:
		_marker.queue_free()
		_marker = null
	_refresh()
	changed.emit()


## Anchor of the moved building's ghost, centred on the cursor.
func _move_anchor() -> Vector2i:
	var fs := Defs.rotated(_moving.base_size, _move_rot)
	return _cell - Vector2i(fs.x / 2, fs.y / 2)


## Side of the field (rotation) nearest to the cell.
static func _nearest_side(f: Field, c: Vector2i) -> int:
	var d := (Vector2(c) + Vector2(0.5, 0.5) - (Vector2(f.anchor) + Vector2(f.size) * 0.5)) / Vector2(f.size)
	if absf(d.x) > absf(d.y):
		return 1 if d.x > 0.0 else 3
	return 2 if d.y > 0.0 else 0


static func _count(n: int, one: String, many: String) -> String:
	return "%d %s" % [n, one if n == 1 else many]


func _cut_hint() -> String:
	if _drag_start == null:
		return "Drag over trees to %s them · Shift unmarks · right click to finish" % ("unmark" if _shift else "mark")
	var n := world.trees_to_mark(_field_rect(), _shift).size()
	if _shift:
		return "Drag over marked trees to unmark them · %s · right click to finish" % _count(n, "tree", "trees")
	return "Drag over trees to mark them · %s · ≈ %s · Shift unmarks · right click to finish" % [
		_count(n, "tree", "trees"), _count(n * Defs.WOOD_PER_TREE, "log", "logs")]


func _move_hint() -> String:
	if _moving == null:
		var b := world.building_at(_cell)
		if b == null or world.move_blocker(b) != "":
			return "Click a building to move it · right click to finish"
		return "Click to move the **%s** · right click to finish" % b.display_name()
	return "Moving **%s** · click to place (workers take it down and rebuild it) · **R** rotates · right click to pick another" % _moving.display_name()


func _demolish_hint() -> String:
	var b := world.building_at(_cell)
	if b and world.demolish_blocker(b) == "":
		var site := b as ConstructionSite
		if site and site.partner:
			return "Click to cancel moving the **%s** · right click to stop" % Defs.def(b.def_id)["name"]
		var back := _refund_text(b)
		if site:
			return "Cancel the **%s**%s · click to cancel it · right click to stop" % [b.display_name(), back]
		return "Demolish **%s**%s · click to remove · right click to stop" % [b.display_name(), back]
	var road: Variant = world.road_block_at(_cell)
	if b == null and road != null and world.road_blocker(road) == "":
		return "Demolish the **%s road** block · click to remove · right click to stop" % String(world.road_blocks[road])
	return "Click a building or a road block to remove it · right click to stop"


## " · 15 planks and 200 qk back to the barn" — what demolishing gives back (World.demolish).
func _refund_text(b: Building) -> String:
	var parts: PackedStringArray = []
	var goods := {}
	if b is ConstructionSite:
		var s := b as ConstructionSite
		for res: StringName in s.delivered:
			goods[res] = goods.get(res, 0.0) + s.delivered[res]
		for res: StringName in s.pile:
			goods[res] = goods.get(res, 0.0) + s.pile[res]
	else:
		goods = b.materials
	for res: StringName in goods:
		if goods[res] > 0.0:
			parts.append(Defs.format_goods(res, goods[res]))
	if b.paid > 0:
		parts.append(Defs.format_money(b.paid))
	if parts.is_empty():
		return ""
	return " · %s back%s" % [" and ".join(parts), " to the barn" if not goods.is_empty() else ""]


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


## Roads are drawn point by point: a click starts the road or adds a bend where the leg to the cursor
## ends, a click on the last point again builds the whole road.
func _road_click() -> void:
	if _road_points.is_empty():
		_road_points.append(_block_anchor(_cell))
		return
	var end := _leg_end(_road_points.back(), _block_anchor(_cell))
	if end != _road_points.back():
		_road_points.append(end)
		return
	for b in _road_blocks():
		world.place_site(def_id, b, 0)
	_road_points.clear()


## End of a straight leg from `from` towards `to` (along the longer axis, 4 directions only).
static func _leg_end(from: Vector2i, to: Vector2i) -> Vector2i:
	var d := to - from
	return Vector2i(to.x, from.y) if absi(d.x) >= absi(d.y) else Vector2i(from.x, to.y)


## Road blocks of the road being drawn: the legs between the points and the leg to the cursor.
func _road_blocks() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var pts := _road_points.duplicate()
	if pts.is_empty():
		out.append(_block_anchor(_cell))
		return out
	pts.append(_leg_end(pts.back(), _block_anchor(_cell)))
	out.append(pts[0])
	for i in range(1, pts.size()):
		var a: Vector2i = pts[i - 1]
		var b: Vector2i = pts[i]
		var step := (b - a).sign() * Defs.ROAD_BLOCK
		var p := a
		while p != b:
			p += step
			if not out.has(p):
				out.append(p)
	return out


func _refresh() -> void:
	if not active():
		return
	if mode != &"":
		_refresh_mode()
		_apply_tint()
	elif Defs.is_road(def_id):
		_refresh_road()
	elif Defs.is_field(def_id):
		var r := _field_rect()
		if not _gate_manual and _drag_start != null:
			rot = world.field_gate_side(r, rot)
		var base := Defs.rotated(r.size, rot)
		var ok := world.can_place(def_id, r.position, rot, base)
		_marker.visible = _drag_start != null
		if _drag_start == null:
			ok = world.in_bounds(_cell) and not world.is_locked(_cell) and world.occupant[world.idx(_cell)] == 0
		_marker.position = Defs.cell_center(Defs.access_for(base, r.position, rot)) + Vector3(0, 0.02, 0)
		_marker.rotation.y = -rot * PI * 0.5
		ground.mark_place(0, r, ok)
	else:
		var anchor := _anchor()
		var fs := Defs.footprint(def_id, rot)
		var ok := world.can_place(def_id, anchor, rot)
		_ghost.position = Defs.footprint_center(anchor, fs)
		_ghost.rotation.y = -rot * PI * 0.5
		(_ghost.get_child(0) as MeshInstance3D).material_override = _ok_mat if ok else _bad_mat
		_marker.position = Defs.cell_center(Defs.access_cell(def_id, anchor, rot)) + Vector3(0, 0.02, 0)
		_marker.rotation.y = _ghost.rotation.y
		ground.mark_place(0, Rect2i(anchor, fs), ok)


# Kit colours of the in-world tool feedback
const CREAM := Color("#FFFAF0")
const GO_DARK := Color("#36592A")
const RED := Color("#B4472A")
const RED_DARK := Color("#8E3418")
const DASH := 16.0                 # dash period of dashed outlines, px at 1080p


func _refresh_mode() -> void:
	ground.clear_marks()
	_want_tint = null
	_want_road = null
	match mode:
		&"cut":
			# the drag: a dashed cream frame, green to mark, orange with Shift to unmark
			var r := _field_rect()
			if _drag_start != null:
				ground.mark(0, r, Color(UiStyle.WARN if _shift else UiStyle.GO, 0.25), CREAM,
						UiStyle.SHORT if _shift else GO_DARK, DASH)
			else:
				ground.mark(0, r, Color(CREAM, 0.25), CREAM, Color.TRANSPARENT, DASH)
			if _trees:
				_trees.call("preview", world.trees_to_mark(r, _shift) if _drag_start != null else [], _shift)
		&"demolish":
			var b := world.building_at(_cell)
			var road: Variant = world.road_block_at(_cell)
			if b:
				var ok := world.demolish_blocker(b) == ""
				# what goes: tinted red with a red ring; a blocked one only gets a thin red frame
				ground.mark(0, b.rect(), Color(RED, 0.6 if ok else 0.12), Color.TRANSPARENT, RED, DASH if not ok else 0.0)
				if ok:
					_want_tint = b
			elif road != null:
				ground.mark(0, Rect2i(road, Vector2i(Defs.ROAD_BLOCK, Defs.ROAD_BLOCK)), Color(RED, 0.18), RED, Color.TRANSPARENT, DASH)
				if world.road_blocker(road) == "":
					_want_road = road
		&"move":
			if _moving == null:
				var b := world.building_at(_cell)
				if b:
					if world.move_blocker(b) == "":
						ground.mark(0, b.rect(), Color(CREAM, 0.3), CREAM, Color.TRANSPARENT, DASH)
					else:
						ground.mark(0, b.rect(), Color(RED, 0.12), RED, Color.TRANSPARENT, DASH)
				return
			var anchor := _move_anchor()
			var fs := Defs.rotated(_moving.base_size, _move_rot)
			var ok := world.can_move(_moving, anchor, _move_rot)
			_ghost.position = Defs.footprint_center(anchor, fs)
			_ghost.rotation.y = -_move_rot * PI * 0.5
			(_ghost.get_child(0) as MeshInstance3D).material_override = _ok_mat if ok else _bad_mat
			_marker.position = Defs.cell_center(Defs.access_for(_moving.base_size, anchor, _move_rot)) + Vector3(0, 0.02, 0)
			_marker.rotation.y = _ghost.rotation.y
			# where it stands now: a dashed cream frame; where it goes: green fits, red can't
			ground.mark(1, _moving.rect(), Color(CREAM, 0.25), CREAM, Color.TRANSPARENT, DASH)
			ground.mark_place(0, Rect2i(anchor, fs), ok)
		&"gate":
			var f := _gate_field
			var ok := _side == f.rot or world.field_gate_ok(f, _side)
			# the field framed blue; the gate a wooden bar on its side, the other free sides dashed
			ground.mark(0, f.rect(), Color.TRANSPARENT, Color.TRANSPARENT, UiStyle.SELECT)
			for side in 4:
				var bar := _gate_bar(f, side)
				if side == _side:
					ground.mark(1 + side, bar, Color(UiStyle.WOOD, 1.0), CREAM, UiStyle.SELECT if ok else RED)
				elif side == f.rot or world.field_gate_ok(f, side):
					ground.mark(1 + side, bar, Color.TRANSPARENT, Color(CREAM, 0.8), Color.TRANSPARENT, 10.0)


## The gate bar of a field side, in tiles: just outside the edge (the field covers the ground), centred on the gate tile.
func _gate_bar(f: Field, side: int) -> Rect2:
	var c := world.field_gate_cell(f, side)
	var r := f.rect()
	var centre := Vector2(c) + Vector2(0.5, 0.5)
	if c.y < r.position.y:
		return Rect2(centre.x - 0.9, r.position.y - 0.75, 1.8, 0.6)
	if c.y >= r.end.y:
		return Rect2(centre.x - 0.9, r.end.y + 0.15, 1.8, 0.6)
	if c.x < r.position.x:
		return Rect2(r.position.x - 0.75, centre.y - 0.9, 0.6, 1.8)
	return Rect2(r.end.x + 0.15, centre.y - 0.9, 0.6, 1.8)


## Red see-through copy over the building that the click would remove, red road block likewise.
func _apply_tint() -> void:
	if _roads:
		_roads.call("tint", _want_road)
	var b: Building = _want_tint
	if b == _tinted:
		return
	_tinted = b
	if _tint:
		_tint.queue_free()
		_tint = null
	if b == null or b is Field or b is ConstructionSite:
		return
	_tint = Node3D.new()
	_tint.position = Defs.footprint_center(b.anchor, b.size)
	_tint.rotation.y = -b.rot * PI * 0.5
	_tint.scale = Vector3.ONE * 1.02
	var m := Models.instance(b.model())
	m.material_override = _demolish_mat
	_tint.add_child(m)
	add_child(_tint)


func _refresh_road() -> void:
	var blocks := _road_blocks()
	var surface: StringName = Defs.def(def_id)["road"]
	while _road_ghosts.size() < blocks.size():
		var mi := MeshInstance3D.new()
		add_child(mi)
		_road_ghosts.append(mi)
	for i in _road_ghosts.size():
		var g := _road_ghosts[i]
		g.visible = i < blocks.size()
		if not g.visible:
			continue
		var ok := world.can_place(def_id, blocks[i], 0) or world.road_blocks.has(blocks[i])
		# over the river the block becomes a bridge
		if world.is_water(blocks[i]) and world.river_axis(blocks[i]) != -1:
			g.mesh = Models.mesh("bridge_%s_twoway" % surface)
			g.rotation.y = -RoadView.bridge_rotation(world, blocks[i]) * PI * 0.5
		else:
			# straight pieces run N-S; on a leg along x they turn
			var nb: Vector2i = blocks[i + 1] if i + 1 < blocks.size() else (blocks[i - 1] if i > 0 else blocks[i])
			g.mesh = Models.mesh("road_%s_twoway_straight" % surface)
			g.rotation.y = -PI * 0.5 if nb.y == blocks[i].y and nb != blocks[i] else 0.0
		g.position = Defs.footprint_center(blocks[i], Vector2i(2, 2)) + Vector3(0, 0.03, 0)
		g.material_override = _road_mat if ok else _bad_mat
	ground.clear_marks()
	_overlay.queue_redraw()


## Road being drawn (2D over the view): a dashed blue line through the points, a cream dot per
## point, the cursor end filled blue, and a "Bridge · n blocks" chip over the river crossing.
func _draw_overlay() -> void:
	if rig == null or mode != &"" or not Defs.is_road(def_id) or _road_points.is_empty():
		return
	var cam := rig.camera
	var pts: Array[Vector2] = []
	var ends: Array[Vector2i] = _road_points.duplicate()
	var last := _leg_end(ends.back(), _block_anchor(_cell))
	if last != ends.back():
		ends.append(last)
	for a in ends:
		pts.append(cam.unproject_position(Defs.footprint_center(a, Vector2i(2, 2))))
	for i in range(1, pts.size()):
		_overlay.draw_dashed_line(pts[i - 1], pts[i], UiStyle.SELECT, 3.0, 10.0)
	for i in pts.size():
		var tip := i == pts.size() - 1
		_overlay.draw_circle(pts[i], 11.0, UiStyle.SELECT)
		if not tip:
			_overlay.draw_circle(pts[i], 8.0, CREAM)
	# bridge chip over the middle of the blocks on the river
	var wet: Array[Vector3] = []
	for b in _road_blocks():
		if world.is_water(b) and world.river_axis(b) != -1:
			wet.append(Defs.footprint_center(b, Vector2i(2, 2)))
	if wet.is_empty():
		return
	var mid := Vector3.ZERO
	for p in wet:
		mid += p
	var at := cam.unproject_position(mid / wet.size())
	var text := "Bridge · %d block%s" % [wet.size(), "" if wet.size() == 1 else "s"]
	var font := UiStyle.body_font(true)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var box := Rect2(at + Vector2(-w * 0.5 - 10.0, -46.0), Vector2(w + 20.0, 24.0))
	var sb := UiStyle.box(UiStyle.SELECT_PAPER, Color("#3E7FB5"), 12, 2)
	_overlay.draw_style_box(sb, box)
	_overlay.draw_string(font, box.position + Vector2(10.0, 17.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#1F4E77"))


## " · 3 blocks · 600 qk · 900 kg gravel" for the blocks of the drag that will be built.
func _road_cost_text() -> String:
	var n := 0
	var money := 0
	var material := {}
	for b in _road_blocks():
		if not world.can_place(def_id, b, 0):
			continue
		n += 1
		money += world.cost_of(def_id, Vector2i.ZERO, b)
		var mat: Dictionary = Defs.def(def_id).get("material", {})
		for res: StringName in mat:
			material[res] = material.get(res, 0.0) + mat[res]
	if n == 0:
		return ""
	var text := " · %d block%s" % [n, "" if n == 1 else "s"]
	if money > 0:
		text += " · " + Defs.format_money(money)
	for res: StringName in material:
		var have: float = world.total(res)
		var barn := Defs.format_amount(res, have)
		text += " · %s (in the barn: %s)" % [Defs.format_goods(res, material[res]), "!!%s!!" % barn if have < material[res] else barn]
	return text


## Whether the crop picker floats above the drawn field (below it when the gate is on top).
func picker_above() -> bool:
	return not (_drag_start != null and rot == 0)


## World point at the field edge where the crop picker floats.
func picker_anchor() -> Vector3:
	var r := _field_rect()
	var y := r.position.y if picker_above() else r.end.y
	return Vector3((r.position.x + r.size.x * 0.5) * Defs.TILE, 0.0, y * Defs.TILE)


## Size, cost and seed need of the field being drawn (empty before the drag starts).
func field_info() -> String:
	if _drag_start == null:
		return ""
	var r := _field_rect()
	var tiles := r.size.x * r.size.y
	var seed := Defs.seed_of(crop)
	var text := "%d × %d = %d tiles · %s · %s needed: %s (in the barn: %s)" % [r.size.x, r.size.y, tiles,
		Defs.format_money(Defs.field_cost(r.size)), Defs.resource_name(seed), Defs.format_kg(tiles * Defs.seed_per_tile(crop)),
		Defs.format_kg(world.total(seed))]
	if not Defs.field_size_ok(r.size):
		text += "\nsides %d–%d tiles, at most %d tiles" % [Defs.FIELD_MIN_DIM, Defs.FIELD_MAX_DIM, Defs.FIELD_MAX_AREA]
	return text


## Screenshots (--show=tool_cut / tool_move / tool_demolish): the mode in a sample state near the barn.
func debug_show(what: String, _game: Node) -> void:
	if not what.begins_with("tool_"):
		return
	_debug_hold = true
	var barn: Building = null
	for b: Building in world.buildings.values():
		if Defs.def(b.def_id).get("storage", false) and not (b is ConstructionSite):
			barn = b
	var near := barn.access if barn else Vector2i(world.size / 2, world.size / 2)
	match what:
		&"tool_cut":
			var r := _debug_tree_rect(near, 2)
			world.mark_trees(_debug_tree_rect(r.position + Vector2i(5, 0), 2))
			start_mode(&"cut")
			_drag_start = r.position
			_cell = r.end - Vector2i.ONE
			rig.focus(Defs.cell_center(r.position + Vector2i(4, 2)))
		&"tool_move", &"tool_demolish":
			var pick: Building = barn
			for b: Building in world.buildings.values():
				if not (b is ConstructionSite) and not b.recipe().is_empty():
					pick = b
			start_mode(StringName(what.trim_prefix("tool_")))
			_cell = pick.anchor
			if mode == &"move":
				_pick_moving(pick)
				_cell = pick.anchor + Vector2i(pick.size.x + 3, 1)
			rig.focus(Defs.cell_center(_cell))
		&"tool_gate":
			var field: Field = null
			for b: Building in world.buildings.values():
				if b is Field:
					field = b
			if field == null:
				return
			start_gate(field)
			for s in [1, 2, 3]:
				if world.field_gate_ok(field, (field.rot + s) % 4):
					_side = (field.rot + s) % 4
					break
			_cell = world.field_gate_cell(field, _side)
			rig.focus(Defs.cell_center(field.anchor + field.size / 2))
		&"tool_road":
			# a road with a bend that crosses the river nearest to the barn (the cursor on the far bank)
			var wet := Vector2i(-1, -1)
			var best := INF
			for y in range(0, world.size, 2):
				for x in range(0, world.size, 2):
					var c := Vector2i(x, y)
					if world.is_water(c) and world.river_axis(c) == 1 and Vector2(c - near).length() < best:
						best = Vector2(c - near).length()
						wet = c
			if wet.x < 0:
				wet = _block_anchor(near + Vector2i(16, 6))
			start(&"road_gravel")
			var start_at := _block_anchor(wet + Vector2i(-14, -6))
			_road_points.append(start_at)
			_road_points.append(Vector2i(start_at.x, _block_anchor(wet).y))
			_cell = _block_anchor(wet) + Vector2i(12, 0)
			rig.focus(Defs.cell_center(wet))
	_refresh()
	changed.emit()


func _debug_tree_rect(near: Vector2i, min_trees: int) -> Rect2i:
	for r in range(2, 60):
		for dy in range(-r, r + 1, 2):
			for dx in range(-r, r + 1, 2):
				var rect := Rect2i(near + Vector2i(dx, dy), Vector2i(4, 3))
				if world.trees_to_mark(rect).size() >= min_trees:
					return rect
	return Rect2i(near, Vector2i(4, 3))
