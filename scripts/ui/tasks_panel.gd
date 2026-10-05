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
var _expanded := {}                # categories showing all their rows ("and N more" clicked); "trip:<id>" -> open
var _sample_tasks: Array[Task] = []        # --show=tasks_legs: sample chain legs (not in the queue)
var _sample_trips: Array[Dictionary] = []  # --show=tasks_legs: sample trip previews


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
	add_to_group("debug_show")


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
	if t.kind == Task.Kind.CARRY or res == &"" or world.total(res) >= world.fetch_min(t):
		return {}
	var name := Defs.resource_name(res).to_lower()
	var ordered: float = world.orders.get(res, 0.0)
	var missing: float = short.get(res, world.fetch_min(t) - world.total(res))
	if ordered > 0.0 and ordered >= missing:
		return {"wait": "waiting for the pickup to bring %s" % Defs.format_amount(res, ordered)}
	if String(res).begins_with("seed_"):
		var text := "stuck: no %s in the barn" % name if world.total(res) < 0.0005 else "stuck: %s" % _more_needed(res, missing)
		return {"text": text, "fix": "Buy seed"}
	return {"wait": "waiting for %s in the barn" % name}


## Why a site's material is not on its way: {text, fix, arg} like `_stuck`, or {"wait": text}.
func _need_stuck(res: StringName, missing: float) -> Dictionary:
	var ordered: float = world.orders.get(res, 0.0)
	if ordered > 0.0 and ordered >= missing:
		return {"wait": "waiting for the pickup to bring %s" % Defs.format_amount(res, ordered)}
	var text := "stuck: %s" % _more_needed(res, missing)
	if res == &"planks" and not world.building_unlocked(&"sawmill"):
		return {"text": text, "fix": "Research", "arg": Tech.node_for_building(&"sawmill")}
	if Defs.buyable(res) and world.item_unlocked(res):
		return {"text": text, "fix": "Dealer"}
	return {"text": text}


## "600 kg more gravel needed", "80 more planks needed".
static func _more_needed(res: StringName, missing: float) -> String:
	var name := Defs.resource_name(res).to_lower()
	if Defs.is_piece(res):
		return "%d more %s needed" % [ceili(missing - 0.0001), name]
	return "%s more %s needed" % [Defs.format_kg(missing), name]


func _target_name(t: Task) -> String:
	if t.site:
		return t.site.base_name()
	if t.field:
		return "%s field" % Defs.CROPS[t.field.crop]["name"]
	if t.building:
		return t.building.display_name()
	return ""


## "the Garage", but "North Mill": a name of its own goes without "the".
static func _the(site: ConstructionSite) -> String:
	var b: Building = site.upgrade_of if site.upgrade_of else site
	return site.base_name() if b.custom_name != "" else "the " + site.base_name()


func _title(t: Task, rows: Array, sites := 1) -> String:
	if t.kind == Task.Kind.FIELD and t.field:
		var r := "row %d" % (rows[0] + 1)
		if rows.size() > 1:
			rows.sort()
			r = "rows %d–%d" % [rows[0] + 1, rows[-1] + 1] if rows[-1] - rows[0] == rows.size() - 1 else "%d rows" % rows.size()
		return "%s %s · %s field, %s" % [String(t.step).capitalize(), Defs.CROPS[t.field.crop]["name"].to_lower(), Defs.CROPS[t.field.crop]["name"], r]
	var text := t.label()
	if t.kind == Task.Kind.CARRY and t.plan.size() > 1:
		# "Wood → road pile · then pickup to Storage Barn"
		text = "%s → %s" % [Defs.resource_name(t.fetch), t.dst.label()]
		if t.leg_i < t.plan.size() - 1:
			var by_pickup := false
			for i in range(t.leg_i + 1, t.plan.size()):
				by_pickup = by_pickup or t.plan[i]["by"] == &"ride"
			text += " · then %s to %s" % ["pickup" if by_pickup else "carried", t.final_dst().label()]
	match t.kind:
		Task.Kind.CHOP, Task.Kind.BUILD:
			if t.site and t.kind == Task.Kind.CHOP:
				text += " · %s site" % _target_name(t)
		Task.Kind.CARRY:
			if t.site and t.dst and t.dst.kind == Store.Kind.SITE:
				text += _site_progress(t.site, t.fetch)       # "Carry planks from Storage Barn to Garage · 20 of 80"
	return text


