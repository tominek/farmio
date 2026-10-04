# Farm animals as part rigs (body, head, legs, tail) for procedural animation in Godot
# (scripts/view/animal_figure.gd). Front = +Y. Parts: animal_<kind>_<variant>__<part>, pivots:
# legs at the hip / shoulder, head at the neck, tail at its root.
import bpy, math, random
from mathutils import Vector, Matrix, Euler

F = bpy.app.driver_namespace['farmio']; P2 = F['p2']
B = F['Builder']; rig = P2['rig']; export = P2['export']


def seg(b, p0, p1, w, color, h=None):
    """Box from p0 to p1 (w wide, h thick)."""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    q = d.to_track_quat('Y', 'Z')
    e = q.to_euler()
    return b.box(tuple((p0 + p1) / 2), (w, d.length, h if h is not None else w), color,
                 rot=tuple(math.degrees(a) for a in e))


def arc(b, center, r, a0, a1, steps, x, w0, w1, color, r_shrink=0.0):
    """Horn-like chain of boxes on an arc in the Y-Z plane at side x (angles in degrees, 0 = +Y)."""
    pts = []
    for i in range(steps + 1):
        t = i / steps
        a = math.radians(a0 + (a1 - a0) * t)
        rr = r * (1 - r_shrink * t)
        pts.append(Vector((x, center[0] + rr * math.cos(a), center[1] + rr * math.sin(a))))
    for i in range(steps):
        w = w0 + (w1 - w0) * i / steps
        seg(b, pts[i], pts[i + 1] + (pts[i + 1] - pts[i]) * 0.15, w, color)


# --------------------------------------------------------------------------------- quadrupeds

