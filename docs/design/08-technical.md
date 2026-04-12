# Technical Design

## Engine & Setup

- **Engine**: Godot 4.x
- **Language**: GDScript (fast iteration, native to Godot)
- **Rendering**: 3D with orthographic camera (fixed angle, no rotation)
- **Style**: Low-poly 3D models (Phase 1: Godot primitive meshes as placeholders)

## Scale & Units

- 1 grid tile = 3m x 3m
- All vehicles occupy 1 tile wide for pathfinding and collision, regardless of visual model size
- Vehicle models can be visually slightly larger/smaller than 1 tile for variety — logic stays 1 tile

## Scene Architecture

```
Main
├── World
│   ├── Grid (custom grid manager)
│   │   ├── Terrain (grass base)
│   │   └── NaturalObjects (trees, future: bushes, stones)
│   ├── Roads (road tiles with type and direction data)
│   ├── Buildings
│   │   ├── Fields (variable size, crop state per tile)
│   │   ├── TreeFarms (variable size, tree growth state)
│   │   ├── Processing (mills, bakeries, sawmill, etc.)
│   │   ├── Storage (barns, silos, supply storage)
│   │   └── Garage (vehicle/equipment inventory)
│   ├── Vehicles
│   │   ├── Tractors (+ attachment data)
│   │   ├── Combines
│   │   ├── PickupTrucks (+ trailer data)
│   │   └── Wheelbarrows
│   ├── Workers (pathfinding agents)
│   └── Dealer (off-map location)
├── Camera (orthographic, fixed rotation, smooth zoom)
├── UI (CanvasLayer)
│   ├── HUD (money, planks, workers, game speed)
│   ├── BuildMenu
│   ├── BuildingInfoPanel
│   ├── WorkerInfoPanel
│   ├── TaskQueuePanel
│   ├── DealerPanel
│   ├── EquipmentPanel
│   ├── TechTreePanel
│   ├── PriorityPanel
│   ├── Notifications (toasts + history log)
│   └── SettingsMenu
└── Systems (autoloads / singletons)
	├── GridManager
	├── TaskQueue
	├── ResearchManager
	└── EconomyManager
```

## Key Systems

### Grid Manager
- Custom grid system (not GridMap — we need variable-size fields and per-tile data)
- Tracks per tile: occupied/free, building reference, road type/direction, natural objects
- Handles placement validation (enough space? obstructions? within field tier limits?)
- Triggers clearing tasks when placing on tiles with natural objects

### Task Queue
- Global priority queue holding all pending tasks
- Each building registers tasks when work is needed
- Priority sorting: category priority → per-building priority → distance → task age
- Equipment filtering: skip tasks that need unavailable equipment
- Workers poll the queue when they become free

### Pathfinding
- Godot's NavigationServer3D for worker/vehicle movement
- Navigation mesh updated when buildings/roads are placed or demolished
- **Weighted movement cost per tile type:**
  - Grass: highest cost
  - Dirt Road → Gravel → Cobblestone → Asphalt → Concrete: decreasing cost
- Path caching: recalculate only when grid changes, not every frame
- Field vehicles (tractors, combines) pathfind on field tiles directly
- Road vehicles (pickups) pathfind on road network

### Worker AI
- State machine per worker:
  ```
  Idle → Check Task Queue → Pick Task → Need Equipment?
    → Yes: Walk to Garage → Pick up equipment → Walk to task location
    → No: Walk to task location
  → Perform task → Need to deliver output?
    → Yes: Carry/drive to storage → Drop off
    → No: Return equipment to garage (if any)
  → Back to Idle
  ```
- Workers pick up consumables (seeds, fertilizer, spray) from nearest Supply Storage before heading to field
- Dealer trips: load pickup at storage → drive to Dealer → sell/buy → drive back → unload

### Vehicle System
- Vehicles stored in Garage buildings with inventory tracking
- Equipment contention: if no tractor available, task stays in queue
- Attachment system: tractor + one attachment, pickup + optional trailer
- Speed/capacity modified by vehicle type, attachment, load weight, and road surface

### Building System
- Base Building class with common properties (grid position, size, rotation, state, upgrade level)
- Specialized subclasses:
  - **Field**: crop type, growth progress, tile-by-tile state (for visual crop growth), variable dimensions
  - **TreeFarm**: similar to field but different growth cycle (plant → slow grow → harvest → replant)
  - **Processing**: input/output resource slots, processing speed, recipe
  - **Storage**: resource inventory, capacity, accepted resource type (for Supply Storage)
  - **Garage**: vehicle/equipment inventory (no capacity limit)
- Buildings generate tasks appropriate to their type and state
- In-place upgrades modify building stats without changing footprint

### Resource System
- Per-building storage: each building has input/output slots with limited buffer
- Overflow goes to nearest Storage Barn / Silo with space
- Resources are physical: they must be transported between buildings by workers/vehicles
- Resource types: crops (potatoes, wheat, corn, sugar beet), wood, planks, flour, bread, pasta, sugar, seeds, fertilizer, spray

### Road System
- Per-tile road data: type (dirt/gravel/cobblestone/asphalt/concrete), direction (one-way or two-way)
- Auto-connecting intersections: road tiles visually connect when adjacent
- Right-of-way at intersections: first-come-first-served, future: traffic signs
- In-place upgrades: place higher-tier road over existing without demolish

