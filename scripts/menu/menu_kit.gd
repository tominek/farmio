class_name MenuKit
## Shared pieces of the menus (main menu, game menu, settings, save / load, loading screen): the
## brand images, save badges and rows, time texts, segmented controls, switches and sliders.

const BOARD := "res://assets/ui/brand/wordmark_board.png"
const BOARD_TAGLINE := "res://assets/ui/brand/wordmark_board_tagline.png"
const CHIP := "res://assets/ui/brand/logo_chip.png"

## Save badge colours: fill, text.
const BADGES := {
	"manual": [Color("#E3F0D4"), Color("#36592A")],
	"autosave": [Color("#EEE9DF"), Color("#5E574C")],
	"quicksave": [Color("#DCEAF6"), Color("#1F4E77")],
}
const DIM := Color("#2B1E14")          # modal dim, drawn at 45 %
const LINE := Color("#E4D6BC")         # dialog footer line, card edges
const CARD := Color("#FBF5E8")         # cards inside dialogs (save, fonts)
const ROW_LINE := Color("#EFE4CE")     # line under settings rows
const MUTED := Color("#5E5244")        # "coming later" texts
const DANGER_FILL := Color("#B4472A")
const DANGER_EDGE := Color("#8E3418")
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


# --- brand ---------------------------------------------------------------------------------

## The wordmark as an image: "board", "tagline" (board with the tagline) or "chip" (compact, HUD).
## `height` in px; the width follows the image.
static func logo(kind: String, height: float) -> TextureRect:
	var tex: Texture2D = load({"board": BOARD, "tagline": BOARD_TAGLINE, "chip": CHIP}[kind])
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(height * tex.get_width() / tex.get_height(), height)
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


# --- texts -----------------------------------------------------------------------------------

## "Today 14:32", "Yesterday 21:05", "2 Oct 18:40" (local time).
static func when(unix: int) -> String:
	var bias := int(Time.get_time_zone_from_system()["bias"]) * 60
	var d := Time.get_datetime_dict_from_unix_time(unix + bias)
	var now := Time.get_datetime_dict_from_unix_time(int(Time.get_unix_time_from_system()) + bias)
	var hm := "%02d:%02d" % [d["hour"], d["minute"]]
	var day := int((unix + bias) / 86400.0)
	var today := int((Time.get_unix_time_from_system() + bias) / 86400.0)
	if day == today:
		return "Today " + hm
	if day == today - 1:
		return "Yesterday " + hm
	var text := "%d %s" % [d["day"], MONTHS[d["month"] - 1]]
	if d["year"] != now["year"]:
		text += " %d" % d["year"]
	return text + " " + hm


## "just now", "4 min ago", "2 h ago", "3 days ago".
static func ago(unix: int) -> String:
	var s := int(Time.get_unix_time_from_system()) - unix
	if s < 60:
		return "just now"
	if s < 3600:
		return "%d min ago" % (s / 60)
	if s < 86400:
		return "%d h ago" % (s / 3600)
	return "%d days ago" % (s / 86400) if s >= 172800 else "1 day ago"


## "45 min", "3 h 12 min".
static func duration(seconds: float) -> String:
	var m := int(seconds / 60.0)
	if m < 60:
		return "%d min" % m
	return "%d h %d min" % [m / 60, m % 60]


## "1.2 MB", "640 kB".
static func file_size(bytes: int) -> String:
	if bytes >= 1048576:
		return "%.1f MB" % (bytes / 1048576.0)
	return "%d kB" % maxi(1, bytes / 1024)


## Default name of a new save: "Riverside farm · day 14", or "Farm · 4 Oct 14:32" without a farm name.
static func default_save_name(w: World) -> String:
	var farm := farm_name(w)
	if farm != "":
		return "%s · day %d" % [farm, int(w.call("day"))] if w.has_method("day") else farm
	return "Farm · " + when(int(Time.get_unix_time_from_system())).trim_prefix("Today ").replace("Yesterday ", "")


# --- small pieces ------------------------------------------------------------------------------

static func label(text: String, variation := "", size := 0, color := Color.TRANSPARENT) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	if color.a > 0.0:
		l.add_theme_color_override("font_color", color)
	return l


static func head(text: String, size: int, weight := 600, color := UiStyle.INK) -> Label:
	var l := label(text, "", size, color)
	l.add_theme_font_override("font", UiStyle.head_font(weight))
	return l


