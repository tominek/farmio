class_name ResearchPanel
extends PanelContainer
## Research tree (T): branches as bands, prerequisites as elbow lines, the selected node's details
## and the Unlock button on the right. The game keeps running while it is open.

const NODE := Vector2(196, 64)
const DOCK_ROOM := 96.0            # room left at the bottom for the tool dock
const COL_W := 240.0                # node + gap
const SUB_ROW := 92.0               # sub-rows inside one branch (Processing)
const LABEL_W := 170.0              # branch names on the left
const PAD := 24.0
const NOTE_ROOM := 340.0            # empty room right of the nodes, so the note never hides one
const MAX_SIZE := Vector2(1872, 966)
const TOP := 90.0                   # below the HUD's top bar
const MARGIN := 24.0
const SIDE_W := 420.0
const HEADER_H := 58.0

const BRANCH_ICONS: Array[String] = ["flour", "logs", "gravel", "wheelbarrow", "wheat", "egg"]
const KIND_ICONS := {Tech.Kind.PLAN: "plan", Tech.Kind.UPGRADE: "upgrade", Tech.Kind.TECHNOLOGY: "tech"}
const KIND_CHIP := {Tech.Kind.PLAN: "Building plan", Tech.Kind.UPGRADE: "Upgrade", Tech.Kind.TECHNOLOGY: "Technology"}
## Technologies show what they bring as their big preview icon.
const TECH_ICONS := {&"gravel_road": "groad", &"wheelbarrow": "wheelbarrow", &"cobblestone": "road", &"better_seed": "seeds",
	&"new_crops": "corn"}
const STATE_TEXT := {"done": "Unlocked", "ready": "Can unlock now", "locked": "Needs something first",
	"later": "Coming later"}

const BANDS: Array[Color] = [Color("#FBF5E8"), Color("#F4ECDA")]
const LATER_FILL := Color("#F4EFE5")
const LATER_EDGE := Color("#B5AD9E")
const LATER_TEXT := Color("#6E665B")
const LOCKED_NAME := Color("#5E5244")
const DONE_TEXT := Color("#3F6B2E")
const READY_HOVER := Color("#F6EBD3")
const RING := Color("#3E7FB5")
const SOFT_EDGE := Color("#E4D6BC")
const SIDE_FILL := Color("#FFFDF7")
const SELECT_TEXT := Color("#1F4E77")

var world: World
var _selected := &""
var _canvas: TreeCanvas
var _scroll: ScrollContainer
var _frame: Control
var _legend: HFlowContainer
var _money: Label
var _info: VBoxContainer            # the details, rebuilt on every refresh
var _unlock: Button
var _unlock_lock: TextureRect
var _unlock_text: Label
var _unlock_num: Label
var _unlock_coin: TextureRect
var _reason: Label
var _italic: FontVariation
var _head: VBoxContainer            # kind and state chips, title (rebuilt)
var _preview: Preview


