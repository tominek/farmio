class_name DealerPanel
extends PanelContainer
## Dealer: auto-sell rules per resource, seed orders and the pickup's current trip.

var world: World
var _status: Label
var _money: Label
var _stock_labels := {}     # resource -> Label
var _order_labels := {}     # seed resource -> Label
var _accum := 0.0


func setup(p_world: World) -> void:
	world = p_world
	custom_minimum_size = Vector2(680, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "Dealer"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "✕"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(hide)
	head.add_child(close)

	_status = Label.new()
	box.add_child(_status)
	_money = Label.new()
	box.add_child(_money)

	box.add_child(_section("Sell — the pickup takes everything above the amount kept in the barn"))
	var sell := GridContainer.new()
	sell.columns = 5
	sell.add_theme_constant_override("h_separation", 18)
	box.add_child(sell)
	for h in ["Goods", "In barn", "Price", "Auto-sell", "Keep in barn"]:
		sell.add_child(_header(h))
	for res: StringName in Defs.SELL_PRICE:
		sell.add_child(_cell(Defs.resource_name(res)))
		_stock_labels[res] = _cell("")
		sell.add_child(_stock_labels[res])
		sell.add_child(_cell(Defs.format_price(res, Defs.SELL_PRICE[res])))
		var on := CheckBox.new()
		on.button_pressed = world.auto_sell[res]["on"]
		on.focus_mode = Control.FOCUS_NONE
		on.toggled.connect(func(v: bool) -> void: world.auto_sell[res]["on"] = v)
		sell.add_child(on)
		var keep := SpinBox.new()
		keep.max_value = 100000
		keep.step = 5 if res == &"wood" else 100
		keep.suffix = "logs" if res == &"wood" else "kg"
		keep.value = world.auto_sell[res]["keep"]
		keep.value_changed.connect(func(v: float) -> void: world.auto_sell[res]["keep"] = v)
		sell.add_child(keep)
	var send := Button.new()
	send.text = "Send the pickup now"
	send.focus_mode = Control.FOCUS_NONE
	send.pressed.connect(world.request_trip)
	box.add_child(send)

	box.add_child(_section("Buy seeds — collected by the pickup on its next trip, stored in the barn"))
	var buy := GridContainer.new()
	buy.columns = 5
	buy.add_theme_constant_override("h_separation", 18)
	box.add_child(buy)
	for h in ["Seeds", "In barn", "Price", "Ordered", ""]:
		buy.add_child(_header(h))
	for crop: StringName in Defs.CROPS:
		var res := Defs.seed_of(crop)
		buy.add_child(_cell(Defs.resource_name(res)))
		_stock_labels[res] = _cell("")
		buy.add_child(_stock_labels[res])
		buy.add_child(_cell(Defs.format_price(res, Defs.SEED_PRICE[crop])))
		_order_labels[res] = _cell("")
		buy.add_child(_order_labels[res])
		var row := HBoxContainer.new()
		# order in kg; the step is roughly the seed for 10 tiles, default enough for 100 tiles
		var per_tile := Defs.seed_per_tile(crop)
		var step := pow(10.0, floorf(log(per_tile * 10.0) / log(10.0)))
		var qty := SpinBox.new()
		qty.step = step
		qty.min_value = step
		qty.max_value = step * 10000
		qty.value = snappedf(per_tile * 100.0, step)
		qty.suffix = "kg"
		qty.custom_minimum_size.x = 120
		row.add_child(qty)
		var tiles := _cell("")
		tiles.custom_minimum_size.x = 110
		var show_tiles := func(v: float) -> void: tiles.text = "≈ %d tiles" % floori(v / per_tile)
		show_tiles.call(qty.value)
		qty.value_changed.connect(show_tiles)
		row.add_child(tiles)
		var order := Button.new()
		order.text = "Order"
		order.focus_mode = Control.FOCUS_NONE
		order.pressed.connect(func() -> void: world.order(res, qty.value))
		row.add_child(order)
		buy.add_child(row)
	refresh()


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	l.modulate = Color(1, 0.92, 0.7)
	return l


func _header(text: String) -> Label:
	var l := _cell(text)
	l.modulate = Color(1, 1, 1, 0.6)
	return l


func _cell(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _process(delta: float) -> void:
	if not visible:
		return
	_accum += delta
	if _accum > 0.25:
		_accum = 0.0
		refresh()


func refresh() -> void:
	var v: Vehicle = world.vehicles[0] if not world.vehicles.is_empty() else null
	var load := ""
	if v and v.cargo_total() > 0.0:
		var parts := PackedStringArray()
		for res in v.cargo:
			parts.append("%s %s" % [Defs.format_amount(res, v.cargo[res]), Defs.resource_name(res).to_lower()])
		load = " · carrying " + ", ".join(parts)
	_status.text = "Pickup: %s%s" % [world.trip_status, load]
	_money.text = "Money: $%d" % world.money
	for res in _stock_labels:
		(_stock_labels[res] as Label).text = Defs.format_amount(res, world.stock.get(res, 0.0))
	for res in _order_labels:
		var n: float = world.orders.get(res, 0.0)
		(_order_labels[res] as Label).text = Defs.format_kg(n) if n > 0.0 else "–"
