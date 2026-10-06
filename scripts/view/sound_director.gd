class_name SoundDirector
extends Node3D
## The farm's sound: work strokes and engines of the agents nearest the camera, one-shot events
## (a tree falls, a building is done, goods put down or taken) and ambience layers whose volumes
## follow what is on screen. One node for the whole game; no audio player per worker or vehicle.
##
## Cost: the activity scan goes over workers and vehicles SCAN_EVERY (O(agents)), the ambience
## samples a fixed GRID x GRID of tiles AMBIENCE_EVERY; per frame only the queued strokes, the held
## engine voices and the layer glides (all bounded by VOICES and the layer count).

const VOICES := 20                  # positional players; the agents nearest the camera win
const SCAN_EVERY := 0.25            # s (real time)
const AMBIENCE_EVERY := 0.5
const GRID := 16                    # ambience samples per side of the view
const NEAR_ZOOM := 60.0             # camera size up to which activity sounds play fully
const FAR_ZOOM := 140.0             # from here on only the ambience is heard
const THIN_RATE := 1.5              # strokes never come faster than this times their 1x pace (3x: thinned)
const SILENT_SPEED := 50.0          # from this game speed on only the ambience plays
const EVENT_GAP := 0.08             # s between two one-shots of the same sound
const SELL_GAP := 1.5               # s between two "sold" coin sounds
const GLIDE := 0.6                  # ambience volume change per second (linear 0..1)
const MUFFLE_HZ := 700.0            # low-pass on the ambience while paused

## work stroke per task kind: [sound, seconds between strokes at 1x]; field rows by their step
const STROKES := {
	Task.Kind.CHOP: [&"axe", 1.1],
	Task.Kind.BUILD: [&"hammer", 0.7],
	Task.Kind.PROCESS: [&"mill", 2.0],
}
const FIELD_STROKES := {
	&"cultivate": [&"hoe", 0.9],
	&"seed": [&"sow", 1.2],
	&"harvest": [&"harvest", 1.0],
}
const SAW_SHARE := 0.25             # building: this share of the strokes is the saw

var world: World
var rig: CameraRig
var game: Node                      # reads `speed` and `paused`
var layer_mult := {}                # layer -> volume multiplier (dev sound board, not saved)
var level := {}                     # layer -> current linear volume (glides to _target)

var _voices: Array[AudioStreamPlayer3D] = []
var _held := {}                     # vehicle id -> [voice, sound]: engine loops
var _listener: AudioListener3D
var _layers := {}                   # layer -> AudioStreamPlayer (only those with a file)
var _target := {}                   # layer -> linear volume
var _clock := 0.0                   # real seconds
var _scan_at := 0.0
var _ambience_at := 0.0
var _next := {}                     # worker id -> clock time of its next stroke
var _queue: Array = []              # [time, sound, position, db] strokes due before the next scan
var _last_event := {}               # sound -> clock time it last played
var _last_pos := {}                 # vehicle id -> pos at the last scan
var _working := 0                   # working workers in view (last scan)
var _moving := 0                    # moving vehicles in view
var _muffle: AudioEffectLowPassFilter
var _muffle_bus := -1
var _muffle_i := -1
var _muffled := false


