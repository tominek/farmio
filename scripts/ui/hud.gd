class_name Hud
extends CanvasLayer
## Main-view chrome: the top bar (quacks and stock chips, workers, tasks chip, speed, panel toggles,
## menu), warning cards under it, the tool dock with the build list and the hint pill (BuildDock),
## the crop picker floating over a field being drawn, toasts, and the panels it opens.

signal build_requested(def_id: StringName)
signal speed_requested(speed: float)
signal save_requested
signal load_requested
signal menu_requested
signal focus_requested(cell: Vector2i)        # move the camera to a cell (Tasks "Show")
signal follow_requested(t: Variant)           # keep a worker or a vehicle centred (null stops following)

const BAR_H := 60.0
const MARGIN := 12.0
const BELOW_BAR := 86.0           # y of the warnings and the left-docked panels
const MONEY_FILL := Color("#FBEFC9")
const MONEY_EDGE := Color("#E2C27A")
const DIVIDER := Color("#E8DAC0")
const TIP_WARN := Color("#F5A27C")    # warnings on the dark tooltip

var world: World
var tool: PlacementTool
var dealer_panel: DealerPanel
var dev_menu: DevMenu
var info: InfoStack
var priorities: PriorityPanel
var research: ResearchPanel
var tasks: TasksPanel
var dock: BuildDock

var _money: Label
var _chips_row: HBoxContainer
var _chips := {}                  # resource (or &"seeds") -> {panel, label}
var _chip_keys := ""
var _idle_n: Label
var _idle_rest: Label
var _tasks_btn: Button
var _speed := 1.0
var _speed_buttons := {}          # speed -> Button
var _toggles := {}                # "dealer" / "priorities" / "research" -> Button
var _warnings: VBoxContainer
var _warning_text := ""
var _dismissed := {}              # heads of warning lines hidden with their ×
var _following: Variant = null     # a Worker or a Vehicle
var _float: PanelContainer        # crop icons floating above the field being drawn
var _float_icons := {}
var _float_info: Label
var _accum := 0.0
var _toast: PanelContainer
var _toast_label: RichTextLabel
var _toast_mark: Control
var _toast_action: Button
var _toast_callback := Callable()
var _toast_kind := "info"
var _toast_time := 0.0
var _bold := RegEx.create_from_string("(\\d[\\d  .,]*\\s?(?:kg|t|g|qk|planks?|logs?|tasks?)(?![\\w]))")


## Styles a button by hand (all states): fill and edge, text colour, hover fill; `pad_right` leaves
## room for a key cap. Used by the HUD toggles, the dock tools and the tasks rows.
static func paint_button(b: Button, fill: Color, edge: Color, text: Color, hover: Color, radius := 10, pad_right := 10, border := 2, drop := 0) -> void:
	for s in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var f := fill if s == "normal" or s == "disabled" else hover
		var sb := UiStyle.box(f, edge, radius, border, drop)
		sb.content_margin_left = 8
		sb.content_margin_right = pad_right
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		b.add_theme_stylebox_override(s, sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
		b.add_theme_color_override(c, text)


func setup(p_world: World, p_tool: PlacementTool) -> void:
	world = p_world
	tool = p_tool
	add_to_group("debug_show")
	_build_top()

	_warnings = VBoxContainer.new()
	_warnings.position = Vector2(MARGIN, BELOW_BAR)
	_warnings.custom_minimum_size.x = 640
	_warnings.add_theme_constant_override("separation", 8)
	_warnings.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_warnings)

	dock = BuildDock.new()
	add_child(dock)
	dock.setup(world, tool)
	get_viewport().size_changed.connect(_layout)   # also while the game (and this node) is paused
	_layout.call_deferred()
	dock.build_requested.connect(_on_build_pressed)
	dock.research_requested.connect(show_research)
	_build_float()
	_build_toast()

	dealer_panel = DealerPanel.new()
	add_child(dealer_panel)
	dealer_panel.setup(world)
	dealer_panel.hide()

	dev_menu = DevMenu.new()
	add_child(dev_menu)
	dev_menu.setup(world)
	dev_menu.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	dev_menu.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	dev_menu.position += Vector2(-MARGIN, BELOW_BAR)
	dev_menu.speed_requested.connect(func(s: float) -> void: speed_requested.emit(s))
	dev_menu.hide()

	priorities = PriorityPanel.new()
	add_child(priorities)
	priorities.setup(world)
	priorities.hide()

	research = ResearchPanel.new()
	add_child(research)
	research.setup(world)
	research.hide()

	tasks = TasksPanel.new()
	add_child(tasks)
	tasks.setup(world)
	tasks.position = Vector2(MARGIN, BELOW_BAR)
	tasks.dealer_requested.connect(_open_dealer)
	tasks.research_requested.connect(show_research)
	tasks.priorities_requested.connect(_open_priorities)
	tasks.focus_requested.connect(func(c: Vector2i) -> void: focus_requested.emit(c))
	tasks.worker_selected.connect(func(w: Worker) -> void: info.select(w))
	tasks.visibility_changed.connect(_refresh)

	# the info panels sit under the other panels and the dock
	info = InfoStack.new()
	add_child(info)
	move_child(info, 0)
	info.setup(world)
	info.follow_requested.connect(func(t: Variant) -> void:
		_following = t
		follow_requested.emit(t))
	info.priorities_requested.connect(_open_priorities)
	info.research_requested.connect(show_research)
	info.dealer_requested.connect(func() -> void: _open_dealer(&"", &""))
	info.gate_requested.connect(func(f: Field) -> void:
		dock.close_list()
		tool.start_gate(f))
	info.selection_changed.connect(func() -> void:
		if _following and not info.has_target(_following.garage if _following is Vehicle else _following):
			_following = null
			follow_requested.emit(null))

	for p: Control in [dealer_panel, priorities, research]:
		p.visibility_changed.connect(_refresh)
	tool.changed.connect(_refresh)
	world.stock_changed.connect(_refresh)
	_refresh()