def quadruped(name, c, loc, d, col, extras=None):
    """d: dimensions, col: colour roles. extras(parts, d, col) adds species details."""
    L, W, H, LEG = d["L"], d["W"], d["H"], d["leg"]
    top = LEG + H
    lt = d["lt"]
    parts = {}

    body = B()
    body.box((0, 0, LEG + H / 2), (W, L, H), col["body"])
    # rounded feel: belly and back bevels
    body.box((0, 0, LEG + 0.02), (W * 0.8, L * 0.86, 0.06), col.get("belly", col["body"]))
    body.box((0, L * 0.02, top + 0.02), (W * 0.82, L * 0.9, 0.05), col["body"])
    for p in d.get("patches", []):          # (side, y, z / x, size_a, size_b): side 'L', 'R', 'T', 'B' (back end), 'F'
        side, u, v, sa, sb = p
        pc = col.get("patch", "cow_black")
        if side in "LR":
            sx = -1 if side == "L" else 1
            body.box((sx * (W / 2 + 0.006), u, v), (0.014, sa, sb), pc)
            body.box((sx * (W / 2 + 0.007), u + sa * 0.25, v - sb * 0.3), (0.014, sa * 0.75, sb * 0.7), pc, rot=(25, 0, 0))
        elif side == "T":
            body.box((u, v, top + 0.052), (sa, sb, 0.014), pc)
            body.box((u + sa * 0.3, v - sb * 0.25, top + 0.053), (sa * 0.7, sb * 0.8, 0.014), pc, rot=(0, 0, 20))
        elif side == "B":
            body.box((u, -L / 2 - 0.006, v), (sa, 0.014, sb), pc)
    parts["body"] = (body, (0, 0, 0))

    # legs (hoof at the bottom), pivot at the top of the leg inside the body
    leg_y = L / 2 - lt / 2 - d.get("leg_inset", 0.08)
    leg_x = W / 2 - lt / 2 - 0.04
    for key, sx, sy in (("leg_fl", -1, 1), ("leg_fr", 1, 1), ("leg_bl", -1, -1), ("leg_br", 1, -1)):
        lb = B()
        piv = (sx * leg_x, sy * leg_y, LEG + 0.12)
        lc = col.get("leg_f" if sy > 0 else "leg_b", col.get("leg", col["body"]))
        lb.box((piv[0], piv[1], (LEG + 0.12 + 0.1) / 2 + 0.0), (lt, lt, LEG + 0.12 - 0.1), lc)
        lb.box((piv[0], piv[1] + 0.01, 0.05), (lt * 1.05, lt * 1.1, 0.1), col.get("hoof", "hoof"))
        parts[key] = (lb, piv)

    # head on a neck: pivot at the front top of the body
    hw, hl, hh = d["head"]
    npiv = (0, L / 2 - 0.06, top - d.get("neck_drop", 0.12))
    hb = B()
    ny, nz = d.get("neck_dir", (0.22, 0.05))
    neck_end = (0, npiv[1] + ny, npiv[2] + nz)
    seg(hb, (0, npiv[1] - 0.1, npiv[2] - 0.08), neck_end, d.get("neck_w", W * 0.55), col.get("neck", col["body"]),
        h=d.get("neck_h", H * 0.6))
    tilt = d.get("head_tilt", -30)
    hc = Vector((0, neck_end[1] + hl * 0.35, neck_end[2] + d.get("head_up", 0.02)))
    R = Euler((math.radians(tilt), 0, 0)).to_matrix()
    def at(v):                                   # head-local offset -> model space
        return tuple(hc + R @ Vector(v))
    hb.box(at((0, 0, 0)), (hw, hl, hh), col.get("head", col["body"]), rot=(tilt, 0, 0))
    # muzzle
    mw, ml, mh = d.get("muzzle", (hw * 0.85, hl * 0.3, hh * 0.6))
    hb.box(at((0, hl / 2 + ml / 2 - 0.04, -hh / 2 + mh / 2 - 0.01)), (mw, ml, mh), col.get("muzzle", "muzzle_pink"), rot=(tilt, 0, 0))
    # eyes
    for sx in (-1, 1):
        hb.box(at((sx * (hw / 2 + 0.004), hl * 0.12, hh * 0.18)), (0.012, 0.04, 0.04), "eye", rot=(tilt, 0, 0))
    # ears
    ear_w, ear_l, ear_droop = d.get("ear", (0.16, 0.07, 10))
    for sx in (-1, 1):
        ep = Vector(at((sx * (hw / 2 + ear_w / 2 - 0.01), -hl * 0.3, hh * 0.32)))
        hb.box(tuple(ep), (ear_w, ear_l, 0.035), col.get("ear", col.get("head", col["body"])),
               rot=(tilt, sx * -ear_droop, 0))
    for p in d.get("head_patches", []):       # (x, y, z, sx, sy, sz) in head space
        hb.box(at(p[:3]), p[3:], col.get("head_patch", col.get("patch", "cow_white")), rot=(tilt, 0, 0))
    parts["head"] = (hb, npiv)
    head_at = at

    # tail
    tpiv = (0, -L / 2 + 0.02, top - 0.06)
    tb = B()
    tl = d.get("tail", 0.6)
    if d.get("tail_up"):
        seg(tb, tpiv, (0, tpiv[1] - 0.08, tpiv[2] + tl), 0.05, col.get("tail", col["body"]))
    else:
        seg(tb, tpiv, (0, tpiv[1] - 0.06, tpiv[2] - tl), d.get("tail_w", 0.05), col.get("tail", col["body"]))
        if d.get("tuft"):
            tb.box((0, tpiv[1] - 0.06, tpiv[2] - tl - 0.06), (0.08, 0.08, 0.16), col.get("tuft", "cow_black"))
    parts["tail"] = (tb, tpiv)

    if extras:
        extras(parts, d, col, head_at)
    return rig(name, parts, c, loc)


# ------------------------------------------------------------------------------------ cattle

