class_name InfoPanel
extends PanelContainer
## Floating info about a selected field, building, construction site, road block, ground pile or worker
## (InfoStack places it beside the object): what it is doing, its goods, the crop choice of fields, priority, upgrades and
## demolition. The content is rebuilt only when its layout changes, values update every 0.25 s.

signal selection_changed
signal follow_requested(w: Worker)
signal priorities_requested
signal research_requested(id: StringName)
signal dealer_requested
signal gate_requested(f: Field)
signal open_requested(t: Variant)     # a link to another object (a worker on its way to a pile)

const WIDTH := 360.0
const PILE_WIDTH := 390.0     # a ground pile: room for where it lies beside the title
const TRACK := Color("#EFE4CE")           # bar background
const TRACK_EDGE := Color("#D2BF98")
const WAITING := Color("#E8D3AE")         # material on its way or available (striped)
const RIPE := Color("#C98F2A")
const CROP_SELECTED := Color("#EAF2FA")
const GOING_EDGE := Color("#3E7FB5")       # ground pile: a worker is on the way
const WAIT_PAPER := Color("#FBEFC9")       # ground pile: the leg waits for a free hand
const WAIT_EDGE := Color("#D9A21F")

var world: World
var target: Variant = null      # Building, Worker, Store (ground pile) or Vector2i (road block anchor)
var _panel: Dictionary          # UiStyle.make_panel parts
var _head_icon: TextureRect
var _body: VBoxContainer
var _key := ""                  # layout of the current content; a change rebuilds it
var _ui := {}                   # widgets that refresh() updates
var _action: Button             # demolish / cancel (Delete key), null when there is none
var _armed := false             # demolish needs a second click
var _accum := 0.0
var _row_styles := {}           # row strip state -> StyleBoxFlat
var _name_box: HBoxContainer    # header: name button and pencil (workers and finished buildings rename)
var _name_btn: Button
var _name_on: StyleBoxFlat      # name highlight on hover
var _name_off: StyleBox
var _name_col: VBoxContainer
var _subtitle: Label            # default name under a custom one
var _pencil: Button
var _name_edit: LineEdit
var _edit_parts: Array[Control] = []   # shown while editing the name: field, ✓, ×, hint row
var _hint_text: RichTextLabel
var _hint_count: Label
var _hover_forced := false      # --show: draw the hover state
var _pile_where: Label            # ground pile: where it lies, beside the title


func setup(p_world: World) -> void:
	world = p_world
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_panel = UiStyle.make_panel("", "house")
	add_child(_panel["root"])
	(_panel["root"] as Control).custom_minimum_size.x = WIDTH
	_head_icon = (_panel["header"] as HBoxContainer).get_child(0)
	_build_rename()
	_body = _panel["body"]
	(_panel["close"] as Button).pressed.connect(clear)
	_row_styles = {
		"growing": UiStyle.box(UiStyle.WHEAT, Color.TRANSPARENT, 4),
		"ripe": UiStyle.box(RIPE, Color.TRANSPARENT, 4),
		"worked": UiStyle.box(UiStyle.PAPER, UiStyle.GO, 4, 2),
		"soil": UiStyle.box(UiStyle.BOARD, Color.TRANSPARENT, 4),
	}

	world.building_removed.connect(func(b: Building) -> void:
		if target == b:
			clear())
	world.worker_removed.connect(func(w: Worker) -> void:
		if target == w:
			clear())
	world.road_changed.connect(func(a: Vector2i) -> void:
		if target is Vector2i and target == a and not world.road_blocks.has(a):
			clear())
	world.building_renamed.connect(func(b: Building) -> void:
		if target == b or (target is ConstructionSite and (target as ConstructionSite).upgrade_of == b):
			refresh())
	world.pile_removed.connect(func(s: Store) -> void:
		if target == s:
			clear())
	_build_pile_where()
	hide()


func select(t: Variant) -> void:
	target = t
	_armed = false
	_key = ""
	visible = t != null
	refresh()
	selection_changed.emit()


func clear() -> void:
	select(null)


## The header bar: the panel is dragged by it.
func header() -> Control:
	return (_panel["header"] as Control).get_parent()


## Demolish / cancel (Delete key or the button); the first press only asks for confirmation.
func press_action() -> void:
	if not visible or _action == null or _action.disabled:
		return
	if not _armed:
		_armed = true
		refresh()
		return
	if target is Building:
		world.demolish(target)
	elif target is Vector2i:
		world.demolish_road(target)
	clear()


func _process(delta: float) -> void:
	if not visible:
		return
	_update_hover()
	_accum += delta
	if _accum > 0.25:
		_accum = 0.0
		refresh()


func refresh() -> void:
	if target == null:
		return
	var key := _layout_key()
	if key != _key:
		_key = key
		_rebuild()
	if target is Field:
		_update_field(target)
	elif target is ConstructionSite:
		_update_site(target)
	elif target is Building:
		_update_building(target)
	elif target is Worker:
		_update_worker(target)
	elif target is Store:
		_update_pile(target)
	_fit_title()
	reset_size()


## Everything that changes which widgets the panel shows (not their values).
func _layout_key() -> String:
	var parts := [_armed]
	if target is Field:
		var f := target as Field
		parts.append_array(["field", f.id, f.next_crop, f.crop, f.priority, f.size, world.demolish_blocker(f)])
	elif target is ConstructionSite:
		var s := target as ConstructionSite
		parts.append_array(["site", s.id, s.stage, s.priority, _site_missing(s).keys(), s.base_name()])
	elif target is Building:
		var b := target as Building
		parts.append_array(["building", b.id, b.level, b.priority, world.upgrade_blocker(b), world.demolish_blocker(b),
			b.upgrading.stage if b.upgrading else -1, b.custom_name, b.number])
		if Defs.def(b.def_id).get("storage", false):
			parts.append(_stored().keys())
	elif target is Worker:
		parts.append_array(["worker", (target as Worker).id, _worker_name(target)])
	elif target is Vector2i:
		parts.append_array(["road", target, world.road_blocks.get(target, &""), world.road_blocker(target)])
	elif target is Store:
		var s := target as Store
		parts.append_array(["pile", s.get_instance_id(), s.contents.keys(), _pile_leg(s)["state"], s.origin])
	return str(parts)


func _rebuild() -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	_ui.clear()
	_action = null
	(_panel["badge"] as Label).visible = false
	_subtitle.visible = false
	_end_rename(false)
	if target is Field:
		_build_field(target)
	elif target is ConstructionSite:
		_build_site(target)
	elif target is Building:
		_build_building(target)
	elif target is Worker:
		_build_worker(target)
	elif target is Vector2i:
		_build_road(target)
	elif target is Store:
		_build_pile(target)
	_pile_where.visible = target is Store
	(_panel["root"] as Control).custom_minimum_size.x = PILE_WIDTH if target is Store else WIDTH


func _set_header(title: String, icon_name: String, badge := "") -> void:
	(_panel["title"] as Label).text = title
	_head_icon.texture = UiStyle.icon(icon_name)
	var b: Label = _panel["badge"]
	b.text = badge
	b.visible = badge != ""


# --- processing and other buildings ---------------------------------------------------

func _build_building(b: Building) -> void:
	var d := Defs.def(b.def_id)
	_set_header(b.display_name(), "house", "Level %d" % b.level if d.has("upgrade") else "")
	_subtitle.text = b.default_name()
	_subtitle.visible = b.custom_name != ""
	if not b.recipe().is_empty():
		_build_process(b)
	elif d.get("storage", false):
		_build_storage()
	for v in world.vehicles:
		if v.garage == b:
			_ui["trip"] = _add(UiStyle.status_line())
			break
	if b.def_id == &"dealer":
		_add(_text("The Dealer buys your harvest and sells seeds, materials and equipment.", "SoftLabel"))
		var open := _add(_content_button("PrimaryButton", ["Open the Dealer"]))
		open.pressed.connect(dealer_requested.emit)
		return
	_add_action("Demolish (%s)" % _refund_text(b.paid, b.materials), world.demolish_blocker(b))


func _build_process(b: Building) -> void:
	var r := b.recipe()
	var rin: StringName = r["in"]
	var rout: StringName = r["out"]
	_ui["status"] = _add(UiStyle.status_line())

	var well := _add(_well()) as PanelContainer
	var col := _vbox(6)
	well.add_child(col)
	col.add_child(_text("%s → %s" % [Defs.resource_name(rin).to_upper(), Defs.resource_name(rout).to_upper()], "SectionLabel"))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	col.add_child(line)
	line.add_child(UiStyle.icon_rect(UiStyle.resource_icon(rin), 22))
	line.add_child(_text(Defs.format_amount(rin, r["batch"]), "NumberLabel"))
	var arrow := _text("→")
	arrow.add_theme_color_override("font_color", UiStyle.WOOD)
	line.add_child(arrow)
	line.add_child(UiStyle.icon_rect(UiStyle.resource_icon(rout), 22))
	line.add_child(_text(Defs.format_amount(rout, r["batch"] * r["yield"]), "NumberLabel"))
	line.add_child(_spacer())
	line.add_child(UiStyle.icon_rect(UiStyle.icon("clock"), 18))
	line.add_child(_text("%d s" % roundi(r["work"]), "NumberLabel"))
	var pb := UiStyle.bar(UiStyle.GO, 10)
	pb.add_theme_stylebox_override("background", UiStyle.box(UiStyle.PAPER, TRACK_EDGE, 5, 1))
	col.add_child(pb)
	_ui["batch_bar"] = pb
	var bt := _text("", "SmallLabel")
	col.add_child(bt)
	_ui["batch_text"] = bt

	_ui["inside"] = _meter(UiStyle.resource_icon(rin), "Inside")
	_ui["made"] = _meter(UiStyle.resource_icon(rout), "Made")
	_add_priority(b)
	_build_upgrade(b)


