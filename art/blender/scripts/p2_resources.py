# Resources in the forms the game needs: item_ (one unit on the ground), carry_ (held by a worker,
# like carry_sack / carry_crate, ~0.5 m), cargo_ (one load on a pickup bed or a trailer, fits
# 1.6 x 1.4 m, max ~0.9 m high), pile_ (stock next to a building, ~2.2 x 2.2 m). Origin on the
# ground (or the bed floor) at the centre.
import bpy, math, random
from mathutils import Vector

F = bpy.app.driver_namespace['farmio']; P2 = F['p2']
B = F['Builder']; export = P2['export']; recolor = P2['recolor']


def pallet(b, x, y, z=0.0, w=1.2, d=1.0):
    for yy in (-d / 2 + 0.05, 0, d / 2 - 0.05):
        b.box((x, y + yy, z + 0.05), (w, 0.1, 0.1), "pallet")
    for i in range(5):
        b.box((x - w / 2 + 0.1 + i * (w - 0.2) / 4, y, z + 0.13), (0.14, d, 0.03), "pallet")
    return z + 0.145


def bag(b, x, y, z, w, d, h, color, band=None, rot=0):
    b.box((x, y, z + h / 2), (w, d, h), color, rot=(0, 0, rot))
    b.box((x, y, z + h + 0.02), (w * 0.85, d * 0.8, 0.04), color, rot=(0, 0, rot))
    if band:
        b.box((x, y, z + h * 0.5), (w + 0.01, d + 0.01, h * 0.22), band, rot=(0, 0, rot))


def bag_stack(b, x, y, z, layers, color, band=None, w=1.2, d=1.0, bw=0.58, bd=0.38, bh=0.16):
    """Sacks on a pallet in alternating layers."""
    for i in range(layers):
        zz = z + i * bh
        if i % 2 == 0:
            for sx in (-1, 1):
                for sy in (-1, 0, 1):
                    bag(b, x + sx * bw / 2, y + sy * bd * 0.86, zz, bw - 0.02, bd - 0.02, bh - 0.02, color, band)
        else:
            for sx in (-1, 0, 1):
                for sy in (-1, 1):
                    bag(b, x + sx * bd * 1.05, y + sy * bw * 0.4, zz, bd - 0.02, bw * 0.8 - 0.02, bh - 0.02, color, band)


def big_bag(b, x, y, z, s, color, band="white"):
    """Bulk bag (~1 t) with lifting loops."""
    b.box((x, y, z + s / 2), (s, s, s), color)
    b.box((x, y, z + s + 0.03), (s * 0.9, s * 0.9, 0.06), color)
    b.box((x, y, z + s * 0.6), (s + 0.01, s + 0.01, 0.06), band)
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.box((x + sx * s * 0.4, y + sy * s * 0.4, z + s + 0.1), (0.06, 0.06, 0.18), band)


def heap(b, x, y, z, rx, ry, h, colors, seed, n=1):
    """Loose bulk material: flattened icospheres, bottom clamped to z."""
    r = random.Random(seed)
    for i in range(n):
        ox, oy = (r.uniform(-0.25, 0.25) * rx, r.uniform(-0.25, 0.25) * ry) if i else (0, 0)
        k = 1.0 if i == 0 else r.uniform(0.45, 0.7)
        vs = b.ico((x + ox, y + oy, z), 1.0, colors[i % len(colors)], sub=2, s=(rx * k, ry * k, h * k), jitter=0.06, seed=seed + i)
        for v in vs:
            if v.co.z < z:
                v.co.z = z
    # coarse grains on the surface so it reads as loose material, not a boulder
    for i in range(int(14 * (rx + ry))):
        u, t = r.uniform(0, math.tau), r.uniform(0.1, 0.95)
        rr = math.sqrt(1 - t * t)
        p = (x + math.cos(u) * rr * rx * 0.98, y + math.sin(u) * rr * ry * 0.98, z + t * h * 0.98)
        b.ico(p, r.uniform(0.05, 0.1) * (rx + ry), colors[1 + i % (len(colors) - 1)] if len(colors) > 1 else colors[0],
              sub=1, s=(1, 1, 0.6))