# --- top bar ------------------------------------------------------------------------

func _build_top() -> void:
	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = MARGIN
	top.offset_right = -MARGIN
	top.offset_top = MARGIN
	top.custom_minimum_size.y = BAR_H
	var sb := UiStyle.box(UiStyle.PAPER, UiStyle.WOOD, UiStyle.PANEL_RADIUS, 2)
	sb.shadow_color = Color(UiStyle.INK, 0.35)
	sb.shadow_size = 1
	sb.shadow_offset = Vector2(0, 4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	top.add_theme_stylebox_override("panel", sb)
	add_child(top)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	top.add_child(bar)

	# quacks, then a chip per good the farm has or needs
	var money := _chip(MONEY_FILL, MONEY_EDGE, 1)
	money.tooltip_text = "Quacks"
	bar.add_child(money)
	var mrow := money.get_child(0) as HBoxContainer
	mrow.add_child(UiStyle.icon_rect(UiStyle.icon("qk"), 28))
	_money = _number(21)
	mrow.add_child(_money)
	_chips_row = HBoxContainer.new()
	_chips_row.add_theme_constant_override("separation", 6)
	bar.add_child(_chips_row)
	bar.add_child(_spacer())

	# workers, tasks
	var workers := _chip(UiStyle.PAPER_DEEP, Color.TRANSPARENT, 0)
	workers.tooltip_text = "Idle workers / all workers"
	bar.add_child(workers)
	var wrow := workers.get_child(0) as HBoxContainer
	wrow.add_theme_constant_override("separation", 8)
	wrow.add_child(UiStyle.icon_rect(UiStyle.icon("worker"), 26))
	_idle_n = _number(18)
	wrow.add_child(_idle_n)
	_idle_rest = Label.new()
	_idle_rest.theme_type_variation = "SoftLabel"
	wrow.add_child(_idle_rest)
	# "(12) tasks waiting": a dark count pill and plain text
	_tasks_btn = _face_button("tasks waiting", "", "", 42)
	_tasks_btn.tooltip_text = "Tasks: what the workers do and what is stuck"
	_tasks_btn.pressed.connect(toggle_tasks)
	var text: Label = _tasks_btn.get_node("Face/Text")
	text.add_theme_font_override("font", UiStyle.body_font())
	var count := Label.new()
	count.name = "Count"
	count.add_theme_font_override("font", UiStyle.body_font(true))
	count.add_theme_font_size_override("font_size", 15)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count.custom_minimum_size = Vector2(28, 26)
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var face: HBoxContainer = _tasks_btn.get_node("Face")
	face.add_child(count)
	face.move_child(count, 0)
	bar.add_child(_tasks_btn)

	# speed: pause, 1×, 2×, 3× (the current one green)
	var seg := PanelContainer.new()
	var ssb := UiStyle.box(UiStyle.PAPER_DEEP, UiStyle.BOARD, UiStyle.RADIUS, 1)
	ssb.set_content_margin_all(3)
	seg.add_theme_stylebox_override("panel", ssb)
	seg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(seg)
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 3)
	seg.add_child(srow)
	for s in [[0.0, "❚❚", "Pause (Space)"], [1.0, "1×", "Normal speed (1)"], [2.0, "2×", "Fast (2)"], [3.0, "3×", "Fastest (3)"]]:
		var b := Button.new()
		b.text = s[1]
		b.tooltip_text = s[2]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(40, 32)
		b.pressed.connect(func() -> void: speed_requested.emit(s[0]))
		srow.add_child(b)
		_speed_buttons[s[0]] = b
	bar.add_child(_spacer())

	# panel toggles, menu
	for t in [["dealer", "Dealer", "qk", "", toggle_dealer], ["priorities", "Priorities", "", "P", toggle_priorities],
			["research", "Research", "", "T", toggle_research]]:
		var b := _face_button(t[1], t[2], t[3])
		b.pressed.connect(t[4])
		bar.add_child(b)
		_toggles[t[0]] = b
	var div := ColorRect.new()
	div.color = DIVIDER
	div.custom_minimum_size = Vector2(2, 32)
	div.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(div)
	# menu: the same paper button, three bars instead of a label
	var menu := Button.new()
	menu.tooltip_text = "Menu (Esc)"
	menu.focus_mode = Control.FOCUS_NONE
	menu.custom_minimum_size = Vector2(44, 40)
	menu.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	paint_button(menu, UiStyle.PAPER, UiStyle.WOOD, UiStyle.INK, Color("#F6EBD3"), 10, 0, 2, 3)
	var lines := Control.new()
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lines.draw.connect(func() -> void:
		var y0 := floorf((menu.size.y - 3.0 - 17.0) * 0.5)
		for i in 3:
			lines.draw_style_box(UiStyle.box(UiStyle.INK, Color.TRANSPARENT, 2), Rect2((menu.size.x - 20.0) * 0.5, y0 + i * 7.0, 20, 3)))
	menu.add_child(lines)
	menu.pressed.connect(func() -> void: menu_requested.emit())
	bar.add_child(menu)


