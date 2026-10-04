# Cobblestone, asphalt and concrete road pieces, same set and outlines as road_dirt_* / road_gravel_*:
# two-way 2x2 tiles (straight, corner, t, cross, end), one-way 1 tile (straight with arrow, corner).
import bpy, math, random
from mathutils import Vector

F = bpy.app.driver_namespace['farmio']; P2 = F['p2']
B = F['Builder']; export = P2['export']
G = F['road_piece'].__globals__
outline, inside, on_open_side, DIRS, rut_line, rut_arc = (G['outline'], G['inside'], G['on_open_side'], G['DIRS'],
                                                            G['rut_line'], G['rut_arc'])

SURF = {"cobble": "cobble_dark", "asphalt": "asphalt", "concrete": "concrete"}


def quad(b, x, y, z, sx, sy, color, rot=0.0):
    """Flat top-only tile (cheap: one face)."""
    c, s = math.cos(rot), math.sin(rot)
    pts = [(-sx / 2, -sy / 2), (sx / 2, -sy / 2), (sx / 2, sy / 2), (-sx / 2, sy / 2)]
    vs = [b.bm.verts.new((x + px * c - py * s, y + px * s + py * c, z)) for px, py in pts]
    f = b.bm.faces.new(vs)
    b._paint(vs, color)


def build_up(b, name, c, loc):
    """Build, then turn every lone flat face (markings, setts, panels) to face up: the normal
    recalculation can't tell which side of an isolated quad is the top, and Godot culls back faces."""
    import bmesh
    ob = b.build(name, c, loc=loc)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    for f in bm.faces:
        if f.normal.z < -0.9 and all(len(e.link_faces) == 1 for e in f.edges):
            f.normal_flip()
    bm.to_mesh(ob.data)
    bm.free()
    return ob


def centre_lines(sides, h, oneway):
    """Polylines along the middle of each lane connection (for dashes / joints)."""
    sl = sorted(sides); n = len(sides)
    opposite = n == 2 and set(sides) in ({'N', 'S'}, {'E', 'W'})
    if n == 2 and not opposite:
        d1, d2 = DIRS[sl[0]], DIRS[sl[1]]
        C = ((d1[0] + d2[0]) * h, (d1[1] + d2[1]) * h)
        a_c = math.degrees(math.atan2(-C[1], -C[0]))
        pts = []
        for i in range(13):
            a = math.radians(a_c - 45 + 90 * i / 12)
            pts.append((C[0] + h * math.cos(a), C[1] + h * math.sin(a)))
        return [pts]
    if opposite:
        d = DIRS[sl[0]]
        return [[(d[0] * h, d[1] * h), (-d[0] * h, -d[1] * h)]]
    stop = 0.0 if n > 2 else -h * 0.5
    return [[(DIRS[s][0] * h, DIRS[s][1] * h), (DIRS[s][0] * stop, DIRS[s][1] * stop)] for s in sides]


def dashed(b, line, w, color, dash=1.0, gap=0.8, z=0.062):
    """Dashes along a polyline: each dash is cut into the polyline segments it spans."""
    segs = []                                   # (start distance, p, q, length)
    total = 0.0
    for i in range(len(line) - 1):
        p, q = Vector(line[i]), Vector(line[i + 1])
        L = (q - p).length
        if L > 1e-6:
            segs.append((total, p, q, L))
            total += L
    n = int(total / (dash + gap)) + 1
    for k in range(n):
        s0 = k * (dash + gap) + gap / 2
        s1 = min(s0 + dash, total)
        for start, p, q, L in segs:
            a, e = max(s0, start), min(s1, start + L)
            if e - a < 0.02:
                continue
            pa = p + (q - p) * ((a - start) / L)
            pe = p + (q - p) * ((e - start) / L)
            m = (pa + pe) / 2
            quad(b, m.x, m.y, z, e - a, w, color, math.atan2((q - p).y, (q - p).x))


