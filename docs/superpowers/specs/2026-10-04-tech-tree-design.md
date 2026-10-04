# Research tree and material building costs — design

Date: 2026-10-04 · Status: agreed in brainstorming, waiting for the user's review of this spec

## Goal

Money gets a purpose beyond buying buildings: the player **unlocks building plans, building upgrades
and technologies** in a research tree and chooses which branch to push. Building itself then costs
**materials** (planks, gravel), so the production chains (sawmill → planks) matter for growth. Someone
who specialises in one branch and earns money with it never has to unlock another branch; the
prerequisites only follow what makes sense (a Water Mill needs the Hand Mill and the Sawmill).

The game's own currency is **Quacks** (no real country): amounts are written "1 500 qk" (`$1 500` → `1 500 qk`, prices "2 qk/kg"); the UI later shows a small duck-head icon instead of "qk". All "$" in texts, docs and the ledger go away; the prices in this spec are written as before but mean quacks.

The game is played only by the developer and friends for now. **Old save games are not migrated**: the
save format just changes.

## Scope

In this project:
- the currency rename to Quacks (one formatting helper `Defs.format_money`, used everywhere)
- research tree data, unlock rules and the research screen (simple first version; a concept UI from
  Claude Design will restyle it later)
- building plans for the existing processing buildings, gravel road and wheelbarrow as unlocks
- building costs in materials, planks sold at the Dealer, full material refund on demolition
- level 2 / 3 upgrades of the Hand Mill, Water Mill and Sawmill (models `_l2` / `_l3` exist)
- "coming later" nodes for content that does not exist yet (shown, not buyable), so the tree also works
  as a to-do list

Not in this project (each its own project later): Bakery and other new buildings, tree farm, new crops
and seed varieties, animals, tractors, cobblestone / asphalt / concrete roads, storage capacity
upgrades, saved layouts ("blueprints" in Future Ideas — a different thing from building plans here).

## Rules

### Unlocking
- A node costs money and is unlocked instantly. It can be bought once every node with a line into it
  (its prerequisites) is unlocked and the player has the money. Money spent is booked as "research".
- The whole tree is visible from the start (docs 06).
- Node kinds: **building plan** (makes a building buildable), **upgrade** (allows level 2 or 3 for every
  building of the listed types), **technology / equipment** (gravel road, wheelbarrow at the Dealer).
- "Coming later" nodes are drawn dashed with their prerequisites, never buyable.

### Available from the start (no node)
Small fields (all four crops), Storage Barn, Garage, Dirt Road (with bridges).

### First tree

| Node | Kind | Price | Needs | Unlocks |
|---|---|---|---|---|
| Hand Mill | plan | $300 | — | Hand Mill |
| Sawmill | plan | $300 | — | Sawmill |
| Water Mill | plan | $1 500 | Hand Mill, Sawmill | Water Mill |
| Mill gear II | upgrade | $2 000 | Hand Mill | level 2 of Hand Mill and Water Mill |
| Mill gear III | upgrade | $5 000 | Mill gear II | level 3 of Hand Mill and Water Mill |
| Sawmill II | upgrade | $1 200 | Sawmill | Sawmill level 2 |
| Sawmill III | upgrade | $3 000 | Sawmill II | Sawmill level 3 |
| Gravel road | technology | $200 | — | Gravel Road, gravel at the Dealer |
| Wheelbarrow | equipment | $150 | — | wheelbarrows at the Dealer |
| Bakery → Pasta Maker | coming later | — | Hand Mill | |
| Sugar Mill | coming later | — | Hand Mill | |
| Tree Farm | coming later | — | Sawmill | |
| Cobblestone → Asphalt → Concrete | coming later | — | Gravel road | |
| Light tractor | coming later | — | Wheelbarrow | |
| Better seed → New crops | coming later | — | — | |
| Chicken coop → Sheep & goat shed → Cowshed | coming later | — | — | |

Prices are placeholders, tuned with the balance bot afterwards.

### Building costs in materials
- Buildings cost only materials: Storage Barn 60 planks, Garage 80, Hand Mill 30, Sawmill 40,
  Water Mill 80. Roads: dirt free (a bridge still costs money on top), gravel 300 kg gravel per block.
  Fields keep their money price per tile (ground preparation, not a building).
