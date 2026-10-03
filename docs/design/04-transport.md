# Transport & Logistics

## Core Concept

Resources don't teleport — they need to physically move between buildings. This is where the logistics puzzle lives. Workers carry things by hand initially, then upgrade to pickup trucks with trailers for serious hauling.

Transport is separate from field work — **tractors work the fields, pickup trucks move the goods.**

## Transport Modes

### Automatic (default)
- Workers automatically transport goods when a building needs input
- "Mill needs wheat, Barn has wheat" → a worker picks up wheat and carries it over
- No player setup required — just works
- Workers pick the nearest source that has what's needed
- Good enough for early/mid game

### Manual Routes (optimization layer)
- Player can define explicit routes for repeated transport needs
- A route is a sequence of stops: Pick up [resource] at [building] → Deliver to [building]
- A worker with a pickup truck loops the route continuously
- Overrides automatic transport for those buildings — more efficient, less wasted trips
- Late-game tool for squeezing out throughput on high-traffic paths

This hybrid means early game just works, late game rewards route planning.

## Transport Methods

### 1. Worker Carry (Early Game)
- Workers carry resources by hand between buildings
- Very slow, very low capacity
- The starting point — motivates upgrading

### 2. Wheelbarrows (Early Game)
- Stored at Storage Barns (no Garage needed), a worker grabs one when a transport task benefits from it
- Still uses worker walking speed
- Bridges the gap before vehicles

### 3. Pickup Trucks (from the start)
- Dedicated transport vehicles stored in the Garage
- Worker picks up a truck, drives a transport route, returns it
- The player starts with one Light Pickup in a starting Garage (needed for early sell trips to the Dealer); Heavy Pickup comes mid-late
- Can tow trailers for extra capacity

### 4. Pickup + Trailer (Mid-Late Game)
- Trailers attached to pickups massively increase carry capacity
- Multiple trailer sizes with different capacity and weight limits
- Heavier loads = slightly slower speed
- Large trailers restricted to Heavy Pickup (weight limit)

## Transport Progression

```
Hands → Wheelbarrow → Light Pickup → Light Pickup + Small Trailer
								   → Heavy Pickup + Medium Trailer
								   → Heavy Pickup + Large Trailer
```

Each step is a meaningful capacity jump. The player decides when to invest in transport vs. production.

## Roads & Pathfinding

### Road Types

| Surface | Speed | Build Cost | Unlocked | Notes |
|---------|-------|------------|----------|-------|
| Grass (no road) | Slowest | — | Start | Default terrain |
| Dirt Road | Slow | Free | Start | Packed earth, no materials needed |
| Gravel Road | Medium | Cheap | Early | Crushed stone, common farm roads |
| Cobblestone Road | Good | Medium | Mid | Durable, classic look |
| Asphalt Road | Fast | Expensive | Mid-Late | Modern paved road |
| Concrete Road | Fastest | Very expensive | Late | Industrial-grade, extra bonus for loaded heavy vehicles |

### Weighted Pathfinding
- All units (workers on foot, wheelbarrows, pickup trucks) use A* pathfinding with tile movement cost
- Units always pick the **lowest total cost** path — not the shortest distance
- A longer asphalt route beats a short grass shortcut if the total travel time is lower
- This means road building has a real, visible impact: lay down asphalt between your barn and mill and you'll see trucks reroute onto it immediately

### Road Strategy
- Early game: dirt roads everywhere (free), gravel on key paths
- Mid game: cobblestone/asphalt on high-traffic routes
- Late game: concrete on busiest corridors (barn → mill → market highways)
- Road placement starts free but upgrading the network becomes a meaningful resource sink

### Road Width & Direction

**One-way roads (1 tile wide):**
- Player sets direction (arrow indicator on the road)
- No oncoming traffic — collision-free by design
- The optimization tool: build one-way loops for maximum throughput
- Cheaper (1 tile of material)

**Two-way roads (2 tiles wide):**
- One lane per direction, vehicles stay in their lane
- No direction setup needed — just works
- The default "easy" option for most situations
- More expensive (2 tiles of material)

### Collisions & Blocking
- Vehicles on the same lane going the same direction: faster one slows down behind the slower one (basic queuing, no overtaking)
- Two-way roads: no head-on collisions (separate lanes)
- One-way roads: no collision possible by design
- **Field vehicles** (tractors, combines): drive on the field itself, never block roads
- **Transport vehicles** (pickup trucks): drive on roads and **block traffic when loading/unloading** at buildings

### Loading Bays
- By default, pickup trucks stop on the road next to a building to load/unload — this **blocks traffic** behind them
- Buildings can be upgraded with a **loading bay** — a dedicated pull-off area where trucks load without blocking the road
- Loading bay is an in-place building upgrade (adds a small pull-off zone to the building's footprint)
- Priority upgrade for high-traffic buildings (main storage barn, processing buildings)
- Creates a natural progression: early game blocking is tolerable, late game it becomes a bottleneck the player solves with loading bay upgrades

### Intersections & Right of Way
- Default rule: **first-come-first-served** — vehicle that arrives at the intersection first passes through
- Simultaneous arrival: right-hand priority rule (vehicle coming from the right goes first)
- Higher-tier roads could have implicit priority over lower-tier (asphalt beats dirt)
- Future: player-placed **traffic signs** (yield, stop) to manually control priority at specific intersections
- Future: **traffic lights** for high-traffic intersections (automated timing)

### Road Placement
- Placed via drag (hold click and drag to paint multiple tiles)
- One-way direction set during placement (or toggled after)
- Roads block building placement — must demolish first
- Upgrading a road in-place: place a higher tier over an existing road directly (no demolish needed)
- Two-way roads are drawn by the drag tool as a **2-tile-wide strip** and form one road object with two lanes; one-way roads are a 1-tile strip with a direction. The game never has to guess lanes from two adjacent 1-tile roads.

## Open Questions

- ~~Multi-stop routes~~ — **No for now.** One pickup, one delivery per trip. More trucks/routes solves throughput. Multi-stop parked as future feature.
- ~~Traffic / congestion~~ — **Yes.** Transport vehicles block roads when loading. Solved with loading bay upgrades.
- ~~Road intersections~~ — **Auto-connect** visually, like Factorio belts. Intersections form automatically where roads meet.
- ~~Route editor~~ — **Click and drag** to draw routes, or single click to place one tile.
- Traffic density / most-used paths overlay — **future feature**
- ~~Front loader~~ — **Parked.** Unnecessary complexity for now.