## A bar button laid out like the kit: [icon] text [key cap], centred on the face above the drop
## shadow. The row is a child ("Face"); _layout sizes the button to it.
func _face_button(text: String, icon_name: String, key: String, height := 40) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = height
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var face := HBoxContainer.new()
	face.name = "Face"
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_theme_constant_override("separation", 8)
	b.add_child(face)
	if icon_name != "":
		var ic := UiStyle.icon_rect(UiStyle.icon(icon_name), 20)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		face.add_child(ic)
	var l := Label.new()
	l.name = "Text"
	l.text = text
	l.add_theme_font_override("font", UiStyle.head_font(600))
	l.add_theme_font_size_override("font_size", 16)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	face.add_child(l)
	if key != "":
		var cap := UiStyle.key_cap(key)
		cap.name = "Key"
		cap.custom_minimum_size = Vector2(22, 22)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		face.add_child(cap)
	return b


## A stock chip: hovering splits the good by place (17b), built only when the tooltip shows.
class StockChip extends PanelContainer:
	var hud: Hud
	var key: StringName

	func _make_custom_tooltip(_for_text: String) -> Object:
		return hud.stock_tip(key)


func _chip(fill: Color, edge: Color, border: int, p: PanelContainer = null) -> PanelContainer:
	if p == null:
		p = PanelContainer.new()
	var sb := UiStyle.box(fill, edge, UiStyle.RADIUS, border)
	sb.content_margin_left = 8
	sb.content_margin_right = 12
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size.y = 42
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	p.add_child(row)
	return p


func _number(size: int) -> Label:
	var l := Label.new()
	l.theme_type_variation = "NumberLabel"
	l.add_theme_font_size_override("font_size", size)
	return l


func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Goods shown as chips: whatever is in the barn or short for a waiting task, in stock order;
## seeds are summed up in one chip.
func _chip_resources(short: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	var totals := world.totals()
	for res: StringName in totals:
		var key := &"seeds" if String(res).begins_with("seed_") else res
		if out.has(key):
			continue
		if totals[res] > 0.0005 or short.has(res):
			out.append(key)
	return out


func _refresh_chips() -> void:
	var short := world.seed_shortage()
	var keys := _chip_resources(short)
	var sig := str(keys)
	if sig != _chip_keys:
		_chip_keys = sig
		for c in _chips_row.get_children():
			_chips_row.remove_child(c)
			c.queue_free()
		_chips.clear()
		for key in keys:
			var sc := StockChip.new()
			sc.hud = self
			sc.key = key
			var p := _chip(Color.TRANSPARENT, Color.TRANSPARENT, 0, sc)
			p.mouse_filter = Control.MOUSE_FILTER_STOP
			var row := p.get_child(0) as HBoxContainer
			row.add_child(UiStyle.icon_rect(UiStyle.resource_icon(key), 24))
			var l := _number(18)
			row.add_child(l)
			var unit := Label.new()
			unit.add_theme_font_size_override("font_size", 14)
			unit.add_theme_color_override("font_color", UiStyle.INK_SOFT)
			row.add_child(unit)
			_chips_row.add_child(p)
			_chips[key] = {"panel": p, "label": l, "unit": unit, "short": null}
	for key: StringName in _chips:
		var c: Dictionary = _chips[key]
		var amount := 0.0
		var is_short := false
		var tip := PackedStringArray()
		if key == &"seeds":
			for res: StringName in world.GOODS:
				var have := world.total(res)
				if String(res).begins_with("seed_") and (have > 0.0005 or short.has(res)):
					amount += have
					is_short = is_short or short.has(res)
					tip.append("%s: %s%s" % [Defs.resource_name(res), Defs.format_kg(have),
						" (short by %s)" % Defs.format_kg(short[res]) if short.has(res) else ""])
		else:
			amount = world.total(key)
			is_short = short.has(key)
			tip.append("%s: %s%s" % [Defs.resource_name(key), Defs.format_amount(key, amount),
				" (short by %s)" % Defs.format_amount(key, short[key]) if is_short else ""])
		# the number in bold, the unit ("kg", "t") small and soft
		var text := str(int(amount)) if Defs.is_piece(key) else Defs.format_kg(amount)
		var cut := text.rfind(" ") if not Defs.is_piece(key) else -1
		(c["label"] as Label).text = text.substr(0, cut) if cut > 0 else text
		(c["unit"] as Label).text = text.substr(cut + 1) if cut > 0 else ""
		(c["unit"] as Label).visible = cut > 0
		(c["panel"] as Control).tooltip_text = "\n".join(tip)
		if c["short"] != is_short:
			c["short"] = is_short
			var sb := UiStyle.box(UiStyle.WARN_PAPER if is_short else Color.TRANSPARENT, Color("#F0B395") if is_short else Color.TRANSPARENT, UiStyle.RADIUS, 1)
			sb.content_margin_left = 10
			sb.content_margin_right = 10
			sb.content_margin_top = 0
			sb.content_margin_bottom = 0
			(c["panel"] as PanelContainer).add_theme_stylebox_override("panel", sb)
			(c["label"] as Label).add_theme_color_override("font_color", UiStyle.SHORT if is_short else UiStyle.INK)


## The stock chip's tooltip (17b): "{Good} · {total}", then one row per place (barns and Sheds by
## name, goods not stored; collection points and road piles soft, as on the way and not in the
## total; greyed at 0), then what is short. The seeds chip lists each seed instead.
func stock_tip(key: StringName) -> Control:
	var short := world.seed_shortage()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 5)
	var notes := PackedStringArray()
	var total := 0.0
	if key == &"seeds":
		for res: StringName in world.GOODS:
			var have := world.total(res)
			if String(res).begins_with("seed_") and (have > 0.0005 or short.has(res)):
				total += have
				_tip_row(grid, UiStyle.resource_icon(res), Defs.resource_name(res), _tip_amount(res, have), have > 0.0005, true)
				if short.has(res):
					notes.append("%s: sowing needs %s more" % [Defs.resource_name(res), Defs.format_kg(short[res])])
	else:
		total = world.total(key)
		var on_way := false
		for p: Dictionary in world.stock_places(key):
			if not p["counted"] and not on_way:
				# collection points and road piles: goods on their way to a store, not in the total
				on_way = true
				grid.add_child(Control.new())
				var sub := Label.new()
				sub.text = "On the way"
				sub.add_theme_font_size_override("font_size", 12)
				sub.add_theme_color_override("font_color", Color(UiStyle.PAPER, 0.55))
				grid.add_child(sub)
				grid.add_child(Control.new())
			var icon: String = {&"barn": "house", &"shed": "shed", &"collect": "cpoint", &"road": "pile"}.get(p["kind"], "pile")
			_tip_row(grid, UiStyle.icon(icon), p["name"], _tip_amount(key, p["amount"]), p["amount"] > 0.0005, p["counted"])
		if short.has(key):
			notes.append("Construction needs %s more" % _tip_amount(key, short[key]))
	var title := Label.new()
	title.text = "%s · %s" % ["Seeds" if key == &"seeds" else Defs.resource_name(key), _tip_amount(key, total)]
	title.add_theme_font_override("font", UiStyle.body_font(true))
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", UiStyle.PAPER)
	v.add_child(title)
	v.add_child(grid)
	if not notes.is_empty():
		var line := ColorRect.new()
		line.color = Color(UiStyle.PAPER, 0.18)
		line.custom_minimum_size.y = 1
		v.add_child(line)
		for n in notes:
			var l := Label.new()
			l.text = n
			l.add_theme_font_size_override("font_size", 14)
			l.add_theme_color_override("font_color", TIP_WARN)
			v.add_child(l)
	return v


