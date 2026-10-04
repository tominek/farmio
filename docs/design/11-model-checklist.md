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

## Phase 2 and 3 models — done, exported

Everything below is built by scripts in `art/blender/scripts/` (`p2_animals.py`, `p2_trees.py`, `p2_vehicles.py`, `p2_buildings.py`, `p2_resources.py`, `p2_roads.py`) and exported to `assets/models/`. Rebuild without the Blender UI:
`Blender -b art/blender/style_exploration.blend --python art/blender/scripts/p2_run.py -- animals trees vehicles buildings resources roads save` (`p0_helpers.py` restores the Builder helpers after a Blender restart). The exports also write `scripts/tools/model_showcase.json`; **all of it can be seen in `scenes/model_showcase.tscn`** (animals in every animation state). Colour variants are palette swaps of one base model (`_<colour>` / `_b`). Not wired into the game yet.

### Buildings (front / access side = Blender +Y, origin at the footprint centre)
- [x] **Tree Farm** — `tile_tree_farm` (nursery soil per tile, trees from the tree models), `tile_orchard`, `building_tool_shed` (1x1)
- [x] **Hand Mill** (2x2) — timber hut with a quern under the porch (`building_hand_mill`)
- [x] **Sawmill** (3x2) — open shed, saw bench, logs and planks (`building_sawmill`)
- [x] **Water Mill** (3x3) — mill house on the two land columns, undershot wheel in the river on the east column (Blender +X), reaching ~1.1 m below ground into the river bed (`building_water_mill`)
- [x] **River and ponds** — generated in Godot (`scripts/view/water_view.gd`): grass cut away by a smoothed water mask (`ground.gdshader`), sunken bed height field (`water_bed.gdshader`), water surface with depth tint, shore rim and ripples (`water.gdshader`); bridges are the `bridge_*` models
- [x] **Wide road curves** for every road surface — `road_<surface>_twoway_curve_wide`: one model over 2x2 blocks (12 x 12 m, axis radius 9 m), entering at the south edge of the south-west block and leaving at the east edge of the north-east block. `World.wide_curves()` makes one of a corner with a straight block before and after it when the tiles the arc would cross on the inside of the bend are free (no road, building, field, water or tree); otherwise the small corner piece stays. The arc covers three tiles of the inside block (they can't be built on) and leaves the outer tile of the elbow block as grass (it can be). While something stands on that free corner, road changes that would turn the curve back into a small corner are refused. The generated start road pays extra for every bend, so it runs straight and its bends can become wide curves
- [x] **Bridges** for every road surface — `bridge_<dirt|gravel|cobble|asphalt|concrete>_<twoway|oneway>` (6 x 6 m / 3 x 3 m): repeatable pieces with the road along Y, deck flush with the road, railings / parapets, pier down into the river bed; a crossing is a row of them (log bridge, timber bridge on a stone pier, stone bridge, concrete bridge with guard rails or parapets)
- [x] **Bakery** (3x3) — shop front, awning, brick oven and chimney (`building_bakery`)
- [x] **Sugar Mill** (3x3) — brick factory, chimney, beet bunker and conveyor (`building_sugar_mill`)
- [x] **Pasta Maker** (2x2) — workshop with pasta drying racks (`building_pasta_maker`)
- [x] **Industrial Mill** (3x3) — concrete mill, two silos, elevator (`building_industrial_mill`)
- [x] **Processing building levels** — every processing building has `_l2` (lean-to with crates and sacks) and `_l3` (plus a grain bin and solar panel), and a colour variant `_b`
- [x] **Silo** (2x2) — `building_silo`, `_l2` (taller, ladder cage), `_l3` (tallest, bucket elevator)
- [x] **Supply Storage** (2x2) — `building_supply_storage` (timber), `_metal`, `_b`; blank label board above the roller door at Blender (0, 2.02, 3.25) (metal: z 2.95), 1.8 x 0.62 m — put a small resource model or icon there in the game
- [x] **Storage Barn levels** — `building_storage_barn_l2` (stone ground floor, hay-loft hoist, lean-to), `_l3` (brick barn, two gates, roof vents, covered dock)
- [x] **Loading bay** (2x1, 6 x 3 m) — `building_loading_bay` (concrete), `_gravel`, `_asphalt`; dock edge towards the building (-Y)

### Animal buildings (new, for the animal ideas in Future Ideas)
- [x] **Cowshed / dairy barn** (4x3) with feeding fence and milk cans — `building_cowshed`, `_b`
- [x] **Sheep / goat shed** (3x2) with a fenced yard — `building_stock_shed`, `_b`
- [x] **Chicken coop** (2x2) with nest boxes and a wire run — `building_chicken_coop`, `_b`

### Vehicles (origin at the body centre)
- [x] **Basic Tractor** — green / red / blue / orange (`vehicle_tractor_basic_*`), hitch at Blender (0, -1.5, 0.5)
- [x] **Advanced Tractor** — green / red / blue / yellow (`vehicle_tractor_advanced_*`), hitch at (0, -2.35, 0.6)
- [x] **Basic Combine** (4.5 m header) and **Large Combine** (7.5 m header) — green / red / yellow
- [x] **Heavy Pickup** — crew cab, dual rear wheels; blue / red / white / green / grey
- [x] **Light Pickup colours** — `vehicle_pickup_light_red / _white / _green / _grey`

### Trailers & attachments (origin on the ground under the hitch point, body towards -Y)
- [x] **Small / Medium / Large Trailer** (1 / 2 / 3 axles) — red / green / blue
- [x] **Grain Cart** — red / green / blue
- [x] **Basic Plow** (3 bottoms), **Deep Plow** (5 bottoms, discs) — red / blue
- [x] **Basic Seeder** (3 m drill), **Precision Seeder** (6 row units) — red / green
- [x] **Basic Sprayer** (mounted, 6 m boom), **Boom Sprayer** (trailed, 12 m boom) — red / green
- [x] **Fertilizer Spreader** (twin disc) — red / blue / orange

### Resources — `item_` one unit on the ground, `carry_` held by a worker, `cargo_` one load on a pickup bed / trailer (fits 1.6 x 1.4 m), `pile_` stock at a building (~2.2 x 2.2 m)
- [x] Planks (`cargo_`, `pile_`; `carry_planks` from Phase 1), flour, sugar (sacks), bread (loaf, crates), pasta (cartons)
- [x] Seeds and fertilizer (sacks + bulk bag), spray (20 l canister, 1000 l IBC tank)
- [x] Road materials: gravel, asphalt (heaps), cobblestones (pallets of setts), concrete (cement bags, precast slabs)
- [x] Animal goods: milk and goat milk (cans, `cargo_milk_tank`), wool (fleece, bales), eggs (tray, basket, crates), manure (`tool_wheelbarrow_manure`, heap, dung heap)
- [x] Feed / crop residues: straw and hay (small bales, stacks, round bales)
- [x] Fruit: apples, pears, plums, apricots in crates (`carry_crate_*`, `cargo_*`, `pile_*`)

### Roads
- [x] **Cobblestone**, **Asphalt** (centre dashes, kerbs, edge lines) and **Concrete** (3 m panels with joints) — same pieces and outlines as dirt / gravel (`road_<surface>_twoway_<piece>`, `_oneway_straight / _corner`)

### Animals — part rigs for procedural animation (`scripts/view/animal_figure.gd`: idle, walk, eat, sleep)
Parts `body`, `head` (pivot at the neck), `tail`, legs `leg_fl / fr / bl / br` (birds `leg_l / r`), pivots at the top of each leg.
- [x] **Cows** — holstein / pied (red-pied) / brown; **Bulls** — black / pied / cream; **Calves** — holstein / pied / brown
- [x] **Sheep** — white / blackface / brown; **Rams** (curled horns) and **Lambs** in the same colours
- [x] **Goats** — white / brown (chamois) / pied; **Billy goats** (long horns, beard) and **Kids** in the same colours
- [x] **Hens** — brown / white / black; **Roosters** — red / white / black; **Chicks** — yellow / brown

### Trees (stages `_sapling`, `_small`, `_full`; fruit trees also `_blossom`, `_fruit`)
- [x] Forest: **Scots pine**, **spruce**, **oak**, **beech**, **birch**
- [x] Orchard: **apple**, **pear**, **plum**, **apricot** (saplings with a stake and tree disc)

---

## Polish (later)

- [x] **Worker animations** — workers are split into parts (`worker_*_rig`: body, arms, legs with pivots at shoulders / hips, made from the base models in Blender, collection `worker_rigs`) and animated procedurally in `scripts/view/worker_figure.gd`: walk, carry, push a wheelbarrow, chop (axe), build (hammer), cultivate (hoe), sow (seed sack), harvest (sickle), pick up. Held tools `tool_axe`, `tool_hammer`, `tool_hoe`, `tool_sickle` (grip at the origin, handle down). All states side by side: `scenes/worker_showcase.tscn`. The old pose models are removed
- [ ] **Worker animations at workplaces** — for now every processing task reuses the build (hammer) animation (`WorkerFigure.action_of`: `Task.Kind.PROCESS` → `Action.BUILD`). Wanted: Hand Mill: turning the quern crank under the porch; Water Mill: pouring grain into the hopper, carrying sacks inside; Sawmill: pushing a log along the saw bench; later Bakery, Sugar Mill, Pasta Maker and the animal buildings (milking, shearing, collecting eggs). The worker should stand at the actual spot of the model (quern, saw bench), not just on the access tile, and face it
- Vehicle animations (wheels, suspension) and driving workers visible in the cab
- Particle effects (dust behind vehicles, bakery smoke, chopping chips)
- More cosmetic worker variety
