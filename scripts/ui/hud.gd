class_name Hud
extends CanvasLayer
## Top bar (money, wood, workers, tasks, speed) and a minimal build bar.

signal build_requested(def_id: StringName)
signal speed_requested(speed: float)

var world: World
var tool: PlacementTool
var _stats: Label
var _hint: Label
var _speed_label: Label
var _accum := 0.0


func setup(p_world: World, p_tool: PlacementTool) -> void:
	world = p_world
	tool = p_tool

	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	add_child(top)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 16)
	top.add_child(bar)
	_stats = Label.new()
	_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_stats)
	_speed_label = Label.new()
	bar.add_child(_speed_label)
	for s in [[0.0, "||"], [1.0, "1x"], [2.0, "2x"], [3.0, "3x"]]:
		var b := Button.new()
		b.text = s[1]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: speed_requested.emit(s[0]))
		bar.add_child(b)

	var bottom := VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.position += Vector2(12, -12)
	add_child(bottom)
	_hint = Label.new()
	bottom.add_child(_hint)
	var builds := HBoxContainer.new()
	bottom.add_child(builds)
	for id: StringName in Defs.BUILDINGS:
		var d: Dictionary = Defs.BUILDINGS[id]
		if not d["buildable"]:
			continue
		var b := Button.new()
		b.text = "%s  $%d" % [d["name"], d["cost"]] if d["cost"] > 0 else d["name"]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: build_requested.emit(id))
		builds.add_child(b)
	tool.changed.connect(_refresh)
	world.stock_changed.connect(_refresh)
	_refresh()


func set_speed_text(text: String) -> void:
	_speed_label.text = text


func _process(delta: float) -> void:
	_accum += delta
	if _accum > 0.25:
		_accum = 0.0
		_refresh()


func _refresh() -> void:
	_stats.text = "$ %d    Wood %d    Workers %d idle / %d    Tasks %d waiting / %d" % [
		world.money, world.stock[&"wood"], world.idle_workers(), world.workers.size(),
		world.tasks.pending_count(), world.tasks.tasks.size()]
	_hint.text = tool.hint()