func _tip_row(grid: GridContainer, icon: Texture2D, text: String, amount: String, any: bool, counted: bool) -> void:
	var alpha := (1.0 if counted else 0.7) * (1.0 if any else 0.55)
	var ic := UiStyle.icon_rect(icon, 16)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.modulate.a = alpha
	grid.add_child(ic)
	var l := Label.new()
	l.text = text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(UiStyle.PAPER, alpha))
	grid.add_child(l)
	var a := Label.new()
	a.text = amount
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	a.custom_minimum_size.x = 56
	a.add_theme_font_override("font", UiStyle.body_font(true))
	a.add_theme_font_size_override("font_size", 14)
	a.add_theme_color_override("font_color", Color(UiStyle.PAPER, alpha))
	grid.add_child(a)


func _tip_amount(res: StringName, n: float) -> String:
	return str(int(round(n))) if Defs.is_piece(res) else Defs.format_kg(n)


func set_speed_text(text: String) -> void:
	_speed = 0.0 if text == "Paused" else text.to_float()
	_paint_speed()


func _paint_speed() -> void:
	for s: float in _speed_buttons:
		var b: Button = _speed_buttons[s]
		if is_equal_approx(s, _speed):
			paint_button(b, UiStyle.GO, Color.TRANSPARENT, UiStyle.PAPER, UiStyle.GO, 7, 8)
		else:
			paint_button(b, Color.TRANSPARENT, Color.TRANSPARENT, UiStyle.INK_SOFT, Color(UiStyle.PAPER, 0.7), 7, 8)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER


