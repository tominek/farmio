# Resources & Production Chains

## Core Concept

Crops are grown, harvested, processed through multiple stages, and eventually sold. Longer production chains yield more profit, rewarding players who build complex setups.

## Raw Crops

| Crop | Growth Time | Notes |
|------|------------|-------|
| Potatoes | Fast | Heavy (36 kg per tile): good money only with transport (pickup by a road gate, later trailers) |
| Wheat | Medium | Bread chain staple |
| Corn | Medium | Direct sale only (processing could come later, e.g. animal feed) |
| Sugar Beet | Medium | Sugar chain |

### Crop residues (future)

What stays on the field after harvest is a resource too, not just stubble: wheat → **straw**, corn → **stover** (stalks and leaves), sugar beet → **beet leaves**, potatoes → haulm (little value). Later it can be collected (by hand on small fields, a baler on bigger ones), stored, sold at the Dealer, processed (straw bales, bedding, silage, biomass) or used as **feed for the farm's own animals**. Until then residues are simply ploughed back in. Keep the field cycle open for an optional "collect residues" step between harvest and cultivation.

## Production Chains

### Wood Chain (building material)
```
Tree Farm → [wood] → Sawmill → [planks] → Used for construction
```
Tree Farm works differently from crop fields:
- Plant saplings, trees grow slowly (longest growth time of any resource)
- Harvest = logging (felling trees, requires worker or tractor)
- Replant after harvest — no cultivate/fertilize/spray cycle, just plant new saplings
- Plan ahead: plant trees early, they'll be ready when you need planks for mid-game buildings

### Direct Sale (no processing)
```
Potatoes → Dealer (low price, fast cycle, early game income)
Corn → Dealer (medium price)
```

### Bread Chain (2 steps)
```
Wheat → Mill → [flour] → Bakery → [bread] → Dealer
```
First processing chain the player builds. Introduces the concept of multi-step production.

### Sugar Chain (2 steps)
```
Sugar Beet → Sugar Mill → [sugar] → Dealer
```
Alternative processing chain — different buildings from the bread chain.

### Flour Products (3 steps, branching)
```
Wheat → Mill → [flour] ─→ Bakery → [bread] → Dealer
						└→ Pasta Maker → [pasta] → Dealer
```
Mid-game complexity — flour becomes a shared input for multiple products. Player decides how to split output.

## Pricing Principle

- Raw crops sell for little at the Dealer
- Each processing step increases value significantly
- Longest chains = highest profit per unit
- Branching chains reward building parallel processing for the same input

### Example Price Scaling (relative)
| Product | Steps | Value |
|---------|-------|-------|
| Raw potatoes | 0 | ★ |
| Raw wheat | 0 | ★ |
| Raw wood | 0 | ★ |
| Flour | 1 | ★★ |
| Sugar | 1 | ★★ |
| Planks | 1 | ★★ |
| Bread | 2 | ★★★ |
| Pasta | 2 | ★★★ |

## Consumable Resources

Resources used during field work, purchased at the Dealer:

| Resource | Used For | Stored In |
|----------|---------|-----------|
| Seeds (per crop type) | Seeding task | Supply Storage |
| Fertilizer | Fertilize task during crop growth | Supply Storage |
| Spray | Spray task during crop growth | Supply Storage |
| Road materials (gravel, cobblestones, asphalt, concrete) | Building higher-tier roads | Storage Barn |

**Units:** crops and seeds are counted in **kg** with realistic per-tile rates (a tile is 3×3 m = 0.0009 ha): seed wheat 0.16 kg, seed potatoes 2.25 kg, corn 23 g, sugar beet 4 g per tile; yields wheat ~6 kg, potatoes ~36 kg, corn ~9 kg, sugar beet ~60 kg per tile. Wood is counted in logs (50 kg each in a vehicle). A worker carries 50 kg by hand, the Light Pickup 800 kg. Field piles of 300 kg or more are collected by the pickup when the gate is next to a road (the pile waits for it); only a smaller rest is carried by hand once the field is harvested. Fields without a road gate are emptied by hand (wheelbarrows help).

**Balance notes (measured with `scripts/tools/balance.gd`, a headless bot):** growth times wheat 4 min, potatoes 3 min, corn and sugar beet 4.5 min; a 10×10 field with 3 workers brings the first sale around minute 10. Heavy crops (potatoes 3.6 t, sugar beet 6 t per 10×10 harvest) are **deliberately demanding early**: carrying by hand or one Light Pickup (800 kg, loaded by hand) is the bottleneck, so per tile they pay more than wheat/corn but only with better transport later (Heavy Pickup, trailers, wheelbarrows). Wheat and corn are the easy early cash crops.

Fertilizer and spray are liquids counted in **litres** (realistic per-tile rates, e.g. a few hundred l/ha → roughly 0.1–0.3 l per tile; exact values TBD). They are bought at the Dealer and fetched from storage like seeds.

