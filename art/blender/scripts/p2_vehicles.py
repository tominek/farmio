# Vehicles, trailers and tractor attachments. Front = +Y.
# Self-propelled (tractors, combines, pickups): origin on the ground at the centre of the body.
# Towed / mounted (trailers, grain cart, attachments): origin on the ground under the hitch point,
# the implement extends towards -Y. Colour variants are palette swaps of one base model.
import bpy, math, random
from mathutils import Vector

F = bpy.app.driver_namespace['farmio']; P2 = F['p2']
B = F['Builder']; export = P2['export']; recolor = P2['recolor']


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


def wheel(b, x, y, r, w, rim="veh_yellow", lugs=0, segs=14, rim_k=0.6):
    """Wheel with its axle along X; x is the centre of the tyre."""
    b.cyl((x, y, r), r, w, "tire", segs=segs, rot=(0, 90, 0))
    b.cyl((x, y, r), r * rim_k, w + 0.02, rim, segs=segs, rot=(0, 90, 0))
    b.cyl((x, y, r), r * 0.18, w + 0.08, "metal_dark", segs=6, rot=(0, 90, 0))
    for i in range(lugs):                       # tread lugs (chevrons alternate sides)
        a = math.radians(i * 360 / lugs)
        for s in (-1, 1):
            p = (x + s * w * 0.25, y + math.cos(a) * r, r + math.sin(a) * r)
            b.box(p, (w * 0.48, 0.07 * r / 0.7, 0.05 * r / 0.7), "tire", rot=(math.degrees(a) + 90 + s * 12, 0, 0))


def light(b, p, color="headlight", s=(0.16, 0.04, 0.1)):
    b.box(p, s, color)


# ----------------------------------------------------------------------------------- tractors

def tractor_basic():
    """Small classic tractor (2-wheel drive), hood in front, open-frame cab. Hitch (0, -1.5, 0.5)."""
    b = B()
    M, D, R = "veh_green", "veh_green_dark", "veh_yellow"
    # chassis + engine block
    b.box((0, 0.6, 0.62), (0.5, 2.8, 0.3), "metal_dark")
    b.box((0, -0.85, 0.75), (0.75, 0.9, 0.5), "metal_dark")           # gearbox / rear axle housing
    b.box((0, 1.0, 1.08), (0.72, 1.85, 0.58), M)                       # hood
    b.box((0, 1.0, 1.39), (0.6, 1.8, 0.06), D)                         # hood top stripe
    b.box((0, 1.94, 1.0), (0.66, 0.08, 0.66), "metal_dark")            # grille
    for x in (-0.18, 0.18):
        light(b, (x, 1.99, 1.22))
    for x in (-0.38, 0.38):                                            # side vents
        b.box((x, 1.2, 1.1), (0.02, 0.7, 0.2), D)
    tube(b, (0.22, 1.45, 1.35), (0.22, 1.45, 2.05), 0.045, "metal_dark")          # exhaust
    b.cyl((0.22, 1.45, 2.08), 0.06, 0.06, "black", segs=6)
    # front axle + wheels
    b.box((0, 1.35, 0.42), (1.2, 0.14, 0.12), "metal_dark")
    for sx in (-1, 1):
        wheel(b, sx * 0.66, 1.35, 0.4, 0.22, R, lugs=0, segs=12)
    # rear wheels + fenders
    for sx in (-1, 1):
        wheel(b, sx * 0.78, -0.75, 0.72, 0.4, R, lugs=12)
        b.box((sx * 0.8, -0.75, 1.52), (0.48, 0.9, 0.05), M)
        # fender ends slope down and away from the wheel
        b.box((sx * 0.8, -0.2, 1.33), (0.48, 0.05, 0.42), M, rot=(30, 0, 0))
        b.box((sx * 0.8, -1.3, 1.33), (0.48, 0.05, 0.42), M, rot=(-30, 0, 0))
        b.box((sx * 0.56, -0.75, 1.22), (0.03, 0.9, 0.62), M)
    # operator platform, seat, steering
    b.box((0, -0.65, 1.12), (1.05, 1.1, 0.06), "metal_dark")
    b.box((0, -0.9, 1.4), (0.42, 0.38, 0.1), "seat")
    b.box((0, -1.08, 1.62), (0.42, 0.08, 0.4), "seat")
    tube(b, (0, 0.2, 1.38), (0, -0.15, 1.75), 0.03, "black")
    b.cyl((0, -0.17, 1.77), 0.17, 0.04, "black", segs=8, rot=(-60, 0, 0))
    # cab: four posts, roof, front and back glass
    for x in (-0.52, 0.52):
        for y in (0.08, -1.18):
            b.box((x, y, 1.82), (0.06, 0.06, 1.35), D)
    b.box((0, -0.55, 2.52), (1.2, 1.45, 0.08), M)
    b.box((0, -0.55, 2.58), (1.05, 1.25, 0.06), D)
    b.box((0, 0.09, 1.86), (1.0, 0.03, 1.2), "glass")
    b.box((0, -1.19, 2.0), (1.0, 0.03, 0.9), "glass")
    for x in (-0.48, 0.48):
        light(b, (x, -0.05, 2.45), "headlight", (0.12, 0.04, 0.08))
        light(b, (x, -1.25, 2.45), "taillight", (0.1, 0.04, 0.06))
    # three-point linkage + drawbar at the back
    for sx in (-1, 1):
        seg(b, (sx * 0.3, -1.1, 0.55), (sx * 0.38, -1.55, 0.5), 0.06, "metal_dark")
    seg(b, (0, -1.15, 1.0), (0, -1.5, 0.85), 0.06, "metal_dark")
    b.box((0, -1.45, 0.5), (0.2, 0.25, 0.06), "metal_dark")
    return b