## Manual / Autosave / Quicksave tag.
static func badge(kind: String) -> Label:
	var c: Array = BADGES.get(kind, BADGES["manual"])
	var l := label(SaveGame.KIND_NAMES.get(kind, "Manual"), "", 12, c[1])
	l.add_theme_font_override("font", UiStyle.body_font(true))
	var sb := UiStyle.box(c[0], Color.TRANSPARENT, 5)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	l.add_theme_stylebox_override("normal", sb)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


## A framed picture of the saved farm (or an empty frame when there is none).
static func thumb(tex: Texture2D, size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UiStyle.box(UiStyle.PAPER, UiStyle.WOOD, 8, 2)
	sb.set_content_margin_all(2)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tex:
		var r := TextureRect.new()
		r.texture = tex
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(r)
	return p


## "1 840 (coin) · 7 workers" as a row of labels.
static func stats_line(m: Dictionary) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 5)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not m.has("quacks"):
		h.add_child(label("No details stored", "SmallLabel"))
		return h
	if int(m.get("day", 0)) > 0:
		h.add_child(label("Day", "SmallLabel"))
		var d := label(str(int(m["day"])), "", 14, UiStyle.INK)
		d.add_theme_font_override("font", UiStyle.body_font(true))
		h.add_child(d)
		h.add_child(label("·", "SmallLabel"))
	var q := label(UiStyle.money_number(m["quacks"]), "", 14, UiStyle.INK)
	q.add_theme_font_override("font", UiStyle.body_font(true))
	h.add_child(q)
	h.add_child(UiStyle.icon_rect(UiStyle.icon("qk"), 15))
	h.add_child(label("·", "SmallLabel"))
	var w := label(str(int(m["workers"])), "", 14, UiStyle.INK)
	w.add_theme_font_override("font", UiStyle.body_font(true))
	h.add_child(w)
	h.add_child(label("worker" if int(m["workers"]) == 1 else "workers", "SmallLabel"))
	for c in h.get_children():
		if c is Control:
			(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


## A save in a list: thumbnail, name + badge, stats, time and room for buttons on the right.
## Returns { root: Button (toggle, the row itself), right: HBoxContainer }.
static func slot_row(m: Dictionary, thumb_size := Vector2(126, 70)) -> Dictionary:
	var row := Button.new()
	row.toggle_mode = true
	row.focus_mode = Control.FOCUS_NONE
	row.custom_minimum_size.y = thumb_size.y + 24
	var normal := UiStyle.box(Color("#FBF3E6"), Color("#EADCC1"), 12, 2)
	var hover := UiStyle.box(Color("#F6EBD3"), Color("#DCC9A6"), 12, 2)
	var sel := UiStyle.box(UiStyle.SELECT_PAPER, UiStyle.SELECT, 12, 2)
	for s in ["normal", "focus", "disabled"]:
		row.add_theme_stylebox_override(s, normal)
	row.add_theme_stylebox_override("hover", hover)
	row.add_theme_stylebox_override("pressed", sel)
	row.add_theme_stylebox_override("hover_pressed", sel)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(margin)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(h)
	h.add_child(thumb(SaveGame.thumbnail(m["slot"]), thumb_size))
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(col)
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 10)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name := head(m.get("name", m["slot"]), 18)
	title.add_child(name)
	title.add_child(badge(m.get("kind", "manual")))
	col.add_child(title)
	col.add_child(stats_line(m))
	var t := label(when(int(m.get("saved", 0))), "", 14, UiStyle.INK_SOFT)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(t)
	var right := HBoxContainer.new()
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(right)
	for c in [name, t, title.get_child(1)]:
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	return {"root": row, "right": right}


## Full-window warm dark dim behind a modal (the map dims, nothing blurs).
static func dim(alpha := 0.45) -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(DIM, alpha)
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c


# --- dialogs -----------------------------------------------------------------------------------

