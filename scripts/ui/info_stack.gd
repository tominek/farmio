class_name InfoStack
extends Control
## The open info panels, one per selected object, each floating beside its object on the map and
## following it as the camera moves. A click on another object opens another panel; panels close
## with their × (Esc closes the newest). A click into a panel brings it to the front; a panel dragged
## by its header stays where it was put. Forwards the panels' link signals.

signal selection_changed
signal follow_requested(w: Worker)
signal priorities_requested
signal research_requested(id: StringName)
signal dealer_requested
signal gate_requested(f: Field)

const GAP := 20.0             # between the object and its panel
const TOP := 86.0             # under the top bar
const BOTTOM := 96.0          # above the tool dock
const HEIGHT := 4.0           # m: buildings are measured up to this height on screen

var world: World
var camera: Camera3D
var _panels: Array[InfoPanel] = []      # oldest first; the newest is drawn on top
var _drag: InfoPanel = null             # panel being dragged by its header
var _drag_offset := Vector2.ZERO


func setup(p_world: World) -> void:
	world = p_world
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("debug_show")


## Opens a panel for `t`, or brings its open panel to the front.
func select(t: Variant) -> void:
	if t == null:
		return
	for p in _panels:
		if p.target == t:
			_raise(p)
			return
	var p := InfoPanel.new()
	add_child(p)
	p.setup(world)
	p.follow_requested.connect(func(w: Worker) -> void: follow_requested.emit(w))
	p.priorities_requested.connect(func() -> void: priorities_requested.emit())
	p.research_requested.connect(func(id: StringName) -> void: research_requested.emit(id))
	p.dealer_requested.connect(func() -> void: dealer_requested.emit())
	p.gate_requested.connect(func(f: Field) -> void: gate_requested.emit(f))
	p.selection_changed.connect(func() -> void:
		if p.target == null:
			_remove(p))
	_panels.append(p)
	p.select(t)
	_place(p)
	selection_changed.emit()


## Closes every panel.
func clear() -> void:
	for p in _panels.duplicate():
		p.clear()


## Closes the newest panel; false when none is open.
func close_last() -> bool:
	if _panels.is_empty():
		return false
	_panels.back().clear()
	return true


func is_open() -> bool:
	return not _panels.is_empty()


func targets() -> Array:
	return _panels.map(func(p: InfoPanel) -> Variant: return p.target)


func has_target(t: Variant) -> bool:
	return targets().has(t)


## Demolish / cancel of the newest panel (Delete key).
func press_action() -> void:
	if not _panels.is_empty():
		_panels.back().press_action()


func _raise(p: InfoPanel) -> void:
	_panels.erase(p)
	_panels.append(p)
	move_child(p, -1)


func _remove(p: InfoPanel) -> void:
	_panels.erase(p)
	p.queue_free()
	selection_changed.emit()


func _process(_delta: float) -> void:
	for p in _panels:
		if not p.has_meta("pinned"):
			_place(p)


## Clicks into a panel raise it (before the panel's own buttons get them); a press on the header,
## off its buttons and the name field, starts dragging.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			_drag = null
			return
		var p := _panel_at(event.position)
		var hovered := get_viewport().gui_get_hovered_control()
		if p == null or hovered == null or not (p == hovered or p.is_ancestor_of(hovered)):
			return      # not this panel, or another panel lies over it
		_raise(p)
		var head := p.header()
		if head.get_global_rect().has_point(event.position) and not _on_control(head, event.position):
			_drag = p
			_drag_offset = event.position - p.position
			p.set_meta("pinned", true)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _drag:
		var vp := get_viewport_rect().size
		var pos: Vector2 = event.position - _drag_offset
		pos.x = clampf(pos.x, 0.0, vp.x - _drag.size.x)
		pos.y = clampf(pos.y, 0.0, vp.y - 40.0)
		_drag.position = pos.floor()
		get_viewport().set_input_as_handled()


func _panel_at(at: Vector2) -> InfoPanel:
	for i in range(_panels.size() - 1, -1, -1):
		if _panels[i].visible and _panels[i].get_global_rect().has_point(at):
			return _panels[i]
	return null