func _update_building(b: Building) -> void:
	if _ui.has("trip"):
		var idle := world.trip_status == "In the garage"
		UiStyle.set_status(_ui["trip"], "idle" if idle else "walking", "[b]Light Pickup:[/b] %s" % world.trip_status)
	if _ui.has("stored"):
		var stored := _stored()
		for res: StringName in _ui["stored"]:
			(_ui["stored"][res] as Label).text = Defs.format_amount(res, stored.get(res, 0.0))
	if _action:
		_set_action_text("Demolish (%s)" % _refund_text(b.paid, b.materials))
	if not _ui.has("status"):
		return
	var r := b.recipe()
	var rin: StringName = r["in"]
	var rout: StringName = r["out"]
	var st := _process_status(b)
	UiStyle.set_status(_ui["status"], st[0], st[1])

	var t := b.process_task
	if t and t.worker and t.worker.phase == Worker.Phase.WORKING and t.work > 0.0:
		(_ui["batch_bar"] as ProgressBar).value = clampf(t.worker.work_timer / t.work, 0.0, 1.0)
		(_ui["batch_text"] as Label).text = "This batch: %d s of %d s" % [floori(t.worker.work_timer), roundi(t.work)]
	else:
		(_ui["batch_bar"] as ProgressBar).value = 0.0
		(_ui["batch_text"] as Label).text = "No batch running"

	var inside: Dictionary = _ui["inside"]
	inside["value"].text = Defs.format_amount(rin, b.input)
	inside["right"].text = "room for %s" % Defs.format_amount(rin, r["in_cap"])
	inside["bar"].value = b.input / float(r["in_cap"])
	var made: Dictionary = _ui["made"]
	made["value"].text = Defs.format_amount(rout, b.output)
	made["bar"].value = b.output / float(r["out_cap"])
	var full := b.output >= float(r["out_cap"]) - 0.0001
	var no_room := b.output + float(r["batch"]) * float(r["yield"]) > float(r["out_cap"]) + 0.0001
	if full or no_room:
		made["right"].text = "full" if full else "no room for a batch"
		made["right"].add_theme_color_override("font_color", UiStyle.SHORT)
		UiStyle.set_bar_color(made["bar"], UiStyle.WARN)
	else:
		made["right"].text = "room for %s" % Defs.format_amount(rout, r["out_cap"])
		made["right"].remove_theme_color_override("font_color")
		UiStyle.set_bar_color(made["bar"], UiStyle.BOARD)

	var up := b.upgrading
	if up and _ui.has("up_text"):
		if up.stage == ConstructionSite.Stage.BUILDING:
			(_ui["up_text"] as RichTextLabel).text = "Rebuilding: [b]%d %%[/b]" % roundi(up.progress() * 100.0)
			(_ui["up_bar"] as ProgressBar).value = up.progress()
		else:
			var need: float = up.material().get(&"planks", 0.0)
			var got: float = up.delivered.get(&"planks", 0.0)
			(_ui["up_text"] as RichTextLabel).text = "Bringing planks: [b]%d of %d[/b] [color=#%s](available: %d)[/color]" % [
				got, need, UiStyle.INK_SOFT.to_html(false), _free(up, &"planks")]
			(_ui["up_bar"] as ProgressBar).value = got / need if need > 0.0 else 1.0
		(_ui["up_cancel"] as Button).text = "Cancel the upgrade (%s)" % _refund_text(0, up.delivered)


## [status kind, bbcode] of a processing building.
func _process_status(b: Building) -> Array:
	var s := world.process_status(b)
	var t := b.process_task
	if b.upgrading:
		return ["walking", "[b]Upgrading[/b] to level %d · not working meanwhile" % (b.level + 1)]
	if s == "Working":
		return ["working", "[b]Working[/b] · 1 worker at it"]
	if s == "Waiting for a worker":
		if t and t.worker:
			return ["walking", "[b]Starting[/b] · a worker is on the way"]
		return ["idle", "[b]Waiting[/b] for a free worker"]
	if s.begins_with("Halted"):
		return ["halted", _bold_head(s)]
	return ["idle", _bold_head(s)]


## Level upgrade: the running upgrade, the upgrade button, or why it is locked.
func _build_upgrade(b: Building) -> void:
	var d := Defs.def(b.def_id)
	if not d.has("upgrade"):
		return
	if b.upgrading:
		var box := _add(_vbox(6))
		var rt := _rich()
		box.add_child(rt)
		_ui["up_text"] = rt
		var pb := UiStyle.bar(UiStyle.BOARD if b.upgrading.stage != ConstructionSite.Stage.BUILDING else UiStyle.GO, 12)
		box.add_child(pb)
		_ui["up_bar"] = pb
		var cancel := Button.new()
		cancel.focus_mode = Control.FOCUS_NONE
		cancel.pressed.connect(_on_upgrade)
		_add(cancel)
		_ui["up_cancel"] = cancel
		return
	if b.level >= 3:
		_add(_text("Highest level", "SmallLabel"))
		return
	var blocker := world.upgrade_blocker(b)
	var cost: float = d["upgrade"][b.level + 1]
	var box := _add(_vbox(6))
	if blocker == "":
		var btn := _content_button("PrimaryButton", ["↑ Upgrade to level %d · %d" % [b.level + 1, cost], UiStyle.icon("planks")])
		btn.pressed.connect(_on_upgrade)
		box.add_child(btn)
		return
	var locked := _content_button("Button", [UiStyle.icon("locked"), "Upgrade to level %d · %d planks" % [b.level + 1, cost]], UiStyle.LOCKED_TEXT)
	locked.disabled = true
	box.add_child(locked)
	var node := Tech.node_for_level(b.def_id, b.level + 1)
	if node != &"" and not world.is_unlocked(node):
		var link := LinkButton.new()
		link.text = "Unlock %s in research" % Tech.node(node)["name"]
		link.underline = LinkButton.UNDERLINE_MODE_ALWAYS
		link.focus_mode = Control.FOCUS_NONE
		link.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		link.add_theme_color_override("font_color", UiStyle.SELECT)
		link.add_theme_color_override("font_hover_color", UiStyle.SELECT.darkened(0.25))
		link.add_theme_color_override("font_pressed_color", UiStyle.SELECT.darkened(0.25))
		link.add_theme_font_size_override("font_size", 14)
		link.pressed.connect(func() -> void: research_requested.emit(node))
		box.add_child(link)
	else:
		box.add_child(_text(blocker, "SmallLabel", true))


func _on_upgrade() -> void:
	var b := target as Building
	if b == null:
		return
	if b.upgrading:
		world.demolish(b.upgrading)
	else:
		world.start_upgrade(b)
	refresh()


## This barn's own store: everything in it (amount > 0), resource -> amount.
func _stored() -> Dictionary:
	var out := {}
	var store := (target as Building).store
	for res: StringName in store.contents:
		if store.contents[res] > 0.0001:
			out[res] = store.contents[res]
	return out


func _build_storage() -> void:
	_add(_text("STORED", "SectionLabel"))
	var stored := _stored()
	if stored.is_empty():
		_add(_text("Nothing stored yet", "SoftLabel"))
		return
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	_add(grid)
	_ui["stored"] = {}
	for res: StringName in stored:
		var chip := PanelContainer.new()
		chip.theme_type_variation = "Chip"
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(chip)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		chip.add_child(row)
		row.add_child(UiStyle.icon_rect(UiStyle.resource_icon(res), 20))
		var name_l := _text(Defs.resource_name(res), "SmallLabel")
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.clip_text = true
		name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(name_l)
		var amount := _text("", "NumberLabel")
		amount.add_theme_font_size_override("font_size", 14)
		row.add_child(amount)
		_ui["stored"][res] = amount


# --- construction sites --------------------------------------------------------------------

## Material a site still lacks beyond what is on site, on the way and free to be brought, resource -> amount.
func _site_missing(s: ConstructionSite) -> Dictionary:
	var out := {}
	if s.stage == ConstructionSite.Stage.BUILDING:
		return out
	var mat := s.material()
	for res: StringName in mat:
		var missing: float = mat[res] - s.delivered.get(res, 0.0) - _in_transit(s, res) - _free(s, res)
		if missing > 0.0001:
			out[res] = missing
	return out


