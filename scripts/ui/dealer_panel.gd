class_name DealerPanel
extends PanelContainer
## Dealer: docked on the right under the HUD. The pickup's trip on top, then two tabs: Sell (auto-sell
## rules per good, the next load, "Send the pickup now") and Buy (seeds, materials, equipment, hiring).

const WIDTH := 640.0
const TOP := 84.0                 # below the HUD
const BOTTOM := 96.0              # above the tool dock
const TRIP_BLUE := Color("#3E7FB5")
const RULE := Color("#EFE4CE")
const SOFT_EDGE := Color("#E4D6BC")
const CARD := Color("#FBF5E8")

var world: World
var _tab := &"sell"
var _tabs := {}                   # &"sell" / &"buy" -> Tab
var _pages := {}                  # &"sell" / &"buy" -> Control
var _accum := 0.0

# pickup strip
var _trip_icon: TextureRect
var _trip_text: RichTextLabel
var _trip_cargo: Label
var _trip_bar: ProgressBar

# sell tab
var _sell_rows := {}              # resource -> {name, stock, price, check, keep, none, icon, ...}
var _load_text: Label
var _load_value: Label
var _send: Button

# buy tab
var _crop := &"wheat"
var _crop_buttons := {}           # crop -> Button
var _seed_qty := {}               # crop -> last amount in the spin
var _seed_spin: Spin
var _seed_info: Label
var _seed_tiles: Label
var _seed_cost: Label
var _seed_order: Button
var _mat_rows := {}               # material -> {row, spin, cost, order, info}
var _orders_chip: PanelContainer
var _orders_text: RichTextLabel
var _barrow_row: Control
var _barrow_info: Label
var _barrow_buy: Button
var _hire_spin: Spin
var _hire_title: Label
var _hire_info: Label
var _hire_cost: Label
var _hire_btn: Button
var _waiting: PanelContainer
var _waiting_text: RichTextLabel
var _waiting_cancel: Button


func setup(p_world: World) -> void:
	world = p_world
	add_to_group("debug_show")
	custom_minimum_size = Vector2(WIDTH, 0)
	var p := UiStyle.make_panel("Dealer", "qk")
	var col: VBoxContainer = p["root"].get_child(0)
	p["root"].remove_child(col)
	p["root"].queue_free()
	add_child(col)
	(p["title"] as Label).add_theme_font_size_override("font_size", 24)
	(p["close"] as Button).pressed.connect(hide)
	var margin: MarginContainer = (p["body"] as Control).get_parent()
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	var body: VBoxContainer = p["body"]
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL

	col.add_child(_trip_strip())
	col.move_child(col.get_child(col.get_child_count() - 1), 1)
	col.add_child(_tab_strip())
	col.move_child(col.get_child(col.get_child_count() - 1), 2)

	_pages[&"sell"] = _sell_page()
	_pages[&"buy"] = _buy_page()
	for k: StringName in _pages:
		body.add_child(_pages[k])
	visibility_changed.connect(func() -> void:
		if visible:
			_dock())
	show_tab(&"sell")


## Docks the panel on the right between the HUD and the tool dock.
func _dock() -> void:
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	offset_left = -WIDTH - 12.0
	offset_right = -12.0
	offset_top = TOP
	offset_bottom = -BOTTOM


## Switches to the Sell or the Buy tab; with a seed (or crop) the Buy tab preselects that crop.
func show_tab(tab: StringName, seed_res := &"") -> void:
	_tab = tab if _pages.has(tab) else &"sell"
	for k: StringName in _pages:
		(_pages[k] as Control).visible = k == _tab
		(_tabs[k] as Tab).set_selected(k == _tab)
	if seed_res != &"":
		var crop := StringName(String(seed_res).trim_prefix("seed_"))
		if Defs.CROPS.has(crop):
			_select_crop(crop)
	if world:
		refresh()


## --show=dealer_sell / dealer_buy (screenshots): opens on that tab; the buy tab with a waiting hire.
## dealer_sell_empty: nothing above "keep in barn"; dealer_buy_orders: planks and gravel on order
## and two waiting hires.
func debug_show(name: String, _game: Node3D) -> void:
	if not name in ["dealer_sell", "dealer_buy", "dealer_sell_empty", "dealer_buy_orders"]:
		return
	if name == "dealer_buy" and world.hires_wanted == 0:
		world.hire(1)
	if name == "dealer_buy_orders":
		world.order(&"planks", 40.0)
		if world.item_unlocked(&"gravel"):
			world.order(&"gravel", 300.0)
		if world.hires_wanted == 0:
			world.hire(2)
	if name == "dealer_sell":
		# sample barn: goods waiting for the pickup, a good kept back, one switched off
		world.stock[&"wheat"] = maxf(world.stock[&"wheat"], 1240.0)
		world.stock[&"flour"] = maxf(world.stock[&"flour"], 410.0)
		world.auto_sell[&"wheat"]["keep"] = 200.0
		world.auto_sell[&"potato"]["on"] = false
		world.auto_sell[&"potato"]["keep"] = 100.0
		world.auto_sell[&"beet"]["on"] = false
	if name == "dealer_sell_empty":
		# everything sold up to the amounts kept: the pickup has nothing to take
		for res: StringName in world.auto_sell:
			if world.auto_sell[res]["on"]:
				world.auto_sell[res]["keep"] = ceilf(world.stock.get(res, 0.0) / 100.0) * 100.0 + 100.0
	show_tab(&"sell" if name.begins_with("dealer_sell") else &"buy")
	show()


# --- pickup strip and tabs ---------------------------------------------------------------------