def cow_extras(parts, d, col, at):
    body = parts["body"][0]; hb = parts["head"][0]
    L, W, LEG = d["L"], d["W"], d["leg"]
    tilt = d.get("head_tilt", -30)
    if d.get("udder"):
        body.box((0, -L * 0.25, LEG - 0.02), (W * 0.42, L * 0.2, 0.16), "muzzle_pink")
        for sx in (-1, 1):
            for sy in (-1, 1):
                body.box((sx * 0.07, -L * 0.25 + sy * 0.07, LEG - 0.13), (0.035, 0.035, 0.07), "muzzle_pink")
    hw, hl, hh = d["head"]
    hs = d.get("horns")
    if hs:                                   # horns: out to the side, then up / forward
        for sx in (-1, 1):
            p0 = Vector(at((sx * hw * 0.42, -hl * 0.4, hh * 0.45)))
            p1 = p0 + Vector((sx * hs * 0.75, 0.0, hs * 0.15))
            p2 = p1 + Vector((sx * hs * 0.25, 0.06, hs * 0.45))
            seg(hb, p0, p1, 0.06 * (1 + hs * 0.4), "horn")
            seg(hb, p1, p2, 0.045, d.get("horn_tip", "horn"))
    if d.get("ring"):
        p = Vector(at((0, hl / 2 + 0.06, -hh * 0.42)))
        for k in range(6):
            a0, a1 = k * 60, (k + 1) * 60
            q0 = p + Vector((0.055 * math.cos(math.radians(a0)), 0, 0.055 * math.sin(math.radians(a0))))
            q1 = p + Vector((0.055 * math.cos(math.radians(a1)), 0, 0.055 * math.sin(math.radians(a1))))
            seg(hb, q0, q1, 0.018, "metal")
    if d.get("hump"):
        body.box((0, L * 0.28, LEG + d["H"] + 0.06), (W * 0.7, L * 0.3, 0.14), col["body"])
        for p in d.get("hump_patch", []):
            pass
    if d.get("fringe"):                       # curly forehead
        hb.box(at((0, -hl * 0.12, hh / 2 + 0.01)), (hw * 0.8, hl * 0.3, 0.04), col.get("fringe", col.get("head", col["body"])), rot=(tilt, 0, 0))


def holstein_patches(L, W, H, LEG, seed, k=1.0):
    r = random.Random(seed); ps = []
    for side in "LR":
        for i in range(3):
            y = -L / 2 + L * (0.18 + 0.32 * i) + r.uniform(-0.08, 0.08) * k
            z = LEG + H * r.uniform(0.35, 0.68)
            ps.append((side, y, z, r.uniform(0.22, 0.42) * k, r.uniform(0.22, 0.38) * k))
    for i in range(2):
        ps.append(("T", r.uniform(-W * 0.2, W * 0.2), -L / 2 + L * (0.3 + 0.4 * i), r.uniform(0.25, 0.4) * k, r.uniform(0.25, 0.4) * k))
    return ps


