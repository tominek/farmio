# Worker System

## Core Concept

Workers are abstract labor units — think of them as robots, not people. They don't sleep, don't need housing, don't have morale. The player hires them, equips them, and they work.

This is a farming logistics game, not a colony sim. Workers exist to execute the player's automation plan.

Workers are **not assigned to buildings**. Instead, buildings generate tasks and workers pick them up from a shared task queue.

## Hiring

- **First 2-3 workers are free** — family members, available from the start
- Additional workers are **hired at the Dealer** for a **one-time fee** — a worker has to drive there with a vehicle and bring the new hires back; one trip brings as many workers as the vehicle has **free seats** (Light Pickup: driver + 1–2 passengers), so bigger vehicles make hiring faster later in the game
- **Temporary workers** (later): when a permanent hire is too expensive, workers can be rented for a smaller fee for a limited time — a short boost for harvest or a big construction; they leave when the time runs out
- **Scaling cost** — each additional hire costs more than the last
- No recurring salary — no stress, no bankruptcy risk from idle workers
- Once hired, a worker exists permanently
- No cap on worker count (limited only by money)

| Worker # | Cost |
|----------|------|
| 1-3 | Free (family) |
| 4-5 | $ |
| 6-10 | $$ |
| 11-20 | $$$ |
| 20+ | $$$$ |

Exact prices TBD via balancing. Current values: the 4th worker costs $400 and every next one 25 % more (rounded to $50). The fee is paid when hiring (the button is disabled without enough money, "Max" picks as many as the player can afford); cancelling hires that still wait at the Dealer refunds them. New hires get off at the barn (and help unload) or at the garage. The scaling cost naturally paces expansion — "hire another worker or buy a tractor?" is the fun decision.

## Task Queue System

### How It Works
1. Buildings generate tasks when work is needed
   - A field that needs plowing creates a "Cultivate Field #3" task
   - A mill with grain in its input creates a "Process Grain at Mill #1" task
   - Auto-sell threshold exceeded creates a "Transport goods to Dealer" task
2. Tasks enter a **global priority queue**
3. The nearest available worker picks up the highest-priority task they can perform
4. Worker walks to the location, performs the task, then grabs the next one
5. If no tasks exist, workers idle (stand in place or wander near last task)

### Splitting Field Work
- Field tasks (cultivate, seed, fertilize, spray, harvest) are split into **strips** of the field
- Each strip is a separate task, so several workers and machines can work the same field in parallel
- Adding more workers to a field is directly visible — more people working side by side, the field finishes sooner

### Task Examples

| Source Building | Task Generated | When |
|----------------|---------------|------|
| Crop Field | Cultivate | After harvest or on new field |
| Crop Field | Seed | After cultivation |
| Crop Field | Fertilize | During growth at ~20% (if fertilizer available) |
| Crop Field | Spray | During growth at ~50% (if spray available) |
| Crop Field | Harvest | When crops are fully grown |
| Mill | Process grain | When input resource is available |
| Bakery | Bake bread | When flour is available |
| Storage Barn | Transport to/from | When goods need moving between buildings |
| Dealer | Transport for sale | When auto-sell threshold is exceeded |
| Construction Site | Clear (chop trees) | Natural objects in the footprint |
| Construction Site | Deliver materials | After clearing, until all materials are on site |
| Construction Site | Build | Once materials are delivered (dirt roads: immediately) |

### Priority System

The player controls task priority at two levels:

**Category priorities** (global setting):
- Rank task categories by importance: Harvesting > Planting > Construction > Processing > Transport > etc.
- Default order that works for most situations
- Player can reorder anytime via a priority panel

**Per-building priority** (override):
- Individual buildings can be set to High / Normal / Low priority
- A High-priority mill's tasks jump ahead of Normal-priority tasks
- Useful for bottleneck management: "This bakery is falling behind, boost it"

### Task Selection Logic