func setup(p_world: World, p_rig: CameraRig, p_game: Node) -> void:
	world = p_world
	rig = p_rig
	game = p_game
	process_mode = Node.PROCESS_MODE_ALWAYS     # the ambience goes on (muffled) in the game menu
	_listener = AudioListener3D.new()
	add_child(_listener)
	_listener.make_current()
	for i in VOICES:
		var v := AudioStreamPlayer3D.new()
		v.bus = &"Effects"
		v.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED   # distance gain is ours (_gain)
		v.panning_strength = 0.6
		v.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(v)
		_voices.append(v)
	for name: StringName in SoundBank.LAYERS:
		layer_mult[name] = 1.0
		level[name] = 0.0
		_target[name] = 0.0
		var s := SoundBank.layer(name)
		if s == null:
			continue
		var p := AudioStreamPlayer.new()
		p.bus = &"Ambience"
		p.stream = s
		p.volume_db = -80.0
		add_child(p)
		p.play(randf() * maxf(s.get_length() - 0.1, 0.0))
		_layers[name] = p
	_muffle_bus = AudioServer.get_bus_index(&"Ambience")
	if _muffle_bus >= 0:
		_muffle = AudioEffectLowPassFilter.new()
		_muffle.cutoff_hz = MUFFLE_HZ
		_muffle_i = AudioServer.get_bus_effect_count(_muffle_bus)
		AudioServer.add_bus_effect(_muffle_bus, _muffle, _muffle_i)
		AudioServer.set_bus_effect_enabled(_muffle_bus, _muffle_i, false)
	world.tree_changed.connect(_on_tree_changed)
	world.building_added.connect(_on_building_added)
	world.goods_put.connect(_on_goods_put)
	world.goods_taken.connect(func(c: Vector2i) -> void: _event(&"goods_up", Defs.cell_center(c)))


func _exit_tree() -> void:
	if _muffle_bus >= 0 and _muffle_i < AudioServer.get_bus_effect_count(_muffle_bus) \
			and AudioServer.get_bus_effect(_muffle_bus, _muffle_i) == _muffle:
		AudioServer.remove_bus_effect(_muffle_bus, _muffle_i)


## Whether a layer has its loop file (the dev sound board greys the others out).
func has_layer(name: StringName) -> bool:
	return _layers.has(name)


func _paused() -> bool:
	return game.get("paused") == true or get_tree().paused


func _speed() -> float:
	var s: Variant = game.get("speed")
	return s if s is float else 1.0


## 1 close up, fading to 0 between NEAR_ZOOM and FAR_ZOOM; 0 while paused or at SILENT_SPEED.
func _activity() -> float:
	if _paused() or _speed() >= SILENT_SPEED:
		return 0.0
	return 1.0 - smoothstep(NEAR_ZOOM, FAR_ZOOM, rig.camera.size)


## Horizontal radius (m) around the view centre in which agents are heard.
func _radius() -> float:
	return rig.camera.size * 0.8


## Linear gain of a sound `d2` (squared m) from the view centre.
func _gain(d2: float) -> float:
	var near := rig.camera.size * 0.5
	return 1.0 / (1.0 + d2 / (near * near))


func _process(delta: float) -> void:
	_clock += delta
	_listener.global_transform = Transform3D(rig.global_basis, rig.global_position + Vector3(0, rig.camera.size * 0.25, 0))
	if _clock >= _scan_at:
		_scan_at = _clock + SCAN_EVERY
		_scan()
	if _clock >= _ambience_at:
		_ambience_at = _clock + AMBIENCE_EVERY
		_ambience()
	# strokes due now
	var i := 0
	while i < _queue.size():
		var q: Array = _queue[i]
		if q[0] <= _clock:
			_play(q[1], q[2], q[3])
			_queue.remove_at(i)
		else:
			i += 1
	# engines follow their vehicles
	for id: int in _held:
		var v := _vehicle(id)
		if v:
			(_held[id][0] as AudioStreamPlayer3D).position = _at(v.pos)
	# ambience glides
	var paused := _paused()
	if paused != _muffled and _muffle_bus >= 0 and _muffle_i < AudioServer.get_bus_effect_count(_muffle_bus):
		_muffled = paused
		AudioServer.set_bus_effect_enabled(_muffle_bus, _muffle_i, paused)
	for name: StringName in level:
		var t: float = _target[name] * layer_mult[name] * (0.6 if paused else 1.0)
		level[name] = move_toward(level[name], t, GLIDE * delta)
		if _layers.has(name):
			(_layers[name] as AudioStreamPlayer).volume_db = linear_to_db(maxf(level[name], 0.0001))


