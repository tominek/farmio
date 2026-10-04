class_name UiStyle
## The game's UI look (art/ui/design: "Acres and Quacks UI Kit"): palette, fonts, the Theme set on
## the window, and small builders for the recurring pieces (panel with a board header, status line,
## chips, progress bars, icon + amount). Panels use these instead of styling controls one by one.
##
## Theme type variations: PrimaryButton (green), DangerButton (red text), GhostButton (flat),
## OpenButton (toggled panel button, blue), TitleLabel / PanelTitle / SectionLabel (Fredoka),
## SmallLabel / SoftLabel (ink soft), Well (paper-deep inset), Chip.

# palette — UI roles (tuned for text contrast on paper) and colours from the 3D scene
const PAPER := Color("#FFFAF0")          # panel fill
const PAPER_DEEP := Color("#F3EBD8")     # wells, chips
const BOARD := Color("#C9A06A")          # panel headers
const WOOD := Color("#8B5A3C")           # borders, hard shadows
const INK := Color("#3B2A1E")            # text
const INK_SOFT := Color("#6B5644")       # labels, units
const GO := Color("#4E7D38")             # primary
const SELECT := Color("#2F6A9C")         # selection, open panels
const SELECT_PAPER := Color("#DCEAF6")
const WARN := Color("#E2683F")           # warning icon, edge
const WARN_PAPER := Color("#FFF1E4")
const SHORT := Color("#A23E22")          # missing, demolish
const DONE := Color("#E3F0D4")           # unlocked
const DONE_EDGE := Color("#5E8F45")
const LOCKED := Color("#EEE9DF")
const LOCKED_EDGE := Color("#BDB5A6")
const LOCKED_TEXT := Color("#7C7468")
const GOLD := Color("#F2C14E")           # the quack coin only
const GRASS := Color("#8DC66A")
const DARK_GRASS := Color("#5E8F45")
const WHEAT := Color("#E7B54A")

const RADIUS := 10
const PANEL_RADIUS := 14

static var _theme: Theme
static var _fonts := {}
static var _icons := {}


# --- fonts -----------------------------------------------------------------------

## Fredoka (rounded, friendly): titles, buttons, node names, tabs. `weight` 400–700.
static func head_font(weight := 600) -> Font:
	var key := "head%d" % weight
	if not _fonts.has(key):
		var fv := FontVariation.new()
		fv.base_font = load("res://assets/fonts/Fredoka.ttf")
		var ts := TextServerManager.get_primary_interface()
		fv.variation_opentype = {ts.name_to_tag("weight"): weight}
		_fonts[key] = fv
	return _fonts[key]


## Atkinson Hyperlegible: body text and every number.
static func body_font(bold := false) -> Font:
	var key := "bold" if bold else "body"
	if not _fonts.has(key):
		_fonts[key] = load("res://assets/fonts/AtkinsonHyperlegible-%s.ttf" % ("Bold" if bold else "Regular"))
	return _fonts[key]


# --- icons -------------------------------------------------------------------------

## Kit icon by name (assets/ui/icons/kit/<name>.svg): qk, wheat, potato, corn, beet, seeds, logs,
## planks, flour, gravel, wheelbarrow, worker, idle, working, walking, locked, warning, plan,
## upgrade, tech, house, field, road, groad, egg, clock, build, move, cut, demolish.
static func icon(name: String) -> Texture2D:
	if not _icons.has(name):
		var path := "res://assets/ui/icons/kit/%s.svg" % name
		_icons[name] = load(path) if ResourceLoader.exists(path) else null
	return _icons[name]


## Icon of a resource of the game (crop, seed, material, product).
static func resource_icon(res: StringName) -> Texture2D:
	var s := String(res)
	if s.begins_with("seed_"):
		return icon("seeds")
	return icon({"wood": "logs", "wheelbarrow": "wheelbarrow"}.get(s, s))


static func icon_rect(tex: Texture2D, size := 20.0) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(size, size)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


# --- style boxes ---------------------------------------------------------------------