## The tree: branch bands, lines and node cards, all drawn here; click selects, drag pans.
class TreeCanvas extends Control:
	var panel: ResearchPanel
	var scroll: ScrollContainer
	var rects := {}                 # node id -> Rect2
	var bands: Array = []           # per branch: [top, height]
	var hovered := &""
	var _press := Vector2.ZERO
	var _pressed := false
	var _dragging := false

	func layout() -> void:
		rects.clear()
		bands.clear()
		var rows: Array[int] = []
		rows.resize(Tech.BRANCHES.size())
		rows.fill(1)
		var max_col := 0
		for id: StringName in Tech.NODES:
			var n := Tech.node(id)
			rows[n["branch"]] = maxi(rows[n["branch"]], int(n.get("row", 0)) + 1)
			max_col = maxi(max_col, n["col"])
		var y := 0.0
		for b in rows.size():
			var h := rows[b] * SUB_ROW + 20.0
			bands.append([y, h])
			y += h
		for id: StringName in Tech.NODES:
			var n := Tech.node(id)
			var top: float = bands[n["branch"]][0]
			rects[id] = Rect2(Vector2(LABEL_W + PAD + n["col"] * COL_W, top + PAD + int(n.get("row", 0)) * SUB_ROW), NODE)
		custom_minimum_size = Vector2(LABEL_W + PAD + max_col * COL_W + NODE.x + NOTE_ROOM, y)

	func content_height() -> float:
		return custom_minimum_size.y

	func _draw() -> void:
		var head := UiStyle.head_font(600)
		for b in bands.size():
			var top: float = bands[b][0]
			var h: float = bands[b][1]
			if b == bands.size() - 1:
				h = maxf(h, size.y - top)
			draw_rect(Rect2(0, top, size.x, h), BANDS[b % 2])
			var mid: float = top + float(bands[b][1]) * 0.5
			draw_texture_rect(UiStyle.icon(BRANCH_ICONS[b]), Rect2(18, mid - 13, 26, 26), false)
			draw_string(head, Vector2(54, mid + (head.get_ascent(18) - head.get_descent(18)) * 0.5),
				Tech.BRANCHES[b], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UiStyle.INK)
		# lines: the selected node's own lines last, on top
		var top_lines: Array = []
		for id: StringName in Tech.NODES:
			var needs: Array = Tech.node(id)["needs"]
			for i in needs.size():
				if id == panel._selected:
					top_lines.append([needs[i], id, i])
				else:
					_draw_line(needs[i], id, i)
		for l in top_lines:
			_draw_line(l[0], l[1], l[2])
		for id: StringName in Tech.NODES:
			_draw_node(id)

	func _route(from: StringName, to: StringName, i: int) -> PackedVector2Array:
		var a: Rect2 = rects[from]
		var b: Rect2 = rects[to]
		var p := Vector2(a.end.x, a.get_center().y)
		var q := Vector2(b.position.x, b.get_center().y)
		var x1 := a.end.x + 18.0 + 12.0 * i
		if b.position.x - a.end.x <= COL_W - NODE.x + 1.0:
			if absf(p.y - q.y) < 1.0:
				return PackedVector2Array([p, q])
			return PackedVector2Array([p, Vector2(x1, p.y), Vector2(x1, q.y), q])
		# skipping columns: through the gap above the target's row, so no card hides the line
		var cy := b.position.y - 13.0
		var x2 := b.position.x - 22.0
		return PackedVector2Array([p, Vector2(x1, p.y), Vector2(x1, cy), Vector2(x2, cy), Vector2(x2, q.y), q])

	func _draw_line(from: StringName, to: StringName, i: int) -> void:
		var pts := _route(from, to, i)
		var w := panel.world
		if to == panel._selected:
			draw_polyline(pts, UiStyle.DONE_EDGE if w.is_unlocked(from) else UiStyle.WARN, 4.0, true)
			return
		match panel._state(to):
			"later":
				ResearchPanel.dashed_polyline(self, pts, LATER_EDGE, 2.5)
			"locked":
				draw_polyline(pts, UiStyle.LOCKED_EDGE, 3.0, true)
			_:
				draw_polyline(pts, UiStyle.WOOD, 3.0, true)

	func _draw_node(id: StringName) -> void:
		var r: Rect2 = rects[id]
		var n := Tech.node(id)
		var state := panel._state(id)
		var selected := id == panel._selected
		var hover := id == hovered
		var fill: Color = {"done": UiStyle.DONE, "ready": UiStyle.PAPER, "locked": UiStyle.LOCKED,
			"later": LATER_FILL}[state]
		var edge: Color = {"done": UiStyle.DONE_EDGE, "ready": UiStyle.WOOD, "locked": UiStyle.LOCKED_EDGE,
			"later": LATER_EDGE}[state]
		if hover:
			fill = READY_HOVER if state == "ready" else fill.lightened(0.35)
		if selected:
			draw_style_box(UiStyle.box(RING, Color.TRANSPARENT, 16), r.grow(4))
		elif state == "done" or state == "ready":
			draw_style_box(UiStyle.box(edge, Color.TRANSPARENT, 12), Rect2(r.position + Vector2(0, 3), r.size))
		if state == "later":
			draw_style_box(UiStyle.box(fill, Color.TRANSPARENT, 12), r)
			ResearchPanel.dashed_polyline(self, ResearchPanel.round_rect_points(r.grow(-1), 11), edge, 2.0)
		else:
			draw_style_box(UiStyle.box(fill, edge, 12, 2), r)
		var alpha: float = {"locked": 0.55, "later": 0.4}.get(state, 1.0)
		draw_texture_rect(UiStyle.icon(KIND_ICONS[n["kind"]]), Rect2(r.position + Vector2(10, 18), Vector2(28, 28)),
			false, Color(1, 1, 1, alpha))
		var x := r.position.x + 48
		var head := UiStyle.head_font(600)
		var name_color: Color = {"locked": LOCKED_NAME, "later": LATER_TEXT}.get(state, UiStyle.INK)
		draw_string(head, Vector2(x, r.position.y + 11 + head.get_ascent(16)), n["name"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, name_color)
		var base := r.position.y + 47.0
		var bold := UiStyle.body_font(true)
		match state:
			"done":
				draw_string(bold, Vector2(x, base), "✓ Unlocked", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, DONE_TEXT)
			"ready":
				var short := int(n["cost"]) - panel.world.money
				var color := UiStyle.SHORT if short > 0 else UiStyle.INK
				var price := UiStyle.money_number(n["cost"])
				draw_string(bold, Vector2(x, base), price, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
				var px := x + bold.get_string_size(price, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 4
				draw_texture_rect(UiStyle.icon("qk"), Rect2(px, base - 13, 16, 16), false)
				if short > 0:
					draw_string(UiStyle.body_font(), Vector2(px + 20, base), "short " + UiStyle.money_number(short),
						HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiStyle.SHORT)
			"locked":
				draw_texture_rect(UiStyle.icon("locked"), Rect2(x, base - 12, 14, 14), false)
				draw_string(UiStyle.body_font(), Vector2(x + 18, base), UiStyle.money_number(n["cost"]),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiStyle.INK_SOFT)
			"later":
				draw_string(panel._italic, Vector2(x, base), "Coming later", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, LATER_TEXT)

	func _hit(pos: Vector2) -> StringName:
		for id: StringName in rects:
			if (rects[id] as Rect2).has_point(pos):
				return id
		return &""

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb and mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pressed = true
				_dragging = false
				_press = mb.position
			else:
				if _pressed and not _dragging:
					var id := _hit(mb.position)
					if id != &"":
						panel.select(id)
				_pressed = false
				_dragging = false
				mouse_default_cursor_shape = CURSOR_ARROW
			accept_event()
			return
		var mm := event as InputEventMouseMotion
		if mm:
			if _pressed and (_dragging or mm.position.distance_to(_press) > 5.0):
				_dragging = true
				mouse_default_cursor_shape = CURSOR_DRAG
				scroll.scroll_horizontal -= int(mm.relative.x)
				scroll.scroll_vertical -= int(mm.relative.y)
				accept_event()
				return
			var id := _hit(mm.position)
			if id != hovered:
				hovered = id
				mouse_default_cursor_shape = CURSOR_POINTING_HAND if id != &"" else CURSOR_ARROW
				queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_EXIT and hovered != &"":
			hovered = &""
			queue_redraw()


## A rounded box with a dashed edge ("coming later"): legend swatch, chips.
class DashedBox extends Control:
	var fill := LATER_FILL
	var edge := LATER_EDGE
	var radius := 10.0

	func _init(p_fill := LATER_FILL, p_edge := LATER_EDGE, p_radius := 10.0) -> void:
		fill = p_fill
		edge = p_edge
		radius = p_radius
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UiStyle.box(fill, Color.TRANSPARENT, int(radius)), r)
		ResearchPanel.dashed_polyline(self, ResearchPanel.round_rect_points(r.grow(-1), radius - 1), edge, 2.0, 4.0, 3.0)


## The stage behind the preview: light green with a ground shadow under a model, paper for an icon.
class Stage extends Control:
	const GREEN := Color("#E9F2DF")
	const GROUND := Color("#C9DDB4")
	var model := true

	func _draw() -> void:
		if size.x < 30.0 or size.y < 30.0:
			return
		var r := Rect2(Vector2.ZERO, size)
		var outline := ResearchPanel.round_rect_points(r, 12)
		outline.remove_at(outline.size() - 1)
		draw_colored_polygon(outline, GREEN if model else UiStyle.PAPER_DEEP)
		if model:
			# the ground ellipse the model stands on (220 × 34, 30 px above the bottom)
			var c := Vector2(size.x * 0.5, size.y - 30.0 - 17.0)
			var pts := PackedVector2Array()
			for i in 48:
				var a := TAU * i / 48.0
				pts.append(c + Vector2(cos(a) * 110.0, sin(a) * 17.0))
			draw_colored_polygon(pts, GROUND)
		draw_polyline(ResearchPanel.round_rect_points(r.grow(-0.75), 11.25), SOFT_EDGE, 1.5, true)


## A small open ring (the "turning slowly" sign), turning with the model.
class Spinner extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(14, 14)
		pivot_offset = Vector2(7, 7)
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_arc(Vector2(7, 7), 5.5, -PI * 0.25, PI * 1.25, 16, UiStyle.WOOD, 2.0, true)

	func _process(delta: float) -> void:
		if is_visible_in_tree():
			rotation += delta * 0.8


## The selected node's building turning slowly in a small 3D view (rendered only while visible);
## an upgrade shows the building at its new level, a technology a big icon instead.
class Preview extends Control:
	const MODELS := "res://assets/models/"
	var _stage: Stage
	var _view: SubViewportContainer
	var _vp: SubViewport
	var _pivot: Node3D
	var _cam: Camera3D
	var _icon: TextureRect
	var _turning: PanelContainer
	var _level: Label
	var _model := "-"

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE
		_stage = Stage.new()
		_stage.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		_stage.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(_stage)
		_view = SubViewportContainer.new()
		_view.stretch = true
		_view.mouse_filter = MOUSE_FILTER_IGNORE
		_view.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		add_child(_view)
		_vp = SubViewport.new()
		_vp.own_world_3d = true
		_vp.transparent_bg = true
		_vp.msaa_3d = Viewport.MSAA_4X
		_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
		_view.add_child(_vp)
		var env := Environment.new()
		env.background_mode = Environment.BG_CLEAR_COLOR
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(1.0, 0.97, 0.9)
		env.ambient_light_energy = 0.75
		var we := WorldEnvironment.new()
		we.environment = env
		_vp.add_child(we)
		var sun := DirectionalLight3D.new()
		sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(-35), 0)
		sun.light_energy = 1.1
		_vp.add_child(sun)
		_pivot = Node3D.new()
		_vp.add_child(_pivot)
		_cam = Camera3D.new()
		_cam.fov = 30
		_vp.add_child(_cam)
		_icon = UiStyle.icon_rect(null, 120)
		_icon.set_anchors_and_offsets_preset(PRESET_CENTER)
		_icon.grow_horizontal = GROW_DIRECTION_BOTH
		_icon.grow_vertical = GROW_DIRECTION_BOTH
		add_child(_icon)

		# "turning slowly" (bottom right) and the level of an upgrade (top left)
		_turning = PanelContainer.new()
		var tsb := UiStyle.box(UiStyle.PAPER, UiStyle.BOARD, 12, 1)
		tsb.content_margin_left = 10
		tsb.content_margin_right = 10
		tsb.content_margin_top = 3
		tsb.content_margin_bottom = 3
		_turning.add_theme_stylebox_override("panel", tsb)
		_turning.mouse_filter = MOUSE_FILTER_IGNORE
		var th := HBoxContainer.new()
		th.add_theme_constant_override("separation", 6)
		_turning.add_child(th)
		var sp := Spinner.new()
		sp.size_flags_vertical = SIZE_SHRINK_CENTER
		th.add_child(sp)
		var tl := Label.new()
		tl.text = "turning slowly"
		tl.add_theme_font_size_override("font_size", 12)
		tl.add_theme_color_override("font_color", UiStyle.INK_SOFT)
		th.add_child(tl)
		_turning.set_anchors_preset(PRESET_BOTTOM_RIGHT)
		_turning.grow_horizontal = GROW_DIRECTION_BEGIN
		_turning.grow_vertical = GROW_DIRECTION_BEGIN
		_turning.offset_left = -10
		_turning.offset_right = -10
		_turning.offset_top = -10
		_turning.offset_bottom = -10
		add_child(_turning)
		_level = Label.new()
		_level.add_theme_font_override("font", UiStyle.body_font(true))
		_level.add_theme_font_size_override("font_size", 13)
		_level.add_theme_color_override("font_color", UiStyle.PAPER)
		var lsb := UiStyle.box(UiStyle.GO, Color.TRANSPARENT, 12)
		lsb.content_margin_left = 10
		lsb.content_margin_right = 10
		lsb.content_margin_top = 2
		lsb.content_margin_bottom = 2
		_level.add_theme_stylebox_override("normal", lsb)
		_level.position = Vector2(10, 10)
		add_child(_level)

	## Shows the model (Models name) — at `level` for an upgrade (0: none) — or the icon when there
	## is none.
	func show_model(model: String, icon: Texture2D, level := 0) -> void:
		var has := model != "" and ResourceLoader.exists(MODELS + model + ".glb")
		_view.visible = has
		_turning.visible = has
		_stage.model = has
		_stage.queue_redraw()
		_icon.visible = not has
		_icon.texture = icon
		_level.visible = has and level > 0
		_level.text = "Level %d" % level
		if not has or model == _model:
			return
		_model = model
		for c in _pivot.get_children():
			c.queue_free()
		var mi: MeshInstance3D = Models.instance(model)
		var box := mi.get_aabb()
		var c := box.get_center()
		mi.position = Vector3(-c.x, -box.position.y, -c.z)
		_pivot.add_child(mi)
		_pivot.rotation.y = deg_to_rad(-30)
		# frame the whole model: its bounding sphere fits the height of the view
		var r := box.size.length() * 0.5
		var dist := r / sin(deg_to_rad(_cam.fov * 0.5)) * 1.05
		var target := Vector3(0, box.size.y * 0.62, 0)
		var dir := Vector3(0, sin(deg_to_rad(24)), cos(deg_to_rad(24)))
		_cam.look_at_from_position(target + dir * dist, target)

	func _process(delta: float) -> void:
		if _view.visible and is_visible_in_tree():
			_pivot.rotation.y += delta * 0.4


func setup(p_world: World) -> void:
	world = p_world
	add_to_group("debug_show")
	_italic = FontVariation.new()
	_italic.base_font = UiStyle.body_font()
	_italic.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.2, 1), Vector2.ZERO)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	add_child(col)
	col.add_child(_build_header())
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	body.add_child(_build_tree())
	body.add_child(_build_side())

	world.tech_changed.connect(refresh)
	world.stock_changed.connect(func() -> void:
		if visible:
			refresh())
	visibility_changed.connect(_fit)
	get_tree().root.size_changed.connect(_fit)
	select(Tech.NODES.keys()[0])


