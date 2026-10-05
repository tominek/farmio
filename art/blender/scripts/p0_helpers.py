# Phase 0 / 1 Blender helpers, restored into bpy.app.driver_namespace['farmio'] (they are lost when
# Blender restarts). Run first, then p2_common.py:
#   exec(open(".../p0_helpers.py").read()); exec(open(".../p2_common.py").read())
# Builder: bmesh model builder painting faces with palette swatches (rot in degrees).
import bpy, bmesh, math, random, os
from mathutils import Vector, Matrix, Euler

# the repo this script lives in (a worktree builds into itself); the main checkout when run by hand
ROOT = (os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        if "__file__" in globals() else "/Users/tomin/Projects/tominek/farmio/art")
N = 16
BASE = ["grass", "grass_dark", "grass_light", "soil", "soil_dark", "soil_light", "dirt_road", "dirt_road_dark",
        "wood_dark", "wood", "wood_light", "bark", "leaf_dark", "leaf", "leaf_light", "conifer", "conifer_light",
        "barn_red", "barn_red_dark", "trim_white", "roof", "roof_dark", "stone", "stone_dark", "wheat_green",
        "wheat_young", "wheat_gold", "wheat_ripe", "stubble", "skin1", "skin2", "skin3", "skin4", "shirt_blue",
        "shirt_red", "shirt_green", "shirt_yellow", "denim", "pants_brown", "hair_dark", "hair_blond", "hair_red",
        "boots", "car_blue", "car_blue_dark", "glass", "tire", "metal", "metal_dark", "headlight", "taillight",
        "straw", "white", "black", "hay", "sign_yellow", "orange", "plaster", "plaster_shade", "roof_tile",
        "roof_tile_dark", "timber", "timber_dark", "grass_a", "grass_b", "grass_c", "grass_tuft", "grass_tuft_light",
        "flower_white", "flower_yellow", "flower_purple", "wheat_leaf", "wheat_leaf_young", "wheat_turning",
        "wheat_straw", "wheat_ear", "wheat_ear_green", "gravel", "gravel_dark", "gravel_light", "plaster_warm",
        "shutter_green", "flower_red", "sign_wood"]
IDX = {n: i for i, n in enumerate(BASE)}
mat = bpy.data.materials["M_Palette"]


class Builder:
    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
    def _paint(self, verts, color):
        i = IDX[color]
        u = ((i % N + 0.5) / N, 1 - (i // N + 0.5) / N)
        faces = {f for v in verts for f in v.link_faces}
        for f in faces:
            for l in f.loops: l[self.uv].uv = u
        return faces
    @staticmethod
    def M(c=(0, 0, 0), rot=(0, 0, 0), s=(1, 1, 1)):
        return Matrix.Translation(Vector(c)) @ Euler([math.radians(a) for a in rot]).to_matrix().to_4x4() @ Matrix.Diagonal((*s, 1))
    def box(self, c, s, color, rot=(0, 0, 0)):
        r = bmesh.ops.create_cube(self.bm, size=1.0, matrix=self.M(c, rot, s))
        self._paint(r['verts'], color); return r['verts']
    def cyl(self, c, r1, depth, color, segs=8, r2=None, rot=(0, 0, 0)):
        r = bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=segs,
                                  radius1=r1, radius2=(r1 if r2 is None else r2), depth=depth, matrix=self.M(c, rot))
        self._paint(r['verts'], color); return r['verts']
    def ico(self, c, rad, color, sub=1, s=(1, 1, 1), jitter=0.0, seed=0):
        r = bmesh.ops.create_icosphere(self.bm, subdivisions=sub, radius=rad, matrix=self.M(c, (0, 0, 0), s))
        rnd = random.Random(seed)
        for v in r['verts']:
            v.co += Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1))) * jitter * rad
        self._paint(r['verts'], color); return r['verts']
    def prism(self, prof, a0, a1, color, axis='Y', offset=(0, 0, 0)):
        """prof: list of (p, z); extruded along axis from a0 to a1. axis Y: p = x. axis X: p = y."""
        o = Vector(offset)
        def P(p, z, a):
            return o + (Vector((p, a, z)) if axis == 'Y' else Vector((a, p, z)))
        f = [self.bm.verts.new(P(p, z, a0)) for p, z in prof]
        b = [self.bm.verts.new(P(p, z, a1)) for p, z in prof]
        n = len(prof)
        self.bm.faces.new(f); self.bm.faces.new(list(reversed(b)))
        for i in range(n):
            j = (i + 1) % n
            self.bm.faces.new([f[i], f[j], b[j], b[i]])
        self._paint(f + b, color); return f + b
    def build(self, name, coll, loc=(0, 0, 0), rotz=0):
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces[:])
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me); self.bm.free()
        me.materials.append(mat)
        ob = bpy.data.objects.new(name, me)
        ob.location = loc; ob.rotation_euler.z = math.radians(rotz)
        coll.objects.link(ob)
        return ob


