# Phase 2 / 3 buildings in the Central European style of the barn and the dealer.
# Origin on the ground at the centre of the footprint, access side (front) towards +Y.
# 1 tile = 3 m. Colour variants are palette swaps; processing buildings get upgrade levels 2 / 3.
import bpy, math, random
from mathutils import Vector, Matrix

F = bpy.app.driver_namespace['farmio']; P2 = F['p2']
B = F['Builder']; export = P2['export']; recolor = P2['recolor']
tile_roof = F['tile_roof']; merge = F['merge']


def seg(b, p0, p1, w, color, h=None):
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    e = d.to_track_quat('Y', 'Z').to_euler()
    return b.box(tuple((p0 + p1) / 2), (w, d.length, h if h is not None else w), color,
                 rot=tuple(math.degrees(a) for a in e))


def tube(b, p0, p1, r, color, segs=8):
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    e = d.to_track_quat('Z', 'Y').to_euler()
    b.cyl(tuple((p0 + p1) / 2), r, d.length, color, segs=segs, rot=tuple(math.degrees(a) for a in e))


def roof(b, c, hx, d, wh, pitch=40, rot=0, ov=0.45, xov=0.35, gable="plaster", rows=None):
    """Gable roof with tile rows, ridge along X (rot 90: along Y), gable triangles in `gable`."""
    s = B()
    rz = tile_roof(s, hx, d, wh, pitch, OV=ov, XOV=xov, rows=rows or max(4, int(d * 1.6)))
    if gable:
        s.prism([(-d, wh - 0.01), (d, wh - 0.01), (0, rz - 0.05)], -hx, hx, gable, axis='X')
    merge(b, s, Matrix.Translation(Vector(c)) @ Matrix.Rotation(math.radians(rot), 4, 'Z'))
    return rz


def shed_roof(b, x0, x1, y0, y1, z0, z1, color="roof_tile", trim="timber_dark"):
    """Lean-to roof sloping from z1 at y1 down to z0 at y0."""
    L = math.hypot(y1 - y0, z1 - z0)
    ang = math.degrees(math.atan2(z1 - z0, y1 - y0))
    b.box(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2 + 0.08), (x1 - x0, L + 0.3, 0.14), color, rot=(ang, 0, 0))
    b.box(((x0 + x1) / 2, y0 - 0.12, z0 - 0.02), (x1 - x0, 0.1, 0.18), trim)


def walls(b, cx, cy, w, d, h, color, plinth="stone", ph=0.45):
    if plinth:
        b.box((cx, cy, ph / 2), (w + 0.12, d + 0.12, ph), plinth)
    b.box((cx, cy, ph + (h - ph) / 2), (w, d, h - ph), color)


def window(b, p, face, w=0.9, h=1.0, shutters="shutter_green", frame="trim_white"):
    """Window on a wall; face: 'N' (+Y), 'S' (-Y), 'E' (+X), 'W' (-X); p = point on the wall surface."""
    x, y, z = p
    if face in "NS":
        s = 1 if face == "N" else -1
        b.box((x, y + s * 0.03, z), (w + 0.16, 0.06, h + 0.16), frame)
        b.box((x, y + s * 0.06, z), (w, 0.04, h), "glass")
        b.box((x, y + s * 0.07, z), (0.05, 0.04, h), frame)
        b.box((x, y + s * 0.09, z - h / 2 - 0.08), (w + 0.25, 0.14, 0.06), frame)
        if shutters:
            for sx in (-1, 1):
                b.box((x + sx * (w / 2 + 0.2), y + s * 0.05, z), (0.36, 0.05, h + 0.1), shutters)
    else:
        s = 1 if face == "E" else -1
        b.box((x + s * 0.03, y, z), (0.06, w + 0.16, h + 0.16), frame)
        b.box((x + s * 0.06, y, z), (0.04, w, h), "glass")
        b.box((x + s * 0.07, y, z), (0.04, 0.05, h), frame)
        b.box((x + s * 0.09, y, z - h / 2 - 0.08), (0.14, w + 0.25, 0.06), frame)
        if shutters:
            for sy in (-1, 1):
                b.box((x + s * 0.05, y + sy * (w / 2 + 0.2), z), (0.05, 0.36, h + 0.1), shutters)


def door(b, p, face, w=1.2, h=2.2, color="timber", frame="timber_dark", double=False):
    x, y, z0 = p
    if face in "NS":
        s = 1 if face == "N" else -1
        b.box((x, y + s * 0.03, z0 + h / 2), (w + 0.2, 0.06, h + 0.1), frame)
        b.box((x, y + s * 0.06, z0 + h / 2 - 0.02), (w, 0.05, h - 0.06), color)
        for i in range(1, 4 if not double else 6):
            b.box((x - w / 2 + i * w / (4 if not double else 6), y + s * 0.09, z0 + h / 2), (0.03, 0.02, h - 0.1), frame)
        if double:
            seg(b, (x - w / 2, y + s * 0.1, z0 + 0.1), (x, y + s * 0.1, z0 + h - 0.1), 0.08, frame, h=0.03)
            seg(b, (x + w / 2, y + s * 0.1, z0 + 0.1), (x, y + s * 0.1, z0 + h - 0.1), 0.08, frame, h=0.03)
    else:
        s = 1 if face == "E" else -1
        b.box((x + s * 0.03, y, z0 + h / 2), (0.06, w + 0.2, h + 0.1), frame)
        b.box((x + s * 0.06, y, z0 + h / 2 - 0.02), (0.05, w, h - 0.06), color)


def sack_stack(b, x, y, z, n=3, color="sack"):
    for i in range(n):
        b.box((x + (i % 2) * 0.05, y, z + 0.13 + i * 0.24), (0.62, 0.42, 0.24), color if i % 2 == 0 else "sack_shade",
              rot=(0, 0, (i % 2) * 8))


def crate(b, x, y, z, s=0.5, color="wood_light"):
    b.box((x, y, z + s / 2), (s, s, s), color)
    for zz in (z + 0.08, z + s - 0.08):
        b.box((x, y, zz), (s + 0.02, s + 0.02, 0.05), "wood")


def lamp(b, x, y, z, face="N"):
    s = 1 if face == "N" else -1
    b.box((x, y + s * 0.15, z), (0.05, 0.3, 0.05), "black")
    b.box((x, y + s * 0.3, z - 0.1), (0.16, 0.16, 0.16), "headlight")