func _build_header() -> Control:
	var head := PanelContainer.new()
	var sb := UiStyle.box(UiStyle.BOARD, UiStyle.WOOD, 12, 0)
	sb.border_width_bottom = 2
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
	sb.content_margin_left = 18
	sb.content_margin_right = 12
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	head.add_theme_stylebox_override("panel", sb)
	head.custom_minimum_size.y = HEADER_H
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	head.add_child(row)
	row.add_child(_centered(UiStyle.icon_rect(UiStyle.icon("tech"), 28)))
	var title := _label("Research", UiStyle.head_font(600), 24)
	row.add_child(title)

	var pill := PanelContainer.new()
	var psb := UiStyle.box(UiStyle.PAPER_DEEP, Color.TRANSPARENT, 12)
	psb.content_margin_left = 10
	psb.content_margin_right = 10
	psb.content_margin_top = 3
	psb.content_margin_bottom = 3
	pill.add_theme_stylebox_override("panel", psb)
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 6)
	pill.add_child(ph)
	var dot := Panel.new()
	dot.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.GO, Color.TRANSPARENT, 4))
	dot.custom_minimum_size = Vector2(8, 8)
	ph.add_child(_centered(dot))
	ph.add_child(_label("The farm keeps running while this is open", UiStyle.body_font(), 14))
	row.add_child(pill)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var have := HBoxContainer.new()
	have.add_theme_constant_override("separation", 6)
	have.add_child(_centered(UiStyle.icon_rect(UiStyle.icon("qk"), 20)))
	have.add_child(_label("You have", UiStyle.body_font(), 15))
	_money = _label("", UiStyle.body_font(true), 15)
	have.add_child(_money)
	row.add_child(have)

	var close := Button.new()
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(90, 38)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(hide)
	var ch := HBoxContainer.new()
	ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ch.alignment = BoxContainer.ALIGNMENT_CENTER
	ch.add_theme_constant_override("separation", 8)
	ch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ch.offset_bottom = -3
	ch.add_child(_label("Close", UiStyle.head_font(600), 15))
	ch.add_child(UiStyle.key_cap("T"))
	close.add_child(ch)
	row.add_child(close)
	return head