def tractor_advanced():
    """Large modern 4WD tractor with a glass cab, front weights. Hitch (0, -2.35, 0.6)."""
    b = B()
    M, D, R = "veh_green", "veh_green_dark", "veh_yellow"
    b.box((0, 0.5, 0.95), (0.85, 4.2, 0.45), "metal_dark")             # frame
    b.box((0, -1.2, 1.15), (1.1, 1.3, 0.8), "metal_dark")              # transmission
    # hood with a sloping nose
    b.box((0, 1.55, 1.55), (1.0, 2.3, 0.9), M)
    b.prism([(-0.5, 1.1), (0.5, 1.1), (0.5, 1.75), (0.38, 2.0), (-0.38, 2.0), (-0.5, 1.75)], 0.4, 2.75, M)
    b.box((0, 2.73, 1.45), (0.86, 0.06, 0.62), "metal_dark")           # grille
    for x in (-0.3, 0.3):
        light(b, (x, 2.77, 1.82), "headlight", (0.24, 0.04, 0.1))
    for sx in (-1, 1):
        b.box((sx * 0.51, 1.7, 1.55), (0.02, 1.6, 0.1), D)            # stripe
    b.box((0, 3.15, 1.0), (1.0, 0.7, 0.55), "metal_dark")              # front weight block
    for i in range(5):
        b.box((0, 3.52, 0.82 + i * 0.1), (0.95, 0.04, 0.04), "veh_grey")
    tube(b, (0.38, 0.55, 1.9), (0.38, 0.55, 3.05), 0.07, "metal_dark")             # exhaust
    # wheels: big rear, large front with fenders
    for sx in (-1, 1):
        wheel(b, sx * 1.02, 1.85, 0.7, 0.48, R, lugs=10)
        b.box((sx * 1.02, 1.85, 1.5), (0.55, 1.1, 0.05), M, rot=(0, sx * 10, 0))
        wheel(b, sx * 1.05, -1.1, 0.98, 0.62, R, lugs=14)
        b.box((sx * 1.05, -1.1, 2.06), (0.7, 1.4, 0.06), M)
        b.box((sx * 1.05, -0.32, 1.76), (0.7, 0.06, 0.7), M, rot=(30, 0, 0))
        b.box((sx * 1.05, -1.88, 1.82), (0.7, 0.06, 0.55), M, rot=(-30, 0, 0))
        b.box((sx * 0.78, -0.45, 1.12), (0.25, 0.12, 0.6), "metal_dark")      # steps
    # cab: glass box with dark posts and a coloured roof
    cy, cz = -0.75, 2.55
    b.box((0, cy, 1.72), (1.55, 1.75, 0.12), "metal_dark")
    b.box((0, cy, cz), (1.5, 1.7, 1.5), "glass")
    for x in (-0.76, 0.76):
        for y in (cy + 0.86, cy - 0.86):
            b.box((x, y, cz), (0.07, 0.07, 1.52), "black")
    b.box((0, cy, cz + 0.8), (1.68, 1.95, 0.14), M)
    b.box((0, cy - 0.05, cz + 0.9), (1.4, 1.5, 0.08), "veh_white")
    for x in (-0.55, -0.2, 0.2, 0.55):
        light(b, (x, cy + 0.98, cz + 0.8), "headlight", (0.14, 0.04, 0.07))
    b.box((0.6, cy, cz + 1.02), (0.12, 0.12, 0.08), "orange")          # beacon
    for sx in (-1, 1):
        b.box((sx * 0.92, cy + 0.75, cz + 0.2), (0.25, 0.03, 0.2), "black")      # mirrors
    # rear linkage, PTO, drawbar
    for sx in (-1, 1):
        seg(b, (sx * 0.35, -1.75, 0.65), (sx * 0.45, -2.35, 0.6), 0.08, "metal_dark")
    seg(b, (0, -1.8, 1.35), (0, -2.3, 1.05), 0.08, "metal_dark")
    b.box((0, -2.2, 0.6), (0.24, 0.3, 0.08), "metal_dark")
    for x in (-0.6, 0.6):
        light(b, (x, -1.88, 1.6), "taillight", (0.12, 0.04, 0.08))
    return b


# ----------------------------------------------------------------------------------- combines

