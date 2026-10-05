class_name BuildDock
extends VBoxContainer
## Bottom-centre tool dock (Build, Move, Cut trees | Demolish), the horizontal build list that
## grows above it (category tabs that scroll to their tiles) and the hint pill of the active tool.
## The list hides while a tool is active and reopens on the same category after placing.

signal build_requested(def_id: StringName)
signal research_requested(node_id: StringName)

const CATEGORIES: Array[String] = ["Storage", "Processing", "Farming", "Roads", "Animals"]
const CATEGORY_ICONS := {"Storage": "house", "Processing": "flour", "Farming": "field", "Roads": "road", "Animals": "egg"}
## Research branches whose "coming later" building plans show as dashed tiles in a category.
const BRANCH_CATEGORY := {"Storage": "Storage", "Processing": "Processing", "Forestry": "Farming", "Fields": "Farming",
	"Animals": "Animals"}
## Tiles that come first in their category, in this order (the rest follow in Defs order).
const FIRST: Array[StringName] = [&"storage_barn", &"collection_point", &"shed"]
## Tile labels shorter than the building name.
const TILE_NAMES := {&"collection_point": "Collection pt."}
const TILE_SIZE := Vector2(120, 92)
const TILE_STEP := 128.0
const MODES := {&"move": ["Move", "move", "M"], &"cut": ["Cut trees", "cut", "C"], &"demolish": ["Demolish", "demolish", "X"]}

var world: World
var tool: PlacementTool
var category := "Processing"       # tab shown when the list opens
var _list: PanelContainer
var _scroll: ScrollContainer
var _tiles_row: HBoxContainer
var _tabs := {}                    # category -> Button
var _first_tile := {}              # category -> Control (scroll target)
var _tiles := {}                   # building id -> {button, cost: HBoxContainer}
var _hint: PanelContainer
var _hint_chip: PanelContainer
var _hint_chip_icon: TextureRect
var _hint_chip_label: Label
var _hint_text: RichTextLabel
var _problem: PanelContainer      # "Can't go here: …" pill under the hint
var _problem_text: RichTextLabel
var _tool_buttons := {}            # &"build" / mode -> Button
var _reopen := ""                  # category to reopen after placing from the list
var _was_active := false
var _by_scroll := false             # the arrows moved the list: the tab follows the scroll position
var _bold := RegEx.create_from_string("(\\d[\\d  .,]*\\s?(?:kg|t|g|qk|blocks?|planks?|logs?|tiles?|trees?)(?![\\w]))")
var _strong := RegEx.create_from_string("\\*\\*(.+?)\\*\\*")
var _red := RegEx.create_from_string("!!(.+?)!!")


## Category of a buildable building, derived from its data.
static func category_of(id: StringName) -> String:
	var d: Dictionary = Defs.def(id)
	if d.has("road"):
		return "Roads"
	if d.has("field"):
		return "Farming"
	if d.has("process"):
		return "Processing"
	return "Storage"


static func building_icon(id: StringName) -> String:
	var d: Dictionary = Defs.def(id)
	if d.has("road"):
		return "groad" if d["road"] == &"gravel" else "road"
	if d.has("field"):
		return "field"
	if id == &"shed":
		return "shed"
	if d.get("by_road", false):
		return "cpoint"
	return "house"


## What a tile's tooltip says about the building itself (stores: size, capacity, filter); first
## line bold.
static func building_tip(id: StringName) -> String:
	var d: Dictionary = Defs.def(id)
	if not d.has("capacity"):
		return ""
	var sz: Vector2i = d["size"]
	var lines := PackedStringArray(["%s · %d×%d" % [d["name"], sz.x, sz.y],
		"Holds %s%s" % [Defs.format_kg(d["capacity"]), " · choose which goods" if d.get("filter", false) else ""]])
	if d.get("by_road", false):
		lines.append("Must touch a road — the pickup collects it")
	return "\n".join(lines)


