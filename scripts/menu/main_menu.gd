extends Node
## Title screen: the logo board and the menu over a live farm (MenuFarm).
##
## Command-line flags of the game scene (--seed, --load, --snap, --shots, --sim, --show, --size, …)
## start the game scene right away, so the usual debug and screenshot commands keep working.
## `--menu` keeps the main menu: then `--snap=<file>` takes a screenshot of it and
## `--menu-show=load|settings|new|credits` opens one of its dialogs first, `play` / `continue`
## start a new game / the newest save through the loading screen (`--loading-snap=<file>` snaps it).

const GAME_SCENE := "res://scenes/game.tscn"
const GAME_FLAGS := ["--seed=", "--size=", "--load=", "--snap=", "--shots=", "--sim=", "--show=", "--at=", "--zoom=", "--yaw="]

var _ui: CanvasLayer
var _menu: Control
var _continue: Button
var _newest := {}
var _load_dialog: LoadDialog
var _settings: SettingsPanel
var _new_farm: Control
var _credits: Control
var _name_edit: LineEdit
var _dim: ColorRect


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.has("--menu"):
		for arg in args:
			for flag: String in GAME_FLAGS:
				if arg.begins_with(flag):
					get_tree().change_scene_to_file.call_deferred(GAME_SCENE)
					return
	get_tree().paused = false
	add_child(MenuFarm.new())
	_build_ui()
	for arg in args:
		if arg.begins_with("--menu-show="):
			match arg.trim_prefix("--menu-show="):
				"load":
					_open_load()
				"settings":
					_open_settings()
				"new":
					_open_new_farm()
				"credits":
					_open_credits()
				"play":
					LoadingScreen.start_new(get_tree(), MenuKit.random_farm_name())
					return
				"continue":
					LoadingScreen.start_load(get_tree(), SaveGame.newest()["slot"])
					return
	for arg in args:
		if arg.begins_with("--snap="):
			var farm: MenuFarm = get_child(0)
			while world_pending(farm):
				await get_tree().process_frame
			for i in 30:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--snap="))
			get_tree().quit()


func world_pending(farm: MenuFarm) -> bool:
	return farm.world == null or not farm._running


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)
	_menu = VBoxContainer.new()
	_menu.position = Vector2(100, 80)
	_menu.custom_minimum_size.x = 560
	_menu.add_theme_constant_override("separation", 24)
	_ui.add_child(_menu)
	var logo := MenuKit.logo("tagline", 150)
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_menu.add_child(logo)

	var panel := PanelContainer.new()
	var sb := UiStyle.box(UiStyle.PAPER, UiStyle.WOOD, 16, 2, 3)
	sb.set_content_margin_all(18)
	sb.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", sb)
	_menu.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	_newest = SaveGame.newest()
	if not _newest.is_empty():
		var sub := MenuKit.save_title(_newest) + " · saved " + MenuKit.ago(int(_newest.get("saved", 0)))
		_continue = MenuKit.menu_button("Continue", "PrimaryButton", sub)
		_continue.pressed.connect(func() -> void: LoadingScreen.start_load(get_tree(), _newest["slot"]))
		col.add_child(_continue)
	var new_game := MenuKit.menu_button("New game")
	new_game.pressed.connect(_open_new_farm)
	col.add_child(new_game)
	var load := MenuKit.menu_button("Load game")
	load.pressed.connect(_open_load)
	load.disabled = _newest.is_empty()
	col.add_child(load)
	var sett := MenuKit.menu_button("Settings")
	sett.pressed.connect(_open_settings)
	col.add_child(sett)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	var credits := Button.new()
	credits.text = "Credits"
	credits.theme_type_variation = "GhostButton"
	credits.focus_mode = Control.FOCUS_NONE
	credits.add_theme_font_size_override("font_size", 17)
	credits.add_theme_color_override("font_color", UiStyle.INK_SOFT)
	credits.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	credits.custom_minimum_size.y = 46
	credits.pressed.connect(_open_credits)
	row.add_child(credits)
	var quit := Button.new()
	quit.text = "Quit"
	quit.theme_type_variation = "DangerButton"
	quit.focus_mode = Control.FOCUS_NONE
	quit.add_theme_font_size_override("font_size", 17)
	quit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quit.custom_minimum_size.y = 46
	quit.pressed.connect(func() -> void: get_tree().quit())
	row.add_child(quit)

	var version := MenuKit.label("v%s" % ProjectSettings.get_setting("application/config/version", "0.1"), "", 14, UiStyle.INK_SOFT)
	var vsb := UiStyle.box(UiStyle.PAPER, Color.TRANSPARENT, 8)
	vsb.content_margin_top = 5
	vsb.content_margin_bottom = 5
	version.add_theme_stylebox_override("normal", vsb)
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	version.position -= Vector2(24, 20)
	_ui.add_child(version)

	_dim = MenuKit.dim(0.45)
	_dim.hide()
	_ui.add_child(_dim)
	_load_dialog = LoadDialog.new()
	_ui.add_child(_load_dialog)
	_load_dialog.load_requested.connect(func(slot: String) -> void: LoadingScreen.start_load(get_tree(), slot))
	_load_dialog.closed.connect(_back)
	_settings = SettingsPanel.new()
	_ui.add_child(_settings)
	_settings.closed.connect(_back)
	_new_farm = _build_new_farm()
	_ui.add_child(_new_farm)
	_credits = _build_credits()
	_ui.add_child(_credits)