def combine(k=1.0, header_w=4.5):
    """Self-propelled combine harvester with grain tank, cab and a wide header in front."""
    b = B()
    M, D, R = "veh_green", "veh_green_dark", "veh_yellow"
    L0, L1 = -3.0 * k, 1.5 * k                 # body extent along Y
    hw = 1.25 * k
    b.box((0, (L0 + L1) / 2, 0.75 * k + 1.0 * k), (2 * hw, L1 - L0, 2.0 * k), M)
    b.box((0, (L0 + L1) / 2, 0.68 * k), (1.6 * k, L1 - L0 - 0.6, 0.3 * k), "metal_dark")
    for sx in (-1, 1):                          # side panels / vents
        b.box((sx * (hw + 0.01), -0.6 * k, 1.9 * k), (0.02, 2.6 * k, 0.9 * k), D)
        for i in range(5):
            b.box((sx * (hw + 0.025), -1.7 * k + i * 0.5 * k, 2.1 * k), (0.02, 0.32 * k, 0.05), "metal_dark")
    # grain tank on top with sloped sides
    tz = 2.75 * k
    b.prism([(-hw * 0.95, tz), (hw * 0.95, tz), (hw * 1.12, tz + 0.75 * k), (-hw * 1.12, tz + 0.75 * k)],
            -1.6 * k, 0.9 * k, M)
    b.box((0, -0.35 * k, tz + 0.78 * k), (2.1 * hw, 2.4 * k, 0.06), "metal_dark")      # tank rim
    b.box((0, -0.35 * k, tz + 0.78 * k + 0.035), (1.9 * hw, 2.2 * k, 0.02), "wheat_gold")     # grain inside
    # engine bay + exhaust at the rear top
    b.box((0, -2.4 * k, tz + 0.25 * k), (1.6 * k, 0.9 * k, 0.5 * k), D)
    tube(b, (0.5 * k, -2.5 * k, tz + 0.4 * k), (0.5 * k, -2.5 * k, tz + 1.1 * k), 0.08 * k, "metal_dark")
    # straw chopper at the back
    b.box((0, L0 - 0.25 * k, 1.1 * k), (1.8 * k, 0.5 * k, 0.6 * k), "metal_dark")
    b.box((0, L0 - 0.5 * k, 0.95 * k), (1.9 * k, 0.05, 0.4 * k), D, rot=(25, 0, 0))
    # cab at the front top
    cy, cz = 1.85 * k, 3.0 * k
    b.box((0, cy - 0.2 * k, 2.15 * k), (1.7 * k, 1.2 * k, 0.12), "metal_dark")
    b.box((0, cy, cz), (1.6 * k, 1.25 * k, 1.5 * k), "glass")
    for x in (-0.8 * k, 0.8 * k):
        for y in (cy + 0.62 * k, cy - 0.62 * k):
            b.box((x, y, cz), (0.07, 0.07, 1.52 * k), "black")
    b.box((0, cy, cz + 0.8 * k), (1.8 * k, 1.45 * k, 0.14), "veh_white")
    for x in (-0.6, -0.2, 0.2, 0.6):
        light(b, (x * k, cy + 0.74 * k, cz + 0.8 * k), "headlight", (0.16, 0.04, 0.07))
    b.box((0.5 * k, cy - 0.3 * k, cz + 0.92 * k), (0.12, 0.12, 0.08), "orange")
    # ladder
    for i in range(6):
        b.box((-hw - 0.15, 1.2 * k, 0.5 + i * 0.32 * k), (0.25, 0.08, 0.04), "metal_dark")
    seg(b, (-hw - 0.27, 1.2 * k, 0.4), (-hw - 0.27, 1.2 * k, 2.2 * k), 0.04, "metal_dark")
    # unloading auger folded along the left side
    tube(b, (-hw - 0.05, -1.8 * k, tz + 0.3 * k), (-hw - 0.2, 1.2 * k, tz + 0.55 * k), 0.13 * k, M)
    tube(b, (-hw - 0.2, 1.2 * k, tz + 0.55 * k), (-hw - 0.2, 1.35 * k, tz + 0.45 * k), 0.1 * k, "metal_dark")
    # wheels: big drive wheels in front, small steering wheels at the back
    for sx in (-1, 1):
        wheel(b, sx * (hw + 0.22 * k), 0.9 * k, 0.85 * k, 0.6 * k, R, lugs=12)
        b.box((sx * (hw + 0.22 * k), 0.9 * k, 1.78 * k), (0.66 * k, 1.5 * k, 0.06), M)
        wheel(b, sx * (hw - 0.1 * k), -2.45 * k, 0.5 * k, 0.38 * k, R, lugs=8)
    # feeder house down to the header
    seg(b, (0, 1.4 * k, 1.75 * k), (0, 2.75 * k, 0.75 * k), 1.2 * k, D, h=0.8 * k)
    # header: floor, back wall, side shields, auger, reel
    H = header_w / 2
    hy = 3.1 * k
    b.box((0, hy + 0.35 * k, 0.2), (header_w, 0.9 * k, 0.08), "metal_dark")          # floor + cutter bar
    b.box((0, hy - 0.05 * k, 0.6 * k), (header_w, 0.1, 0.85 * k), M)                  # back wall
    for sx in (-1, 1):
        b.prism([(hy - 0.1, 0.15), (hy + 0.85 * k, 0.15), (hy + 0.85 * k, 0.4), (hy, 1.05 * k)], sx * H - 0.04, sx * H + 0.04, M, axis='X')
    for i in range(int(header_w / 0.3)):                                              # knife guards
        b.box((-H + 0.15 + i * 0.3, hy + 0.85 * k, 0.2), (0.05, 0.16, 0.04), "metal")
    tube(b, (-H + 0.1, hy + 0.2 * k, 0.45), (H - 0.1, hy + 0.2 * k, 0.45), 0.2 * k, "metal_dark")
    ry, rz, rr = hy + 0.55 * k, 1.25 * k, 0.5 * k
    tube(b, (-H + 0.15, ry, rz), (H - 0.15, ry, rz), 0.06, "metal_dark")
    for i in range(6):                                                                # reel bats
        a = math.radians(i * 60)
        tube(b, (-H + 0.15, ry + math.cos(a) * rr, rz + math.sin(a) * rr), (H - 0.15, ry + math.cos(a) * rr, rz + math.sin(a) * rr),
             0.035, "metal")
    for sx in (-1, 0, 1):
        for i in range(3):
            a = math.radians(i * 120)
            seg(b, (sx * (H - 0.2), ry, rz), (sx * (H - 0.2), ry + math.cos(a) * rr, rz + math.sin(a) * rr), 0.04, "metal_dark")
        seg(b, (sx * (H - 0.2), ry, rz), (sx * (H - 0.2) * 0.98, hy - 0.05, 1.4 * k), 0.06, M)       # reel arms
    for x in (-0.9 * k, 0.9 * k):
        light(b, (x, L0 - 0.02, 2.4 * k), "taillight", (0.12, 0.04, 0.1))
    return b