## A build tile whose tooltip shows its first line bold, in the kit's dark tooltip.
class TileButton extends Button:
	func _make_custom_tooltip(for_text: String) -> Object:
		return BuildDock.rich_tip(for_text)


## Tooltip body: the first line bold, the rest regular (paper on the theme's dark panel).
static func rich_tip(text: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	var lines := text.split("\n")
	for i in lines.size():
		var l := Label.new()
		l.text = lines[i]
		l.add_theme_font_override("font", UiStyle.body_font(i == 0))
		l.add_theme_font_size_override("font_size", 15 if i == 0 else 14)
		l.add_theme_color_override("font_color", UiStyle.PAPER)
		v.add_child(l)
	return v


func setup(p_world: World, p_tool: PlacementTool) -> void:
	world = p_world
	tool = p_tool
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", 10)
	_build_hint()
	_build_list()
	_build_dock()
	tool.changed.connect(_on_tool_changed)
	world.stock_changed.connect(refresh)
	world.tech_changed.connect(refresh)
	refresh()


# --- hint pill ------------------------------------------------------------------------

func _build_hint() -> void:
	_hint = PanelContainer.new()
	_hint.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_hint.add_child(row)
	_hint_chip = PanelContainer.new()
	var cs := UiStyle.box(UiStyle.SELECT_PAPER, Color.TRANSPARENT, 14)
	cs.content_margin_left = 4
	cs.content_margin_right = 10
	cs.content_margin_top = 2
	cs.content_margin_bottom = 2
	_hint_chip.add_theme_stylebox_override("panel", cs)
	row.add_child(_hint_chip)
	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override("separation", 6)
	_hint_chip.add_child(chip_row)
	_hint_chip_icon = UiStyle.icon_rect(null, 22)
	chip_row.add_child(_hint_chip_icon)
	_hint_chip_label = Label.new()
	_hint_chip_label.add_theme_font_override("font", UiStyle.head_font(600))
	_hint_chip_label.add_theme_font_size_override("font_size", 15)
	_hint_chip_label.add_theme_color_override("font_color", Color("#1F4E77"))
	chip_row.add_child(_hint_chip_label)
	_hint_text = _rich_label()
	row.add_child(_hint_text)
	_hint.hide()
	_problem = PanelContainer.new()
	_problem.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_problem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_problem.add_theme_stylebox_override("panel", _pill_box(UiStyle.WARN))
	add_child(_problem)
	_problem_text = _rich_label()
	_problem.add_child(_problem_text)
	_problem.hide()


func _rich_label() -> RichTextLabel:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.add_theme_font_override("normal_font", UiStyle.body_font())
	l.add_theme_font_override("bold_font", UiStyle.body_font(true))
	l.add_theme_font_size_override("normal_font_size", 16)
	l.add_theme_font_size_override("bold_font_size", 16)
	l.add_theme_color_override("default_color", UiStyle.INK)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Kit hint pill: paper, 2 px coloured edge, fully rounded, a soft drop.
func _pill_box(edge: Color, pad_left := 18) -> StyleBoxFlat:
	var sb := UiStyle.box(UiStyle.PAPER, edge, 22, 2)
	sb.shadow_color = Color(UiStyle.INK, 0.35)
	sb.shadow_size = 1
	sb.shadow_offset = Vector2(0, 3)
	sb.content_margin_left = pad_left
	sb.content_margin_right = 18
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	return sb


## Tool markup to BBCode: numbers with units bold, **x** bold, !!x!! red bold.
func _bbcode(text: String) -> String:
	var bb := _bold.sub(text.replace("[", "[lb]"), "[b]$1[/b]", true)
	bb = _strong.sub(bb, "[b]$1[/b]", true)
	return _red.sub(bb, "[b][color=#A23E22]$1[/color][/b]", true)


func _update_hint() -> void:
	var text := tool.hint_rich() if tool.active() else ""
	_hint.visible = text != ""
	var problem := tool.problem() if tool.active() else ""
	_problem.visible = problem != ""
	if problem != "":
		var colon := problem.find(":")
		var bb := "[b][color=#A23E22]%s[/color][/b]%s" % [problem.left(colon + 1), problem.substr(colon + 1)]
		if _problem_text.text != bb:
			_problem_text.text = bb
	if text == "":
		return
	var mode := _mode()
	var edge := UiStyle.SELECT
	if mode == &"cut":
		edge = UiStyle.GO
	elif mode == &"demolish":
		edge = Color("#B4472A")
	var chip := mode == &"" and tool.def_id != &"" and not Defs.is_road(tool.def_id)
	_hint.add_theme_stylebox_override("panel", _pill_box(edge, 8 if chip else 18))
	_hint_chip.visible = chip
	if chip:
		_hint_chip_icon.texture = UiStyle.icon(building_icon(tool.def_id))
		_hint_chip_label.text = Defs.def(tool.def_id)["name"]
	var bb := _bbcode(text)
	if _hint_text.text != bb:
		_hint_text.text = bb


# --- build list -----------------------------------------------------------------------

func _build_list() -> void:
	_list = PanelContainer.new()
	_list.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var sb := UiStyle.box(UiStyle.PAPER, UiStyle.SELECT, UiStyle.PANEL_RADIUS, 2)
	sb.shadow_color = Color(UiStyle.INK, 0.35)
	sb.shadow_size = 1
	sb.shadow_offset = Vector2(0, 4)
	sb.set_content_margin_all(0)
	_list.add_theme_stylebox_override("panel", sb)
	add_child(_list)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	_list.add_child(col)

	# tabs
	var tab_margin := MarginContainer.new()
	tab_margin.add_theme_constant_override("margin_left", 10)
	tab_margin.add_theme_constant_override("margin_right", 10)
	tab_margin.add_theme_constant_override("margin_top", 8)
	col.add_child(tab_margin)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	tab_margin.add_child(tabs)
	for cat in CATEGORIES:
		var b := Button.new()
		b.text = cat
		b.icon = UiStyle.icon(CATEGORY_ICONS[cat])
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 15)
		b.add_theme_constant_override("icon_max_width", 20)
		b.add_theme_constant_override("h_separation", 6)
		b.pressed.connect(func() -> void: show_category(cat))
		tabs.add_child(b)
		_tabs[cat] = b
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(spacer)
	var collapse := Button.new()
	collapse.text = "Collapse"
	collapse.focus_mode = Control.FOCUS_NONE
	collapse.add_theme_font_size_override("font_size", 14)
	collapse.pressed.connect(func() -> void: _list.hide())
	Hud.paint_button(collapse, Color.TRANSPARENT, Color.TRANSPARENT, UiStyle.INK_SOFT, UiStyle.PAPER_DEEP, 8, 30)
	tabs.add_child(collapse)
	var cap := UiStyle.key_cap("B")
	collapse.add_child(cap)
	cap.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT, Control.PRESET_MODE_MINSIZE, 6)
	var line := ColorRect.new()
	line.color = Color("#E8DAC0")
	line.custom_minimum_size.y = 2
	col.add_child(line)

	# tiles: ‹ [scrolling row] ›
	var tm := MarginContainer.new()
	tm.add_theme_constant_override("margin_left", 8)
	tm.add_theme_constant_override("margin_right", 8)
	tm.add_theme_constant_override("margin_top", 10)
	tm.add_theme_constant_override("margin_bottom", 12)
	col.add_child(tm)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	tm.add_child(row)
	row.add_child(_arrow("‹", -1))
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size = Vector2(TILE_STEP * 7.5, TILE_SIZE.y + 4)
	_scroll.get_h_scroll_bar().value_changed.connect(func(_v: float) -> void: _update_tabs())
	row.add_child(_scroll)
	row.add_child(_arrow("›", 1))
	_tiles_row = HBoxContainer.new()
	_tiles_row.add_theme_constant_override("separation", 8)
	_scroll.add_child(_tiles_row)
	var ids: Array[StringName] = FIRST.duplicate()
	for id: StringName in Defs.BUILDINGS:
		if not ids.has(id):
			ids.append(id)
	for cat in CATEGORIES:
		var first := true
		for id: StringName in ids:
			if Defs.def(id)["buildable"] and category_of(id) == cat:
				_add_divider(first)
				first = false
				_add_tile(id, cat)
		if cat == "Storage":
			_add_divider(false)
			_add_road_piles_hint()
		for node: StringName in Tech.NODES:
			var n: Dictionary = Tech.node(node)
			var branch: String = Tech.BRANCHES[n["branch"]]
			if n["kind"] == Tech.Kind.PLAN and Tech.is_later(node) and BRANCH_CATEGORY.get(branch, "") == cat:
				_add_divider(first)
				first = false
				_add_later_tile(node, cat)
	_list.hide()