func _trip_strip() -> PanelContainer:
	var strip := PanelContainer.new()
	var sb := UiStyle.box(UiStyle.PAPER_DEEP, Color.TRANSPARENT, 0)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	strip.add_theme_stylebox_override("panel", sb)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 4)
	strip.add_child(lines)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	lines.add_child(row)
	_trip_icon = UiStyle.icon_rect(UiStyle.icon("walking"), 24)
	row.add_child(_trip_icon)
	_trip_text = RichTextLabel.new()
	_trip_text.bbcode_enabled = true
	_trip_text.fit_content = true
	_trip_text.scroll_active = false
	_trip_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	_trip_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_trip_text.add_theme_font_override("normal_font", UiStyle.body_font())
	_trip_text.add_theme_font_override("bold_font", UiStyle.body_font(true))
	_trip_text.add_theme_font_size_override("normal_font_size", 15)
	_trip_text.add_theme_font_size_override("bold_font_size", 15)
	_trip_text.add_theme_color_override("default_color", UiStyle.INK)
	_trip_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_trip_text)
	_trip_bar = UiStyle.bar(TRIP_BLUE, 10)
	var bg := UiStyle.box(UiStyle.PAPER, Color("#D2BF98"), 5, 1)
	bg.set_content_margin_all(0)
	_trip_bar.add_theme_stylebox_override("background", bg)
	var fill := UiStyle.box(TRIP_BLUE, Color.TRANSPARENT, 5)
	fill.set_content_margin_all(0)
	_trip_bar.add_theme_stylebox_override("fill", fill)
	_trip_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trip_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_trip_bar)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.name = "Spacer"
	row.add_child(spacer)
	var cap := RichTextLabel.new()
	cap.bbcode_enabled = true
	cap.fit_content = true
	cap.scroll_active = false
	cap.autowrap_mode = TextServer.AUTOWRAP_OFF
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cap.add_theme_font_override("normal_font", UiStyle.body_font())
	cap.add_theme_font_override("bold_font", UiStyle.body_font(true))
	cap.add_theme_font_size_override("normal_font_size", 15)
	cap.add_theme_font_size_override("bold_font_size", 15)
	cap.add_theme_color_override("default_color", UiStyle.INK_SOFT)
	cap.text = "up to [b][color=#%s]%s[/color][/b]" % [UiStyle.INK.to_html(false), Defs.format_kg(Defs.PICKUP_CAPACITY)]
	cap.tooltip_text = "What the pickup carries per trip"
	cap.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(cap)
	# what it carries, on its own line under the text
	var cm := MarginContainer.new()
	cm.add_theme_constant_override("margin_left", 36)
	lines.add_child(cm)
	_trip_cargo = _label("", 14, UiStyle.INK_SOFT)
	_trip_cargo.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_trip_cargo.custom_minimum_size.x = 120
	_trip_cargo.mouse_filter = Control.MOUSE_FILTER_PASS
	cm.add_child(_trip_cargo)
	return strip


func _tab_strip() -> PanelContainer:
	var strip := PanelContainer.new()
	var sb := UiStyle.box(UiStyle.PAPER_DEEP, UiStyle.WOOD, 0, 0)
	sb.border_width_bottom = 2
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 4
	sb.content_margin_bottom = 0
	strip.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	strip.add_child(row)
	var sell := Tab.new("Sell", "%d goods" % Defs.SELL_PRICE.size())
	var buy := Tab.new("Buy", "seeds · materials · workers")
	_tabs[&"sell"] = sell
	_tabs[&"buy"] = buy
	for k: StringName in _tabs:
		var t: Tab = _tabs[k]
		t.pressed.connect(func() -> void: show_tab(k))
		row.add_child(t)
	return strip


# --- sell tab -------------------------------------------------------------------------------------

func _sell_page() -> Control:
	var page := VBoxContainer.new()
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 10)
	var scroll := _scroll()
	page.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 0)
	scroll.add_child(list)

	var head := _sell_row_box()
	head.custom_minimum_size.y = 26
	for h: Array in [["Goods", -1, HORIZONTAL_ALIGNMENT_LEFT], ["In barn", 86, HORIZONTAL_ALIGNMENT_RIGHT],
			["Price", 84, HORIZONTAL_ALIGNMENT_RIGHT], ["Auto", 50, HORIZONTAL_ALIGNMENT_CENTER],
			["Keep in barn", 134, HORIZONTAL_ALIGNMENT_CENTER]]:
		var l := _label(h[0], 13, UiStyle.INK_SOFT)
		l.horizontal_alignment = h[2]
		_col_width(l, h[1])
		head.add_child(l)
	list.add_child(head)
	list.add_child(_rule(SOFT_EDGE, 2))

	var first := true
	for res: StringName in Defs.SELL_PRICE:
		if not first:
			list.add_child(_rule(RULE, 1))
		first = false
		list.add_child(_sell_row(res))

	var note := _label("Auto-sell loads everything above “keep in barn” onto every pickup (mills and the sawmill get their share first).", 14, UiStyle.INK_SOFT)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(_gap(12))
	list.add_child(note)

	var foot := PanelContainer.new()
	foot.theme_type_variation = "Well"
	var fsb := UiStyle.box(UiStyle.PAPER_DEEP, Color.TRANSPARENT, 12)
	fsb.content_margin_left = 14
	fsb.content_margin_right = 14
	fsb.content_margin_top = 12
	fsb.content_margin_bottom = 12
	foot.add_theme_stylebox_override("panel", fsb)
	page.add_child(foot)
	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 14)
	foot.add_child(frow)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 2)
	frow.add_child(texts)
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	_load_text = _label("", 14, UiStyle.INK_SOFT)
	_load_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_load_text.custom_minimum_size.x = 100
	_load_text.mouse_filter = Control.MOUSE_FILTER_PASS
	texts.add_child(_load_text)
	var value := UiStyle.amount("qk", "", 20)
	value.move_child(value.get_child(0), 1)
	value.add_theme_constant_override("separation", 5)
	_load_value = value.get_child(0)
	_load_value.add_theme_font_size_override("font_size", 18)
	texts.add_child(value)
	_send = Button.new()
	_send.theme_type_variation = "PrimaryButton"
	_send.text = "Send the pickup now"
	_send.focus_mode = Control.FOCUS_NONE
	_send.custom_minimum_size.y = 44
	_send.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_send.pressed.connect(func() -> void: world.request_trip(); refresh())
	frow.add_child(_send)
	return page


