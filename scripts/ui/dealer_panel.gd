class_name DealerPanel
extends PanelContainer
## Dealer: auto-sell rules per resource, seed and material orders and the pickup's current trip.

var world: World
var _status: Label
var _money: Label
var _stock_labels := {}     # resource -> Label
var _order_labels := {}     # seed resource -> Label
var _hire_info: Label
var _hire_count: SpinBox
var _hire_cost: Label
var _hire_cancel: Button
var _hire_btn: Button
var _seed_rows: Array[Dictionary] = []
var _barrow_qty: SpinBox
var _barrow_cost: Label
var _barrow_order: Button
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

	box.add_child(_section("Buy seeds — paid now, collected by the pickup on its next trip, stored in the barn"))
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
		tiles.custom_minimum_size.x = 190
		row.add_child(tiles)
		var max_btn := _button("Max", func() -> void:
			var price: float = Defs.SEED_PRICE[crop]
			qty.value = maxf(step, floorf(world.money / price / step) * step))
		row.add_child(max_btn)
		var order := _button("Order", func() -> void: world.order(res, qty.value); refresh())
		row.add_child(order)
		_seed_rows.append({"res": res, "qty": qty, "tiles": tiles, "order": order, "per_tile": per_tile, "unit": "tiles"})
		qty.value_changed.connect(func(_v: float) -> void: refresh())
		buy.add_child(row)

	box.add_child(_section("Buy road materials — paid now, collected by the pickup, carried to road sites from the barn"))
	var mats := GridContainer.new()
	mats.columns = 5
	mats.add_theme_constant_override("h_separation", 18)
	box.add_child(mats)
	for h in ["Material", "In barn", "Price", "Ordered", ""]:
		mats.add_child(_header(h))
	for res: StringName in Defs.MATERIAL_PRICE:
		mats.add_child(_cell(Defs.resource_name(res)))
		_stock_labels[res] = _cell("")
		mats.add_child(_stock_labels[res])
		mats.add_child(_cell(Defs.format_price(res, Defs.MATERIAL_PRICE[res])))
		_order_labels[res] = _cell("")
		mats.add_child(_order_labels[res])
		var row := HBoxContainer.new()
		# order in hand loads, default enough for one road block
		var step := Defs.CARRY_CAPACITY
		var qty := SpinBox.new()
		qty.step = step
		qty.min_value = step
		qty.max_value = step * 1000
		qty.value = Defs.GRAVEL_PER_BLOCK
		qty.suffix = "kg"
		qty.custom_minimum_size.x = 120
		row.add_child(qty)
		var blocks := _cell("")
		blocks.custom_minimum_size.x = 190
		row.add_child(blocks)
		var price: float = Defs.MATERIAL_PRICE[res]
		row.add_child(_button("Max", func() -> void:
			qty.value = maxf(step, floorf(world.money / price / step) * step)))
		var order := _button("Order", func() -> void: world.order(res, qty.value); refresh())
		row.add_child(order)
		_seed_rows.append({"res": res, "qty": qty, "tiles": blocks, "order": order, "per_tile": Defs.GRAVEL_PER_BLOCK, "unit": "road blocks"})
		qty.value_changed.connect(func(_v: float) -> void: refresh())
		mats.add_child(row)

	box.add_child(_section("Equipment — paid now, collected by the pickup, kept in the barn"))
	var eq := HBoxContainer.new()
	eq.add_theme_constant_override("separation", 12)
	box.add_child(eq)
	var barrow := _cell("Wheelbarrow · carries %d kg instead of %d kg by hand · $%d" % [Defs.WHEELBARROW_CAPACITY, Defs.CARRY_CAPACITY, Defs.WHEELBARROW_PRICE])
	barrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eq.add_child(barrow)
	_stock_labels[&"wheelbarrow"] = _cell("")
	eq.add_child(_stock_labels[&"wheelbarrow"])
	_order_labels[&"wheelbarrow"] = _cell("")
	eq.add_child(_order_labels[&"wheelbarrow"])
	_barrow_qty = SpinBox.new()
	_barrow_qty.min_value = 1
	_barrow_qty.max_value = 20
	_barrow_qty.custom_minimum_size.x = 90
	_barrow_qty.value_changed.connect(func(_v: float) -> void: refresh())
	eq.add_child(_barrow_qty)
	_barrow_cost = _cell("")
	eq.add_child(_barrow_cost)
	eq.add_child(_button("Max", func() -> void:
		_barrow_qty.value = maxf(1.0, floorf(world.money / float(Defs.WHEELBARROW_PRICE)))))
	_barrow_order = _button("Order", func() -> void:
		world.order(&"wheelbarrow", _barrow_qty.value)
		refresh())
	eq.add_child(_barrow_order)

	box.add_child(_section("Hire workers — paid now, the pickup brings %d per trip (free seats)" % (Defs.PICKUP_SEATS - 1)))
	_hire_info = _cell("")
	box.add_child(_hire_info)
	var hire_row := HBoxContainer.new()
	hire_row.add_theme_constant_override("separation", 12)
	box.add_child(hire_row)
	_hire_count = SpinBox.new()
	_hire_count.min_value = 1
	_hire_count.max_value = 20
	_hire_count.custom_minimum_size.x = 90
	_hire_count.value_changed.connect(func(_v: float) -> void: refresh())
	hire_row.add_child(_hire_count)
	_hire_cost = _cell("")
	_hire_cost.custom_minimum_size.x = 110
	hire_row.add_child(_hire_cost)
	hire_row.add_child(_button("Max", func() -> void:
		var n := 1
		while n < _hire_count.max_value and world.hire_cost(n + 1) <= world.money:
			n += 1
		_hire_count.value = n))
	_hire_btn = _button("Hire", func() -> void: world.hire(int(_hire_count.value)); refresh())
	hire_row.add_child(_hire_btn)
	_hire_cancel = Button.new()
	_hire_cancel.text = "Cancel waiting hires"
	_hire_cancel.focus_mode = Control.FOCUS_NONE
	_hire_cancel.pressed.connect(func() -> void: world.cancel_hires(); refresh())
	hire_row.add_child(_hire_cancel)
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