def log_pile(b, cx, cy, n_x=3, n_z=3, L=2.6, r=0.18, axis="X", color="bark", end="wood_light"):
    for zi in range(n_z):
        for xi in range(n_x - zi):
            off = (xi - (n_x - zi - 1) / 2) * r * 2.05
            z = r + zi * r * 1.75
            if axis == "X":
                b.cyl((cx, cy + off, z), r, L, color, segs=7, rot=(0, 90, 0))
                for s in (-1, 1):
                    b.cyl((cx + s * L / 2, cy + off, z), r * 0.85, 0.02, end, segs=7, rot=(0, 90, 0))
            else:
                b.cyl((cx + off, cy, z), r, L, color, segs=7, rot=(90, 0, 0))
                for s in (-1, 1):
                    b.cyl((cx + off, cy + s * L / 2, z), r * 0.85, 0.02, end, segs=7, rot=(90, 0, 0))


def plank_stack(b, cx, cy, layers=5, L=2.8, w=1.1):
    """Stack of planks lying along Y on spacer sticks."""
    for i in range(layers):
        z = 0.1 + i * 0.1
        for y in (-L * 0.35, L * 0.35):
            b.box((cx, cy + y, z - 0.045), (w, 0.06, 0.02), "wood_dark")
        for k in range(4):
            b.box((cx + (k - 1.5) * w / 4, cy, z), (w / 4 - 0.02, L, 0.07), "wood_light" if (i + k) % 3 else "wood")


# ------------------------------------------------------------------------------- buildings

def hand_mill():
    """2x2: small timber mill hut with a porch where the quern is turned by hand."""
    b = B()
    walls(b, 0, -0.6, 4.2, 3.4, 2.6, "timber")
    for i in range(-7, 8):                                         # board-and-batten
        b.box((i * 0.28, 1.13, 1.55), (0.05, 0.03, 2.1), "timber_dark")
        b.box((i * 0.28, -2.33, 1.55), (0.05, 0.03, 2.1), "timber_dark")
    rz = roof(b, (0, -0.6, 0), 2.1, 1.7, 2.6, pitch=42, gable="timber", xov=0.3)
    door(b, (-0.9, 1.1, 0.45), "N", w=1.0, h=1.9)
    window(b, (1.0, 1.1, 1.6), "N", w=0.7, h=0.7)
    window(b, (2.1, -0.6, 1.6), "E", w=0.7, h=0.7)
    # porch with the quern stones
    b.box((0.5, 1.95, 0.08), (3.2, 1.7, 0.16), "stone")
    for x in (-1.0, 2.0):
        b.box((x, 2.65, 1.3), (0.16, 0.16, 2.3), "timber_dark")
    shed_roof(b, -1.2, 2.2, 2.85, 1.15, 2.3, 2.75)
    b.cyl((0.7, 2.0, 0.55), 0.55, 0.5, "stone_dark", segs=10)       # base
    b.cyl((0.7, 2.0, 0.92), 0.5, 0.22, "stone", segs=10)            # runner stone
    b.box((0.7 + 0.32, 2.0, 1.23), (0.06, 0.06, 0.42), "wood")      # crank handle
    b.cyl((0.7, 2.0, 1.06), 0.08, 0.06, "wood_dark", segs=6)
    sack_stack(b, -0.5, 2.1, 0.16, 3)
    sack_stack(b, 1.8, 1.7, 0.16, 2, "sack")
    return b


def sawmill():
    """3x2: open-sided timber shed over a saw bench, logs on the left, planks on the right."""
    b = B()
    W, D = 5.4, 3.6
    b.box((0, 0, 0.06), (W + 0.4, D + 0.4, 0.12), "stone")
    for x in (-W / 2, 0, W / 2):
        for y in (-D / 2, D / 2):
            b.box((x, y, 1.75), (0.22, 0.22, 3.3), "timber_dark")
    b.box((0, -D / 2, 1.6), (W, 0.12, 3.0), "timber")                   # back wall
    for i in range(-9, 10):
        b.box((i * 0.29, -D / 2 - 0.07, 1.6), (0.05, 0.03, 2.9), "timber_dark")
    for x in (-W / 2, W / 2):
        for s in (-1, 1):
            seg(b, (x, s * (D / 2 - 0.7), 3.35), (x, s * D / 2, 2.7), 0.12, "timber_dark")
    rz = roof(b, (0, 0, 0), W / 2, D / 2, 3.4, pitch=30, gable="timber", xov=0.45, ov=0.6)
    # saw bench with a circular blade and a log on the carriage
    b.box((0, 0.2, 0.5), (3.4, 0.7, 0.75), "wood")
    b.box((0, 0.2, 0.9), (3.6, 0.8, 0.06), "wood_dark")
    b.cyl((0.6, 0.2, 1.0), 0.48, 0.03, "metal", segs=14, rot=(90, 0, 90))
    b.box((0.6, 0.2, 0.6), (0.5, 0.5, 0.3), "metal_dark")
    b.cyl((-0.7, 0.2, 1.15), 0.24, 2.2, "bark", segs=7, rot=(0, 90, 0))
    b.cyl((-1.8, 0.2, 1.15), 0.21, 0.02, "wood_light", segs=7, rot=(0, 90, 0))
    b.box((1.6, -1.0, 0.7), (0.9, 0.7, 1.2), "veh_green")             # motor
    b.box((1.6, -1.0, 1.32), (0.95, 0.75, 0.06), "metal_dark")
    seg(b, (1.6, -0.66, 0.9), (0.6, 0.15, 0.6), 0.06, "black")         # belt
    log_pile(b, -3.65, 0.0, 4, 3, L=2.6, axis="Y")
    plank_stack(b, 3.75, 0.0, 6, L=2.6, w=1.2)
    b.box((0, D / 2 + 0.35, 2.6), (1.6, 0.06, 0.45), "sign_wood")      # sign board
    return b


