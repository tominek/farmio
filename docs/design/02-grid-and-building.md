# Grid & Building System

## Grid

- World is divided into a uniform grid — **1 tile = 3m x 3m**
- Buildings snap to grid on placement
- Some buildings occupy multiple tiles (e.g., a barn might be 3x2)
- Terrain is flat grass (no elevation, no terrain variation for now)
- Fertility / soil types can be added later as a progression mechanic

## Natural Environment

The world starts with natural objects scattered across the map:

- **Natural trees** — spawn across the map at game start
- Trees **slowly regrow** on unoccupied tiles outside the farm area (edges of the map, unused land)
- This means the player always has a renewable source of free wood — chop trees, they grow back over time
- Future: bushes, stones as additional clearable obstacles

### Clearing
- Any placement (field, building, road) on tiles with natural objects requires **clearing first**
- Workers chop trees / clear debris as tasks before construction begins
- Cleared wood goes to the nearest Storage Barn
- Open grassland = instant placement, forested area = clearing phase + free wood

Natural trees serve three purposes:
1. **Bankruptcy safety net** — always something to chop and sell
2. **Early wood income** — before the player has a Tree Farm
3. **Land clearing as gameplay** — expanding the farm feels physical and earned

## Building Placement Flow

1. Player opens the build menu (hotkey or UI button)
2. Selects a building category, then a specific building
3. Ghost preview shows on the grid, follows cursor
4. R to rotate (90° increments — 0°, 90°, 180°, 270°)
5. Click to place:
   - **Clear land:** Instant construction if all tiles are clear
   - **Obstructed land:** Area marked as "pending construction" (ghost outline), clearing tasks generated for workers. Once all natural objects are removed, construction completes automatically.
6. Building starts generating tasks for workers as needed

Cleared wood from natural trees goes to the nearest Storage Barn — free early-game resources.

## Rotation

- All buildings support 4-way rotation (90° increments)
- Rotation affects input/output sides where relevant (e.g., a mill might take input from the left and output to the right)
- Rotation preview shown during placement ghost

## Roads

- Roads are placed on grid tiles like buildings
- Placed via drag (hold click and drag to paint multiple road tiles at once)
- Roads **block** building placement — must demolish the road first
- Workers and vehicles move faster on roads vs. grass
- Road types: Dirt (free), Gravel, Cobblestone, Asphalt, Concrete (see Transport doc for details)
- Roads have no assigned worker — they're passive infrastructure

## Demolition

- Player can demolish any building or road
- **Full material refund** on demolition (configurable for future difficulty settings)
- Demolition is instant
- Frees up the grid tiles

## Building States

- **Active**: Has pending or in-progress tasks, workers come and go as needed
- **Idle**: No tasks needed right now (e.g., crops are growing, mill has no input)
- **Disabled**: Manually turned off by the player — stops generating tasks entirely

## Building Upgrades

Buildings have two independent progression axes, but not all building types use both:

### 1. Size Variants (separate buildings, unlocked via research)

Different sizes of the same building type exist as separate entries in the build menu. Bigger variants are unlocked through the tech tree.

**Fields:**
Fields are **variable size** — the player draws them freely on the grid (click and drag). Each tier unlocks a larger maximum area while enforcing a minimum dimension to prevent unrealistic shapes.

| Tier | Max Area | Min Dimension | Max Dimension | Machines | Unlocked |
|------|----------|---------------|---------------|----------|----------|
| Small | 256 tiles (e.g. 16x16) | 4 tiles (12m) | 16 tiles (48m) | Not required | Start |
| Medium | 1024 tiles (e.g. 32x32) | 8 tiles (24m) | 32 tiles (96m) | Recommended | Early-Mid |
| Large | 2304 tiles (e.g. 48x48) | 12 tiles (36m) | 48 tiles (144m) | **Required** | Mid-Late |
| Mega | 4096 tiles (e.g. 64x64) | 16 tiles (48m) | 64 tiles (192m) | **Required** | Late |

- Player draws any rectangle within the tier's constraints (e.g., a Medium field could be 16x32, 20x24, 32x32, etc.)
- Min dimension prevents degenerate shapes (no 1x1024 strip fields)
- Unlocking a tier raises the max area and max dimension — player can build any size up to that limit
- Sizes are subject to playtesting and tuning

Small fields are the early game workhorse — no machines needed. Medium fields push the player toward buying first machines. Large and Mega fields are gated behind equipment ownership — workers won't even attempt the tasks without appropriate machines in the garage.

**Processing buildings:**
| Variant | Size | Speed | Notes |
|---------|------|-------|-------|
| Hand Mill | 2x2 | Slow | Starting tier, manual grinding |
| Water Mill | 3x3 | Medium | Unlocked mid-game |
| Industrial Mill | 3x3 | Fast | Late-game, high throughput |

