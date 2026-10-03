# Art Pipeline

## Approach: Low-Poly from the Start

Models are created in **Blender via the Blender MCP** (Claude builds and iterates on models through Blender's Python API, the user reviews renders and approves). Since a simple low-poly model is almost as fast to make this way as a grey-box, the game uses real low-poly models from the start. Godot primitives are only a temporary stand-in for things that don't have a model yet.

## Phases

### Phase 0 — Style Exploration (before any gameplay code)
- Build a handful of representative models in Blender (e.g. Storage Barn, worker, tree, pickup, a field with crops)
- Iterate until the style is settled: proportions, level of detail, palette, readability from the game camera
- Outcome: a written **style guide** + **palette texture** + **export conventions** — done, see below

### Phase 1 — Low-Poly Models for Gameplay
- Every gameplay element gets a simple low-poly model in the agreed style as it is implemented
- Shared palette texture, flat colors, no per-model textures
- Basic shape language: round = natural/organic, boxy = man-made
- Recognizable silhouettes from the angled game camera at default zoom

### Phase 2 — Polish
- More detail where it pays off, upgrade-level variants
- Worker and vehicle animations
- Particle effects (dust, smoke from bakery, etc.)
- Seasonal visual variations (if implemented)

## Visual Style (settled in Phase 0)

- **Low-poly, flat-shaded**, colors from a single shared **palette texture** (`art/textures/palette.png`, 64x64 px = 16x16 swatches of 4 px; every face's UVs point to the centre of one swatch)
- **One matte material** for everything: roughness 1, no specular — no glossy highlights
- **Central European countryside**: timber barns with half-hip clay-tile roofs, plastered/half-timbered houses, stone plinths, green shutters; no American-style red barns as the default
- **Characters**: blocky (boxes), slightly big head; male/female with skin tone and clothing color variants
- **Nature**: icosphere-cluster deciduous trees, stacked-cone conifers in a natural dark green (not teal)
- **Crops**: individual plants (leaves, stalks, ears/cobs), no solid "canopy" volumes; growth is continuous (see below)
- **No religious symbols** in any model (e.g. no cross-shaped weathervanes)
- **Lighting reference**: warm sun from ~40° elevation, soft sky-colored ambient, linear tonemapping (matches Blender "Standard")
- Readable from the angled orthographic camera at default zoom: distinct silhouettes and colors matter more than detail

## Export Conventions (validated in Godot 4.7)

- **Units**: meters, 1 grid tile = 3m
- **Orientation**: model the front / access point towards **Blender +Y**; the glTF exporter (+Y up) maps it to **Godot -Z** (forward) — verified with barn, dealer, pickup
- **Origin**: on the ground at the centre of the footprint (buildings) or of the body (vehicles, workers); props and tiles centred on their tile
- **Format**: one **GLB per model**, exported with `export_yup=True`, materials included, no animations; mesh object name = file name
- **Naming**: `category_name[_variant]` — `building_*`, `worker_*`, `vehicle_*`, `tool_*`, `prop_*`, `tree_*`, `crop_*`, `road_<surface>_<oneway|twoway>_<piece>`, `fence_*`, `ui_*`
- **Godot material**: imported materials are replaced by one shared `StandardMaterial3D` (palette texture, **nearest** filtering, roughness 1, specular 0) via `material_override` / an import script. Export GLBs **without the embedded image** (otherwise Godot extracts a separate palette copy per model)
- **Crop meshes** carry extra vertex data for the growth shader: `COLOR.rgb` = part mask (r leaf, g stalk, b ear), `COLOR.a` = pivot height / 1.5, `UV2` = pivot x/z (in Blender store `v = 1 + y` because the exporter flips V)
- **Folders**: sources in `art/blender/` (+ palette in `art/textures/`), exported GLBs in the game's `assets/models/`; `art/` has a `.gdignore`
- **Poly budgets** (current models): worker ~110 faces, tree 35–70, pickup ~240, buildings 600–1 900, road piece 200–600, crop tile 2 000–2 500 at full growth (needs LOD, see Performance)

## Pipeline Test Results (`prototypes/art_pipeline/`)

A minimal Godot 4.7 project loads the exported GLBs with the game camera, the shared palette material and a wheat field on a MultiMesh with the growth shader. Screenshots in `art/renders/godot/`.

- Scale, orientation, colors and shadows match the Blender renders
- Continuous growth works on the MultiMesh (one float per tile in `INSTANCE_CUSTOM.r`), including the seeding gradient and wind sway
- Performance (Apple M4 Pro, full-detail wheat): 16x16 and 32x32 fields stay at the 60 FPS cap; a **64x64 mega field costs ~23 ms per frame** → a far-zoom LOD is required
- From game zoom a **ripe field reads brown** (thin stalks, soil showing through) → the soil under a crop should be tinted by the shader as the crop grows (green → straw), giving a dense look without extra geometry

## Field Rendering

Fields are variable-size and each tile has its own growth state, so they are built from modular pieces assembled programmatically.

### Modular Components

| Piece | Description | Notes |
|-------|-------------|-------|
| Soil tile | 1x1 inner field tile | Flat, can be one scaled plane per field |
| Crop mesh | Growing crop on a tile, one per crop type | Height + color driven by growth value in the shader |
| Fence segment | 1-tile-long border piece | |
| Fence corner | Corner border piece | |
| Gate | The field's access point — entry for workers/vehicles, harvest pile is dropped here | Gap in fence with posts |

### Assembly Logic

When a field is placed:
1. For each tile in field dimensions: place soil tile
2. Along edges: place fence segments (rotated to face outward)
3. At corners: place fence corners
4. Place the gate on the edge chosen as the field's access point (default: closest to the nearest road)

### Per-Tile Growth Rendering

Each tile in a field has its own growth value (0.0 → 1.0) because workers/tractors process tiles sequentially — first rows start growing before last rows are seeded.

**Implementation:** MultiMeshInstance3D with per-instance custom data:
- One MultiMesh for all crop tiles in a field — single draw call
- Each instance's custom data holds its growth value (float)
- A shader reads the value and adjusts height + color per tile

```
# Per-tile update (GDScript)
multimesh.set_instance_custom_data(tile_index, Color(growth_value, 0, 0, 0))

# Shader
void vertex() {
    float growth = INSTANCE_CUSTOM.r;
    VERTEX.y *= growth;  // scale crop height by growth
}

void fragment() {
    float growth = INSTANCE_CUSTOM.r;
    // Interpolate color: light green (young) → dark green (mid) → golden (mature)
    ALBEDO = mix(young_color, mature_color, growth);
}
```

### Continuous Growth (no visible steps)

Growth must look **gradual**, never jump between discrete models. Each crop has **one mesh authored at full growth**; the shader derives every intermediate state from the per-tile growth value:

- **Part masks** are baked into vertex color channels when exporting from Blender: e.g. R = leaf, G = stalk, B = ear, A = height ratio of the vertex within its plant (0 at the ground, 1 at the tip)
- **Leaves** grow first (length scales with growth up to ~0.5), **stalks** rise from ~0.3, **ears** scale in from ~0.55
- **Color** is interpolated in the shader (young green → green → yellow-green → gold) instead of picking palette swatches — palette colors are only the authoring reference
- Small per-instance random offset (±0.03) softens tile borders
- Growth value is updated continuously by the simulation (or interpolated between simulation ticks) — no stage thresholds in rendering

The Blender style exploration (`art/blender/style_exploration.blend`) shows this with a parametric wheat tile built at 10 growth values (`WheatGrowthStrip`) and a field with a continuous seeding gradient.

**Wheat tile structure** (validated in style exploration): 5 rows per 3m tile, each row = 9 individual plants with 3 leaves (fading out when ripening), 4 stalks and 4 ears — no solid "canopy" volumes (tried and rejected, they read as lumps). ~2500 faces at full growth — too heavy for mega fields, so far zoom needs a **LOD** (fewer plants, ears only; target ~300 faces per tile).

### Visual Growth Reference (continuous, not discrete stages)

| Growth Value | Visual |
|-------------|--------|
| — | Bare soil (no crop mesh) |
| — | Cultivated — furrowed soil (field state, not growth) |
| 0.1-0.2 | Seeded — soil with tiny green dots |
| 0.2-0.5 | Growing — short to medium green crop |
| 0.5-1.0 | Maturing — tall crop, color shifts toward harvest color |
| 1.0 | Ready to harvest — full height, golden/mature color |
| Harvested | Stubble — short brown stalks (separate state) |

The gradient effect is visible as a tractor works across the field — seeded rows start growing while the tractor is still seeding the rest. Same for harvesting: combine passes through and rows switch to stubble behind it.

### Performance Notes

- MultiMesh handles thousands of instances efficiently (mega field = 64x64 = 4096 tiles, well within limits)
- One MultiMesh per field for crops, separate MultiMesh for fence perimeter
- Soil tiles can be a single scaled plane per field (no per-tile needed if soil is uniform)
- Custom data updates at simulation tick rate (growth is continuous); batch updates per field

## Ground & Grass

Grass must not add geometry to the scene:
- **Ground** is a flat plane per chunk; color variation (soft patches of slightly different greens, subtle facet-like noise) comes from the **ground shader** using world-space noise — no extra polygons
- **Tufts and small flowers** are visual sugar only: either painted into the ground shader (texture/noise-driven decals) or a **MultiMesh** that exists only in chunks near the camera and fades out with zoom — decided during implementation, shader-first
- Blender style exploration fakes this with a faceted ground mesh and scattered tuft instances purely for the renders

## Natural Trees

Also rendered with MultiMeshInstance3D:
- Per-instance custom data for growth stage (sapling → small → full)
- Shader scales height/width by growth value
- Same approach as crops but slower growth cycle

## Tools
- **Modeling**: Blender (via Blender MCP) → export as GLB
- **Temporary stand-ins**: Godot built-in meshes, only until a model exists

## Art Guidelines
- Keep poly counts low — the charm is in simplicity
- Consistent scale: 1 grid tile = 3m (Godot units = meters)
- Every model tested in the game camera (angled ortho, several rotations) before it's considered done