## Material on its way to the site: what carry legs have promised to bring.
func _in_transit(s: ConstructionSite, res: StringName) -> float:
	return s.supply.reserved_in.get(res, 0.0)


## Material not promised to anyone yet that could be brought: in barns, mill outputs, gate and
## ground piles (World.available), and a moved building's own pile.
func _free(s: ConstructionSite, res: StringName) -> float:
	return world.available(res) + (s.pile_store.available(res) if s.moved else 0.0)


func _build_site(s: ConstructionSite) -> void:
	var name := s.base_name()
	if s.upgrade_of:
		_set_header(name, "upgrade", "Upgrade to level %d" % (s.upgrade_of.level + 1))
	else:
		_set_header(name, "plan", "Building site")
	match s.stage:
		ConstructionSite.Stage.CLEARING:
			_ui["stage_text"] = _add(_rich())
		ConstructionSite.Stage.DELIVERY:
			_ui["deliveries"] = {}
			for res: StringName in s.material():
				var box := _add(_vbox(6))
				var rt := _rich()
				box.add_child(rt)
				var bar := TwoPartBar.new()
				box.add_child(bar)
				box.add_child(_legend([[UiStyle.BOARD, "on site"], [WAITING, "available"]]))
				_ui["deliveries"][res] = [rt, bar]
			var missing := _site_missing(s)
			for res: StringName in missing:
				_ui["missing_" + String(res)] = _warning_card(res)
		ConstructionSite.Stage.BUILDING:
			var box := _add(_vbox(6))
			var rt := _rich()
			box.add_child(rt)
			_ui["stage_text"] = rt
			var pb := UiStyle.bar(UiStyle.GO, 12)
			box.add_child(pb)
			_ui["build_bar"] = pb

	var workers := HBoxContainer.new()
	workers.add_theme_constant_override("separation", 6)
	workers.mouse_filter = Control.MOUSE_FILTER_STOP
	_add(workers)
	workers.add_child(_text("Workers here", "SoftLabel"))
	workers.add_child(_spacer())
	var icons := HBoxContainer.new()
	icons.add_theme_constant_override("separation", 2)
	workers.add_child(icons)
	_ui["worker_icons"] = icons
	var count := _text("", "NumberLabel")
	workers.add_child(count)
	_ui["worker_count"] = count
	_add_priority(s)
	_add_action("Cancel (%s)" % _refund_text(s.paid, s.delivered), "")


## "25 planks still missing — buy them at the Dealer / make them at a Sawmill" with a Dealer button.
func _warning_card(res: StringName) -> RichTextLabel:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.WARN_PAPER, UiStyle.WARN, UiStyle.RADIUS, 2))
	_add(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var ic := UiStyle.icon_rect(UiStyle.icon("warning"), 20)
	row.add_child(ic)
	var rt := _rich()
	rt.add_theme_font_size_override("normal_font_size", 14)
	rt.add_theme_font_size_override("bold_font_size", 14)
	row.add_child(rt)
	if Defs.buyable(res) and world.item_unlocked(res):
		var b := Button.new()
		b.text = "Dealer"
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(dealer_requested.emit)
		row.add_child(b)
	return rt


## Where the player can get more of a building material.
func _material_source(res: StringName) -> String:
	var ways := PackedStringArray()
	if Defs.buyable(res) and world.item_unlocked(res):
		ways.append("buy them at the Dealer" if Defs.is_piece(res) else "buy it at the Dealer")
	for id: StringName in Defs.BUILDINGS:
		var p: Dictionary = Defs.BUILDINGS[id].get("process", {})
		if p.get("out", &"") == res:
			ways.append("make them at a %s" % Defs.BUILDINGS[id]["name"])
			break
	return " / ".join(ways)


func _update_site(s: ConstructionSite) -> void:
	match s.stage:
		ConstructionSite.Stage.CLEARING:
			var trees := 0
			for t in s.open_tasks:
				if t.kind == Task.Kind.CHOP:
					trees += 1
			(_ui["stage_text"] as RichTextLabel).text = "Clearing the ground: [b]%d tree%s[/b] left to chop" % [trees, "" if trees == 1 else "s"]
		ConstructionSite.Stage.DELIVERY:
			var mat := s.material()
			var soft := UiStyle.INK_SOFT.to_html(false)
			for res: StringName in _ui.get("deliveries", {}):
				var need: float = mat[res]
				var got: float = s.delivered.get(res, 0.0)
				var free := _free(s, res)
				var parts: Array = _ui["deliveries"][res]
				(parts[0] as RichTextLabel).text = "Bringing %s: [b]%s of %s[/b] [color=#%s](available: %s)[/color]" % [
					Defs.resource_name(res).to_lower(), _num(res, got), _num(res, need), soft, _num(res, free)]
				(parts[1] as TwoPartBar).set_parts(got / need, (_in_transit(s, res) + free) / need)
			var missing := _site_missing(s)
			for res: StringName in missing:
				var rt: RichTextLabel = _ui.get("missing_" + String(res))
				if rt:
					var src := _material_source(res)
					rt.text = "[b]%s[/b] still missing%s" % [Defs.format_goods(res, ceilf(missing[res]) if Defs.is_piece(res) else missing[res]),
						" — " + src if src != "" else ""]
		ConstructionSite.Stage.BUILDING:
			(_ui["stage_text"] as RichTextLabel).text = "Building: [b]%d %%[/b]" % roundi(s.progress() * 100.0)
			(_ui["build_bar"] as ProgressBar).value = s.progress()
	var n := 0
	var names := PackedStringArray()
	for w in world.workers:
		if w.task and w.task.site == s:
			n += 1
			names.append(_worker_title(w).trim_prefix("Worker · "))
	var icons: HBoxContainer = _ui["worker_icons"]
	(icons.get_parent() as Control).tooltip_text = ", ".join(names)
	var shown := mini(n, 4)
	if icons.get_child_count() != shown:
		for c in icons.get_children():
			icons.remove_child(c)
			c.queue_free()
		for i in shown:
			icons.add_child(UiStyle.icon_rect(UiStyle.icon("worker"), 24))
	(_ui["worker_count"] as Label).text = str(n)
	if _action:
		_set_action_text("Cancel (%s)" % _refund_text(s.paid, s.delivered))


## Amount without the unit for pieces ("20"), with it for kg ("300 kg").
func _num(res: StringName, amount: float) -> String:
	return "%d" % floori(amount + 0.0001) if Defs.is_piece(res) else Defs.format_kg(amount)


# --- fields ------------------------------------------------------------------------------

func _build_field(f: Field) -> void:
	_set_header("Field", "field", "%d tiles" % (f.size.x * f.size.y))
	_add(_text("CROP", "SectionLabel"))
	var crops := HBoxContainer.new()
	crops.add_theme_constant_override("separation", 8)
	_add(crops)
	for c: StringName in Defs.CROPS:
		crops.add_child(_crop_tile(c, c == f.next_crop))
	if f.next_crop != f.crop:
		_add(_text("Switching to %s once the %s is harvested and carried away" % [
			String(Defs.CROPS[f.next_crop]["name"]).to_lower(), String(Defs.CROPS[f.crop]["name"]).to_lower()], "SmallLabel", true))

	var rows := _add(_vbox(6))
	var head := HBoxContainer.new()
	rows.add_child(head)
	var left := _rich()
	left.add_theme_font_size_override("normal_font_size", 14)
	left.add_theme_font_size_override("bold_font_size", 14)
	head.add_child(left)
	var right := _text("", "SmallLabel")
	head.add_child(right)
	_ui["field_left"] = left
	_ui["field_right"] = right
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 4)
	rows.add_child(strip)
	for r in f.size.y:
		var seg := Panel.new()
		seg.custom_minimum_size.y = 14
		seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		strip.add_child(seg)
	_ui["strip"] = strip
	rows.add_child(_legend([[UiStyle.WHEAT, "growing"], [RIPE, "ripe"], [UiStyle.GO, "being worked", true], [UiStyle.BOARD, "bare soil"]]))

	var gate := _add(_well()) as PanelContainer
	var g := HBoxContainer.new()
	g.add_theme_constant_override("separation", 8)
	gate.add_child(g)
	g.add_child(_text("Gate", "SoftLabel"))
	g.add_child(_text("%s side" % _gate_side(f), "NumberLabel"))
	g.add_child(_spacer())
	var pile := _text("", "SmallLabel")
	g.add_child(pile)
	_ui["pile"] = pile
	var move := Button.new()
	move.text = "Move gate"
	move.focus_mode = Control.FOCUS_NONE
	move.add_theme_font_size_override("font_size", 14)
	move.pressed.connect(func() -> void: gate_requested.emit(f))
	g.add_child(move)
	var info := _text("", "SmallLabel", true)
	_add(info)
	_ui["field_info"] = info
	_add_priority(f)
	_add_action("Demolish field (refund %s, crops are lost)" % Defs.format_money(f.paid), world.demolish_blocker(f))