def cattle(name, c, loc, kind, variant):
    adult = kind in ("cow", "bull")
    if kind == "cow":
        d = dict(L=1.75, W=0.72, H=0.78, leg=0.72, lt=0.16, head=(0.34, 0.5, 0.38), tail=0.62, tuft=True,
                 udder=True, horns=0.12, ear=(0.17, 0.07, 12))
    elif kind == "bull":
        d = dict(L=1.95, W=0.86, H=0.86, leg=0.7, lt=0.19, head=(0.42, 0.52, 0.44), tail=0.62, tuft=True,
                 horns=0.34, ring=True, hump=True, neck_w=0.6, neck_h=0.6, ear=(0.17, 0.07, 8), fringe=True)
    else:  # calf
        d = dict(L=0.98, W=0.42, H=0.44, leg=0.58, lt=0.1, head=(0.25, 0.36, 0.28), tail=0.36, tuft=True,
                 neck_drop=0.06, neck_dir=(0.14, 0.06), ear=(0.12, 0.05, 15), leg_inset=0.05,
                 muzzle=(0.21, 0.1, 0.16))
    L, W, H, LEG = d["L"], d["W"], d["H"], d["leg"]
    col = {"body": "cow_white", "hoof": "hoof"}
    if variant == "holstein":            # black and white
        col.update(body="cow_white", patch="cow_black", head="cow_black", head_patch="cow_white", ear="cow_black",
                   muzzle="muzzle_pink", tail="cow_white", tuft="cow_black", leg="cow_white")
        d["patches"] = holstein_patches(L, W, H, LEG, 3 if adult else 7, 1.0 if adult else 0.55)
        hw, hl, hh = d["head"]
        d["head_patches"] = [(0, -hl * 0.05, hh / 2 + 0.006, hw * 0.35, hl * 0.6, 0.012)]   # white blaze
    elif variant == "pied":              # red-pied (Czech Fleckvieh): red-brown patches, white head and legs
        col.update(body="cow_white", patch="cow_brown", head="cow_white", ear="cow_brown", muzzle="muzzle_pink",
                   tail="cow_brown", tuft="cow_white", leg="cow_white", neck="cow_brown")
        d["patches"] = holstein_patches(L, W, H, LEG, 11 if adult else 13, 1.25 if adult else 0.7)
        hw, hl, hh = d["head"]
        d["head_patches"] = [(sx * (hw / 2 + 0.004), -hl * 0.2, hh * 0.15, 0.012, hl * 0.3, hh * 0.35) for sx in (-1, 1)]
        col["head_patch"] = "cow_brown"
    elif variant == "brown":             # brown (Brown Swiss / Jersey-like), dark muzzle
        col.update(body="cow_tan", head="cow_tan", ear="cow_tan", muzzle="cow_black", tail="cow_tan", tuft="cow_black",
                   leg="cow_tan", belly="cow_cream")
        d["horn_tip"] = "cow_black"
    elif variant == "black":             # black beef bull / cow
        col.update(body="cow_black", head="cow_black", ear="cow_black", muzzle="hoof", tail="cow_black",
                   tuft="cow_black", leg="cow_black")
    elif variant == "cream":             # Charolais-like
        col.update(body="cow_cream", head="cow_cream", ear="cow_cream", muzzle="muzzle_pink", tail="cow_cream",
                   tuft="cow_cream", leg="cow_cream", fringe="wool")
    elif variant == "red":               # solid red-brown
        col.update(body="cow_brown", head="cow_brown", ear="cow_brown", muzzle="muzzle_pink", tail="cow_brown",
                   tuft="cow_brown_dark", leg="cow_brown", belly="cow_brown_dark")
    return quadruped(name, c, loc, d, col, cow_extras)


# ----------------------------------------------------------------------------------- sheep