# ----------------------------------------------------------------------------------- pickups

def pickup_heavy():
    """Heavy-duty pickup: crew cab, long bed, dual rear wheels, body colour car_blue like the light pickup."""
    b = B()
    M, D = "car_blue", "car_blue_dark"
    b.box((0, 0.0, 0.62), (1.6, 5.6, 0.25), "metal_dark")                 # frame
    # front: hood + grille
    b.box((0, 2.05, 1.05), (2.1, 1.5, 0.75), M)
    b.box((0, 2.82, 1.0), (1.9, 0.06, 0.6), "metal")                      # chrome grille
    for i in range(4):
        b.box((0, 2.86, 0.8 + i * 0.13), (1.6, 0.03, 0.04), "metal_dark")
    for x in (-0.82, 0.82):
        light(b, (x, 2.83, 1.2), "headlight", (0.3, 0.05, 0.16))
    b.box((0, 2.86, 0.6), (2.1, 0.12, 0.2), "metal_dark")                 # bumper
    # crew cab
    b.box((0, 0.35, 1.25), (2.1, 1.9, 1.15), M)
    b.prism([(-1.0, 1.82), (1.0, 1.82), (0.95, 2.35), (-0.95, 2.35)], -0.55, 0.85, M)
    b.box((0, 0.35, 2.38), (1.92, 1.5, 0.06), M)
    b.prism([(-0.97, 1.82), (0.97, 1.82), (0.9, 2.33), (-0.9, 2.33)], 0.85, 1.32, M)  # windscreen frame
    b.box((0, 1.12, 2.08), (1.82, 0.36, 0.48), "glass", rot=(-35, 0, 0))
    for sx in (-1, 1):
        b.box((sx * 1.06, 0.72, 2.07), (0.03, 0.75, 0.42), "glass")
        b.box((sx * 1.06, -0.15, 2.07), (0.03, 0.7, 0.42), "glass")
        b.box((sx * 1.07, 0.3, 1.35), (0.02, 0.03, 0.9), D)               # door gaps
        b.box((sx * 1.07, 1.2, 1.35), (0.02, 0.03, 0.9), D)
        b.box((sx * 1.13, 1.3, 1.85), (0.12, 0.05, 0.22), "black")       # mirrors
        b.box((sx * 1.09, 0.35, 0.72), (0.08, 1.8, 0.08), "metal_dark")   # step bars
    b.box((0, -0.6, 2.05), (1.8, 0.03, 0.45), "glass")
    # bed with dual rear wheels (wide fenders)
    b.box((0, -1.95, 0.85), (2.25, 2.6, 0.12), "metal_dark")
    for sx in (-1, 1):
        b.box((sx * 1.08, -1.95, 1.2), (0.1, 2.6, 0.62), M)
        b.box((sx * 1.18, -1.95, 1.12), (0.12, 1.2, 0.5), M)
    b.box((0, -0.67, 1.2), (2.25, 0.08, 0.62), M)
    b.box((0, -3.24, 1.2), (2.25, 0.08, 0.62), M)                         # tailgate
    for x in (-0.95, 0.95):
        light(b, (x, -3.29, 1.3), "taillight", (0.12, 0.04, 0.3))
    b.box((0, -3.32, 0.6), (2.1, 0.12, 0.18), "metal_dark")
    b.box((0, -3.5, 0.55), (0.1, 0.3, 0.08), "metal_dark")               # hitch
    for sx in (-1, 1):
        wheel(b, sx * 0.88, 1.95, 0.42, 0.3, "metal", segs=12)
        b.box((sx * 0.95, 1.95, 0.95), (0.3, 1.0, 0.1), M)
        wheel(b, sx * 0.86, -2.0, 0.42, 0.26, "metal", segs=12)
        wheel(b, sx * 1.14, -2.0, 0.42, 0.26, "metal", segs=12)
    return b