func _add_divider(first: bool) -> void:
	if not first or _tiles_row.get_child_count() == 0:
		return
	var d := ColorRect.new()
	d.color = Color("#E8DAC0")
	d.custom_minimum_size = Vector2(2, TILE_SIZE.y - 12)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_tiles_row.add_child(d)


func _arrow(text: String, dir: int) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(32, TILE_SIZE.y)
	b.add_theme_font_size_override("font_size", 22)
	Hud.paint_button(b, UiStyle.PAPER_DEEP, Color.TRANSPARENT, UiStyle.INK, Color("#EADCC1"), 8, 0)
	b.pressed.connect(func() -> void:
		_by_scroll = true
		var tw := create_tween()
		tw.tween_property(_scroll, "scroll_horizontal", _scroll.scroll_horizontal + int(dir * TILE_STEP * 3), 0.2))
	return b


## Dashed "Road piles appear on their own — not built" tile at the end of Storage (not a button).
func _add_road_piles_hint() -> void:
	var p := PanelContainer.new()
	var sb := UiStyle.box(Color.TRANSPARENT, Color.TRANSPARENT, UiStyle.RADIUS, 0)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(200, TILE_SIZE.y)
	p.tooltip_text = "The planner makes road piles by itself where goods wait for the pickup"
	p.draw.connect(func() -> void:
		ResearchPanel.dashed_polyline(p, ResearchPanel.round_rect_points(Rect2(Vector2.ZERO, p.size).grow(-1), UiStyle.RADIUS - 1),
			UiStyle.LOCKED_EDGE, 2.0, 5.0, 4.0))
	p.resized.connect(p.queue_redraw)
	_tiles_row.add_child(p)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var ic := UiStyle.icon_rect(UiStyle.icon("pile"), 28)
	ic.modulate.a = 0.8
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(v)
	var title := Label.new()
	title.text = "Road piles"
	title.add_theme_font_override("font", UiStyle.head_font(600))
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color("#5E5244"))
	v.add_child(title)
	var note := _cost_label("appear on their own —\nnot built", false, UiStyle.INK_SOFT, 13)
	v.add_child(note)