def sheep_extras(parts, d, col, at):
    body = parts["body"][0]; hb = parts["head"][0]
    L, W, H, LEG = d["L"], d["W"], d["H"], d["leg"]
    top = LEG + H
    r = random.Random(d.get("seed", 1))
    # fleece: a grid of big puffs bulging out of the body box, light on top and darker below
    ny_, nz_ = 4, 2
    k = W / 0.62
    for iy in range(ny_):
        y = -L * 0.36 + L * 0.72 * iy / (ny_ - 1) + r.uniform(-0.03, 0.03) * k
        for sx in (-1, 1):
            for iz in range(nz_):
                z = LEG + H * (0.32 + 0.38 * iz) + r.uniform(-0.02, 0.02) * k
                body.box((sx * (W / 2 + 0.025 * k), y, z), (0.08 * k, 0.24 * k, 0.2 * k),
                         col["body"] if iz else col["wool_shade"], rot=(r.uniform(-20, 20), 0, 0))
        for sx in (-0.5, 0.5):
            body.box((sx * W * 0.5, y + 0.03, top + 0.06 * k), (0.26 * k, 0.24 * k, 0.1 * k), col["body"],
                     rot=(0, 0, r.uniform(-25, 25)))
    body.box((0, -L / 2 - 0.03 * k, LEG + H * 0.55), (W * 0.8, 0.08 * k, H * 0.65), col["wool_shade"])
    body.box((0, L / 2 + 0.03 * k, LEG + H * 0.5), (W * 0.75, 0.08 * k, H * 0.6), col["body"])
    # wool cap on the head
    hw, hl, hh = d["head"]
    tilt = d.get("head_tilt", -30)
    hb.box(at((0, -hl * 0.22, hh / 2 + 0.03)), (hw * 1.05, hl * 0.42, 0.08), col["body"], rot=(tilt, 0, 0))
    # legs: wool "trousers" at the top
    for k in ("leg_fl", "leg_fr", "leg_bl", "leg_br"):
        lb, piv = parts[k]
        lb.box((piv[0], piv[1], LEG - 0.02), (d["lt"] * 1.8, d["lt"] * 1.8, 0.14), col["wool_shade"])
    if d.get("horns"):                       # ram: curled horns at the sides of the head
        s = d["horns"]
        for sx in (-1, 1):
            ctr = Vector(at((sx * (hw / 2 + 0.04), -hl * 0.18, hh * 0.05)))
            pts = []
            for i in range(15):
                t = i / 14
                a = math.radians(100 - 330 * t)
                rr = s * (1 - 0.55 * t)
                pts.append(ctr + Vector((sx * 0.06 * t, rr * math.cos(a), rr * math.sin(a))))
            for i in range(14):
                seg(hb, pts[i], pts[i + 1] + (pts[i + 1] - pts[i]) * 0.2, 0.075 * (1 - 0.5 * i / 14) + 0.02, "horn")


def sheep(name, c, loc, kind, variant):
    if kind == "sheep":
        d = dict(L=1.05, W=0.62, H=0.56, leg=0.36, lt=0.075, head=(0.2, 0.3, 0.23), tail=0.16, tail_w=0.1,
                 ear=(0.12, 0.05, 25), neck_dir=(0.12, 0.2), neck_drop=0.1, puffs=12, seed=2)
    elif kind == "ram":
        d = dict(L=1.15, W=0.7, H=0.62, leg=0.38, lt=0.085, head=(0.24, 0.33, 0.26), tail=0.16, tail_w=0.1,
                 ear=(0.1, 0.05, 25), neck_dir=(0.13, 0.2), neck_drop=0.1, puffs=14, seed=4, horns=0.13)
    else:  # lamb
        d = dict(L=0.6, W=0.34, H=0.32, leg=0.32, lt=0.055, head=(0.15, 0.22, 0.17), tail=0.12, tail_w=0.07,
                 ear=(0.09, 0.04, 20), neck_dir=(0.08, 0.12), neck_drop=0.05, puffs=6, seed=5, leg_inset=0.04,
                 muzzle=(0.12, 0.07, 0.1))
    col = {"hoof": "hoof"}
    if variant == "white":
        col.update(body="wool", wool_shade="wool_shade", head="sheep_pink", ear="sheep_pink", muzzle="sheep_pink",
                   leg="sheep_pink", tail="wool")
    elif variant == "blackface":       # Suffolk-like: black head and legs
        col.update(body="wool", wool_shade="wool_shade", head="sheep_face", ear="sheep_face", muzzle="sheep_face",
                   leg="sheep_face", tail="wool")
    else:                               # brown wool
        col.update(body="wool_brown", wool_shade="wool_brown_shade", head="sheep_face", ear="sheep_face",
                   muzzle="sheep_face", leg="sheep_face", tail="wool_brown")
    d["head_tilt"] = -25
    return quadruped(name, c, loc, d, col, sheep_extras)


# ------------------------------------------------------------------------------------ goats