func _sell_row_box() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	return row


func _sell_row(res: StringName) -> Control:
	var row := _sell_row_box()
	row.custom_minimum_size.y = 48
	var name_box := HBoxContainer.new()
	name_box.add_theme_constant_override("separation", 8)
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ic := UiStyle.icon_rect(UiStyle.resource_icon(res), 24)
	name_box.add_child(ic)
	var name_l := _label(Defs.resource_name(res), 15)
	name_box.add_child(name_l)
	row.add_child(name_box)

	var stock := _label("", 15)
	stock.add_theme_font_override("font", UiStyle.body_font(true))
	stock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_col_width(stock, 86)
	row.add_child(stock)

	var price := HBoxContainer.new()
	price.add_theme_constant_override("separation", 3)
	price.alignment = BoxContainer.ALIGNMENT_END
	_col_width(price, 84)
	var pnum := _label(_price_num(Defs.SELL_PRICE[res]), 15)
	pnum.add_theme_font_override("font", UiStyle.body_font(true))
	price.add_child(pnum)
	var coin := UiStyle.icon_rect(UiStyle.icon("qk"), 15)
	price.add_child(coin)
	var unit := _label("each" if Defs.is_piece(res) else "/kg", 15, UiStyle.INK_SOFT)
	price.add_child(unit)
	price.tooltip_text = Defs.format_price(res, Defs.SELL_PRICE[res])
	price.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(price)

	var check_box := CenterContainer.new()
	_col_width(check_box, 50)
	var check := Check.new()
	check.tooltip_text = "Auto-sell: the pickup takes what is above the amount kept in the barn"
	check.toggled.connect(func(v: bool) -> void:
		world.auto_sell[res]["on"] = v
		refresh())
	check_box.add_child(check)
	row.add_child(check_box)

	var keep_box := CenterContainer.new()
	_col_width(keep_box, 134)
	var piece := Defs.is_piece(res)
	var keep := Spin.new(5.0 if piece else 100.0, 0.0, 100000.0, "" if piece else "kg", 32.0)
	keep.custom_minimum_size.x = 134
	keep.changed.connect(func(v: float) -> void:
		world.auto_sell[res]["keep"] = v
		refresh())
	keep_box.add_child(keep)
	var none := _label("none in barn", 13, UiStyle.LOCKED_TEXT)
	keep_box.add_child(none)
	row.add_child(keep_box)

	_sell_rows[res] = {"name": name_l, "icon": ic, "stock": stock, "num": pnum, "coin": coin, "unit": unit,
		"check": check, "keep": keep, "none": none}
	return row


## The pickup's next load: what the "load" step would take now (in the same order, up to its capacity).
func _next_load() -> Array:
	var items: Array = []
	var space := Defs.PICKUP_CAPACITY
	for res: StringName in world.auto_sell:
		var n := minf(world.sellable(res), floorf(space / Defs.weight(res, 1.0)))
		if n > 0.0:
			items.append([res, n])
			space -= Defs.weight(res, n)
	return items


# --- buy tab ------------------------------------------------------------------------------------------

func _buy_page() -> Control:
	var scroll := _scroll()
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 14)
	scroll.add_child(list)

	# what is ordered and comes with the pickup: a blue banner on top
	_orders_chip = PanelContainer.new()
	var osb := UiStyle.box(UiStyle.SELECT_PAPER, TRIP_BLUE, 10, 2)
	osb.content_margin_left = 12
	osb.content_margin_right = 12
	osb.content_margin_top = 8
	osb.content_margin_bottom = 8
	_orders_chip.add_theme_stylebox_override("panel", osb)
	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override("separation", 10)
	_orders_chip.add_child(chip_row)
	chip_row.add_child(UiStyle.icon_rect(UiStyle.icon("walking"), 20))
	_orders_text = _rich(15)
	chip_row.add_child(_orders_text)
	list.add_child(_orders_chip)

	list.add_child(_seeds_card())
	list.add_child(_materials_card())
	list.add_child(_equipment_card())
	list.add_child(_hire_card())
	return scroll


func _card(title: String) -> Array:
	var card := PanelContainer.new()
	var sb := UiStyle.box(CARD, SOFT_EDGE, 12, 2)
	sb.set_content_margin_all(14)
	card.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)
	var t := Label.new()
	t.text = title
	t.add_theme_font_override("font", UiStyle.head_font(600))
	t.add_theme_font_size_override("font_size", 18)
	box.add_child(t)
	return [card, box]


func _seeds_card() -> Control:
	var c := _card("Buy seeds")
	var box: VBoxContainer = c[1]
	# segmented crop selector
	var seg := PanelContainer.new()
	var ssb := UiStyle.box(UiStyle.PAPER_DEEP, UiStyle.BOARD, 10, 2)
	ssb.set_content_margin_all(3)
	seg.add_theme_stylebox_override("panel", ssb)
	seg.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var seg_row := HBoxContainer.new()
	seg_row.add_theme_constant_override("separation", 3)
	seg.add_child(seg_row)
	for crop: StringName in Defs.CROPS:
		var b := Button.new()
		b.text = String(Defs.CROPS[crop]["name"]).trim_prefix("Sugar ").capitalize()
		b.icon = UiStyle.resource_icon(crop)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_constant_override("icon_max_width", 20)
		b.add_theme_constant_override("h_separation", 6)
		b.add_theme_font_size_override("font_size", 14)
		b.custom_minimum_size.y = 34
		b.pressed.connect(func() -> void: _select_crop(crop); refresh())
		seg_row.add_child(b)
		_crop_buttons[crop] = b
		var per_tile := Defs.seed_per_tile(crop)
		var step := pow(10.0, floorf(log(per_tile * 10.0) / log(10.0)))
		_seed_qty[crop] = snappedf(per_tile * 100.0, step)      # enough for 100 tiles
	box.add_child(seg)

	_seed_info = _label("", 13, UiStyle.INK_SOFT)
	_seed_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_seed_info)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	_seed_spin = Spin.new(1.0, 1.0, 10000.0, "kg", 36.0, 84.0, UiStyle.icon("seeds"))
	_seed_spin.changed.connect(func(v: float) -> void:
		_seed_qty[_crop] = v
		refresh())
	row.add_child(_seed_spin)
	_seed_tiles = _label("", 15)
	row.add_child(_seed_tiles)
	var cost := UiStyle.amount("qk", "", 16)
	cost.move_child(cost.get_child(0), 1)
	cost.add_theme_constant_override("separation", 3)
	_seed_cost = cost.get_child(0)
	_seed_cost.add_theme_font_size_override("font_size", 15)
	row.add_child(cost)
	row.add_child(_spacer())
	row.add_child(_button("Max", "", func() -> void:
		var price := Defs.buy_price(Defs.seed_of(_crop))
		var step := _seed_spin.step
		_seed_spin.set_value(maxf(step, floorf(world.money / price / step) * step))))
	_seed_order = _button("Order", "PrimaryButton", func() -> void:
		world.order(Defs.seed_of(_crop), _seed_spin.value)
		refresh())
	row.add_child(_seed_order)
	box.move_child(_seed_info, -1)         # the stock line under the amount
	_select_crop(_crop)
	return c[0]