def water_mill():
    """3x3 on a river bank: the mill house stands on the two land columns of the footprint, the
    east column (x 1.5..4.5) lies on the river. An undershot wheel turns in the current: its lower
    part is below ground level (the river bed is lower than the land)."""
    b = B()
    hx = -1.6                                                          # house centre (land side)
    walls(b, hx, -0.2, 5.4, 5.4, 4.6, "plaster")
    b.box((hx, -0.2, 0.45 + 1.0), (5.42, 5.42, 2.0), "stone")          # stone ground floor
    for x in (hx - 2.6, hx + 2.6):
        for y in (-2.8, 2.4):
            b.box((x, y, 2.3), (0.2, 0.2, 4.6), "stone_dark")
    roof(b, (hx, -0.2, 0), 2.7, 2.7, 4.6, pitch=45, gable="plaster", xov=0.4)
    door(b, (hx - 0.9, 2.52, 0.45), "N", w=1.5, h=2.3, double=True)
    window(b, (hx + 1.3, 2.52, 1.6), "N", w=0.8, h=0.9)
    window(b, (hx - 0.9, 2.52, 3.6), "N", w=0.8, h=0.8)
    window(b, (hx + 1.3, 2.52, 3.6), "N", w=0.8, h=0.8)
    window(b, (hx - 2.7, -0.2, 3.3), "W", w=0.8, h=0.8)
    # stone quay along the river edge, down into the river bed
    b.box((1.38, 0, -0.5), (0.36, 9.0, 1.6), "stone_dark")
    b.box((1.38, 0, 0.32), (0.44, 9.0, 0.08), "stone")
    # undershot wheel in the river, axle through the wall and a stone pier in the water
    wx, wy, wz, wr = 2.75, -0.2, 0.75, 1.85
    for i in range(16):                                                # paddles
        a = math.radians(i * 360 / 16)
        b.box((wx, wy + math.cos(a) * wr * 0.93, wz + math.sin(a) * wr * 0.93), (0.8, 0.5, 0.06), "wood",
              rot=(i * 360 / 16 + 90, 0, 0))
    for s in (-0.36, 0.36):
        for i in range(16):                                            # open rims: ring of segments
            a0, a1 = math.radians(i * 22.5), math.radians((i + 1) * 22.5)
            seg(b, (wx + s, wy + math.cos(a0) * wr, wz + math.sin(a0) * wr), (wx + s, wy + math.cos(a1) * wr, wz + math.sin(a1) * wr),
                0.08, "wood_dark", h=0.12)
        for i in range(4):                                             # spokes
            a = math.radians(i * 45)
            seg(b, (wx + s, wy - math.cos(a) * wr, wz - math.sin(a) * wr), (wx + s, wy + math.cos(a) * wr, wz + math.sin(a) * wr),
                0.1, "wood_dark")
    tube(b, (hx + 2.7, wy, wz), (3.75, wy, wz), 0.14, "metal_dark")
    b.box((3.75, wy, -0.25), (0.5, 0.9, 2.1), "stone")                 # pier
    b.box((3.75, wy, 0.86), (0.6, 1.0, 0.14), "stone_dark")
    b.box((2.75, wy, 2.75), (1.3, 4.3, 0.1), "wood", rot=(0, 8, 0))   # small roof over the wheel
    for y in (wy - 2.0, wy + 2.0):
        b.box((3.35, y, 0.75), (0.14, 0.14, 3.9), "timber_dark")      # posts stand in the river bed
    sack_stack(b, hx + 1.3, 3.3, 0, 3)
    return b


def bakery():
    """3x3: plastered town bakery: shop front with an awning, brick oven and chimney at the back."""
    b = B()
    walls(b, 0, 0.2, 7.2, 5.2, 4.4, "plaster_warm")
    rz = roof(b, (0, 0.2, 0), 3.6, 2.6, 4.4, pitch=45, gable="plaster_warm")
    b.box((0, 2.81, 2.55), (7.2, 0.04, 0.12), "plaster_shade")
    # shop front: door + 2 big windows, striped awning
    door(b, (0, 2.8, 0.45), "N", w=1.2, h=2.3, color="shutter_green")
    for x in (-2.2, 2.2):
        b.box((x, 2.84, 1.55), (1.9, 0.06, 1.5), "trim_white")
        b.box((x, 2.88, 1.55), (1.7, 0.04, 1.3), "glass")
        for i in range(3):                                            # bread on the display shelves
            b.box((x - 0.5 + i * 0.5, 2.92, 1.1), (0.36, 0.12, 0.16), "bread")
    for i in range(10):
        b.box((-3.2 + i * 0.71, 3.35, 2.75), (0.71, 1.1, 0.06), "barn_red" if i % 2 else "trim_white", rot=(-25, 0, 0))
    b.box((0, 2.9, 3.35), (2.4, 0.08, 0.55), "sign_wood")             # sign with a loaf
    b.ico((0, 2.96, 3.35), 0.22, "bread", sub=1, s=(1.6, 0.4, 0.8))
    for x in (-2.2, 2.2):
        window(b, (x, 2.8, 3.9), "N", w=0.8, h=0.8)
    window(b, (3.6, 0.2, 2.0), "E", w=0.8, h=1.0)
    # brick oven annex and chimney at the back
    b.box((-1.6, -3.0, 1.3), (3.0, 1.6, 2.6), "brick")
    b.box((-1.6, -3.0, 2.68), (3.2, 1.8, 0.16), "brick_dark")
    b.box((-2.4, -3.0, 4.6), (0.75, 0.75, 4.0), "brick")
    b.box((-2.4, -3.0, 6.65), (0.9, 0.9, 0.12), "brick_dark")
    log_pile(b, 1.6, -3.0, 3, 2, L=1.6, r=0.14, axis="X")
    b.box((3.0, 3.2, 0.45), (0.9, 0.5, 0.9), "wood")                  # bench
    return b