func _tile_button(cat: String) -> Button:
	var b := TileButton.new()
	b.custom_minimum_size = TILE_SIZE
	b.focus_mode = Control.FOCUS_NONE
	_tiles_row.add_child(b)
	if not _first_tile.has(cat):
		_first_tile[cat] = b
	return b


func _tile_content(b: Button, icon_name: String, name: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 3)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ic := UiStyle.icon_rect(UiStyle.icon(icon_name), 34)
	ic.name = "Icon"
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var l := Label.new()
	l.name = "Name"
	l.text = name
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", UiStyle.head_font(600))
	l.add_theme_font_size_override("font_size", 15)
	v.add_child(l)
	return v


func _add_tile(id: StringName, cat: String) -> void:
	var b := _tile_button(cat)
	var v := _tile_content(b, building_icon(id), TILE_NAMES.get(id, Defs.def(id)["name"]))
	var cost := HBoxContainer.new()
	cost.alignment = BoxContainer.ALIGNMENT_CENTER
	cost.add_theme_constant_override("separation", 3)
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(cost)
	b.pressed.connect(func() -> void:
		if world.building_unlocked(id):
			_reopen = cat
			category = cat
			_list.hide()
		build_requested.emit(id))
	_tiles[id] = {"button": b, "cost": cost, "vbox": v}


