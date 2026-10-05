class_name PriorityPanel
extends PanelContainer
## Task priorities (P), docked left under the HUD: the player ranks task categories and can
## switch them off. Waiting tasks still age, so low categories get done eventually.

const WIDTH := 520.0
const DOCK := Vector2(12, 84)               # top-left corner, under the HUD bar
const CARD := Color("#FBF5E8")
const CARD_EDGE := Color("#E4D6BC")
## Kit icon per category name; categories added later fall back to "working".
const ICONS := {
	"harvest": "wheat", "pickup trips": "pickup", "planting": "seeds", "construction": "build",
	"processing": "flour", "transport": "wheelbarrow", "felling": "cut",
}

var world: World
var _rows: VBoxContainer
var _counts := {}           # category -> RichTextLabel
var _foot: Label
var _accum := 0.0


func setup(p_world: World) -> void:
	world = p_world
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var p := UiStyle.make_panel("Priorities")
	add_child(p["root"])
	(p["root"] as Control).custom_minimum_size.x = WIDTH
	var header: HBoxContainer = p["header"]
	var key := UiStyle.key_cap("P")
	header.add_child(key)
	header.move_child(key, (p["title"] as Label).get_index() + 1)
	(p["close"] as Button).pressed.connect(hide)
	var body: VBoxContainer = p["body"]
	body.add_theme_constant_override("separation", 8)

	var note := Label.new()
	note.text = ("Idle workers take the highest task that is switched on, then the nearest one. Tasks that wait "
		+ "long move up about one place per %d s. High / Low on a building or field moves its jobs one place.") % Defs.TASK_AGING
	note.theme_type_variation = "SoftLabel"
	note.add_theme_font_size_override("font_size", 15)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 1
	body.add_child(note)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 8)
	body.add_child(_rows)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	body.add_child(foot)
	_foot = Label.new()
	_foot.theme_type_variation = "SmallLabel"
	_foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_foot.custom_minimum_size.x = 1
	_foot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_foot)
	var reset := Button.new()
	reset.text = "Reset to default"
	reset.theme_type_variation = "GhostButton"
	reset.focus_mode = Control.FOCUS_NONE
	reset.add_theme_font_size_override("font_size", 15)
	reset.add_theme_color_override("font_color", UiStyle.INK_SOFT)
	reset.pressed.connect(func() -> void:
		world.reset_priorities()
		rebuild())
	foot.add_child(reset)

	visibility_changed.connect(func() -> void:
		if visible:
			_dock())
	add_to_group("debug_show")
	rebuild()


func _dock() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	position = DOCK
	reset_size.call_deferred()


func rebuild() -> void:
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	_counts.clear()
	var n := world.category_order.size()
	for i in n:
		_rows.add_child(_card(world.category_order[i], i, n))
	var off := PackedStringArray()
	for cat: int in world.category_order:
		if world.category_off.has(cat):
			var name: String = _names(cat)[0]
			if cat == Task.Category.TRANSPORT:
				off.append("%s is off — goods stay where they are made." % name)
			elif cat == Task.Category.PICKUP:
				off.append("%s is off — the pickup stays in the garage." % name)
			else:
				off.append("%s is off — workers skip these tasks." % name)
	_foot.text = " ".join(off)
	refresh()
	reset_size.call_deferred()


func _names(cat: int) -> Array:
	return Task.CATEGORY_NAMES.get(cat, ["Task %d" % cat, ""])


