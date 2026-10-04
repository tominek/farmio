class_name AnimalFigure
extends Node3D
## A farm animal built from parts (body, head, legs, tail; animal_*.glb) with procedural animation:
## idle, walk, eat (grazing / pecking) and sleep (lying down). Quadrupeds have four legs
## (leg_fl, leg_fr, leg_bl, leg_br), birds two (leg_l, leg_r).

enum Action { IDLE, WALK, EAT, SLEEP }

const LIE_SPEED := 1.6           # lying down / standing up per second (0..1)

var body: Node3D                 # everything carried by the legs: lowers when lying
var head: MeshInstance3D
var tail: MeshInstance3D
var legs: Array[MeshInstance3D] = []
var bird := false
var _leg_rest: Array[Vector3] = []
var _drop := 0.0                 # how far the body goes down when lying
var _eat_angle := 1.0            # head pitch that brings the mouth to the ground
var _lie := 0.0                  # 0 standing .. 1 lying


func setup(model: String) -> void:
	var p: Dictionary = Models.parts(model)
	body = Node3D.new()
	add_child(body)
	_part(p["body"], body)
	head = _part(p["head"], body)
	if p.has("tail"):
		tail = _part(p["tail"], body)
	bird = p.has("leg_l")
	for k in (["leg_l", "leg_r"] if bird else ["leg_fl", "leg_fr", "leg_bl", "leg_br"]):
		var leg := _part(p[k], self)
		legs.append(leg)
		_leg_rest.append(leg.position)
	var leg_box: AABB = legs[0].mesh.get_aabb()
	var pivot_y := legs[0].position.y
	# lying: the belly comes down onto the folded legs (birds sit on the ground)
	_drop = pivot_y - 0.03 if bird else pivot_y - 0.12 - leg_box.size.x * 1.1
	_eat_angle = _find_eat_angle()


func _part(data: Array, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = data[0]
	mi.material_override = Models.palette
	mi.position = data[1]
	parent.add_child(mi)
	return mi


## Smallest downward head pitch at which the head reaches the ground.
func _find_eat_angle() -> float:
	var box: AABB = head.mesh.get_aabb()
	for i in 40:
		var a := i * 0.04
		var b := Basis(Vector3.RIGHT, -a)
		var low := INF
		for c in 8:
			low = minf(low, (head.position + b * box.get_endpoint(c)).y)
		if low <= 0.04:
			return a
	return 1.5


## `t`: time in seconds; `delta` > 0 blends lying down / standing up (0 snaps).
func pose(action: Action, t: float, delta := 0.0) -> void:
	var want_lie := 1.0 if action == Action.SLEEP else 0.0
	_lie = move_toward(_lie, want_lie, delta * LIE_SPEED) if delta > 0.0 else want_lie
	var lie := smoothstep(0.0, 1.0, _lie)

	var step := t * (9.0 if bird else 5.5)
	var head_pitch := 0.0
	var head_yaw := 0.0
	var bob := 0.0
	var swing := 0.0
	match action:
		Action.WALK:
			swing = sin(step)
			bob = absf(sin(step)) * (0.015 if bird else 0.03)
			head_pitch = sin(step * 2.0) * (0.25 if bird else 0.05)
		Action.IDLE:
			# looks around now and then, breathes
			head_yaw = sin(t * 0.7) * 0.45 * smoothstep(0.2, 0.8, absf(sin(t * 0.23)))
			head_pitch = sin(t * 0.5) * 0.08
			bob = sin(t * 1.8) * 0.006
		Action.EAT:
			if bird:
				# pecking: quick jabs at the ground, short pauses with the head up
				var c := fmod(t, 0.9) / 0.9
				head_pitch = -_eat_angle * (smoothstep(0.0, 0.15, c) - smoothstep(0.25, 0.4, c))
				if c > 0.4:
					head_pitch = -_eat_angle * 0.25 * sin((c - 0.4) / 0.6 * PI)
			else:
				# grazing: head down, small chewing nods and slow side steps of the muzzle
				head_pitch = -_eat_angle + sin(t * 4.0) * 0.04
				head_yaw = sin(t * 0.6) * 0.25
		Action.SLEEP:
			bob = sin(t * 1.3) * 0.008
			head_pitch = -0.25
			head_yaw = 0.55 if not bird else 0.0
	var amp := 0.6 if bird else 0.45
	body.position.y = -_drop * lie + bob * (1.0 - lie)
	body.rotation.x = 0.0
	head.rotation = Vector3(head_pitch, head_yaw, 0.0)
	if tail:
		# swishing, faster when idle or eating (flies)
		var s := 0.35 if action != Action.SLEEP else 0.08
		tail.rotation = Vector3(0.15 + sin(t * 1.1) * 0.05, 0.0, sin(t * (2.6 if action != Action.WALK else 5.5)) * s)
	for i in legs.size():
		var leg := legs[i]
		var phase := swing
		if bird:
			phase = swing if i == 0 else -swing
		else:
			phase = swing if i == 0 or i == 3 else -swing   # diagonal pairs move together
		# lying: front legs fold back under the chest, hind legs forward under the belly
		var fold := 0.0 if bird else (-1.45 if i < 2 else 1.45)
		leg.rotation.x = lerpf(phase * amp, fold, lie)
		leg.position = _leg_rest[i] - Vector3(0, _drop * lie, 0)
		leg.visible = not (bird and lie > 0.6)
