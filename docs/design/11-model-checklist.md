# 3D Model Checklist

Scale: 1 grid tile = 3m x 3m. All dimensions in tiles.

---

## Phase 1 — Grey-box POC

Core models needed to prove the gameplay loop. All built from Godot primitives (BoxMesh, CylinderMesh, SphereMesh, CSG nodes). Colors distinguish types.

### Workers
- [x] **Worker** — Capsule (0.5m wide, 1.8m tall), light blue. Floating colored sphere above head for status (green = working, yellow = walking, grey = idle)

### Field Components
- [x] **Bare soil tile** — Flat brown box (3m x 3m x 0.1m)
- [x] **Cultivated soil tile** — Slightly darker brown box with thin ridges (or just darker shade)
- [x] **Crop mesh (generic)** — Small green box/cylinder on soil tile. Height driven by shader (0 → 1.5m). Color shifts from light green to dark green to yellow at maturity. One generic mesh for all crop types in Phase 1.
- [x] **Stubble** — Short brown cylinders (0.2m tall) scattered on soil tile
- [x] **Harvest crate (generic)** — Brown box with golden crop on top, placed on field after harvest
- [x] **Fence segment** — Thin brown box (3m long x 0.1m wide x 1m tall)
- [x] **Fence corner** — Two thin brown boxes joined in an L
- [x] **Gate** — Two short brown posts (0.3m x 0.3m x 1m) with a gap between them

### Buildings
- [x] **Storage Barn** — Orange box (12m x 9m x 5m) with darker orange triangle prism on top (roof)
- [x] **Garage** — Grey box (15m x 12m x 4m) with dark grey flat top
- [x] **Hand Mill** — Beige box (6m x 6m x 4m) with a brown cylinder on top (millstone)
- [x] **Sawmill** — Brown box (9m x 6m x 3m) with a thin disc on the side (saw blade — flat cylinder)
- [x] **Dealer** — Large red box (12m x 9m x 5m) with a sign (flat plane with different color on front)
- [x] **Pickup Point** — Grey pad (6m x 6m) with wooden post and yellow sign

### Vehicles
- [x] **Light Pickup** — Blue box (4.5m x 2m x 1.5m) on 4 small black cylinders (wheels). Smaller box on front (cab)
- [x] **Wheelbarrow** — Small grey box (1m x 0.6m x 0.5m) on one black cylinder wheel, with two thin cylinder handles

### Roads
- [x] **Dirt Road** — Flat dark brown plane (3m x 3m x 0.05m), slightly raised from grass
- [x] **Gravel Road** — Light grey/tan plane
- [ ] **One-way arrow** — Small flat white triangle on the road surface

### Natural Environment
- [x] **Full tree (deciduous)** — Brown cylinder trunk (0.5m wide x 3m tall) + green sphere canopy (3m diameter) on top
- [x] **Full tree (conifer)** — Brown cylinder trunk + stacked cone canopy layers
- [x] **Small tree (deciduous)** — Thinner trunk + medium sphere canopy
- [x] **Small tree (conifer)** — Thinner trunk + single cone canopy
- [x] **Sapling (deciduous)** — Thin brown cylinder (0.2m wide x 1m tall) + small green sphere (1m diameter)
- [x] **Sapling (conifer)** — Thin trunk + tiny cone canopy
- [x] **Tree stump** — Short brown cylinder (0.5m wide x 0.3m tall)

### Terrain
- [x] **Grass base** — Large flat green plane (generated programmatically)
- [x] **Grid overlay** — Subtle white/grey lines, toggled during placement mode (generated programmatically)

### UI Elements
- [x] **Ghost preview** — Semi-transparent version of the building being placed (generated programmatically)
- [ ] **Pending construction marker** — Dashed outline or pulsing semi-transparent version

**Phase 1 total: ~22 models — nearly all done!**

---

## Phase 2 — Core Gameplay Complete

Add remaining buildings, vehicles, and per-crop visuals. Still using Godot primitives but with more visual distinction. Transition to low-poly Blender models when ready.

### Additional Buildings
- [ ] **Water Mill** (3x3 / 9m x 9m) — Grey-box: Beige box with a water wheel (flat cylinder on the side, slightly bigger than Hand Mill)
- [ ] **Bakery** (3x3 / 9m x 9m) — Grey-box: Warm brown box with a small cylinder chimney on top (for smoke later)
- [ ] **Sugar Mill** (3x3 / 9m x 9m) — Grey-box: White/beige box, taller than Hand Mill
- [ ] **Silo** (2x2 / 6m x 6m) — Grey-box: Tall silver/grey cylinder (2m wide x 8m tall) with cone top
- [ ] **Supply Storage** (2x2 / 6m x 6m) — Grey-box: Small brown box (like a shed), with a colored label indicating resource type

### Additional Vehicles
- [ ] **Basic Tractor** — Grey-box: Green box (3m x 1.8m x 2m), big rear wheels (black cylinders), small front wheels
- [ ] **Basic Combine** — Grey-box: Large yellow box (5m x 3m x 3m), wide front header (flat box extending forward), big wheels

