class_name ResearchPanel
extends PanelContainer
## Research tree (T): branches as rows, prerequisites as lines, the selected node's details and the
## Unlock button on the right. The game keeps running while it is open.

const COL_W := 178.0
const ROW_H := 74.0
const NODE := Vector2(150, 52)
const LEFT := 110.0                 # room for the branch names
const TOP := 12.0

const COLORS := {                   # node state -> [fill, border]
	"done": [Color(0.85, 0.93, 0.82), Color(0.35, 0.62, 0.3)],
	"ready": [Color(1.0, 0.98, 0.94), Color(0.85, 0.55, 0.18)],
	"locked": [Color(0.9, 0.9, 0.9), Color(0.6, 0.6, 0.6)],
	"later": [Color(0.97, 0.97, 0.97), Color(0.7, 0.7, 0.7)],
}

var world: World
var _canvas: TreeCanvas
var _buttons := {}                  # node id -> Button
var _selected := &""
var _title: Label
var _kind: Label
var _desc: Label
var _needs: Label
var _then: Label
var _leads: Label
var _unlock: Button
var _reason: Label


## Draws the prerequisite lines behind the node buttons.
class TreeCanvas extends Control:
	var lines: Array = []           # [from, to] points

	func _draw() -> void:
		for l in lines:
			var a: Vector2 = l[0]
			var b: Vector2 = l[1]
			var mid := (a.x + b.x) * 0.5
			var pts := PackedVector2Array()
			if absf(a.y - b.y) < 1.0 and b.x - a.x > COL_W:
				# along a row over other nodes: up into the gap above the row, across, and down into the node
				var y := a.y - NODE.y * 0.5 - 8.0
				pts = PackedVector2Array([a, a + Vector2(10, 0), Vector2(a.x + 14, y), Vector2(b.x - 22, y), Vector2(b.x - 14, b.y), b])
			else:
				for i in 17:
					var t := i / 16.0
					# a smooth S from the right side of one node to the left side of the next
					pts.append(a.bezier_interpolate(Vector2(mid, a.y), Vector2(mid, b.y), b, t))
			draw_polyline(pts, Color(0.45, 0.45, 0.45), 2.0, true)
			draw_colored_polygon(PackedVector2Array([b, b + Vector2(-9, -5), b + Vector2(-9, 5)]), Color(0.45, 0.45, 0.45))


func setup(p_world: World) -> void:
	world = p_world
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "Research"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "✕"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(hide)
	head.add_child(close)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(LEFT + 7 * COL_W + 8, ROW_H * Tech.BRANCHES.size() + TOP * 2 + 12)
	row.add_child(scroll)
	_canvas = TreeCanvas.new()
	scroll.add_child(_canvas)
	_build_tree()

	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 300
	side.add_theme_constant_override("separation", 8)
	row.add_child(side)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	side.add_child(_title)
	_kind = _side_label(side)
	_kind.modulate = Color(1, 1, 1, 0.65)
	_desc = _side_label(side)
	_needs = _side_label(side)
	_then = _side_label(side)
	_leads = _side_label(side)
	_unlock = Button.new()
	_unlock.focus_mode = Control.FOCUS_NONE
	_unlock.custom_minimum_size.y = 40
	_unlock.pressed.connect(func() -> void: world.unlock(_selected))
	side.add_child(_unlock)
	_reason = _side_label(side)
	_reason.modulate = Color(1, 0.75, 0.6)

	world.tech_changed.connect(refresh)
	world.stock_changed.connect(func() -> void:
		if visible:
			refresh())
	select(Tech.NODES.keys()[0])


func _side_label(parent: Control) -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 300
	parent.add_child(l)
	return l


func _build_tree() -> void:
	var max_col := 0
	for id: StringName in Tech.NODES:
		max_col = maxi(max_col, Tech.node(id)["col"])
	_canvas.custom_minimum_size = Vector2(LEFT + (max_col + 1) * COL_W, TOP * 2 + Tech.BRANCHES.size() * ROW_H)
	for i in Tech.BRANCHES.size():
		var l := Label.new()
		l.text = Tech.BRANCHES[i]
		l.modulate = Color(1, 1, 1, 0.6)
		l.position = Vector2(4, TOP + i * ROW_H + NODE.y * 0.5 - 12)
		_canvas.add_child(l)
	for id: StringName in Tech.NODES:
		var b := Button.new()
		b.position = _node_pos(id)
		b.size = NODE
		b.custom_minimum_size = NODE
		b.focus_mode = Control.FOCUS_NONE
		b.clip_text = true
		b.pressed.connect(func() -> void: select(id))
		_canvas.add_child(b)
		_buttons[id] = b
		for n: StringName in Tech.node(id)["needs"]:
			_canvas.lines.append([_node_pos(n) + Vector2(NODE.x, NODE.y * 0.5), _node_pos(id) + Vector2(0, NODE.y * 0.5)])
	_canvas.queue_redraw()