## " · 20 of 80": how much of the material the site has.
func _site_progress(site: ConstructionSite, res: StringName) -> String:
	var need: float = site.material().get(res, 0.0)
	var got: float = site.delivered.get(res, 0.0)
	if need <= 0.0:
		return ""
	if Defs.is_piece(res):
		return " · %d of %d" % [floori(got + 0.0001), roundi(need)]
	return " · %s of %s" % [Defs.format_kg(got).trim_suffix(" kg"), Defs.format_kg(need)]


func _running_detail(t: Task) -> String:
	var w := t.worker
	match t.kind:
		Task.Kind.FIELD:
			return "tile %d of %d" % [mini(w.strip_i + 1, t.cells.size()), t.cells.size()]
		Task.Kind.BUILD:
			return "%d %% built" % roundi(t.site.progress() * 100.0)
		Task.Kind.CHOP:
			return "clearing the site" if t.site else "felling"
		Task.Kind.CARRY:
			if w.carrying != &"":
				return "carrying %s" % Defs.format_goods(w.carrying, w.carry_amount)
			if w.phase == Worker.Phase.TO_TOOL:
				return "getting a wheelbarrow"
			return "fetching %s" % Defs.format_goods(t.fetch, t.fetch_amount)
		Task.Kind.TRIP, Task.Kind.HELP:
			return world.trip_status
		Task.Kind.PROCESS:
			return world.process_status(t.building)
	return ""


## The hops of a carry, one chip each: how a leg goes (walk / pickup), then where it ends.
## [[icon, state]], state "done" / "current" / "next"; a lone leg is walk → place.
func _chips(t: Task, running: bool) -> Array:
	var legs: Array[Dictionary] = t.plan
	var cur := t.leg_i
	if legs.size() < 2:
		legs = [{"by": &"walk", "from": t.src, "to": t.dst}]
		cur = 0
	var out := []
	for i in legs.size():
		var done := i < cur
		out.append(["pickup" if legs[i]["by"] == &"ride" else "walking",
			"done" if done else ("current" if i == cur and running else "next")])
		out.append([_place_icon(legs[i]["to"]), "done" if done else "next"])
	return out


static func _place_icon(s: Store) -> String:
	if s == null:
		return "house"
	match s.kind:
		Store.Kind.GROUND, Store.Kind.MOVE_PILE:
			return "pile"
		Store.Kind.DEALER:
			return "qk"
		Store.Kind.SITE:
			return "build"
		Store.Kind.GATE:
			return "field"
	return "house"


## "leg 2 of 3" for a chain, "one leg" for a lone carry.
static func _leg_text(t: Task) -> String:
	return "leg %d of %d" % [t.leg_i + 1, t.plan.size()] if t.plan.size() > 1 else "one leg"


## Each vehicle's trip as a collapsible group for the Tasks list (idle vehicles have none):
## {key, category, title, status, running, open, stops: [{n, state, text, sub}]}.
func _trips() -> Array:
	var previews := []
	for v in world.vehicles:
		var p := world.trip_preview(v)
		if p["state"] != &"idle":
			previews.append([v.id, v.trip.category if v.trip else Task.Category.TRANSPORT, p])
	for i in _sample_trips.size():
		previews.append([1000 + i, _sample_trips[i].get("category", Task.Category.TRANSPORT), _sample_trips[i]])
	var out := []
	for e: Array in previews:
		var p: Dictionary = e[2]
		var running: bool = p["state"] == &"running"
		if _filter == 2 or (_filter == 1 and running):
			continue
		var stops: Array = p["stops"]
		var status := "waiting for a driver"
		match p["state"]:
			&"running":
				status = "in progress · stop %d of %d" % [mini(int(p["stop_i"]) + 1, stops.size()), stops.size()]
			&"gathering":
				var s: float = p["starts_in"]
				status = "waiting · starts in ~%d s" % (ceili(s / 5.0) * 5) if s > 0.0 else ("waiting · starts now" if s == 0.0 else "waiting for more goods")
		var key := "trip:%d" % e[0]
		var rows := []
		for i in stops.size():
			var st: Dictionary = stops[i]
			rows.append({"n": i + 1, "state": String(st.get("state", &"next")), "text": _stop_text(st), "sub": _stop_sub(st, running)})
		out.append({"key": key, "category": e[1], "title": "Pickup trip · %d stop%s" % [stops.size(), "" if stops.size() == 1 else "s"],
			"status": status, "running": running, "open": _expanded.get(key, not running), "stops": rows})
	return out


