class_name TasksPanel
extends PanelContainer
## Tasks (opened from the HUD chip, docked left under the HUD): waiting and running tasks grouped
## by category in the player's priority order. Stuck tasks say why and offer the fix.

signal dealer_requested(tab: StringName, res: StringName)
signal research_requested(id: StringName)
signal priorities_requested
signal focus_requested(cell: Vector2i)
signal worker_selected(w: Worker)

const CATEGORY_ICONS := {
	Task.Category.HARVEST: "wheat", Task.Category.DEALER: "qk", Task.Category.PLANTING: "seeds",
	Task.Category.CONSTRUCTION: "build", Task.Category.TRANSPORT: "wheelbarrow", Task.Category.PROCESSING: "flour",
}
## Icon for categories added later (e.g. Felling) by their name.
const NAMED_ICONS := {"Felling": "cut"}
const FILTERS: Array[String] = ["All", "Waiting", "Stuck"]
const MAX_ROWS := 6                # rows per category; the rest is summed up in one line
const WIDTH := 600.0

var world: World
var _filter := 0
var _sub: Label
var _filter_buttons: Array[Button] = []
var _idle_warn: PanelContainer
var _idle_text: RichTextLabel
var _scroll: ScrollContainer
var _list: VBoxContainer
var _sig := ""
var _accum := 0.0
var _expanded := {}                # categories showing all their rows ("and N more" clicked)


func setup(p_world: World) -> void:
	world = p_world
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	custom_minimum_size.x = WIDTH
	var p := UiStyle.make_panel("Tasks")
	add_child(p["root"])
	(p["close"] as Button).pressed.connect(hide)
	var header: HBoxContainer = p["header"]
	_sub = Label.new()
	_sub.add_theme_font_size_override("font_size", 14)
	_sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_sub)
	header.move_child(_sub, (p["title"] as Label).get_index() + 1)
	var body: VBoxContainer = p["body"]
	body.add_theme_constant_override("separation", 10)

	var frow := HBoxContainer.new()
	body.add_child(frow)
	var show_l := Label.new()
	show_l.text = "Show"
	show_l.theme_type_variation = "SmallLabel"
	show_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frow.add_child(show_l)
	var seg := PanelContainer.new()
	var ssb := UiStyle.box(UiStyle.PAPER_DEEP, UiStyle.BOARD, UiStyle.RADIUS, 1)
	ssb.set_content_margin_all(3)
	seg.add_theme_stylebox_override("panel", ssb)
	frow.add_child(seg)
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 3)
	seg.add_child(srow)
	for i in FILTERS.size():
		var b := Button.new()
		b.text = FILTERS[i]
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 14)
		b.custom_minimum_size.y = 28
		b.pressed.connect(func() -> void:
			_filter = i
			_sig = ""
			refresh())
		srow.add_child(b)
		_filter_buttons.append(b)

	_idle_warn = PanelContainer.new()
	var wsb := UiStyle.box(UiStyle.WARN_PAPER, UiStyle.WARN, UiStyle.RADIUS, 1)
	wsb.content_margin_top = 7
	wsb.content_margin_bottom = 7
	_idle_warn.add_theme_stylebox_override("panel", wsb)
	body.add_child(_idle_warn)
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 10)
	_idle_warn.add_child(wrow)
	wrow.add_child(UiStyle.icon_rect(UiStyle.icon("warning"), 20))
	_idle_text = _rich(14)
	wrow.add_child(_idle_text)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UiStyle.slim_scrollbars(_scroll)
	body.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	visibility_changed.connect(func() -> void:
		if visible:
			_sig = ""
			refresh())
	hide()


func _process(delta: float) -> void:
	if not visible:
		return
	_accum += delta
	if _accum > 0.5:
		_accum = 0.0
		refresh()


# --- model ----------------------------------------------------------------------------