- Planks are sold by the Dealer at $4 each (the Sawmill makes 3 planks from a $3 log, so own production
  is cheaper); gravel stays $0.40/kg. Gravel can only be ordered once Gravel road is unlocked, the
  wheelbarrow once Wheelbarrow is unlocked.
- Materials are carried from the barn to the site before building (existing delivery stage); the site
  waits and the alert says what is missing and where to get it.
- Demolishing returns the materials that went into the building (including its upgrades) to the barn;
  cancelling a site returns what was delivered (existing).

### Building upgrades
- When a building's next level is unlocked, its info panel offers "Upgrade to level 2 · 50 planks"
  (level 3: 100 planks); otherwise the button is greyed with "Unlock Mill gear II in research".
- An upgrade works like construction: workers carry the planks to the building, then build (work half
  of the building's build work). The building stops processing meanwhile; its contents stay. The upgrade
  can be cancelled (delivered planks go back to the barn).
- Effects: level 2 — batch work × 0.6, input / output room × 1.5; level 3 — work × 0.4, room × 2.
- The model switches to `<model>_l2` / `<model>_l3`.

## Screens

- **Research screen** — key T or the "Research" button in the top bar; the game keeps running.
  Branches as rows (Processing, Forestry, Roads, Equipment, Fields, Animals), nodes connected by lines.
  Node states: unlocked (green), can unlock now (orange border, price), needs something first (grey,
  lock), coming later (dashed). Clicking a node shows a side panel: name, kind, description,
  prerequisites with ✓ / ✗, what building it then costs, what it leads to, and the "Unlock · $X"
  button (disabled without money or prerequisites).
- **Build bar** — unlocked buildings show their material cost ("Storage Barn · 60 planks"); locked
  ones are greyed with a lock and open the research screen on their node.
- **Info panel** — the upgrade button for processing buildings (see above) and the current level.
- **Dealer** — wheelbarrow and gravel rows only when unlocked; planks in the materials section.
- Mock-up agreed in brainstorming: `.superpowers/brainstorm/*/content/tree-ui.html` (local only).

## Code

- `scripts/sim/tech.gd` (`class_name Tech`): static tree data — node id → name, kind, branch, column
  (for drawing), price, prerequisites, what it unlocks (`buildings`, `levels` {def id: level}, `items`),
  description, `later` flag. Helpers to read it.
- `Defs.BUILDINGS`: `"unlock": <node id>` on lockable buildings and roads, `"material"` costs instead of
  money, `"upgrade"` {level: planks}. `Defs`: plank price, level effects.
- `World`:
  - `unlocked := {}` with `is_unlocked(node)`, `can_unlock(node)`, `unlock(node)`; `building_unlocked(def)`,
    `item_unlocked(res)`, `max_level(def)`
  - `can_place` refuses locked buildings; `order` refuses locked items
  - `Building.level` and `Building.materials` (what was spent, for the refund); recipe values scaled by
    level (one place, e.g. `Building.recipe()` returns the effective recipe)
  - upgrades: a `ConstructionSite` with `upgrade_of: Building` that does not occupy tiles; it reuses the
    delivery / build tasks (work spots around the building); `_update_building` skips a building while
    it is being upgraded; finishing raises the level and emits a signal for the view
- `SaveGame`: unlocked nodes, building level and materials, upgrade sites. No migration of old saves.
- Views / UI: `scripts/ui/research_panel.gd` (new), HUD button + T, build bar lock state, info panel
  upgrade button, Dealer rows by unlock, `BuildingView` swaps the model on level change.
- Docs: 02 (costs, upgrades), 05 (materials, Dealer planks), 06 (tree contents).

## Testing

- `scripts/tools/tech_test.gd` (new):
  - start state: barn / garage / fields / dirt road placeable; Hand Mill, Water Mill, Sawmill, Gravel
    Road not; wheelbarrow and gravel can't be ordered
  - unlocking: refused without money or prerequisites, Water Mill needs both mills' nodes, money is
    taken once, "coming later" nodes are never unlockable
  - material cost: a barn site waits for planks, workers carry them and build; demolishing returns them
  - upgrade: refused before Mill gear II; with it, planks are carried, the mill stops while upgrading,
    level 2 grinds a batch in 0.6 of the time and holds 1.5×; cancelling returns the planks
  - save round trip keeps unlocked nodes, levels and a running upgrade
- Existing tests (`mill_test`, `road_test`, `river_test`, `save_test`, scenario, balance bot) unlock what
  they use first and pass.