## A confirmation / one-step dialog: board header (optional icon, title, ✕), a padded body and a
## footer under a thin line with Cancel on the left. Add the actions to `foot` (they go right).
## Returns { root, body: VBoxContainer, foot: HBoxContainer, cancel: Button, close: Button, title: Label }.
static func dialog(title: String, width: float, icon_name := "") -> Dictionary:
	var p := UiStyle.make_panel(title, icon_name)
	var root: PanelContainer = p["root"]
	root.custom_minimum_size.x = width
	header_size(p, 56, 22)
	var body: VBoxContainer = p["body"]
	body.add_theme_constant_override("separation", 14)
	var margin := body.get_parent() as MarginContainer
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	var col := margin.get_parent()
	var line := ColorRect.new()
	line.color = LINE
	line.custom_minimum_size.y = 2
	col.add_child(line)
	var fm := MarginContainer.new()
	fm.add_theme_constant_override("margin_left", 22)
	fm.add_theme_constant_override("margin_right", 22)
	fm.add_theme_constant_override("margin_top", 14)
	fm.add_theme_constant_override("margin_bottom", 18)
	col.add_child(fm)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	fm.add_child(foot)
	var cancel := button("Cancel", "GhostButton", 44)
	cancel.add_theme_color_override("font_color", UiStyle.INK_SOFT)
	cancel.add_theme_color_override("font_hover_color", UiStyle.INK)
	foot.add_child(cancel)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(sp)
	p["foot"] = foot
	p["cancel"] = cancel
	return p


## Header of a make_panel / dialog: fixed height, bigger title, everything centred vertically.
static func header_size(p: Dictionary, height: float, title_size: int) -> void:
	var header: HBoxContainer = p["header"]
	(header.get_parent() as Control).custom_minimum_size.y = height
	(p["title"] as Label).add_theme_font_size_override("font_size", title_size)
	for c in header.get_children():
		(c as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER


## A dialog laid over the whole window: its own dim and the dialog centred. Hidden at first.
static func overlay(dialog_root: Control) -> Control:
	var wrap := Control.new()
	wrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wrap.add_child(dim())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(center)
	center.add_child(dialog_root)
	wrap.hide()
	return wrap


## A kit button: `variation` "" (secondary), PrimaryButton, DangerButton, GhostButton.
static func button(text: String, variation := "", height := 44.0, font_size := 16) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = height
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if font_size != 16:
		b.add_theme_font_size_override("font_size", font_size)
	b.ready.connect(_pad.bind(b, 14))
	return b


## The filled red button of a destructive confirmation ("Delete save").
static func danger_fill(b: Button) -> void:
	var normal := UiStyle.box(DANGER_FILL, DANGER_EDGE, UiStyle.RADIUS, 2, 3)
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = DANGER_FILL.lightened(0.08)
	var pressed := UiStyle.box(DANGER_FILL.darkened(0.05), DANGER_EDGE, UiStyle.RADIUS, 2, 1)
	pressed.content_margin_top = 8
	pressed.content_margin_bottom = 6
	var boxes := {"normal": normal, "hover": hover, "pressed": pressed}
	for s: String in boxes:
		b.add_theme_stylebox_override(s, boxes[s])
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, UiStyle.PAPER)


## A soft paper-deep box with an icon and wrapped text (hints in dialogs).
static func info_box(icon_name: String, text: String, size := 15) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UiStyle.box(UiStyle.PAPER_DEEP, Color.TRANSPARENT, 10)
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	p.add_child(h)
	if icon_name != "":
		var i := UiStyle.icon_rect(UiStyle.icon(icon_name), 22)
		i.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		h.add_child(i)
	var l := label(text, "", size, UiStyle.INK)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	return p


## A card inside a dialog: light paper, thin edge (the save to delete, the fonts in Credits).
static func card(pad := 10) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UiStyle.box(CARD, LINE, 12, 2)
	sb.set_content_margin_all(pad)
	p.add_theme_stylebox_override("panel", sb)
	return p


## A box with a dashed edge: things that are not in the game yet.
static func dashed_box(fill: Color, radius: int, pad_x: int, pad_y: int) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UiStyle.box(fill, Color.TRANSPARENT, radius)
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y
	p.add_theme_stylebox_override("panel", sb)
	p.draw.connect(func() -> void:
		var edge := Color("#B5AD9E")
		var r := float(radius) - 1.0
		var s := p.size - Vector2.ONE
		var o := Vector2.ONE
		p.draw_dashed_line(o + Vector2(r, 0), o + Vector2(s.x - r - 1, 0), edge, 2.0, 6.0)
		p.draw_dashed_line(o + Vector2(r, s.y - 1), o + Vector2(s.x - r - 1, s.y - 1), edge, 2.0, 6.0)
		p.draw_dashed_line(o + Vector2(0, r), o + Vector2(0, s.y - r - 1), edge, 2.0, 6.0)
		p.draw_dashed_line(o + Vector2(s.x - 1, r), o + Vector2(s.x - 1, s.y - r - 1), edge, 2.0, 6.0)
		for c: Array in [[Vector2(r, r), PI], [Vector2(s.x - r - 1, r), PI * 1.5],
				[Vector2(s.x - r - 1, s.y - r - 1), 0.0], [Vector2(r, s.y - r - 1), PI * 0.5]]:
			p.draw_arc(o + c[0], r, c[1], c[1] + PI * 0.5, 8, edge, 2.0, true))
	return p