func _select_crop(crop: StringName) -> void:
	_crop = crop
	for k: StringName in _crop_buttons:
		_style_segment(_crop_buttons[k], k == crop)
	var per_tile := Defs.seed_per_tile(crop)
	var step := pow(10.0, floorf(log(per_tile * 10.0) / log(10.0)))
	_seed_spin.configure(step, step, step * 10000.0)
	_seed_spin.set_value(_seed_qty[crop], false)


func _style_segment(b: Button, on: bool) -> void:
	var sel := UiStyle.box(UiStyle.PAPER, UiStyle.WOOD, 7, 2, 2)
	sel.content_margin_left = 10
	sel.content_margin_right = 10
	sel.content_margin_top = 2
	sel.content_margin_bottom = 2
	var off := UiStyle.box(Color.TRANSPARENT, Color.TRANSPARENT, 7)
	off.content_margin_left = 10
	off.content_margin_right = 10
	off.content_margin_top = 2
	off.content_margin_bottom = 4
	var hover := off.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#EADCC1")
	for s in ["normal", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(s, sel if on else off)
	b.add_theme_stylebox_override("hover", sel if on else hover)
	var text := UiStyle.INK if on else UiStyle.INK_SOFT
	for s in ["font_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(s, text)
	b.add_theme_color_override("font_hover_color", UiStyle.INK)


func _materials_card() -> Control:
	var c := _card("Buy materials")
	var box: VBoxContainer = c[1]
	box.add_theme_constant_override("separation", 8)
	var mats: Array = Defs.MATERIAL_PRICE.keys()
	if mats.has(&"planks"):          # planks first, as in the design
		mats.erase(&"planks")
		mats.push_front(&"planks")
	for res: StringName in mats:
		# one line: name and price, amount, cost, Order; the stock line under it
		var line := _stock_line()
		box.add_child(line["box"])
		var row: HBoxContainer = line["row"]
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(head)
		head.add_child(UiStyle.icon_rect(UiStyle.resource_icon(res), 22))
		head.add_child(_label(Defs.resource_name(res), 15))
		var price := HBoxContainer.new()
		price.add_theme_constant_override("separation", 2)
		price.add_child(_label(_price_num(Defs.MATERIAL_PRICE[res], 2), 15, UiStyle.INK_SOFT))
		price.add_child(UiStyle.icon_rect(UiStyle.icon("qk"), 14))
		price.add_child(_label("each" if Defs.is_piece(res) else "/kg", 15, UiStyle.INK_SOFT))
		head.add_child(price)
		# in hand loads; by default enough for a Storage Barn of planks / a road block of gravel
		var planks := res == &"planks"
		var step := Defs.hand_load(res)
		var spin := Spin.new(step, step, step * 1000.0, "" if Defs.is_piece(res) else "kg", 32.0, 72.0)
		spin.set_value(Defs.def(&"storage_barn")["material"][&"planks"] if planks else Defs.GRAVEL_PER_BLOCK, false)
		spin.changed.connect(func(_v: float) -> void: refresh())
		spin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(spin)
		var cost_box := _cost_box()
		row.add_child(cost_box)
		var cost: Label = cost_box.get_child(0)
		var order := _button("Order", "PrimaryButton", func() -> void:
			world.order(res, spin.value)
			refresh())
		order.add_theme_font_size_override("font_size", 14)
		row.add_child(order)
		_mat_rows[res] = {"row": line["box"], "info": line["info"], "spin": spin, "cost": cost, "order": order}
	var note := _label("Orders are paid now and come with the next pickup.", 13, UiStyle.INK_SOFT)
	box.add_child(note)
	return c[0]


## A line of the Buy tab: a row (filled by the caller) and the stock line under it, a rule below.
func _stock_line() -> Dictionary:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.TRANSPARENT
	sb.border_color = RULE
	sb.border_width_bottom = 1
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	p.add_child(v)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 30)
	v.add_child(m)
	var info := _label("", 13, UiStyle.INK_SOFT)
	info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.custom_minimum_size.x = 60
	m.add_child(info)
	return {"box": p, "row": row, "info": info}


## "160 (coin)": a bold cost right-aligned in 56 px.
func _cost_box() -> HBoxContainer:
	var cost_box := UiStyle.amount("qk", "", 15)
	cost_box.move_child(cost_box.get_child(0), 1)
	cost_box.add_theme_constant_override("separation", 3)
	cost_box.alignment = BoxContainer.ALIGNMENT_END
	cost_box.custom_minimum_size.x = 56
	(cost_box.get_child(0) as Label).add_theme_font_size_override("font_size", 15)
	(cost_box.get_child(0) as Label).add_theme_font_override("font", UiStyle.body_font(true))
	return cost_box


func _equipment_card() -> Control:
	var c := _card("Equipment")
	var box: VBoxContainer = c[1]
	_barrow_row = HBoxContainer.new()
	_barrow_row.add_theme_constant_override("separation", 10)
	box.add_child(_barrow_row)
	_barrow_row.add_child(UiStyle.icon_rect(UiStyle.icon("wheelbarrow"), 32))
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 0)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_barrow_row.add_child(texts)
	var name_l := _label("Wheelbarrow", 15)
	name_l.add_theme_font_override("font", UiStyle.body_font(true))
	texts.add_child(name_l)
	_barrow_info = _label("", 13, UiStyle.INK_SOFT)
	_barrow_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_barrow_info.custom_minimum_size.x = 120
	texts.add_child(_barrow_info)
	var price := UiStyle.amount("qk", UiStyle.money_number(Defs.WHEELBARROW_PRICE), 15)
	price.move_child(price.get_child(0), 1)
	price.add_theme_constant_override("separation", 3)
	(price.get_child(0) as Label).add_theme_font_size_override("font_size", 15)
	_barrow_row.add_child(price)
	_barrow_buy = _button("Buy", "PrimaryButton", func() -> void:
		world.order(&"wheelbarrow", 1.0)
		refresh())
	_barrow_buy.add_theme_font_size_override("font_size", 14)
	_barrow_row.add_child(_barrow_buy)
	# what the Equipment branch of the research tree promises for later
	var branch := Tech.BRANCHES.find("Equipment")
	for id: StringName in Tech.NODES:
		var n: Dictionary = Tech.NODES[id]
		if n["branch"] != branch or not Tech.is_later(id):
			continue
		var later := Dashed.new()
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		later.add_child(row)
		var ic := UiStyle.icon_rect(UiStyle.icon("tech"), 22)
		ic.modulate.a = 0.45
		row.add_child(ic)
		row.add_child(_label("%s · coming later" % n["name"], 14, Color("#6E665B")))
		later.tooltip_text = n.get("desc", "")
		box.add_child(later)
	return c[0]


