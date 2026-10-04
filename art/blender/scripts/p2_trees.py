# European trees (pine, spruce, oak, beech, birch) and fruit trees for orchards (apple, pear,
# plum, apricot). Same style as tree_deciduous_* / tree_conifer_*: stages sapling / small / full,
# fruit trees also _blossom (spring) and _fruit (ripe). Origin at the foot of the trunk.
import bpy, math, random
from mathutils import Vector, Matrix

F = bpy.app.driver_namespace['farmio']; P2 = F['p2']
B = F['Builder']; export = P2['export']


def crown(b, pts, seed, jitter=0.12):
    """pts: [(x, y, z, r, color, (sx, sy, sz))] icosphere clusters."""
    for i, (x, y, z, r, col, s) in enumerate(pts):
        b.ico((x, y, z), r, col, sub=1, s=s, jitter=jitter, seed=seed + i)


def branch(b, p0, p1, r, color):
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    e = d.to_track_quat('Z', 'Y').to_euler()
    b.cyl(tuple((p0 + p1) / 2), r, d.length, color, segs=5, r2=r * 0.6, rot=tuple(math.degrees(a) for a in e))


# ------------------------------------------------------------------------------- forest trees

def oak(k, seed):
    b = B()
    b.cyl((0, 0, 1.0 * k), 0.36 * k, 2.0 * k, "bark", segs=7, r2=0.28 * k)
    for a, l in ((20, 1.3), (150, 1.2), (260, 1.1)):
        ra = math.radians(a)
        branch(b, (0, 0, 1.9 * k), (math.cos(ra) * l * k, math.sin(ra) * l * k, 3.0 * k), 0.14 * k, "bark")
    crown(b, [(0, 0, 3.6 * k, 1.75 * k, "oak_leaf", (1.1, 1.05, 0.75)),
              (1.25 * k, 0.4 * k, 3.2 * k, 1.1 * k, "oak_leaf", (1, 1, 0.8)),
              (-1.2 * k, -0.5 * k, 3.3 * k, 1.15 * k, "leaf_dark", (1, 1, 0.8)),
              (0.3 * k, -1.2 * k, 3.1 * k, 1.0 * k, "oak_leaf_light", (1, 1, 0.8)),
              (-0.3 * k, 0.9 * k, 4.3 * k, 1.0 * k, "oak_leaf_light", (1, 1, 0.8))], seed)
    return b


def beech(k, seed):
    b = B()
    b.cyl((0, 0, 1.4 * k), 0.27 * k, 2.8 * k, "beech_bark", segs=7, r2=0.2 * k)
    crown(b, [(0, 0, 4.2 * k, 1.5 * k, "beech_leaf", (1, 1, 1.25)),
              (0.7 * k, 0.3 * k, 3.4 * k, 1.05 * k, "leaf", (1, 1, 1)),
              (-0.6 * k, -0.4 * k, 3.5 * k, 1.05 * k, "beech_leaf", (1, 1, 1)),
              (-0.2 * k, 0.3 * k, 5.4 * k, 0.9 * k, "beech_leaf_light", (1, 1, 1))], seed)
    return b


def birch(k, seed):
    b = B()
    r = random.Random(seed)
    # the trunk runs up into the top cluster, tapering, so it never ends in the open
    b.cyl((0, 0, 2.7 * k), 0.15 * k, 5.4 * k, "birch_bark", segs=6, r2=0.04 * k)
    for i in range(int(9 * k) + 3):           # black bark marks
        z = r.uniform(0.3, 3.6) * k
        a = r.uniform(0, 360)
        rr = (0.15 - 0.06 * z / (4 * k)) * k
        b.box((math.cos(math.radians(a)) * rr, math.sin(math.radians(a)) * rr, z), (0.1 * k, 0.1 * k, 0.04 * k),
              "birch_mark", rot=(0, 0, a))
    pts = []
    for i in range(6):                         # airy crown of small clusters
        a = math.radians(i * 60 + r.uniform(-20, 20))
        d = r.uniform(0.35, 0.65) * k
        z = r.uniform(3.2, 5.0) * k
        pts.append((math.cos(a) * d, math.sin(a) * d, z, r.uniform(0.6, 0.8) * k,
                    r.choice(("birch_leaf", "birch_leaf_light", "birch_leaf")), (1, 1, 1.25)))
        branch(b, (0, 0, z - 0.6 * k), (math.cos(a) * d, math.sin(a) * d, z), 0.04 * k, "birch_bark")
    pts.append((0, 0, 5.4 * k, 0.6 * k, "birch_leaf_light", (1, 1, 1.3)))
    crown(b, pts, seed)
    return b