## Why a waiting task can't start, from world state only: {} when it isn't stuck, else
## {text, fix, arg} (fix: "Priorities", "Buy seed", "Dealer", "Research"); {"wait": text} when it
## waits for something that is on its way.
func _stuck(t: Task, short: Dictionary) -> Dictionary:
	if t.worker != null:
		return {}
	if world.category_off.has(t.category):
		return {"text": "stuck: %s is switched off" % Task.CATEGORY_NAMES[t.category][0], "fix": "Priorities"}
	var res := t.fetch
	if res == &"" or res == &"wheelbarrow" or world.stock.get(res, 0.0) >= world.fetch_min(t):
		return {}
	var name := Defs.resource_name(res).to_lower()
	var ordered: float = world.orders.get(res, 0.0)
	var missing: float = short.get(res, world.fetch_min(t) - world.stock.get(res, 0.0))
	if ordered > 0.0 and ordered >= missing:
		return {"wait": "waiting for the pickup to bring %s" % Defs.format_amount(res, ordered)}
	if String(res).begins_with("seed_"):
		var text := "stuck: no %s in the barn" % name if world.stock.get(res, 0.0) < 0.0005 else "stuck: %s" % _more_needed(res, missing)
		return {"text": text, "fix": "Buy seed"}
	if t.kind == Task.Kind.DELIVER and t.site:
		var text := "stuck: %s" % _more_needed(res, missing)
		if res == &"planks" and not world.building_unlocked(&"sawmill"):
			return {"text": text, "fix": "Research", "arg": Tech.node_for_building(&"sawmill")}
		if Defs.buyable(res) and world.item_unlocked(res):
			return {"text": text, "fix": "Dealer"}
		return {"text": text}
	# a mill or the sawmill waiting for its raw goods: not something to fix
	return {"wait": "waiting for %s in the barn" % name}


## "600 kg more gravel needed", "80 more planks needed".
static func _more_needed(res: StringName, missing: float) -> String:
	var name := Defs.resource_name(res).to_lower()
	if Defs.is_piece(res):
		return "%d more %s needed" % [ceili(missing - 0.0001), name]
	return "%s more %s needed" % [Defs.format_kg(missing), name]


func _target_name(t: Task) -> String:
	if t.site:
		return Defs.def(t.site.def_id)["name"]
	if t.field:
		return "%s field" % Defs.CROPS[t.field.crop]["name"]
	if t.building:
		return t.building.display_name()
	return ""


func _title(t: Task, rows: Array, sites := 1) -> String:
	if t.kind == Task.Kind.FIELD and t.field:
		var r := "row %d" % (rows[0] + 1)
		if rows.size() > 1:
			rows.sort()
			r = "rows %d–%d" % [rows[0] + 1, rows[-1] + 1] if rows[-1] - rows[0] == rows.size() - 1 else "%d rows" % rows.size()
		return "%s %s · %s field, %s" % [String(t.step).capitalize(), Defs.CROPS[t.field.crop]["name"].to_lower(), Defs.CROPS[t.field.crop]["name"], r]
	var text := t.label()
	match t.kind:
		Task.Kind.CHOP, Task.Kind.BUILD:
			if t.site and t.kind == Task.Kind.CHOP:
				text += " · %s site" % _target_name(t)
		Task.Kind.DELIVER:
			if t.site and sites > 1:
				# "Bring gravel · 3 sites" (the count is added by the caller)
				return "Bring %s" % Defs.resource_name(t.fetch).to_lower()
			if t.site:
				# "Bring planks to the Garage · 20 of 80"
				text = "Bring %s to the %s" % [Defs.resource_name(t.fetch).to_lower(), Defs.def(t.site.def_id)["name"]]
				var need: float = t.site.material().get(t.fetch, 0.0)
				var got: float = t.site.delivered.get(t.fetch, 0.0)
				if need > 0.0:
					if Defs.is_piece(t.fetch):
						text += " · %d of %d" % [floori(got + 0.0001), roundi(need)]
					else:
						text += " · %s of %s" % [Defs.format_kg(got).trim_suffix(" kg"), Defs.format_kg(need)]
	return text


func _running_detail(t: Task) -> String:
	var w := t.worker
	match t.kind:
		Task.Kind.FIELD:
			return "tile %d of %d" % [mini(w.strip_i + 1, t.cells.size()), t.cells.size()]
		Task.Kind.BUILD:
			return "%d %% built" % roundi(t.site.progress() * 100.0)
		Task.Kind.CHOP:
			return "clearing the site" if t.site else "felling"
		Task.Kind.DELIVER, Task.Kind.HAUL:
			if w.carrying != &"":
				return "carrying %s" % Defs.format_goods(w.carrying, w.carry_amount)
			return "on the way" if t.kind == Task.Kind.HAUL else "fetching %s from the barn" % Defs.format_goods(t.fetch, t.fetch_amount)
		Task.Kind.TRIP, Task.Kind.HELP:
			return world.trip_status
		Task.Kind.PROCESS:
			return world.process_status(t.building)
	return ""


