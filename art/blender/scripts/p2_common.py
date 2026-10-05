# Shared setup for the Phase 2 models (animals, trees, vehicles, buildings, resources, roads).
# Run inside Blender (Blender Lab MCP) after the Phase 0 / 1 helpers are in
# bpy.app.driver_namespace['farmio']:  exec(open(".../p2_common.py").read())
# Adds palette colours, part rigs, export and preview helpers to the same namespace as F['p2'].
import bpy, bmesh, math, random, json, os, shutil
from mathutils import Vector, Matrix, Euler

F = bpy.app.driver_namespace['farmio']
B = F['Builder']; IDX = F['IDX']; coll = F['coll']
REPO = os.path.dirname(F["ROOT"])                     # the repo of the helpers (p0_helpers.py)
MODELS = REPO + "/assets/models"
MANIFEST = REPO + "/scripts/tools/model_showcase.json"
NN, SW, SIZE = 16, 4, 64

NEW_COLORS = [
    # animals
    ("cow_white", "EFEBE2"), ("cow_black", "2B2725"), ("cow_brown", "8E4E2C"), ("cow_brown_dark", "6A3720"),
    ("cow_cream", "E6D6B4"), ("cow_tan", "B98552"), ("muzzle_pink", "DDA49A"), ("horn", "DCD0B2"),
    ("hoof", "3A302B"), ("wool", "ECE5D3"), ("wool_shade", "C8BDA3"), ("wool_cream", "DCCBA4"),
    ("wool_brown", "6E5442"), ("wool_brown_shade", "5A4436"), ("sheep_face", "3A3431"), ("sheep_pink", "D9B3A0"),
    ("goat_white", "EDE9DF"), ("goat_brown", "9A6942"), ("goat_brown_dark", "5E3E28"), ("goat_black", "322E2B"),
    ("hen_brown", "A5582E"), ("hen_brown_dark", "7C3F20"), ("hen_white", "F3F0E8"), ("hen_black", "2C2A2F"),
    ("comb_red", "D2372D"), ("beak", "E8B43C"), ("chick", "F4D95A"), ("tail_green", "2D4A3C"),
    ("hackle_orange", "D9782F"), ("eye", "151515"),
    # trees
    ("birch_bark", "EAE7DE"), ("birch_mark", "3B3734"), ("beech_bark", "8C8A82"), ("pine_bark", "A15F3A"),
    ("oak_leaf", "4C7A2F"), ("oak_leaf_light", "62913A"), ("beech_leaf", "6EA03E"), ("beech_leaf_light", "8BB750"),
    ("birch_leaf", "9AC45A"), ("birch_leaf_light", "B5D46A"), ("pine", "3A6A3A"), ("pine_light", "4B7D45"),
    ("spruce", "23523A"), ("spruce_light", "2F6447"), ("fruit_leaf", "5A9840"), ("fruit_leaf_light", "77AE4C"),
    ("apple_red", "C7372C"), ("apple_green", "A6C23E"), ("pear", "D7C24C"), ("plum", "5A3A72"),
    ("apricot", "EE9838"), ("blossom_white", "F6EEF0"), ("blossom_pink", "F0BFCF"),
    # vehicles
    ("veh_green", "3F8B3B"), ("veh_green_dark", "2C682B"), ("veh_red", "C33A2E"), ("veh_red_dark", "8F2A22"),
    ("veh_blue", "2F62AA"), ("veh_blue_dark", "234A82"), ("veh_yellow", "E9B92F"), ("veh_yellow_dark", "B88E1F"),
    ("veh_orange", "E07A2E"), ("veh_orange_dark", "B05C1F"), ("veh_white", "EDEDE8"), ("veh_grey", "5B6068"),
    ("veh_silver", "A9AEB4"), ("rim", "D9D4C8"), ("seat", "33302E"),
    # materials, goods, roads
    ("brick", "B4583A"), ("brick_dark", "8C4430"), ("water", "4F8FBE"), ("water_light", "79AFD4"),
    ("asphalt", "45474B"), ("asphalt_dark", "33353A"), ("asphalt_light", "5A5C60"), ("road_paint", "EEEAD8"),
    ("concrete", "C6C2B8"), ("concrete_dark", "A39F95"), ("concrete_light", "D8D5CC"),
    ("cobble", "8F8A80"), ("cobble_dark", "6C6861"), ("cobble_light", "ABA69B"),
    ("sack", "EAE1C9"), ("sack_shade", "CFC3A6"), ("bread", "BC7A3C"), ("bread_light", "DDA662"),
    ("sugar", "FAF8F2"), ("pasta", "ECD47C"), ("fert_blue", "3C78B8"), ("spray_green", "4D9E47"),
    ("plastic_white", "E8E8E2"), ("plastic_blue", "3473B8"), ("cardboard", "C7A16E"), ("pallet", "B88F5A"),
    ("milk", "FBFBF6"), ("egg", "EFE0C2"), ("egg_brown", "D2A97F"), ("manure", "4B3A28"), ("manure_dark", "3A2C1E"),
    ("hay_dark", "C9AA4F"), ("straw_dark", "CBAE62"), ("steel_blue", "6E8494"), ("solar", "2D3C5A"),
    ("canvas_green", "5E7A4A"), ("rust", "9B5434"), ("chimney", "6E6A66"), ("hay_green", "B3B860"), ("hay_green_dark", "939A4A"),
]