def coll(name, parent=None):
    c = bpy.data.collections.get(name) or bpy.data.collections.new(name)
    p = parent or bpy.context.scene.collection
    if c.name not in p.children: p.children.link(c)
    return c


def merge(dst, src, matrix):
    src.bm.transform(matrix)
    me = bpy.data.meshes.new("tmp"); src.bm.to_mesh(me); src.bm.free()
    dst.bm.from_mesh(me); bpy.data.meshes.remove(me)


def shot(name, loc, scale, angles, res=(1600, 1000)):
    sc = bpy.context.scene
    rig = bpy.data.objects["P1_CamPivot"]; cam = bpy.data.objects["P1_Cam"]
    sc.render.resolution_x, sc.render.resolution_y = res
    rig.location = loc; cam.data.ortho_scale = scale
    out = []
    for i, a in enumerate(angles):
        rig.rotation_euler.z = math.radians(a)
        p = ROOT + f"/renders/p1_{name}_{i}.png"
        sc.render.filepath = p; bpy.ops.render.render(write_still=True); out.append(p)
    return out

def tile_roof(b, HX, D, WH, pitch_deg, OV=0.5, XOV=0.45, rows=8):
    """gable roof, ridge along X, with tile rows; returns ridge height"""
    t = math.tan(math.radians(pitch_deg))
    RZ = WH + D*t
    for sy in (1, -1):
        ey, ez = sy*(D + OV), WH - OV*t
        L = math.hypot(D + OV, RZ - ez) + 0.15
        ang = -pitch_deg if sy == 1 else pitch_deg
        nyy, nzz = sy*math.sin(math.radians(pitch_deg)), math.cos(math.radians(pitch_deg))
        b.box((0, ey/2 + nyy*0.12, (ez + RZ)/2 + nzz*0.12), (2*(HX + XOV), L, 0.2), "roof_tile", rot=(ang, 0, 0))
        for k in range(1, rows):
            tt = k/rows
            py, pz = ey*(1 - tt), ez + (RZ - ez)*tt
            b.box((0, py + nyy*0.235, pz + nzz*0.235), (2*(HX + XOV), 0.09, 0.06), "roof_tile_dark", rot=(ang, 0, 0))
        b.box((0, ey + sy*0.02, ez - 0.05), (2*(HX + XOV), 0.08, 0.22), "timber_dark")
    b.box((0, 0, RZ + 0.2), (2*(HX + XOV) + 0.05, 0.32, 0.32), "roof_tile_dark", rot=(45, 0, 0))
    return RZ

# --- road pieces (dirt / gravel); the Phase 2 surfaces reuse outline() & co. in p2_roads.py
B = Builder
c = bpy.data.collections.get("P1_Roads")
SURF = {"dirt": ("dirt_road", "dirt_road_dark"), "gravel": ("gravel", "gravel_dark")}
DIRS = {'N': (0, 1), 'S': (0, -1), 'E': (1, 0), 'W': (-1, 0)}

def rut_line(b, p0, p1, w, col):
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]; L = math.hypot(dx, dy)
    if L < 1e-3: return
    b.box(((p0[0] + p1[0])/2, (p0[1] + p1[1])/2, 0.056), (w, L + 0.02, 0.012), col, rot=(0, 0, math.degrees(math.atan2(dy, dx)) - 90))

def rut_arc(b, center, r, a0, a1, w, col, segs=6):
    for i in range(segs):
        t0 = math.radians(a0 + (a1 - a0)*i/segs); t1 = math.radians(a0 + (a1 - a0)*(i + 1)/segs)
        rut_line(b, (center[0] + r*math.cos(t0), center[1] + r*math.sin(t0)), (center[0] + r*math.cos(t1), center[1] + r*math.sin(t1)), w, col)

def outline(sides, h, size):
    """Convex outline of the road surface (counter-clockwise)."""
    sl = sorted(sides); n = len(sides)
    opposite = n == 2 and set(sides) in ({'N', 'S'}, {'E', 'W'})
    if n == 2 and not opposite:      # corner: quarter disc around the shared corner
        d1, d2 = DIRS[sl[0]], DIRS[sl[1]]
        C = ((d1[0] + d2[0])*h, (d1[1] + d2[1])*h)
        a_c = math.degrees(math.atan2(-C[1], -C[0]))
        pts = [C]
        for i in range(13):
            a = math.radians(a_c - 45 + 90*i/12)
            pts.append((C[0] + size*math.cos(a), C[1] + size*math.sin(a)))
        return pts
    if n == 1:                       # dead end: rounded cap opposite the open side
        d = DIRS[sl[0]]; ad = math.degrees(math.atan2(d[1], d[0]))
        arc = []
        for i in range(13):
            a = math.radians(ad + 90 + 180*i/12)
            arc.append((h*math.cos(a), h*math.sin(a)))
        return arc + [(arc[-1][0] + d[0]*h, arc[-1][1] + d[1]*h), (arc[0][0] + d[0]*h, arc[0][1] + d[1]*h)]
    return [(-h, -h), (h, -h), (h, h), (-h, h)]

