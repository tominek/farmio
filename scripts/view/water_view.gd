class_name WaterView
extends Node3D
## River and ponds: a sunken bed (height field built from the same smoothed water mask that cuts the
## grass in the ground shader, so the shoreline matches) in chunks that contain water, and a water
## surface patch per such chunk below ground level that only shows where the bed is lower; the
## water shader moves it in gentle swells.

const CHUNK := 16                 # tiles per bed chunk
const STEP := 3                   # bed vertices per tile (1 m apart)
const WATER_CUT := 0.42           # = ground.gdshader: grass is cut away above this mask value
const DEPTH := 1.3                # bed depth below ground in the middle of the river
const SURFACE := -0.45            # water level

var world: World
var _mask: PackedByteArray        # GroundView.water_image() as bytes
var _res := 0                     # mask width in texels


func setup(p_world: World) -> void:
	world = p_world
	var img := GroundView.water_image(world)
	_mask = img.get_data()
	_res = img.get_width()
	var bed_mat := ShaderMaterial.new()
	bed_mat.shader = load("res://assets/shaders/water_bed.gdshader")
	var water_mat := ShaderMaterial.new()
	water_mat.shader = load("res://assets/shaders/water.gdshader")
	# one surface patch per wet chunk, finely divided so the shader can move it in gentle swells
	var patch := PlaneMesh.new()
	patch.size = Vector2(CHUNK * Defs.TILE, CHUNK * Defs.TILE)
	patch.subdivide_width = CHUNK * 2 - 1
	patch.subdivide_depth = CHUNK * 2 - 1
	var n := ceili(float(world.size) / CHUNK)
	for cy in n:
		for cx in n:
			var mesh := _chunk_mesh(Vector2i(cx, cy))
			if mesh:
				var mi := MeshInstance3D.new()
				mi.mesh = mesh
				mi.material_override = bed_mat
				add_child(mi)
				var water := MeshInstance3D.new()
				water.mesh = patch
				water.position = Vector3((cx + 0.5) * CHUNK * Defs.TILE, SURFACE, (cy + 0.5) * CHUNK * Defs.TILE)
				water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				water.material_override = water_mat
				add_child(water)


## Water mask at a point in meters, sampled like the linear-filtered texture in the ground shader
## (bilinear between texel centres, clamped at the map edge).
func field(x: float, z: float) -> float:
	var k := float(_res) / world.size / Defs.TILE
	var s := x * k - 0.5
	var t := z * k - 0.5
	var i := floori(s)
	var j := floori(t)
	var fs := s - i
	var ft := t - j
	return lerpf(lerpf(_at(i, j), _at(i + 1, j), fs), lerpf(_at(i, j + 1), _at(i + 1, j + 1), fs), ft)


func _at(x: int, y: int) -> float:
	x = clampi(x, 0, _res - 1)
	y = clampi(y, 0, _res - 1)
	return _mask[y * _res + x] / 255.0


func height(x: float, z: float) -> float:
	return -0.03 - DEPTH * smoothstep(WATER_CUT, 0.6, field(x, z))


func _chunk_mesh(ch: Vector2i) -> ArrayMesh:
	var t0 := ch * CHUNK
	var wet := false
	for y in range(t0.y - 1, t0.y + CHUNK + 1):
		for x in range(t0.x - 1, t0.x + CHUNK + 1):
			if world.is_water(Vector2i(x, y)):
				wet = true
	if not wet:
		return null
	var n := CHUNK * STEP
	var d := Defs.TILE / STEP
	var h := PackedFloat32Array()
	h.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			h[j * (n + 1) + i] = height(t0.x * Defs.TILE + i * d, t0.y * Defs.TILE + j * d)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for j in n:
		for i in n:
			var a := h[j * (n + 1) + i]
			var b := h[j * (n + 1) + i + 1]
			var c := h[(j + 1) * (n + 1) + i]
			var e := h[(j + 1) * (n + 1) + i + 1]
			if maxf(maxf(a, b), maxf(c, e)) > -0.031 and minf(minf(a, b), minf(c, e)) > -0.031:
				continue                   # flat land under the grass
			any = true
			var x0 := t0.x * Defs.TILE + i * d
			var z0 := t0.y * Defs.TILE + j * d
			var p00 := Vector3(x0, a, z0)
			var p10 := Vector3(x0 + d, b, z0)
			var p01 := Vector3(x0, c, z0 + d)
			var p11 := Vector3(x0 + d, e, z0 + d)
			for v in [p00, p10, p11, p00, p11, p01]:
				st.add_vertex(v)
	if not any:
		return null
	st.generate_normals()
	return st.commit()