def road(name, mat, sides, size, oneway=False, arrow=False, loc=(0, 0, 0), seed=1, c=None):
    rnd = random.Random(seed); b = B(); h = size / 2
    pts = outline(sides, h, size)
    base = SURF[mat]
    bm = b.bm
    top = [bm.verts.new((x, y, 0.05)) for x, y in pts]
    bot = [bm.verts.new((x, y, 0.0)) for x, y in pts]
    bm.faces.new(top); b._paint(top, base)
    for i in range(len(pts)):
        j = (i + 1) % len(pts)
        q = [bot[i], bot[j], top[j], top[i]]
        bm.faces.new(q); b._paint(q, base)

    if mat == "cobble":
        # stones in staggered rows, the darker base shows in the joints
        s = 0.42
        n = int(size / s) + 1
        for i in range(n):
            for j in range(n):
                x = -h + (i + 0.5) * s + (s / 2 if j % 2 else 0)
                y = -h + (j + 0.5) * s
                if abs(x) > h - 0.05 or not inside(pts, x, y, 0.12):
                    continue
                quad(b, x, y, 0.056, s - 0.07, s - 0.07, rnd.choice(("cobble", "cobble", "cobble_light")), rnd.uniform(-0.08, 0.08))
    elif mat == "concrete":
        # cast panels 3 x 3 m with joints, slight colour variation
        k = int(size / 3.0)
        for i in range(k):
            for j in range(k):
                x, y = -h + 1.5 + i * 3.0, -h + 1.5 + j * 3.0
                corners = [(x + sx * 1.47, y + sy * 1.47) for sx in (-1, 1) for sy in (-1, 1)]
                if all(inside(pts, cx, cy, 0.0) for cx, cy in corners):
                    quad(b, x, y, 0.052, 2.94, 2.94, rnd.choice(("concrete", "concrete_light")))
        # joints every 3 m, clipped to the outline in short pieces
        step = 0.25
        for g in [-h + 3.0 * i for i in range(k + 1)]:
            for t in [-h + step * (m + 0.5) for m in range(int(size / step))]:
                for x, y, sx, sy in ((g, t, 0.05, step), (t, g, step, 0.05)):
                    if inside(pts, x, y, 0.05):
                        quad(b, x, y, 0.054, sx, sy, "concrete_dark")
    else:
        for i in range(int(size * size * 0.25)):          # patches / wear
            x, y = rnd.uniform(-h + 0.3, h - 0.3), rnd.uniform(-h + 0.3, h - 0.3)
            if inside(pts, x, y, 0.4):
                quad(b, x, y, 0.053, rnd.uniform(0.3, 0.9), rnd.uniform(0.3, 0.7), rnd.choice(("asphalt_dark", "asphalt_light")),
                     rnd.uniform(0, 3))

    # markings
    paint = "road_paint" if mat != "cobble" else None
    if paint and not oneway:
        for line in centre_lines(sides, h, oneway):
            dashed(b, line, 0.12, paint)
    # kerbs / fringe along the closed edges
    for i in range(len(pts)):
        p, q = pts[i], pts[(i + 1) % len(pts)]
        if on_open_side(p, q, sides, h):
            continue
        ex, ey = q[0] - p[0], q[1] - p[1]; L = math.hypot(ex, ey)
        if L < 1e-4:
            continue
        nx, ny = ey / L, -ex / L
        mx, my = (p[0] + q[0]) / 2 - nx * 0.1, (p[1] + q[1]) / 2 - ny * 0.1
        ang = math.degrees(math.atan2(ey, ex))
        if mat == "cobble":
            b.box((mx, my, 0.07), (L + 0.02, 0.2, 0.06), "stone", rot=(0, 0, ang))
            for k in range(max(1, round(L / 0.7))):
                t = (k + 0.5) / max(1, round(L / 0.7))
                if rnd.random() < 0.6:
                    b.cyl((p[0] + ex * t + nx * 0.08, p[1] + ey * t + ny * 0.08, 0.08), 0.12, 0.12, "grass_tuft", segs=4, r2=0.0)
        else:
            b.box((mx, my, 0.09), (L + 0.02, 0.2, 0.12), "concrete_light" if mat == "asphalt" else "concrete_dark", rot=(0, 0, ang))
            if paint and not oneway:
                b.box((mx - nx * 0.3, my - ny * 0.3, 0.061), (L + 0.02, 0.1, 0.012), paint, rot=(0, 0, ang))
    if arrow:
        arr = "road_paint" if mat != "cobble" else "cobble_light"
        b.box((0, -0.45, 0.065), (0.28, 1.0, 0.02), arr)
        tri = [b.bm.verts.new(p) for p in [(-0.45, 0.05, 0.075), (0.45, 0.05, 0.075), (0.0, 0.65, 0.075)]]
        b.bm.faces.new(tri); b._paint(tri, arr)
    return build_up(b, name, c, loc)