def sugar_mill():
    """3x3: brick factory with a tall chimney, beet bunker in front, conveyor into the building."""
    b = B()
    walls(b, 0, -1.0, 7.4, 4.6, 5.2, "brick", plinth="stone_dark")
    for x in (-2.6, -0.9, 0.9, 2.6):
        b.box((x, 1.33, 2.6), (0.9, 0.08, 1.8), "trim_white")
        b.box((x, 1.36, 2.6), (0.75, 0.04, 1.65), "glass")
        b.box((x, 1.36, 3.55), (0.95, 0.08, 0.2), "brick_dark")
    b.box((0, -1.0, 5.25), (7.6, 4.8, 0.14), "brick_dark")
    rz = roof(b, (0, -1.0, 5.2), 3.75, 2.35, 0.0, pitch=22, gable=None, xov=0.2, ov=0.3)
    b.prism([(-2.3, 5.2), (2.3, 5.2), (0, 5.2 + 2.3 * math.tan(math.radians(22)) - 0.05)], -3.7, 3.7, "brick", axis='X')
    # chimney
    b.cyl((3.0, -2.6, 6.0), 0.65, 12.0, "brick", segs=8, r2=0.45)
    b.cyl((3.0, -2.6, 12.0), 0.55, 0.3, "brick_dark", segs=8)
    for z in (4, 7, 10):
        b.cyl((3.0, -2.6, z), 0.62 - z * 0.017, 0.12, "brick_dark", segs=8)
    # beet bunker (low walls) with beets, conveyor up into the wall
    b.box((-2.2, 3.0, 0.4), (3.2, 2.4, 0.8), "concrete")
    b.box((-2.2, 3.0, 0.65), (2.9, 2.1, 0.4), "concrete_dark")
    r = random.Random(3)
    for i in range(26):
        b.ico((-2.2 + r.uniform(-1.3, 1.3), 3.0 + r.uniform(-0.9, 0.9), 0.9 + r.uniform(0, 0.15)), 0.17, "trim_white", sub=1, s=(1, 1, 1.3))
    seg(b, (-2.2, 2.4, 0.9), (-2.2, 1.35, 3.6), 0.6, "metal_dark", h=0.2)
    for z in (1.4, 2.4):
        b.box((-2.2, 2.3 - (z - 0.9) * 0.4, z * 0.9), (0.08, 0.08, z * 0.9), "metal_dark")
    door(b, (1.8, 1.32, 0.45), "N", w=2.2, h=2.8, color="veh_grey", frame="brick_dark")
    b.box((1.8, 1.4, 3.6), (2.6, 0.06, 0.5), "trim_white")              # sign
    for i in range(3):
        b.box((0.9 + i * 0.6, 1.44, 3.6), (0.35, 0.03, 0.25), "sugar")
    # sugar sacks on a pallet
    b.box((3.0, 2.5, 0.08), (1.2, 1.0, 0.14), "pallet")
    sack_stack(b, 3.0, 2.5, 0.15, 3, "sugar")
    return b


def pasta_maker():
    """2x2: small plastered workshop with pasta drying racks under an awning."""
    b = B()
    walls(b, 0, -0.8, 5.0, 3.6, 3.2, "plaster")
    rz = roof(b, (0, -0.8, 0), 2.5, 1.8, 3.2, pitch=38, gable="plaster")
    b.box((0, 1.01, 2.0), (5.0, 0.04, 0.1), "plaster_shade")
    door(b, (-1.2, 1.0, 0.45), "N", w=1.0, h=2.1, color="shutter_green")
    window(b, (0.9, 1.0, 1.6), "N", w=1.1, h=0.9)
    window(b, (2.5, -0.8, 1.7), "E", w=0.8, h=0.8)
    # awning + racks with hanging pasta
    for x in (-2.2, 2.2):
        b.box((x, 2.45, 1.2), (0.12, 0.12, 2.4), "wood")
    for i in range(7):
        b.box((-2.1 + i * 0.7, 1.75, 2.42), (0.7, 1.6, 0.05), "trim_white" if i % 2 else "veh_green", rot=(-12, 0, 0))
    for y in (1.6, 2.2):
        b.box((0.4, y, 1.75), (3.4, 0.05, 0.05), "wood_dark")
        for x in (-1.25, 2.05):
            b.box((x, y, 0.88), (0.05, 0.05, 1.75), "wood_dark")
        for i in range(14):
            b.box((-1.1 + i * 0.23, y, 1.38), (0.12, 0.03, 0.72), "pasta")
    b.box((0, 1.05, 2.75), (1.8, 0.06, 0.4), "sign_wood")
    crate(b, -1.9, 1.7, 0, 0.5, "wood_light")
    return b


def silo(level=1):
    """2x2 corrugated grain silo. L2 taller with a ladder cage; L3 tallest with a bucket elevator."""
    b = B()
    r = 2.4 if level < 3 else 2.6
    h = {1: 6.0, 2: 9.0, 3: 12.0}[level]
    b.cyl((0, 0, 0.15), r + 0.3, 0.3, "concrete", segs=16)
    b.cyl((0, 0, 0.3 + h / 2), r, h, "metal", segs=16)
    for i in range(int(h / 0.75)):
        b.cyl((0, 0, 0.6 + i * 0.75), r + 0.02, 0.05, "metal_dark", segs=16)
    b.cyl((0, 0, 0.3 + h + 0.7), r + 0.12, 1.4, "metal", segs=16, r2=0.5)
    b.cyl((0, 0, 0.3 + h + 1.55), 0.45, 0.4, "metal_dark", segs=8)
    b.box((0, r - 0.05, 0.9), (0.9, 0.2, 1.2), "metal_dark")             # unload hatch at the front
    b.box((0.0, r + 0.2, 0.7), (0.4, 0.5, 0.4), "metal_dark")
    # ladder up the side
    lx = -r * 0.72
    ly = r * 0.72
    for s in (-0.2, 0.2):
        b.box((lx - 0.08 + s * 0.7, ly + 0.08 + s * 0.7, 0.3 + h / 2 + 0.5), (0.05, 0.05, h + 1.0), "metal_dark", rot=(0, 0, 45))
    for i in range(int(h / 0.4)):
        b.box((lx - 0.08, ly + 0.08, 0.6 + i * 0.4), (0.04, 0.4, 0.04), "metal_dark", rot=(0, 0, 45))
    if level >= 2:
        # safety cage: open hoops around the ladder (only the rim, open towards the silo) + bars
        cx, cy, cr = lx - 0.08 - 0.3, ly + 0.08 + 0.3, 0.38
        angles = [math.radians(135 - 110 + 220 * k / 8) for k in range(9)]
        hoops = [2.8 + i * 0.6 for i in range(int((h - 2.5) / 0.6))]
        for z in hoops:
            for a0, a1 in zip(angles, angles[1:]):
                seg(b, (cx + cr * math.cos(a0), cy + cr * math.sin(a0), z), (cx + cr * math.cos(a1), cy + cr * math.sin(a1), z),
                    0.04, "metal_dark")
        for a in angles[1::2]:
            seg(b, (cx + cr * math.cos(a), cy + cr * math.sin(a), hoops[0]), (cx + cr * math.cos(a), cy + cr * math.sin(a), hoops[-1]),
                0.035, "metal_dark")
        b.cyl((0, 0, 0.3 + h + 0.02), r + 0.25, 0.06, "metal_dark", segs=16)   # walkway ring
    if level >= 3:
        # bucket elevator tower and spout over the roof
        tx, ty = r + 0.25, -r + 0.6
        b.box((tx, ty, (h + 4.0) / 2), (0.55, 0.55, h + 4.0), "veh_grey")
        b.box((tx, ty, h + 4.2), (0.9, 0.9, 0.6), "veh_grey")
        tube(b, (tx - 0.2, ty, h + 3.9), (0.3, 0.0, h + 1.9), 0.13, "metal_dark")
        b.box((tx, ty + 0.6, 0.6), (1.0, 0.8, 1.0), "concrete_dark")          # intake pit
        for i in range(int((h + 3) / 1.5)):
            b.box((tx, ty, 1.0 + i * 1.5), (0.6, 0.6, 0.06), "metal_dark")
    return b