func _node_pos(id: StringName) -> Vector2:
	var n := Tech.node(id)
	return Vector2(LEFT + n["col"] * COL_W, TOP + n["branch"] * ROW_H)


func _state(id: StringName) -> String:
	if world.is_unlocked(id):
		return "done"
	if Tech.is_later(id):
		return "later"
	return "ready" if world.unlock_ready(id) else "locked"


## Opens the tree on a node (e.g. from a locked build button).
func select(id: StringName) -> void:
	_selected = id
	refresh()


func refresh() -> void:
	for id: StringName in _buttons:
		var b: Button = _buttons[id]
		var state := _state(id)
		var n := Tech.node(id)
		var line2: String = {"done": "✓ unlocked", "later": "coming later", "locked": Defs.format_money(n["cost"]),
			"ready": Defs.format_money(n["cost"])}[state]
		b.text = "%s\n%s" % [n["name"], line2]
		var c: Array = COLORS[state]
		for s in ["normal", "hover", "pressed"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = (c[0] as Color).lightened(0.25) if s == "hover" else c[0]
			sb.border_color = Color(0.95, 0.75, 0.3) if id == _selected else c[1]
			sb.set_border_width_all(3 if id == _selected else (2 if state == "ready" else 1))
			sb.set_corner_radius_all(7)
			b.add_theme_stylebox_override(s, sb)
		var font := Color(0.13, 0.17, 0.1) if state != "later" and state != "locked" else Color(0.45, 0.45, 0.45)
		for s in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(s, font)
	_show_details()


func _show_details() -> void:
	var id := _selected
	var n := Tech.node(id)
	_title.text = n["name"]
	_kind.text = "%s · %s" % [Tech.KIND_NAMES[n["kind"]], Tech.BRANCHES[n["branch"]]]
	_desc.text = n["desc"]
	var needs := PackedStringArray()
	for p: StringName in n["needs"]:
		needs.append("%s %s" % ["✓" if world.is_unlocked(p) else "✗", Tech.node(p)["name"]])
	_needs.text = "Needs: " + (", ".join(needs) if not needs.is_empty() else "nothing")
	var then := PackedStringArray()
	for def_id: StringName in n.get("buildings", []):
		var mat: Dictionary = Defs.def(def_id).get("material", {})
		for res: StringName in mat:
			then.append("%s: %s" % [Defs.def(def_id)["name"], Defs.format_goods(res, mat[res])])
	var levels: Dictionary = n.get("levels", {})
	for def_id: StringName in levels:
		var lvl: int = levels[def_id]
		then.append("%s to level %d: %s" % [Defs.def(def_id)["name"], lvl, Defs.format_goods(&"planks", Defs.UPGRADE_PLANKS[lvl])])
	var head := "Upgrading then costs: " if n["kind"] == Tech.Kind.UPGRADE else "Building it then costs: "
	_then.text = head + "; ".join(then) if not then.is_empty() else ""
	_then.visible = not then.is_empty()
	var leads := Tech.leads_to(id).map(func(o: StringName) -> String: return Tech.node(o)["name"])
	_leads.text = "Leads to: " + ", ".join(leads) if not leads.is_empty() else ""
	_leads.visible = not leads.is_empty()
	var state := _state(id)
	_unlock.visible = state == "ready" or state == "locked"
	_unlock.text = "Unlock · %s" % Defs.format_money(n["cost"])
	_unlock.disabled = not world.can_unlock(id)
	_reason.text = {"done": "Unlocked", "later": "Coming later — not in the game yet"}.get(state, "")
	if state == "locked":
		_reason.text = "Unlock what it needs first"
	elif state == "ready" and world.money < int(n["cost"]):
		_reason.text = "Not enough quacks"