func _build_tree() -> Control:
	var m := MarginContainer.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_theme_constant_override("margin_left", 20)
	m.add_theme_constant_override("margin_right", 20)
	m.add_theme_constant_override("margin_top", 16)
	m.add_theme_constant_override("margin_bottom", 16)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	m.add_child(v)

	_legend = HFlowContainer.new()
	_legend.add_theme_constant_override("h_separation", 22)
	_legend.add_theme_constant_override("v_separation", 6)
	v.add_child(_legend)
	for s: Array in [["Unlocked", UiStyle.DONE, UiStyle.DONE_EDGE], ["Can unlock now", UiStyle.PAPER, UiStyle.WOOD],
			["Needs something first", UiStyle.LOCKED, UiStyle.LOCKED_EDGE], ["Coming later", LATER_FILL, LATER_EDGE]]:
		var sw: Control
		if s[0] == "Coming later":
			sw = DashedBox.new(s[1], s[2], 4.0)
		else:
			sw = Panel.new()
			sw.add_theme_stylebox_override("panel", UiStyle.box(s[1], s[2], 4, 2))
		sw.custom_minimum_size = Vector2(18, 14)
		_legend.add_child(_legend_item(sw, s[0]))
	var sep := ColorRect.new()
	sep.color = Color("#E8DAC0")
	sep.custom_minimum_size = Vector2(2, 18)
	_legend.add_child(_centered(sep))
	for k: Tech.Kind in [Tech.Kind.PLAN, Tech.Kind.UPGRADE, Tech.Kind.TECHNOLOGY]:
		_legend.add_child(_legend_item(UiStyle.icon_rect(UiStyle.icon(KIND_ICONS[k]), 18), KIND_CHIP[k]))

	# the frame: rounded mask over the scrolling tree, the note card floats in its corner
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PAPER, Color.TRANSPARENT, 12))
	frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	v.add_child(frame)
	_frame = frame
	var holder := Control.new()
	frame.add_child(holder)
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(_scroll)
	_canvas = TreeCanvas.new()
	_canvas.panel = self
	_canvas.scroll = _scroll
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.layout()
	_scroll.add_child(_canvas)
	UiStyle.slim_scrollbars(_scroll)

	var note := PanelContainer.new()
	var nsb := UiStyle.box(UiStyle.PAPER, SOFT_EDGE, 10, 2)
	nsb.content_margin_left = 14
	nsb.content_margin_right = 14
	nsb.content_margin_top = 10
	nsb.content_margin_bottom = 10
	note.add_theme_stylebox_override("panel", nsb)
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = 272
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_font_override("normal_font", UiStyle.body_font())
	text.add_theme_font_override("bold_font", UiStyle.body_font(true))
	for f in ["normal_font_size", "bold_font_size"]:
		text.add_theme_font_size_override(f, 14)
	text.add_theme_color_override("default_color", UiStyle.INK_SOFT)
	text.text = "A node needs [b][color=#3B2A1E]every[/color][/b] node with a line into it. Scroll or drag to pan when more branches arrive."
	note.add_child(text)
	note.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	note.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	note.grow_vertical = Control.GROW_DIRECTION_BEGIN
	note.offset_left = -20
	note.offset_right = -20
	note.offset_top = -16
	note.offset_bottom = -16
	holder.add_child(note)

	var border := Panel.new()
	border.add_theme_stylebox_override("panel", UiStyle.box(Color.TRANSPARENT, SOFT_EDGE, 12, 2))
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(border)
	return m