func _card(cat: int, i: int, n: int) -> PanelContainer:
	var on := not world.category_off.has(cat)
	var names := _names(cat)
	var card := PanelContainer.new()
	var sb := UiStyle.box(CARD, CARD_EDGE, 12, 2)
	sb.content_margin_left = 8
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", sb)
	var desc := String(names[1])
	card.tooltip_text = desc.left(1).to_upper() + desc.substr(1)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)

	var rank := Label.new()
	rank.text = str(i + 1)
	rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rank.custom_minimum_size = Vector2(30, 30)
	rank.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rank.add_theme_font_override("font", UiStyle.head_font(600))
	rank.add_theme_font_size_override("font_size", 16)
	var rsb := UiStyle.box(UiStyle.BOARD, Color.TRANSPARENT, 15)
	rsb.set_content_margin_all(0)
	rank.add_theme_stylebox_override("normal", rsb)
	row.add_child(rank)
	var ic := UiStyle.icon_rect(UiStyle.icon(ICONS.get(String(names[0]).to_lower(), "working")), 30)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)
	var name := Label.new()
	name.text = names[0]
	name.add_theme_font_override("font", UiStyle.head_font(600))
	name.add_theme_font_size_override("font_size", 18)
	text.add_child(name)
	var count := RichTextLabel.new()
	count.bbcode_enabled = true
	count.fit_content = true
	count.scroll_active = false
	count.autowrap_mode = TextServer.AUTOWRAP_OFF
	count.add_theme_font_override("normal_font", UiStyle.body_font())
	count.add_theme_font_override("bold_font", UiStyle.body_font(true))
	count.add_theme_font_size_override("normal_font_size", 14)
	count.add_theme_font_size_override("bold_font_size", 14)
	count.add_theme_color_override("default_color", UiStyle.INK_SOFT)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(count)
	_counts[cat] = count
	if not on:
		name.add_theme_color_override("font_color", UiStyle.INK_SOFT)
		ic.modulate.a = 0.5

	var toggle := Switch.new()
	toggle.button_pressed = on
	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	toggle.tooltip_text = "Switch %s off" % String(names[0]).to_lower() if on else "Switch %s on" % String(names[0]).to_lower()
	toggle.toggled.connect(func(v: bool) -> void:
		world.set_category_on(cat, v)
		rebuild.call_deferred())
	row.add_child(toggle)

	var arrows := VBoxContainer.new()
	arrows.add_theme_constant_override("separation", 3)
	arrows.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(arrows)
	arrows.add_child(_arrow("▲", i > 0, func() -> void:
		world.move_category(cat, -1)
		rebuild.call_deferred()))
	arrows.add_child(_arrow("▼", i < n - 1, func() -> void:
		world.move_category(cat, 1)
		rebuild.call_deferred()))
	return card


## Small up / down button.
func _arrow(text: String, enabled: bool, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(34, 24)
	b.add_theme_font_override("font", UiStyle.body_font())
	b.add_theme_font_size_override("font_size", 11)
	for s: String in ["normal", "hover", "pressed", "disabled"]:
		var fill := {"normal": UiStyle.PAPER, "hover": Color("#F6EBD3"), "pressed": UiStyle.PAPER_DEEP, "disabled": UiStyle.LOCKED}[s] as Color
		var sb := UiStyle.box(fill, UiStyle.LOCKED_EDGE if s == "disabled" else UiStyle.WOOD, 7, 2)
		sb.set_content_margin_all(0)
		b.add_theme_stylebox_override(s, sb)
	b.pressed.connect(on_pressed)
	return b


func _process(delta: float) -> void:
	if not visible:
		return
	_accum += delta
	if _accum > 0.25:
		_accum = 0.0
		refresh()


func refresh() -> void:
	var counts := world.category_counts()
	var ink := UiStyle.INK.to_html(false)
	for cat: int in _counts:
		var c: Array = counts.get(cat, [0, 0])
		var t := "[color=#%s][b]%d[/b][/color] waiting · [color=#%s][b]%d[/b][/color] in progress" % [ink, c[0], ink, c[1]]
		var l: RichTextLabel = _counts[cat]
		if l.text != t:
			l.text = t


## --show=priorities: the panel with Transport switched off (to show the footer).
func debug_show(name: String, _game: Node) -> void:
	if name != "priorities":
		return
	world.set_category_on(Task.Category.TRANSPORT, false)
	show()
	rebuild()


## On / off pill switch (green with the knob right when on).
class Switch extends Button:
	func _init() -> void:
		toggle_mode = true
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(48, 28)
		for s: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			add_theme_stylebox_override(s, StyleBoxEmpty.new())
		toggled.connect(func(_v: bool) -> void: queue_redraw())

	func _draw() -> void:
		var on := button_pressed
		var r := Rect2(Vector2(0, (size.y - 28.0) * 0.5), Vector2(48, 28))
		var sb := UiStyle.box(UiStyle.GO if on else Color("#D6CDBB"), Color("#36592A") if on else Color("#A39A8A"), 14, 2)
		draw_style_box(sb, r)
		var knob := Vector2(r.end.x - 14.0 if on else r.position.x + 14.0, r.get_center().y)
		draw_circle(knob, 10.0, UiStyle.PAPER, true, -1.0, true)