## A big menu button (main menu): Fredoka 21, optional second line.
static func menu_button(text: String, variation := "", sub := "") -> Button:
	var b := Button.new()
	b.theme_type_variation = variation
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 21)
	b.custom_minimum_size.y = 56
	if sub == "":
		b.text = text
		b.ready.connect(_pad.bind(b, 20))
		return b
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 20
	col.offset_bottom = -3
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fg := UiStyle.PAPER if variation == "PrimaryButton" else UiStyle.INK
	var t := head(text, 21, 600, fg)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(t)
	var s := label(sub, "", 14, Color(fg, 0.9))
	s.name = "Sub"
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(s)
	b.add_child(col)
	b.custom_minimum_size.y = 64
	return b


## Button with a key cap at its right end (game menu).
static func key_button(text: String, key: String, variation := "") -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.y = 46
	b.ready.connect(_pad.bind(b, 18))
	if key != "":
		var cap := UiStyle.key_cap(key)
		cap.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
		cap.position.x -= 14
		cap.position.y -= 2
		if variation == "PrimaryButton":
			cap.add_theme_color_override("font_color", UiStyle.PAPER)
			var sb := UiStyle.box(Color(1, 1, 1, 0.08), Color(UiStyle.PAPER, 0.85), 5, 1)
			sb.content_margin_left = 6
			sb.content_margin_right = 6
			sb.content_margin_top = 0
			sb.content_margin_bottom = 0
			cap.add_theme_stylebox_override("normal", sb)
		b.add_child(cap)
		cap.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	return b


static func _pad(b: Button, px: int) -> void:
	for s in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		var sb := b.get_theme_stylebox(s).duplicate() as StyleBox
		sb.content_margin_left = px
		sb.content_margin_right = px
		b.add_theme_stylebox_override(s, sb)


## Segmented control ("Fullscreen | Borderless | Windowed"). `changed` is called with the index.
static func segmented(options: Array, selected: int, changed: Callable) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UiStyle.box(UiStyle.PAPER_DEEP, UiStyle.BOARD, 10, 2)
	sb.set_content_margin_all(3)
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_SHRINK_END
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 3)
	p.add_child(h)
	var group := ButtonGroup.new()
	var on := UiStyle.box(UiStyle.PAPER, UiStyle.WOOD, 7, 1, 2)
	on.content_margin_top = 3
	on.content_margin_bottom = 3
	var off := UiStyle.box(Color.TRANSPARENT, Color.TRANSPARENT, 7, 2)
	off.content_margin_top = 4
	off.content_margin_bottom = 4
	for sb2: StyleBoxFlat in [on, off]:
		sb2.content_margin_left = 12
		sb2.content_margin_right = 12
	var off_h := off.duplicate() as StyleBoxFlat
	off_h.bg_color = Color(1, 1, 1, 0.45)
	for i in options.size():
		var b := Button.new()
		b.text = options[i]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size.y = 30
		b.add_theme_font_size_override("font_size", 15)
		b.add_theme_stylebox_override("normal", off)
		b.add_theme_stylebox_override("hover", off_h)
		b.add_theme_stylebox_override("pressed", on)
		b.add_theme_stylebox_override("hover_pressed", on)
		b.add_theme_color_override("font_color", UiStyle.INK_SOFT)
		b.add_theme_color_override("font_hover_color", UiStyle.INK)
		b.add_theme_color_override("font_pressed_color", UiStyle.INK)
		b.add_theme_color_override("font_hover_pressed_color", UiStyle.INK)
		b.button_pressed = i == selected
		b.pressed.connect(func() -> void: changed.call(i))
		h.add_child(b)
	return p