def inside(pts, x, y, margin):
    n = len(pts)
    for i in range(n):
        ax, ay = pts[i]; bx, by = pts[(i + 1) % n]
        ex, ey = bx - ax, by - ay; L = math.hypot(ex, ey)
        if L < 1e-6: continue
        if (ex*(y - ay) - ey*(x - ax))/L < margin: return False
    return True

def on_open_side(p, q, sides, h):
    for s in sides:
        d = DIRS[s]
        if abs(p[0]*d[0] + p[1]*d[1] - h) < 1e-4 and abs(q[0]*d[0] + q[1]*d[1] - h) < 1e-4: return True
    return False

def road_piece(name, mat, sides, size, oneway=False, arrow=False, loc=(0, 0, 0), seed=1):
    rnd = random.Random(seed); b = B(); h = size/2
    base, dark = SURF[mat]
    pts = outline(sides, h, size)
    # base slab following the outline (top + sides, no bottom)
    bm = b.bm
    top = [bm.verts.new((x, y, 0.05)) for x, y in pts]
    bot = [bm.verts.new((x, y, 0.0)) for x, y in pts]
    bm.faces.new(top); b._paint(top, base)
    for i in range(len(pts)):
        j = (i + 1) % len(pts)
        q = [bot[i], bot[j], top[j], top[i]]
        bm.faces.new(q); b._paint(q, base)
    offs = [-0.8, 0.8] if oneway else [-2.3, -0.7, 0.7, 2.3]
    sl = sorted(sides); n = len(sides)
    opposite = n == 2 and set(sides) in ({'N', 'S'}, {'E', 'W'})
    if n == 2 and not opposite:
        d1, d2 = DIRS[sl[0]], DIRS[sl[1]]
        cx, cy = (d1[0] + d2[0])*h, (d1[1] + d2[1])*h
        a_c = math.degrees(math.atan2(-cy, -cx))
        for o in offs:
            rut_arc(b, (cx, cy), h + o, a_c - 45, a_c + 45, 0.32, dark)
    elif opposite:
        d = DIRS[sl[0]]
        for o in offs:
            px_, py_ = -d[1]*o, d[0]*o
            rut_line(b, (d[0]*h + px_, d[1]*h + py_), (-d[0]*h + px_, -d[1]*h + py_), 0.32, dark)
    else:
        stop = h*0.55
        for s in sides:
            d = DIRS[s]
            for o in offs:
                px_, py_ = -d[1]*o, d[0]*o
                end = -h*0.55 if n == 1 else stop
                rut_line(b, (d[0]*h + px_, d[1]*h + py_), (d[0]*end + px_, d[1]*end + py_), 0.32, dark)
    for k in range(int(size*size*(1.6 if mat == "gravel" else 0.4))):
        x, y = rnd.uniform(-h + 0.1, h - 0.1), rnd.uniform(-h + 0.1, h - 0.1)
        if not inside(pts, x, y, 0.15): continue
        col = rnd.choice(["gravel_dark", "gravel_light"]) if mat == "gravel" else "stone"
        b.box((x, y, 0.055), (rnd.uniform(0.06, 0.14), rnd.uniform(0.06, 0.14), 0.02), col, rot=(0, 0, rnd.uniform(0, 90)))
    # grass fringe / stones along the closed edges of the outline
    for i in range(len(pts)):
        p, q = pts[i], pts[(i + 1) % len(pts)]
        if on_open_side(p, q, sides, h): continue
        ex, ey = q[0] - p[0], q[1] - p[1]; L = math.hypot(ex, ey)
        if L < 1e-4: continue
        nx, ny = ey/L, -ex/L          # outward normal of a CCW outline
        cnt = max(1, round(L/0.5))
        for k in range(cnt):
            t = (k + 0.5)/cnt + rnd.uniform(-0.1, 0.1)/max(L, 0.5)
            x, y = p[0] + ex*t - nx*0.05, p[1] + ey*t - ny*0.05
            if mat == "gravel":
                b.box((x, y, 0.07), (0.22, 0.22, 0.1), "stone", rot=(0, 0, rnd.uniform(0, 30)))
            else:
                b.cyl((x, y, 0.08), 0.12, 0.12, "grass_tuft", segs=4, r2=0.0, rot=(0, 0, rnd.uniform(0, 90)))
    if arrow:
        arr = "trim_white" if mat == "gravel" else "wood_light"
        b.box((0, -0.45, 0.065), (0.28, 1.0, 0.02), arr)
        tri = [b.bm.verts.new(p) for p in [(-0.45, 0.05, 0.075), (0.45, 0.05, 0.075), (0.0, 0.65, 0.075)]]
        b.bm.faces.new(tri); b._paint(tri, arr)
    return b.build(name, c, loc=loc)


ns = bpy.app.driver_namespace
ns['farmio'] = dict(Builder=Builder, coll=coll, mat=mat, ROOT=ROOT, IDX=IDX, N=N, merge=merge, shot=shot,
                    tile_roof=tile_roof, road_piece=road_piece)
result = {"colors": len(IDX)}