func _open_load() -> void:
	_front()
	_load_dialog.open(false)


func _open_settings() -> void:
	_front()
	_settings.open(1)


func _open_new_farm() -> void:
	_front()
	_name_edit.text = MenuKit.random_farm_name()
	_new_farm.show()
	_name_edit.grab_focus()
	_name_edit.select_all()


func _open_credits() -> void:
	_front()
	_credits.show()


func _front() -> void:
	_menu.hide()
	_dim.show()


func _back() -> void:
	for c: Control in [_load_dialog, _settings, _new_farm, _credits]:
		c.hide()
	_dim.hide()
	_menu.show()
	# a deleted save changes Continue
	if not _newest.is_empty() and not SaveGame.exists(_newest["slot"]):
		get_tree().reload_current_scene()


## New game step: name the farm (a friendly suggestion is filled in), then generate it.
func _build_new_farm() -> Control:
	var wrap := CenterContainer.new()
	wrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var p := MenuKit.dialog("Name your farm", 600, "house")
	wrap.add_child(p["root"])
	(p["close"] as Button).pressed.connect(_back)
	(p["cancel"] as Button).pressed.connect(_back)
	var body: VBoxContainer = p["body"]
	body.add_child(MenuKit.section("Farm name"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	body.add_child(row)
	_name_edit = LineEdit.new()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.custom_minimum_size.y = 44
	_name_edit.max_length = 40
	_name_edit.add_theme_color_override("font_selected_color", UiStyle.INK)
	_name_edit.add_theme_color_override("caret_color", UiStyle.SELECT)
	_name_edit.add_theme_font_size_override("font_size", 17)
	var field := UiStyle.box(UiStyle.PAPER, UiStyle.WOOD, 10, 2)
	field.content_margin_left = 14
	field.content_margin_right = 14
	_name_edit.add_theme_stylebox_override("normal", field)
	# focused: blue edge with a light blue ring (drawn over the normal box)
	var focus := UiStyle.box(Color.TRANSPARENT, UiStyle.SELECT, 10, 2)
	_name_edit.add_theme_stylebox_override("focus", focus)
	_name_edit.draw.connect(func() -> void:
		if _name_edit.has_focus():
			var ring := UiStyle.box(Color.TRANSPARENT, Color("#CFE0F0"), 13, 3)
			_name_edit.draw_style_box(ring, Rect2(Vector2(-3, -3), _name_edit.size + Vector2(6, 6))))
	_name_edit.text_submitted.connect(func(_t: String) -> void: _start_new())
	row.add_child(_name_edit)
	var dice := MenuKit.button("Another")
	dice.tooltip_text = "Suggest another name"
	dice.pressed.connect(func() -> void:
		var old := _name_edit.text
		while _name_edit.text == old:
			_name_edit.text = MenuKit.random_farm_name())
	row.add_child(dice)
	body.add_child(MenuKit.info_box("field", "A new map is made for every farm. The name shows in your saves — you can't change it later."))
	var start := MenuKit.button("Start farming", "PrimaryButton", 46, 17)
	start.pressed.connect(_start_new)
	(p["foot"] as HBoxContainer).add_child(start)
	wrap.hide()
	return wrap


func _start_new() -> void:
	var n := _name_edit.text.strip_edges()
	LoadingScreen.start_new(get_tree(), n if n != "" else MenuKit.random_farm_name())


## Credits: the logo board, who made it, the engine and the font licences.
func _build_credits() -> Control:
	var wrap := CenterContainer.new()
	wrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := PanelContainer.new()
	root.custom_minimum_size.x = 660
	wrap.add_child(root)
	var m := MarginContainer.new()
	for side in ["left", "right", "top"]:
		m.add_theme_constant_override("margin_" + side, 36)
	m.add_theme_constant_override("margin_bottom", 28)
	root.add_child(m)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 22)
	m.add_child(col)
	var logo := MenuKit.logo("board", 104)
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(logo)
	var by := VBoxContainer.new()
	by.add_theme_constant_override("separation", 2)
	col.add_child(by)
	var a := MenuKit.label("A game by", "", 15, UiStyle.INK_SOFT)
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	by.add_child(a)
	var who := MenuKit.head("Tominek", 30)
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	by.add_child(who)
	var pill := PanelContainer.new()
	var psb := UiStyle.box(UiStyle.PAPER_DEEP, Color.TRANSPARENT, 16)
	psb.content_margin_left = 14
	psb.content_margin_right = 14
	psb.content_margin_top = 5
	psb.content_margin_bottom = 6
	pill.add_theme_stylebox_override("panel", psb)
	pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 6)
	pill.add_child(ph)
	ph.add_child(MenuKit.label("Made with", "", 15, UiStyle.INK))
	var godot := MenuKit.label("Godot %d" % Engine.get_version_info()["major"], "", 15, UiStyle.INK)
	godot.add_theme_font_override("font", UiStyle.body_font(true))
	ph.add_child(godot)
	col.add_child(pill)
	var fonts := MenuKit.card(0)
	var fsb := fonts.get_theme_stylebox("panel") as StyleBoxFlat
	fsb.content_margin_left = 16
	fsb.content_margin_right = 16
	fsb.content_margin_top = 14
	fsb.content_margin_bottom = 14
	col.add_child(fonts)
	var fc := VBoxContainer.new()
	fc.add_theme_constant_override("separation", 8)
	fonts.add_child(fc)
	fc.add_child(MenuKit.section("Fonts"))
	for f: Array in [["Fredoka", "SIL Open Font License 1.1"],
			["Atkinson Hyperlegible", "SIL Open Font License 1.1 · Braille Institute"]]:
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 12)
		fc.add_child(r)
		var n := MenuKit.head(f[0], 16) if f[0] == "Fredoka" else MenuKit.label(f[0], "", 14, UiStyle.INK)
		if f[0] != "Fredoka":
			n.add_theme_font_override("font", UiStyle.body_font(true))
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(n)
		r.add_child(MenuKit.label(f[1], "", 14, UiStyle.INK_SOFT))
	var close := MenuKit.button("Close", "PrimaryButton")
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(_back)
	col.add_child(close)
	wrap.hide()
	return wrap


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE and (_new_farm.visible or _credits.visible):
		get_viewport().set_input_as_handled()
		_back()