func _at(p: Vector2) -> Vector3:
	return Vector3(p.x * Defs.TILE, 0.5, p.y * Defs.TILE)


func _vehicle(id: int) -> Vehicle:
	for v in world.vehicles:
		if v.id == id:
			return v
	return null


## Activity scan: who works near the camera, which strokes come before the next scan, which
## engines are held. Also counts the working agents and moving vehicles in view for the ambience.
func _scan() -> void:
	var center := Vector2(rig.position.x, rig.position.z)
	var r := _radius()
	var r2 := r * r
	var activity := _activity()
	var rate := minf(_speed(), THIN_RATE)
	var found: Array = []           # [d2, key, position, sound, interval] / [d2, -1 - vehicle id, position, engine sound, 0]
	_working = 0
	_moving = 0
	for w in world.workers:
		if w.phase != Worker.Phase.WORKING or w.task == null or w.in_vehicle:
			continue
		var d2 := (w.pos * Defs.TILE).distance_squared_to(center)
		if d2 > r2:
			continue
		_working += 1
		var s := _stroke(w.task)
		if not s.is_empty() and SoundBank.has(s[0]):
			found.append([d2, w.id, _at(w.pos), s[0], s[1]])
	for v in world.vehicles:
		var moved: bool = _last_pos.get(v.id, v.pos) != v.pos
		_last_pos[v.id] = v.pos
		if v.parked:
			continue
		var d2 := (v.pos * Defs.TILE).distance_squared_to(center)
		if d2 > r2:
			continue
		if moved:
			_moving += 1
		var engine := &"engine_drive" if moved else (&"engine_load" if v.status.contains("oading") else &"engine_idle")
		if SoundBank.has(engine):
			found.append([d2, -1 - v.id, _at(v.pos), engine, 0.0])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	if activity <= 0.0:
		found.clear()
		_queue.clear()
	found.resize(mini(found.size(), VOICES))

	var heard := {}
	var engines := {}
	for f: Array in found:
		var key: int = f[1]
		var db := linear_to_db(activity * _gain(f[0]))
		if key < 0:
			engines[-1 - key] = [f[3], db]
			continue
		heard[key] = true
		var interval: float = f[4] / rate
		var at: float = _next.get(key, _clock + randf() * interval)    # a newcomer starts out of step
		while at < _clock + SCAN_EVERY:
			var sound: StringName = f[3]
			if sound == &"hammer" and randf() < SAW_SHARE and SoundBank.has(&"saw"):
				sound = &"saw"
			_queue.append([maxf(at, _clock), sound, f[2], db])
			at += interval * randf_range(0.85, 1.15)
		_next[key] = at
	for key: int in _next.keys():
		if not heard.has(key):
			_next.erase(key)
	_hold_engines(engines)


## Starts, switches and stops the engine loops of the vehicles heard (id -> [sound, db]).
func _hold_engines(engines: Dictionary) -> void:
	for id: int in _held.keys():
		var h: Array = _held[id]
		if not engines.has(id) or engines[id][0] != h[1]:
			(h[0] as AudioStreamPlayer3D).stop()
			_held.erase(id)
	for id: int in engines:
		var sound: StringName = engines[id][0]
		if not _held.has(id):
			var voice := _free_voice()
			if voice == null:
				continue
			voice.stream = SoundBank.pick(sound)
			voice.pitch_scale = SoundBank.pitch(sound) * randf_range(0.96, 1.04)
			voice.play(randf() * maxf(voice.stream.get_length() - 0.1, 0.0))
			_held[id] = [voice, sound]
		(_held[id][0] as AudioStreamPlayer3D).volume_db = engines[id][1] + SoundBank.db(sound)


## The work stroke of a task: [sound, interval], empty for work without one.
func _stroke(t: Task) -> Array:
	if t.kind == Task.Kind.FIELD:
		return FIELD_STROKES.get(t.step, [])
	return STROKES.get(t.kind, [])


