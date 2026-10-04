class_name GameMenu
extends CanvasLayer
## The in-game menu (Esc or the HUD menu button): pauses the game behind a dark dim and leads to
## the save / load dialogs, settings, the main menu and quitting.

const MAIN_MENU := "res://scenes/main_menu.tscn"
const HUD_HEIGHT := 84.0          # the top bar with its margin, left undimmed

var game: Node                    # game.gd: world, save_game(slot, name), last_saved, played
var save_dialog: SaveDialog
var load_dialog: LoadDialog
var settings: SettingsPanel
var _dim: ColorRect
var _panel: Control
var _farm: Label
var _footer: Label
var _thumb: Image
var _leave_box: Control           # "leave without saving?" confirmation
var _leave_text: RichTextLabel
var _leave_sub: Label
var _leave_action: Callable


func setup(p_game: Node) -> void:
	game = p_game
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("debug_show")
	# a clear layer takes the clicks; the visible dim leaves the HUD bar (top 84 px) bright
	_dim = ColorRect.new()
	_dim.color = Color.TRANSPARENT
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)
	var shade := MenuKit.dim()
	shade.offset_top = HUD_HEIGHT
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = _build_panel()
	center.add_child(_panel)
	save_dialog = SaveDialog.new()
	add_child(save_dialog)
	save_dialog.save_requested.connect(func(slot: String, save_name: String) -> void:
		game.save_game(slot, save_name)
		_refresh())
	save_dialog.closed.connect(_back)
	load_dialog = LoadDialog.new()
	add_child(load_dialog)
	load_dialog.load_requested.connect(func(slot: String) -> void: LoadingScreen.start_load(get_tree(), slot))
	load_dialog.closed.connect(_back)
	settings = SettingsPanel.new()
	add_child(settings)
	settings.closed.connect(_back)
	_leave_box = _build_leave()
	add_child(_leave_box)
	_leave_box.hide()
	_set_open(false)


## Main menu / Quit: with progress since the last save the player is asked first. `what_lost` says
## what leaving does ("Going to the main menu will lose those changes.").
func _leave(action: Callable, what_lost := "Going to the main menu will lose those changes.") -> void:
	if not game.has_method("unsaved") or not game.unsaved():
		action.call()
		return
	_leave_action = action
	var saved: int = game.last_saved
	if saved > 0:
		_leave_text.text = "The farm has changed since it was last saved [b](%s)[/b]." % MenuKit.ago(saved)
	else:
		_leave_text.text = "The farm [b]has not been saved yet[/b]."
	_leave_sub.text = what_lost
	_panel.hide()
	_leave_box.show()


func _build_leave() -> Control:
	var wrap := CenterContainer.new()
	wrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var p := MenuKit.dialog("Leave the farm?", 640)
	wrap.add_child(p["root"])
	(p["close"] as Button).pressed.connect(_leave_cancel)
	(p["cancel"] as Button).pressed.connect(_leave_cancel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	(p["body"] as VBoxContainer).add_child(row)
	var icon := UiStyle.icon_rect(UiStyle.icon("warning"), 40)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(icon)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	row.add_child(col)
	_leave_text = RichTextLabel.new()
	_leave_text.bbcode_enabled = true
	_leave_text.fit_content = true
	_leave_text.scroll_active = false
	_leave_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_leave_text.add_theme_font_size_override("normal_font_size", 18)
	_leave_text.add_theme_font_size_override("bold_font_size", 18)
	_leave_text.add_theme_font_override("bold_font", UiStyle.body_font(true))
	_leave_text.add_theme_color_override("default_color", UiStyle.INK)
	col.add_child(_leave_text)
	_leave_sub = MenuKit.label("", "", 15, UiStyle.INK_SOFT)
	_leave_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_leave_sub)
	var foot: HBoxContainer = p["foot"]
	var leave := MenuKit.button("Leave without saving", "DangerButton")
	leave.pressed.connect(func() -> void: _leave_action.call())
	foot.add_child(leave)
	var save := MenuKit.button("Save and leave", "PrimaryButton")
	save.pressed.connect(func() -> void:
		game.save_game("quicksave")
		_leave_action.call())
	foot.add_child(save)
	return wrap


func _leave_cancel() -> void:
	_leave_box.hide()
	_panel.show()