### Natural Environment
- Trees spawn at world generation on random tiles
- Slow regrowth on unoccupied tiles outside farm area
- Clearing generates tasks: workers chop trees → wood goes to storage
- Construction blocked on occupied tiles until cleared

### Research / Tech Tree
- Tree of unlockable items stored as data (JSON or Resource)
- Each node: name, cost, prerequisites, what it unlocks
- Instant unlock on purchase
- Full tree visible from start

### Economy
- Money: earned from Dealer sales, spent on buildings, workers, vehicles, supplies, research
- Planks: earned from Sawmill, spent on mid/late-game buildings
- Auto-sell: per-resource threshold configuration, generates transport tasks
- Worker cost: first 2-3 free, then scaling one-time hire fee

### Save System
- Serialize all game state:
  - Grid state (tiles, natural objects)
  - All buildings (type, position, rotation, upgrade level, inventory, crop state)
  - All workers (position, current task, restrictions)
  - All vehicles (type, attachments, location, status)
  - Road network
  - Research progress
  - Economy state (money, auto-sell config)
  - Task queue state
- Format: Godot's built-in Resource system or JSON
- Autosave on interval

## Performance Considerations

- Many workers + vehicles moving simultaneously — keep pathfinding efficient
- Path caching: only recalculate when grid topology changes
- LOD: switch to simplified models or schematic icons at far zoom
- Large fields: per-tile crop growth with MultiMeshInstance3D + per-instance custom data + shader. One draw call per field regardless of size. Custom data updates only on growth stage changes, not every frame.
- Navigation mesh updates should be batched (don't rebuild on every single tile change during drag-placement)

## Resolved Questions

- ~~Language~~ — **GDScript.** Can optimize hot paths with C# or GDExtension later if needed.
- ~~Day/night cycle~~ — **Visual only.** Lighting changes over time for atmosphere, but farm operates 24/7 — workers don't sleep, crops grow continuously. Night is darker but gameplay doesn't pause or slow.
- ~~Dealer placement~~ — **Random position** on world generation, so each game plays a bit differently. Distance from farm may be configurable via difficulty settings later.
- ~~World generation~~ — See World Generation section below.
- ~~Tree regrowth~~ — **Visible growth.** Saplings appear on empty tiles and grow through stages over time (sapling → small tree → full tree). Gives the world a living feel.

## World Generation

### New Game Screen
Before starting a game, the player configures:

| Setting | Options | Notes |
|---------|---------|-------|
| **Map Size** | Small / Medium / Large / Huge | e.g., 256² / 512² / 1024² / 2048² tiles |
| **Seed** | Text/number input + random button | Determines all procedural placement |

Future settings (parked for now):
- Vegetation density (sparse → dense)
- Open area amount
- Ponds / rivers
- Dealer distance

### Map Preview
- After setting size and seed, a **schematic preview** is generated and shown
- Top-down 2D view using colored blocks: green = trees, light green = open grass, brown = dirt road, icon = Dealer, icon = farm start
- Player can re-roll seed or tweak settings until they like the layout
- Preview generates quickly (just noise + placement logic, no 3D rendering)
- Click "Start Game" to begin with that seed

### Generation Steps
1. Create flat grass terrain at the chosen map size
2. Generate tree clusters using noise (Perlin/Simplex) — creates natural-looking dense and sparse areas
3. Place Dealer at a random position
4. Place pickup point (farm origin) with starting Garage + Storage Barn
5. Generate winding dirt road between them — pathfind around dense vegetation, creating organic turns
6. Ensure a clear area around the farm origin (enough open grass for first fields)
7. Map edges: thick band of **unclearable dense forest** — can't be chopped or built on. Serves as a natural boundary. Future: mixed boundaries (rivers, hills) for visual variety.

### Seed Reproducibility
- Same seed + same settings = identical map every time
- Seeds can be shared between players for identical starting conditions

## Debug Menu

In-game GUI panel (not a CLI) toggled via F12:

- **Resources**: Add/remove money, planks, any resource
- **Workers**: Spawn workers instantly (free)
- **Vehicles**: Spawn any vehicle/attachment
- **Buildings**: Instant place any building (ignore cost and research)
- **Research**: Unlock all / unlock specific items
- **Time**: Speed controls beyond 3x (5x, 10x, 50x) for testing growth cycles and long-term balance
- **Field**: Force crop growth to specific % / instant harvest
- **Teleport**: Jump camera to Dealer / specific buildings
- **Info**: Show pathfinding overlay, task queue debug, tile data on hover

### Tweakable Constants Panel

A separate tab/section within the debug menu that exposes **all game balance constants** as live-editable sliders/inputs:

- **Crop growth times** (per crop type)
- **Yield amounts** (base, fertilized, sprayed bonuses)
- **Worker speed**, work speed
- **Vehicle speeds**, carry capacities, trailer weight limits
- **Road speed multipliers** (per road type)
- **Building costs** (money + planks per building)
- **Worker hiring cost curve**
- **Processing speeds** (per building type and upgrade level)
- **Dealer prices** (buy and sell per resource)
- **Research costs**
- **Tree regrowth rate**
- **Natural tree density at world gen**
- **Dealer distance range**

Changes apply immediately in-game — no restart needed. Values stored in a single config resource file so they're easy to manage. This panel evolves into the **difficulty settings menu** for release, where presets (Easy/Normal/Hard) map to curated combinations of these values.

Should be disabled/stripped from release builds (or locked behind a developer flag). Can be toggled to stay available in early access for community testing if useful.

## Open Questions

- Mod support? (way later if ever)