func _hire_card() -> Control:
	var c := _card("Hire workers")
	var box: VBoxContainer = c[1]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	row.add_child(UiStyle.icon_rect(UiStyle.icon("worker"), 28))
	# the price of one hire: "250 (coin) each"
	var each := HBoxContainer.new()
	each.add_theme_constant_override("separation", 3)
	each.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	each.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(each)
	_hire_title = _label("", 15)
	each.add_child(_hire_title)
	each.add_child(_centered_icon("qk", 14))
	_hire_info = _label("each", 15)
	each.add_child(_hire_info)
	_hire_spin = Spin.new(1.0, 1.0, 20.0, "", 32.0, 72.0)
	_hire_spin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hire_spin.changed.connect(func(_v: float) -> void: refresh())
	row.add_child(_hire_spin)
	var cost := _cost_box()
	_hire_cost = cost.get_child(0)
	row.add_child(cost)
	_hire_btn = _button("Hire", "PrimaryButton", func() -> void:
		world.hire(int(_hire_spin.value))
		refresh())
	_hire_btn.add_theme_font_size_override("font_size", 14)
	row.add_child(_hire_btn)

	_waiting = PanelContainer.new()
	var wsb := UiStyle.box(UiStyle.PAPER_DEEP, Color.TRANSPARENT, 10)
	wsb.content_margin_left = 10
	wsb.content_margin_right = 10
	wsb.content_margin_top = 6
	wsb.content_margin_bottom = 6
	_waiting.add_theme_stylebox_override("panel", wsb)
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 10)
	_waiting.add_child(wrow)
	_waiting_text = RichTextLabel.new()
	_waiting_text.bbcode_enabled = true
	_waiting_text.fit_content = true
	_waiting_text.scroll_active = false
	_waiting_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_waiting_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_waiting_text.add_theme_font_override("normal_font", UiStyle.body_font())
	_waiting_text.add_theme_font_override("bold_font", UiStyle.body_font(true))
	_waiting_text.add_theme_font_size_override("normal_font_size", 14)
	_waiting_text.add_theme_font_size_override("bold_font_size", 14)
	_waiting_text.add_theme_color_override("default_color", UiStyle.INK)
	_waiting_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrow.add_child(_waiting_text)
	_waiting_cancel = _button("Cancel", "DangerButton", func() -> void:
		world.cancel_hires()
		refresh())
	_waiting_cancel.add_theme_font_size_override("font_size", 14)
	_waiting_cancel.tooltip_text = "Call off the waiting hires and get their fees back"
	wrow.add_child(_waiting_cancel)
	box.add_child(_waiting)
	return c[0]


# --- refresh ----------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not visible:
		return
	_accum += delta
	if _accum > 0.25:
		_accum = 0.0
		refresh()


func refresh() -> void:
	if world == null:
		return
	_refresh_trip()
	if _tab == &"sell":
		_refresh_sell()
	else:
		_refresh_buy()


func _refresh_trip() -> void:
	var v: Vehicle = world.vehicles[0] if not world.vehicles.is_empty() else null
	var status := world.trip_status
	var text := status.left(1).to_lower() + status.substr(1) if not status.begins_with("Can't") else status
	_trip_text.text = "[b]Pickup[/b] %s" % text
	var kind := "walking"
	if v == null or v.parked:
		kind = "idle"
	if status.begins_with("Can't") or status.contains("not by a road"):
		kind = "warning"
	_trip_icon.texture = UiStyle.icon(kind)
	var parts := PackedStringArray()
	if v:
		for res: StringName in v.cargo:
			parts.append(Defs.format_goods(res, v.cargo[res]))
		if not v.passengers.is_empty():
			parts.append("%d new worker%s" % [v.passengers.size(), "" if v.passengers.size() == 1 else "s"])
	_trip_cargo.text = ("carrying " + ", ".join(parts)) if not parts.is_empty() else ""
	_trip_cargo.tooltip_text = _trip_cargo.text
	_trip_cargo.get_parent().visible = not parts.is_empty()
	var progress := _trip_progress(v)
	_trip_bar.visible = progress >= 0.0
	_trip_bar.get_parent().get_node("Spacer").visible = progress < 0.0
	if progress >= 0.0:
		_trip_bar.value = progress


