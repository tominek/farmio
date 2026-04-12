# Art Pipeline

## Approach: Gameplay First, Art Later

All visuals start as Godot built-in primitives (BoxMesh, CylinderMesh, CSG nodes). The goal is to prove the gameplay loop with placeholder art before investing time in polished models.

## Phases

### Phase 1 — Grey-box (current)
- Buildings: colored boxes/cylinders with different colors per type
- Workers: small capsules or cylinders
- Vehicles (pickups, tractors, combines): colored boxes on smaller box wheels
- Crops: small boxes/cones scaled by growth value (see Field Rendering below)
- Roads: flat darker planes
- Focus: gameplay, systems, fun factor

### Phase 2 — Basic Models
- Replace placeholders with simple low-poly Blender models
- Flat-color materials (no textures yet)
- Basic shape language: round = natural/organic, boxy = man-made
- Recognizable silhouettes from top-down view

### Phase 3 — Polish
- Proper textures / color palettes
- Worker and vehicle animations
- Particle effects (dust, smoke from bakery, etc.)
- Seasonal visual variations (if implemented)

## Field Rendering

Fields are variable-size and each tile has its own growth state, so they are built from modular pieces assembled programmatically.

### Modular Components

| Piece | Description | Phase 1 (grey-box) |
|-------|-------------|-------------------|
| Soil tile | 1x1 inner field tile | Dark brown flat box |
| Crop mesh | Growing crop on a tile | Green box/cone, height driven by growth value |
| Fence segment | 1-tile-long border piece | Thin tall box |
| Fence corner | Corner border piece | Thin tall box, L-shaped |
| Gate | Entry point for workers/vehicles | Gap in fence (no mesh) |

### Assembly Logic

When a field is placed:
1. For each tile in field dimensions: place soil tile
2. Along edges: place fence segments (rotated to face outward)
3. At corners: place fence corners
4. Pick one edge (closest to nearest road): replace fence with gate

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

### Visual Growth Stages

| Growth Value | Visual |
|-------------|--------|
| 0.0 | Bare soil (no crop mesh) |
| 0.0-0.1 | Cultivated — furrowed soil |
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
- Custom data updates only when a tile's growth stage changes, not every frame

## Natural Trees

Also rendered with MultiMeshInstance3D:
- Per-instance custom data for growth stage (sapling → small → full)
- Shader scales height/width by growth value
- Same approach as crops but slower growth cycle

## Tools
- **Prototyping**: Godot built-in meshes + CSG nodes
- **Final models**: Blender → export as glTF/GLB
- **Placeholders if needed**: Kenney free asset packs

## Art Guidelines (for when we get to Phase 2+)
- Keep poly counts low — the charm is in simplicity
- Readable from top-down at default zoom: distinct silhouettes and colors matter more than detail
- Consistent scale: 1 grid tile = 3m (map to appropriate Godot units)
- Color-code building categories for quick visual identification