def goat_extras(parts, d, col, at):
    body = parts["body"][0]; hb = parts["head"][0]
    L, W, H, LEG = d["L"], d["W"], d["H"], d["leg"]
    hw, hl, hh = d["head"]
    tilt = d.get("head_tilt", -40)
    # beard under the chin
    b = d.get("beard", 0.08)
    hb.box(at((0, hl * 0.25, -hh / 2 - b / 2 + 0.02)), (0.05, 0.06, b), col.get("beard", col.get("head", col["body"])), rot=(tilt + 15, 0, 0))
    # horns swept back
    hs = d.get("horns", 0)
    if hs:
        for sx in (-1, 1):
            p0 = Vector(at((sx * hw * 0.25, -hl * 0.25, hh / 2)))
            pts = [p0]
            for i in range(1, 7):
                t = i / 6
                a = math.radians(70 + 110 * t)
                pts.append(p0 + Vector((sx * 0.04 * t, hs * 0.8 * (math.cos(a) - math.cos(math.radians(70))),
                                        hs * (math.sin(a) - math.sin(math.radians(70)) + 0.9 * t))))
            for i in range(6):
                seg(hb, pts[i], pts[i + 1] + (pts[i + 1] - pts[i]) * 0.15, 0.05 * (1 - 0.6 * i / 6) + 0.015, "horn")
    if d.get("stripe"):                     # dark stripe along the back
        body.box((0, 0, LEG + H + 0.05), (0.08, L * 0.92, 0.014), col["stripe"])
    if d.get("mane"):
        body.box((0, L * 0.18, LEG + H + 0.06), (W * 0.5, L * 0.5, 0.06), col.get("mane_col", col["body"]))
        body.box((0, L * 0.38, LEG + H * 0.35), (W * 0.9, 0.2, H * 0.6), col.get("mane_col", col["body"]))


def goat(name, c, loc, kind, variant):
    if kind == "goat":
        d = dict(L=0.98, W=0.42, H=0.46, leg=0.55, lt=0.075, head=(0.18, 0.34, 0.21), tail=0.14, tail_up=True,
                 ear=(0.13, 0.05, 30), neck_dir=(0.16, 0.24), neck_drop=0.08, neck_w=0.2, neck_h=0.24,
                 horns=0.12, beard=0.08, muzzle=(0.14, 0.1, 0.13))
    elif kind == "billy":
        d = dict(L=1.12, W=0.5, H=0.54, leg=0.6, lt=0.09, head=(0.22, 0.38, 0.24), tail=0.15, tail_up=True,
                 ear=(0.14, 0.05, 30), neck_dir=(0.18, 0.26), neck_drop=0.08, neck_w=0.26, neck_h=0.3,
                 horns=0.3, beard=0.2, mane=True, muzzle=(0.16, 0.11, 0.14))
    else:  # kid
        d = dict(L=0.55, W=0.26, H=0.28, leg=0.38, lt=0.05, head=(0.13, 0.22, 0.15), tail=0.08, tail_up=True,
                 ear=(0.09, 0.04, 30), neck_dir=(0.1, 0.14), neck_drop=0.04, neck_w=0.12, neck_h=0.14,
                 beard=0.0, leg_inset=0.04, muzzle=(0.1, 0.07, 0.09))
    d["head_tilt"] = -45
    col = {"hoof": "hoof"}
    if variant == "white":            # Saanen
        col.update(body="goat_white", head="goat_white", ear="goat_white", muzzle="muzzle_pink", leg="goat_white", tail="goat_white")
    elif variant == "brown":          # chamois: brown with a black stripe and black legs
        col.update(body="goat_brown", head="goat_brown", ear="goat_brown", muzzle="goat_black", leg="goat_black",
                   tail="goat_black", stripe="goat_black", beard="goat_black", mane_col="goat_brown_dark")
        d["stripe"] = True
        hw, hl, hh = d["head"]
        d["head_patches"] = [(sx * (hw / 2 + 0.004), 0.0, 0.0, 0.012, hl * 0.8, hh * 0.3) for sx in (-1, 1)]
        col["head_patch"] = "goat_black"
    else:                             # pied black / white
        col.update(body="goat_white", patch="goat_black", head="goat_black", ear="goat_black", muzzle="goat_black",
                   leg="goat_white", leg_f="goat_black", tail="goat_black", beard="goat_black", mane_col="goat_black")
        L, W, H, LEG = d["L"], d["W"], d["H"], d["leg"]
        d["patches"] = [("L", L * 0.15, LEG + H * 0.55, L * 0.45, H * 0.7), ("R", -L * 0.1, LEG + H * 0.5, L * 0.4, H * 0.6),
                        ("T", 0, L * 0.05, W * 0.8, L * 0.35)]
    return quadruped(name, c, loc, d, col, goat_extras)