Gravel: 300 kg per two-way road block, 0.40 qk/kg, ordered in 50 kg steps in the Dealer panel (collected by the pickup like seeds). Road materials are bought at the Dealer at launch; own production chains (quarry, concrete plant) can come later.

Early game, supplies are stored in the **Storage Barn** together with everything else. **Supply Storage** is an optimization: it holds one resource type (set by the player on placement) and is placed close to the fields that use it, so workers walk less.

## Dealer

The Dealer is an **off-farm location** (placed at a random position on the map) where all buying and selling happens. Workers drive pickup trucks to the dealer.

### Buying
- Player opens Dealer UI and orders: seeds, fertilizer, spray, road materials (also vehicles and equipment)
- Orders are paid immediately — an order the player can't afford is not possible ("Max" fills in the most they can afford), so the pickup never drives for goods that can't be paid
- Worker drives a pickup truck to the Dealer, picks up ordered goods (limited by truck capacity)
- Worker drives back, unloads at the appropriate Supply Storage, or the Storage Barn if there is none
- Multiple item types can be collected in one trip as long as they fit the truck's capacity

### Selling
- Player configures auto-sell rules per resource: "Sell wheat when stock > 200"
- When threshold is exceeded, a transport task is generated
- Worker loads pickup from Storage Barn/Silo, drives to Dealer, sells, returns
- Player can also manually trigger sell trips

### Starting Equipment
- Player starts with a **basic pickup truck** — enough to make early Dealer trips
- Capacity is limited, so early game means frequent trips for small loads
- Upgrading to bigger trucks + trailers reduces trip frequency

Producing fertilizer and spray in-house could be a future production chain.

## Building Costs

Buildings cost **money** and optionally **planks**:

| Phase | Cost | Examples |
|-------|------|---------|
| Early game | Money only | First crop fields, first storage barn, garage |
| Mid game | Money + planks | Mills, bakeries, bigger barns, silos |
| Late game | More money + more planks | Advanced processing, building upgrades |

This means players don't need wood to get started, but must establish a Tree Farm + Sawmill as part of mid-game progression. Planks can also be sold at market for profit — another use for excess wood.

## Storage

- Resources must be stored somewhere between production steps
- **Storage Barn**: general purpose, holds any goods
- **Silo**: specialized for grain/bulk crops, higher capacity
- **Supply Storage**: single resource type (seeds, fertilizer, spray), optional optimization near fields

### Processing (implemented: Hand Mill, Water Mill, Sawmill)
- A processing building holds its raw goods and products itself. Workers bring raw goods from storage in hand loads (Transport), grind / saw one batch at a time at the building (Processing, the worker is needed for every batch) and carry the products to storage (Transport)
- Auto-sell leaves in the barn what the processing buildings still have room for, so the mills get their raw goods first
- Recipes: Hand Mill 50 kg wheat → 37.5 kg flour in 40 s of work (holds 200 kg wheat, 150 kg flour); Water Mill the same in 12 s (400 / 300 kg); Sawmill 1 log → 3 planks in 10 s (10 logs / 30 planks)
- Prices: flour 4 qk/kg (wheat 2 qk/kg, 75 % extraction), planks 2.50 qk each (a log 3 qk). Planks are counted in pieces (10 kg, five in a hand load); the Dealer also sells them (4 qk each, so the Sawmill pays off) and they are not auto-sold by default (kept for building)
- Unlocked in the research tree (docs 06), then built from planks: Hand Mill 30, Sawmill 40, Water Mill 80 (carried to the site like gravel)
- Upgrades (unlocked by Mill gear II / III, Sawmill II / III): 50 planks to level 2, 100 to level 3, half the build work; the building stops while it is rebuilt. Level 2: batch work × 0.6, room × 1.5; level 3: work × 0.4, room × 2. Models `_l2` / `_l3`
- Demolishing a processing building puts its raw goods and products back in the barn

### Internal Buffers & Overflow
- Every building has a small **internal output buffer** (a few units)
- Workers deliver output to the nearest storage with space
- If all storage is full, output stays in the building's buffer
- When the buffer is full, **production halts** — nothing is lost, just paused
- Fields: the harvest is dropped as a **pile at the field's access point** — this buffer holds the whole harvest. Transport tasks carry it to storage; the field can't start a new cycle until the pile is picked up
- Notification alerts the player: "Storage full — Mill #2 halted"

No goods are ever lost or wasted — production simply pauses until space is freed. Fits the peaceful design.

## Resolved Questions

- ~~Seasons~~ — **Future feature.** Adds too much balancing complexity for launch. Task queue already handles workers shifting between jobs naturally, so seasons can be layered in later.
- ~~Crop rotation / soil depletion~~ — **Future feature.** Same reasoning.
- ~~Spoilage~~ — **No for launch.** Adds time pressure that conflicts with the peaceful pillar. Could be a future difficulty setting.
- ~~Different field preparation per crop~~ — **No.** All crops use the same cycle (cultivate → seed → grow → harvest). Differentiation comes from growth time and processing chains.
- ~~Fertilizer/spray production~~ — **Future feature.** Bought with money at launch. In-house production is a future chain.
