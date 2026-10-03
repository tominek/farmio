# Art Pipeline

## Approach: Low-Poly from the Start

Models are created in **Blender via the Blender MCP** (Claude builds and iterates on models through Blender's Python API, the user reviews renders and approves). Since a simple low-poly model is almost as fast to make this way as a grey-box, the game uses real low-poly models from the start. Godot primitives are only a temporary stand-in for things that don't have a model yet.

## Phases

### Phase 0 — Style Exploration (before any gameplay code)
- Build a handful of representative models in Blender (e.g. Storage Barn, worker, tree, pickup, a field with crops)
- Iterate until the style is settled: proportions, level of detail, palette, readability from the game camera
- Outcome: a written **style guide** + **palette texture** + **export conventions** (sections below get filled in)

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

## Visual Style

- **Low-poly, flat-shaded**, colors from a single shared **palette texture** (UVs point into palette swatches, Kenney/Islanders-like)
- All models share one material → consistent look and good batching
- Readable from the angled orthographic camera at default zoom: distinct silhouettes and colors matter more than detail
- Color-code building categories for quick visual identification
- Style details (proportions, palette, outlines/no outlines, lighting) — **to be decided in Phase 0**

## Export Conventions

To be finalized in Phase 0. Starting proposal:
- Units: meters, 1 grid tile = 3m
- Buildings: origin at the center of the footprint on the ground, access point facing **-Z** (Godot forward) at rotation 0°
- Vehicles/workers: origin on the ground at the center, facing -Z
- Source `.blend` files kept in the repo (e.g. `art/blender/`), exported **GLB** in `assets/models/`
- Naming: `category_name[_variant]` (e.g. `building_storage_barn`, `worker_female`)

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