When a worker becomes free:
1. Look at all pending tasks
2. Filter by what the worker can do (some tasks may need equipment)
3. Sort by: priority level → distance to task → task age (older first)
   - Waiting tasks **age**: every ~45 s of waiting counts like one category level, so low categories (transport) never starve while fields keep generating new work; tasks of similar urgency are then picked by distance
   - Default order: Harvesting > Dealer trips (pickup) > Planting (cultivate, seed) > Construction > Transport
   - **Priority panel (P)**: the player reorders the categories and can switch a category off (its tasks wait, the HUD says so); work already started is finished. "Reset to default" restores the order
   - **Per field / construction site**: High / Normal / Low in the info panel moves its tasks one category level up or down
4. Pick the top task, walk there, do it

## Worker Properties

| Property | Description |
|----------|-------------|
| Speed | How fast they walk between tasks |
| Work Speed | How fast they perform tasks |
| Carry Capacity | How much they can carry by hand |

All workers have identical base stats. Differentiation comes entirely from equipment.

Workers look different for liveliness only: male/female, varied skin tone and clothing colors (one base model per gender, color variations). No stat differences.

## Equipment & Garage

Equipment is a shared farm resource stored in a **Garage** building. Workers pick up equipment when a task requires (or benefits from) it, and return it to the garage when done.

### Garage Building
- Purchased and placed like any other building
- Stores all owned vehicles and attachments
- **No capacity limit** — a garage holds any number of vehicles
- Multiple garages are still useful for placement (closer to different farm areas, less worker travel)
- Vehicles and attachments can be **sold at the Dealer** for reduced value (50-75% of purchase price) — worker drives it there

### Equipment List

**Vehicles** (worker picks one up from the Garage, uses it, returns it):

Two vehicle categories with distinct roles:

### Tractors (field work — plowing, seeding, spraying)
Used for cultivating, seeding, and spraying. Tractors use attachments to perform different tasks.

| Tractor | Speed | Unlocked |
|---------|-------|----------|
| Basic Tractor | Medium | Mid |
| Advanced Tractor | Fast | Late |

**Tractor Attachments:**
| Attachment | Effect | Compatible With | Unlocked |
|------------|--------|----------------|----------|
| Basic Plow | Cultivating | Any tractor | Mid |
| Basic Seeder | Seeding | Any tractor | Mid |
| Basic Sprayer | Spraying | Any tractor | Mid |
| Fertilizer Spreader | Fertilizing | Any tractor | Mid |
| Deep Plow | Faster cultivating, wider coverage | Advanced Tractor | Late |
| Precision Seeder | Faster seeding, better yield, wider coverage | Advanced Tractor | Late |
| Boom Sprayer | Faster spraying, wider coverage | Advanced Tractor | Late |
| Grain Cart | Drives alongside combine, collects harvest on the go | Advanced Tractor | Late |

- Advanced attachments are restricted to better tractors — gives a reason to upgrade beyond raw speed
- Grain Cart is special: requires a **second worker** with a tractor on the same field as a combine. The combine doesn't need to stop and unload, greatly improving harvest throughput

### Combine Harvesters (harvesting)
Dedicated harvesting machines — self-contained, no attachments needed.

| Combine | Speed | Coverage | Unlocked |
|---------|-------|----------|----------|
| Basic Combine | Medium | Standard | Mid |
| Large Combine | Fast | Wide (covers more rows per pass) | Late |

- Combines harvest only — they're specialized machines, not general-purpose like tractors
- Worker drives the combine to the field, harvests, then the crop needs to be transported away (by hand, wheelbarrow, or pickup truck)
- Large combines are the most efficient way to harvest mega fields
- Pair with a Grain Cart (tractor + grain cart attachment, second worker) so the combine never stops to unload


### Pickup Trucks (transport)
Used for moving goods between buildings and driving to/from the Dealer for buying and selling.

| Pickup Truck | Speed | Base Capacity | Unlocked |
|-------------|-------|---------------|----------|
| Light Pickup | Medium | + | **Start** (player begins with one) |
| Heavy Pickup | Fast | ++ | Mid-Late |