## A voice not playing and not held by an engine; else the one-shot that has played longest.
func _free_voice() -> AudioStreamPlayer3D:
	var held := {}
	for id: int in _held:
		held[_held[id][0]] = true
	var oldest: AudioStreamPlayer3D = null
	for v in _voices:
		if held.has(v):
			continue
		if not v.playing:
			return v
		if oldest == null or v.get_playback_position() > oldest.get_playback_position():
			oldest = v
	return oldest


## One stroke or event with a little variation in pitch and volume.
func _play(sound: StringName, pos: Vector3, db: float) -> void:
	var s := SoundBank.pick(sound)
	var voice := _free_voice() if s else null
	if voice == null:
		return
	voice.stream = s
	voice.position = pos
	voice.pitch_scale = SoundBank.pitch(sound) * randf_range(0.92, 1.08)
	voice.volume_db = db + SoundBank.db(sound) + randf_range(-2.0, 1.0)
	voice.play()


## A one-shot event at `pos`, when it is in view (rate-limited per sound).
func _event(sound: StringName, pos: Vector3) -> void:
	var activity := _activity()
	if activity <= 0.0 or _clock - _last_event.get(sound, -INF) < EVENT_GAP:
		return
	var d2 := Vector2(pos.x, pos.z).distance_squared_to(Vector2(rig.position.x, rig.position.z))
	if d2 > _radius() * _radius():
		return
	_last_event[sound] = _clock
	_play(sound, pos, linear_to_db(activity * _gain(d2)))


func _on_tree_changed(c: Vector2i) -> void:
	if world.in_bounds(c) and world.tree_kind[world.idx(c)] == Defs.TreeKind.NONE:
		_event(&"tree_fall", Defs.cell_center(c))


func _on_building_added(b: Building) -> void:
	if not (b is ConstructionSite):
		_event(&"build_done", Defs.footprint_center(b.anchor, b.size))


func _on_goods_put(c: Vector2i, sold: bool) -> void:
	if sold:
		if _clock - _last_event.get(&"sell", -INF) >= SELL_GAP and not _paused():
			_last_event[&"sell"] = _clock
			UiStyle.sound(&"sell")
		return
	_event(&"goods_down", Defs.cell_center(c))


## Ambience targets from the view: terrain from GRID x GRID tiles under the screen, work and
## engines from the last scan's counts.
func _ambience() -> void:
	var vp := get_viewport().get_visible_rect().size
	var corners: Array[Vector3] = []
	for p: Vector2 in [Vector2.ZERO, Vector2(vp.x, 0), Vector2(0, vp.y), vp]:
		var g: Variant = rig.ground_point(p)
		corners.append(g if g != null else rig.position)
	var open := 0
	var forest := 0
	var water := 0
	var size := world.size
	for j in GRID:
		var fy := (j + 0.5) / GRID
		var left := corners[0].lerp(corners[2], fy) / Defs.TILE
		var step := (corners[1].lerp(corners[3], fy) / Defs.TILE - left) / GRID
		var p := left + step * 0.5
		for i in GRID:
			var x := floori(p.x)
			var y := floori(p.z)
			p += step
			if x < 0 or y < 0 or x >= size or y >= size:
				continue
			var k := y * size + x
			if world.water[k] != Defs.Water.NONE:
				water += 1
			elif world.tree_kind[k] != Defs.TreeKind.NONE:
				forest += 1
			else:
				open += 1
	var n := float(GRID * GRID)
	_target[&"nature"] = 0.35 + 0.45 * open / n
	_target[&"forest"] = 0.9 * pow(forest / n, 0.7)
	_target[&"water"] = minf(1.0, water * 4.0 / n)
	_target[&"bustle"] = 0.8 * (1.0 - exp(-_working / 6.0))
	_target[&"engines"] = 0.7 * (1.0 - exp(-_moving / 2.0))