### Tractor Attachments (basic set)
- [ ] **Basic Plow** — Grey-box: Dark grey box with angled blades (thin triangles pointing down)
- [ ] **Basic Seeder** — Grey-box: Grey box with a row of thin cylinders underneath (seed tubes)
- [ ] **Basic Sprayer** — Grey-box: White cylinder tank on a frame with thin horizontal bar (boom arms)
- [ ] **Fertilizer Spreader** — Grey-box: Green box/hopper with a spinning disc underneath (flat cylinder)

### Per-Crop Meshes (replace generic crop mesh)
**Potatoes:**
- [ ] Growing — Low leafy bushes (flat green boxes, wider than tall)
- [ ] Harvest-ready — Full bushy plant
- [ ] Harvest crate — Brown crate with potatoes visible on top
- [ ] Stubble — Bare soil with small holes

**Wheat:**
- [ ] Growing — Thin vertical cylinders (stalks), dense
- [ ] Harvest-ready — Golden yellow tall stalks
- [ ] Harvest crate — Brown crate with golden wheat on top
- [ ] Stubble — Short cut stalks

**Corn:**
- [ ] Growing — Tall single stalk with leaf shapes
- [ ] Harvest-ready — Tall stalk with small box cobs
- [ ] Harvest crate — Brown crate with yellow corn on top
- [ ] Stubble — Cut stalks

**Sugar Beet:**
- [ ] Growing — Leafy top (similar to potato but pointier)
- [ ] Harvest-ready — Leaves with visible root bulge
- [ ] Harvest crate — Brown crate with beets on top
- [ ] Stubble — Bare soil with holes

### Additional Roads
- [ ] **Cobblestone Road** — Grey plane with grid pattern (or slightly bumpy top)

### Natural Environment
- [ ] **Dense forest boundary** — Tightly packed cluster of full trees (reuse full tree model, place densely)

### Loading Bay
- [ ] **Loading bay** — Small flat grey platform extending from a building (3m x 3m pull-off area)

**Phase 2 total: ~25 additional models**

---

## Phase 3 — Late Game Content

Advanced vehicles, equipment, and building tiers.

### Advanced Vehicles
- [ ] **Advanced Tractor** — Grey-box: Larger green box than basic, bigger wheels, visually beefier
- [ ] **Large Combine** — Grey-box: Wider yellow box than basic, much wider header
- [ ] **Heavy Pickup** — Grey-box: Larger blue box than light pickup, dual rear wheels

### Trailers
- [ ] **Small Trailer** — Grey-box: Small open box (2m x 1.5m x 1m) on 2 wheels with hitch bar
- [ ] **Medium Trailer** — Grey-box: Medium open box (3m x 2m x 1.2m) on 2 wheels
- [ ] **Large Trailer** — Grey-box: Large open box (4.5m x 2.5m x 1.5m) on 4 wheels

### Advanced Tractor Attachments
- [ ] **Deep Plow** — Grey-box: Wider/heavier version of basic plow
- [ ] **Precision Seeder** — Grey-box: Wider version of basic seeder with more tubes
- [ ] **Boom Sprayer** — Grey-box: Much wider boom arms than basic sprayer
- [ ] **Grain Cart** — Grey-box: Large hopper box (3m x 2m x 2m) on wheels with hitch, unloading auger (angled cylinder)

### Advanced Buildings
- [ ] **Industrial Mill** (3x3 / 9m x 9m) — Grey-box: Larger/taller than Water Mill, more industrial look (flat roof, pipes)
- [ ] **Pasta Maker** (2x2 / 6m x 6m) — Grey-box: White box with cylinder pipes/rollers on the side

### Advanced Roads
- [ ] **Asphalt Road** — Dark grey/black smooth plane
- [ ] **Concrete Road** — Light grey smooth plane, slightly wider-looking

### Building Upgrade Visuals
- [ ] **Storage Barn Level 2** — Larger/cleaner version, maybe added side extension
- [ ] **Storage Barn Level 3** — Biggest version
- [ ] **Silo Level 2/3** — Taller or additional cylinder next to original
- [ ] **Processing building upgrade indicators** — Subtle visual changes (better equipment visible, cleaner look)

**Phase 3 total: ~20 additional models**

---

## Phase 4 — Blender Polish (replace all grey-box)

Replace every Godot primitive with a proper low-poly Blender model (glTF/GLB export). Priority order:

1. **Vehicles first** — most visible, constantly moving on screen
2. **Workers** — always visible, add 2-3 cosmetic variants
3. **Crops** — cover large areas, big visual impact
4. **Buildings** — static but important for farm identity
5. **Roads** — auto-connecting pieces (straight, corner, T-junction, crossroad, dead-end) per type
6. **Natural trees** — cover the map, high visual impact
7. **Terrain** — grass texture, edge boundary polish

**Road connection variants needed per type (Phase 4):**
- [ ] Straight
- [ ] Corner (90°)
- [ ] T-junction
- [ ] Crossroad (4-way)
- [ ] Dead-end

That's 5 variants x 5 road types = 25 road pieces.

---

## Full Summary

| Phase | Models | Purpose |
|-------|--------|---------|
| Phase 1 | ~22 | POC — nearly all done! |
| Phase 2 | ~25 | Core gameplay — all crops, basic machines |
| Phase 3 | ~20 | Late game — advanced vehicles, upgrades |
| Phase 4 | ~80 | Polish — replace all with Blender models |

Start with Phase 1. If the game is fun with colored boxes, everything else is polish.