func _worker_name(w: Worker) -> String:
	var n: Variant = w.get("name")
	if n != null and str(n) != "":
		return str(n)
	return "Worker %d" % (world.workers.find(w) + 1)


## Rows per category: running tasks one by one, waiting ones grouped (same kind, target and reason).
func _model() -> Dictionary:
	var short := world.seed_shortage()
	var cats := {}
	var waiting := 0
	var running := 0
	var stuck_n := 0
	for c in Task.Category.values():
		cats[c] = {"waiting": 0, "running": 0, "rows": [], "groups": {}}
	for t in world.tasks.tasks:
		var g: Dictionary = cats[t.category]
		if t.worker != null:
			running += 1
			g["running"] += 1
			if _filter == 0:
				var walking := t.worker.phase != Worker.Phase.WORKING
				g["rows"].append({"state": "walking" if walking else "working", "title": _title(t, [t.row]),
					"detail": _running_detail(t), "worker": t.worker, "cell": t.cell, "count": 1})
			continue
		waiting += 1
		g["waiting"] += 1
		var s := _stuck(t, short)
		var is_stuck := s.has("text")
		if is_stuck:
			stuck_n += 1
		if _filter == 2 and not is_stuck:
			continue
		var target: Variant = t.site if t.site else (t.field if t.field else t.building)
		# sites of one kind (e.g. gravel road blocks) share a row; fields and buildings get their own
		var who: Variant = Defs.def(t.site.def_id)["name"] if t.site else (target.get_instance_id() if target else 0)
		var key := "%d|%s|%s|%s|%s" % [t.kind, t.step, t.fetch, who, s.get("text", "")]
		if g["groups"].has(key):
			var row: Dictionary = g["groups"][key]
			row["count"] += 1
			row["rows"].append(t.row)
			if t.site:
				row["sites"][t.site] = true
			continue
		var detail: String = s.get("text", s.get("wait", ""))
		if detail == "":
			detail = "waiting for a free worker" if world.idle_workers() == 0 else "waiting to start"
		var row := {"state": "warning" if is_stuck else "idle", "task": t, "rows": [t.row], "detail": detail,
			"bad": is_stuck, "fix": s.get("fix", ""), "arg": s.get("arg", &""), "cell": t.cell, "count": 1,
			"res": t.fetch, "sites": {t.site: true} if t.site else {}}
		g["groups"][key] = row
		g["rows"].append(row)
	for c: int in cats:
		for row: Dictionary in cats[c]["rows"]:
			if row.has("task"):
				var t: Task = row["task"]
				var sites: int = row["sites"].size()
				row["title"] = _title(t, row["rows"], sites)
				if sites > 1:
					row["title"] += " · %d sites" % sites
				elif row["count"] > 1 and t.kind != Task.Kind.FIELD and t.kind != Task.Kind.DELIVER:
					row["title"] += " · ×%d" % row["count"]
				row.erase("sites")
				row.erase("task")
				row.erase("rows")
	return {"cats": cats, "waiting": waiting, "running": running, "stuck": stuck_n}


# --- view -----------------------------------------------------------------------------

func refresh() -> void:
	if world == null:
		return
	var m := _model()
	_sub.text = "%d waiting · %d in progress" % [m["waiting"], m["running"]]
	for i in _filter_buttons.size():
		_paint_filter(_filter_buttons[i], i == _filter)
	var idle := world.idle_workers()
	_idle_warn.visible = idle > 0 and m["stuck"] > 0
	if _idle_warn.visible:
		_idle_text.text = "[b]%d worker%s idle[/b] — %d waiting task%s stuck on materials or switched-off work." % [
			idle, "" if idle == 1 else "s", m["stuck"], " is" if m["stuck"] == 1 else "s are"]
	var sig := str(m["cats"])
	if sig == _sig:
		return
	_sig = sig
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var any := false
	for c: int in world.category_order:
		var g: Dictionary = m["cats"][c]
		if (g["rows"] as Array).is_empty():
			continue
		any = true
		_list.add_child(_category_box(c, g))
	if not any:
		var l := Label.new()
		l.text = "No tasks waiting." if _filter == 0 else "Nothing here."
		l.theme_type_variation = "SoftLabel"
		_list.add_child(l)
	var counts := world.category_counts()
	for c: int in world.category_order:
		if world.category_off.has(c) and counts[c][0] > 0:
			_list.add_child(_off_line(c, counts[c][0]))
	_fit.call_deferred()