Same pattern for Bakery, Sugar Mill, etc. — tiered variants with better speed/capacity.

### 2. In-Place Quality Upgrades (processing & utility buildings only)

Click a placed building → "Upgrade" button → pay cost → building improves without changing its grid footprint.

**Applies to:**
- **Processing buildings** (Mill, Bakery, etc.): Faster throughput, reduced waste — represents upgrading the equipment inside
- **Storage**: Increased capacity — better shelving, organization
**Does NOT apply to:**
- **Fields** — a field is just dirt. Yield improvements come from inputs and infrastructure (see below)
- **Roads** — upgrade by placing a higher tier over existing road (no demolish needed)

Each upgradeable building has multiple levels (e.g., Level 1 → 2 → 3). Cost increases per level. Visual change on upgrade to reflect better equipment.

### Field Yield Improvements

Fields don't upgrade directly. Instead, yield and efficiency improve through:

- **Better seeds**: Unlocked via research tree, selected when planting
- **Fertilizer**: A resource (produced or bought) applied during the growth phase
- **Pest spraying**: A task during the growth phase, requires spray resource
- **Better equipment**: Workers with tractors/precision seeders work faster and waste less

This means field productivity is emergent — it comes from the player's overall operation, not from clicking an upgrade button.

## Crop Field Work Cycle

A field generates tasks in sequence. Workers pick them up from the task queue:

```
Cultivate → Seed → [growth phase] → Harvest
```

The growth phase is not idle — tasks are generated at specific growth milestones:

| Growth % | Task | Effect if skipped |
|----------|------|-------------------|
| ~20% | Fertilize | Reduced yield |
| ~50% | Spray (herbicide/pesticide) | Risk of crop damage, reduced yield |

- Skipping growth-phase tasks doesn't kill the crop, but **reduces yield** — rewarding players who have enough workers to tend their fields
- Initially, skipping simply reduces yield. Future plans: varied consequences (pest spread to neighboring fields, weed overgrowth requiring extra cultivation next cycle, visual crop quality differences, lower sell price for damaged goods)
- Between milestone tasks, the field generates no work — workers are free for other jobs
- After harvest, the cycle resets

Note: Fields are rain-fed — no watering required. Water management is reserved for **Greenhouses** (see Future Ideas), which offer higher yields and year-round growing but require water infrastructure and more labor.

## Building Types (initial set)

### Production
| Building | Size | Function | Cost |
|----------|------|----------|------|
| Crop Field | Variable (see field tiers) | Grows a selected crop type | Money |
| Tree Farm | Variable (similar to fields) | Grows trees for wood | Money |

### Processing (upgradeable in-place)
| Building | Size | Real Size | Function | Cost |
|----------|------|-----------|----------|------|
| Hand Mill | 2x2 | 6m x 6m | Grinds grain into flour (slow) | Money |
| Water Mill | 3x3 | 9m x 9m | Grinds grain into flour (medium speed) | Money + planks |
| Bakery | 3x3 | 9m x 9m | Bakes flour into bread | Money + planks |
| Sawmill | 3x2 | 9m x 6m | Processes wood into planks | Money |
| Sugar Mill | 3x3 | 9m x 9m | Processes sugar beet into sugar | Money + planks |
| Pasta Maker | 2x2 | 6m x 6m | Processes flour into pasta | Money + planks |

### Storage & Logistics (upgradeable in-place)
| Building | Size | Real Size | Function |
|----------|------|-----------|----------|
| Storage Barn | 4x3 | 12m x 9m | Stores harvested crops and processed goods | Money |
| Silo | 2x2 | 6m x 6m | Specialized grain/bulk storage, high capacity | Money + planks |
| Supply Storage | 2x2 | 6m x 6m | Stores one resource type (seeds, fertilizer, or spray), set on placement | Money |
| Garage | 5x4 | 15m x 12m | Stores vehicles and attachments, workers pick up equipment here | Money |

### Infrastructure
| Building | Size | Function |
|----------|------|----------|
| Dirt Road | 1x1 | Free, slow speed bonus |
| Gravel Road | 1x1 | Cheap, medium speed bonus |
| Cobblestone Road | 1x1 | Medium cost, good speed bonus |
| Asphalt Road | 1x1 | Expensive, fast |
| Concrete Road | 1x1 | Very expensive, fastest + heavy vehicle bonus |

## Open Questions

- What's the max upgrade level for in-place upgrades? (3 levels? 5?)
- ~~Grid tile size~~ — **3m x 3m per tile.** All sizes subject to playtesting.
- Should there be a "blueprint" system for saving and stamping building layouts?
- Can multiple crop types be grown on the same field, or one type per field?