func _paint_toggles() -> void:
	var open := {"dealer": dealer_panel.visible, "priorities": priorities.visible, "research": research.visible}
	for k: String in _toggles:
		var b: Button = _toggles[k]
		var on: bool = open[k]
		if str(b.get_meta("on", "")) == str(on):
			continue
		b.set_meta("on", on)
		if on:
			# open: blue, pressed onto its shadow
			paint_button(b, UiStyle.SELECT_PAPER, UiStyle.SELECT, Color("#1F4E77"), UiStyle.SELECT_PAPER, 10, 10, 2, 1)
		else:
			# the kit's panel buttons: paper with a timber edge and a hard drop shadow
			paint_button(b, UiStyle.PAPER, UiStyle.WOOD, UiStyle.INK, Color("#F6EBD3"), 10, 10, 2, 3)
		(b.get_node("Face/Text") as Label).add_theme_color_override("font_color", Color("#1F4E77") if on else UiStyle.INK)
		if b.has_node("Face/Key"):
			var cap: Label = b.get_node("Face/Key")
			var csb := UiStyle.box(UiStyle.PAPER if on else UiStyle.PAPER_DEEP, UiStyle.SELECT if on else UiStyle.WOOD, 5, 1)
			csb.set_content_margin_all(0)
			cap.add_theme_stylebox_override("normal", csb)
	var t_on := tasks.visible
	if str(_tasks_btn.get_meta("on", "")) != str(t_on):
		_tasks_btn.set_meta("on", t_on)
		if t_on:
			paint_button(_tasks_btn, UiStyle.SELECT_PAPER, UiStyle.SELECT, Color("#1F4E77"), UiStyle.SELECT_PAPER, 10, 12)
		else:
			paint_button(_tasks_btn, UiStyle.PAPER_DEEP, Color.TRANSPARENT, UiStyle.INK, Color("#EADFC8"), 10, 12)
		(_tasks_btn.get_node("Face/Text") as Label).add_theme_color_override("font_color", Color("#1F4E77") if t_on else UiStyle.INK)
		var count: Label = _tasks_btn.get_node("Face/Count")
		var pill := UiStyle.box(UiStyle.SELECT if t_on else UiStyle.INK, Color.TRANSPARENT, 13)
		pill.content_margin_left = 8
		pill.content_margin_right = 8
		pill.content_margin_top = 0
		pill.content_margin_bottom = 0
		count.add_theme_stylebox_override("normal", pill)
		count.add_theme_color_override("font_color", UiStyle.PAPER)


# --- warnings -------------------------------------------------------------------------

## The fixes offered under an alert line: [[button text, Callable, icon], …]; the first one is the
## green primary. Missing planks: make them (research the Sawmill, build one, or cut trees for the
## one there is) or buy them at the Dealer.
func _alert_actions(line: String) -> Array:
	if line.contains("switched off"):
		return [["Priorities", _open_priorities, ""]]
	var short := world.seed_shortage()
	for res: StringName in short:
		if not line.begins_with(Defs.resource_name(res) + ":"):
			continue
		var dealer := ["Dealer", func() -> void: _open_dealer(&"buy", res), "qk"]
		if res != &"planks":
			return [dealer]
		if not world.building_unlocked(&"sawmill"):
			return [["Research", func() -> void: show_research(Tech.node_for_building(&"sawmill")), "tech"], dealer]
		for b: Building in world.buildings.values():
			if b.def_id == &"sawmill":
				return [["Cut trees", func() -> void: dock.press_mode(&"cut"), "cut"], dealer]
		return [["Build a Sawmill", func() -> void: _on_build_pressed(&"sawmill"), "house"], dealer]
	return [["Dealer", func() -> void: _open_dealer(&"buy", &""), "qk"]]


func _alert_bbcode(line: String) -> String:
	var text := line.replace("[", "[lb]")
	var head := ""
	var colon := text.find(": ")
	if colon > 0 and colon < 30:
		head = "[b]%s[/b]" % text.left(colon + 1)
		text = text.substr(colon + 1)
	elif text.contains(" is switched off"):
		var i := text.find(" is switched off")
		head = "[b]%s[/b]" % text.left(i)
		text = text.substr(i)
	return head + _bold.sub(text, "[b]$1[/b]", true)


## Warning cards: the line with a × (hides it until that problem goes away), the fixes on a row
## under it. A problem is known by the head of its line ("Planks:"), the numbers in it change.
func _refresh_warnings() -> void:
	var all := Array(world.alerts())
	var heads := all.map(func(l: String) -> String: return l.get_slice(":", 0))
	for h: String in _dismissed.keys():
		if not heads.has(h):
			_dismissed.erase(h)
	var lines := all.filter(func(l: String) -> bool: return not _dismissed.has(l.get_slice(":", 0)))
	var text := "\n".join(PackedStringArray(lines))
	if text == _warning_text:
		return
	_warning_text = text
	for c in _warnings.get_children():
		_warnings.remove_child(c)
		c.queue_free()
	for line: String in lines:
		var card := PanelContainer.new()
		var sb := UiStyle.box(UiStyle.WARN_PAPER, UiStyle.WARN, 12, 2)
		sb.shadow_color = Color(UiStyle.INK, 0.3)
		sb.shadow_size = 1
		sb.shadow_offset = Vector2(0, 3)
		sb.content_margin_left = 12
		sb.content_margin_right = 10
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		card.add_theme_stylebox_override("panel", sb)
		_warnings.add_child(card)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 8)
		card.add_child(col)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		col.add_child(row)
		var ic := UiStyle.icon_rect(UiStyle.icon("warning"), 22)
		ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(ic)
		var rt := RichTextLabel.new()
		rt.bbcode_enabled = true
		rt.fit_content = true
		rt.scroll_active = false
		rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rt.add_theme_font_override("normal_font", UiStyle.body_font())
		rt.add_theme_font_override("bold_font", UiStyle.body_font(true))
		rt.add_theme_font_size_override("normal_font_size", 15)
		rt.add_theme_font_size_override("bold_font_size", 15)
		rt.add_theme_color_override("default_color", UiStyle.INK)
		rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rt.text = _alert_bbcode(line)
		row.add_child(rt)
		var x := Button.new()
		x.text = "✕"
		x.tooltip_text = "Hide this warning"
		x.focus_mode = Control.FOCUS_NONE
		x.custom_minimum_size = Vector2(26, 26)
		x.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		x.modulate.a = 0.7
		paint_button(x, Color.TRANSPARENT, Color.TRANSPARENT, UiStyle.INK, Color(UiStyle.WARN, 0.15), 7, 0)
		x.alignment = HORIZONTAL_ALIGNMENT_CENTER
		x.pressed.connect(func() -> void:
			_dismissed[line.get_slice(":", 0)] = true
			_refresh_warnings())
		row.add_child(x)
		var acts := HBoxContainer.new()
		acts.add_theme_constant_override("separation", 8)
		var pad := Control.new()
		pad.custom_minimum_size.x = 24      # under the text, past the warning icon
		acts.add_child(pad)
		col.add_child(acts)
		var first := true
		for action: Array in _alert_actions(line):
			var b := Button.new()
			b.text = action[0]
			b.focus_mode = Control.FOCUS_NONE
			b.theme_type_variation = "PrimaryButton" if first else ""
			b.add_theme_font_size_override("font_size", 14)
			b.custom_minimum_size.y = 32
			if action[2] != "":
				b.icon = UiStyle.icon(action[2])
				b.add_theme_constant_override("icon_max_width", 16)
			b.pressed.connect(action[1])
			acts.add_child(b)
			first = false