## "Load 160 kg wheat · road pile by the forest", "Unload all · Storage Barn", "Dealer: sell 400 kg wheat".
static func _stop_text(st: Dictionary) -> String:
	var goods := _goods_text(st.get("goods", {}))
	match st.get("kind", &"load"):
		&"unload":
			return "Unload %s · %s" % [goods if goods != "" else "all", st.get("label", "")]
		&"dealer":
			var parts: Array[String] = []
			if goods != "":
				parts.append("sell " + goods)
			var buy := _goods_text(st.get("buy", {}))
			if buy != "":
				parts.append("buy " + buy)
			var hires: int = st.get("hires", 0)
			if hires > 0:
				parts.append("pick up %d new worker%s" % [hires, "" if hires == 1 else "s"])
			return "Dealer: " + ", ".join(parts) if not parts.is_empty() else "Dealer"
	return "Load %s · %s" % [goods if goods != "" else "goods", st.get("label", "")]


static func _goods_text(goods: Dictionary) -> String:
	var parts: Array[String] = []
	for res: StringName in goods:
		parts.append(Defs.format_goods(res, goods[res]))
	return ", ".join(parts)


## Under a stop: "done", "190 kg to go", "≈ 0:30 after start" (waiting trip) / "in ≈ 0:30" (running).
static func _stop_sub(st: Dictionary, running: bool) -> String:
	if st.has("note"):
		return st["note"]
	match st.get("state", &"next"):
		&"done":
			return "done"
		&"current":
			var left: float = st.get("left", 0.0)
			return "%s to go" % Defs.format_kg(left) if left > 0.0 else "here now"
	var eta: float = st.get("eta", -1.0)
	if eta < 0.0:
		return ""
	var clock := "%d:%02d" % [floori(eta / 60.0), floori(fmod(eta, 60.0))]
	if not running and eta < 1.0:
		return "right at the start"
	return "in ≈ %s" % clock if running else "≈ %s after start" % clock


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
	for t in _sample_tasks + world.tasks.tasks:
		# vehicle legs are shown in their trip's group, and so is a vehicle's own trip
		if t.kind == Task.Kind.RIDE:
			continue
		var in_group := t.kind == Task.Kind.TRIP and t.vehicle != null and t.vehicle.trip == t
		var g: Dictionary = cats[t.category]
		if t.worker != null:
			running += 1
			g["running"] += 1
			if _filter == 0 and not in_group:
				var walking := t.worker.phase != Worker.Phase.WORKING
				var row := {"state": "walking" if walking else "working", "title": _title(t, [t.row]),
					"detail": _running_detail(t), "worker": t.worker, "cell": t.cell, "count": 1}
				if t.kind == Task.Kind.CARRY:
					row["chips"] = _chips(t, true)
					if t.plan.size() > 1:
						row["detail"] = "%s · %s" % [_leg_text(t), row["detail"]]
				g["rows"].append(row)
			continue
		waiting += 1
		g["waiting"] += 1
		if in_group:
			continue
		var s := _stuck(t, short)
		var is_stuck := s.has("text")
		if is_stuck:
			stuck_n += 1
		if _filter == 2 and not is_stuck:
			continue
		var target: Variant = t.site if t.site else (t.field if t.field else t.building)
		# sites of one name (e.g. gravel road blocks) share a row; fields and buildings get their own
		var who: Variant = t.site.base_name() if t.site else (target.get_instance_id() if target else 0)
		if t.kind == Task.Kind.CARRY:
			who = "%s>%s" % [t.src.get_instance_id(), t.dst.get_instance_id()]
			for leg: Dictionary in t.plan:
				who += ">%s%s" % [leg["by"], (leg["to"] as Store).get_instance_id()]
			who += "@%d" % t.leg_i
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
		if t.kind == Task.Kind.CARRY:
			row["chips"] = _chips(t, false)
			if not is_stuck:
				row["detail"] = "%s · %s" % [detail, _leg_text(t)]
		g["groups"][key] = row
		g["rows"].append(row)
	# material sites still lack that nobody can bring (none to hand out): one row per kind of site
	var con: Dictionary = cats[Task.Category.CONSTRUCTION]
	for sn: Array in world.site_needs():
		var site: ConstructionSite = sn[0]
		var res: StringName = sn[1]
		if not short.has(res):
			continue
		var s := _need_stuck(res, short[res])
		var is_stuck := s.has("text")
		if _filter == 2 and not is_stuck:
			continue
		waiting += 1
		con["waiting"] += 1
		if is_stuck:
			stuck_n += 1
		var key := "need|%s|%s" % [res, site.base_name()]
		if con["groups"].has(key):
			con["groups"][key]["sites"][site] = true
			continue
		var row := {"state": "warning" if is_stuck else "idle", "need": [site, res], "detail": s.get("text", s.get("wait", "")),
			"bad": is_stuck, "fix": s.get("fix", ""), "arg": s.get("arg", &""), "cell": site.access, "count": 1,
			"res": res, "sites": {site: true}}
		con["groups"][key] = row
		con["rows"].append(row)
	for c: int in cats:
		for row: Dictionary in cats[c]["rows"]:
			if row.has("need"):
				var site: ConstructionSite = row["need"][0]
				var res: StringName = row["need"][1]
				var n: int = row["sites"].size()
				# "Bring planks to the Garage · 20 of 80", "Bring gravel · 3 sites"
				row["title"] = "Bring %s · %d sites" % [Defs.resource_name(res).to_lower(), n] if n > 1 else \
					"Bring %s to %s%s" % [Defs.resource_name(res).to_lower(), _the(site), _site_progress(site, res)]
				row.erase("need")
				row.erase("sites")
			elif row.has("task"):
				var t: Task = row["task"]
				var sites: int = row["sites"].size()
				row["title"] = _title(t, row["rows"], sites)
				if sites > 1:
					row["title"] += " · %d sites" % sites
				elif row["count"] > 1 and t.kind != Task.Kind.FIELD:
					row["title"] += " · ×%d" % row["count"]
				row.erase("sites")
				row.erase("task")
				row.erase("rows")
	return {"cats": cats, "trips": _trips(), "waiting": waiting, "running": running, "stuck": stuck_n}


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
	var sig := str(m["cats"]) + str(m["trips"])
	if sig == _sig:
		return
	_sig = sig
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var any := false
	for c: int in world.category_order:
		var g: Dictionary = m["cats"][c]
		if not (g["rows"] as Array).is_empty():
			any = true
			_list.add_child(_category_box(c, g))
		any = _add_trips(m["trips"], c) or any
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
	if r.has("chips"):
		text.add_child(_chip_row(r["chips"]))
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