**Trailers** (towed behind pickup trucks for extra capacity):
| Trailer | Capacity Bonus | Weight Limit | Compatible With | Unlocked |
|---------|---------------|-------------|----------------|----------|
| Small Trailer | ++ | Low | Any pickup | Mid |
| Medium Trailer | +++ | Medium | Any pickup | Mid-Late |
| Large Trailer | +++++ | High | Heavy Pickup only | Late |

- Each pickup truck can tow one trailer at a time
- Trailers slow down the pickup slightly based on load weight
- Larger trailers on weaker pickups = slower speed (weight limit matters)
- A pickup without a trailer is faster but carries less

### Hand Tools (early game, no garage needed)
| Equipment | Effect | Unlocked |
|-----------|--------|----------|
| Wheelbarrow | +carry capacity for transport, stored at Storage Barns | Early |

### How It Works
1. A task is generated (e.g., "Harvest Mega Field #2" — requires combine harvester)
2. Worker picks up the task from the queue
3. Worker walks to the nearest garage that has the needed equipment
4. Worker picks up the combine harvester (or a tractor + the needed attachment for other field tasks), drives to the field
5. Worker performs the task
6. Worker returns equipment to the garage, becomes available for the next task

### Equipment Contention
- If a task needs a tractor but all tractors are in use, the task stays in the queue until one is returned
- Workers won't pick up equipment-requiring tasks if no equipment is available — they'll take a different task instead
- This creates a natural incentive to buy more equipment as the farm scales
- Player can see equipment availability in the garage UI: "Tractors: 1/3 available"

### Tasks Without Equipment
- **Small fields** (up to 16x16): All tasks can be done by hand — cultivate, seed, fertilize, spray, harvest. Slower, but no machines needed. This is the early game.
- **Medium fields** (up to 32x32): Can still be done by hand, but very slow. Machines strongly recommended.
- **Large fields** (up to 48x48) and **Mega fields** (up to 64x64): **Require machines** — too much area for manual work. Tasks won't be picked up by workers unless appropriate equipment is available in the garage.
- Non-field tasks (processing, transport, storage) can always be done by hand but benefit from pickup trucks

## Worker Restrictions — Future Feature

Not in the first version — task priorities are the only control at launch. Later, the player could optionally:

- **Restrict a worker to a zone**: "This worker only handles tasks in the north fields"
- **Restrict a worker to task types**: "This worker only does transport tasks"
- **Lock a worker to a building**: "This worker stays at the bakery" (effectively static assignment, but opt-in)

These are power-user tools for late-game optimization (see Future Ideas).

## Visual Indicators

- Workers carry visible equipment (wheelbarrow model, sitting on tractor, etc.)
- Color-coded status indicator above worker:
  - Green: working on a task
  - Yellow: walking to a task
  - Grey: idle (no tasks available)
- Clicking a worker shows: current task, equipment, status

## Progression

### Early Game
- 2-3 family workers doing everything by hand
- Small fields, short task queues, no prioritization needed
- Workers bounce between planting, harvesting, carrying to storage

### Mid Game
- 5-10 workers, wheelbarrows, first tractors and pickups
- Multiple production chains running — priority management starts mattering
- Player starts noticing bottlenecks ("harvesting is backing up, I need more workers or a tractor")

### Late Game
- 20+ workers, several with tractors and attachments
- Complex priority setups, per-building priorities for bottlenecks
- Workers specialize through equipment: tractor operators handle fields, others handle processing
- The farm runs itself with minimal player intervention

## Open Questions

- ~~Worker hiring cost~~ — **Scaling one-time fee.** First 2-3 free (family), then increasing cost per hire.
- ~~Firing workers~~ — **No.** Workers have no upkeep, so there is no reason to dismiss them.
- ~~Visual variety~~ — **Cosmetic only:** male/female, skin tone and clothing colors.
- ~~Task queue visibility~~ — **Dedicated panel + per-building indicators.** (See UI doc)
- ~~Tractor fuel~~ — **No fuel.** Vehicles just work. Fits the "not a sim" approach.
- ~~Garage access~~ — **Any garage.** Workers go to the nearest one with available equipment.