# ----------------------------------------------------------------------------------- trailers

def trailer(length, width, side_h, deck, axles, r, tipper=False):
    """Farm trailer; origin under the drawbar eye, body behind it (-Y)."""
    b = B()
    M, D = "veh_red", "veh_red_dark"
    y0 = -1.2                                   # front of the body
    y1 = y0 - length
    yc = (y0 + y1) / 2
    seg(b, (0, 0, deck - 0.45), (0, y0 - 0.3, deck - 0.2), 0.1, "metal_dark")       # drawbar
    for sx in (-1, 1):
        seg(b, (sx * 0.05, -0.2, deck - 0.43), (sx * 0.5, y0 - 0.2, deck - 0.2), 0.08, "metal_dark")
    b.box((0, 0.0, deck - 0.45), (0.12, 0.12, 0.06), "metal_dark")
    b.box((0, -0.5, deck - 0.6), (0.06, 0.06, 0.35), "metal_dark")                 # jack stand
    b.box((0, yc, deck - 0.2), (width * 0.6, length - 0.2, 0.2), "metal_dark")      # chassis
    b.box((0, yc, deck - 0.05), (width, length, 0.1), D)                            # deck
    for sx in (-1, 1):
        b.box((sx * (width / 2 - 0.03), yc, deck + side_h / 2), (0.06, length, side_h), M)
        for i in range(int(length / 1.0) + 1):                                      # side stakes
            b.box((sx * (width / 2 + 0.01), y0 - 0.05 - i * (length - 0.1) / int(length / 1.0), deck + side_h / 2),
                  (0.04, 0.07, side_h + 0.02), D)
        b.box((sx * (width / 2 + 0.01), yc, deck + side_h - 0.02), (0.05, length, 0.06), D)
    for y in (y0 - 0.03, y1 + 0.03):
        b.box((0, y, deck + side_h / 2), (width, 0.06, side_h), M)
    if side_h > 0.8:
        b.box((0, y0 - 0.03, deck + side_h + 0.3), (width, 0.05, 0.6), "metal_dark")   # front mesh extension
        for x in range(5):
            b.box((-width / 2 + 0.2 + x * (width - 0.4) / 4, y0 - 0.03, deck + side_h + 0.3), (0.04, 0.07, 0.6), "metal_dark")
    # axles
    spacing = r * 2.2
    ya = yc - length * 0.08
    for i in range(axles):
        y = ya + (i - (axles - 1) / 2) * spacing
        b.box((0, y, r), (width - 0.1, 0.12, 0.12), "metal_dark")
        for sx in (-1, 1):
            wheel(b, sx * (width / 2 - r * 0.35), y, r, r * 0.6, "veh_silver", segs=12)
    for sx in (-1, 1):
        light(b, (sx * (width / 2 - 0.15), y1 - 0.02, deck - 0.15), "taillight", (0.18, 0.04, 0.1))
    return b


def grain_cart():
    """Chaser bin: a big hopper on one axle with a folding auger at the front left."""
    b = B()
    M, D = "veh_red", "veh_red_dark"
    seg(b, (0, 0, 0.6), (0, -1.3, 0.9), 0.14, "metal_dark")
    b.box((0, 0, 0.6), (0.14, 0.14, 0.08), "metal_dark")
    yc, L = -3.2, 3.6
    # hopper: wide on top, narrow at the bottom (prism along Y)
    b.prism([(-0.5, 0.9), (0.5, 0.9), (1.45, 2.0), (1.45, 3.1), (-1.45, 3.1), (-1.45, 2.0)], yc - L / 2, yc + L / 2, M, axis='Y')
    b.box((0, yc, 3.1), (2.9, L, 0.06), D)
    b.box((0, yc, 3.12), (2.7, L - 0.2, 0.04), "wheat_gold")
    for sx in (-1, 1):
        b.box((sx * 1.46, yc, 2.55), (0.03, L - 0.3, 0.06), D)
    b.box((0, yc, 0.85), (0.9, L + 0.3, 0.2), "metal_dark")
    # auger: up the front left corner, folded over the top
    tube(b, (-1.2, yc + L / 2 + 0.05, 0.9), (-1.2, yc + L / 2 + 0.15, 3.6), 0.17, M)
    tube(b, (-1.2, yc + L / 2 + 0.15, 3.6), (1.1, yc + L / 2 + 0.15, 3.75), 0.15, M)
    b.box((1.25, yc + L / 2 + 0.15, 3.6), (0.3, 0.3, 0.3), "metal_dark")
    for sx in (-1, 1):
        wheel(b, sx * 1.35, yc - 0.3, 0.85, 0.6, "veh_silver", lugs=10)
        b.box((sx * 1.35, yc - 0.3, 1.8), (0.65, 1.4, 0.05), D)
        light(b, (sx * 1.0, yc - L / 2 - 0.02, 1.2), "taillight", (0.18, 0.04, 0.1))
    return b