def pine(k, seed):
    b = B()
    r = random.Random(seed)
    b.cyl((0, 0, 1.0 * k), 0.24 * k, 2.0 * k, "bark", segs=6, r2=0.2 * k)
    b.cyl((0, 0, 3.6 * k), 0.2 * k, 3.2 * k, "pine_bark", segs=6, r2=0.12 * k)   # orange upper trunk
    for i, (a, l, z) in enumerate(((30, 0.9, 4.6), (160, 1.0, 5.0), (270, 0.8, 5.6))):
        ra = math.radians(a + r.uniform(-15, 15))
        branch(b, (0, 0, z * k - 0.4 * k), (math.cos(ra) * l * k, math.sin(ra) * l * k, z * k + 0.2 * k), 0.08 * k, "pine_bark")
        crown(b, [(math.cos(ra) * l * k, math.sin(ra) * l * k, z * k + 0.35 * k, 0.85 * k, "pine" if i % 2 else "pine_light",
                   (1.25, 1.25, 0.5))], seed + i * 3)
    crown(b, [(0, 0, 6.3 * k, 0.95 * k, "pine", (1.2, 1.2, 0.55))], seed + 20)
    return b


def spruce(k, seed):
    b = B()
    b.cyl((0, 0, 0.5 * k), 0.2 * k, 1.0 * k, "bark", segs=6, r2=0.15 * k)
    tiers = [(1.45, 1.6, 1.5), (1.25, 1.5, 2.5), (1.02, 1.4, 3.4), (0.8, 1.3, 4.3), (0.56, 1.2, 5.2), (0.32, 1.1, 6.0)]
    for i, (r, h, z) in enumerate(tiers):
        b.cyl((0, 0, z * k), r * k, h * k, "spruce" if i % 2 == 0 else "spruce_light", segs=8, r2=0.04 * k,
              rot=(0, 0, seed * 11 + i * 22))
    return b


# -------------------------------------------------------------------------------- fruit trees

FRUIT = {
    "apple": dict(fruit="apple_red", alt="apple_green", shape=(1, 1, 0.82), crown=(1.15, 1.15, 0.85), blossom="blossom_white", h=1.0),
    "pear": dict(fruit="pear", alt="apple_green", shape=(0.9, 0.9, 1.25), crown=(0.95, 0.95, 1.2), blossom="blossom_white", h=1.15),
    "plum": dict(fruit="plum", alt="plum", shape=(0.95, 0.95, 1.1), crown=(1.05, 1.05, 1.0), blossom="blossom_white", h=1.05),
    "apricot": dict(fruit="apricot", alt="apricot", shape=(1, 1, 1), crown=(1.25, 1.25, 0.8), blossom="blossom_pink", h=0.95),
}


def fruit_tree(kind, k, seed, state):
    """state: 'leaf', 'blossom' or 'fruit'."""
    f = FRUIT[kind]
    b = B()
    r = random.Random(seed)
    th = 1.25 * k * f["h"]
    b.cyl((0, 0, th / 2), 0.17 * k, th, "bark", segs=6, r2=0.13 * k)
    for a in (40, 170, 290):                     # three main limbs
        ra = math.radians(a + r.uniform(-15, 15))
        branch(b, (0, 0, th - 0.1 * k), (math.cos(ra) * 0.75 * k, math.sin(ra) * 0.75 * k, th + 0.8 * k), 0.08 * k, "bark")
    sx, sy, sz = f["crown"]
    lc = "fruit_leaf"
    second = "fruit_leaf_light"
    cz = th + 1.15 * k * sz
    blobs = [(0, 0, cz, 1.25 * k, lc, (sx, sy, sz)),
             (0.75 * k, 0.3 * k, cz - 0.35 * k, 0.8 * k, second, (1, 1, 0.9)),
             (-0.7 * k, -0.35 * k, cz - 0.3 * k, 0.8 * k, lc, (1, 1, 0.9)),
             (0.1 * k, -0.6 * k, cz + 0.5 * k * sz, 0.75 * k, second, (1, 1, 0.9))]
    if state not in ("fruit", "blossom"):
        crown(b, blobs, seed)
        return b
    # fruit / flowers sit on the actual crown faces (the low-poly crown is smaller than the
    # spheres it is built from), only on visible parts: not inside another cluster, not underneath
    cb = B()
    crown(cb, blobs, seed)
    import bmesh
    bmesh.ops.recalc_face_normals(cb.bm, faces=cb.bm.faces[:])
    def buried(p):
        for bx, by, bz, br, _, (ex, ey, ez) in blobs:
            q = Vector(((p.x - bx) / (br * ex), (p.y - by) / (br * ey), (p.z - bz) / (br * ez)))
            if q.length < 0.86:
                return True
        return False
    faces = [(f.calc_center_median(), f.normal.copy(), f.calc_area(), [v.co.copy() for v in f.verts])
             for f in cb.bm.faces if f.normal.z > -0.35]
    total = sum(a for _, _, a, _ in faces)
    n = 26 if state == "fruit" else 90
    placed = tries = 0
    while placed < n and tries < n * 20:
        tries += 1
        t = r.uniform(0, total)
        for ctr, nrm, area, vs in faces:
            t -= area
            if t <= 0:
                break
        u, w = r.random(), r.random()
        if u + w > 1:
            u, w = 1 - u, 1 - w
        p = vs[0] + (vs[1] - vs[0]) * u + (vs[2] - vs[0]) * w
        if buried(p):
            continue
        placed += 1
        if state == "fruit":
            s = 0.11 * max(k, 0.7)
            col = f["fruit"] if r.random() > 0.25 else f["alt"]
            b.ico(tuple(p + nrm * s * 0.45), s, col, sub=1, s=f["shape"])
        else:
            s = 0.065 * k
            b.ico(tuple(p + nrm * s * 0.3), s, f["blossom"] if r.random() > 0.2 else "flower_white", sub=0)
    F['merge'](b, cb, Matrix.Identity(4))
    return b