def bridge(name, mat, size, c, loc, seed=1):
    """Repeatable bridge piece over the river: road runs along Y, deck flush with the road
    (top at z 0.05), railings on both sides, structure and a pier reaching down into the river bed.
    A river crossing is a row of these pieces."""
    rnd = random.Random(seed); b = B(); h = size / 2
    W = size - 0.5                                     # carriageway; parapets / rails on the 0.25 m edges
    if mat == "dirt":                                  # rustic log bridge
        for i in range(int(size / 0.3)):
            y = -h + 0.15 + i * 0.3
            b.cyl((0, y, -0.08), 0.13, size, "bark", segs=6, rot=(0, 90, 0))
        b.box((0, 0, 0.0), (W - 0.6, size, 0.1), "dirt_road")
        for sx in (-1, 1):
            for y in (-h + 0.3, 0, h - 0.3):
                b.box((sx * (h - 0.15), y, 0.5), (0.16, 0.16, 1.0), "wood_dark")
            b.cyl((sx * (h - 0.15), 0, 0.92), 0.08, size, "wood", segs=6, rot=(90, 0, 0))
        for x in (-h * 0.6, h * 0.6):
            b.cyl((x, 0, -0.9), 0.18, 1.6, "bark", segs=7)
    elif mat == "gravel":                              # timber beam bridge on a stone pier
        b.box((0, 0, -0.2), (size, size, 0.3), "wood_dark")
        for i in range(int(size / 0.4)):
            b.box((0, -h + 0.2 + i * 0.4, 0.0), (size - 0.1, 0.36, 0.1), "wood" if i % 3 else "wood_light")
        b.box((0, 0, 0.055), (W - 0.8, size, 0.02), "gravel")
        for sx in (-1, 1):
            for y in (-h + 0.25, -h / 3, h / 3, h - 0.25):
                b.box((sx * (h - 0.12), y, 0.55), (0.14, 0.14, 1.0), "timber_dark")
            b.box((sx * (h - 0.12), 0, 1.0), (0.12, size, 0.12), "timber")
            b.box((sx * (h - 0.12), 0, 0.55), (0.08, size, 0.08), "timber")
        b.box((0, 0, -1.0), (size * 0.8, 0.8, 1.4), "stone")
    elif mat == "cobble":                              # stone arch segment with parapets
        b.box((0, 0, -0.15), (size, size, 0.4), "stone")
        b.box((0, 0, 0.055), (W, size, 0.01), "cobble_dark")
        s = 0.42
        for i in range(int(W / s)):
            for j in range(int(size / s)):
                quad(b, -W / 2 + (i + 0.5) * s, -h + (j + 0.5) * s, 0.062, s - 0.07, s - 0.07,
                     rnd.choice(("cobble", "cobble", "cobble_light")))
        for sx in (-1, 1):
            b.box((sx * (h - 0.13), 0, 0.45), (0.26, size, 0.8), "stone")
            b.box((sx * (h - 0.13), 0, 0.88), (0.32, size, 0.08), "stone_dark")
            b.box((sx * (h + 0.01), 0, -0.25), (0.04, size * 0.6, 0.3), "stone_dark")        # arch band on the face
        for sy in (-1, 1):
            b.box((0, sy * (h - 0.4), -1.0), (size, 0.8, 1.6), "stone_dark")    # piers at the piece ends
    else:                                              # asphalt / concrete: concrete girder bridge
        top = "asphalt" if mat == "asphalt" else "concrete"
        b.box((0, 0, -0.25), (size, size, 0.6), "concrete")
        b.box((0, 0, 0.055), (W, size, 0.01), top)
        if mat == "asphalt":
            if size > 4.0:                                 # two-way: centre line
                dashed(b, [(0, -h), (0, h)], 0.12, "road_paint")
            for sx in (-1, 1):
                b.box((sx * (W / 2 - 0.3), 0, 0.062), (0.1, size, 0.012), "road_paint")
        else:
            for j in range(int(size / 3.0)):
                quad(b, 0, -h + 3.0 * (j + 1) - 0.03, 0.062, W, 0.05, "concrete_dark")
        for sx in (-1, 1):
            b.box((sx * (h - 0.13), 0, 0.2), (0.26, size, 0.3), "concrete_light")         # kerb / edge beam
            if mat == "asphalt":                                                         # steel guard rail
                for y in (-h + 0.3, 0, h - 0.3):
                    b.box((sx * (h - 0.13), y, 0.65), (0.08, 0.08, 0.7), "metal_dark")
                b.box((sx * (h - 0.1), 0, 0.85), (0.06, size, 0.22), "metal")
            else:                                                                        # concrete parapet
                b.box((sx * (h - 0.13), 0, 0.65), (0.22, size, 0.7), "concrete")
        b.box((0, 0, -1.2), (size * 0.6, 0.9, 1.6), "concrete_dark")                     # pier
    return build_up(b, name, c, loc)