# -------------------------------------------------------------------------------- attachments

def headstock(b, h=0.9):
    """Three-point hitch frame at the front of a mounted implement (origin under the hitch)."""
    for sx in (-1, 1):
        seg(b, (sx * 0.42, -0.05, 0.55), (0, -0.05, h + 0.35), 0.08, "veh_red")
        b.box((sx * 0.45, -0.05, 0.55), (0.12, 0.1, 0.1), "metal_dark")
    b.box((0, -0.05, h + 0.35), (0.14, 0.1, 0.12), "metal_dark")
    b.box((0, -0.1, 0.55), (0.95, 0.1, 0.1), "veh_red")


def plow(bottoms=3, deep=False):
    """Mouldboard plough: bottoms offset diagonally along the main beam, depth wheel at the back."""
    b = B()
    M, D = "veh_red", "veh_red_dark"
    k = 1.25 if deep else 1.0
    headstock(b)
    step_y, step_x = 0.85 * k, 0.4 * k
    y0 = -0.5
    yE = y0 - step_y * bottoms
    seg(b, (0.0, -0.1, 0.75), (step_x * (bottoms - 1) + 0.2, yE + 0.3, 0.78 * k), 0.14 * k, M, h=0.16 * k)     # main beam
    for i in range(bottoms):
        x, y = step_x * i, y0 - step_y * i
        seg(b, (x, y, 0.75 * k), (x, y - 0.25, 0.15), 0.08, D)                       # leg
        b.box((x + 0.12, y - 0.35, 0.18), (0.42 * k, 0.6 * k, 0.32 * k), "metal", rot=(10, -30, 28))   # mouldboard
        b.box((x - 0.05, y - 0.05, 0.05), (0.08, 0.35, 0.08), "metal_dark", rot=(0, 0, 25))  # share point
        if deep:
            b.cyl((x - 0.25, y + 0.35, 0.28), 0.25, 0.04, "metal", segs=10, rot=(0, 90, 0))     # disc coulter
    wx = step_x * (bottoms - 1) + 0.45
    seg(b, (wx - 0.2, yE + 0.4, 0.78 * k), (wx, yE + 0.1, 0.4), 0.07, D)
    wheel(b, wx, yE + 0.1, 0.35 * k, 0.2, "veh_silver", segs=10)
    return b


def seeder(precision=False):
    """Seed drill: wide hopper over a row of coulters; precision planter: row units with own hoppers."""
    b = B()
    M, D = "veh_red", "veh_red_dark"
    headstock(b)
    W = 4.5 if precision else 3.0
    b.box((0, -0.45, 0.6), (W, 0.12, 0.12), "metal_dark")                   # tool bar
    if precision:
        n = 6
        for i in range(n):
            x = -W / 2 + W / n * (i + 0.5)
            seg(b, (x, -0.45, 0.6), (x, -1.3, 0.4), 0.1, "metal_dark")
            b.box((x, -1.0, 1.0), (0.42, 0.45, 0.45), M)                      # seed hopper
            b.box((x, -1.0, 1.24), (0.44, 0.47, 0.04), "veh_white")
            b.cyl((x, -0.85, 0.22), 0.22, 0.05, "metal", segs=10, rot=(0, 90, 0))
            wheel(b, x, -1.5, 0.16, 0.1, "metal_dark", segs=8)
        b.box((0, -0.75, 1.25), (1.4, 0.8, 0.7), M)                           # fertiliser hopper
        b.box((0, -0.75, 1.62), (1.45, 0.85, 0.05), "veh_white")
        for sx in (-1, 1):                                                    # folded markers
            seg(b, (sx * W / 2, -0.45, 0.7), (sx * (W / 2 - 0.2), -0.6, 2.0), 0.06, D)
            b.cyl((sx * (W / 2 - 0.2), -0.6, 2.05), 0.18, 0.04, "metal", segs=8, rot=(0, 90, 0))
    else:
        b.box((0, -0.95, 1.05), (W, 0.9, 0.8), M)                             # hopper
        b.box((0, -0.95, 1.47), (W + 0.05, 0.95, 0.06), D)                    # lid
        b.box((0, -0.5, 0.82), (W, 0.05, 0.3), "veh_white")
        for i in range(12):                                                   # seed tubes + coulters
            x = -W / 2 + W / 12 * (i + 0.5)
            seg(b, (x, -0.9, 0.65), (x, -1.0 + (0.12 if i % 2 else 0.0), 0.2), 0.035, "black")
            b.cyl((x, -1.05 + (0.12 if i % 2 else 0.0), 0.16), 0.15, 0.03, "metal", segs=8, rot=(0, 90, 0))
        b.box((0, -1.6, 0.18), (W, 0.06, 0.05), "metal_dark")                 # harrow tines bar
        for i in range(16):
            b.box((-W / 2 + W / 16 * (i + 0.5), -1.6, 0.08), (0.02, 0.02, 0.2), "metal_dark", rot=(20, 0, 0))
        for sx in (-1, 1):
            wheel(b, sx * (W / 2 + 0.15), -1.0, 0.35, 0.18, "veh_silver", segs=10)
        for i in range(3):                                                    # step + rail
            b.box((0, -1.48, 0.55 + i * 0.25), (0.5, 0.06, 0.04), "metal_dark")
    return b


