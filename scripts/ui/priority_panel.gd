class_name PriorityPanel
extends PanelContainer
## Task priorities (P): the player ranks task categories and can switch them off.
## Waiting tasks still age, so low categories get done eventually.

var world: World
var _rows: VBoxContainer
var _counts := {}           # category -> Label
var _accum := 0.0


func setup(p_world: World) -> void:
	world = p_world
	custom_minimum_size = Vector2(620, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "Task priorities"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "✕"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(hide)
	head.add_child(close)

	var note := Label.new()
	note.text = "Free workers take the most urgent task first, then the nearest one.\nTasks that wait long move up (about one place per %d s), so nothing waits forever." % Defs.TASK_AGING
	note.modulate = Color(1, 1, 1, 0.7)
	box.add_child(note)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	box.add_child(_rows)

	var foot := HBoxContainer.new()
	box.add_child(foot)
	var hint := Label.new()
	hint.text = "Single fields and sites: High / Low in their info panel"
	hint.modulate = Color(1, 1, 1, 0.6)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(hint)
	var reset := Button.new()
	reset.text = "Reset to default"
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(func() -> void:
		world.reset_priorities()
		rebuild())
	foot.add_child(reset)
	rebuild()


func rebuild() -> void:
	for c in _rows.get_children():
		c.queue_free()
	_counts.clear()
	var n := world.category_order.size()
	for i in n:
		var cat: int = world.category_order[i]
		var on := not world.category_off.has(cat)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_rows.add_child(row)

		var rank := Label.new()
		rank.text = "%d." % (i + 1)
		rank.custom_minimum_size.x = 28
		row.add_child(rank)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_constant_override("separation", 0)
		row.add_child(text)
		var name := Label.new()
		name.text = Task.CATEGORY_NAMES[cat][0]
		name.add_theme_font_size_override("font_size", 18)
		text.add_child(name)
		var desc := Label.new()
		desc.text = Task.CATEGORY_NAMES[cat][1]
		desc.add_theme_font_size_override("font_size", 13)
		desc.modulate = Color(1, 1, 1, 0.6)
		text.add_child(desc)
		if not on:
			text.modulate = Color(1, 1, 1, 0.4)

		var count := Label.new()
		count.custom_minimum_size.x = 170
		row.add_child(count)
		_counts[cat] = count
		row.add_child(_button("▲", i > 0, func() -> void:
			world.move_category(cat, -1)
			rebuild()))
		row.add_child(_button("▼", i < n - 1, func() -> void:
			world.move_category(cat, 1)
			rebuild()))
		var toggle := CheckBox.new()
		toggle.text = "On"
		toggle.button_pressed = on
		toggle.focus_mode = Control.FOCUS_NONE
		toggle.toggled.connect(func(v: bool) -> void:
			world.set_category_on(cat, v)
			rebuild())
		row.add_child(toggle)
	refresh()


func _button(text: String, enabled: bool, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(36, 0)
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
	for cat in _counts:
		(_counts[cat] as Label).text = "%d waiting · %d working" % counts[cat]