def add_colors(cols):
    img = bpy.data.images["farmio_palette"]
    px = list(img.pixels)
    for name, hx in cols:
        if name not in IDX:
            IDX[name] = len(IDX)
        i = IDX[name]
        assert i < NN * NN, "palette full"
        rgb = [int(hx[k:k + 2], 16) / 255 for k in (0, 2, 4)]
        cx, cy = i % NN, i // NN
        for yy in range(SW):
            for xx in range(SW):
                x = cx * SW + xx; y = SIZE - 1 - (cy * SW + yy); k = (y * SIZE + x) * 4
                px[k:k + 4] = rgb + [1.0]
    img.pixels = px
    img.filepath_raw = REPO + "/art/textures/palette.png"
    img.save()
    shutil.copyfile(REPO + "/art/textures/palette.png", REPO + "/assets/textures/palette.png")


def p2_coll(name):
    root = coll("P2")
    return coll(name, root)


def clear_coll(c):
    for o in list(c.objects):
        me = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        if me and me.users == 0:
            bpy.data.meshes.remove(me)


def rig(name, parts, c, loc=(0, 0, 0)):
    """parts: {part: (Builder, pivot)} built in model space. Makes an empty `name` with children
    `name__part` whose origin is the pivot (the game rotates parts around it)."""
    root = bpy.data.objects.new(name, None)
    root.empty_display_size = 0.3
    c.objects.link(root)
    for part, (b, pivot) in parts.items():
        b.bm.transform(Matrix.Translation(-Vector(pivot)))
        ob = b.build(f"{name}__{part}", c)
        ob.parent = root
        ob.location = pivot
    root.location = loc
    return root


def export(ob, name=None):
    """One GLB per model; the model is exported at the origin (gallery offset removed)."""
    name = name or ob.name
    objs = [ob] + list(ob.children_recursive)
    saved = ob.location.copy()
    ob.location = (0, 0, 0)
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.hide_set(False)
        o.select_set(True)
    bpy.context.view_layer.objects.active = ob
    import io, contextlib, logging
    logging.disable(logging.CRITICAL)
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        bpy.ops.export_scene.gltf(filepath=f"{MODELS}/{name}.glb", use_selection=True, export_format="GLB",
                                  export_image_format="NONE", export_apply=True, export_yup=True)
    logging.disable(logging.NOTSET)
    ob.location = saved
    bpy.ops.object.select_all(action='DESELECT')
    return name


def manifest_set(group, entries):
    """entries: list of [model, label] for the Godot showcase; groups keep the order of first use."""
    data = {}
    if os.path.exists(MANIFEST):
        with open(MANIFEST) as f:
            data = json.load(f)
    groups = data.setdefault("groups", [])
    for g in groups:
        if g["name"] == group:
            g["models"] = entries
            break
    else:
        groups.append({"name": group, "models": entries})
    with open(MANIFEST, "w") as f:
        json.dump(data, f, indent=1)


class Gallery:
    """Lays models out in rows in the Phase1 scene, south of the Phase 1 content."""
    def __init__(self, x0, y0, dx, dy, per_row):
        self.x0, self.y0, self.dx, self.dy, self.per_row, self.i = x0, y0, dx, dy, per_row, 0
    def next(self):
        r, c = divmod(self.i, self.per_row)
        self.i += 1
        return (self.x0 + c * self.dx, self.y0 - r * self.dy, 0)


def uv_of(color):
    i = IDX[color]
    return ((i % NN + 0.5) / NN, 1 - (i // NN + 0.5) / NN)


def recolor(src, name, mapping, c, loc):
    """Copy of a single-mesh model with palette colours swapped: mapping {old colour: new colour}."""
    me = src.data.copy()
    me.name = name
    uvs = me.uv_layers.active.data
    table = [(Vector(uv_of(a)), Vector(uv_of(b))) for a, b in mapping.items()]
    for d in uvs:
        for old, new in table:
            if (Vector(d.uv) - old).length < 1e-4:
                d.uv = new
                break
    ob = bpy.data.objects.new(name, me)
    c.objects.link(ob)
    ob.location = loc
    return ob


F['p2'] = dict(add_colors=add_colors, p2_coll=p2_coll, clear_coll=clear_coll, rig=rig, export=export,
               manifest_set=manifest_set, Gallery=Gallery, MODELS=MODELS, REPO=REPO, recolor=recolor, uv_of=uv_of)
add_colors(NEW_COLORS)
result = {"colors": len(IDX)}