def supply_storage(kind="timber"):
    """2x2 small store with a roller door and a blank sign board above it (label slot, see docs)."""
    b = B()
    if kind == "timber":
        walls(b, 0, -0.3, 4.6, 4.4, 3.0, "timber")
        for i in range(-8, 9):
            b.box((i * 0.27, 1.93, 1.72), (0.05, 0.03, 2.5), "timber_dark")
        roof(b, (0, -0.3, 0), 2.3, 2.2, 3.0, pitch=35, gable="timber", rot=90)
    else:
        walls(b, 0, -0.3, 4.6, 4.4, 3.2, "steel_blue", plinth="concrete", ph=0.2)
        for i in range(-8, 9):
            b.box((i * 0.27, 1.93, 1.7), (0.08, 0.04, 3.0), "veh_grey")
        b.box((0, -0.3, 3.25), (4.9, 4.7, 0.16), "veh_grey")
    b.box((0, 1.95, 1.25), (2.4, 0.06, 2.3), "metal_dark")
    for i in range(10):
        b.box((0, 1.99, 0.25 + i * 0.22), (2.3, 0.03, 0.04), "metal")      # roller door slats
    b.box((0, 2.0, 2.65), (2.6, 0.12, 0.3), "metal_dark")
    b.box((0, 2.02, 3.25 if kind == "timber" else 2.95), (1.8, 0.06, 0.62), "sign_wood")   # label board
    b.box((0, 2.0, 3.25 if kind == "timber" else 2.95), (1.92, 0.04, 0.72), "timber_dark")
    lamp(b, 1.6, 1.95, 2.7)
    b.box((0, 2.6, 0.05), (2.6, 1.2, 0.1), "concrete")                     # apron
    return b


def industrial_mill():
    """3x3: tall concrete flour mill with two silos and an elevator tower."""
    b = B()
    walls(b, -1.2, 0.8, 5.2, 5.4, 9.0, "concrete_light", plinth="concrete_dark", ph=0.6)
    for z in (3.0, 6.0):
        b.box((-1.2, 0.8, z), (5.25, 5.45, 0.15), "concrete_dark")
    for fz in (1.6, 4.5, 7.5):
        for x in (-2.8, -1.2, 0.4):
            b.box((x, 3.53, fz), (1.0, 0.06, 1.3), "veh_grey")
            b.box((x, 3.56, fz), (0.9, 0.04, 1.2), "glass")
    b.box((-1.2, 0.8, 9.08), (5.4, 5.6, 0.16), "concrete_dark")
    b.box((-2.4, -0.4, 9.9), (1.6, 1.6, 1.6), "concrete_light")             # roof head house
    door(b, (-1.2, 3.52, 0.6), "N", w=2.6, h=3.0, color="veh_grey", frame="concrete_dark")
    b.box((-1.2, 3.58, 3.6), (3.4, 0.06, 0.5), "veh_blue")                  # sign stripe
    # two silos on the right
    for y in (2.0, -1.4):
        b.cyl((2.75, y, 0.3), 1.6, 0.6, "concrete_dark", segs=14)
        b.cyl((2.75, y, 6.3), 1.5, 11.4, "concrete", segs=14)
        b.cyl((2.75, y, 12.1), 1.55, 0.2, "concrete_dark", segs=14)
    b.box((2.75, 0.3, 12.5), (0.8, 4.4, 0.6), "veh_grey")                   # conveyor gallery
    b.box((0.9, 0.3, 11.2), (1.4, 0.8, 0.6), "veh_grey")
    # dust filter + pipe
    b.cyl((-3.6, -2.4, 10.4), 0.45, 2.0, "metal", segs=10)
    tube(b, (-3.6, -2.4, 9.3), (-3.6, -1.6, 9.3), 0.12, "metal_dark")
    # loading spout over a truck bay at the front right
    b.box((2.4, 3.6, 4.2), (1.6, 1.2, 0.3), "concrete_dark")
    tube(b, (2.4, 3.6, 4.0), (2.4, 3.6, 2.8), 0.18, "metal_dark")
    b.box((2.4, 3.6, 0.03), (2.4, 2.2, 0.06), "concrete")
    return b