func _build_panel() -> Control:
	var root := PanelContainer.new()
	root.custom_minimum_size.x = 418
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	root.add_child(col)
	var head_box := PanelContainer.new()
	var hb := UiStyle.box(UiStyle.BOARD, UiStyle.WOOD, UiStyle.PANEL_RADIUS, 0)
	hb.border_width_bottom = 2
	hb.corner_radius_bottom_left = 0
	hb.corner_radius_bottom_right = 0
	hb.content_margin_left = 16
	hb.content_margin_top = 10
	hb.content_margin_bottom = 10
	head_box.add_theme_stylebox_override("panel", hb)
	col.add_child(head_box)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	head_box.add_child(header)
	header.add_child(wordmark(22))
	header.add_child(_paused_pill())

	var m := MarginContainer.new()
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 18)
	m.add_theme_constant_override("margin_top", 16)
	m.add_theme_constant_override("margin_bottom", 14)
	col.add_child(m)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	m.add_child(body)
	_farm = MenuKit.label("", "", 15, UiStyle.INK_SOFT)
	_farm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_farm)
	var resume := MenuKit.key_button("Resume", "Esc", "PrimaryButton")
	resume.pressed.connect(close)
	body.add_child(resume)
	var save := MenuKit.key_button("Save game", "F5")
	save.pressed.connect(open_save)
	body.add_child(save)
	var load := MenuKit.key_button("Load game", "F9")
	load.pressed.connect(open_load)
	body.add_child(load)
	var sett := MenuKit.key_button("Settings", "")
	sett.pressed.connect(open_settings)
	body.add_child(sett)
	var line := ColorRect.new()
	line.color = Color("#EADCC1")
	line.custom_minimum_size.y = 2
	body.add_child(line)
	var main := MenuKit.key_button("Main menu", "")
	main.pressed.connect(func() -> void: _leave(func() -> void:
		get_tree().paused = false
		get_tree().change_scene_to_file(MAIN_MENU)))
	body.add_child(main)
	var quit := MenuKit.key_button("Quit game", "", "DangerButton")
	quit.pressed.connect(func() -> void: _leave(func() -> void: get_tree().quit(), "Quitting the game will lose those changes."))
	body.add_child(quit)
	_footer = MenuKit.label("", "", 14, UiStyle.INK_SOFT)
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_footer)
	return root


## "Acres (coin) Quacks" set in Fredoka, for board headers.
static func wordmark(size: int) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 3)
	h.add_child(MenuKit.head("Acres", size, 700))
	var coin := UiStyle.icon_rect(UiStyle.icon("qk"), size * 0.8)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(coin)
	h.add_child(MenuKit.head("Quacks", size, 700))
	return h


func _paused_pill() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UiStyle.box(UiStyle.PAPER, Color.TRANSPARENT, 12)
	sb.content_margin_left = 8
	sb.content_margin_right = 10
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	p.add_child(h)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(14, 14)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.draw.connect(func() -> void:
		icon.draw_circle(Vector2(7, 7), 7, UiStyle.LOCKED_TEXT)
		icon.draw_rect(Rect2(4.5, 4, 1.8, 6), UiStyle.PAPER)
		icon.draw_rect(Rect2(7.7, 4, 1.8, 6), UiStyle.PAPER))
	h.add_child(icon)
	h.add_child(MenuKit.label("Game paused", "", 14, UiStyle.INK))
	return p


func is_open() -> bool:
	return _dim.visible


func open() -> void:
	if is_open():
		return
	# a picture of the farm without the menu and the HUD, for saves made from here
	if DisplayServer.get_name() != "headless" and game.has_method("farm_image"):
		_thumb = await game.farm_image()
		if is_open():
			return
	_set_open(true)
	_panel.show()
	_refresh()


func close() -> void:
	for d: Control in [save_dialog, load_dialog, settings, _leave_box]:
		d.hide()
	_set_open(false)


func toggle() -> void:
	if is_open():
		close()
	else:
		open()


## The picture saved with a save: the farm as it was when the menu opened.
func thumbnail() -> Image:
	return _thumb if is_open() else null


func open_save() -> void:
	_open_dialog()
	save_dialog.open(game.world)


func open_load() -> void:
	_open_dialog()
	load_dialog.open(true)


func open_settings() -> void:
	_open_dialog()
	settings.open(1)


func _open_dialog() -> void:
	if not is_open():
		open()
	_panel.hide()


func _back() -> void:
	_panel.show()
	_refresh()


func _set_open(on: bool) -> void:
	_dim.visible = on
	_panel.get_parent().visible = on
	get_tree().paused = on


func _refresh() -> void:
	var w: World = game.world
	var farm := MenuKit.farm_name(w)
	if farm != "" and w.has_method("day"):
		farm += " · day %d" % int(w.call("day"))
	_farm.text = farm
	_farm.visible = farm != ""
	var parts := []
	var last: int = game.last_saved
	parts.append("Last saved " + MenuKit.ago(last) if last > 0 else "Not saved yet")
	var every: float = Settings.autosave_interval()
	parts.append("autosave every %d min of game time" % roundi(every / 60.0) if every > 0.0 else "autosave off")
	_footer.text = " · ".join(parts)


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_open() or not event.is_pressed() or event.is_echo():
		return
	match (event as InputEventKey).keycode:
		KEY_ESCAPE:
			if _panel.visible:
				get_viewport().set_input_as_handled()
				close()
		KEY_F5:
			if _panel.visible:
				get_viewport().set_input_as_handled()
				open_save()
		KEY_F9:
			if _panel.visible:
				get_viewport().set_input_as_handled()
				open_load()


func debug_show(what: String, _game: Node) -> void:
	if what == "game_menu":
		open()
	elif what == "leave":
		await open()
		_leave(func() -> void: pass)
	elif what in ["save", "load", "delete"] or what.begins_with("settings"):
		_open_dialog()