func _legend_item(swatch: Control, text: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.add_child(_centered(swatch))
	h.add_child(_label(text, UiStyle.body_font(), 14))
	return h


func _build_side() -> Control:
	var side := PanelContainer.new()
	var sb := UiStyle.box(SIDE_FILL, Color.TRANSPARENT, 0)
	sb.border_color = SOFT_EDGE
	sb.border_width_left = 2
	sb.corner_radius_bottom_right = 12
	sb.set_content_margin_all(0)
	side.add_theme_stylebox_override("panel", sb)
	side.custom_minimum_size.x = SIDE_W
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	UiStyle.slim_scrollbars(scroll)
	var m := MarginContainer.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.size_flags_vertical = Control.SIZE_EXPAND_FILL
	m.add_theme_constant_override("margin_left", 22)
	m.add_theme_constant_override("margin_right", 22)
	m.add_theme_constant_override("margin_top", 20)
	m.add_theme_constant_override("margin_bottom", 22)
	scroll.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	m.add_child(v)
	_head = VBoxContainer.new()
	_head.add_theme_constant_override("separation", 16)
	v.add_child(_head)
	_preview = Preview.new()
	_preview.custom_minimum_size.y = 210
	v.add_child(_preview)
	_info = VBoxContainer.new()
	_info.add_theme_constant_override("separation", 16)
	v.add_child(_info)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)

	var bottom := VBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	v.add_child(bottom)
	_unlock = Button.new()
	_unlock.theme_type_variation = "PrimaryButton"
	_unlock.focus_mode = Control.FOCUS_NONE
	_unlock.custom_minimum_size.y = 58
	_unlock.pressed.connect(func() -> void: world.unlock(_selected))
	var uh := HBoxContainer.new()
	uh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	uh.alignment = BoxContainer.ALIGNMENT_CENTER
	uh.add_theme_constant_override("separation", 8)
	uh.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	uh.offset_bottom = -3
	_unlock.add_child(uh)
	_unlock_lock = UiStyle.icon_rect(UiStyle.icon("locked"), 22)
	uh.add_child(_centered(_unlock_lock))
	_unlock_text = _label("Unlock ·", UiStyle.head_font(600), 21)
	uh.add_child(_unlock_text)
	_unlock_num = _label("", UiStyle.body_font(true), 21)
	uh.add_child(_unlock_num)
	_unlock_coin = UiStyle.icon_rect(UiStyle.icon("qk"), 24)
	uh.add_child(_centered(_unlock_coin))
	bottom.add_child(_unlock)
	_reason = _label("", UiStyle.body_font(), 14, UiStyle.INK_SOFT)
	_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.add_child(_reason)
	return side


