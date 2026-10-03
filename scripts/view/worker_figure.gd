class_name WorkerFigure
extends Node3D
## A worker built from parts (body, arms, legs) with procedural animation and held tools.
## pose() is a pure function of the action and time, so the game and the showcase share it.

enum Action { IDLE, WALK, CARRY, PUSH, CHOP, BUILD, HOE, SOW, HARVEST, PICK_UP }

const RIG := {
	Worker.Look.MALE: "worker_male_rig", Worker.Look.FEMALE: "worker_female_rig",
	Worker.Look.MALE_VAR: "worker_male_var_rig", Worker.Look.FEMALE_VAR: "worker_female_var_rig",
}
const TOOL := { Action.CHOP: "tool_axe", Action.BUILD: "tool_hammer", Action.HOE: "tool_hoe", Action.HARVEST: "tool_sickle" }
const TWO_HANDED := [Action.CHOP, Action.HOE]
const CARRY_MODEL := { &"wood": "carry_logs", &"potato": "carry_crate", &"beet": "carry_crate" }
const BARROW_MODEL := { &"wood": "tool_wheelbarrow_logs", &"wheat": "tool_wheelbarrow_wheat", &"corn": "tool_wheelbarrow_wheat",
	&"potato": "tool_wheelbarrow_potatoes", &"beet": "tool_wheelbarrow_potatoes" }
const ARM := 0.52                # shoulder pivot to the grip
const HIPS := 0.78
# wheelbarrow model: wheel contact point and the end of the handles
const BARROW_WHEEL := Vector3(0, 0, -0.6)
const BARROW_GRIP := Vector3(0, 0.56, 0.95)

var body: Node3D                 # everything above the hips: leans and twists
var arm_l: MeshInstance3D
var arm_r: MeshInstance3D
var leg_l: MeshInstance3D
var leg_r: MeshInstance3D
var tool_hand: MeshInstance3D    # one-handed tools in the right hand
var tool_both: MeshInstance3D    # two-handed tools held between both hands
var held: MeshInstance3D         # seed sack in the left hand
var load_node: MeshInstance3D    # goods carried in front with both arms
var barrow: MeshInstance3D
var _shoulder: Vector3           # right shoulder in body space (left is mirrored)
var _tool_model := ""


func setup(look: Worker.Look) -> void:
	var p: Dictionary = Models.parts(RIG[look])
	body = Node3D.new()
	body.position.y = HIPS
	add_child(body)
	var torso := _part(p["body"], body)
	torso.position.y -= HIPS
	arm_l = _part(p["arm_l"], body)
	arm_r = _part(p["arm_r"], body)
	arm_l.position.y -= HIPS
	arm_r.position.y -= HIPS
	_shoulder = arm_r.position
	leg_l = _part(p["leg_l"], self)
	leg_r = _part(p["leg_r"], self)

	tool_hand = _tool(arm_r)
	tool_hand.position.y = -ARM
	tool_both = _tool(body)
	held = Models.instance("carry_sack")
	held.position = Vector3(-0.08, -ARM - 0.12, -0.08)
	held.scale = Vector3.ONE * 0.75
	arm_l.add_child(held)
	load_node = _tool(body)
	load_node.position = Vector3(0.0, 0.25, -0.42)
	barrow = Models.instance("tool_wheelbarrow")
	add_child(barrow)