def storage_barn(level):
    """4x3 Storage Barn upgrades. L2: stone ground floor, hay loft hatch with a hoist beam, lean-to.
    L3: big brick barn with two gates, roof vents and a covered loading dock."""
    b = B()
    if level == 2:
        walls(b, 0, -0.2, 10.0, 7.4, 2.6, "stone", plinth="stone_dark")
        b.box((0, -0.2, 2.6 + 1.6), (10.0, 7.4, 3.2), "timber")
        for i in range(-17, 18):
            b.box((i * 0.29, 3.52, 4.2), (0.05, 0.04, 3.1), "timber_dark")
            b.box((i * 0.29, -3.92, 4.2), (0.05, 0.04, 3.1), "timber_dark")
        roof(b, (0, -0.2, 0), 5.0, 3.7, 5.8, pitch=42, gable="timber", xov=0.5)
        door(b, (-1.6, 3.5, 0.45), "N", w=3.2, h=2.1, double=True)
        door(b, (2.4, 3.5, 0.45), "N", w=1.0, h=2.0)
        b.box((1.0, 3.55, 4.4), (1.6, 0.08, 1.6), "timber_dark")             # loft hatch
        b.box((1.0, 3.6, 4.4), (1.4, 0.05, 1.4), "timber")
        b.box((1.0, 4.4, 6.0), (0.2, 1.8, 0.2), "timber_dark")               # hoist beam
        seg(b, (1.0, 5.2, 5.95), (1.0, 5.2, 4.3), 0.02, "black")
        b.box((1.0, 5.2, 4.25), (0.12, 0.12, 0.12), "metal_dark")
        for x in (-3.8, 3.8):
            window(b, (x, 3.5, 1.5), "N", w=0.8, h=0.7, shutters=None)
        # lean-to on the east gable with stacked crates
        b.box((5.6, -0.2, 0.06), (1.2, 7.0, 0.12), "stone")
        for y in (-3.5, 3.1):
            b.box((5.95, y, 1.3), (0.16, 0.16, 2.5), "timber_dark")
        b.box((5.65, -0.2, 2.62), (1.5, 7.4, 0.12), "roof_tile", rot=(0, -14, 0))
        for i, y in enumerate((-2.6, -1.6, -0.6)):
            crate(b, 5.6, y, 0.12, 0.6)
        sack_stack(b, 5.6, 1.0, 0.12, 3)
    else:
        walls(b, 0, -0.4, 11.0, 7.0, 6.0, "brick", plinth="concrete_dark", ph=0.5)
        for x in (-5.5, -1.8, 1.8, 5.5):
            b.box((x, 3.12, 3.0), (0.4, 0.12, 6.0), "brick_dark")
        roof(b, (0, -0.4, 0), 5.5, 3.5, 6.0, pitch=35, gable="brick", xov=0.5)
        for x in (-3.65, 0.0, 3.65):                                          # roof vents on the ridge
            b.box((x, -0.4, 6.0 + 3.5 * math.tan(math.radians(35)) + 0.55), (0.9, 0.9, 0.7), "metal")
            b.box((x, -0.4, 6.0 + 3.5 * math.tan(math.radians(35)) + 0.95), (1.1, 1.1, 0.1), "metal_dark")
        for x in (-3.65, 3.65):
            door(b, (x, 3.1, 0.5), "N", w=3.0, h=3.6, color="veh_grey", frame="brick_dark")
            for i in range(12):
                b.box((x, 3.2, 0.7 + i * 0.28), (2.9, 0.03, 0.04), "metal")
        window(b, (0.0, 3.1, 2.0), "N", w=1.2, h=1.0, shutters=None)
        for x in (-3.6, 0, 3.6):
            window(b, (x, 3.1, 4.8), "N", w=1.4, h=0.7, shutters=None)
            lamp(b, x, 3.1, 4.2)
        # covered loading dock along the front
        b.box((0, 3.7, 0.5), (11.0, 1.0, 1.0), "concrete")
        b.box((0, 4.21, 0.5), (11.0, 0.06, 0.9), "concrete_dark")
        for x in (-5.2, 0, 5.2):
            b.box((x, 4.1, 3.0), (0.14, 0.14, 4.0), "metal_dark")
        b.box((0, 3.75, 4.95), (11.4, 1.5, 0.12), "metal", rot=(-8, 0, 0))
        for x in (-4.5, -2.8, 2.8, 4.5):
            b.box((x, 4.26, 0.55), (0.35, 0.12, 0.45), "black")                # bumpers
    return b


def loading_bay(kind="concrete"):
    """Pull-off platform added to a building's access point: 2x1 tiles (6 x 3 m)."""
    b = B()
    base = {"concrete": "concrete", "gravel": "gravel", "asphalt": "asphalt"}[kind]
    b.box((0, 0, 0.04), (6.0, 3.0, 0.08), base)
    b.box((0, -1.35, 0.25), (6.0, 0.3, 0.5), "concrete_dark" if kind != "gravel" else "stone")   # dock edge
    for x in (-2.0, 2.0):
        b.box((x, -1.18, 0.35), (0.4, 0.1, 0.35), "black")                   # bumpers
    paint = "sign_yellow"
    for x in (-2.95, 2.95):
        b.box((x, 0.1, 0.085), (0.12, 2.8, 0.01), paint)
    for i in range(6):                                                         # hatched loading area
        b.box((-2.2 + i * 0.9, 0.2, 0.085), (0.12, 1.6, 0.01), paint, rot=(0, 0, 35))
    b.box((0, 1.3, 0.085), (5.9, 0.12, 0.01), paint)
    for x in (-3.15, 3.15):
        b.box((x, -1.2, 0.6), (0.12, 0.12, 1.2), "sign_yellow")              # bollards
        b.box((x, -1.2, 1.0), (0.13, 0.13, 0.15), "black")
    b.box((2.6, -1.3, 1.6), (0.08, 0.08, 3.2), "metal_dark")                 # lamp post
    lamp(b, 2.6, -1.3, 3.15)
    return b


# ------------------------------------------------------------------------------ animal buildings

def cowshed():
    """4x3 dairy barn: long low stable with an open feeding alley, hay loft and a milk room."""
    b = B()
    walls(b, 0, -0.8, 11.0, 6.0, 3.0, "plaster", ph=0.6)
    roof(b, (0, -0.8, 0), 5.5, 3.0, 3.0, pitch=35, gable="timber", xov=0.55, ov=0.9)
    for x in (-4.0, -1.5, 1.0, 3.5):
        window(b, (x, 2.2, 2.0), "N", w=0.9, h=0.6, shutters=None)
    door(b, (-5.0, 2.2, 0.6), "N", w=1.2, h=2.2, double=True)
    door(b, (5.0, 2.2, 0.6), "N", w=1.2, h=2.2, double=True)
    for x in (-2.2, 2.2):                                                    # roof vents
        b.box((x, -0.8, 3.0 + 3.0 * math.tan(math.radians(35)) + 0.3), (0.7, 0.7, 0.6), "timber")
        b.box((x, -0.8, 3.0 + 3.0 * math.tan(math.radians(35)) + 0.65), (0.9, 0.9, 0.1), "roof_tile_dark")
    # feed fence along the front with a trough
    b.box((0, 3.4, 0.35), (9.0, 0.7, 0.4), "concrete")
    b.box((0, 3.4, 0.5), (8.8, 0.5, 0.15), "hay")
    for i in range(16):
        b.box((-4.4 + i * 0.58, 3.0, 0.9), (0.05, 0.05, 1.1), "metal")
    b.box((0, 3.0, 1.45), (9.0, 0.06, 0.06), "metal")
    b.box((0, 3.0, 0.4), (9.0, 0.06, 0.06), "metal")
    # milk room at the east end with milk cans
    for i in range(3):
        b.cyl((4.2 + i * 0.4, 3.5, 0.32), 0.17, 0.64, "milk", segs=8)
        b.cyl((4.2 + i * 0.4, 3.5, 0.7), 0.1, 0.12, "metal", segs=8)
    return b


