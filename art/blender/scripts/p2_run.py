# Builds and exports Phase 2 model sets without the Blender UI:
#   Blender -b art/blender/style_exploration.blend --python art/blender/scripts/p2_run.py -- animals trees ...
# Options after "--": module names (animals, trees, vehicles, buildings, resources, roads),
# "noexport" (build only), "save" (save the .blend), "shot=<name>:<x>,<y>,<z>:<scale>:<angle>[:<w>x<h>]".
import bpy, sys, os

D = os.path.dirname(os.path.abspath(__file__)) + "/"
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
for f in ("p0_helpers.py", "p2_common.py"):
    exec(open(D + f).read(), {"__file__": D + f})
F = bpy.app.driver_namespace['farmio']; P2 = F['p2']
export = "noexport" not in args
if not bpy.data.objects.get("p2_ground"):              # grass under the gallery for preview renders
    b = F['Builder']()
    b.box((100, -420, -0.06), (320, 640, 0.1), "grass")
    b.build("p2_ground", P2['p2_coll']("P2_Ground"))

for name in [a for a in args if "=" not in a and a not in ("noexport", "save")]:
    ns = {"__file__": D + f"p2_{name}.py"}
    exec(open(D + f"p2_{name}.py").read(), ns)
    groups = ns["build_all"](do_export=export)
    if export:
        items = groups.items() if isinstance(groups, dict) else groups
        for g, ents in items:
            if isinstance(ents, list) and ents and isinstance(ents[0], (list, tuple)):
                P2['manifest_set'](g, [list(e) for e in ents])
    print("BUILT", name)

for a in args:
    if a.startswith("shot="):
        parts = a[5:].split(":")
        loc = tuple(float(v) for v in parts[1].split(","))
        res = tuple(int(v) for v in parts[4].split("x")) if len(parts) > 4 else (1600, 1100)
        print("SHOT", F['shot'](parts[0], loc, float(parts[2]), [float(parts[3])], res=res))

if "save" in args:
    for m in list(bpy.data.meshes):
        if m.users == 0:
            bpy.data.meshes.remove(m)
    bpy.ops.wm.save_mainfile()
    print("SAVED")