func _add_later_tile(node: StringName, cat: String) -> void:
	var b := _tile_button(cat)
	var v := _tile_content(b, "house", Tech.node(node)["name"])
	(v.get_node("Icon") as CanvasItem).modulate.a = 0.35
	(v.get_node("Name") as Label).add_theme_color_override("font_color", Color("#6E665B"))
	var l := Label.new()
	l.text = "later"
	l.theme_type_variation = "SmallLabel"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color("#6E665B"))
	v.add_child(l)
	b.tooltip_text = "%s · coming later" % Tech.node(node)["name"]
	_paint_tile(b, Color("#F4EFE5"), Color("#CFC7B8"), false)
	b.pressed.connect(func() -> void: research_requested.emit(node))


func _paint_tile(b: Button, fill: Color, edge: Color, drop: bool, hover := Color.TRANSPARENT) -> void:
	var h := hover if hover.a > 0.0 else fill
	for s in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var f := h if s != "normal" and s != "disabled" else fill
		var sb := UiStyle.box(f, edge, UiStyle.RADIUS, 2, 3 if drop and s != "pressed" else 0)
		b.add_theme_stylebox_override(s, sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


## Tile looks: unlocked (cost, red when short), locked (greyed, "Research"), selected while placing.
func _refresh_tiles() -> void:
	for id: StringName in _tiles:
		var t: Dictionary = _tiles[id]
		var b: Button = t["button"]
		var v: VBoxContainer = t["vbox"]
		var cost: HBoxContainer = t["cost"]
		var open := world.building_unlocked(id)
		var key := "%s|%s" % [open, _cost_key(id)]
		if b.get_meta("key", "") == key:
			continue
		b.set_meta("key", key)
		for c in cost.get_children():
			cost.remove_child(c)
			c.queue_free()
		(v.get_node("Icon") as CanvasItem).modulate.a = 1.0 if open else 0.45
		(v.get_node("Name") as Label).add_theme_color_override("font_color", UiStyle.INK if open else Color("#5E5244"))
		if not open:
			_paint_tile(b, UiStyle.LOCKED, UiStyle.LOCKED_EDGE, false, Color("#E6E0D3"))
			cost.add_child(UiStyle.icon_rect(UiStyle.icon("locked"), 14))
			cost.add_child(_cost_label("Research", false, UiStyle.INK_SOFT, 13))
			var info := building_tip(id)
			b.tooltip_text = (info + "\nUnlock it in the research tree") if info != "" \
				else "%s · unlock it in the research tree" % Defs.def(id)["name"]
			continue
		_paint_tile(b, UiStyle.PAPER, UiStyle.BOARD, true, Color("#F6EBD3"))
		b.tooltip_text = building_tip(id)
		var d: Dictionary = Defs.def(id)
		var mat: Dictionary = d.get("material", {})
		if d.has("field"):
			cost.add_child(_cost_label(str(Defs.FIELD_COST_PER_TILE), true, UiStyle.INK))
			cost.add_child(UiStyle.icon_rect(UiStyle.icon("qk"), 16))
			cost.add_child(_cost_label("/tile", false, UiStyle.INK_SOFT))
		elif d["cost"] > 0:
			cost.add_child(_cost_label(UiStyle.money_number(d["cost"]), true, UiStyle.SHORT if world.money < d["cost"] else UiStyle.INK))
			cost.add_child(UiStyle.icon_rect(UiStyle.icon("qk"), 16))
		for res: StringName in mat:
			var short: bool = world.total(res) < mat[res]
			var amount := Defs.format_amount(res, mat[res])
			cost.add_child(_cost_label(amount.get_slice(" ", 0) if Defs.is_piece(res) else amount, true, UiStyle.SHORT if short else UiStyle.INK))
			cost.add_child(UiStyle.icon_rect(UiStyle.resource_icon(res), 16))
			if short:
				var line := "%s in the barn: %s" % [Defs.resource_name(res), Defs.format_amount(res, world.total(res))]
				b.tooltip_text = line if b.tooltip_text == "" else b.tooltip_text + "\n" + line
		if cost.get_child_count() == 0:
			cost.add_child(_cost_label("free", false, UiStyle.INK_SOFT))


func _cost_key(id: StringName) -> String:
	var key := ""
	for res: StringName in Defs.def(id).get("material", {}):
		key += "%s" % (world.total(res) < Defs.def(id)["material"][res])
	return key


func _cost_label(text: String, bold: bool, color: Color, size := 14) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiStyle.body_font(bold))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Opens the list scrolled to a category.
func show_category(cat: String) -> void:
	category = cat
	if tool.active():
		tool.cancel()
	_by_scroll = false
	_list.show()
	refresh()
	_update_tabs()
	if _first_tile.has(cat):
		await get_tree().process_frame       # tiles laid out
		var c: Control = _first_tile[cat]
		var tw := create_tween()
		tw.tween_property(_scroll, "scroll_horizontal", int(maxf(0.0, c.position.x - 4.0)), 0.18)