static func set_segment(seg: PanelContainer, index: int) -> void:
	var h := seg.get_child(0)
	(h.get_child(index) as Button).set_pressed_no_signal(true)


## An on / off switch. `changed` is called with the new state.
static func switch(on: bool, changed: Callable) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = on
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(48, 28)
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		b.add_theme_stylebox_override(s, empty)
	b.draw.connect(func() -> void:
		var r := Rect2(Vector2.ZERO, b.size)
		var track := UiStyle.box(UiStyle.GO if b.button_pressed else Color("#D9CDB6"), Color("#3A5F29") if b.button_pressed else Color("#BFAF92"), 14, 2)
		b.draw_style_box(track, r)
		var cx := r.size.x - 14.0 if b.button_pressed else 14.0
		b.draw_circle(Vector2(cx, r.size.y * 0.5), 10.0, UiStyle.PAPER))
	b.toggled.connect(func(v: bool) -> void:
		b.queue_redraw()
		changed.call(v))
	return b


## A slider in the kit's look: green fill in a framed track, round paper knob with a hard shadow.
static func slider(min_v: float, max_v: float, step: float, value: float, changed: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.focus_mode = Control.FOCUS_NONE
	s.custom_minimum_size = Vector2(300, 26)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var track := UiStyle.box(ROW_LINE, Color("#D2BF98"), 4, 1)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	s.add_theme_stylebox_override("slider", track)
	var fill := UiStyle.box(UiStyle.GO, Color.TRANSPARENT, 4)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	# the knob is drawn as vectors (crisp at any UI scale); the empty icon only sizes it
	var blank := ImageTexture.create_from_image(Image.create(22, 24, false, Image.FORMAT_RGBA8))
	s.add_theme_icon_override("grabber", blank)
	s.add_theme_icon_override("grabber_highlight", blank)
	s.draw.connect(func() -> void:
		var x := float(s.get_as_ratio()) * (s.size.x - 22.0) + 11.0
		var c := Vector2(x, s.size.y * 0.5 - 1.0)
		var edge := Color("#36592A")
		s.draw_circle(c + Vector2(0, 2), 11.0, edge)
		s.draw_circle(c, 11.0, edge)
		s.draw_circle(c, 9.0, UiStyle.PAPER))
	s.value_changed.connect(changed)
	return s


## Settings row: label (+ optional hint below) on the left, control on the right, thin line under.
static func setting_row(title: String, hint: String, control: Control) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	var h := HBoxContainer.new()
	h.custom_minimum_size.y = 54
	h.add_theme_constant_override("separation", 16)
	v.add_child(h)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	h.add_child(col)
	col.add_child(label(title, "", 16, UiStyle.INK))
	if hint != "":
		var hl := label(hint, "", 13, UiStyle.INK_SOFT)
		hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(hl)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(control)
	var line := ColorRect.new()
	line.color = ROW_LINE
	line.custom_minimum_size.y = 1
	v.add_child(line)
	return v


## Small uppercase heading over a group of rows (Fredoka, a little letter spacing).
static func section(text: String) -> Label:
	var l := label(text.to_upper(), "", 13, UiStyle.INK_SOFT)
	if not _section_font:
		_section_font = FontVariation.new()
		_section_font.base_font = load("res://assets/fonts/Fredoka.ttf")
		_section_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("weight"): 600}
		_section_font.spacing_glyph = 1
	l.add_theme_font_override("font", _section_font)
	return l


static var _section_font: FontVariation


## The farm's name (World.farm_name), "" when the world has none.
static func farm_name(w: World) -> String:
	return String(w.get("farm_name")) if w and "farm_name" in w else ""


## "Riverside farm · day 14" for a save header (name and day when known).
static func save_title(m: Dictionary) -> String:
	var t: String = m.get("farm", "")
	if t == "":
		t = m.get("name", m.get("slot", ""))
	if int(m.get("day", 0)) > 0:
		t += " · day %d" % int(m["day"])
	return t


const FARM_NAMES := ["Riverside farm", "Willow acres", "Duckpond farm", "Meadowbrook", "Old mill farm",
	"Crooked creek", "Sunny acres", "Puddle lane", "Clover hill", "Mallard meadows", "Bramble farm",
	"Featherfield", "Kingfisher acres", "Reed bank farm", "Honeyfield"]


static func random_farm_name() -> String:
	return FARM_NAMES[randi() % FARM_NAMES.size()]