## The hops of a carry as chips joined by arrows: done (green), current (blue, ringed), to come (faded).
func _chip_row(chips: Array) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", 4)
	m.add_theme_constant_override("margin_bottom", 3)
	m.add_theme_constant_override("margin_left", 3)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	m.add_child(row)
	for i in chips.size():
		if i > 0:
			var arrow := Label.new()
			arrow.text = "→"
			arrow.add_theme_font_override("font", UiStyle.body_font(true))
			arrow.add_theme_font_size_override("font_size", 14)
			arrow.add_theme_color_override("font_color", UiStyle.BOARD)
			arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(arrow)
		var state: String = chips[i][1]
		var colors: Array = {"done": [Color("#E3F0D4"), Color("#5E8F45")], "current": [Color("#DCEAF6"), UiStyle.SELECT]}.get(
			state, [UiStyle.PAPER, Color("#D2BF98")])
		var chip := PanelContainer.new()
		var sb := UiStyle.box(colors[0], colors[1], 8, 2)
		sb.set_content_margin_all(3)
		if state == "current":
			sb.shadow_color = Color("#CFE0F0")
			sb.shadow_size = 3
		chip.add_theme_stylebox_override("panel", sb)
		chip.custom_minimum_size = Vector2(28, 28)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := UiStyle.icon_rect(UiStyle.icon(chips[i][0]), 18)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if state == "next":
			ic.modulate.a = 0.55
		chip.add_child(ic)
		row.add_child(chip)
	return m


## The trip groups of category c, after its box. True when any was added.
func _add_trips(trips: Array, c: int) -> bool:
	var any := false
	for tr: Dictionary in trips:
		if tr["category"] == c:
			_list.add_child(_trip_box(tr))
			any = true
	return any