def crate(b, x, y, z, w, d, h, color="wood_light", fill=None, fill_n=0, seed=1, fill_s=0.07):
    b.box((x, y, z + 0.03), (w, d, 0.06), color)
    for sy in (-1, 1):
        b.box((x, y + sy * (d / 2 - 0.02), z + h / 2), (w, 0.04, h), color)
    for sx in (-1, 1):
        b.box((x + sx * (w / 2 - 0.02), y, z + h / 2), (0.04, d, h), color)
        b.box((x + sx * (w / 2 - 0.01), y, z + h - 0.06), (0.05, d * 0.4, 0.05), "wood_dark")   # handle slot
    if fill:
        r = random.Random(seed)
        cols = fill if isinstance(fill, (list, tuple)) else [fill]
        for i in range(fill_n):
            p = (x + r.uniform(-w / 2 + 0.08, w / 2 - 0.08), y + r.uniform(-d / 2 + 0.08, d / 2 - 0.08), z + h - 0.06 + r.uniform(0, 0.05))
            b.ico(p, fill_s, r.choice(cols), sub=1)


def canister(b, x, y, z, s=1.0, color="plastic_white", cap="spray_green"):
    b.box((x, y, z + 0.2 * s), (0.3 * s, 0.17 * s, 0.4 * s), color)
    b.box((x - 0.05 * s, y, z + 0.44 * s), (0.16 * s, 0.05 * s, 0.06 * s), color)          # handle
    b.cyl((x + 0.1 * s, y, z + 0.43 * s), 0.035 * s, 0.06 * s, cap, segs=6)
    b.box((x, y + 0.087 * s, z + 0.2 * s), (0.2 * s, 0.01, 0.14 * s), cap)                  # label


def ibc(b, x, y, z, color="plastic_white", label="spray_green"):
    z = pallet(b, x, y, z, 1.2, 1.0)
    b.box((x, y, z + 0.5), (1.08, 0.9, 0.96), color)
    for sx in (-1, 0, 1):
        b.box((x + sx * 0.55, y - 0.47, z + 0.5), (0.03, 0.03, 1.0), "metal")
        b.box((x + sx * 0.55, y + 0.47, z + 0.5), (0.03, 0.03, 1.0), "metal")
    for zz in (0.33, 0.66, 1.0):
        b.box((x, y - 0.47, z + zz), (1.12, 0.03, 0.03), "metal")
        b.box((x, y + 0.47, z + zz), (1.12, 0.03, 0.03), "metal")
        for sx in (-1, 1):
            b.box((x + sx * 0.56, y, z + zz), (0.03, 0.96, 0.03), "metal")
    b.cyl((x, y, z + 1.02), 0.12, 0.06, "black", segs=8)
    b.box((x, y + 0.48, z + 0.6), (0.4, 0.01, 0.3), label)


def milk_can(b, x, y, z, s=1.0, lid="metal"):
    b.cyl((x, y, z + 0.25 * s), 0.17 * s, 0.5 * s, "milk", segs=10)
    b.cyl((x, y, z + 0.55 * s), 0.17 * s, 0.1 * s, "milk", segs=10, r2=0.09 * s)
    b.cyl((x, y, z + 0.63 * s), 0.1 * s, 0.07 * s, lid, segs=10)
    b.cyl((x, y, z + 0.3 * s), 0.175 * s, 0.03 * s, "metal", segs=10)
    for sx in (-1, 1):
        b.box((x + sx * 0.18 * s, y, z + 0.5 * s), (0.03 * s, 0.08 * s, 0.03 * s), "metal")


def straw_bale(b, x, y, z, color="straw", dark="straw_dark", rot=0, k=1.0):
    w, d, h = 0.9 * k, 0.45 * k, 0.36 * k
    if rot:
        w, d = d, w
    b.box((x, y, z + h / 2), (w, d, h), color)
    for t in (-0.25, 0.25):                                   # twine
        if rot:
            b.box((x, y + t * d, z + h / 2), (w + 0.01, 0.025, h + 0.01), dark)
        else:
            b.box((x + t * w, y, z + h / 2), (0.025, d + 0.01, h + 0.01), dark)