def small_stock_shed():
    """3x2 shed for sheep and goats: open-front timber shelter with a fenced yard."""
    b = B()
    W = 8.0
    b.box((0, -1.4, 1.35), (W, 0.12, 2.7), "timber")
    for x in (-W / 2, W / 2):
        b.box((x, -0.4, 1.35), (0.12, 2.0, 2.7), "timber")
    for i in range(-13, 14):
        b.box((i * 0.29, -1.48, 1.35), (0.05, 0.03, 2.6), "timber_dark")
    for x in (-W / 2, -1.3, 1.3, W / 2):
        b.box((x, 0.6, 1.1), (0.16, 0.16, 2.2), "timber_dark")
    shed_roof(b, -W / 2 - 0.3, W / 2 + 0.3, 0.9, -1.6, 2.2, 2.85)
    b.box((0, -0.4, 0.04), (W, 2.0, 0.06), "straw")                           # bedding
    # yard fence in front
    for x in [(-W / 2) + i * 0.8 for i in range(11)]:
        b.box((x, 2.75, 0.55), (0.1, 0.1, 1.1), "wood")
    for z in (0.45, 0.9):
        b.box((0, 2.75, z), (W, 0.06, 0.12), "wood_light")
    for y in (0.9, 1.8):
        for x in (-W / 2, W / 2):
            b.box((x, y, 0.55), (0.1, 0.1, 1.1), "wood")
    for x in (-W / 2, W / 2):
        for z in (0.45, 0.9):
            b.box((x, 1.8, z), (0.06, 1.9, 0.12), "wood_light")
    b.box((2.2, 1.6, 0.28), (1.6, 0.45, 0.3), "wood")                         # hay rack + trough
    b.box((2.2, 1.6, 0.4), (1.5, 0.35, 0.1), "hay")
    b.cyl((-2.6, 1.7, 0.25), 0.35, 0.5, "metal", segs=10)
    b.cyl((-2.6, 1.7, 0.48), 0.3, 0.05, "water", segs=10)
    return b