## How far the pickup is through its planned trip legs (0–1), or -1 when it is not on a trip.
## Each leg counts the same; a drive leg advances with its route.
func _trip_progress(v: Vehicle) -> float:
	if v == null or v.parked or v.driver == null or v.driver.task == null:
		return -1.0
	var t := v.driver.task
	if t.kind != Task.Kind.TRIP or t.steps.is_empty():
		return -1.0
	var part := 0.0
	if t.step_i < t.steps.size() and t.steps[t.step_i]["type"] == "drive" and t.route.size() > 0:
		part = float(t.route_i) / t.route.size()
	return clampf((t.step_i + part) / t.steps.size(), 0.0, 1.0)


func _refresh_sell() -> void:
	for res: StringName in _sell_rows:
		var r: Dictionary = _sell_rows[res]
		var rule: Dictionary = world.auto_sell.get(res, {"on": false, "keep": 0.0})
		var have: float = world.stock.get(res, 0.0)
		var muted: bool = have < 0.5 and not rule["on"]
		(r["stock"] as Label).text = _qty(res, have)
		(r["check"] as Check).set_state(rule["on"], muted)
		var keep: Spin = r["keep"]
		keep.set_value(rule["keep"], false)
		keep.visible = not muted
		(r["none"] as Label).visible = muted
		var ink := UiStyle.LOCKED_TEXT if muted else UiStyle.INK
		(r["name"] as Label).add_theme_color_override("font_color", ink)
		(r["stock"] as Label).add_theme_color_override("font_color", ink)
		(r["stock"] as Label).add_theme_font_override("font", UiStyle.body_font(not muted))
		(r["num"] as Label).add_theme_color_override("font_color", ink)
		(r["num"] as Label).add_theme_font_override("font", UiStyle.body_font(not muted))
		(r["unit"] as Label).add_theme_color_override("font_color", UiStyle.LOCKED_TEXT if muted else UiStyle.INK_SOFT)
		(r["icon"] as TextureRect).modulate.a = 0.55 if muted else 1.0
		(r["coin"] as TextureRect).modulate.a = 0.55 if muted else 1.0
	var items := _next_load()
	var parts := PackedStringArray()
	var value := 0.0
	for it: Array in items:
		parts.append(Defs.format_goods(it[0], it[1]))
		value += it[1] * Defs.SELL_PRICE[it[0]]
	if items.is_empty():
		_load_text.text = "Nothing above “keep in barn” to sell"
	else:
		_load_text.text = "Next load · " + ", ".join(parts)
	_load_text.tooltip_text = _load_text.text
	_load_value.text = "≈ " + UiStyle.money_number(value)
	_load_value.get_parent().visible = not items.is_empty()
	_send.disabled = items.is_empty()
	_send.tooltip_text = "Nothing to sell: switch on auto-sell or keep less in the barn" if items.is_empty() \
		else "Go now, even with less than %s" % Defs.format_kg(Defs.MIN_TRIP_LOAD)


func _refresh_buy() -> void:
	var ordered := PackedStringArray()
	for res: StringName in world.orders:
		if world.orders[res] > 0.0:
			ordered.append(Defs.format_goods(res, world.orders[res]) if Defs.is_piece(res) or res == &"gravel" \
				else "%s %s" % [Defs.format_amount(res, world.orders[res]), Defs.resource_name(res).to_lower()])
	_orders_chip.visible = not ordered.is_empty()
	var t := "[b]On order:[/b] %s — comes with the %s" % [", ".join(ordered), "next pickup"]
	if _orders_text.text != t:
		_orders_text.text = t

	# seeds
	var seed := Defs.seed_of(_crop)
	var price := Defs.buy_price(seed)
	var info := "%s · %s" % [Defs.resource_name(seed), Defs.format_price(seed, price)]
	info += " · in barn %s" % Defs.format_amount(seed, world.stock.get(seed, 0.0))
	info += " · ordered %s" % Defs.format_amount(seed, world.orders.get(seed, 0.0))
	_seed_info.text = info
	var tiles := floori(_seed_spin.value / Defs.seed_per_tile(_crop) + 0.0001)
	_seed_tiles.text = "≈ %s tile%s ·" % [UiStyle.money_number(tiles), "" if tiles == 1 else "s"]
	var cost := world.order_cost(seed, _seed_spin.value)
	_seed_cost.text = UiStyle.money_number(cost)
	_seed_order.disabled = cost > world.money

	# materials
	for res: StringName in _mat_rows:
		var r: Dictionary = _mat_rows[res]
		var on := world.item_unlocked(res)
		(r["row"] as Control).visible = on
		if not on:
			continue
		var spin: Spin = r["spin"]
		var c := world.order_cost(res, spin.value)
		(r["cost"] as Label).text = UiStyle.money_number(c)
		(r["order"] as Button).disabled = c > world.money
		# stock line: "in barn 300 kg · ordered 300 kg · ≈ 3 road blocks"
		var bits := PackedStringArray()
		bits.append("in barn %s" % _qty(res, world.stock.get(res, 0.0)))
		bits.append("ordered %s" % _qty(res, world.orders.get(res, 0.0)))
		if res == &"gravel":
			var blocks := floori(spin.value / Defs.GRAVEL_PER_BLOCK + 0.0001)
			bits.append("≈ %d road block%s" % [blocks, "" if blocks == 1 else "s"])
		(r["info"] as Label).text = " · ".join(bits)

	# equipment
	_barrow_row.visible = world.item_unlocked(&"wheelbarrow")
	var have := int(world.stock.get(&"wheelbarrow", 0.0))
	for w in world.workers:
		if w.equipment == &"wheelbarrow":
			have += 1
	var barrow := "carries %s instead of %s · you have %d" % [Defs.format_kg(Defs.WHEELBARROW_CAPACITY), Defs.format_kg(Defs.CARRY_CAPACITY), have]
	if world.orders.get(&"wheelbarrow", 0.0) > 0.0:
		barrow += " · %d ordered" % int(world.orders[&"wheelbarrow"])
	_barrow_info.text = barrow
	_barrow_buy.disabled = Defs.WHEELBARROW_PRICE > world.money

	# hiring
	var n := int(_hire_spin.value)
	var hire_cost := world.hire_cost(n)
	var first := world.hire_cost(1)
	# the fee may rise with the size of the farm: then the first one's price and "next"
	_hire_title.text = UiStyle.money_number(first)
	_hire_info.text = "each" if hire_cost == first * n else "the next one"
	(_hire_title.get_parent() as Control).tooltip_text = "%d worker%s on the farm · %d ride along per pickup" % [
		world.workers.size(), "" if world.workers.size() == 1 else "s", Defs.PICKUP_SEATS - 1]
	_hire_cost.text = UiStyle.money_number(hire_cost)
	_hire_btn.disabled = hire_cost > world.money
	var v: Vehicle = world.vehicles[0] if not world.vehicles.is_empty() else null
	var riding := v.passengers.size() if v else 0
	_waiting.visible = world.hires_wanted > 0 or riding > 0
	var wt := ""
	if world.hires_wanted > 0:
		wt = "Waiting hires: [b]%d[/b] — %s with the next pickup" % [world.hires_wanted, "arrives" if world.hires_wanted == 1 else "arrive"]
	if riding > 0:
		wt += (" · [b]%d[/b] on the pickup now" if wt != "" else "Waiting hires: [b]%d[/b] — on the pickup now") % riding
	if _waiting_text.text != wt:
		_waiting_text.text = wt
	_waiting_cancel.visible = world.hires_wanted > 0