func _fit() -> void:
	var max_h := get_viewport_rect().size.y - 86.0 - 340.0
	_scroll.custom_minimum_size.y = minf(_list.get_combined_minimum_size().y, maxf(160.0, max_h))
	reset_size()


func _paint_filter(b: Button, on: bool) -> void:
	if on:
		Hud.paint_button(b, UiStyle.PAPER, UiStyle.WOOD, UiStyle.INK, UiStyle.PAPER, 7, 10, 1)
		for s in ["normal", "hover", "pressed", "hover_pressed"]:
			(b.get_theme_stylebox(s) as StyleBoxFlat).border_width_bottom = 3
	else:
		Hud.paint_button(b, Color.TRANSPARENT, Color.TRANSPARENT, UiStyle.INK_SOFT, Color(UiStyle.PAPER, 0.6), 7, 10)


func _rich(size: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_theme_font_override("normal_font", UiStyle.body_font())
	r.add_theme_font_override("bold_font", UiStyle.body_font(true))
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_color_override("default_color", UiStyle.INK)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _category_box(c: int, g: Dictionary) -> PanelContainer:
	var box := PanelContainer.new()
	var sb := UiStyle.box(Color("#FBF5E8"), Color("#E4D6BC"), UiStyle.RADIUS, 1)
	sb.set_content_margin_all(0)
	box.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	box.add_child(col)
	var head := PanelContainer.new()
	var hsb := UiStyle.box(UiStyle.PAPER_DEEP, Color.TRANSPARENT, 9)
	hsb.corner_radius_bottom_left = 0
	hsb.corner_radius_bottom_right = 0
	hsb.content_margin_left = 10
	hsb.content_margin_right = 10
	hsb.content_margin_top = 5
	hsb.content_margin_bottom = 5
	head.add_theme_stylebox_override("panel", hsb)
	col.add_child(head)
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 8)
	head.add_child(hrow)
	hrow.add_child(UiStyle.icon_rect(UiStyle.icon(_cat_icon(c)), 22))
	var name := Label.new()
	name.text = Task.CATEGORY_NAMES[c][0]
	name.add_theme_font_override("font", UiStyle.head_font(600))
	name.add_theme_font_size_override("font_size", 16)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hrow.add_child(name)
	var counts := _rich(13)
	counts.autowrap_mode = TextServer.AUTOWRAP_OFF
	counts.size_flags_horizontal = Control.SIZE_SHRINK_END
	counts.add_theme_color_override("default_color", UiStyle.INK_SOFT)
	counts.text = "[color=#3B2A1E][b]%d[/b][/color] waiting · [color=#3B2A1E][b]%d[/b][/color] in progress" % [g["waiting"], g["running"]]
	hrow.add_child(counts)
	var rows: Array = g["rows"]
	# stuck rows first, then running, then waiting
	var order := {"warning": 0, "working": 1, "walking": 1, "idle": 2}
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return order[a["state"]] < order[b["state"]])
	var shown := rows.size() if _expanded.has(c) else mini(rows.size(), MAX_ROWS)
	for i in shown:
		if i > 0:
			col.add_child(_rule())
		col.add_child(_row(rows[i]))
	if rows.size() > shown:
		var n := 0
		for i in range(shown, rows.size()):
			n += rows[i]["count"]
		var more := _link("and %d more" % n, false)
		more.tooltip_text = "Show every row of %s" % Task.CATEGORY_NAMES[c][0]
		more.pressed.connect(func() -> void:
			_expanded[c] = true
			_sig = ""
			refresh())
		var mm := MarginContainer.new()
		mm.add_theme_constant_override("margin_left", 42)
		mm.add_theme_constant_override("margin_top", 6)
		mm.add_theme_constant_override("margin_bottom", 8)
		mm.add_child(more)
		more.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		col.add_child(mm)
	return box


## A row separator, inset 10 px from the box edges.
func _rule() -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 10)
	m.add_theme_constant_override("margin_right", 10)
	var sep := ColorRect.new()
	sep.color = Color("#EFE4CE")
	sep.custom_minimum_size.y = 1
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(sep)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return m


## A kit link: blue, underlined, darker on hover.
func _link(text: String, bold: bool) -> LinkButton:
	var l := LinkButton.new()
	l.text = text
	l.focus_mode = Control.FOCUS_NONE
	l.underline = LinkButton.UNDERLINE_MODE_ALWAYS
	l.add_theme_font_override("font", UiStyle.body_font(bold))
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", UiStyle.SELECT)
	l.add_theme_color_override("font_hover_color", Color("#1F4E77"))
	l.add_theme_color_override("font_pressed_color", Color("#1F4E77"))
	l.add_theme_color_override("font_hover_pressed_color", Color("#1F4E77"))
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return l