# --- updates ------------------------------------------------------------------------

func _process(delta: float) -> void:
	_update_float()
	_layout()
	if _toast.visible:
		_toast_time -= delta
		_toast.modulate.a = clampf(_toast_time, 0.0, 1.0)
		if _toast_time <= 0.0:
			_toast.hide()
	_accum += delta
	if _accum > 0.25:
		_accum = 0.0
		_refresh()


func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	# the face row of the bar buttons: 12 px in from the left, centred above the drop shadow
	# (an open toggle sits 2 px lower, pressed onto it); the button is as wide as its row
	for b: Button in _toggles.values() + [_tasks_btn]:
		var face: Control = b.get_node("Face")
		var on := str(b.get_meta("on", "")) == "true"
		var drop := 0.0 if b == _tasks_btn else (1.0 if on else 3.0)
		var fs := face.get_combined_minimum_size()
		var pad_r := 10.0 if b.has_node("Face/Key") else 12.0
		b.custom_minimum_size.x = 12.0 + fs.x + pad_r
		face.size = fs
		face.position = Vector2(12.0, floorf((b.size.y - drop - fs.y) * 0.5) + (2.0 if on and b != _tasks_btn else 0.0))
	dock.reset_size()
	dock.position = Vector2(floorf((vp.x - dock.size.x) * 0.5), vp.y - dock.size.y - 16.0)
	_warnings.reset_size()
	_toast.reset_size()
	_toast.position = Vector2(floorf((vp.x - _toast.size.x) * 0.5), BELOW_BAR)


func _refresh() -> void:
	if world == null or _money == null:
		return
	_money.text = UiStyle.money_number(world.money)
	_refresh_chips()
	var idle := world.idle_workers()
	_idle_n.text = "%d idle" % idle
	_idle_rest.text = "/ %d" % world.workers.size()
	var waiting := world.tasks.pending_count()
	(_tasks_btn.get_node("Face/Count") as Label).text = str(waiting)
	(_tasks_btn.get_node("Face/Text") as Label).text = "task waiting" if waiting == 1 else "tasks waiting"
	_paint_toggles()
	_refresh_warnings()
	# the warnings make room for the panels docked on the left
	# Settings: the player can hide the warning lines under the HUD
	_warnings.visible = not (tasks.visible or priorities.visible) and Settings.warning_lines
	dock.refresh()


func _on_build_pressed(id: StringName) -> void:
	if not world.building_unlocked(id):
		show_research(Tech.node_for_building(id))
		return
	build_requested.emit(id)


## Keyboard shortcuts of the tool dock (from game.gd): B build list, M move, C cut trees,
## X demolish. True when the key was used.
func dock_key(keycode: Key) -> bool:
	match keycode:
		KEY_B:
			dock.toggle_list()
		KEY_M:
			dock.press_mode(&"move")
		KEY_C:
			dock.press_mode(&"cut")
		KEY_X:
			dock.press_mode(&"demolish")
		_:
			return false
	return true


# --- crop picker over a field being drawn ---------------------------------------------