# --- small helpers --------------------------------------------------------------------------------

## Wrapping text with [b]old[/b] parts.
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


func _label(text: String, size := 15, color := UiStyle.INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _button(text: String, variation: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(on_pressed)
	return b


func _scroll() -> ScrollContainer:
	var s := ScrollContainer.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UiStyle.slim_scrollbars(s)
	return s


func _rule(color: Color, height: int) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size.y = height
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _gap(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = height
	return c


func _centered_icon(name: String, size: float) -> TextureRect:
	var r := UiStyle.icon_rect(UiStyle.icon(name), size)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return r


func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


func _col_width(c: Control, width: float) -> void:
	if width < 0.0:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		c.custom_minimum_size.x = width


## "2", "1.5", "0.35" (or with a fixed number of decimals: "0.40").
static func _price_num(p: float, decimals := -1) -> String:
	if p == floorf(p):
		return "%d" % p
	if decimals > 0:
		return String.num(p, decimals).pad_decimals(decimals)
	return String.num(p, 2)


## Stock in a table cell: "1 240 kg", logs and planks as a plain count ("120").
static func _qty(res: StringName, amount: float) -> String:
	if Defs.is_piece(res):
		return UiStyle.money_number(floorf(amount + 0.0001))
	if amount > 0.0 and amount < 10.0:
		return Defs.format_kg(amount)
	return "%s kg" % UiStyle.money_number(amount)


# --- kit controls -------------------------------------------------------------------------------------

## Kit spin box: [−] value unit [+]. The value can also be typed; − is disabled at the minimum.
class Spin extends PanelContainer:
	signal changed(value: float)

	var value := 0.0
	var step := 1.0
	var min_value := 0.0
	var max_value := 100.0
	var unit := ""
	var _minus: Button
	var _plus: Button
	var _edit: LineEdit

	func _init(p_step: float, p_min: float, p_max: float, p_unit: String, height := 32.0, field_w := 70.0, icon: Texture2D = null) -> void:
		unit = p_unit
		var sb := UiStyle.box(UiStyle.PAPER, UiStyle.WOOD, 8, 2)
		sb.set_content_margin_all(2)
		add_theme_stylebox_override("panel", sb)
		custom_minimum_size.y = height
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		add_child(row)
		_minus = _side("−", true)
		_minus.pressed.connect(func() -> void: set_value(value - step))
		row.add_child(_minus)
		var mid := HBoxContainer.new()
		mid.add_theme_constant_override("separation", 4)
		mid.alignment = BoxContainer.ALIGNMENT_CENTER
		mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mid.custom_minimum_size.x = field_w
		row.add_child(mid)
		if icon:
			mid.add_child(UiStyle.icon_rect(icon, 16))
		_edit = LineEdit.new()
		_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
		_edit.expand_to_text_length = true
		_edit.flat = true
		var empty := StyleBoxEmpty.new()
		for s in ["normal", "focus", "read_only"]:
			_edit.add_theme_stylebox_override(s, empty)
		_edit.add_theme_font_size_override("font_size", 14 if height <= 32.0 else 15)
		_edit.select_all_on_focus = true
		_edit.text_submitted.connect(func(_t: String) -> void: _commit())
		_edit.focus_exited.connect(_commit)
		mid.add_child(_edit)
		_plus = _side("+", false)
		_plus.pressed.connect(func() -> void: set_value(value + step))
		row.add_child(_plus)
		configure(p_step, p_min, p_max)
		set_value(p_min, false)

	func configure(p_step: float, p_min: float, p_max: float) -> void:
		step = p_step
		min_value = p_min
		max_value = p_max

	func set_value(v: float, emit := true) -> void:
		v = clampf(snappedf(v, step), min_value, max_value)
		var same := is_equal_approx(v, value)
		value = v
		if not _edit.has_focus():
			_edit.text = _format(v)
		_minus.disabled = value <= min_value + step * 0.001
		_plus.disabled = value >= max_value - step * 0.001
		if emit and not same:
			changed.emit(value)

	func _commit() -> void:
		var typed := _edit.text.replace(" ", "").replace(",", ".")
		var v := typed.to_float() if typed != "" else value
		_edit.release_focus()
		_edit.text = _format(value)
		set_value(v)

	func _format(v: float) -> String:
		var decimals := 0 if step >= 1.0 else ceili(-log(step) / log(10.0) - 0.0001)
		var n := String.num(v, decimals).pad_decimals(decimals) if decimals > 0 else UiStyle.money_number(v)
		return n + (" " + unit if unit != "" else "")

	func _side(text: String, left: bool) -> Button:
		var b := Button.new()
		b.text = text
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size.x = 28
		var styles := {
			"normal": [UiStyle.PAPER_DEEP, UiStyle.BOARD],
			"hover": [Color("#EADCC1"), UiStyle.BOARD],
			"pressed": [Color("#E2D2B4"), UiStyle.BOARD],
			"disabled": [UiStyle.LOCKED, Color("#D6CEBF")],
		}
		for s: String in styles:
			var sb := StyleBoxFlat.new()
			sb.bg_color = styles[s][0]
			sb.border_color = styles[s][1]
			if left:
				sb.border_width_right = 2
				sb.corner_radius_top_left = 6
				sb.corner_radius_bottom_left = 6
			else:
				sb.border_width_left = 2
				sb.corner_radius_top_right = 6
				sb.corner_radius_bottom_right = 6
			sb.set_content_margin_all(0)
			b.add_theme_stylebox_override(s, sb)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.add_theme_font_size_override("font_size", 17)
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(c, UiStyle.INK)
		b.add_theme_color_override("font_disabled_color", UiStyle.LOCKED_EDGE)
		return b


## Kit checkbox: a 24 px box, green with a tick when on; greyed when the row is muted.
class Check extends Control:
	signal toggled(on: bool)

	var on := false
	var muted := false

	func _init() -> void:
		custom_minimum_size = Vector2(24, 24)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func set_state(p_on: bool, p_muted: bool) -> void:
		if p_on != on or p_muted != muted:
			on = p_on
			muted = p_muted
			queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			on = not on
			queue_redraw()
			toggled.emit(on)
			accept_event()

	func _draw() -> void:
		var fill := UiStyle.PAPER
		var edge := UiStyle.WOOD
		if on:
			fill = UiStyle.GO
			edge = Color("#36592A")
		elif muted:
			fill = Color("#E6E0D3")
			edge = Color("#C9C1B1")
		var sb := UiStyle.box(fill, edge, 6, 2)
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		if on:
			var s := size
			draw_polyline(PackedVector2Array([s * Vector2(0.27, 0.52), s * Vector2(0.43, 0.68), s * Vector2(0.74, 0.33)]),
				UiStyle.PAPER, 2.6, true)


## A dashed rounded outline (things that come later).
class Dashed extends PanelContainer:
	const EDGE := Color("#B5AD9E")

	func _init() -> void:
		var sb := StyleBoxEmpty.new()
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		add_theme_stylebox_override("panel", sb)

	func _draw() -> void:
		var r := 10.0
		var a := Vector2(1, 1)
		var b := size - Vector2(1, 1)
		var dash := 5.0
		draw_dashed_line(Vector2(a.x + r, a.y), Vector2(b.x - r, a.y), EDGE, 2.0, dash)
		draw_dashed_line(Vector2(a.x + r, b.y), Vector2(b.x - r, b.y), EDGE, 2.0, dash)
		draw_dashed_line(Vector2(a.x, a.y + r), Vector2(a.x, b.y - r), EDGE, 2.0, dash)
		draw_dashed_line(Vector2(b.x, a.y + r), Vector2(b.x, b.y - r), EDGE, 2.0, dash)
		draw_arc(Vector2(a.x + r, a.y + r), r, PI, PI * 1.5, 6, EDGE, 2.0, true)
		draw_arc(Vector2(b.x - r, a.y + r), r, PI * 1.5, TAU, 6, EDGE, 2.0, true)
		draw_arc(Vector2(b.x - r, b.y - r), r, 0.0, PI * 0.5, 6, EDGE, 2.0, true)
		draw_arc(Vector2(a.x + r, b.y - r), r, PI * 0.5, PI, 6, EDGE, 2.0, true)


## A tab of the Dealer: a title and a small subtitle; the selected one is taller and joins the page.
class Tab extends MarginContainer:
	signal pressed

	var _panel: PanelContainer
	var _title: Label
	var _sub: Label
	var _selected := false

	func _init(title: String, sub: String) -> void:
		size_flags_vertical = Control.SIZE_SHRINK_END
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_panel = PanelContainer.new()
		_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_panel)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(row)
		_title = Label.new()
		_title.text = title
		_title.add_theme_font_override("font", UiStyle.head_font(600))
		_title.add_theme_font_size_override("font_size", 17)
		row.add_child(_title)
		_sub = Label.new()
		_sub.text = sub
		_sub.add_theme_font_size_override("font_size", 13)
		_sub.add_theme_color_override("font_color", UiStyle.INK_SOFT)
		row.add_child(_sub)
		set_selected(false)

	func set_selected(on: bool) -> void:
		_selected = on
		var sb := UiStyle.box(UiStyle.PAPER if on else Color("#E9DCC2"), UiStyle.WOOD if on else UiStyle.BOARD, 10, 2)
		sb.border_width_bottom = 0
		sb.corner_radius_bottom_left = 0
		sb.corner_radius_bottom_right = 0
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		sb.content_margin_top = 0
		sb.content_margin_bottom = 0
		_panel.add_theme_stylebox_override("panel", sb)
		_panel.custom_minimum_size.y = 42 if on else 38
		# the selected tab covers the strip's bottom edge and joins the page
		add_theme_constant_override("margin_bottom", 0 if on else 2)
		_title.add_theme_color_override("font_color", UiStyle.INK if on else UiStyle.INK_SOFT)

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not _selected:
			pressed.emit()
			accept_event()