# --------------------------------------------------------------------------------- chickens

def chicken(name, c, loc, kind, variant):
    if kind == "hen":
        s = dict(bw=0.22, bl=0.32, bh=0.22, z=0.16, head=0.11, leg=0.16, comb=0.05, tail=0.16)
    elif kind == "rooster":
        s = dict(bw=0.24, bl=0.34, bh=0.25, z=0.22, head=0.12, leg=0.22, comb=0.09, tail=0.34)
    else:
        s = dict(bw=0.1, bl=0.12, bh=0.1, z=0.06, head=0.075, leg=0.06, comb=0.0, tail=0.0)
    cols = {"brown": ("hen_brown", "hen_brown_dark", "hen_brown"), "white": ("hen_white", "wool_shade", "hen_white"),
            "black": ("hen_black", "tail_green", "hen_black"), "red": ("hen_brown", "hen_brown_dark", "hackle_orange"),
            "yellow": ("chick", "chick", "chick"), "brownchick": ("cow_tan", "hen_brown", "cow_tan")}[variant]
    main, wing, neck = cols
    bw, bl, bh, z = s["bw"], s["bl"], s["bh"], s["z"]
    parts = {}
    body = B()
    body.box((0, 0, z + bh / 2), (bw, bl, bh), main)
    body.box((0, bl * 0.35, z + bh * 0.62), (bw * 0.85, bl * 0.35, bh * 0.75), neck)        # breast
    if kind != "chick":
        for sx in (-1, 1):                    # wings
            body.box((sx * (bw / 2 + 0.01), -bl * 0.05, z + bh * 0.55), (0.025, bl * 0.62, bh * 0.55), wing, rot=(-10, 0, 0))
        # tail
        if kind == "hen":
            body.box((0, -bl / 2 - 0.02, z + bh + 0.04), (bw * 0.6, 0.08, s["tail"]), wing, rot=(-30, 0, 0))
        else:
            # arched sickle feathers: from the back of the body up and over to the rear
            base = Vector((0, -bl / 2 + 0.03, z + bh * 0.75))
            tc = "tail_green" if variant != "white" else "hen_white"
            for dx, h, lean in [(0.0, 1.0, 0.0), (-0.045, 0.85, 0.25), (0.045, 0.85, 0.25), (0.0, 0.7, 0.55)]:
                R = s["tail"] * h * 0.5
                ctr = base + Vector((dx, -R * 0.6, 0))
                pts = []
                for i in range(5):     # half circle up and over, ending low behind the bird
                    a = math.radians(20 + (150 + 30 * lean) * i / 4)
                    pts.append(ctr + Vector((0, R * 0.6 * math.cos(a) + 0.0, R * 1.3 * math.sin(a))))
                for i in range(4):
                    seg(body, pts[i], pts[i + 1] + (pts[i + 1] - pts[i]) * 0.2, 0.06 - 0.008 * i, tc, h=0.03)
            body.box((0, bl * 0.42, z + bh * 0.95), (bw * 0.75, 0.1, 0.14), "hackle_orange" if variant == "red" else neck)
    else:
        body.box((0, -bl / 2, z + bh * 0.7), (0.05, 0.03, 0.04), main)
    parts["body"] = (body, (0, 0, 0))
    hs = s["head"]
    hpiv = (0, bl * 0.42, z + bh * 0.85)
    hb = B()
    up = 1.4 if kind != "chick" else 0.7
    hc = Vector((0, bl * 0.45 + hs * 0.3, z + bh * 0.85 + hs * up))
    hb.box(tuple(hc - Vector((0, 0.02, hs * up * 0.6))), (hs * 0.75, hs * 0.8, hs * up), neck)     # neck
    hb.box(tuple(hc), (hs * 0.85, hs, hs), neck if kind == "chick" else main if variant != "red" else "hackle_orange")
    hb.box(tuple(hc + Vector((0, hs * 0.6, -hs * 0.05))), (hs * 0.3, hs * 0.4, hs * 0.22), "beak")
    for sx in (-1, 1):
        hb.box(tuple(hc + Vector((sx * hs * 0.43, hs * 0.15, hs * 0.15))), (0.01, 0.025, 0.025), "eye")
    if s["comb"]:
        cm = s["comb"]
        for i in range(3):
            hb.box(tuple(hc + Vector((0, hs * (0.25 - 0.22 * i), hs * 0.5 + cm * (0.5 - 0.15 * abs(i - 1))))),
                   (0.025, hs * 0.26, cm * (1.0 - 0.25 * abs(i - 1))), "comb_red")
        hb.box(tuple(hc + Vector((0, hs * 0.45, -hs * 0.45 - cm * 0.3))), (0.03, hs * 0.2, cm * 0.8), "comb_red")   # wattle
    parts["head"] = (hb, hpiv)
    for key, sx in (("leg_l", -1), ("leg_r", 1)):
        lb = B()
        piv = (sx * bw * 0.25, 0, z + 0.02)
        lt = 0.03 if kind != "chick" else 0.018
        lb.box((piv[0], 0, (z + 0.02) / 2), (lt, lt, z + 0.02), "beak")
        lb.box((piv[0], lt * 1.5, 0.008), (lt * 2.2, lt * 3.5, 0.016), "beak")
        parts[key] = (lb, piv)
    return rig(name, parts, c, loc)