def sprayer(boom=False):
    """Mounted sprayer (tank in a frame, 6 m boom) or trailed boom sprayer (big tank, 12 m boom)."""
    b = B()
    M, D = "veh_red", "veh_red_dark"
    if not boom:
        headstock(b)
        b.box((0, -0.65, 0.5), (1.1, 1.0, 0.1), "metal_dark")
        b.box((0, -0.65, 1.05), (1.05, 0.95, 1.0), "plastic_white")          # tank
        b.cyl((0, -0.65, 1.6), 0.18, 0.1, M, segs=8)
        for sx in (-1, 1):
            b.box((sx * 0.55, -0.65, 1.0), (0.06, 1.0, 1.1), M)
        W, by, bz = 6.0, -1.25, 0.9
    else:
        seg(b, (0, 0, 0.55), (0, -1.6, 0.75), 0.12, "metal_dark")
        b.box((0, 0, 0.55), (0.12, 0.12, 0.08), "metal_dark")
        b.box((0, -3.2, 0.95), (1.2, 3.4, 0.25), "metal_dark")
        b.box((0, -3.0, 1.75), (1.9, 2.8, 1.35), "plastic_white")            # tank
        b.box((0, -3.0, 2.46), (1.7, 2.6, 0.08), "plastic_white")
        b.cyl((0, -2.0, 2.55), 0.25, 0.12, M, segs=8)
        for sx in (-1, 1):
            b.box((sx * 0.97, -3.0, 1.75), (0.05, 2.9, 0.12), M)
            b.box((sx * 0.97, -3.0, 1.15), (0.05, 2.9, 0.2), M)
            wheel(b, sx * 0.95, -3.5, 0.75, 0.35, "veh_silver", lugs=8)
            b.box((sx * 0.95, -3.5, 1.6), (0.42, 1.2, 0.05), D)
            light(b, (sx * 0.7, -4.92, 1.0), "taillight", (0.14, 0.04, 0.1))
        W, by, bz = 12.0, -5.0, 1.2
        b.box((0, -4.7, 1.3), (1.4, 0.4, 1.2), M)                             # boom lift
    # boom: two-level truss with nozzles
    b.box((0, by, bz), (W, 0.1, 0.1), D)
    b.box((0, by, bz + 0.35), (W * 0.85, 0.06, 0.06), D)
    n = int(W / 1.0)
    for i in range(n + 1):
        x = -W / 2 + W * i / n
        if abs(x) <= W * 0.425:
            seg(b, (x, by, bz), (x + (W / n) * 0.5 * (1 if i % 2 else -1), by, bz + 0.35), 0.04, D)
        b.box((x, by, bz - 0.12), (0.04, 0.04, 0.16), "black")
    for sx in (-1, 1):
        b.box((sx * W / 2, by, bz - 0.1), (0.1, 0.25, 0.3), "orange")       # boom end markers
    return b


def spreader():
    """Twin-disc fertiliser spreader: V hopper on a mounted frame, spinning discs below."""
    b = B()
    M, D = "veh_red", "veh_red_dark"
    headstock(b)
    b.prism([(-0.25, 0.75), (0.25, 0.75), (1.1, 1.45), (1.1, 1.85), (-1.1, 1.85), (-1.1, 1.45)], -1.55, -0.45, M, axis='Y')
    b.box((0, -1.0, 1.86), (2.2, 1.1, 0.04), "fert_blue")                  # fertiliser showing
    for sx in (-1, 1):
        b.box((sx * 0.6, -1.0, 0.45), (0.08, 0.9, 0.5), "metal_dark")
        b.cyl((sx * 0.32, -1.25, 0.6), 0.32, 0.04, "metal", segs=10)        # discs
        for i in range(3):
            a = math.radians(i * 120 + (30 if sx > 0 else 0))
            b.box((sx * 0.32 + math.cos(a) * 0.16, -1.25 + math.sin(a) * 0.16, 0.65), (0.28, 0.03, 0.06), "metal_dark", rot=(0, 0, math.degrees(a)))
    b.box((0, -1.7, 0.6), (1.5, 0.05, 0.4), "orange")                       # guard
    return b


# -------------------------------------------------------------------------------------- build