func _crop_tile(c: StringName, selected: bool) -> Button:
	var b := Button.new()
	b.text = Defs.CROPS[c]["name"]
	b.icon = UiStyle.resource_icon(c)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 74)
	b.add_theme_constant_override("icon_max_width", 32)
	b.add_theme_font_size_override("font_size", 14)
	b.tooltip_text = "Sow %s next" % String(Defs.CROPS[c]["name"]).to_lower()
	var fill := CROP_SELECTED if selected else UiStyle.PAPER
	var edge := UiStyle.SELECT if selected else UiStyle.BOARD
	var normal := UiStyle.box(fill, edge, UiStyle.RADIUS, 2, 2)
	normal.content_margin_left = 4
	normal.content_margin_right = 4
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = fill if selected else Color("#F6EBD3")
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.pressed.connect(func() -> void:
		if target is Field:
			world.set_field_crop(target, c)
			refresh())
	return b


## Compass side of the field's gate (grid -y is north).
func _gate_side(f: Field) -> String:
	var r := f.rect()
	if f.access.y < r.position.y:
		return "north"
	if f.access.y >= r.end.y:
		return "south"
	return "west" if f.access.x < r.position.x else "east"


func _update_field(f: Field) -> void:
	var crop: Dictionary = Defs.CROPS[f.crop]
	var worked := {}
	var verb := ""
	var verb_row := -1
	for r in f.size.y:
		var t: Task = f.row_task[r]
		if t and t.worker and t.worker.phase == Worker.Phase.WORKING:
			worked[r] = true
			if verb == "":
				verb = {&"cultivate": "Cultivating", &"seed": "Planting", &"harvest": "Harvesting"}.get(t.step, "Working")
				verb_row = r
	var counts := [0, 0, 0, 0]
	for r in f.size.y:
		counts[f.row_step[r]] += 1
	var left := ""
	if verb != "":
		left = "[b]%s[/b] row %d of %d" % [verb, verb_row + 1, f.size.y]
		if worked.size() > 1:
			left += " (+%d)" % (worked.size() - 1)
	elif counts[Field.RowStep.HARVEST] > 0:
		left = "[b]Ripe[/b] · %d row%s to harvest" % [counts[Field.RowStep.HARVEST], _s(counts[Field.RowStep.HARVEST])]
	elif counts[Field.RowStep.SEED] > 0:
		left = "[b]To plant[/b] · %d row%s" % [counts[Field.RowStep.SEED], _s(counts[Field.RowStep.SEED])]
	elif counts[Field.RowStep.CULTIVATE] > 0:
		left = "[b]To cultivate[/b] · %d row%s" % [counts[Field.RowStep.CULTIVATE], _s(counts[Field.RowStep.CULTIVATE])]
	else:
		left = "[b]Growing[/b] · %d row%s" % [counts[Field.RowStep.GROW], _s(counts[Field.RowStep.GROW])]
	(_ui["field_left"] as RichTextLabel).text = left

	# the sown tiles are all ripe once the least grown one is
	var least := 2.0
	for i in f.tile_state.size():
		if f.tile_state[i] == Field.TileState.PLANTED:
			least = minf(least, f.growth[i])
	var right := ""
	if least < 1.0:
		var secs := (1.0 - least) * float(crop["grow_time"])
		right = "ready in about %s" % ("%d min" % maxi(1, roundi(secs / 60.0)) if secs >= 60.0 else "%d s" % ceili(secs))
	(_ui["field_right"] as Label).text = right

	var strip: HBoxContainer = _ui["strip"]
	for r in mini(f.size.y, strip.get_child_count()):
		var state := "soil"
		if worked.has(r):
			state = "worked"
		elif f.row_step[r] == Field.RowStep.HARVEST:
			state = "ripe"
		elif f.row_step[r] == Field.RowStep.GROW:
			state = "growing"
		var seg := strip.get_child(r) as Panel
		if seg.get_meta("state", "") != state:
			seg.set_meta("state", state)
			seg.add_theme_stylebox_override("panel", _row_styles[state])

	(_ui["pile"] as Label).text = "%s waiting" % Defs.format_goods(f.crop, f.pile) if f.pile > 0.01 else ""
	var tiles := f.size.x * f.size.y
	var harvest: float = tiles * float(crop["yield"])
	(_ui["field_info"] as Label).text = "Seed per sowing %s (in the barn %s) · full harvest about %s" % [
		Defs.format_kg(tiles * Defs.seed_per_tile(f.crop)), Defs.format_kg(world.total(Defs.seed_of(f.crop))),
		Defs.format_kg(harvest)]


func _s(n: int) -> String:
	return "" if n == 1 else "s"


# --- workers ---------------------------------------------------------------------------