## Size and place the panel: the design's 1872 × 966 under the HUD, smaller windows scroll.
func _fit() -> void:
	if not visible or not is_inside_tree():
		return
	var vp := get_viewport_rect().size
	var avail := vp - Vector2(MARGIN * 2, TOP + DOCK_ROOM)          # keep clear of the tool dock
	var sz := Vector2(minf(MAX_SIZE.x, avail.x), minf(MAX_SIZE.y, avail.y))
	# the tree frame takes the height left under the legend, but not more than the tree needs
	var legend_h := maxf(_legend.get_combined_minimum_size().y, _legend.size.y)
	var room := sz.y - HEADER_H - 4 - 32 - legend_h - 12
	_frame.custom_minimum_size.y = clampf(room, 120, _canvas.content_height() + 4)
	position = Vector2(floorf((vp.x - sz.x) * 0.5), TOP + maxf(0, floorf((avail.y - sz.y) * 0.5)))
	size = sz


## Opens the tree on a node (e.g. from a locked build button).
func select(id: StringName) -> void:
	_selected = id
	refresh()
	_scroll_to.call_deferred(id)


func _scroll_to(id: StringName) -> void:
	var r: Rect2 = _canvas.rects.get(id, Rect2())
	var view := Rect2(Vector2(_scroll.scroll_horizontal, _scroll.scroll_vertical), _scroll.size)
	if view.size.x <= 0 or view.encloses(r.grow(8)):
		return
	_scroll.scroll_horizontal = int(clampf(view.position.x, r.end.x + 8 - view.size.x, r.position.x - 8 - LABEL_W))
	_scroll.scroll_vertical = int(clampf(view.position.y, r.end.y + 8 - view.size.y, r.position.y - 8))


func refresh() -> void:
	_money.text = UiStyle.money_number(world.money)
	_canvas.queue_redraw()
	_show_details()


func _state(id: StringName) -> String:
	if world.is_unlocked(id):
		return "done"
	if Tech.is_later(id):
		return "later"
	return "ready" if world.unlock_ready(id) else "locked"


## Model shown in the preview: the building of a plan, the building at the new level of an
## upgrade, a "coming later" building if its model exists already; "" for technologies.
func _model_for(id: StringName) -> String:
	var n := Tech.node(id)
	if n["kind"] == Tech.Kind.TECHNOLOGY:
		return ""
	var buildings: Array = n.get("buildings", [])
	if not buildings.is_empty():
		return Defs.def(buildings[0]).get("model", "")
	var levels: Dictionary = n.get("levels", {})
	if not levels.is_empty():
		var def_id: StringName = levels.keys()[0]
		return "%s_l%d" % [Defs.def(def_id)["model"], levels[def_id]]
	return "building_%s" % id