def round_bale(b, x, y, z, r=0.75, wd=1.2, color="straw", dark="straw_dark"):
    b.cyl((x, y, z + r), r, wd, color, segs=14, rot=(0, 90, 0))
    b.cyl((x, y, z + r), r * 0.7, wd + 0.02, dark, segs=14, rot=(0, 90, 0))
    b.cyl((x, y, z + r), r * 0.3, wd + 0.04, color, segs=10, rot=(0, 90, 0))


def egg_tray(b, x, y, z, color="egg", n=5, m=6, s=1.0):
    b.box((x, y, z + 0.025 * s), (0.3 * s, 0.3 * s * m / n, 0.05 * s), "cardboard")
    for i in range(n):
        for j in range(m):
            b.ico((x - 0.12 * s + i * 0.06 * s, y - 0.06 * s * (m - 1) / 2 + j * 0.06 * s, z + 0.07 * s), 0.026 * s, color, sub=1, s=(1, 1, 1.3))


def wool_bundle(b, x, y, z, s=1.0, color="wool", shade="wool_shade", seed=1):
    r = random.Random(seed)
    b.ico((x, y, z + 0.16 * s), 0.25 * s, color, sub=1, s=(1.3, 1.0, 0.7), jitter=0.12, seed=seed)
    for i in range(3):
        b.ico((x + r.uniform(-0.15, 0.15) * s, y + r.uniform(-0.1, 0.1) * s, z + 0.24 * s), 0.12 * s, shade if i % 2 else color, sub=1, jitter=0.15, seed=seed + i)


def wool_bale(b, x, y, z, color="wool", shade="wool_shade", k=1.0):
    """Pressed wool bale in a jute wrap."""
    w, d, h = 0.75 * k, 0.6 * k, 0.75 * k
    b.box((x, y, z + h / 2), (w, d, h), "sack")
    b.box((x, y, z + h + 0.02), (w * 0.9, d * 0.85, 0.06), color)
    for t in (-0.3, 0.3):
        b.box((x, y, z + h / 2 + t * h), (w + 0.01, d + 0.01, 0.04), "sack_shade")


def loaf(b, x, y, z, s=1.0, rot=0):
    b.ico((x, y, z + 0.07 * s), 0.13 * s, "bread", sub=1, s=(1.4, 0.75, 0.6))
    for t in (-0.06, 0, 0.06):
        b.box((x + t * s, y, z + 0.13 * s), (0.02 * s, 0.12 * s, 0.015), "bread_light", rot=(0, 0, 20 + rot))


def box_carton(b, x, y, z, w, d, h, color="cardboard", label=None):
    b.box((x, y, z + h / 2), (w, d, h), color)
    b.box((x, y, z + h - 0.005), (w * 0.95, 0.03, 0.012), "wood_dark")            # tape
    if label:
        b.box((x, y + d / 2 + 0.003, z + h * 0.55), (w * 0.6, 0.006, h * 0.4), label)


def cubes(b, x, y, z, w, d, layers, col_a="cobble", col_b="cobble_dark", s=0.12, seed=1):
    r = random.Random(seed)
    nx, ny = int(w / s), int(d / s)
    for k in range(layers):
        for i in range(nx):
            for j in range(ny):
                if k == layers - 1 or i in (0, nx - 1) or j in (0, ny - 1):
                    b.box((x - w / 2 + (i + 0.5) * s, y - d / 2 + (j + 0.5) * s, z + (k + 0.5) * s), (s * 0.92, s * 0.92, s * 0.92),
                          r.choice((col_a, col_a, col_b, "cobble_light")))


# --------------------------------------------------------------------------------- resources

