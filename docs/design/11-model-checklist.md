# 3D Model Checklist

Scale: 1 grid tile = 3m x 3m. All models are low-poly Blender models in the shared palette style (see Art Pipeline). Sizes are footprints in tiles / meters.

The list follows the order in which things are needed by the game. `[x]` = designed in Blender (`art/blender/style_exploration.blend`, scenes `Scene` and `Phase1`, renders in `art/renders/`) — not yet exported to GLB or used in the game.

---

## Phase 0 — Style Exploration ✅

- [x] **Storage Barn** — European timber barn with half-hip tile roof (`building_storage_barn_eu`); American red barn and plastered variant kept as references
- [x] **Worker** — blocky style chosen (rounded and in-between variants rejected)
- [x] **Trees** — deciduous + conifer, matte, natural conifer green
- [x] **Light Pickup**
- [x] **Field sample** — soil, wheat with continuous growth, fence and gate
- [x] **Palette texture** — 16x16 swatches (`art/textures/palette.png`), one matte material
- [x] **Grass** — colour patches + tufts/flowers (in game: shader-first, see Art Pipeline)

---

## Phase 1 — First Playable Loop

Everything needed for: generate a map → chop trees → place a field → plant, grow, harvest by hand → haul to the barn → drive to the Dealer and sell.

### Workers
- [x] **Worker (male)** — color variants for skin tone and clothes
- [x] **Worker (female)** — color variants for skin tone and clothes
- [x] **Status indicator** — small gem above the head: green working / yellow walking / grey idle (`ui_status_*`)
- [x] **Carried goods** — sack, crate, logs, planks (`carry_*`)

### Field Components
- [x] **Soil** — bare and cultivated (furrowed) variants; potatoes use hilled ridges
- [x] **Crops** — parametric, continuous growth: wheat, potatoes (flowering, tops yellow when ripe), corn (cobs + tassel, dries tan), sugar beet (oval leaves, white crown)
- [x] **Stubble / harvested soil** — per crop
- [x] **Fence segment** and **fence corner**
- [x] **Gate** — the field's access point
- [x] **Harvest pile** — wheat, potato, corn, beet (`harvest_pile_*`)

### Buildings
- [x] **Storage Barn** (4x3 / 12m x 9m)
- [x] **Garage** (5x4 / 15m x 12m) — open-front machine shed with 3 bays, timber + tile roof (`building_garage`)
- [x] **Dealer** (4x4 / 12m x 12m) — farm supply trader, street gable with shop windows and a wheat-emblem sign, loading dock, grain silo (`building_dealer`)
- [x] **Construction site** — parametric for any footprint, 3 stages: staked out → foundation + materials → timber frame + scaffolding (`construction_site_*`). One generic sequence for now; later per building type: stages 1–2 stay shared (materials vary), the last stage becomes building-specific — cheapest: the finished model "growing" from the ground via shader with scaffolding around, hand-made intermediate stages only for showpiece buildings
- [x] **Access point marker** — yellow tile outline + arrow (`ui_access_point_marker`)

### Vehicles & Tools
- [x] **Light Pickup**
- [x] **Wheelbarrow** — empty and loaded (potatoes, grain, logs) (`tool_wheelbarrow*`)

### Roads
- [x] **Dirt road** and **Gravel road** — two-way pieces 2x2 tiles (straight, corner, T, cross, dead-end), one-way pieces 1 tile (straight with arrow, corner) (`road_*`)
- [x] **One-way arrow**
- [x] **Connection variants** — demo network in the `Phase1` scene

### Natural Environment
- [x] **Deciduous tree** — sapling / small / full
- [x] **Conifer tree** — sapling / small / full
- [x] **Tree stump**
- [x] **Log pile** (`prop_log_pile`)
- [ ] **Dense boundary forest** — reuses the full trees, placed densely (done at world generation)

### Terrain & Overlays (generated in Godot)
- [ ] Grass base (ground shader)
- [ ] Grid overlay during placement
- [ ] Placement ghost (valid/invalid tint)

---

## Phase 2 — Production Chains & Machines

### Buildings
- [ ] **Tree Farm** — rows of saplings/trees (reuses tree models)
- [ ] **Hand Mill** (2x2 / 6m x 6m)
- [ ] **Sawmill** (3x2 / 9m x 6m)
- [ ] **Water Mill** (3x3 / 9m x 9m)
- [ ] **Bakery** (3x3 / 9m x 9m)
- [ ] **Sugar Mill** (3x3 / 9m x 9m)
- [ ] **Pasta Maker** (2x2 / 6m x 6m)
- [ ] **Silo** (2x2 / 6m x 6m)
- [ ] **Supply Storage** (2x2 / 6m x 6m) — label shows the stored resource type

### Vehicles
- [ ] **Basic Tractor**
- [ ] **Basic Combine**

### Tractor Attachments
- [ ] **Basic Plow**
- [ ] **Basic Seeder**
- [ ] **Basic Sprayer**
- [ ] **Fertilizer Spreader**

### Trailers
- [ ] **Small Trailer**
- [ ] **Medium Trailer**

### Resources (cargo visuals in vehicles, piles at buildings)
- [ ] Planks, flour sacks, bread, sugar, pasta
- [ ] Seeds, fertilizer, spray
- [ ] Road materials: gravel, cobblestones, asphalt, concrete

### Roads
- [ ] **Cobblestone road**

### Loading Bay
- [ ] **Loading bay** — pull-off platform at a building's access point

---

## Phase 3 — Late Game

### Vehicles & Attachments
- [ ] **Advanced Tractor**
- [ ] **Large Combine**
- [ ] **Heavy Pickup**
- [ ] **Large Trailer**
- [ ] **Deep Plow**, **Precision Seeder**, **Boom Sprayer**
- [ ] **Grain Cart**

### Buildings
- [ ] **Industrial Mill** (3x3 / 9m x 9m)

### Roads
- [ ] **Asphalt road**
- [ ] **Concrete road**

### Upgrade Visuals (3 levels)
- [ ] **Storage Barn** levels 2 and 3
- [ ] **Silo** levels 2 and 3
- [ ] **Processing buildings** — subtle per-level changes (better equipment visible)

---

## Polish (later)

- Worker and vehicle animations (walking, carrying, chopping, driving)
- Particle effects (dust behind vehicles, bakery smoke, chopping chips)
- More cosmetic worker variety