## Flat box; a thicker bottom border in the edge colour is the kit's hard drop shadow.
static func box(fill: Color, edge := Color.TRANSPARENT, radius := RADIUS, border := 2, drop := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = edge
	if edge.a > 0.0:
		sb.set_border_width_all(border)
		sb.border_width_bottom = border + drop
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(8)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.anti_aliasing = true
	return sb


## Panel: paper, timber edge, dark soft shadow that lifts it off the bright grass.
static func panel_box() -> StyleBoxFlat:
	var sb := box(PAPER, WOOD, PANEL_RADIUS, 2)
	sb.shadow_color = Color(INK, 0.35)
	sb.shadow_size = 2
	sb.shadow_offset = Vector2(0, 4)
	sb.set_content_margin_all(0)
	return sb


static func _button_boxes(fill: Color, edge: Color, hover: Color) -> Dictionary:
	var normal := box(fill, edge, RADIUS, 2, 3)
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	var h := normal.duplicate() as StyleBoxFlat
	h.bg_color = hover
	var p := box(hover.darkened(0.04), edge, RADIUS, 2, 1)
	p.content_margin_top = 8               # pressed: the face moves 2 px down onto its shadow
	p.content_margin_bottom = 6
	var d := box(Color("#E6E0D3"), Color("#C9C1B1"), RADIUS, 2, 0)
	d.content_margin_top = 7
	d.content_margin_bottom = 8
	return {"normal": normal, "hover": h, "pressed": p, "disabled": d, "focus": StyleBoxEmpty.new()}


# --- theme -----------------------------------------------------------------------------

## The Theme for the whole UI (set on the window once).
static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = 16

	t.set_color("font_color", "Label", INK)
	_label_variation(t, "TitleLabel", head_font(700), 28, INK)
	_label_variation(t, "PanelTitle", head_font(600), 21, INK)
	_label_variation(t, "SectionLabel", head_font(600), 14, INK_SOFT)
	_label_variation(t, "SmallLabel", body_font(), 14, INK_SOFT)
	_label_variation(t, "SoftLabel", body_font(), 16, INK_SOFT)
	_label_variation(t, "NumberLabel", body_font(true), 16, INK)

	t.set_stylebox("panel", "PanelContainer", panel_box())
	t.set_type_variation("Well", "PanelContainer")
	t.set_stylebox("panel", "Well", box(PAPER_DEEP, Color.TRANSPARENT, RADIUS))
	t.set_type_variation("Chip", "PanelContainer")
	var chip := box(PAPER_DEEP, Color.TRANSPARENT, RADIUS)
	chip.content_margin_top = 4
	chip.content_margin_bottom = 4
	t.set_stylebox("panel", "Chip", chip)

	# buttons: secondary by default; Primary / Danger / Ghost / Open as variations
	_button(t, "Button", PAPER, WOOD, Color("#F6EBD3"), INK)
	t.set_font("font", "Button", head_font(600))
	t.set_font_size("font_size", "Button", 16)
	_button(t, "PrimaryButton", GO, Color("#3A5F29"), GO.lightened(0.1), PAPER)
	_button(t, "DangerButton", PAPER, SHORT, Color("#FCE3DA"), SHORT)
	_button(t, "OpenButton", SELECT_PAPER, SELECT, SELECT_PAPER, Color("#1F4E77"))
	t.set_type_variation("GhostButton", "Button")
	var ghost := box(Color.TRANSPARENT, Color.TRANSPARENT, RADIUS)
	ghost.content_margin_top = 6
	ghost.content_margin_bottom = 6
	t.set_stylebox("normal", "GhostButton", ghost)
	var ghost_h := box(PAPER_DEEP, Color.TRANSPARENT, RADIUS)
	ghost_h.content_margin_top = 6
	ghost_h.content_margin_bottom = 6
	t.set_stylebox("hover", "GhostButton", ghost_h)
	t.set_stylebox("pressed", "GhostButton", ghost_h)
	t.set_stylebox("disabled", "GhostButton", ghost)

	# tooltips: dark ink, short hover text only
	var tip := box(INK, Color.TRANSPARENT, 6)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", PAPER)

	# inputs
	var field := box(PAPER, WOOD, 8, 2)
	field.content_margin_top = 4
	field.content_margin_bottom = 4
	t.set_stylebox("normal", "LineEdit", field)
	var field_focus := box(PAPER, SELECT, 8, 2)
	field_focus.content_margin_top = 4
	field_focus.content_margin_bottom = 4
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_color("font_color", "LineEdit", INK)
	t.set_font("font", "LineEdit", body_font(true))
	t.set_color("caret_color", "LineEdit", INK)
	t.set_color("selection_color", "LineEdit", SELECT_PAPER)

	t.set_color("font_color", "CheckBox", INK)
	t.set_color("font_hover_color", "CheckBox", INK)
	t.set_color("font_pressed_color", "CheckBox", INK)
	t.set_font("font", "CheckBox", body_font())
	for s in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		t.set_stylebox(s, "CheckBox", StyleBoxEmpty.new())

	# progress bars: goods colour on paper deep (callers tint the fill)
	t.set_stylebox("background", "ProgressBar", box(PAPER_DEEP, Color("#E3D6BE"), 5, 1))
	t.set_stylebox("fill", "ProgressBar", box(WHEAT, Color.TRANSPARENT, 5))
	t.set_constant("outline_size", "ProgressBar", 0)

	# scroll bars: thin wood
	var grab := box(Color(WOOD, 0.55), Color.TRANSPARENT, 4)
	grab.set_content_margin_all(3)
	for bar in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", bar, box(Color(PAPER_DEEP, 0.6), Color.TRANSPARENT, 4))
		t.set_stylebox("grabber", bar, grab)
		t.set_stylebox("grabber_highlight", bar, grab)
		t.set_stylebox("grabber_pressed", bar, grab)

	# tabs (Dealer: Sell / Buy, Settings)
	var tab_sel := box(PAPER, WOOD, 8, 2)
	tab_sel.border_width_bottom = 0
	tab_sel.corner_radius_bottom_left = 0
	tab_sel.corner_radius_bottom_right = 0
	var tab_un := box(Color("#EADCC1"), Color("#C9A06A"), 8, 2)
	tab_un.border_width_bottom = 0
	tab_un.corner_radius_bottom_left = 0
	tab_un.corner_radius_bottom_right = 0
	t.set_stylebox("tab_selected", "TabBar", tab_sel)
	t.set_stylebox("tab_unselected", "TabBar", tab_un)
	t.set_stylebox("tab_hovered", "TabBar", tab_un)
	t.set_font("font", "TabBar", head_font(600))
	t.set_color("font_selected_color", "TabBar", INK)
	t.set_color("font_unselected_color", "TabBar", INK_SOFT)
	t.set_color("font_hovered_color", "TabBar", INK)

	var popup := box(PAPER, WOOD, 8, 2)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", INK)
	t.set_stylebox("hover", "PopupMenu", box(PAPER_DEEP, Color.TRANSPARENT, 6))
	_theme = t
	return t


static func _label_variation(t: Theme, name: String, font: Font, size: int, color: Color) -> void:
	t.set_type_variation(name, "Label")
	t.set_font("font", name, font)
	t.set_font_size("font_size", name, size)
	t.set_color("font_color", name, color)


static func _button(t: Theme, type: String, fill: Color, edge: Color, hover: Color, text: Color) -> void:
	if type != "Button":
		t.set_type_variation(type, "Button")
	var boxes := _button_boxes(fill, edge, hover)
	for s: String in boxes:
		t.set_stylebox(s, type, boxes[s])
	t.set_color("font_color", type, text)
	t.set_color("font_hover_color", type, text)
	t.set_color("font_pressed_color", type, text)
	t.set_color("font_focus_color", type, text)
	t.set_color("font_hover_pressed_color", type, text)
	t.set_color("font_disabled_color", type, LOCKED_TEXT)
	t.set_color("icon_normal_color", type, Color.WHITE)
	t.set_constant("h_separation", type, 8)
	t.set_constant("icon_max_width", type, 22)


# --- builders ------------------------------------------------------------------------------

## A floating panel: board header (icon, title, optional badge, close ✕) over a paper body.
## Returns { root: PanelContainer, body: VBoxContainer, title: Label, badge: Label, header: HBoxContainer,
## close: Button }. Put the content into `body`.
static func make_panel(title: String, icon_name := "", closable := true) -> Dictionary:
	var root := PanelContainer.new()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	root.add_child(col)
	var head_box := PanelContainer.new()
	var hb := box(BOARD, WOOD, PANEL_RADIUS, 0)
	hb.border_width_bottom = 2
	hb.corner_radius_bottom_left = 0
	hb.corner_radius_bottom_right = 0
	hb.content_margin_left = 16
	hb.content_margin_right = 10
	hb.content_margin_top = 8
	hb.content_margin_bottom = 8
	head_box.add_theme_stylebox_override("panel", hb)
	col.add_child(head_box)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	head_box.add_child(header)
	if icon_name != "":
		header.add_child(icon_rect(icon(icon_name), 24))
	var t := Label.new()
	t.theme_type_variation = "PanelTitle"
	t.text = title
	header.add_child(t)
	var badge := Label.new()
	badge.theme_type_variation = "SmallLabel"
	badge.add_theme_color_override("font_color", INK)
	var bsb := box(Color(PAPER, 0.85), WOOD, 6, 1)
	bsb.content_margin_left = 7
	bsb.content_margin_right = 7
	bsb.content_margin_top = 1
	bsb.content_margin_bottom = 1
	badge.add_theme_stylebox_override("normal", bsb)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.visible = false
	header.add_child(badge)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var close := Button.new()
	close.text = "✕"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(34, 32)
	close.visible = closable
	header.add_child(close)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	col.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	margin.add_child(body)
	return {"root": root, "body": body, "title": t, "badge": badge, "header": header, "close": close}


## Status line kinds: "working" (green), "halted" (warn), "idle" (grey), "walking" (blue).
const STATUS := {
	"working": [DONE, DONE_EDGE, "working"],
	"halted": [WARN_PAPER, WARN, "warning"],
	"idle": [LOCKED, LOCKED_EDGE, "idle"],
	"walking": [SELECT_PAPER, SELECT, "walking"],
}


## A tinted line with a state icon and rich text ("[b]Halted:[/b] full…"). Update with set_status().
static func status_line() -> PanelContainer:
	var p := PanelContainer.new()
	var row := HBoxContainer.new()
	row.name = "HBoxContainer"           # set_status() finds the parts by path
	row.add_theme_constant_override("separation", 10)
	p.add_child(row)
	var ic := icon_rect(icon("idle"), 22)
	ic.name = "Icon"
	row.add_child(ic)
	var text := RichTextLabel.new()
	text.name = "Text"
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_font_override("normal_font", body_font())
	text.add_theme_font_override("bold_font", body_font(true))
	text.add_theme_color_override("default_color", INK)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	set_status(p, "idle", "")
	return p


static func set_status(line: PanelContainer, kind: String, bbcode: String) -> void:
	var s: Array = STATUS.get(kind, STATUS["idle"])
	var sb := box(s[0], s[1], RADIUS, 2)
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	line.add_theme_stylebox_override("panel", sb)
	(line.get_node("HBoxContainer/Icon") as TextureRect).texture = icon(s[2])
	var text := line.get_node("HBoxContainer/Text") as RichTextLabel
	if text.text != bbcode:
		text.text = bbcode


## Progress bar with a goods-coloured fill (turns warn-orange when full).
static func bar(color := WHEAT, height := 10.0) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.custom_minimum_size.y = height
	pb.max_value = 1.0
	pb.step = 0.0
	set_bar_color(pb, color)
	return pb


static func set_bar_color(pb: ProgressBar, color: Color) -> void:
	pb.add_theme_stylebox_override("fill", box(color, Color.TRANSPARENT, 5))


## Icon followed by an amount, e.g. the coin and "1 840" (no "qk": the coin replaces it).
## Returns the HBox; its Label is child 1.
static func amount(icon_name: String, text: String, size := 20.0, bold := true) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.add_child(icon_rect(icon(icon_name), size))
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "NumberLabel" if bold else ""
	h.add_child(l)
	return h


## Money without the unit, for places that show the coin icon next to it: "1 840".
static func money_number(amount_qk: float) -> String:
	return Defs.format_money(amount_qk).trim_suffix(" qk")


## A keyboard key cap shown in buttons and hints ("T", "Esc").
static func key_cap(key: String) -> Label:
	var l := Label.new()
	l.text = key
	l.theme_type_variation = "SmallLabel"
	l.add_theme_color_override("font_color", INK)
	l.add_theme_font_override("font", body_font(true))
	l.add_theme_font_size_override("font_size", 12)
	var sb := box(PAPER_DEEP, WOOD, 5, 1)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	l.add_theme_stylebox_override("normal", sb)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