CURVE_C = (6.0, -6.0)            # wide curve: centre of the arc (outer corner of the inside block)
CURVE_R = (6.0, 12.0)            # inner / outer edge radius, the road axis runs at 9 m


def wide_curve(name, mat, c, loc, seed=1):
    """Two-way curve over 2x2 road blocks (12 x 12 m, origin in the middle): enters at the south edge
    of the south-west block, turns through the north-west block, leaves at the east edge of the
    north-east block; the arc (axis radius 9 m) is centred on the far corner of the south-east block,
    which lies on the inside of the bend."""
    rnd = random.Random(seed); b = B()
    cx, cy = CURVE_C
    r0, r1 = CURVE_R
    rm = (r0 + r1) / 2
    segs = 24
    def P(r, a, z):
        return (cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a)), z)
    angles = [180 - 90 * i / segs for i in range(segs + 1)]
    base = {"dirt": "dirt_road", "gravel": "gravel"}.get(mat, SURF.get(mat))
    dark = {"dirt": "dirt_road_dark", "gravel": "gravel_dark"}.get(mat)
    # closed slab (top, bottom, walls, ends) so the normals come out right
    bm = b.bm
    rings = {(r, z): [bm.verts.new(P(r, a, z)) for a in angles] for r in (r0, r1) for z in (0.0, 0.05)}
    for i in range(segs):
        quads = [
            [rings[(r0, 0.05)][i], rings[(r1, 0.05)][i], rings[(r1, 0.05)][i + 1], rings[(r0, 0.05)][i + 1]],
            [rings[(r0, 0.0)][i + 1], rings[(r1, 0.0)][i + 1], rings[(r1, 0.0)][i], rings[(r0, 0.0)][i]],
            [rings[(r1, 0.0)][i], rings[(r1, 0.0)][i + 1], rings[(r1, 0.05)][i + 1], rings[(r1, 0.05)][i]],
            [rings[(r0, 0.0)][i + 1], rings[(r0, 0.0)][i], rings[(r0, 0.05)][i], rings[(r0, 0.05)][i + 1]],
        ]
        for q in quads:
            bm.faces.new(q); b._paint(q, base)
    for k in (0, segs):
        q = [rings[(r0, 0.0)][k], rings[(r1, 0.0)][k], rings[(r1, 0.05)][k], rings[(r0, 0.05)][k]]
        bm.faces.new(q); b._paint(q, base)

    def ring_strip(r, w, color, z, dash=None):
        """A painted strip along the arc at radius r (solid, or dashed: (length, gap))."""
        L = r * math.pi / 2
        if dash:
            pts = [P(r, a, 0)[:2] for a in angles]
            dashed(b, pts, w, color, dash[0], dash[1], z)
            return
        for i in range(segs):
            a0, a1 = angles[i], angles[i + 1]
            p, q = P(r, a0, z), P(r, a1, z)
            m = ((p[0] + q[0]) / 2, (p[1] + q[1]) / 2)
            quad(b, m[0], m[1], z, math.hypot(q[0] - p[0], q[1] - p[1]) + 0.02, w, color, math.atan2(q[1] - p[1], q[0] - p[0]))

    def along_edges(fn):
        """Calls fn(x, y, angle_deg, outward_sign) along the inner and outer edge."""
        for r, s in ((r0 + 0.1, -1), (r1 - 0.1, 1)):
            n = max(4, round(r * math.pi / 2 / 0.7))
            for k in range(n):
                a = 180 - 90 * (k + 0.5) / n
                x, y, _ = P(r, a, 0)
                fn(x, y, a, s)

    def in_band(x, y, margin):
        d = math.hypot(x - cx, y - cy)
        return r0 + margin < d < r1 - margin and x < cx and y > cy

    if mat in ("dirt", "gravel"):
        for o in (-2.3, -0.7, 0.7, 2.3):
            rut_arc(b, CURVE_C, rm + o, 90, 180, 0.32, dark, segs=16)
        for k in range(int(144 * (1.6 if mat == "gravel" else 0.4))):
            x, y = rnd.uniform(-6, 6), rnd.uniform(-6, 6)
            if in_band(x, y, 0.15):
                col = rnd.choice(["gravel_dark", "gravel_light"]) if mat == "gravel" else "stone"
                b.box((x, y, 0.055), (rnd.uniform(0.06, 0.14), rnd.uniform(0.06, 0.14), 0.02), col, rot=(0, 0, rnd.uniform(0, 90)))
        def edge(x, y, a, s):
            if mat == "gravel":
                b.box((x, y, 0.07), (0.22, 0.22, 0.1), "stone", rot=(0, 0, rnd.uniform(0, 30)))
            elif rnd.random() < 0.8:
                b.cyl((x, y, 0.08), 0.12, 0.12, "grass_tuft", segs=4, r2=0.0, rot=(0, 0, rnd.uniform(0, 90)))
        along_edges(edge)
    elif mat == "cobble":
        s = 0.42
        r = r0 + 0.25
        while r < r1 - 0.2:
            n = int(r * math.pi / 2 / s)
            for k in range(n):
                a = 180 - 90 * (k + 0.5 + (0.5 if int((r - r0) / s) % 2 else 0)) / n
                half = math.degrees(s * 0.5 / r)          # keep whole setts inside the piece ends
                if a - half < 90 or a + half > 180:
                    continue
                x, y, _ = P(r, a, 0)
                quad(b, x, y, 0.056, s - 0.07, s - 0.07, rnd.choice(("cobble", "cobble", "cobble_light")), math.radians(a))
            r += s
        def edge(x, y, a, sgn):
            b.box((x, y, 0.07), (0.6, 0.2, 0.06), "stone", rot=(0, 0, a + 90))
            if rnd.random() < 0.6:
                b.cyl((x - sgn * math.cos(math.radians(a)) * -0.1, y, 0.08), 0.12, 0.12, "grass_tuft", segs=4, r2=0.0)
        along_edges(edge)
    else:
        if mat == "asphalt":
            for k in range(30):
                x, y = rnd.uniform(-6, 6), rnd.uniform(-6, 6)
                if in_band(x, y, 0.5):
                    quad(b, x, y, 0.053, rnd.uniform(0.3, 0.9), rnd.uniform(0.3, 0.7), rnd.choice(("asphalt_dark", "asphalt_light")), rnd.uniform(0, 3))
        else:
            ring_strip(rm, 0.05, "concrete_dark", 0.054)
            for k in range(1, 6):                                   # radial panel joints
                a = 180 - 90 * k / 6
                for t in range(24):
                    rr = r0 + (r1 - r0) * (t + 0.5) / 24
                    x, y, _ = P(rr, a, 0)
                    quad(b, x, y, 0.054, (r1 - r0) / 24, 0.05, "concrete_dark", math.radians(a))
        ring_strip(rm, 0.12, "road_paint", 0.062, dash=(1.0, 0.8))
        ring_strip(r0 + 0.4, 0.1, "road_paint", 0.061)
        ring_strip(r1 - 0.4, 0.1, "road_paint", 0.061)
        kerb = "concrete_light" if mat == "asphalt" else "concrete_dark"
        for r in (r0 + 0.1, r1 - 0.1):
            for i in range(segs):
                p, q = P(r, angles[i], 0), P(r, angles[i + 1], 0)
                b.box(((p[0] + q[0]) / 2, (p[1] + q[1]) / 2, 0.09), (math.hypot(q[0] - p[0], q[1] - p[1]) + 0.03, 0.2, 0.12), kerb,
                      rot=(0, 0, math.degrees(math.atan2(q[1] - p[1], q[0] - p[0]))))
    return build_up(b, name, c, loc)