func _build_float() -> void:
	_float = PanelContainer.new()
	_float.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UiStyle.panel_box()
	sb.set_content_margin_all(10)
	_float.add_theme_stylebox_override("panel", sb)
	_float.visible = false
	add_child(_float)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_float.add_child(col)
	_float_info = Label.new()
	_float_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_float_info.add_theme_font_size_override("font_size", 15)
	col.add_child(_float_info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	for c: StringName in Defs.CROPS:
		var box := PanelContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		box.add_child(v)
		var icon := UiStyle.icon_rect(UiStyle.resource_icon(c), 44)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(icon)
		var name := Label.new()
		name.text = Defs.CROPS[c]["name"]
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name.add_theme_font_override("font", UiStyle.head_font(600))
		name.add_theme_font_size_override("font_size", 14)
		v.add_child(name)
		row.add_child(box)
		_float_icons[c] = box
	var tab := UiStyle.key_cap("Tab")
	row.add_child(tab)


func _update_float() -> void:
	var on := tool.active() and tool.def_id != &"" and Defs.is_field(tool.def_id)
	_float.visible = on
	if not on:
		return
	for c: StringName in _float_icons:
		var box: PanelContainer = _float_icons[c]
		var selected: bool = c == tool.crop
		if str(box.get_meta("sel", "")) != str(selected):
			box.set_meta("sel", selected)
			var sb := UiStyle.box(UiStyle.SELECT_PAPER if selected else Color.TRANSPARENT, UiStyle.SELECT if selected else Color.TRANSPARENT, UiStyle.RADIUS, 2)
			sb.set_content_margin_all(6)
			box.add_theme_stylebox_override("panel", sb)
			box.modulate.a = 1.0 if selected else 0.55
	var text := tool.field_info()
	_float_info.text = text
	_float_info.visible = text != ""
	_float.reset_size()
	var cam := tool.rig.camera
	var p := cam.unproject_position(tool.picker_anchor())
	var dy := -_float.size.y - 40.0 if tool.picker_above() else 24.0
	_float.position = p + Vector2(-_float.size.x * 0.5, dy)
	var screen := get_viewport().get_visible_rect().size
	_float.position = _float.position.clamp(Vector2(8, BELOW_BAR), screen - _float.size - Vector2(8, 90))


# --- panels -------------------------------------------------------------------------

func toggle_dealer() -> void:
	if dealer_panel.visible:
		dealer_panel.hide()
	else:
		_open_dealer(&"", &"")


## Opens the Dealer, on a tab (&"sell" / &"buy") and with a seed preselected when given.
func _open_dealer(tab: StringName, res: StringName) -> void:
	priorities.hide()
	research.hide()
	tasks.hide()
	dealer_panel.show()
	dealer_panel.refresh()
	if tab != &"" and dealer_panel.has_method("show_tab"):
		if String(res).begins_with("seed_"):
			dealer_panel.call("show_tab", tab, res)
		else:
			dealer_panel.call("show_tab", tab)
	_refresh()


func toggle_research() -> void:
	if research.visible:
		research.hide()
	else:
		show_research(&"")


## Opens the research tree, on a node if one is given.
func show_research(id: StringName) -> void:
	dealer_panel.hide()
	priorities.hide()
	tasks.hide()
	if id != &"":
		research.select(id)
	research.refresh()
	research.show()
	_refresh()


func toggle_dev_menu() -> void:
	dev_menu.visible = not dev_menu.visible
	if dev_menu.visible:
		dev_menu.refresh()


func toggle_priorities() -> void:
	if priorities.visible:
		priorities.hide()
	else:
		_open_priorities()


func _open_priorities() -> void:
	dealer_panel.hide()
	research.hide()
	tasks.hide()
	priorities.show()
	priorities.rebuild()
	priorities.position = Vector2(MARGIN, BELOW_BAR)
	_refresh()


## The Tasks panel, docked left under the bar (it shares the place with Priorities).
func toggle_tasks() -> void:
	if tasks.visible:
		tasks.hide()
	else:
		priorities.hide()
		dealer_panel.hide()
		research.hide()
		tasks.position = Vector2(MARGIN, BELOW_BAR)
		tasks.show()
	_refresh()


# --- toast --------------------------------------------------------------------------

func _build_toast() -> void:
	_toast = PanelContainer.new()
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.custom_minimum_size.y = 44
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_toast.add_child(row)
	_toast_mark = Control.new()
	_toast_mark.custom_minimum_size = Vector2(22, 22)
	_toast_mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_toast_mark.draw.connect(_draw_toast_mark)
	row.add_child(_toast_mark)
	_toast_label = RichTextLabel.new()
	_toast_label.bbcode_enabled = true
	_toast_label.fit_content = true
	_toast_label.scroll_active = false
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_toast_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_toast_label.add_theme_font_override("normal_font", UiStyle.body_font())
	_toast_label.add_theme_font_override("bold_font", UiStyle.body_font(true))
	_toast_label.add_theme_font_size_override("normal_font_size", 15)
	_toast_label.add_theme_font_size_override("bold_font_size", 15)
	_toast_label.add_theme_color_override("default_color", UiStyle.INK)
	_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_toast_label)
	_toast_action = Button.new()
	_toast_action.focus_mode = Control.FOCUS_NONE
	_toast_action.add_theme_font_size_override("font_size", 13)
	_toast_action.custom_minimum_size.y = 30
	_toast_action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_toast_action.pressed.connect(func() -> void:
		_toast.hide()
		if _toast_callback.is_valid():
			_toast_callback.call())
	row.add_child(_toast_action)
	_toast.hide()
	add_child(_toast)


## The mark at the start of a toast: a green tick (done), a clock (info) or the warning sign.
func _draw_toast_mark() -> void:
	match _toast_kind:
		"ok":
			_toast_mark.draw_circle(Vector2(11, 11), 11, UiStyle.GO)
			_toast_mark.draw_polyline(PackedVector2Array([Vector2(6.5, 11.5), Vector2(9.5, 14.5), Vector2(15.5, 8)]), UiStyle.PAPER, 2.4, true)
		"fail":
			_toast_mark.draw_texture_rect(UiStyle.icon("warning"), Rect2(0, 0, 22, 22), false)
		_:
			_toast_mark.draw_texture_rect(UiStyle.icon("clock"), Rect2(0, 0, 22, 22), false)