func _build_worker(w: Worker) -> void:
	_set_header(_worker_title(w), "worker")
	_ui["status"] = _add(UiStyle.status_line())
	var rows := _add(_vbox(6))
	for key in ["Carries", "With", "Task"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		rows.add_child(row)
		var cap := _text(key, "SoftLabel")
		cap.custom_minimum_size.x = 72
		row.add_child(cap)
		var ic := UiStyle.icon_rect(null, 20)
		row.add_child(ic)
		var rt := _rich()
		row.add_child(rt)
		_ui["row_" + key] = [ic, rt]
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	_add(buttons)
	var follow := Button.new()
	follow.text = "Follow"
	follow.focus_mode = Control.FOCUS_NONE
	follow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	follow.pressed.connect(func() -> void:
		if target is Worker:
			follow_requested.emit(target))
	buttons.add_child(follow)
	var prio := Button.new()
	prio.text = "Priorities"
	prio.focus_mode = Control.FOCUS_NONE
	prio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prio.pressed.connect(priorities_requested.emit)
	buttons.add_child(prio)


func _update_worker(w: Worker) -> void:
	var st := _worker_status(w)
	UiStyle.set_status(_ui["status"], st[0], st[1])
	var carries: Array = _ui["row_Carries"]
	if w.carrying != &"":
		carries[0].texture = UiStyle.resource_icon(w.carrying)
		carries[1].text = "[b]%s[/b]" % Defs.format_goods(w.carrying, w.carry_amount)
	else:
		carries[0].texture = null
		carries[1].text = "nothing"
	var with: Array = _ui["row_With"]
	if w.equipment == &"wheelbarrow":
		with[0].texture = UiStyle.icon("wheelbarrow")
		with[1].text = "Wheelbarrow · up to [b]%d kg[/b]" % Defs.WHEELBARROW_CAPACITY
	else:
		with[0].texture = null
		with[1].text = "bare hands · up to [b]%d kg[/b]" % Defs.CARRY_CAPACITY
	var task: Array = _ui["row_Task"]
	task[0].texture = null
	if w.task:
		var cat: Array = Task.CATEGORY_NAMES.get(w.task.category, [""])
		task[1].text = "%s · %s" % [cat[0], w.task.label()] if cat[0] != "" else w.task.label()
	else:
		task[1].text = "none"


## [status kind, bbcode] of a worker.
func _worker_status(w: Worker) -> Array:
	if w.in_vehicle:
		if w.task:
			return ["working", "[b]Driving[/b] the pickup · %s" % world.trip_status]
		return ["walking", "[b]Riding[/b] in the pickup"]
	match w.phase:
		Worker.Phase.IDLE:
			return ["idle", "[b]Idle[/b] · waiting for work"]
		Worker.Phase.TO_TOOL:
			return ["walking", "[b]Getting[/b] a wheelbarrow from %s" % (_the(w.task.tool_from) if w.task.tool_from else "the barn")]
		Worker.Phase.TO_FETCH:
			if w.task.kind == Task.Kind.CARRY:
				return ["walking", "[b]Fetching[/b] %s from %s" % [Defs.resource_name(w.task.fetch).to_lower(), _the(w.task.src)]]
			return ["walking", "[b]Fetching[/b] %s from the barn" % Defs.resource_name(w.task.fetch).to_lower()]
		Worker.Phase.TO_TASK:
			return ["walking", "[b]Walking[/b] to: %s" % _lower_first(w.task.label())]
		Worker.Phase.WORKING:
			return ["working", "[b]Working[/b] · %s" % _lower_first(w.task.label())]
		Worker.Phase.TO_DELIVER:
			return ["walking", "[b]Walking[/b] to %s" % _delivery_place(w)]
	return ["idle", ""]



## Where a worker brings back what it carries: "North Barn", "the Storage Barn".
func _delivery_place(w: Worker) -> String:
	if not w.path.is_empty():
		for b: Building in world.buildings.values():
			if b.store and b.access == w.path.back() and Defs.def(b.def_id).get("storage", false):
				return _the(b.store)
	return "the barn"


## "the Storage Barn", "the ground pile"; a place with a name of its own goes without "the".
static func _the(s: Store) -> String:
	var b := s.owner
	if b is ConstructionSite and (b as ConstructionSite).upgrade_of:
		b = (b as ConstructionSite).upgrade_of
	return s.label() if b and b.custom_name != "" else "the " + s.label()


## A task label inside a sentence: "carry wheat from Storage Barn 2 to North Mill".
static func _lower_first(text: String) -> String:
	return text.left(1).to_lower() + text.substr(1)


## The worker's name (World.rename_worker), or "" when it has none.
func _worker_name(w: Worker) -> String:
	var n: Variant = w.get("name")
	return n if n is String else ""


func _worker_title(w: Worker) -> String:
	var n := _worker_name(w)
	return "Worker · %s" % n if n != "" else "Worker %d" % (world.workers.find(w) + 1)


## Finished building only: a plain Building, not a Field or a ConstructionSite (also Building).
func _renamable_building() -> bool:
	return target is Building and not (target is Field) and not (target is ConstructionSite)


## Workers and finished buildings get the pencil; sites, fields and roads don't.
func _can_rename() -> bool:
	return (target is Worker and world.has_method("rename_worker")) \
		or (_renamable_building() and world.has_method("rename_building"))


## The header's name: a flat button with the title (and the default name under a custom one),
## the pencil beside it (shown on hover), and the name field with ✓ and × for editing, plus a
## hint row under the header. The level chip and close × step aside while editing.
func _build_rename() -> void:
	var header: HBoxContainer = _panel["header"]
	var title: Label = _panel["title"]
	var head_box := header.get_parent() as PanelContainer
	var hb := head_box.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	hb.content_margin_left = 14
	hb.content_margin_top = 7
	hb.content_margin_bottom = 7
	head_box.add_theme_stylebox_override("panel", hb)
	header.custom_minimum_size.y = 40
	header.add_theme_constant_override("separation", 8)
	header.get_child((_panel["badge"] as Label).get_index() + 1).visible = false   # the spacer: _name_box fills
	for c in header.get_children():
		(c as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER

	_name_box = HBoxContainer.new()
	_name_box.add_theme_constant_override("separation", 6)
	_name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_name_box)
	header.move_child(_name_box, title.get_index())

	_name_btn = Button.new()
	_name_btn.focus_mode = Control.FOCUS_NONE
	_name_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_name_btn.mouse_default_cursor_shape = Control.CURSOR_IBEAM
	_name_btn.pressed.connect(start_rename)
	_name_off = StyleBoxEmpty.new()
	_name_on = UiStyle.box(Color(UiStyle.PAPER, 0.4), Color.TRANSPARENT, 6, 0)
	_name_on.set_expand_margin(SIDE_LEFT, 6)       # the highlight reaches past the text, not the layout
	_name_on.set_expand_margin(SIDE_RIGHT, 6)
	_name_on.set_expand_margin(SIDE_TOP, 2)
	_name_on.set_expand_margin(SIDE_BOTTOM, 2)
	for sb: StyleBox in [_name_off, _name_on]:
		sb.set_content_margin_all(0)
	for s in ["normal", "hover", "pressed", "disabled", "focus"]:
		_name_btn.add_theme_stylebox_override(s, _name_off)
	_name_box.add_child(_name_btn)
	var col := VBoxContainer.new()
	_name_col = col
	col.add_theme_constant_override("separation", 1)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_btn.add_child(col)
	title.reparent(col, false)
	title.add_theme_font_size_override("font_size", 20)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 13)
	_subtitle.add_theme_constant_override("line_spacing", -2)
	_subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle.visible = false
	col.add_child(_subtitle)

	_pencil = Button.new()
	_pencil.icon = UiStyle.icon("pencil")
	_pencil.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pencil.add_theme_constant_override("icon_max_width", 14)
	_pencil.focus_mode = Control.FOCUS_NONE
	_pencil.custom_minimum_size = Vector2(26, 26)
	_pencil.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pencil.tooltip_text = "Rename (F2)"
	var pb := UiStyle.box(UiStyle.PAPER, UiStyle.WOOD, 7, 1)
	pb.set_content_margin_all(0)
	for s in ["normal", "hover", "pressed", "focus"]:
		_pencil.add_theme_stylebox_override(s, pb)
	_pencil.modulate.a = 0.0
	_pencil.pressed.connect(start_rename)
	_name_box.add_child(_pencil)

	_name_edit = LineEdit.new()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.custom_minimum_size.y = 36
	_name_edit.add_theme_font_override("font", UiStyle.head_font(600))
	_name_edit.add_theme_font_size_override("font_size", 18)
	_name_edit.add_theme_color_override("font_placeholder_color", Color("#9C8B78"))
	_name_edit.add_theme_color_override("caret_color", UiStyle.SELECT)
	var eb := UiStyle.box(UiStyle.PAPER, UiStyle.SELECT, 8, 2)
	eb.content_margin_left = 10
	eb.content_margin_right = 10
	_name_edit.add_theme_stylebox_override("normal", eb)
	_name_edit.add_theme_stylebox_override("focus", eb)
	var ring := UiStyle.box(Color.TRANSPARENT, Color("#CFE0F0"), 11, 3)
	ring.draw_center = false
	ring.set_expand_margin_all(3)
	ring.set_content_margin_all(0)
	var ring_box := PanelContainer.new()
	ring_box.add_theme_stylebox_override("panel", ring)
	ring_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ring_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ring_box.add_child(_name_edit)
	_name_edit.text_changed.connect(func(_t: String) -> void: _update_hint())
	_name_edit.text_submitted.connect(func(_t: String) -> void: _end_rename(true))
	_name_edit.focus_exited.connect(func() -> void: _end_rename(false))
	_name_edit.gui_input.connect(func(e: InputEvent) -> void:
		if e.is_action_pressed("ui_cancel"):
			_name_edit.accept_event()
			_end_rename(false))
	header.add_child(ring_box)
	header.move_child(ring_box, _name_box.get_index() + 1)
	_edit_parts = [ring_box]
	for spec in [["✓", "PrimaryButton", true], ["✕", "", false]]:
		var b := Button.new()
		b.text = spec[0]
		b.theme_type_variation = spec[1]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(34, 34)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.tooltip_text = "Save (Enter)" if spec[2] else "Cancel (Esc)"
		var ok: bool = spec[2]
		b.pressed.connect(func() -> void: _end_rename(ok))
		header.add_child(b)
		_edit_parts.append(b)
	for c: Control in _edit_parts:
		c.visible = false

	# hint row under the header
	var hint_margin := MarginContainer.new()
	hint_margin.add_theme_constant_override("margin_left", 14)
	hint_margin.add_theme_constant_override("margin_right", 14)
	hint_margin.add_theme_constant_override("margin_top", 12)
	hint_margin.visible = false
	head_box.get_parent().add_child(hint_margin)
	head_box.get_parent().move_child(hint_margin, head_box.get_index() + 1)
	var hint := _vbox(4)
	hint_margin.add_child(hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	hint.add_child(row)
	_hint_text = _rich()
	for f in ["normal_font_size", "bold_font_size"]:
		_hint_text.add_theme_font_size_override(f, 13)
	_hint_text.add_theme_color_override("default_color", UiStyle.INK_SOFT)
	row.add_child(_hint_text)
	_hint_count = _text("", "SmallLabel")
	_hint_count.add_theme_font_override("font", UiStyle.body_font(true))
	_hint_count.add_theme_font_size_override("font_size", 13)
	_hint_count.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(_hint_count)
	var keys := _text("Enter or ✓ saves · Esc or × cancels", "SmallLabel")
	keys.add_theme_font_size_override("font_size", 13)
	hint.add_child(keys)
	_edit_parts.append(hint_margin)


## Fits the name button to its text, truncated with "…" (full name as tooltip) so the level chip
## and the close × never move. Also shows the pencil while the name is hovered.
func _fit_title() -> void:
	var title: Label = _panel["title"]
	var font := title.get_theme_font("font")
	var w := font.get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, title.get_theme_font_size("font_size")).x
	if _subtitle.visible:
		w = maxf(w, _subtitle.get_theme_font("font").get_string_size(_subtitle.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			_subtitle.get_theme_font_size("font_size")).x)
	var header: HBoxContainer = _panel["header"]
	var room := (header.size.x if header.size.x > 0.0 else WIDTH - 28.0) - 26.0 - 6.0
	var sep := header.get_theme_constant("separation")
	for c in header.get_children():
		if c != _name_box and (c as Control).visible:
			room -= (c as Control).get_combined_minimum_size().x + sep
	var fits := w <= room
	_name_btn.custom_minimum_size = Vector2(minf(ceilf(w), maxf(room, 40.0)), _name_col.get_combined_minimum_size().y)
	_name_btn.tooltip_text = "" if fits else title.text + ("\n" + _subtitle.text if _subtitle.visible else "")
	_name_btn.disabled = not _can_rename()
	_name_btn.mouse_default_cursor_shape = Control.CURSOR_IBEAM if _can_rename() else Control.CURSOR_ARROW
	_update_hover()


func _update_hover() -> void:
	var on := _can_rename() and not _editing() and (_hover_forced or
		_name_box.get_global_rect().has_point(_name_box.get_global_mouse_position()))
	if (_pencil.modulate.a > 0.5) != on:
		_pencil.modulate.a = 1.0 if on else 0.0
		for s in ["normal", "hover", "pressed"]:
			_name_btn.add_theme_stylebox_override(s, _name_on if on else _name_off)
	_pencil.visible = _can_rename()