func _button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_pressed)
	return b


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
	var waiting := ""
	if world.hires_wanted > 0:
		waiting = " · %d waiting at the Dealer" % world.hires_wanted
	var riding := 0
	if v:
		riding = v.passengers.size()
	if riding > 0:
		waiting += " · %d riding to the farm" % riding
	_hire_info.text = "Workers: %d%s · next hire $%d" % [world.workers.size(), waiting, world.hire_cost(1)]
	_hire_cost.text = "$%d total" % world.hire_cost(int(_hire_count.value))
	_hire_cancel.visible = world.hires_wanted > 0
	_hire_btn.disabled = world.hire_cost(int(_hire_count.value)) > world.money
	for r in _seed_rows:
		var qty: SpinBox = r["qty"]
		var cost := world.order_cost(r["res"], qty.value)
		var n := floori(qty.value / r["per_tile"] + 0.0001)
		var unit: String = r["unit"]
		(r["tiles"] as Label).text = "≈ %d %s · $%d" % [n, unit.trim_suffix("s") if n == 1 else unit, cost]
		(r["order"] as Button).disabled = cost > world.money
	(_stock_labels[&"wheelbarrow"] as Label).text = "in barn %d" % world.stock.get(&"wheelbarrow", 0.0)
	var barrows: float = world.orders.get(&"wheelbarrow", 0.0)
	(_order_labels[&"wheelbarrow"] as Label).text = "ordered %d" % barrows if barrows > 0.0 else ""
	var barrow_cost := world.order_cost(&"wheelbarrow", _barrow_qty.value)
	_barrow_cost.text = "$%d" % barrow_cost
	_barrow_order.disabled = barrow_cost > world.money
