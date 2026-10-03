extends Node
## Loads model meshes from the exported GLBs and provides the shared palette material.

const DIR := "res://assets/models/"

var palette: StandardMaterial3D
var _meshes := {}


func _init() -> void:
	palette = StandardMaterial3D.new()
	palette.albedo_texture = load("res://assets/textures/palette.png")
	palette.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	palette.roughness = 1.0
	palette.metallic_specular = 0.0


func mesh(model: String) -> Mesh:
	if not _meshes.has(model):
		var scene: PackedScene = load(DIR + model + ".glb")
		var root := scene.instantiate()
		_meshes[model] = _find_mesh(root)
		root.free()
	return _meshes[model]


## A MeshInstance3D of the model with the palette material.
func instance(model: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh(model)
	mi.material_override = palette
	return mi


## Palette material tinted and semi-transparent (placement ghosts, planned roads).
func ghost_material(tint: Color) -> StandardMaterial3D:
	var m := palette.duplicate() as StandardMaterial3D
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = tint
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _find_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D:
		return node.mesh
	for child in node.get_children():
		var m := _find_mesh(child)
		if m:
			return m
	return null