func _update_tabs() -> void:
	# the tab of the category whose tiles are at the left edge of the list
	var at := float(_scroll.scroll_horizontal) + 20.0
	var current := CATEGORIES[0]
	for cat in CATEGORIES:
		if _first_tile.has(cat) and (_first_tile[cat] as Control).position.x <= at:
			current = cat
	if not _by_scroll:
		current = category
	for cat in CATEGORIES:
		var b: Button = _tabs[cat]
		var sel := cat == current
		var fill := UiStyle.SELECT_PAPER if sel else Color.TRANSPARENT
		var sb := UiStyle.box(fill, Color.TRANSPARENT, 8)
		sb.corner_radius_bottom_left = 0
		sb.corner_radius_bottom_right = 0
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		if sel:
			sb.border_color = UiStyle.SELECT
			sb.border_width_bottom = 3
		var hv := sb.duplicate() as StyleBoxFlat
		if not sel:
			hv.bg_color = UiStyle.PAPER_DEEP
		for s in ["normal", "pressed", "disabled"]:
			b.add_theme_stylebox_override(s, sb)
		b.add_theme_stylebox_override("hover", hv)
		b.add_theme_stylebox_override("hover_pressed", hv)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var only_later := true
		for id: StringName in _tiles:
			if category_of(id) == cat:
				only_later = false
		var col := Color("#1F4E77") if sel else (Color("#8A8172") if only_later else UiStyle.INK_SOFT)
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(c, col)
		b.add_theme_color_override("icon_normal_color", Color(1, 1, 1, 0.45 if only_later and not sel else 1.0))


func list_open() -> bool:
	return _list.visible


func toggle_list() -> void:
	if tool.active():
		_reopen = ""
		show_category(category)
	elif _list.visible:
		_list.hide()
		refresh()
	else:
		show_category(category)


func close_list() -> void:
	_list.hide()
	refresh()


# --- dock ---------------------------------------------------------------------------