## A vehicle trip: a header that opens / closes it ("Pickup trip · 3 stops", state on the right)
## and, open, its numbered stops.
func _trip_box(tr: Dictionary) -> PanelContainer:
	var box := PanelContainer.new()
	var sb := UiStyle.box(Color("#FBF5E8"), Color("#E4D6BC"), UiStyle.RADIUS, 1)
	sb.set_content_margin_all(0)
	box.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	box.add_child(col)
	var open: bool = tr["open"]
	var head := PanelContainer.new()
	var hsb := UiStyle.box(UiStyle.PAPER_DEEP, Color.TRANSPARENT, 9)
	if open:
		hsb.corner_radius_bottom_left = 0
		hsb.corner_radius_bottom_right = 0
	hsb.content_margin_left = 10
	hsb.content_margin_right = 10
	hsb.content_margin_top = 5
	hsb.content_margin_bottom = 5
	head.add_theme_stylebox_override("panel", hsb)
	head.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	head.tooltip_text = "Hide the stops" if open else "Show the stops"
	var key: String = tr["key"]
	head.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_expanded[key] = not open
			_sig = ""
			refresh())
	col.add_child(head)
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 8)
	hrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(hrow)
	var arrow := Label.new()
	arrow.text = "▼" if open else "▶"
	arrow.add_theme_font_size_override("font_size", 12)
	arrow.custom_minimum_size.x = 16
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hrow.add_child(arrow)
	hrow.add_child(UiStyle.icon_rect(UiStyle.icon("pickup"), 22))
	var name := Label.new()
	name.text = tr["title"]
	name.add_theme_font_override("font", UiStyle.head_font(600))
	name.add_theme_font_size_override("font_size", 16)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hrow.add_child(name)
	var status := Label.new()
	status.text = tr["status"]
	status.add_theme_font_size_override("font_size", 13)
	status.add_theme_color_override("font_color", UiStyle.INK_SOFT)
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hrow.add_child(status)
	for c in hrow.get_children():
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not open:
		return box
	for st: Dictionary in tr["stops"]:
		col.add_child(_stop_row(st))
	var pad := Control.new()
	pad.custom_minimum_size.y = 6
	col.add_child(pad)
	return box


## One stop of a trip: number (✓ when done, blue when the pickup is there), what happens, when.
func _stop_row(st: Dictionary) -> MarginContainer:
	var state: String = st["state"]
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 8)
	m.add_theme_constant_override("margin_right", 8)
	m.add_theme_constant_override("margin_top", 2)
	m.add_theme_constant_override("margin_bottom", 2)
	var p := PanelContainer.new()
	var psb := UiStyle.box(Color("#DCEAF6") if state == "current" else Color.TRANSPARENT,
		Color("#3E7FB5") if state == "current" else Color.TRANSPARENT, 8, 1)
	psb.content_margin_left = 28
	psb.content_margin_right = 8
	psb.content_margin_top = 4
	psb.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", psb)
	p.custom_minimum_size.y = 40
	m.add_child(p)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	p.add_child(row)
	var colors: Array = {"done": [UiStyle.GO, Color("#36592A"), UiStyle.PAPER],
		"current": [UiStyle.SELECT, Color("#1F4E77"), UiStyle.PAPER]}.get(state, [UiStyle.PAPER, UiStyle.BOARD, UiStyle.INK])
	var num := PanelContainer.new()
	var nsb := UiStyle.box(colors[0], colors[1], 11, 2)
	nsb.set_content_margin_all(0)
	num.add_theme_stylebox_override("panel", nsb)
	num.custom_minimum_size = Vector2(22, 22)
	num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var nl := Label.new()
	nl.text = "✓" if state == "done" else str(st["n"])
	nl.add_theme_font_override("font", UiStyle.body_font(true))
	nl.add_theme_font_size_override("font_size", 12)
	nl.add_theme_color_override("font_color", colors[2])
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.add_child(nl)
	row.add_child(num)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 1)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(text)
	var t := Label.new()
	t.text = st["text"]
	t.add_theme_font_size_override("font_size", 14)
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.clip_text = true
	text.add_child(t)
	if st["sub"] != "":
		var s := Label.new()
		s.text = st["sub"]
		s.add_theme_font_size_override("font_size", 12)
		s.add_theme_color_override("font_color", UiStyle.INK_SOFT)
		text.add_child(s)
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


