class_name DevMenu
extends PanelContainer
## Developer menu (F12): cheats and tools for testing. Not meant for release builds.

signal speed_requested(speed: float)

const WIDTH := 380.0

var world: World
var _workers: Label
var _ledger: Label
var _instant: CheckButton
var _accum := 0.0
var _body: VBoxContainer
var _sound: SoundDirector
var _board: VBoxContainer           # sound board, folded away until asked for
var _board_btn: Button
var _layer_info := {}               # ambience layer -> Label


func setup(p_world: World) -> void:
	world = p_world
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var p := UiStyle.make_panel("Developer", "build")
	(p["root"] as Control).custom_minimum_size.x = WIDTH
	add_child(p["root"])
	var badge: Label = p["badge"]
	badge.text = "F12"
	badge.visible = true
	(p["close"] as Button).pressed.connect(hide)
	var body: VBoxContainer = p["body"]
	_body = body

	body.add_child(_heading("Workers"))
	_workers = Label.new()
	_workers.theme_type_variation = "SoftLabel"
	body.add_child(_workers)
	body.add_child(_row([
		["+ Worker", _add_worker],
		["− Worker", func() -> void: world.remove_worker()],
	]))

	body.add_child(_heading("Resources"))
	body.add_child(_row([
		["+ 1 000 qk", func() -> void: world.money += 1000; world.stock_changed.emit()],
		["+ seeds", _add_seeds],
		["+ materials", _add_materials],
	]))

	body.add_child(_heading("Build & research"))
	body.add_child(_row([["Unlock all research", func() -> void: world.unlock_all()]]))
	_instant = CheckButton.new()
	_instant.text = "Build free and instantly"
	_instant.tooltip_text = "New sites, roads, fields and upgrades cost nothing and are done at once"
	_instant.focus_mode = Control.FOCUS_NONE
	_instant.toggled.connect(func(on: bool) -> void: world.instant_build = on)
	body.add_child(_instant)

	body.add_child(_heading("Time"))
	var speeds := []
	for s in [5.0, 10.0, 50.0]:
		speeds.append(["%d×" % s, func() -> void: speed_requested.emit(s)])
	body.add_child(_row(speeds))

	body.add_child(_heading("Money in / out"))
	var well := PanelContainer.new()
	well.theme_type_variation = "Well"
	body.add_child(well)
	_ledger = Label.new()
	_ledger.theme_type_variation = "SmallLabel"
	_ledger.add_theme_color_override("font_color", UiStyle.INK)
	well.add_child(_ledger)
	refresh()


## Sound board for tuning the mix: every sound with a play button, every ambience layer with a
## volume multiplier (kept only while the game runs).
func set_sound(director: SoundDirector) -> void:
	_sound = director
	var head := HBoxContainer.new()
	head.add_child(_heading("Sound board"))
	head.get_child(0).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board_btn = Button.new()
	_board_btn.text = "Show"
	_board_btn.focus_mode = Control.FOCUS_NONE
	_board_btn.add_theme_font_size_override("font_size", 14)
	_board_btn.pressed.connect(func() -> void: _board.visible = not _board.visible; _board_btn.text = "Hide" if _board.visible else "Show")
	head.add_child(_board_btn)
	_body.add_child(head)
	_board = VBoxContainer.new()
	_board.add_theme_constant_override("separation", 6)
	_board.hide()
	_body.add_child(_board)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	var names := SoundBank.SOUNDS.keys()
	names.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for name: StringName in names:
		var b := Button.new()
		b.set_meta(&"silent", true)          # no click on top of the sound itself
		b.text = name
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 12)
		b.disabled = not SoundBank.has(name)
		b.tooltip_text = "%d variant(s)" % SoundBank.streams(name).size() if not b.disabled else "No file yet"
		b.pressed.connect(func() -> void: UiStyle.sound(name))
		flow.add_child(b)
	_board.add_child(flow)
	for layer: StringName in SoundBank.LAYERS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var l := Label.new()
		l.text = String(layer).capitalize()
		l.custom_minimum_size.x = 70
		l.add_theme_font_size_override("font_size", 13)
		row.add_child(l)
		var s := HSlider.new()
		s.min_value = 0.0
		s.max_value = 2.0
		s.step = 0.05
		s.value = _sound.layer_mult[layer]
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		s.focus_mode = Control.FOCUS_NONE
		s.value_changed.connect(func(v: float) -> void: _sound.layer_mult[layer] = v; refresh())
		row.add_child(s)
		var info := Label.new()
		info.theme_type_variation = "SoftLabel"
		info.add_theme_font_size_override("font_size", 12)
		info.custom_minimum_size.x = 96
		row.add_child(info)
		_layer_info[layer] = info
		_board.add_child(row)


## --show=dev_sound: the sound board unfolded.
func show_sound_board() -> void:
	if _board and not _board.visible:
		_board_btn.pressed.emit()


func _add_worker() -> void:
	var looks := Worker.Look.values()
	var barn: Variant = world.delivery_target(world.workers[0].cell()) if not world.workers.is_empty() else null
	var cell: Vector2i = barn if barn != null else Vector2i(world.size / 2, world.size / 2)
	world.add_worker(cell, looks[randi() % looks.size()])


## Seed for 100 tiles of every crop.
func _add_seeds() -> void:
	for crop: StringName in Defs.CROPS:
		world.put_goods(Defs.seed_of(crop), Defs.seed_per_tile(crop) * 100.0)
	world.stock_changed.emit()


## 100 planks and gravel for 3 road blocks.
func _add_materials() -> void:
	world.put_goods(&"planks", 100.0)
	world.put_goods(&"gravel", Defs.GRAVEL_PER_BLOCK * 3.0)
	world.stock_changed.emit()


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.theme_type_variation = "SectionLabel"
	return l


func _row(buttons: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for b in buttons:
		var btn := Button.new()
		btn.text = b[0]
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 14)
		btn.pressed.connect(b[1])
		row.add_child(btn)
	return row


func _process(delta: float) -> void:
	if not visible:
		return
	_accum += delta
	if _accum > 0.25:
		_accum = 0.0
		refresh()


func refresh() -> void:
	_workers.text = "%d workers, %d idle" % [world.workers.size(), world.idle_workers()]
	_instant.set_pressed_no_signal(world.instant_build)
	var keys := world.ledger.keys()
	keys.sort()
	var lines := PackedStringArray()
	var total := 0
	for k: String in keys:
		lines.append("%s  %s" % [k.capitalize(), Defs.format_money(world.ledger[k])])
		total += world.ledger[k]
	var minutes := maxf(world.time / 60.0, 0.01)
	lines.append("Balance  %s  (%s / min over %d min)" % [Defs.format_money(total), Defs.format_money(roundi(total / minutes)), int(minutes)])
	_ledger.text = "\n".join(lines)
	for layer: StringName in _layer_info:
		var info: Label = _layer_info[layer]
		info.text = "×%.2f · %d%%" % [_sound.layer_mult[layer], roundi(_sound.level[layer] * 100.0)] \
			if _sound.has_layer(layer) else "×%.2f · no file" % _sound.layer_mult[layer]