## Short message under the top bar (kinds: "ok" green, "info" paper, "fail" warning). "ok" and
## "info" fade after 3 s; a failure stays until its action is used or another toast replaces it.
## The part before " · " or " — " is bold.
func toast(text: String, kind := "info", action_text := "", action := Callable()) -> void:
	_toast_kind = kind
	var fill: Color = {"ok": UiStyle.DONE, "fail": UiStyle.WARN_PAPER}.get(kind, UiStyle.PAPER)
	var edge: Color = {"ok": UiStyle.DONE_EDGE, "fail": UiStyle.WARN}.get(kind, UiStyle.WOOD)
	var sb := UiStyle.box(fill, edge, 22, 2)
	sb.shadow_color = Color(UiStyle.INK, 0.3)
	sb.shadow_size = 1
	sb.shadow_offset = Vector2(0, 3)
	sb.content_margin_left = 12
	sb.content_margin_right = 8 if action_text != "" else 16
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	_toast.add_theme_stylebox_override("panel", sb)
	var body := text.replace("[", "[lb]")
	for sep in [" · ", " — "]:
		var i := body.find(sep)
		if i > 0:
			body = "[b]%s[/b]%s" % [body.left(i), body.substr(i)]
			break
	_toast_label.text = body
	_toast_action.text = action_text
	_toast_action.visible = action_text != ""
	_toast_callback = action
	_toast.mouse_filter = Control.MOUSE_FILTER_STOP if action_text != "" else Control.MOUSE_FILTER_IGNORE
	_toast_time = INF if kind == "fail" else 3.0
	_toast.modulate.a = 1.0
	_toast_mark.queue_redraw()
	_toast.show()
	_layout()


## --show=hud / build / tasks / road / cut / toast (screenshots).
func debug_show(name: String, _game: Node3D) -> void:
	match name:
		"hud", "road":
			_debug_shortages()
			if name == "road":
				_on_build_pressed(&"road_gravel")
		"build":
			dock.show_category("Processing")
		"build_storage":
			world.unlocked[&"collection_point"] = true
			world.unlocked.erase(&"supply_storage")
			world.tech_changed.emit()
			dock.show_category("Storage")
		"stock_tip":
			_debug_shortages()
			_debug_stock_places()
			_refresh()
			_debug_open_tip.call_deferred(&"planks")
		"tasks":
			_debug_shortages()
			world.set_category_on(Task.Category.TRANSPORT, false)
			toggle_tasks()
		"cut":
			dock.press_mode(&"cut")
		"dev":
			toggle_dev_menu()
		"toast":
			_debug_shortages()
			toast("Saving failed — the disk is full", "fail", "Try again", func() -> void: pass)
	_refresh()


## Screenshots (stock_tip): a Shed near the barn and a collection point by the nearest road, planks
## split between the barn (20), the Shed (15) and the collection point (10, on the way).
func _debug_stock_places() -> void:
	for id: StringName in [&"collection_point", &"supply_storage"]:
		world.unlocked[id] = true
	var barn := Vector2i(world.size / 2, world.size / 2)
	for b: Building in world.buildings.values():
		if b.def_id == &"storage_barn":
			barn = b.anchor
	var shed: Building = null
	for r in range(4, 30):
		for dx in range(-r, r + 1):
			if shed == null and world.can_place(&"shed", barn + Vector2i(dx, r), 0, Vector2i.ZERO, true):
				shed = world.add_building(&"shed", barn + Vector2i(dx, r), 0)
	var blocks: Array = world.road_blocks.keys()
	blocks.sort_custom(func(p: Vector2i, q: Vector2i) -> bool: return p.distance_squared_to(barn) < q.distance_squared_to(barn))
	var cp: Building = null
	for a: Vector2i in blocks:
		var snap := world.road_snap(a + Vector2i(1, 1), 0)
		if not snap.is_empty():
			cp = world.add_building(&"collection_point", snap["anchor"], snap["rot"])
			break
	world.set_stock(&"planks", 20.0)
	if shed:
		shed.store.put(&"planks", 15.0)
	if cp:
		cp.store.put(&"planks", 10.0)
	world.tech_changed.emit()
	world.stock_changed.emit()


## Screenshots: the stock tooltip of `res`, shown as if hovered (a tooltip can't be opened by code).
func _debug_open_tip(res: StringName) -> void:
	await get_tree().process_frame
	if not _chips.has(res):
		return
	var chip: Control = _chips[res]["panel"]
	var tip := PanelContainer.new()
	tip.add_theme_stylebox_override("panel", chip.get_theme_stylebox("panel", "TooltipPanel"))
	tip.add_child(stock_tip(res))
	add_child(tip)
	tip.position = chip.global_position + Vector2(0, chip.size.y + 10)


## Screenshots: gravel road upgrades and a garage site with nothing in the barn for them, so the
## warning cards show.
func _debug_shortages() -> void:
	world.set_stock(&"gravel", 0.0)
	world.set_stock(&"planks", 0.0)
	var barn := Vector2i(world.size / 2, world.size / 2)
	for b: Building in world.buildings.values():
		if b.def_id == &"storage_barn":
			barn = b.anchor
	var blocks: Array = world.road_blocks.keys()
	blocks.sort_custom(func(p: Vector2i, q: Vector2i) -> bool: return p.distance_squared_to(barn) < q.distance_squared_to(barn))
	for a: Vector2i in blocks.slice(0, 3):
		world.place_site(&"road_gravel", a, 0)
	for r in range(6, 40):
		for dx in range(-r, r + 1):
			if world.place_site(&"garage", barn + Vector2i(dx, -r), 2):
				for i in 200:
					world.tick(0.1)
				return