func _show_details() -> void:
	for box: Control in [_head, _info]:
		for c in box.get_children():
			c.queue_free()
	var id := _selected
	var n := Tech.node(id)
	var state := _state(id)

	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	chips.add_child(_chip(UiStyle.SELECT_PAPER, Color.TRANSPARENT, KIND_ICONS[n["kind"]], 20,
		KIND_CHIP[n["kind"]], SELECT_TEXT, true))
	var st_icon: String = {"done": "working", "locked": "locked", "later": "clock"}.get(state, "")
	var st_fill: Color = {"done": UiStyle.DONE, "ready": UiStyle.PAPER, "locked": UiStyle.LOCKED}.get(state, LATER_FILL)
	var st_edge: Color = UiStyle.WOOD if state == "ready" else Color.TRANSPARENT
	chips.add_child(_chip(st_fill, st_edge, st_icon, 16, STATE_TEXT[state],
		DONE_TEXT if state == "done" else LOCKED_NAME, false, state == "later"))
	_head.add_child(chips)

	var title := _label(n["name"], UiStyle.head_font(600), 32)
	_head.add_child(title)
	var levels_of: Dictionary = n.get("levels", {})
	_preview.show_model(_model_for(id), UiStyle.icon(TECH_ICONS.get(id, KIND_ICONS[n["kind"]])),
		int(levels_of.values()[0]) if not levels_of.is_empty() else 0)
	var desc := _label(n["desc"], UiStyle.body_font(), 16)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_constant_override("line_spacing", 5)
	_info.add_child(desc)

	# needs
	var needs := _section("Needs")
	for p: StringName in n["needs"]:
		needs.add_child(_need_row(p))
	if (n["needs"] as Array).is_empty():
		needs.add_child(_label("Nothing — available from the start", UiStyle.body_font(), 15, UiStyle.INK_SOFT))

	# what building (or upgrading) costs afterwards
	var costs: Array = []           # [resource, amount, note]
	for def_id: StringName in n.get("buildings", []):
		var mat: Dictionary = Defs.def(def_id).get("material", {})
		for res: StringName in mat:
			costs.append([res, mat[res], " per road block" if Defs.def(def_id).has("road") else ""])
	var levels: Dictionary = n.get("levels", {})
	if not levels.is_empty():
		var lvl: int = levels.values()[0]
		var names := PackedStringArray(levels.keys().map(func(d: StringName) -> String: return Defs.def(d)["name"]))
		costs.append([&"planks", Defs.UPGRADE_PLANKS[lvl], " each: %s → level %d" % [", ".join(names), lvl]])
	if not costs.is_empty() and state != "later":
		var sec := _section("Upgrading then costs" if n["kind"] == Tech.Kind.UPGRADE else "Building it then costs")
		for c: Array in costs:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			row.add_child(_centered(UiStyle.icon_rect(UiStyle.resource_icon(c[0]), 22)))
			row.add_child(_label(Defs.format_goods(c[0], c[1]), UiStyle.body_font(true), 16))
			if c[2] != "":
				var note := _label(c[2], UiStyle.body_font(), 15, UiStyle.INK_SOFT)
				note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				row.add_child(note)
			sec.add_child(row)

	# leads to
	var leads := Tech.leads_to(id)
	if not leads.is_empty():
		var sec := _section("Leads to")
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 8)
		sec.add_child(flow)
		for o: StringName in leads:
			flow.add_child(_lead_chip(o))

	# the Unlock button and why it can't be pressed
	var cost := int(n["cost"])
	var ok := world.can_unlock(id)
	_unlock.disabled = not ok
	_unlock.remove_theme_stylebox_override("disabled")
	_unlock_lock.visible = not ok and state != "done"
	_unlock_text.text = "Unlock ·"
	_unlock_num.text = UiStyle.money_number(cost)
	_unlock_num.visible = state != "later"
	_unlock_coin.visible = state != "later"
	_unlock_text.visible = true
	var text_color := UiStyle.PAPER if ok else UiStyle.LOCKED_TEXT
	_unlock_coin.modulate.a = 1.0 if ok else 0.5
	match state:
		"done":
			var sb := UiStyle.box(UiStyle.DONE, UiStyle.DONE_EDGE, UiStyle.RADIUS, 2)
			_unlock.add_theme_stylebox_override("disabled", sb)
			_unlock_text.text = "✓ Unlocked"
			_unlock_num.visible = false
			_unlock_coin.visible = false
			text_color = DONE_TEXT
			_reason.text = "Already researched"
		"later":
			_unlock_text.text = "Unlock"
			_reason.text = "Coming later"
		"locked":
			var missing := PackedStringArray()
			for p: StringName in n["needs"]:
				if not world.is_unlocked(p):
					missing.append("the " + String(Tech.node(p)["name"]))
			_reason.text = "Unlock %s first" % " and ".join(missing)
		_:
			_reason.text = "" if ok else "Not enough quacks — %s short" % UiStyle.money_number(cost - world.money)
	_reason.visible = _reason.text != ""
	for l: Label in [_unlock_text, _unlock_num]:
		l.add_theme_color_override("font_color", text_color)