func _editing() -> bool:
	return not _edit_parts.is_empty() and (_edit_parts[0] as Control).visible


## Swaps the name for the name field (click on the name or the pencil, or F2).
func start_rename() -> void:
	if not _can_rename() or _editing():
		return
	_name_box.visible = false
	(_panel["badge"] as Label).visible = false
	(_panel["close"] as Control).visible = false
	for c: Control in _edit_parts:
		c.visible = true
	_name_edit.max_length = WorkerNames.MAX_LENGTH if target is Worker else Building.MAX_NAME
	_name_edit.text = _worker_name(target) if target is Worker else (target as Building).custom_name
	_name_edit.placeholder_text = _default_name()
	_update_hint()
	_name_edit.grab_focus()
	_name_edit.select_all()


## What an empty name gives: the building's default name, or the worker's current name.
func _default_name() -> String:
	return _worker_name(target) if target is Worker else (target as Building).default_name()


func _update_hint() -> void:
	var n := _name_edit.text.length()
	var limit := _name_edit.max_length
	if target is Worker:
		_hint_text.text = "Leave empty to keep [b][color=#%s]%s[/color][/b]" % [UiStyle.INK.to_html(false), _default_name()]
	elif n == 0:
		_hint_text.text = "Empty: ✓ resets to [b][color=#%s]%s[/color][/b]" % [UiStyle.INK.to_html(false), _default_name()]
	else:
		_hint_text.text = "Leave empty to use the default name ([b][color=#%s]%s[/color][/b])" % [
			UiStyle.INK.to_html(false), _default_name()]
	_hint_count.text = "%d / %d" % [n, limit]
	_hint_count.add_theme_color_override("font_color", UiStyle.SHORT if n >= limit else UiStyle.INK_SOFT)


## Leaves the name field; with `confirm` the typed name is given to the worker or building
## (buildings accept an empty name — it resets to the default).
func _end_rename(confirm: bool) -> void:
	if not _editing():
		return
	for c: Control in _edit_parts:
		c.visible = false
	_name_box.visible = true
	(_panel["badge"] as Label).visible = (_panel["badge"] as Label).text != ""
	(_panel["close"] as Control).visible = true
	var name := _name_edit.text.strip_edges()
	if confirm and target is Worker and name != "" and world.has_method("rename_worker"):
		world.call("rename_worker", target, name)
	elif confirm and _renamable_building() and world.has_method("rename_building"):
		world.call("rename_building", target, name)
	if target != null:
		refresh.call_deferred()


# --- road blocks -----------------------------------------------------------------------

func _build_road(anchor: Vector2i) -> void:
	var surface: StringName = world.road_blocks.get(anchor, &"dirt")
	_set_header(Defs.def(&"road_%s" % surface)["name"], "groad" if surface == &"gravel" else "road",
		"Bridge" if world.is_bridge(anchor) else "")
	_add(_text("Vehicles drive only on roads; workers walk faster on them.", "SoftLabel", true))
	_add_action("Demolish road", world.road_blocker(anchor))


# --- ground piles ----------------------------------------------------------------------
# Felled logs and goods put down on the way (World.drop_goods): what lies there, where the planner
# sends it and why it lies here (Store.origin). Off the road there is no pickup to call (17a).

## Where it lies, after the title ("in the forest"); hidden for other objects.
func _build_pile_where() -> void:
	_pile_where = Label.new()
	_pile_where.add_theme_font_override("font", UiStyle.body_font())
	_pile_where.add_theme_font_size_override("font_size", 14)
	_pile_where.add_theme_color_override("font_color", UiStyle.INK)
	_pile_where.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pile_where.size_flags_stretch_ratio = 50.0     # the spacer before the close button gets the rest
	_pile_where.clip_text = true
	_pile_where.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_pile_where.visible = false
	var header: HBoxContainer = _panel["header"]
	header.add_child(_pile_where)
	header.move_child(_pile_where, (_panel["badge"] as Label).get_index() + 1)


func _build_pile(s: Store) -> void:
	_set_header("Ground pile", "pile")
	var res: StringName = s.contents.keys()[0] if not s.contents.is_empty() else &"wood"
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	_add(top)
	top.add_child(UiStyle.icon_rect(UiStyle.resource_icon(res), 40))
	var col := _vbox(2)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(col)
	var amount := Label.new()
	amount.add_theme_font_override("font", UiStyle.head_font(600))
	amount.add_theme_font_size_override("font_size", 26)
	amount.add_theme_color_override("font_color", UiStyle.INK)
	col.add_child(amount)
	_ui["pile_amount"] = amount
	var on_road := world.road[world.idx(s.cell)] != 0
	var kind := _text("one kind only · %s" % ("on a road" if on_road else "off the road"), "SmallLabel")
	kind.add_theme_font_size_override("font_size", 13)
	col.add_child(kind)

	var fill := _add(_vbox(5))
	var row := HBoxContainer.new()
	fill.add_child(row)
	var held := _rich()
	held.add_theme_font_size_override("normal_font_size", 14)
	held.add_theme_font_size_override("bold_font_size", 14)
	row.add_child(held)
	_ui["pile_held"] = held
	var room := _text("", "SmallLabel")
	row.add_child(room)
	_ui["pile_room"] = room
	var pb := UiStyle.bar(UiStyle.WOOD, 12)
	pb.add_theme_stylebox_override("background", UiStyle.box(TRACK, TRACK_EDGE, 6, 1))
	fill.add_child(pb)
	_ui["pile_bar"] = pb

	_add(_text("GOING TO", "SectionLabel"))
	var leg := _pile_leg(s)
	var state: String = leg["state"]
	var card := PanelContainer.new()
	var fills := {"going": [UiStyle.SELECT_PAPER, GOING_EDGE, "walking"], "carrying": [UiStyle.SELECT_PAPER, GOING_EDGE, "walking"],
		"waiting": [WAIT_PAPER, WAIT_EDGE, "idle"], "none": [UiStyle.LOCKED, UiStyle.LOCKED_EDGE, "idle"]}
	var look: Array = fills[state]
	var csb := UiStyle.box(look[0], look[1], 10, 2)
	csb.content_margin_left = 12
	csb.content_margin_right = 12
	csb.content_margin_top = 8
	csb.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", csb)
	_add(card)
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 10)
	card.add_child(crow)
	crow.add_child(UiStyle.icon_rect(UiStyle.icon(look[2]), 22))
	var going := _link_text()
	crow.add_child(going)
	_ui["pile_going"] = going
	if state == "waiting":
		var hint := _link_text()
		hint.add_theme_font_size_override("normal_font_size", 13)
		hint.add_theme_font_size_override("bold_font_size", 13)
		hint.add_theme_color_override("default_color", UiStyle.INK_SOFT)
		_add(hint)
		_ui["pile_hint"] = hint

	_add(_text("WHY IT’S HERE", "SectionLabel"))
	var why := HBoxContainer.new()
	why.add_theme_constant_override("separation", 10)
	_add(why)
	var ic := UiStyle.icon_rect(UiStyle.icon("warning" if s.origin == Store.Origin.DROPPED else "cut"), 22)
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	why.add_child(ic)
	var why_text := _rich()
	why.add_child(why_text)
	_ui["pile_why"] = why_text


func _update_pile(s: Store) -> void:
	var res: StringName = s.contents.keys()[0] if not s.contents.is_empty() else &"wood"
	var n := s.amount(res)
	(_ui["pile_amount"] as Label).text = Defs.format_goods(res, n)
	var kg := s.weight()
	(_ui["pile_held"] as RichTextLabel).text = "[b]%s[/b] of %s" % [Defs.format_kg(kg).trim_suffix(" kg"), Defs.format_kg(s.capacity)]
	(_ui["pile_room"] as Label).text = "room for %s" % Defs.format_kg(maxf(0.0, s.capacity - kg))
	(_ui["pile_bar"] as ProgressBar).value = kg / s.capacity
	_pile_where.text = _pile_place(s)

	var leg := _pile_leg(s)
	var t: Task = leg["task"]
	var going := ""
	match leg["state"]:
		"going", "carrying":
			var who := _link_name(t.worker)
			going = "[b]→ %s[/b] · %s" % [_pile_dest(t.dst), "%s is on the way" % who if leg["state"] == "going" else "%s is carrying a load there" % who]
		"waiting":
			going = "[b]→ %s[/b] · waits for a free hand" % _pile_dest(t.dst)
			var cat: String = Task.CATEGORY_NAMES.get(t.category, ["Transport"])[0]
			var link := "[url=priorities][color=#%s]%s[/color][/url]" % [UiStyle.SELECT.to_html(false), cat]
			var hint := "All workers are busy. Raise %s in Priorities to get it moved sooner." % link
			if world.category_off.has(t.category):
				hint = "Nobody does %s tasks: switch them on in Priorities." % link
			elif world.idle_workers() > 0:
				hint = "A free worker will pick it up in a moment."
			(_ui["pile_hint"] as RichTextLabel).text = hint
		"none":
			going = "[b]Nowhere to take it yet[/b] · %s" % _pile_nowhere(s, res)
	(_ui["pile_going"] as RichTextLabel).text = going

	var why := ""
	match s.origin:
		Store.Origin.FELLED:
			why = "[b]Felled tree[/b] · from your Cut trees order."
			var next := _trees_to_join(s)
			if next > 0:
				why += " The next tree will add to this pile." if next == 1 else " The next %d trees will add to this pile." % next
		Store.Origin.CLEARED:
			why = "[b]Felled tree[/b] · cleared for the %s site." % s.site_name if s.site_name != "" else "[b]Felled tree[/b] · cleared for a building site."
		_:
			why = "[b]Dropped:[/b] %s" % (s.reason if s.reason != "" else "a worker put it down here.")
	(_ui["pile_why"] as RichTextLabel).text = why


