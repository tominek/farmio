# Resources & Production Chains

## Core Concept

Crops are grown, harvested, processed through multiple stages, and eventually sold. Longer production chains yield more profit, rewarding players who build complex setups.

## Raw Crops

| Crop | Growth Time | Notes |
|------|------------|-------|
| Potatoes | Fast | Simple, low value, early game cash |
| Wheat | Medium | Bread chain staple |
| Corn | Medium | Versatile — direct sale or processing |
| Sugar Beet | Medium | Sugar chain |

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
| Raw potatoes | 0 | $ |
| Raw wheat | 0 | $ |
| Raw wood | 0 | $ |
| Flour | 1 | $$ |
| Sugar | 1 | $$ |
| Planks | 1 | $$ |
| Bread | 2 | $$$ |
| Pasta | 2 | $$$ |

## Consumable Resources

Resources used during field work, purchased at the Dealer:

| Resource | Used For | Stored In |
|----------|---------|-----------|
| Seeds (per crop type) | Seeding task | Supply Storage |
| Fertilizer | Fertilize task during crop growth | Supply Storage |
| Spray | Spray task during crop growth | Supply Storage |

Each Supply Storage building accepts **one resource type** (set by the player on placement). Place seed storage near fields that use those seeds, fertilizer storage near fields that need it, etc.

## Dealer

The Dealer is an **off-farm location** (placed at a random position on the map) where all buying and selling happens. Workers drive pickup trucks to the dealer.

### Buying
- Player opens Dealer UI and orders: seeds, fertilizer, spray (also vehicles and equipment)
- Worker drives a pickup truck to the Dealer, picks up ordered goods (limited by truck capacity)
- Worker drives back, unloads at the appropriate Supply Storage
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
- **Supply Storage**: single resource type (seeds, fertilizer, spray)

### Internal Buffers & Overflow
- Every building has a small **internal output buffer** (a few units)
- Workers deliver output to the nearest storage with space
- If all storage is full, output stays in the building's buffer
- When the buffer is full, **production halts** — nothing is lost, just paused
- Fields: harvest sits in the field's buffer, field can't start a new cycle until picked up
- Notification alerts the player: "Storage full — Mill #2 halted"

No goods are ever lost or wasted — production simply pauses until space is freed. Fits the peaceful design.

## Resolved Questions

- ~~Seasons~~ — **Future feature.** Adds too much balancing complexity for launch. Task queue already handles workers shifting between jobs naturally, so seasons can be layered in later.
- ~~Crop rotation / soil depletion~~ — **Future feature.** Same reasoning.
- ~~Spoilage~~ — **No for launch.** Adds time pressure that conflicts with the peaceful pillar. Could be a future difficulty setting.
- ~~Different field preparation per crop~~ — **No.** All crops use the same cycle (cultivate → seed → grow → harvest). Differentiation comes from growth time and processing chains.
- ~~Fertilizer/spray production~~ — **Future feature.** Bought with money at launch. In-house production is a future chain.