def build_resources():
    """Returns [(group, [(name, Builder, label)])]."""
    R = []
    # planks (carry_planks exists)
    b = B(); z = 0.0
    for sy in (-0.5, 0.5):
        b.box((0, sy, 0.05), (1.5, 0.12, 0.1), "wood_dark")
    for i in range(5):
        for k in range(6):
            b.box((-0.55 + k * 0.22, 0, 0.14 + i * 0.09), (0.2, 1.5, 0.07), "wood_light" if (i + k) % 3 else "wood")
    for sy in (-0.45, 0.45):
        b.box((0, sy, 0.35), (1.4, 0.03, 0.5), "black")             # straps
    cargo_planks = b
    b = B()
    for x in (-0.55, 0.55):
        for sy in (-0.7, 0.7):
            b.box((x, sy, 0.05), (1.0, 0.1, 0.1), "wood_dark")
        for i in range(7):
            for k in range(4):
                b.box((x - 0.33 + k * 0.22, 0, 0.14 + i * 0.09), (0.2, 2.0, 0.07), "wood_light" if (i + k) % 3 else "wood")
    R.append(("Planks", [("cargo_planks", cargo_planks, "cargo"), ("pile_planks", b, "pile")]))

    # flour, sugar, seeds, fertilizer: sacks
    for res, col, band, label in (("flour", "sack", "veh_blue", "Flour"), ("sugar", "sugar", "veh_red", "Sugar"),
                                  ("seeds", "sack_shade", "veh_green", "Seeds"), ("fertilizer", "fert_blue", "white", "Fertilizer")):
        c = B(); bag(c, 0, 0, 0, 0.42, 0.3, 0.4, col, band)
        g = B(); z = pallet(g, 0, 0, 0); bag_stack(g, 0, 0, z, 4, col, band)
        p = B()
        for x, n in ((-0.62, 6), (0.62, 4)):
            z = pallet_rot(p, x, 0, 0)
            bag_stack_rot(p, x, 0, z, n, col, band)
        if res in ("seeds", "fertilizer"):
            big = B(); big_bag(big, 0, 0, pallet(big, 0, 0, 0), 0.95, col, "white" if res == "seeds" else "sack")
            R.append((label, [(f"carry_{res}", c, "carry"), (f"cargo_{res}", g, "cargo (sacks)"), (f"cargo_{res}_bulk", big, "cargo (bulk bag)"),
                              (f"pile_{res}", p, "pile")]))
        else:
            R.append((label, [(f"carry_{res}", c, "carry"), (f"cargo_{res}", g, "cargo"), (f"pile_{res}", p, "pile")]))

    # bread
    it = B(); loaf(it, 0, 0, 0, 1.4)
    c = B(); crate(c, 0, 0, 0, 0.5, 0.36, 0.22, "wood_light")
    for x, y in ((-0.12, -0.07), (0.12, -0.07), (-0.12, 0.08), (0.12, 0.08)):
        loaf(c, x, y, 0.1, 0.85)
    g = B(); z = pallet(g, 0, 0, 0)
    for k in range(3):
        for i in range(2):
            for j in range(2):
                crate(g, -0.28 + i * 0.56, -0.24 + j * 0.48, z + k * 0.24, 0.52, 0.44, 0.22, "wood_light")
                if k == 2:
                    loaf(g, -0.28 + i * 0.56, -0.24 + j * 0.48, z + k * 0.24 + 0.1, 0.9)
    p = B()
    for x in (-0.62, 0.62):
        z = pallet_rot(p, x, 0, 0)
        for k in range(4 if x < 0 else 3):
            for j in (-0.45, 0, 0.45):
                crate(p, x, j, z + k * 0.24, 0.52, 0.42, 0.22)
                if k == (3 if x < 0 else 2):
                    loaf(p, x, j, z + k * 0.24 + 0.1, 0.9)
    R.append(("Bread", [("item_bread", it, "item"), ("carry_bread", c, "carry"), ("cargo_bread", g, "cargo"), ("pile_bread", p, "pile")]))

    # pasta: cartons
    c = B(); box_carton(c, 0, 0, 0, 0.45, 0.32, 0.3, "cardboard", "pasta")
    g = B(); z = pallet(g, 0, 0, 0)
    for k in range(3):
        for i in range(3):
            for j in range(3):
                box_carton(g, -0.38 + i * 0.38, -0.3 + j * 0.3, z + k * 0.26, 0.37, 0.29, 0.25, "cardboard", "pasta" if j == 2 else None)
    p = B()
    for x in (-0.62, 0.62):
        z = pallet_rot(p, x, 0, 0)
        for k in range(4 if x < 0 else 3):
            for i in (-0.25, 0.25):
                for j in (-0.6, 0, 0.6):
                    box_carton(p, x + i * 0.95, j, z + k * 0.26, 0.45, 0.55, 0.25, "cardboard", "pasta" if i > 0 else None)
    R.append(("Pasta", [("carry_pasta", c, "carry"), ("cargo_pasta", g, "cargo"), ("pile_pasta", p, "pile")]))

    # spray: canisters and IBC tanks (litres)
    it = B(); canister(it, 0, 0, 0)
    g = B(); ibc(g, 0, 0, 0)
    p = B(); ibc(p, -0.62, -0.5, 0); ibc(p, 0.62, -0.5, 0)
    for i in range(4):
        canister(p, -0.75 + i * 0.4, 0.75, 0)
    R.append(("Spray", [("carry_spray", it, "carry (20 l)"), ("cargo_spray", g, "cargo (1000 l)"), ("pile_spray", p, "pile")]))

    # road materials
    g = B(); heap(g, 0, 0, 0, 0.8, 0.7, 0.55, ["gravel", "gravel_dark", "gravel_light"], 3, 4)
    p = B(); heap(p, 0, 0, 0, 1.15, 1.1, 0.9, ["gravel", "gravel_dark", "gravel_light"], 5, 5)
    R.append(("Gravel", [("cargo_gravel", g, "cargo"), ("pile_gravel", p, "pile")]))
    g = B(); z = pallet(g, 0, 0, 0); cubes(g, 0, 0, z, 1.08, 0.96, 4, seed=2)
    p = B()
    for x in (-0.62, 0.62):
        z = pallet_rot(p, x, 0, 0)
        cubes(p, x, 0, z, 0.96, 1.92, 5 if x < 0 else 3, seed=4 if x < 0 else 6)
    R.append(("Cobblestones", [("cargo_cobblestones", g, "cargo"), ("pile_cobblestones", p, "pile")]))
    g = B(); heap(g, 0, 0, 0, 0.8, 0.7, 0.5, ["asphalt", "asphalt_dark", "asphalt_light"], 7, 4)
    p = B(); heap(p, 0, 0, 0, 1.15, 1.1, 0.8, ["asphalt", "asphalt_dark", "asphalt_light"], 9, 5)
    R.append(("Asphalt", [("cargo_asphalt", g, "cargo"), ("pile_asphalt", p, "pile")]))
    g = B(); z = pallet(g, 0, 0, 0); bag_stack(g, 0, 0, z, 4, "concrete_light", "veh_grey")
    p = B()
    z = pallet_rot(p, -0.62, 0, 0); bag_stack_rot(p, -0.62, 0, z, 5, "concrete_light", "veh_grey")
    for k in range(3):                                                          # precast slabs
        p.box((0.62, 0, 0.1 + k * 0.17), (1.1, 1.9, 0.15), "concrete" if k % 2 else "concrete_dark")
        p.box((0.62, 0, 0.02 + k * 0.17), (1.0, 0.1, 0.04), "wood_dark")
    R.append(("Concrete", [("cargo_concrete", g, "cargo"), ("pile_concrete", p, "pile")]))

    # ---- animal goods
    for res, lid, label, s in (("milk", "metal", "Milk", 1.0), ("goat_milk", "fert_blue", "Goat milk", 0.8)):
        it = B(); milk_can(it, 0, 0, 0, s, lid)
        c = B(); milk_can(c, 0, 0, 0, s * 0.8, lid)
        g = B(); z = pallet(g, 0, 0, 0)
        for i in range(3):
            for j in range(2):
                milk_can(g, -0.4 + i * 0.4, -0.22 + j * 0.44, z, s, lid)
        p = B()
        for i in range(4):
            for j in range(3):
                if (i, j) != (3, 2):
                    milk_can(p, -0.75 + i * 0.5, -0.55 + j * 0.55, 0, s, lid)
        R.append((label, [(f"item_{res}", it, "item (can)"), (f"carry_{res}", c, "carry"), (f"cargo_{res}", g, "cargo"), (f"pile_{res}", p, "pile")]))
    # milk tank for later dairy logistics
    t = B()
    t.cyl((0, 0, 0.75), 0.6, 1.5, "metal", segs=14, rot=(90, 0, 0))
    for y in (-0.55, 0.55):
        t.box((0, y, 0.15), (1.0, 0.12, 0.3), "metal_dark")
    t.cyl((0, 0, 1.38), 0.18, 0.1, "metal_dark", segs=8)
    R.append(("Milk tank", [("cargo_milk_tank", t, "cargo (1000 l tank)")]))

    for res, col, shade, label in (("wool", "wool", "wool_shade", "Wool"),):
        it = B(); wool_bundle(it, 0, 0, 0, 1.0, col, shade)
        c = B(); wool_bale(c, 0, 0, 0, col, shade, 0.65)
        g = B(); z = pallet(g, 0, 0, 0)
        for i in (-0.3, 0.3):
            wool_bale(g, i * 1.25, 0, z, col, shade, 0.95)
        p = B()
        for i, (x, y, zz) in enumerate(((-0.45, -0.4, 0), (0.45, -0.4, 0), (-0.45, 0.45, 0), (0.45, 0.45, 0), (0.0, 0.0, 0.75))):
            wool_bale(p, x, y, zz, col, shade)
        R.append((label, [(f"item_{res}", it, "item (fleece)"), (f"carry_{res}", c, "carry"), (f"cargo_{res}", g, "cargo"), (f"pile_{res}", p, "pile")]))

    it = B(); egg_tray(it, 0, 0, 0)
    c = B()                                                                         # basket of eggs
    c.cyl((0, 0, 0.1), 0.22, 0.2, "wood_light", segs=10, r2=0.25)
    c.cyl((0, 0, 0.19), 0.2, 0.02, "straw", segs=10)
    r = random.Random(4)
    for i in range(9):
        c.ico((r.uniform(-0.12, 0.12), r.uniform(-0.12, 0.12), 0.23), 0.04, r.choice(("egg", "egg_brown")), sub=1, s=(1, 1, 1.3))
    for sx in (-1, 1):
        c.box((sx * 0.12, 0, 0.32), (0.03, 0.03, 0.26), "wood", rot=(0, sx * -35, 0))
    c.box((0, 0, 0.43), (0.12, 0.03, 0.03), "wood")
    g = B(); z = pallet(g, 0, 0, 0)
    for k in range(3):
        for i in range(2):
            for j in range(2):
                crate(g, -0.28 + i * 0.56, -0.24 + j * 0.48, z + k * 0.2, 0.52, 0.44, 0.18, "plastic_blue")
                if k == 2:
                    for t in (-0.12, 0.12):
                        egg_tray(g, -0.28 + i * 0.56 + t, -0.24 + j * 0.48, z + k * 0.2 + 0.08, "egg" if i else "egg_brown", 4, 4, 0.75)
    p = B()
    for x in (-0.62, 0.62):
        z = pallet_rot(p, x, 0, 0)
        for k in range(5 if x < 0 else 3):
            for jy in (-0.45, 0.0, 0.45):
                crate(p, x, jy, z + k * 0.2, 0.52, 0.42, 0.18, "plastic_blue")
    R.append(("Eggs", [("item_eggs", it, "item (tray)"), ("carry_eggs", c, "carry (basket)"), ("cargo_eggs", g, "cargo"), ("pile_eggs", p, "pile")]))

    g = B(); heap(g, 0, 0, 0, 0.8, 0.7, 0.5, ["manure", "manure_dark", "straw_dark"], 11, 4)
    p = B()
    p.box((0, 0, 0.04), (2.3, 2.3, 0.08), "concrete")
    for sx in (-1, 1):
        p.box((sx * 1.1, 0.1, 0.4), (0.12, 2.1, 0.8), "concrete_dark")
    p.box((0, -1.1, 0.4), (2.3, 0.12, 0.8), "concrete_dark")
    heap(p, 0, 0.1, 0.08, 1.0, 1.05, 0.95, ["manure", "manure_dark", "straw_dark"], 13, 6)
    R.append(("Manure", [("cargo_manure", g, "cargo"), ("pile_manure", p, "pile (dung heap)")]))

    for res, col, dark, label in (("straw", "straw", "straw_dark", "Straw"), ("hay", "hay_green", "hay_green_dark", "Hay")):
        it = B(); straw_bale(it, 0, 0, 0, col, dark)
        c = B(); straw_bale(c, 0, 0, 0, col, dark, k=0.62)
        g = B()
        for k in range(2):
            for i in range(2):
                for j in range(3):
                    straw_bale(g, -0.46 + i * 0.92, -0.47 + j * 0.47, k * 0.36, col, dark)
        p = B()
        for k in range(3):
            for i in range(2):
                for j in range(4):
                    if k < 2 or (i == 0 and j in (1, 2)):
                        straw_bale(p, -0.46 + i * 0.92, -0.71 + j * 0.47, k * 0.36, col, dark)
        rb = B(); round_bale(rb, 0, 0, 0, 0.75, 1.2, col, dark)
        R.append((label, [(f"item_{res}_bale", it, "item (bale)"), (f"carry_{res}_bale", c, "carry"), (f"cargo_{res}", g, "cargo"),
                          (f"pile_{res}", p, "pile"), (f"item_{res}_round_bale", rb, "round bale")]))

    # fruit in crates
    for res, cols, label in (("apples", ("apple_red", "apple_red", "apple_green"), "Apples"), ("pears", ("pear", "pear", "apple_green"), "Pears"),
                             ("plums", ("plum",), "Plums"), ("apricots", ("apricot",), "Apricots")):
        c = B(); crate(c, 0, 0, 0, 0.5, 0.36, 0.24, "wood_light", cols, 14, 3, 0.055)
        g = B(); z = pallet(g, 0, 0, 0)
        for k in range(3):
            for i in range(2):
                for j in range(2):
                    crate(g, -0.28 + i * 0.56, -0.24 + j * 0.48, z + k * 0.26, 0.52, 0.44, 0.24, "wood_light",
                          cols if k == 2 else None, 10, i * 2 + j, 0.055)
        p = B()
        for x in (-0.62, 0.62):
            z = pallet_rot(p, x, 0, 0)
            for k in range(4 if x < 0 else 3):
                for jy in (-0.45, 0.0, 0.45):
                    crate(p, x, jy, z + k * 0.26, 0.52, 0.42, 0.24, "wood_light", cols if k == (3 if x < 0 else 2) else None, 8, int(jy * 10) + 5, 0.055)
        R.append((label, [(f"carry_crate_{res}", c, "carry"), (f"cargo_{res}", g, "cargo"), (f"pile_{res}", p, "pile")]))
    return R