## The pile's carry legs: {state, task}; state "going" (a worker is on the way to it), "carrying"
## (a worker took a load and nothing else is planned), "waiting" (planned, nobody has it yet) or
## "none".
func _pile_leg(s: Store) -> Dictionary:
	var going: Task = null
	var waiting: Task = null
	var carrying: Task = null
	for t in world.tasks.tasks:
		if t.kind != Task.Kind.CARRY or t.src != s:
			continue
		if t.worker == null:
			waiting = t if waiting == null else waiting
		elif t.fetch_from == s:
			going = t if going == null else going
		else:
			carrying = t if carrying == null else carrying
	if going:
		return {"state": "going", "task": going}
	if waiting:
		return {"state": "waiting", "task": waiting}
	if carrying:
		return {"state": "carrying", "task": carrying}
	return {"state": "none", "task": null}


## Where a leg takes the goods: "Sawmill", "Storage Barn 2", "Garage site".
func _pile_dest(s: Store) -> String:
	if s == null:
		return "the barn"
	if s.owner is ConstructionSite:
		return "%s site" % (s.owner as ConstructionSite).base_name()
	return s.label()


## Why no leg takes the goods away.
func _pile_nowhere(s: Store, res: StringName) -> String:
	if world.stores().is_empty():
		return "there is no barn. Build a Storage Barn."
	var load := minf(Defs.weight(res, s.amount(res)), Defs.CARRY_CAPACITY)
	var room := false
	for b: Building in world.stores():
		room = room or (b.store.accepts(res) and b.store.room() >= minf(load, 1.0))
	if not room:
		return "every barn is full."
	return "a place for it will be found in a moment."


## Marked trees near a felled pile whose logs will join it (World.drop_goods), as many as fit.
func _trees_to_join(s: Store) -> int:
	var n := 0
	var reach := Defs.GROUND_PILE_REACH + 1
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			if world.marked.has(s.cell + Vector2i(dx, dy)):
				n += 1
	return mini(n, floori(s.room() / Defs.weight(&"wood", Defs.WOOD_PER_TREE) + 0.0001))


## "in the forest", "by the old Garage site", "by Storage Barn 2", "in the open".
func _pile_place(s: Store) -> String:
	var trees := 0
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			if world.has_tree(s.cell + Vector2i(dx, dy)):
				trees += 1
	if trees >= 12:
		return "in the forest"
	if s.origin == Store.Origin.DROPPED and s.site_name != "":
		return "by the old %s site" % s.site_name
	var best: Building = null
	var best_d := 12.0 * 12.0
	for b: Building in world.buildings.values():
		if b is ConstructionSite and (b as ConstructionSite).is_road():
			continue
		var r := b.rect()
		var near := Vector2(clampi(s.cell.x, r.position.x, r.end.x - 1), clampi(s.cell.y, r.position.y, r.end.y - 1))
		var d := near.distance_squared_to(Vector2(s.cell))
		if d < best_d:
			best_d = d
			best = b
	if best == null:
		return "in the open"
	if best is ConstructionSite:
		return "by the %s site" % (best as ConstructionSite).base_name()
	return "by %s" % best.display_name()


## A worker's name as a link to its panel.
func _link_name(w: Worker) -> String:
	var n := _worker_name(w)
	if n == "":
		n = "Worker %d" % (world.workers.find(w) + 1)
	_ui["pile_worker"] = w
	return "[url=worker][color=#%s]%s[/color][/url]" % [UiStyle.SELECT.to_html(false), n]


## Rich text whose links work: "worker" opens the linked worker's panel, "priorities" the Priorities.
func _link_text() -> RichTextLabel:
	var t := _rich()
	t.mouse_filter = Control.MOUSE_FILTER_PASS
	t.meta_underlined = true
	t.meta_clicked.connect(func(meta: Variant) -> void:
		if str(meta) == "priorities":
			priorities_requested.emit()
		elif str(meta) == "worker" and _ui.get("pile_worker") is Worker:
			open_requested.emit(_ui["pile_worker"]))
	return t


# --- shared pieces ---------------------------------------------------------------------

func _add(c: Control) -> Control:
	_body.add_child(c)
	return c


func _text(text: String, variation := "", wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 1
	return l


func _rich() -> RichTextLabel:
	var t := RichTextLabel.new()
	t.bbcode_enabled = true
	t.fit_content = true
	t.scroll_active = false
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.add_theme_font_override("normal_font", UiStyle.body_font())
	t.add_theme_font_override("bold_font", UiStyle.body_font(true))
	t.add_theme_font_size_override("normal_font_size", 15)
	t.add_theme_font_size_override("bold_font_size", 15)
	t.add_theme_color_override("default_color", UiStyle.INK)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


func _vbox(sep: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


func _spacer() -> Control:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


func _well() -> PanelContainer:
	var w := PanelContainer.new()
	w.theme_type_variation = "Well"
	return w


## "<icon> Inside 120 kg ...... room for 200 kg" over a bar. Returns {value, right, bar}.
func _meter(tex: Texture2D, caption: String) -> Dictionary:
	var box := _add(_vbox(5))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	row.add_child(UiStyle.icon_rect(tex, 18))
	var cap := _text(caption)
	cap.add_theme_font_size_override("font_size", 14)
	row.add_child(cap)
	var value := _text("", "NumberLabel")
	value.add_theme_font_size_override("font_size", 14)
	row.add_child(value)
	row.add_child(_spacer())
	var right := _text("", "SmallLabel")
	row.add_child(right)
	var pb := UiStyle.bar(UiStyle.WHEAT, 12)
	pb.add_theme_stylebox_override("background", UiStyle.box(TRACK, TRACK_EDGE, 6, 1))
	box.add_child(pb)
	return {"value": value, "right": right, "bar": pb}


## Colour swatches with captions; an entry [colour, text, true] is drawn as an outline.
func _legend(entries: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	for e: Array in entries:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 5)
		h.add_child(item)
		var sw := Panel.new()
		sw.custom_minimum_size = Vector2(10, 10)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var outline: bool = e.size() > 2 and e[2]
		sw.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PAPER if outline else e[0], e[0] if outline else Color.TRANSPARENT, 3, 2))
		item.add_child(sw)
		var l := _text(e[1], "SmallLabel")
		l.add_theme_font_size_override("font_size", 13)
		item.add_child(l)
	return h


## High / Normal / Low segmented control for a building, field or site.
func _add_priority(b: Building) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_add(row)
	var cap := _text("Priority", "SmallLabel")
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(cap)
	var frame := PanelContainer.new()
	var fsb := UiStyle.box(UiStyle.PAPER_DEEP, UiStyle.BOARD, UiStyle.RADIUS, 2)
	fsb.set_content_margin_all(3)
	frame.add_theme_stylebox_override("panel", fsb)
	row.add_child(frame)
	var seg := HBoxContainer.new()
	seg.add_theme_constant_override("separation", 3)
	frame.add_child(seg)
	for p in [[1, "High"], [0, "Normal"], [-1, "Low"]]:
		var btn := Button.new()
		btn.text = p[1]
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 15)
		var on: bool = b.priority == p[0]
		var sb := UiStyle.box(UiStyle.PAPER, UiStyle.WOOD, 7, 2, 2) if on else UiStyle.box(Color.TRANSPARENT, Color.TRANSPARENT, 7)
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		var hover := sb.duplicate() as StyleBoxFlat
		if not on:
			hover.bg_color = Color(UiStyle.PAPER, 0.7)
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", hover)
		btn.add_theme_stylebox_override("pressed", hover)
		var col := UiStyle.INK if on else UiStyle.INK_SOFT
		for c in ["font_color", "font_hover_color", "font_pressed_color"]:
			btn.add_theme_color_override(c, col)
		btn.pressed.connect(func() -> void:
			if target is Building:
				(target as Building).priority = p[0]
				refresh())
		seg.add_child(btn)


## Button whose face is a row of texts and icons (Strings and Texture2Ds).
func _content_button(variation: String, parts: Array, text_color := Color.TRANSPARENT) -> Button:
	var b := Button.new()
	b.theme_type_variation = variation
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = 42
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_bottom = -3              # above the button's drop shadow
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var col := text_color if text_color.a > 0.0 else (UiStyle.PAPER if variation == "PrimaryButton" else UiStyle.INK)
	for p: Variant in parts:
		if p is Texture2D:
			row.add_child(UiStyle.icon_rect(p, 20))
		else:
			var l := Label.new()
			l.text = p
			l.add_theme_font_override("font", UiStyle.head_font(600))
			l.add_theme_font_size_override("font_size", 16)
			l.add_theme_color_override("font_color", col)
			row.add_child(l)
	return b