KINDS = [("straight", {'N', 'S'}), ("corner", {'N', 'E'}), ("t", {'N', 'E', 'S'}), ("cross", {'N', 'E', 'S', 'W'}), ("end", {'S'})]


def build_all(do_export=True):
    c = P2['p2_coll']("P2_Roads")
    P2['clear_coll'](c)
    groups = []
    for row, (mat, label) in enumerate((("cobble", "Cobblestone road"), ("asphalt", "Asphalt road"), ("concrete", "Concrete road"))):
        ents = []
        y = -140 - row * 9
        for i, (kn, sides) in enumerate(KINDS):
            ob = road(f"road_{mat}_twoway_{kn}", mat, sides, 6.0, loc=(150 + i * 8, y, 0), seed=i + row * 10, c=c)
            ents.append([ob.name, kn])
        ob = road(f"road_{mat}_oneway_straight", mat, {'N', 'S'}, 3.0, oneway=True, arrow=True, loc=(192, y, 0), seed=50 + row, c=c)
        ents.append([ob.name, "one-way"])
        ob = road(f"road_{mat}_oneway_corner", mat, {'N', 'E'}, 3.0, oneway=True, loc=(197, y, 0), seed=60 + row, c=c)
        ents.append([ob.name, "one-way corner"])
        if do_export:
            for n, _ in ents:
                export(bpy.data.objects[n])
        groups.append(("Roads: " + label, ents))
    # demo network mixing the surfaces
    net = {(0, 0): {'E', 'N'}, (1, 0): {'W', 'E'}, (2, 0): {'W', 'N', 'E'}, (3, 0): {'W', 'N'},
           (0, 1): {'S', 'N'}, (2, 1): {'S', 'N'}, (3, 1): {'S', 'N'},
           (0, 2): {'S', 'E'}, (1, 2): {'W', 'E'}, (2, 2): {'W', 'E', 'S', 'N'}, (3, 2): {'W', 'S'}, (2, 3): {'S'}}
    for (gx, gy), sides in net.items():
        mat = "asphalt" if gx >= 2 and gy >= 1 else ("cobble" if gy == 0 else "concrete")
        road(f"road_demo2_{gx}_{gy}", mat, sides, 6.0, loc=(210 + gx * 6, -160 + gy * 6, 0), seed=gx * 7 + gy, c=c)
    # bridges for every road surface (the Phase 1 dirt / gravel roads too)
    ents = []
    for row, (mat, label) in enumerate((("dirt", "dirt"), ("gravel", "gravel"), ("cobble", "cobblestone"),
                                        ("asphalt", "asphalt"), ("concrete", "concrete"))):
        y = -180 - row * 9
        for kind, size, x in (("twoway", 6.0, 150), ("oneway", 3.0, 160)):
            ob = bridge(f"bridge_{mat}_{kind}", mat, size, c, (x, y, 0), seed=row)
            if do_export:
                export(ob)
            ents.append([ob.name, f"{label} {kind.replace('way', '-way')}"])
    groups.append(("Roads: Bridges", ents))
    # wide curves over 2x2 blocks for every road surface
    ents = []
    for i, (mat, label) in enumerate((("dirt", "dirt"), ("gravel", "gravel"), ("cobble", "cobblestone"),
                                      ("asphalt", "asphalt"), ("concrete", "concrete"))):
        ob = wide_curve(f"road_{mat}_twoway_curve_wide", mat, c, (240 + i * 14, -190, 0), seed=i)
        if do_export:
            export(ob)
        ents.append([ob.name, label])
    groups.append(("Roads: Wide curves", ents))
    return groups