def chicken_coop():
    """2x2 hen house on short legs with a ramp, nest boxes and a wire run."""
    b = B()
    b.box((0, -1.2, 0.35), (3.2, 2.4, 0.08), "timber_dark")
    for x in (-1.5, 1.5):
        for y in (-2.3, -0.1):
            b.box((x, y, 0.2), (0.14, 0.14, 0.45), "timber_dark")
    b.box((0, -1.2, 1.35), (3.0, 2.2, 1.9), "barn_red")
    for i in range(-5, 6):
        b.box((i * 0.27, -0.08, 1.35), (0.04, 0.03, 1.85), "barn_red_dark")
    roof(b, (0, -1.2, 0), 1.5, 1.1, 2.3, pitch=38, gable="barn_red", xov=0.25, ov=0.3)
    b.box((1.9, -1.2, 1.0), (0.8, 1.6, 0.6), "barn_red")                     # nest boxes
    b.box((1.9, -1.2, 1.35), (0.95, 1.75, 0.08), "roof_tile_dark", rot=(0, -15, 0))
    b.box((-0.6, -0.06, 0.75), (0.45, 0.05, 0.5), "black")                   # pop hole
    seg(b, (-0.6, 0.0, 0.5), (-0.6, 1.0, 0.0), 0.45, "wood", h=0.05)         # ramp
    door(b, (0.7, -0.08, 0.4), "N", w=0.7, h=1.4, color="trim_white", frame="barn_red_dark")
    # wire run
    for x in (-1.6, 0, 1.6):
        for y in (0.05, 2.7):
            b.box((x, y, 0.7), (0.08, 0.08, 1.4), "wood")
    for (p0, p1) in [((-1.6, 2.7), (1.6, 2.7)), ((-1.6, 0.05), (-1.6, 2.7)), ((1.6, 0.05), (1.6, 2.7))]:
        cx, cy = (p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2
        b.box((cx, cy, 1.38), (abs(p1[0] - p0[0]) + 0.06, abs(p1[1] - p0[1]) + 0.06, 0.06), "wood_light")
        b.box((cx, cy, 0.08), (abs(p1[0] - p0[0]) + 0.06, abs(p1[1] - p0[1]) + 0.06, 0.06), "wood_light")
        n = int(max(abs(p1[0] - p0[0]), abs(p1[1] - p0[1])) / 0.2)
        for i in range(n + 1):                                                # wire mesh as thin bars
            t = i / n
            b.box((p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t, 0.72), (0.015, 0.015, 1.3), "metal")
    b.box((0, 1.4, 0.03), (3.2, 2.6, 0.04), "soil_light")
    b.cyl((0.9, 1.9, 0.12), 0.25, 0.18, "metal", segs=8)                     # feeder
    return b


def tree_farm_tile():
    """1 tile of a tree farm: nursery soil with a mulch ring for the tree in the middle."""
    b = B()
    b.box((0, 0, 0.02), (3.0, 3.0, 0.04), "soil")
    for y in (-1.0, 0, 1.0):
        b.box((0, y, 0.045), (2.9, 0.35, 0.02), "soil_dark")
    b.cyl((0, 0, 0.05), 0.6, 0.03, "wood_dark", segs=10)
    return b


def orchard_tile():
    """1 tile of an orchard: mown grass with a mulched strip along the row and a stake."""
    b = B()
    b.box((0, 0, 0.02), (3.0, 3.0, 0.04), "grass_dark")
    b.box((0, 0, 0.045), (1.0, 3.0, 0.02), "soil_dark")
    b.box((0.3, 0, 0.8), (0.06, 0.06, 1.6), "wood_light")
    return b


def tool_shed():
    """1x1 shed used by the tree farm / orchard (tools, saplings)."""
    b = B()
    walls(b, 0, -0.2, 2.4, 2.0, 2.2, "timber", ph=0.25)
    for i in range(-4, 5):
        b.box((i * 0.27, 0.82, 1.2), (0.05, 0.03, 1.9), "timber_dark")
    shed_roof(b, -1.4, 1.4, 1.15, -1.45, 2.2, 2.6)
    door(b, (-0.3, 0.8, 0.25), "N", w=0.9, h=1.8)
    b.box((0.8, 1.1, 0.25), (0.5, 0.5, 0.5), "wood_light")
    return b


# --------------------------------------------------------------------------- upgrade levels

def upgrade(b, level, hx, hy, side=1):
    """Level visuals added to a processing building: L2 a lean-to with crates and a lamp,
    L3 also a small grain bin, solar panels on the main roof edge and a better sign."""
    if level < 2:
        return
    x0 = side * (hx + 0.1)
    x1 = side * (hx + 1.5)
    xa, xb = min(x0, x1), max(x0, x1)
    b.box(((xa + xb) / 2, -hy * 0.3, 0.06), (abs(x1 - x0), hy * 1.1, 0.12), "concrete")
    for y in (-hy * 0.8, hy * 0.2):
        b.box((x1, y, 1.2), (0.14, 0.14, 2.4), "timber_dark")
    b.box(((xa + xb) / 2, -hy * 0.3, 2.45), (abs(x1 - x0) + 0.3, hy * 1.2, 0.1), "metal", rot=(0, side * 12, 0))
    crate(b, (x0 + x1) / 2, -hy * 0.6, 0.12, 0.55)
    crate(b, (x0 + x1) / 2, -hy * 0.6, 0.67, 0.5, "wood")
    sack_stack(b, (x0 + x1) / 2, 0.0 * hy, 0.12, 2)
    if level >= 3:
        bx = (x0 + x1) / 2
        by = -hy - 0.9
        b.cyl((bx, by, 1.6), 0.75, 2.6, "metal", segs=12)
        b.cyl((bx, by, 3.2), 0.8, 0.6, "metal", segs=12, r2=0.15)
        for z in (0.8, 1.6, 2.4):
            b.cyl((bx, by, z), 0.77, 0.04, "metal_dark", segs=12)
        b.box((x1, hy * 0.2, 2.0), (0.6, 0.06, 0.4), "solar")


PROCESSING = [
    # name, builder, half extents (x, y) of the main body for upgrade props, side for the lean-to
    ("building_hand_mill", hand_mill, (2.1, 1.7), 1),
    ("building_sawmill", sawmill, (2.7, 1.8), -1),
    ("building_water_mill", water_mill, (4.4, 2.7), -1),
    ("building_bakery", bakery, (3.6, 2.6), 1),
    ("building_sugar_mill", sugar_mill, (3.7, 2.3), -1),
    ("building_pasta_maker", pasta_maker, (2.5, 1.8), -1),
    ("building_industrial_mill", industrial_mill, (3.8, 2.7), -1),
]

PLASTER_SWAP = {"plaster": "plaster_warm", "plaster_warm": "plaster", "roof_tile": "roof", "roof_tile_dark": "roof_dark",
                "shutter_green": "barn_red_dark"}
TIMBER_SWAP = {"timber": "wood", "timber_dark": "wood_dark", "roof_tile": "roof", "roof_tile_dark": "roof_dark"}
BRICK_SWAP = {"brick": "plaster", "brick_dark": "plaster_shade", "roof_tile": "roof", "roof_tile_dark": "roof_dark"}
CONCRETE_SWAP = {"concrete_light": "plaster_warm", "veh_blue": "veh_red", "veh_grey": "steel_blue"}


def build_all(do_export=True):
    c = P2['p2_coll']("P2_Buildings")
    P2['clear_coll'](c)
    groups = {}
    row = [0]

    def put(group, name, b, label, x):
        ob = b.build(name, c, loc=(x, -420 - row[0] * 18.0, 0))
        if do_export:
            export(ob)
        groups.setdefault(group, []).append([name, label])
        return ob

    def variant(group, src, name, swap, label, x):
        ob = recolor(src, name, swap, c, (x, src.location.y, 0))
        if do_export:
            export(ob)
        groups.setdefault(group, []).append([name, label])

    swaps = {"building_hand_mill": TIMBER_SWAP, "building_sawmill": TIMBER_SWAP, "building_water_mill": PLASTER_SWAP,
             "building_bakery": PLASTER_SWAP, "building_sugar_mill": BRICK_SWAP, "building_pasta_maker": PLASTER_SWAP,
             "building_industrial_mill": CONCRETE_SWAP}
    for name, fn, (hx, hy), side in PROCESSING:
        group = "Buildings: " + name.replace("building_", "").replace("_", " ").title()
        src = put(group, name, fn(), "level 1", 0)
        for lv in (2, 3):
            b = fn()
            upgrade(b, lv, hx, hy, side)
            put(group, f"{name}_l{lv}", b, f"level {lv}", 16.0 * (lv - 1))
        variant(group, src, f"{name}_b", swaps[name], "colour variant", 48.0)
        row[0] += 1
    g = "Buildings: Silo"
    for lv in (1, 2, 3):
        put(g, f"building_silo" + ("" if lv == 1 else f"_l{lv}"), silo(lv), f"level {lv}", 12.0 * (lv - 1))
    row[0] += 1
    g = "Buildings: Supply Storage"
    s = put(g, "building_supply_storage", supply_storage("timber"), "timber", 0)
    put(g, "building_supply_storage_metal", supply_storage("metal"), "metal", 12.0)
    variant(g, s, "building_supply_storage_b", TIMBER_SWAP, "colour variant", 24.0)
    row[0] += 1
    g = "Buildings: Storage Barn levels"
    for lv in (2, 3):
        src = put(g, f"building_storage_barn_l{lv}", storage_barn(lv), f"level {lv}", 16.0 * (lv - 2))
    row[0] += 1
    g = "Buildings: Loading bay"
    for i, k in enumerate(("concrete", "gravel", "asphalt")):
        put(g, f"building_loading_bay" + ("" if k == "concrete" else f"_{k}"), loading_bay(k), k, 9.0 * i)
    row[0] += 1
    g = "Buildings: Animals"
    cs = put(g, "building_cowshed", cowshed(), "cowshed (dairy barn)", 0)
    variant(g, cs, "building_cowshed_b", {"plaster": "plaster_warm", "roof_tile": "roof", "roof_tile_dark": "roof_dark"}, "cowshed variant", 16.0)
    ss = put(g, "building_stock_shed", small_stock_shed(), "sheep / goat shed", 32.0)
    variant(g, ss, "building_stock_shed_b", TIMBER_SWAP, "shed variant", 44.0)
    cc = put(g, "building_chicken_coop", chicken_coop(), "chicken coop", 56.0)
    variant(g, cc, "building_chicken_coop_b", {"barn_red": "shutter_green", "barn_red_dark": "leaf_dark"}, "coop variant", 64.0)
    row[0] += 1
    g = "Buildings: Tree farm and orchard"
    put(g, "tile_tree_farm", tree_farm_tile(), "tree farm tile", 0)
    put(g, "tile_orchard", orchard_tile(), "orchard tile", 5.0)
    put(g, "building_tool_shed", tool_shed(), "tool shed", 10.0)
    return groups
