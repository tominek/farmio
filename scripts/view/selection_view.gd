class_name SelectionView
extends Node3D
## Outlines on the ground around the objects whose info panels are open (the kit's selection ring):
## a white band with a blue edge, a rounded rectangle around a footprint, a circle under a worker.

const WHITE := 0.3            # m, inner band
const BLUE := 0.22            # m, outer edge
const PAD := 0.5              # m, between the footprint and the band
const LIFT := 0.06

var _marks := {}              # target -> MeshInstance3D
var _material: StandardMaterial3D


func _init() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED


## Shows marks for these targets (Building / Field / ConstructionSite, Worker, Store ground pile,
## Vector2i road block).
func show_targets(targets: Array) -> void:
	for t: Variant in _marks.keys():
		if not targets.has(t):
			(_marks[t] as Node).queue_free()
			_marks.erase(t)
	for t: Variant in targets:
		if not _marks.has(t):
			var m := MeshInstance3D.new()
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			m.material_override = _material
			add_child(m)
			_marks[t] = m
			m.set_meta("shape", "")
		_update(t, _marks[t])


func _update(t: Variant, m: MeshInstance3D) -> void:
	if t is Worker:
		var w := t as Worker
		m.position = Vector3(w.pos.x * Defs.TILE, LIFT, w.pos.y * Defs.TILE)
		if m.get_meta("shape") != "worker":
			m.set_meta("shape", "worker")
			m.mesh = _outline(Vector2(1.4, 1.4), 0.7)
		return
	var r := InfoStack.footprint(t)
	var key := str(r)
	if m.get_meta("shape") != key:
		m.set_meta("shape", key)
		var size := Vector2(r.size) * Defs.TILE + Vector2.ONE * PAD * 2.0
		m.mesh = _outline(size, minf(1.2, minf(size.x, size.y) * 0.5))
		var c := Defs.footprint_center(r.position, r.size)
		m.position = Vector3(c.x, LIFT, c.z)


## A ring around a rounded rectangle centred on the origin (a circle when the radius is half the side).
func _outline(size: Vector2, radius: float) -> ArrayMesh:
	var path := PackedVector2Array()
	var normals := PackedVector2Array()
	var half := size * 0.5 - Vector2.ONE * radius
	var steps := 10
	for corner in 4:
		var c := Vector2(half.x * (1 if corner == 0 or corner == 3 else -1), half.y * (1 if corner < 2 else -1))
		var a0 := corner * PI * 0.5
		for k in steps + 1:
			var n := Vector2.from_angle(a0 + PI * 0.5 * k / steps)
			path.append(c + n * radius)
			normals.append(n)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_band(st, path, normals, 0.0, WHITE, Color.WHITE)
	_band(st, path, normals, WHITE, WHITE + BLUE, UiStyle.SELECT)
	return st.commit()


func _band(st: SurfaceTool, path: PackedVector2Array, normals: PackedVector2Array, from: float, to: float, color: Color) -> void:
	st.set_color(color)
	for i in path.size():
		var j := (i + 1) % path.size()
		var a0 := path[i] + normals[i] * from
		var a1 := path[i] + normals[i] * to
		var b0 := path[j] + normals[j] * from
		var b1 := path[j] + normals[j] * to
		for p: Vector2 in [a0, a1, b1, a0, b1, b0]:
			st.add_vertex(Vector3(p.x, 0.0, p.y))