## --show=tasks_legs: sample chains (legs kept out of the queue) and two pickup trip previews, one
## running (collapsed) and one gathering (open; tasks_legs_open swaps them), rendered through the
## normal model and rows.
func debug_show(name: String, _game: Node) -> void:
	if name != "tasks_legs" and name != "tasks_legs_open":
		return
	var barn: Store = null
	for b: Building in world.buildings.values():
		if b.def_id == &"storage_barn" and b.store:
			barn = b.store
	if barn == null:
		barn = Store.new(Store.Kind.STORAGE)
	var c := Vector2i(world.size / 2, world.size / 2)
	var forest := Store.new(Store.Kind.GROUND, null, c)
	forest.origin = Store.Origin.FELLED
	var road1 := Store.new(Store.Kind.GROUND, null, c + Vector2i(4, 0))
	road1.origin = Store.Origin.ROAD
	var road2 := Store.new(Store.Kind.GROUND, null, c + Vector2i(20, 0))
	road2.origin = Store.Origin.ROAD
	var dealer := Store.new(Store.Kind.DEALER)
	# a felled log walking to a road pile, then the pickup to the barn (running)
	var a := _sample_leg(&"wood", 1.0, forest, road1)
	a.plan = [_sample_hop(&"walk", forest, road1), _sample_hop(&"ride", road1, barn)]
	for w in world.workers:
		if a.worker == null or w.carrying == &"":
			a.worker = w
	# Transport first, so the sample rows and trips are in view
	world.category_order.erase(Task.Category.TRANSPORT)
	world.category_order.push_front(Task.Category.TRANSPORT)
	# wheat on its last walk from a road pile (waiting)
	var b := _sample_leg(&"wheat", 40.0, road2, barn)
	b.plan = [_sample_hop(&"walk", forest, road1), _sample_hop(&"ride", road1, road2), _sample_hop(&"walk", road2, barn)]
	b.leg_i = 2
	# a lone carry (waiting)
	_sample_tasks = [a, b, _sample_leg(&"planks", 4.0, forest, barn)]
	if name == "tasks_legs_open":
		_expanded["trip:1000"] = true
		_expanded["trip:1001"] = false
	_sample_trips = [
		{"state": &"running", "stop_i": 1, "load": 310.0, "capacity": Defs.PICKUP_CAPACITY, "starts_in": -1.0, "stops": [
			_sample_stop(&"load", road1, "road pile by the forest", {&"wood": 3.0}, &"done", -1.0),
			_sample_stop(&"load", road2, "Wheat field gate", {&"wheat": 400.0}, &"current", 10.0, 190.0),
			_sample_stop(&"unload", barn, barn.label(), {&"wood": 3.0}, &"next", 50.0),
			_sample_stop(&"dealer", dealer, "Dealer", {&"wheat": 400.0}, &"next", 130.0)]},
		{"state": &"gathering", "stop_i": -1, "load": 0.0, "capacity": Defs.PICKUP_CAPACITY, "starts_in": 40.0, "stops": [
			_sample_stop(&"load", road1, "road pile by the forest", {&"wood": 4.0}, &"next", 0.0),
			_sample_stop(&"load", road2, "road pile by the east field", {&"potato": 260.0}, &"next", 30.0),
			_sample_stop(&"unload", barn, barn.label(), {}, &"next", 70.0)]}]
	position = Vector2(Hud.MARGIN, Hud.BELOW_BAR)
	show()
	_sig = ""
	refresh()


func _sample_leg(res: StringName, n: float, from: Store, to: Store) -> Task:
	var t := Task.new(Task.Kind.CARRY, to.cell, 0.0, world.time)
	t.category = Task.Category.TRANSPORT
	t.fetch = res
	t.fetch_amount = n
	t.src = from
	t.dst = to
	return t


static func _sample_hop(by: StringName, from: Store, to: Store) -> Dictionary:
	return {"by": by, "from": from, "to": to}


static func _sample_stop(kind: StringName, s: Store, label: String, goods: Dictionary, state: StringName, eta: float, left := 0.0) -> Dictionary:
	return {"kind": kind, "store": s, "label": label, "goods": goods, "buy": {}, "hires": 0, "money": 0,
		"state": state, "eta": eta, "left": left}
