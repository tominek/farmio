# Logistics buildings (step 4): the collection point. A set of its own so that building it does
# not re-export the other buildings. Origin on the ground at the centre of the footprint, access
# side (front, the road) towards +Y. 1 tile = 3 m. Goods on it are dressed in the game (PileView).
import bpy, math
from mathutils import Vector

F = bpy.app.driver_namespace['farmio']; P2 = F['p2']
B = F['Builder']; export = P2['export']

GALLERY = (-40.0, -700.0, 0.0)


def collection_point():
    """1x1 low plank platform on short posts with a darker rim; a sign post at the back corner
    on the right seen from the road holds a small blank board facing the road (+Y), clear of the goods (design 17d)."""
    b = B()
    S, H = 2.6, 0.32                                             # deck size, deck top height
    for x in (-1.1, 0, 1.1):                                     # short posts
        for y in (-1.1, 0, 1.1):
            b.box((x, y, (H - 0.08) / 2), (0.16, 0.16, H - 0.08), "timber_dark")
    for y in (-1.1, 1.1):                                        # joists under the deck
        b.box((0, y, H - 0.14), (S - 0.1, 0.12, 0.1), "timber_dark")
    b.box((0, 0, H - 0.13), (S - 0.2, S - 0.2, 0.04), "timber_dark")          # dark under the plank gaps
    n = 9
    w = (S - 0.24) / n
    for i in range(n):                                           # deck planks, along Y
        x = -S / 2 + 0.12 + (i + 0.5) * w
        b.box((x, 0, H - 0.04), (w - 0.025, S - 0.24, 0.08), "wood_light")
    for s in (-1, 1):                                            # rim: darker boards round the edge
        b.box((0, s * (S / 2 - 0.06), H - 0.06), (S, 0.12, 0.16), "timber_dark")
        b.box((s * (S / 2 - 0.06), 0, H - 0.06), (0.12, S - 0.24, 0.16), "timber_dark")
    b.box((0, S / 2 + 0.005, H - 0.16), (S, 0.03, 0.14), "timber")   # front fascia catches light
    px, py = -1.05, -1.05                                        # sign post: back, right seen from the road
    b.box((px, py, (H + 1.4) / 2), (0.14, 0.14, 1.4 - H + 0.1), "timber_dark")
    b.box((px + 0.25, py + 0.1, 1.2), (1.0, 0.07, 0.5), "timber_dark")     # board frame
    b.box((px + 0.25, py + 0.14, 1.2), (0.88, 0.04, 0.38), "sign_wood")    # blank board
    return b


def build_all(do_export=True):
    c = P2['p2_coll']("P2_Logistics")
    P2['clear_coll'](c)
    ob = collection_point().build("building_collection_point", c, loc=GALLERY)
    if do_export:
        export(ob)
    return {"Buildings: Logistics": [["building_collection_point", "collection point"]]}