func _part(data: Array, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = data[0]
	mi.material_override = Models.palette
	mi.position = data[1]
	parent.add_child(mi)
	return mi


func _tool(parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.material_override = Models.palette
	parent.add_child(mi)
	return mi


## Poses the figure. `moving`: the figure travels (legs walk); `carrying`: resource in its arms.
func pose(action: Action, t: float, moving: bool, carrying: StringName = &"") -> void:
	var walk := t * 9.0
	var swing := sin(walk) if moving else 0.0
	var al := 0.0                  # arm swing forward (x rotation, + = forward)
	var ar := 0.0
	var arz := 0.0                 # right arm sideways (sowing, sickle)
	var ary := 0.0                 # right arm turned sideways (sickle swing)
	var lean := 0.0                # upper body bends forward
	var twist := 0.0               # upper body turns (+ = to the left)
	var grip := 0.0                # two-handed tools: arm angle of both arms
	var tilt := 0.0                # two-handed tools: extra tilt of the tool against the arms
	var spin := 0.0                # two-handed tools: turn around the handle
	var bob := absf(sin(walk)) * 0.05 if moving else sin(t * 2.0) * 0.006
	var legs := swing * 0.55

	match action:
		Action.IDLE, Action.WALK:
			al = -swing * 0.45
			ar = swing * 0.45
		Action.CARRY:
			al = 1.15
			ar = 1.15
			legs *= 0.8
		Action.PUSH:
			al = 0.45
			ar = 0.45
			lean = 0.12
		Action.CHOP:
			# two-handed side swing at a trunk in front: wind up to the right, fast swing into the trunk
			var c := fmod(t, 1.2) / 1.2
			if c < 0.55:
				twist = lerpf(0.1, -1.1, smoothstep(0.0, 0.55, c))
			elif c < 0.66:
				twist = lerpf(-1.1, 0.15, (c - 0.55) / 0.11)
			else:
				twist = lerpf(0.15, 0.1, (c - 0.66) / 0.34)
			grip = 0.85
			tilt = 0.75                # arms down-forward, the axe level at trunk height
			spin = PI * 0.5            # blade facing the swing (to the left)
			lean = 0.1
		Action.BUILD:
			var c := fmod(t, 0.55) / 0.55
			# hammer held across the fist: raise the forearm, strike down onto the work in front
			ar = lerpf(0.35, 1.45, 0.5 + 0.5 * cos(c * TAU))
			al = 0.9
			lean = 0.3
		Action.HOE:
			# lift the hoe high in front, chop it down into the soil ahead, pull back
			var c := fmod(t, 1.0)
			var down := smoothstep(0.45, 0.58, c) * (1.0 - smoothstep(0.8, 1.0, c))
			grip = lerpf(1.6, 0.8, down)
			tilt = lerpf(0.9, 0.3, down)   # the handle leaves the fists at an angle, blade into the soil
			lean = 0.1 + 0.25 * down
		Action.SOW:
			var c := fmod(t, 0.9) / 0.9
			al = 0.5
			ar = 0.4 + 0.8 * sin(c * PI)
			arz = -0.6 * sin(c * TAU)
			lean = 0.05
		Action.HARVEST:
			var c := fmod(t, 0.8) / 0.8
			# one-handed side swing low through the stalks (like the axe, smaller): wind up to the
			# right, fast cut to the left, slow return; the torso only follows a little
			if c < 0.5:
				ary = lerpf(0.6, -0.9, smoothstep(0.0, 0.5, c))
			elif c < 0.65:
				ary = lerpf(-0.9, 0.7, (c - 0.5) / 0.15)
			else:
				ary = lerpf(0.7, 0.6, (c - 0.65) / 0.35)
			lean = 0.45
			ar = 0.55
			al = 0.35
			twist = 0.2 * ary
		Action.PICK_UP:
			var c := fmod(t, 1.0)
			lean = 0.7 * sin(clampf(c, 0.0, 1.0) * PI)
			al = 0.6 + lean
			ar = al

	body.rotation = Vector3(-lean, twist, 0.0)
	body.position.y = HIPS + bob
	leg_l.rotation.x = legs
	leg_r.rotation.x = -legs

	var want := String(TOOL.get(action, ""))
	var two := action in TWO_HANDED
	if want != _tool_model:
		_tool_model = want
		var m: Mesh = Models.mesh(want) if want != "" else null
		tool_hand.mesh = m
		tool_both.mesh = m
	tool_hand.visible = want != "" and not two
	# in the fist the handle points forward; the sickle blade lies flat to sweep sideways
	if action == Action.HARVEST:
		# wrist bent so the handle points forward, the blade lies flat with its inner (cutting) edge
		# towards the cut: the arc bulges to the right, the edge leads the swing to the left
		tool_hand.basis = Basis(Vector3.RIGHT, 0.6) * Basis(Vector3.UP, -PI * 0.5)
	else:
		tool_hand.basis = Basis(Vector3.RIGHT, PI * 0.5)
	tool_both.visible = want != "" and two
	if two:
		# both arms turn in so the hands meet on the handle in front of the chest
		var reach := ARM * maxf(sin(grip), 0.3)
		var turn := asin(clampf((_shoulder.x - 0.05) / reach, 0.0, 1.0))
		arm_r.rotation = Vector3(grip, turn, 0.0)
		arm_l.rotation = Vector3(grip, -turn, 0.0)
		tool_both.position = Vector3(0.0, _shoulder.y - ARM * cos(grip), _shoulder.z - reach * cos(turn))
		tool_both.basis = Basis(Vector3.RIGHT, grip + tilt) * Basis(Vector3.UP, spin)
	else:
		arm_l.rotation = Vector3(al, 0.0, 0.0)
		arm_r.rotation = Vector3(ar, ary, arz)

	held.visible = action == Action.SOW or String(carrying).begins_with("seed_")
	barrow.visible = action == Action.PUSH
	if barrow.visible:
		barrow.mesh = Models.mesh(BARROW_MODEL.get(carrying, "tool_wheelbarrow"))
		_place_barrow()
	load_node.visible = action == Action.CARRY and carrying != &""
	if load_node.visible:
		load_node.mesh = Models.mesh(CARRY_MODEL.get(carrying, "carry_sack"))


## Tilts the wheelbarrow up on its wheel so the handles end in the hands.
func _place_barrow() -> void:
	var hand := (body.transform * arm_r.transform) * Vector3(0, -ARM, 0)
	var arm := BARROW_GRIP - BARROW_WHEEL
	var length := Vector2(arm.z, arm.y).length()
	var rest := atan2(arm.y, arm.z)
	var angle := asin(clampf(hand.y / length, -1.0, 1.0)) - rest
	var b := Basis(Vector3.RIGHT, -angle)
	barrow.basis = b
	barrow.position = Vector3(0.0, 0.0, hand.z) - b * BARROW_GRIP + Vector3(0, hand.y, 0)


## What a simulated worker is doing, as an animation.
static func action_of(w: Worker) -> Action:
	if w.equipment == &"wheelbarrow":
		return Action.PUSH
	if w.phase == Worker.Phase.WORKING and w.task:
		match w.task.kind:
			Task.Kind.CHOP:
				return Action.CHOP
			Task.Kind.BUILD:
				return Action.BUILD
			Task.Kind.FIELD:
				return {&"cultivate": Action.HOE, &"seed": Action.SOW, &"harvest": Action.HARVEST}.get(w.task.step, Action.IDLE)
			Task.Kind.HAUL:
				return Action.PICK_UP
	if w.carrying != &"" and not String(w.carrying).begins_with("seed_"):
		return Action.CARRY
	return Action.WALK