def sapling(kind):
    """Young tree with a support stake (orchards / tree farm) or a plain forest sapling."""
    b = B()
    conifer = kind in ("pine", "spruce")
    fruit = kind in FRUIT
    trunk = "birch_bark" if kind == "birch" else ("beech_bark" if kind == "beech" else "bark")
    b.cyl((0, 0, 0.5), 0.06, 1.0, trunk, segs=5)
    if conifer:
        col = "spruce_light" if kind == "spruce" else "pine_light"
        b.cyl((0, 0, 0.75), 0.42, 0.8, col, segs=6, r2=0.03)
        b.cyl((0, 0, 1.2), 0.28, 0.6, col, segs=6, r2=0.02)
    else:
        col = {"oak": "oak_leaf_light", "beech": "beech_leaf_light", "birch": "birch_leaf_light"}.get(kind, "fruit_leaf_light")
        b.ico((0, 0, 1.15), 0.42, col, sub=1, s=(1, 1, 1.1), jitter=0.1, seed=7)
    if fruit:
        b.box((0.12, 0, 0.75), (0.05, 0.05, 1.5), "wood_light")                   # stake
        b.box((0.06, 0, 0.9), (0.14, 0.03, 0.03), "straw")                        # tie
        b.cyl((0, 0, 0.02), 0.35, 0.04, "soil_dark", segs=8)                       # tree disc
    return b


KINDS = [("pine", pine), ("spruce", spruce), ("oak", oak), ("beech", beech), ("birch", birch)]


def build_all(do_export=True):
    c = P2['p2_coll']("P2_Trees")
    P2['clear_coll'](c)
    groups = []
    row = 0
    for kind, fn in KINDS:
        models = [(f"tree_{kind}_sapling", sapling(kind)), (f"tree_{kind}_small", fn(0.6, 3)), (f"tree_{kind}_full", fn(1.0, 5))]
        groups.append((kind, models))
    for kind in FRUIT:
        models = [(f"tree_{kind}_sapling", sapling(kind)), (f"tree_{kind}_small", fruit_tree(kind, 0.65, 3, "leaf")),
                  (f"tree_{kind}_full", fruit_tree(kind, 1.0, 5, "leaf")), (f"tree_{kind}_blossom", fruit_tree(kind, 1.0, 5, "blossom")),
                  (f"tree_{kind}_fruit", fruit_tree(kind, 1.0, 5, "fruit"))]
        groups.append((kind, models))
    out = []
    for row, (kind, models) in enumerate(groups):
        ents = []
        for i, (name, b) in enumerate(models):
            ob = b.build(name, c, loc=(60 + i * 5.0, -140 - row * 6.0, 0))
            if do_export:
                export(ob)
            ents.append([name, name.split("_")[-1]])
        title = {"pine": "Scots pine"}.get(kind, kind.title())
        out.append((("Fruit trees: " if kind in FRUIT else "Trees: ") + title, ents))
    return out