func _section(title: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	var l := _label(title.to_upper(), UiStyle.head_font(600), 13, UiStyle.INK_SOFT)
	v.add_child(l)
	_info.add_child(v)
	return v


func _need_row(p: StringName) -> Control:
	var met := world.is_unlocked(p)
	var row := PanelContainer.new()
	var sb := UiStyle.box(UiStyle.DONE if met else UiStyle.WARN_PAPER, Color.TRANSPARENT, 10)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	row.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	row.add_child(h)
	var badge := _label("✓" if met else "✗", UiStyle.body_font(true), 13, UiStyle.PAPER)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.custom_minimum_size = Vector2(22, 22)
	var bsb := UiStyle.box(UiStyle.GO if met else UiStyle.WARN, Color.TRANSPARENT, 11)
	bsb.set_content_margin_all(0)
	badge.add_theme_stylebox_override("normal", bsb)
	h.add_child(_centered(badge))
	var name := _label(Tech.node(p)["name"], UiStyle.body_font(true), 15)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(name)
	if met:
		h.add_child(_label("unlocked", UiStyle.body_font(), 15, DONE_TEXT))
	else:
		var go := LinkButton.new()
		go.focus_mode = Control.FOCUS_NONE
		go.text = "Go to it" if Tech.is_later(p) else "Go to it · %s" % UiStyle.money_number(Tech.node(p)["cost"])
		go.add_theme_font_override("font", UiStyle.body_font())
		go.add_theme_font_size_override("font_size", 15)
		for c in ["font_color", "font_hover_color", "font_pressed_color"]:
			go.add_theme_color_override(c, UiStyle.SELECT)
		go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		go.pressed.connect(select.bind(p))
		h.add_child(go)
		if not Tech.is_later(p):
			h.add_child(_centered(UiStyle.icon_rect(UiStyle.icon("qk"), 16)))
	return row


func _lead_chip(o: StringName) -> Control:
	var state := _state(o)
	var suffix: String = {"done": "unlocked", "ready": "can unlock now", "locked": "locked",
		"later": "coming later"}[state]
	var fill: Color = {"done": UiStyle.DONE, "ready": UiStyle.PAPER}.get(state, UiStyle.LOCKED)
	var edge: Color = {"done": UiStyle.DONE_EDGE, "ready": UiStyle.WOOD}.get(state, UiStyle.LOCKED_EDGE)
	var chip := _chip(fill, edge, KIND_ICONS[Tech.node(o)["kind"]], 18,
		"%s · %s" % [Tech.node(o)["name"], suffix], LOCKED_NAME, false, state == "later")
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	chip.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			select(o))
	if state == "later" or state == "locked":
		(chip.get_child(-1).get_child(0) as TextureRect).modulate.a = 0.5
	return chip


## A rounded chip: icon + text; `dashed` draws the "coming later" edge.
func _chip(fill: Color, edge: Color, icon_name: String, icon_size: float, text: String, color: Color,
		bold := false, dashed := false) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UiStyle.box(Color.TRANSPARENT if dashed else fill, Color.TRANSPARENT if dashed else edge, 12, 2)
	sb.content_margin_left = 6 if icon_name != "" else 10
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if dashed:
		sb.bg_color = fill
		p.draw.connect(func() -> void:
			dashed_polyline(p, round_rect_points(Rect2(Vector2.ZERO, p.size).grow(-1), 11.0), LATER_EDGE, 2.0, 4.0, 3.0))
		p.resized.connect(p.queue_redraw)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	if icon_name != "":
		h.add_child(_centered(UiStyle.icon_rect(UiStyle.icon(icon_name), icon_size)))
	h.add_child(_label(text, UiStyle.body_font(bold), 14, color))
	return p


func _label(text: String, font: Font, font_size: int, color := UiStyle.INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


func _centered(c: Control) -> Control:
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return c


# --- drawing helpers -------------------------------------------------------------------

## Outline of a rounded rectangle, closed (the first point repeated at the end).
static func round_rect_points(r: Rect2, radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var corners := [[r.position + Vector2(radius, radius), PI], [Vector2(r.end.x - radius, r.position.y + radius), PI * 1.5],
		[r.end - Vector2(radius, radius), 0.0], [Vector2(r.position.x + radius, r.end.y - radius), PI * 0.5]]
	for c: Array in corners:
		for s in 7:
			var ang: float = c[1] + s / 6.0 * PI * 0.5
			pts.append((c[0] as Vector2) + Vector2(cos(ang), sin(ang)) * radius)
	pts.append(pts[0])
	return pts


static func dashed_polyline(ci: CanvasItem, pts: PackedVector2Array, color: Color, width: float, dash := 6.0,
		gap := 6.0) -> void:
	var on := true
	var left := dash
	for k in pts.size() - 1:
		var a := pts[k]
		var seg := a.distance_to(pts[k + 1])
		if seg < 0.001:
			continue
		var dir := (pts[k + 1] - a) / seg
		var t := 0.0
		while t < seg - 0.001:
			var step := minf(left, seg - t)
			if on:
				ci.draw_line(a + dir * t, a + dir * (t + step), color, width, true)
			t += step
			left -= step
			if left <= 0.001:
				on = not on
				left = dash if on else gap


## --show=research: the tree on the Water Mill; research_mixed also sets the design's sample state
## (a few nodes unlocked, 1 840 qk) on the given world; research_upgrade / research_tech open an
## upgrade (Mill gear II) / a technology (Gravel road) for their previews.
func debug_show(what: String, game: Node) -> void:
	var on: StringName = {"research": &"water_mill", "research_mixed": &"water_mill",
		"research_upgrade": &"mill_gear_2", "research_tech": &"gravel_road"}.get(what, &"")
	if on == &"":
		return
	if what == "research_mixed":
		world.unlocked.clear()
		for id: StringName in [&"hand_mill", &"gravel_road", &"wheelbarrow"]:
			world.unlocked[id] = true
		world.money = 1840
		world.tech_changed.emit()
		world.stock_changed.emit()
	var hud: Variant = game.get("hud")
	if hud is Hud:
		(hud as Hud).show_research(on)
	else:
		select(on)
		show()