## True over a button or a text field inside `c`.
func _on_control(c: Control, at: Vector2) -> bool:
	for n in c.find_children("*", "BaseButton", true, false) + c.find_children("*", "LineEdit", true, false):
		if (n as Control).is_visible_in_tree() and (n as Control).get_global_rect().has_point(at):
			return true
	return false


## Beside the object: right of it, or left when there is no room; kept between the bar and the dock.
func _place(p: InfoPanel) -> void:
	if camera == null or p.target == null:
		return
	var r := _screen_rect(p.target)
	var vp := get_viewport_rect().size
	var s := p.get_combined_minimum_size()
	var x := r.end.x + GAP
	if x + s.x > vp.x - 12.0:
		x = r.position.x - GAP - s.x
	x = clampf(x, 12.0, vp.x - 12.0 - s.x)
	var y := clampf(r.get_center().y - s.y * 0.5, TOP, maxf(TOP, vp.y - BOTTOM - s.y))
	p.position = Vector2(x, y).floor()


## The object's box on screen: its footprint and, for buildings, the space above it.
func _screen_rect(t: Variant) -> Rect2:
	var corners: Array[Vector3] = []
	if t is Worker:
		var c := Vector3((t as Worker).pos.x * Defs.TILE, 0.0, (t as Worker).pos.y * Defs.TILE)
		for d: Vector3 in [Vector3(-1, 0, -1), Vector3(1, 0, 1), Vector3(1, 2.5, -1), Vector3(-1, 2.5, 1)]:
			corners.append(c + d)
	else:
		var r := (t as Building).rect() if t is Building else Rect2i(t, Vector2i(Defs.ROAD_BLOCK, Defs.ROAD_BLOCK))
		var h := HEIGHT if t is Building and not (t is Field) else 0.0
		# the footprint with the selection outline around it (SelectionView)
		var m := Rect2(Vector2(r.position) * Defs.TILE, Vector2(r.size) * Defs.TILE)
		m = m.grow(SelectionView.PAD + SelectionView.WHITE + SelectionView.BLUE)
		for cx in [m.position.x, m.end.x]:
			for cz in [m.position.y, m.end.y]:
				for y in [0.0, h]:
					corners.append(Vector3(cx, y, cz))
	var out := Rect2()
	var first := true
	for c in corners:
		if camera.is_position_behind(c):
			continue
		var p := camera.unproject_position(c)
		if first:
			out = Rect2(p, Vector2.ZERO)
			first = false
		else:
			out = out.expand(p)
	return out


## --show=info_*: a panel for a sample object (InfoPanel.debug_target picks it).
func debug_show(name: String, game: Node) -> void:
	if name == "info_drag":
		_debug_drag(game)
		return
	if not name.begins_with("info_"):
		return
	var p := InfoPanel.new()
	p.setup(world)
	var t: Variant = p.debug_target(name)
	p.free()
	if t == null:
		return
	select(t)
	var rig: Variant = game.get("rig")
	if rig:
		var r := Rect2i((t as Worker).cell(), Vector2i.ONE) if t is Worker else (t as Building).rect()
		rig.focus(Defs.footprint_center(r.position, r.size))


## --show=info_drag: two panels, the first dragged by its header to the top left and raised.
func _debug_drag(game: Node) -> void:
	await debug_show("info_mill", game)
	select(world.fields[0])
	await get_tree().process_frame
	await get_tree().process_frame
	var p := _panels[0]
	var from := p.header().get_global_rect().position + Vector2(40, 16)
	var to := Vector2(300, 200)
	# events come in window pixels; the UI works in its own (stretched) units
	var xf := get_viewport().get_final_transform()
	from = xf * from
	to = xf * to
	for e: InputEvent in [_motion(from), _mouse(from, true), _motion(to), _mouse(to, false)]:
		Input.parse_input_event(e)
		await get_tree().process_frame


static func _mouse(at: Vector2, down: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = at
	e.global_position = at
	return e


static func _motion(at: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	return e