# ------------------------------------------------------------------------------------- build

ANIMALS = [
    ("Cows", cattle, "cow", ["holstein", "pied", "brown"]),
    ("Bulls", cattle, "bull", ["black", "pied", "cream"]),
    ("Calves", cattle, "calf", ["holstein", "pied", "brown"]),
    ("Sheep", sheep, "sheep", ["white", "blackface", "brown"]),
    ("Rams", sheep, "ram", ["white", "blackface", "brown"]),
    ("Lambs", sheep, "lamb", ["white", "blackface", "brown"]),
    ("Goats", goat, "goat", ["white", "brown", "pied"]),
    ("Billy goats", goat, "billy", ["white", "brown", "pied"]),
    ("Kids", goat, "kid", ["white", "brown", "pied"]),
    ("Hens", chicken, "hen", ["brown", "white", "black"]),
    ("Roosters", chicken, "rooster", ["red", "white", "black"]),
    ("Chicks", chicken, "chick", ["yellow", "brownchick"]),
]


def build_all(do_export=True):
    c = P2['p2_coll']("P2_Animals")
    P2["clear_coll"](c)
    groups = []
    for row, (label, fn, kind, variants) in enumerate(ANIMALS):
        ents = []
        for i, v in enumerate(variants):
            name = f"animal_{kind}_{v}"
            ob = fn(name, c, (i * 3.0, -140 - row * 3.0, 0), kind, v)
            if do_export:
                export(ob)
            ents.append([name, v])
        groups.append(("Animals: " + label, ents))
    return groups