## The demolish / cancel button (two clicks) with the reason when it is not allowed.
func _add_action(text: String, blocker: String) -> void:
	_action = Button.new()
	_action.theme_type_variation = "DangerButton"
	_action.focus_mode = Control.FOCUS_NONE
	_action.disabled = blocker != ""
	_action.pressed.connect(press_action)
	_add(_action)
	_set_action_text(text)
	if blocker != "":
		var l := _text(blocker, "SmallLabel", true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_add(l)


func _set_action_text(text: String) -> void:
	var t := "Click again to confirm: %s" % text if _armed else text
	if _action.text != t:
		_action.text = t


## "Halted: full, waiting…" -> "[b]Halted:[/b] full, waiting…"; without a colon the first word is bold.
func _bold_head(s: String) -> String:
	var i := s.find(": ")
	if i >= 0:
		return "[b]%s:[/b] %s" % [s.left(i), s.substr(i + 2)]
	i = s.find(" ")
	return "[b]%s[/b]%s" % [s.left(i), s.substr(i)] if i > 0 else "[b]%s[/b]" % s


## "refund 120 qk, 60 planks back to the barn", "nothing to refund".
func _refund_text(paid: int, materials: Dictionary) -> String:
	var parts := PackedStringArray()
	if paid > 0:
		parts.append("refund %s" % Defs.format_money(paid))
	var goods := PackedStringArray()
	for res: StringName in materials:
		if materials[res] > 0.0001:
			goods.append(Defs.format_goods(res, materials[res]))
	if not goods.is_empty():
		parts.append("%s back to the barn" % ", ".join(goods))
	return ", ".join(parts) if not parts.is_empty() else "nothing to refund"


# --- debugging ---------------------------------------------------------------------------

## --show=info_mill / info_rename / info_renamed / info_site / info_field / info_worker / info_pile / info_pile_dropped: a sample object
## (use with --sim), or null.
func debug_target(name: String) -> Variant:
	var t: Variant = null
	match name:
		"info_mill", "info_rename", "info_renamed":
			for b: Building in world.buildings.values():
				if b.def_id == &"hand_mill" and not (b is ConstructionSite):
					t = b
			if t:
				_debug_mill(t)
			if t and name == "info_renamed":
				world.rename_building(t, "Riverside Mill")
		"info_site":
			t = _debug_site()
		"info_field":
			if not world.fields.is_empty():
				t = world.fields[0]
		"info_worker":
			for w in world.workers:
				if t == null or (w.carrying != &"" and (t as Worker).carrying == &""):
					t = w
		"info_pile":
			t = _debug_felled_pile()
		"info_pile_dropped":
			t = _debug_dropped_pile()
	return t


## --show=info_rename: the panel (already showing the target) with its name being edited.
func debug_state(name: String) -> void:
	if name == "info_rename":
		start_rename()
		_name_edit.text = "Riverside Mill"
		_name_edit.caret_column = _name_edit.text.length()
		_update_hint()


## Fills the mill with wheat and runs the farm until a worker is halfway through a batch.
func _debug_mill(b: Building) -> void:
	b.input = maxf(b.input, 120.0)
	b.output = maxf(b.output, 75.0)
	var order := world.category_order.duplicate()
	world.category_order.erase(Task.Category.PROCESSING)
	world.category_order.push_front(Task.Category.PROCESSING)
	for i in 1200:
		var t := b.process_task
		if t and t.worker and t.worker.phase == Worker.Phase.WORKING and t.worker.work_timer > t.work * 0.5:
			break
		world.tick(0.1)
	world.category_order = order


## Marks a patch of forest near the barn (Felling first) and runs the farm until a worker is on the
## way to a felled pile, with marked trees left beside it.
func _debug_felled_pile() -> Store:
	var center := Vector2i(world.size / 2, world.size / 2)
	for b: Building in world.buildings.values():
		if b.def_id == &"storage_barn":
			center = b.access
	var spot := Vector2i(-1, -1)
	for r in range(6, 60):
		for dx in range(-r, r + 1):
			for dy in [-r, r]:
				var c: Vector2i = center + Vector2i(dx, dy)
				if spot.x < 0 and not world.is_locked(c) and world.has_tree(c) and world.nav.is_walkable(c + Vector2i(0, -signi(dy))) \
						and _trees_around(c, 3) >= 26:
					spot = c
	if spot.x < 0:
		return null
	world.mark_trees(Rect2i(spot - Vector2i(1, 1), Vector2i(3, 3)))
	var order := world.category_order.duplicate()
	world.category_order.erase(Task.Category.FELLING)
	world.category_order.push_front(Task.Category.FELLING)
	var pile: Store = null
	for i in 3000:
		world.tick(0.1)
		for s in world.ground_piles:
			if s.origin == Store.Origin.FELLED and _pile_leg(s)["state"] == "going" \
					and s.room() >= Defs.weight(&"wood", Defs.WOOD_PER_TREE * 2):
				pile = s
		var t: Task = _pile_leg(pile)["task"] if pile else null
		if t and t.worker.pos.distance_to(Vector2(pile.cell)) > 1.5:
			if _trees_to_join(pile) == 0:
				world.mark_trees(Rect2i(pile.cell - Vector2i(2, 2), Vector2i(5, 5)))   # more to come
			break
		pile = null
	world.category_order = order
	return pile


func _trees_around(c: Vector2i, r: int) -> int:
	var n := 0
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if world.has_tree(c + Vector2i(dx, dy)):
				n += 1
	return n


## A garage site by the barn is cancelled while a worker carries planks to it: they lie on the ground.
func _debug_dropped_pile() -> Store:
	var site := _debug_site()
	if site == null:
		return null
	world.set_stock(&"planks", maxf(world.total(&"planks"), 300.0))
	var order := world.category_order.duplicate()
	world.category_order.erase(Task.Category.CONSTRUCTION)
	world.category_order.push_front(Task.Category.CONSTRUCTION)
	for i in 3000:
		var carrier := false
		for w in world.workers:
			carrier = carrier or (w.task and w.task.kind == Task.Kind.CARRY and w.task.dst == site.supply
				and w.carrying != &"" and w.phase == Worker.Phase.TO_TASK and w.cell().distance_to(site.access) > 3.0)
		if carrier:
			break
		world.tick(0.1)
	world.category_order = order
	world.demolish(site)
	for s in world.ground_piles:
		if s.origin == Store.Origin.DROPPED and s.site_name != "":
			world.planner.tick()
			return s
	return null


## Places a garage site by the barn with too few planks in storage and lets the farm work on it.
func _debug_site() -> ConstructionSite:
	var center := Vector2i(world.size / 2, world.size / 2)
	for b: Building in world.buildings.values():
		if b.def_id == &"storage_barn":
			center = b.anchor
	world.set_stock(&"planks", minf(world.total(&"planks"), 30.0))
	for r in range(3, 40):
		for dx in range(-r, r + 1):
			for dy in [-r, r]:
				var s := world.place_site(&"garage", center + Vector2i(dx, dy), 0)
				if s:
					for i in 400:
						world.tick(0.1)
					return s
	return null


## Delivered / waiting part of a material bar: solid wood, then a striped part (on its way or available).
class TwoPartBar extends Control:
	var solid := 0.0
	var waiting := 0.0

	func _init() -> void:
		custom_minimum_size.y = 14
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_parts(a: float, b: float) -> void:
		a = clampf(a, 0.0, 1.0)
		b = clampf(b, 0.0, 1.0 - a)
		if a != solid or b != waiting:
			solid = a
			waiting = b
			queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UiStyle.box(InfoPanel.TRACK, InfoPanel.TRACK_EDGE, 7, 1), r)
		var inner := r.grow(-1.5)
		var w1 := inner.size.x * solid
		var w2 := inner.size.x * waiting
		if w2 > 0.5:
			var wr := Rect2(inner.position + Vector2(w1, 0), Vector2(w2, inner.size.y))
			var clip := PackedVector2Array([wr.position, Vector2(wr.end.x, wr.position.y), wr.end, Vector2(wr.position.x, wr.end.y)])
			var h := wr.size.y
			var x := wr.position.x - h
			while x < wr.end.x:
				var stripe := PackedVector2Array([Vector2(x, wr.end.y), Vector2(x + 6, wr.end.y),
					Vector2(x + 6 + h, wr.position.y), Vector2(x + h, wr.position.y)])
				for p in Geometry2D.intersect_polygons(stripe, clip):
					draw_colored_polygon(p, InfoPanel.WAITING)
				x += 12.0
		if w1 > 0.5:
			draw_style_box(UiStyle.box(UiStyle.BOARD, Color.TRANSPARENT, 6), Rect2(inner.position, Vector2(w1, inner.size.y)))