func _row(r: Dictionary) -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 12)
	m.add_theme_constant_override("margin_right", 8)
	m.add_theme_constant_override("margin_top", 4)
	m.add_theme_constant_override("margin_bottom", 4)
	m.custom_minimum_size.y = 46
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	m.add_child(row)
	var ic := UiStyle.icon_rect(UiStyle.icon(r["state"]), 20)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 1)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(text)
	var title := Label.new()
	title.text = r["title"]
	title.add_theme_font_size_override("font_size", 15)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	text.add_child(title)
	if r["detail"] != "":
		var d := Label.new()
		d.text = r["detail"]
		d.add_theme_font_size_override("font_size", 13)
		d.add_theme_color_override("font_color", UiStyle.SHORT if r.get("bad", false) else UiStyle.INK_SOFT)
		d.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		d.clip_text = true
		text.add_child(d)
	if r.has("worker"):
		var w: Worker = r["worker"]
		# the worker's name is a link: select and follow that worker
		var who := HBoxContainer.new()
		who.add_theme_constant_override("separation", 5)
		who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		who.mouse_filter = Control.MOUSE_FILTER_PASS
		who.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		who.tooltip_text = "Select and follow the worker"
		var wi := UiStyle.icon_rect(UiStyle.icon("worker"), 20)
		who.add_child(wi)
		var link := _link(_worker_name(w), true)
		link.tooltip_text = who.tooltip_text
		link.pressed.connect(func() -> void: worker_selected.emit(w))
		who.add_child(link)
		who.gui_input.connect(func(e: InputEvent) -> void:
			var mb := e as InputEventMouseButton
			if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				worker_selected.emit(w))
		row.add_child(who)
	else:
		var fix: String = r.get("fix", "")
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 13)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.custom_minimum_size.y = 28
		row.add_child(b)
		if fix == "":
			b.text = "Show"
			b.tooltip_text = "Move the camera there"
			_small(b, false)
			var cell: Vector2i = r["cell"]
			b.pressed.connect(func() -> void: focus_requested.emit(cell))
		else:
			b.text = fix
			_small(b, true)
			var arg: StringName = r.get("arg", &"")
			match fix:
				"Priorities":
					b.pressed.connect(func() -> void: priorities_requested.emit())
				"Research":
					b.pressed.connect(func() -> void: research_requested.emit(arg))
				_:
					var res: StringName = r.get("res", &"")
					b.pressed.connect(func() -> void: dealer_requested.emit(&"buy", res))
	return m


## Compact row button (28 px): secondary or primary (green).
func _small(b: Button, primary: bool) -> void:
	var fill := UiStyle.GO if primary else UiStyle.PAPER
	var edge := Color("#36592A") if primary else UiStyle.WOOD
	var text := UiStyle.PAPER if primary else UiStyle.INK
	Hud.paint_button(b, fill, edge, text, fill.lightened(0.08) if primary else Color("#F6EBD3"), 7, 10)
	for s in ["normal", "hover"]:
		var sb := b.get_theme_stylebox(s) as StyleBoxFlat
		sb.border_width_bottom = 4
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2


func _off_line(c: int, n: int) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UiStyle.box(Color.TRANSPARENT, Color("#B5AD9E"), UiStyle.RADIUS, 2)
	p.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	p.add_child(row)
	row.add_child(UiStyle.icon_rect(UiStyle.icon(_cat_icon(c)), 22))
	var t := _rich(14)
	t.add_theme_color_override("default_color", Color("#5E5244"))
	t.text = "[b]%s[/b] is off · %d task%s paused" % [Task.CATEGORY_NAMES[c][0], n, "" if n == 1 else "s"]
	row.add_child(t)
	var link := LinkButton.new()
	link.text = "Turn on in Priorities"
	link.focus_mode = Control.FOCUS_NONE
	link.add_theme_color_override("font_color", UiStyle.SELECT)
	link.add_theme_color_override("font_hover_color", Color("#1F4E77"))
	link.add_theme_font_size_override("font_size", 14)
	link.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	link.pressed.connect(func() -> void: priorities_requested.emit())
	row.add_child(link)
	return p


func _cat_icon(c: int) -> String:
	return CATEGORY_ICONS.get(c, NAMED_ICONS.get(Task.CATEGORY_NAMES[c][0], "build"))