VARIANTS_TRACTOR = {
    "green": {}, "red": {"veh_green": "veh_red", "veh_green_dark": "veh_red_dark", "veh_yellow": "veh_silver"},
    "blue": {"veh_green": "veh_blue", "veh_green_dark": "veh_blue_dark", "veh_yellow": "veh_white"},
    "orange": {"veh_green": "veh_orange", "veh_green_dark": "veh_orange_dark", "veh_yellow": "metal_dark"},
    "yellow": {"veh_green": "veh_yellow", "veh_green_dark": "veh_yellow_dark", "veh_yellow": "veh_grey"},
}
VARIANTS_TOWED = {
    "red": {}, "green": {"veh_red": "veh_green", "veh_red_dark": "veh_green_dark"},
    "blue": {"veh_red": "veh_blue", "veh_red_dark": "veh_blue_dark"},
    "orange": {"veh_red": "veh_orange", "veh_red_dark": "veh_orange_dark"},
}
VARIANTS_CAR = {
    "blue": {}, "red": {"car_blue": "veh_red", "car_blue_dark": "veh_red_dark"},
    "white": {"car_blue": "veh_white", "car_blue_dark": "veh_silver"},
    "green": {"car_blue": "veh_green", "car_blue_dark": "veh_green_dark"},
    "grey": {"car_blue": "veh_grey", "car_blue_dark": "asphalt_dark"},
}

ITEMS = [
    # group, base name, builder, variants table, variant names (first = base colour)
    ("Tractors: Basic tractor", "vehicle_tractor_basic", tractor_basic, VARIANTS_TRACTOR, ["green", "red", "blue", "orange"]),
    ("Tractors: Advanced tractor", "vehicle_tractor_advanced", tractor_advanced, VARIANTS_TRACTOR, ["green", "red", "blue", "yellow"]),
    ("Combines: Basic combine", "vehicle_combine_basic", lambda: combine(1.0, 4.5), VARIANTS_TRACTOR, ["green", "red", "yellow"]),
    ("Combines: Large combine", "vehicle_combine_large", lambda: combine(1.2, 7.5), VARIANTS_TRACTOR, ["green", "red", "yellow"]),
    ("Pickups: Heavy pickup", "vehicle_pickup_heavy", pickup_heavy, VARIANTS_CAR, ["blue", "red", "white", "green", "grey"]),
    ("Trailers: Small trailer", "trailer_small", lambda: trailer(3.0, 1.8, 0.45, 0.95, 1, 0.42), VARIANTS_TOWED, ["red", "green", "blue"]),
    ("Trailers: Medium trailer", "trailer_medium", lambda: trailer(4.6, 2.2, 0.65, 1.1, 2, 0.45), VARIANTS_TOWED, ["red", "green", "blue"]),
    ("Trailers: Large trailer", "trailer_large", lambda: trailer(6.6, 2.45, 1.0, 1.3, 3, 0.5), VARIANTS_TOWED, ["red", "green", "blue"]),
    ("Trailers: Grain cart", "trailer_grain_cart", grain_cart, VARIANTS_TOWED, ["red", "green", "blue"]),
    ("Attachments: Plows", "attachment_plow_basic", lambda: plow(3), VARIANTS_TOWED, ["red", "blue"]),
    ("Attachments: Plows", "attachment_plow_deep", lambda: plow(5, True), VARIANTS_TOWED, ["red", "blue"]),
    ("Attachments: Seeders", "attachment_seeder_basic", lambda: seeder(False), VARIANTS_TOWED, ["red", "green"]),
    ("Attachments: Seeders", "attachment_seeder_precision", lambda: seeder(True), VARIANTS_TOWED, ["red", "green"]),
    ("Attachments: Sprayers", "attachment_sprayer_basic", lambda: sprayer(False), VARIANTS_TOWED, ["red", "green"]),
    ("Attachments: Sprayers", "attachment_sprayer_boom", lambda: sprayer(True), VARIANTS_TOWED, ["red", "green"]),
    ("Attachments: Fertilizer spreader", "attachment_spreader", spreader, VARIANTS_TOWED, ["red", "blue", "orange"]),
]


def build_all(do_export=True):
    c = P2['p2_coll']("P2_Vehicles")
    P2['clear_coll'](c)
    groups = {}
    for row, (group, base, fn, table, variants) in enumerate(ITEMS):
        y = -200 - row * 12.0
        src = fn().build(f"{base}_{variants[0]}", c, loc=(0, y, 0))
        obs = [src]
        for i, v in enumerate(variants[1:]):
            obs.append(recolor(src, f"{base}_{v}", table[v], c, (14.0 * (i + 1), y, 0)))
        for ob in obs:
            if do_export:
                export(ob)
            groups.setdefault(group, []).append([ob.name, ob.name.replace(base + "_", "") if not group.startswith("Attachments") else ob.name.replace("attachment_", "").replace("_", " ")])
    # colour variants of the existing light pickup
    src = bpy.data.objects["vehicle_pickup_light"]
    groups["Pickups: Light pickup"] = [["vehicle_pickup_light", "blue (existing)"]]
    for i, v in enumerate(["red", "white", "green", "grey"]):
        ob = recolor(src, f"vehicle_pickup_light_{v}", VARIANTS_CAR[v], c, (14.0 * (i + 1), -200 - len(ITEMS) * 12.0, 0))
        if do_export:
            export(ob)
        groups.setdefault("Pickups: Light pickup", []).append([ob.name, v])
    return groups