func _build_dock() -> void:
	var dock := PanelContainer.new()
	dock.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var sb := UiStyle.box(UiStyle.PAPER, UiStyle.WOOD, UiStyle.PANEL_RADIUS, 2)
	sb.shadow_color = Color(UiStyle.INK, 0.35)
	sb.shadow_size = 1
	sb.shadow_offset = Vector2(0, 4)
	sb.set_content_margin_all(6)
	dock.add_theme_stylebox_override("panel", sb)
	add_child(dock)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	dock.add_child(row)
	_tool_buttons[&"build"] = _tool_button(row, "Build", "build", "B", toggle_list)
	for mode: StringName in MODES:
		if mode == &"demolish":
			var d := ColorRect.new()
			d.color = Color("#E8DAC0")
			d.custom_minimum_size = Vector2(2, 32)
			d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(d)
		var m: Array = MODES[mode]
		_tool_buttons[mode] = _tool_button(row, m[0], m[1], m[2], func() -> void: press_mode(mode))


func _tool_button(row: HBoxContainer, text: String, icon_name: String, key: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.icon = UiStyle.icon(icon_name)
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = 48
	b.add_theme_constant_override("icon_max_width", 30)
	b.pressed.connect(on_pressed)
	row.add_child(b)
	var cap := UiStyle.key_cap(key)
	cap.name = "Key"
	b.add_child(cap)
	cap.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT, Control.PRESET_MODE_MINSIZE, 10)
	return b


## Move / Cut trees / Demolish: starts the tool mode, or ends it when it is the active one.
func press_mode(mode: StringName) -> void:
	if not tool.has_method("start_mode"):
		return
	_reopen = ""
	if _mode() == mode and tool.active():
		tool.cancel()
	else:
		_list.hide()
		tool.call("start_mode", mode)
	refresh()


func _mode() -> StringName:
	var m: Variant = tool.get("mode")
	return m if m is StringName else &""


func _paint_tools() -> void:
	var modes_ok := tool.has_method("start_mode")
	var mode := _mode() if tool.active() else &"-"
	for k: StringName in _tool_buttons:
		var b: Button = _tool_buttons[k]
		var danger := k == &"demolish"
		var on := (k == &"build" and (_list.visible or mode == &"")) or k == mode
		var fill := Color.TRANSPARENT
		var edge := Color.TRANSPARENT
		var text := UiStyle.SHORT if danger else UiStyle.INK
		var cap_edge := Color("#B4472A") if danger else UiStyle.WOOD
		if on:
			match k:
				&"cut":
					fill = UiStyle.DONE
					edge = UiStyle.GO
					text = Color("#2F4F22")
				&"demolish":
					fill = Color("#FCE7DE")
					edge = Color("#B4472A")
				_:
					fill = UiStyle.SELECT_PAPER
					edge = UiStyle.SELECT
					text = Color("#1F4E77")
			cap_edge = edge
		var key := "%s%s" % [on, modes_ok]
		if b.get_meta("key", "") == key:
			continue
		b.set_meta("key", key)
		Hud.paint_button(b, fill, edge, text, fill if on else (Color("#FCE7DE") if danger else UiStyle.PAPER_DEEP), 10, 42)
		var cap: Label = b.get_node("Key")
		var csb := UiStyle.box(UiStyle.PAPER if on else UiStyle.PAPER_DEEP, cap_edge, 5, 1)
		csb.content_margin_left = 6
		csb.content_margin_right = 6
		csb.content_margin_top = 0
		csb.content_margin_bottom = 0
		cap.add_theme_stylebox_override("normal", csb)
		if k != &"build":
			b.disabled = not modes_ok
			b.tooltip_text = "" if modes_ok else "Coming soon"
			b.modulate.a = 1.0 if modes_ok else 0.5


# --- updates ------------------------------------------------------------------------

func _on_tool_changed() -> void:
	var active := tool.active()
	if active:
		_list.hide()
	elif _was_active and _reopen != "":
		var cat := _reopen
		_reopen = ""
		show_category(cat)
	_was_active = active
	refresh()


func refresh() -> void:
	if world == null:
		return
	_update_hint()
	_paint_tools()
	if _list.visible:
		_refresh_tiles()