def pallet_rot(b, x, y, z):
    """Pallet turned along Y (two of them side by side make a 2.4 x 2 m pile)."""
    for xx in (-0.45, 0, 0.45):
        b.box((x + xx, y, z + 0.05), (0.1, 2.0, 0.1), "pallet")
    for i in range(7):
        b.box((x, y - 0.95 + i * 0.316, z + 0.13), (1.0, 0.14, 0.03), "pallet")
    return z + 0.145


def bag_stack_rot(b, x, y, z, layers, color, band=None):
    for i in range(layers):
        zz = z + i * 0.16
        if i % 2 == 0:
            for sy in range(5):
                for sx in (-1, 1):
                    bag(b, x + sx * 0.24, y - 0.78 + sy * 0.39, zz, 0.46, 0.37, 0.14, color, band)
        else:
            for sy in range(3):
                for sx in (-1, 0, 1):
                    bag(b, x + sx * 0.31, y - 0.62 + sy * 0.62, zz, 0.3, 0.58, 0.14, color, band)


def wheelbarrow_manure(c, loc):
    """The worker's wheelbarrow with a load of manure: palette swap of the grain load."""
    src = bpy.data.objects["tool_wheelbarrow_wheat"]
    return recolor(src, "tool_wheelbarrow_manure", {"wheat_gold": "manure", "wheat_ripe": "manure_dark", "straw": "manure",
                                                     "hay": "manure", "wheat_ear": "manure_dark", "stubble": "manure_dark"}, c, loc)


def build_all(do_export=True):
    c = P2['p2_coll']("P2_Resources")
    P2['clear_coll'](c)
    groups = []
    for row, (label, items) in enumerate(build_resources()):
        ents = []
        for i, (name, b, lab) in enumerate(items):
            ob = b.build(name, c, loc=(100 + i * 3.5, -140 - row * 3.5, 0))
            if do_export:
                export(ob)
            ents.append([name, lab])
        groups.append(("Resources: " + label, ents))
    ob = wheelbarrow_manure(c, (100 + 2 * 3.5, -140 - 23 * 3.5, 0))
    if do_export:
        export(ob)
    for g in groups:
        if g[0] == "Resources: Manure":
            g[1].insert(0, ["tool_wheelbarrow_manure", "wheelbarrow"])
    return groups
