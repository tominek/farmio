# Logistics step 4: the Shed and the collection point — implementation plan

> For agentic workers: one implementer subagent does each task, and a reviewer checks it.
> Read `CLAUDE.md` (rules, commands, tests) before you start. Tasks marked **PARALLEL** may run at
> the same time in separate worktrees. Their files do not overlap, or overlap only by the few lines
> noted. A wave starts only after every task of the previous wave is merged.

**Goal:** the player gets two buildings that make the lazy logistics of step 3 their own:

- The **Shed** ("Supply storage" node, 2×2, built from planks) is a real store with medium capacity
  and a filter. It is placed where the work is. Needs are served from it when it is the cheapest
  source, and clears go into it when it is the cheapest store that takes the good.
- The **collection point** (its own node, cheap, 1×1, touching a road) is a ready-made hand-off by
  the road. The planner uses it instead of making a road pile when it takes the good. It is never a
  final destination and never a store.

Both have a filter edited in the info panel (empty means everything), show what is coming in and
going out, and leave their contents as ground piles when demolished. The research tree gains a
Storage row, and the build dock's Storage category lists them.

**Spec:** `docs/superpowers/specs/2026-10-04-logistics-design.md` (Store table, sections 1–3, step 4
of 5). Step 3 plan (done): `docs/superpowers/plans/2026-10-05-logistics-step3-road-piles-pickup.md`.

Design: kit section 17:

| Shot | Shows | In this plan |
|---|---|---|
| `art/ui/design/shots/s17a.png` | collection point panel, right | Task 5 |
| `s17b.png` | Shed panel, stock chip tooltip split by place | Tasks 5, 6 |
| `s17d.png` | in-world collection point (empty / holding goods), Shed, placement ghost snapping to the road edge | Tasks 2, 4 |
| `s17e.png` | research Storage row: Storage Barn ✓ → Collection point 300 → Supply storage 800 → Bigger Shed (later) | Tasks 1, 6 |
| `s17f.png` | build dock Storage: Storage Barn, Collection pt., Shed (locked: Research), dashed "Road piles appear on their own — not built" hint | Task 6 |

HTML source: `art/ui/design/Acres and Quacks UI Kit.dc.html`, sections
`data-screen-label="17a …"` … `"17f …"`. Icons are `i-shed` and `i-cpoint` there. Values in the
mockups (capacities, prices, plank costs) are illustrative.

**Architecture:**

- **Shed = a STORAGE store.** The def has `"storage": true`, `"capacity"` and `"filter": true`.
  `_register_store` gives it `Store.Kind.STORAGE` with the def's capacity. It joins `_stores`, so
  everything that already treats barns as stores picks it up:
  - the planner's suppliers and clear destinations (`barns`), with the cheapest one chosen by route
    cost;
  - seed fetches (`_nearest_store`), totals, `sellable`, wheelbarrows.

  Barn-only assumptions that break with a finite, filtered store are fixed one by one (Task 3):
  - `put_goods` / `_store_for` and `deliver` check room;
  - a wheelbarrow brought back goes to a store that takes it;
  - the rest of a trip's cargo goes to a store with room;
  - the "farm needs a Storage Barn" rules count Storage Barns, not `_stores`.
- **Collection point = a COLLECT store** (`Store.Kind.COLLECT`, appended). It is not in `_stores`.
  It is cached in `_collects`. Its door (access tile) is a road tile, so it is always a vehicle stop.
  The planner treats it in three ways:
  - **as a hand-off** — `Planner._handoff` prefers a collection point that takes the good, has room
    for a hand load and lies near the store, over joining or making a road pile;
  - **as a clear source** — goods lying on it that are not promised to a leg (a chain broke, its
    filter changed) are cleared like a ground pile;
  - **never as a final destination** (`want()` is 0, it is not in `barns`), and as a source for a
    need only when the route starts with a ride from it.
- **Filters** are `Store.filter` (resource → true). An empty filter takes everything, and
  `{Store.FILTER_NONE: true}` takes nothing. The info panel edits them by good groups
  (`Defs.FILTER_GROUPS`; "Seeds" is every `seed_*`).

  `World.set_filter(s, filter)` sets the filter. Waiting legs and rides that would still bring goods
  it no longer takes are dropped, with all their claims. Legs already under way arrive, because their
  room is reserved. The planner then clears every good a STORAGE or COLLECT store no longer takes
  to another store (one more clear pass). Nothing is stranded and nothing is teleported.
- **Demolition and moving** of a Shed or collection point leave its contents as ground piles
  (origin DROPPED, with a reason) on and around its spot, after its tiles are released, in piles of
  at most `GROUND_PILE_CAPACITY`. Legs to and from it are cancelled through the existing
  `_drop_legs` → `_drop_legs_where`. Barns keep today's behaviour (contents to the other barns).
- **Placement:** a def with `"by_road": true` is placeable only when its access tile is a built road
  tile. `World.road_snap(cell, pref_rot)` finds the placement that touches a road within
  `Defs.COLLECT_SNAP` tiles of the cursor. The placement tool's ghost jumps there and the road edge
  it uses glows.
- **Models:** decided after checking the repo and the machine:
  - The Shed uses the existing GLB `building_supply_storage`. It is 2×2 timber with a door and a sign
    board, made in the Phase 2 Blender set exactly for "Supply storage", in the palette and at the
    scale of the other buildings.
  - The collection point gets a new GLB `building_collection_point` (1×1 wooden platform with a sign
    post facing the road, per 17d). It is built **headless with Blender here** (Blender 5.2.2 at
    `/Applications/Blender.app`, verified with `-b --version`). It goes through the existing
    pipeline (`art/blender/scripts/p2_run.py`, helpers in `p0_helpers.py` / `p2_common.py`), in a
    **new set** `p2_logistics.py` so that no other model is re-exported.
  - The goods on a collection point are not baked into the model. They are dressed on it at runtime
    with the same per-good meshes as the road piles (`PileView`), by fill level.
  - Fallback, only if the headless build fails: a procedural platform (a `BoxMesh` deck, a post and a
    sign board in the palette material). The report must say so.

**Tech:** Godot 4.7, typed GDScript, headless test scripts in `scripts/tools/`, Blender 5.2 headless
(Python) for one model.

## Global constraints

- Code, comments and UI texts are in English. Use sparse `##` doc comments, tabs and typed
  GDScript, and match the surrounding code. Add no new `class_name`, so no `--import` is needed for
  scripts. Run `--import` once after the new GLB and the SVG icons are added.
- Tuning numbers live in `scripts/sim/defs.gd`. Make no save migrations. Task 3 bumps
  `SaveGame.VERSION` to 5.
- Performance is not the focus of this step (Tomas tunes later), but add **no per-frame work**:
  - the planner and dispatcher stay on their 1 s timer;
  - views rebuild on signals only;
  - the placement snap runs only when the cursor cell or rotation changes.

  Each task states the rough cost of what it adds.
- Every existing test keeps passing: `logistics_test`, `tech_test`, `mill_test`, `road_test`,
  `river_test`, `save_test`, `tools_test`. Run them as in CLAUDE.md, wrapped in
  `perl -e 'alarm 300; exec @ARGV'`. If this plan changes the behaviour an old test pins on purpose,
  update that test, and the report says which test and why.
- Only Tasks 3 and 7 edit `scripts/tools/logistics_test.gd`, one after the other.
- Commit on the current branch (`restart/design-and-art`, or the worktree branch for PARALLEL tasks)
  with a clear message. Never touch `.claude/`. Scratch output goes to `tmp/`.

## Review focus

1. **Goods conservation** through every new path:
   - the filter change (goods planned out, legs dropped, rides in a trip unloading into a store that
     no longer takes them);
   - demolishing or moving a Shed or collection point with goods in it and legs on their way;
   - a chain whose hand-off is a collection point that is demolished mid-way;
   - a save with goods on a collection point.

   The test sum is places + carried + loose + cargo (+ money for sold goods).
2. **Capacity:** a Shed and a collection point are never over capacity (contents + `reserved_in` ≤
   capacity) through `_put_into`, `put_goods`, `deliver`, wheelbarrow returns and `unload_rest`.
3. **Role of the collection point:** it is never a final destination of a clear or a sale, never
   the walked source of a need, and never in `_stores` (totals, `sellable`, seed fetches). It is
   used instead of a road pile only when it takes the good and has room.
4. **No old behaviour lost:** a single barn still behaves exactly as in step 3, and so do road piles,
   "Carry to the barn now", trips, the Dealer and the menu farm.

---

## Parallel plan

| Wave | Tasks | Notes |
|---|---|---|
| 0 | **Task 1** (contracts) ∥ **Task 2** (collection point model, `PileView.dress`) | Task 2 touches only art scripts, the new GLB and `pile_view.gd` |
| 1 | **Task 3** (Shed, filters, demolition piles, save v5 — sim core 1) ∥ **Task 4** (placement snap, building views) ∥ **Task 5** (info panels) ∥ **Task 6** (research row, build dock, stock tooltip) | UI tasks build on Task 1's real readers and Task 2's model |
| 2 | **Task 7** (collection point in the planner — sim core 2) | needs Task 3 |
| 3 | **Task 8** (menu showcase) | needs Task 7 so the collection point reads well |
| 4 | **Task 9** (integration, screenshots, docs — controller) | |

Files per task:

- Task 3: `world.gd`, `planner.gd`, `construction_site.gd`, `save_game.gd`, `logistics_test.gd`,
  `save_test.gd`.
- Task 4: `placement_tool.gd`, `building_view.gd`.
- Task 5: `info_panel.gd` only.
- Task 6: `research_panel.gd`, `build_dock.gd`, `hud.gd`.
- Task 7: `world.gd`, `planner.gd`, `logistics_test.gd`.
- Task 8: `menu_farm.gd`.

The only shared file in wave 1 is `CLAUDE.md` (each UI task adds its `--show` names to the list).
Merge it by hand.

---

### Task 1: contracts — defs, store kind, filters, tech nodes, readers, placement rule (first)

**Files:**
- `scripts/sim/defs.gd`, `store.gd`, `tech.gd`;
- `world.gd`: small edits in `_register_store`, `_release`, `can_place`, `demolish_blocker`,
  `move_blocker` and `is_unlocked`, plus one new block at the end of the file:
  "# --- sheds and collection points (logistics step 4)";
- icons `assets/ui/icons/kit/shed.svg` and `cpoint.svg`, taken from the kit's `i-shed` / `i-cpoint`
  symbols in the design HTML (as `pickup.svg` was in step 3);
- tests in `scripts/tools/tech_test.gd` and `road_test.gd`.

**Produces (exact names; later tasks rely on them):**

- `Defs`, each commented like its neighbours, all illustrative:
  - `SHED_CAPACITY := 2000.0` (kg)
  - `COLLECT_CAPACITY := 400.0` (kg)
  - `COLLECT_PREFER := 8`: tiles a collection point may lie farther than the road pile spot and
    still be used instead of it
  - `COLLECT_SNAP := 2`: tiles within which the placement ghost jumps to a road edge
  - `BUILDINGS`:
    - `&"shed"`:
      `{"name": "Shed", "size": Vector2i(2, 2), "cost": 0, "build_work": 24.0, "model": "building_supply_storage", "buildable": true, "storage": true, "capacity": SHED_CAPACITY, "filter": true, "material": {&"planks": 60.0}}`
    - `&"collection_point"`:
      `{"name": "Collection point", "size": Vector2i(1, 1), "cost": 0, "build_work": 6.0, "model": "building_collection_point", "buildable": true, "collect": true, "capacity": COLLECT_CAPACITY, "filter": true, "by_road": true, "material": {&"planks": 20.0}, "hint": "it must touch a road: the pickup collects there"}`

      The model file arrives with Task 2, in the same wave. Until then nothing places it.
  - `FILTER_GROUPS: Array[Dictionary]`, in the order of the 17a/17b grid. Each entry is
    `{"id": StringName, "name": String, "goods": Array[StringName]}`:
    - wheat "Wheat"
    - potato "Potatoes"
    - corn "Corn"
    - beet "Sugar beet"
    - seeds "Seeds" (`seed_wheat`, `seed_potato`, `seed_corn`, `seed_beet`)
    - flour "Flour"
    - wood "Logs"
    - planks "Planks"
    - gravel "Gravel"

    The icon is `UiStyle.resource_icon(goods[0])`. Wheelbarrows are not in the grid; a store takes
    them only when it takes everything.
- `Store`:
  - `Kind.COLLECT` appended (saved kinds keep their ints).
  - `const FILTER_NONE := &"-"`: a filter of only this key takes nothing.
  - `func takes_all() -> bool` (filter empty).
  - `static func filter_for(goods: Array) -> Dictionary`:
    - every good of every `FILTER_GROUPS` entry → `{}`;
    - none → `{FILTER_NONE: true}`;
    - else the set.
  - `accepts()` is unchanged (the sentinel never matches a good).
  - `to_dict` / `from_dict` are unchanged; the filter is already saved as a list of keys.
- `World`:
  - `signal store_changed(s: Store)`: a building store's filter changed (panels and views).
  - `var _collects: Array[Building] = []`, and `func collects() -> Array[Building]` (do not modify;
    like `stores()`).
  - `_register_store(b, saved)` handles `storage` and `collect` defs:
    - kind STORAGE or COLLECT;
    - `capacity = def.get("capacity", INF)` (from the def, not the save);
    - the filter from `saved`;
    - `cell = b.access`;
    - appended to `_stores` or `_collects`.

    `_release` also erases from `_collects`.
  - `func barn_count() -> int`: standing Storage Barns (`def_id == &"storage_barn"`, not a site).
    `demolish_blocker` and `move_blocker` use it instead of `_stores.size()`. Their rule only
    applies to `storage_barn`.
  - `can_place`: for a def with `"by_road"`, the access tile must also be a built road tile
    (`road[idx(a)] != 0` and `building_at(a)` not a road site). The placement tool's
    `_place_reason` gets the matching reason "it must touch a road" (Task 4).
  - `func road_snap(cell: Vector2i, pref_rot: int) -> Dictionary`, real, for 1×1 `by_road` defs:
    - it looks at tiles within `Defs.COLLECT_SNAP` (Chebyshev) of `cell` and the 4 rotations, keeping
      those where `can_place(&"collection_point", c, r)` holds, ignoring money;
    - it returns the nearest to `cell` (ties: `pref_rot`, then the lower rotation) as
      `{"anchor": Vector2i, "rot": int, "edge": Vector2i (the road tile it touches = its access)}`,
      or `{}`.
    - Cost: ≤ 25 × 4 one-tile checks per call.

    Add a `can_place` variant or flag that skips the money check, without changing the existing
    callers.
  - `func place_of(cell: Vector2i, exclude: Building = null) -> String`: the building part of
    `pile_place`, moved out ("by Hand Mill", "by the Garage site", "" when none within 12 tiles).
    `pile_place` calls it. The panels use it for the Shed subtitle ("by Hand Mill").
  - `func stock_places(res: StringName) -> Array[Dictionary]`, for the 17b tooltip, in this order:
    - each barn, then each Shed, by `display_name()`:
      `{"name", "amount", "kind": &"barn" | &"shed", "counted": true}`;
    - `"Not stored"` loose: `&"loose"`, counted;
    - each collection point holding the good: `&"collect"`, counted false;
    - one `"Road piles"` row (`&"road"`, counted false; the sum of ground piles of origin ROAD,
      present even at 0).

    The counted rows sum to `total(res)`. `stock_split` stays as it is for the existing tests.
  - `func store_flows(s: Store) -> Array[Dictionary]`: what is coming in and going out, one scan of
    `tasks.tasks`. Each entry is
    `{"dir": &"in" | &"out", "res": StringName, "amount": float, "text": String, "worker": Worker or null, "by": &"walk" | &"pickup"}`:
    - CARRY with `dst == s`: in, `"from {src label}"`, the worker if any, amount = what the worker
      carries or `fetch_amount`;
    - CARRY with `fetch_from == s`: out, `"to {dst label}"`;
    - RIDE with `dst == s` / `fetch_from == s`, by pickup:
      - `"pickup trip, stop N"` when it is in a trip (N = 1-based index of that store's stop in
        `trip.stops`);
      - else `"waiting for the pickup"`;
      - amount = `fetch_reserved + loaded`.

    Unopened later legs (`next`) are not listed. Cost: O(tasks), called by an open panel at its
    refresh rate.
  - `func set_filter(s: Store, filter: Dictionary) -> void`: **stub**. It sets `s.filter`, emits
    `store_changed` and `stock_changed`. Task 3 makes it drop legs.
  - `is_unlocked(id)` is also true for `Tech.is_start(id)`.
- `Tech`:
  - `BRANCHES` becomes `["Storage", "Processing", "Forestry", "Roads", "Equipment", "Fields", "Animals"]`.
    Every existing node's `branch` goes +1 (saves store node ids, not branches).
  - `static func is_start(id) -> bool` (`"start": true`).
  - New nodes, Storage row, per 17e:
    - `&"storage_barn"`: "Storage Barn", PLAN, col 0, cost 0, needs [], `"start": true`, no
      `buildings` (so the barn is never locked).
      Desc: "The farm's main store. Every farm starts with one."
    - `&"collection_point"`: "Collection point", PLAN, col 1, cost 300, needs [storage_barn],
      buildings [collection_point].
      Desc: "A small wooden platform by a road. Workers drop goods here instead of walking to the
      Barn; the pickup collects them on its round."
    - `&"supply_storage"`: "Supply storage", PLAN, col 2, cost 800, needs [collection_point],
      buildings [shed]. It **replaces** the old "later" node of that id in Fields.
      Desc: "Unlocks the Shed (2×2): a small store you put where the work is — by a mill or a far
      field. Choose which goods it takes; workers use the cheapest place that will."
    - `&"bigger_shed"`: "Bigger Shed", UPGRADE, col 3, needs [supply_storage], `"later": true`.
      Desc: "Sheds can be upgraded to hold more."
  - `unlock_all` skips start nodes (already unlocked).

**Tests:**

- `tech_test`:
  - the shed and the collection point are locked at the start;
  - `storage_barn` reads as unlocked;
  - no Supply storage before the collection point;
  - after both, `can_place(&"shed", …)` holds on a free spot;
  - `bigger_shed` is never unlockable;
  - the old checks still pass.
- `road_test`:
  - `can_place(&"collection_point")` is false off the road and true with its door on the road;
  - `road_snap` from 2 tiles away returns the touching tile with `edge` a road tile;
  - from 3 tiles away it returns `{}`.
- All tests pass.

**Cost:** none per frame. `road_snap` ≤ 100 small checks per cursor move.

### Task 2: the collection point model; goods dressed by fill level (PARALLEL, wave 0)

**Files:**
- `art/blender/scripts/p2_logistics.py` (new set: `build_all(do_export)` like `p2_buildings.py`,
  only this model);
- `assets/models/building_collection_point.glb` (+ `.import` after `--import`);
- `scripts/view/pile_view.gd`.

**Produces:**

- `collection_point()` (Blender), per 17d. The origin is on the ground at the centre of the 1×1
  footprint, with the access side (front) towards +Y as in every building. It has:
  - a low plank platform about 2.6 × 2.6 m, on short posts;
  - a darker rim;
  - a sign post at the front edge with a small blank board facing +Y (towards the road).

  It uses palette colours from `p2_common.py` (`timber`, `timber_dark`, `wood_light`,
  `sign_wood`).
- Build headless:
  `perl -e 'alarm 300; exec @ARGV' /Applications/Blender.app/Contents/MacOS/Blender -b art/blender/style_exploration.blend --python art/blender/scripts/p2_run.py -- logistics shot=cpoint:<x>,<y>,0:1.5:30`.
  The shot goes to `art/renders/…` as the runner does; copy a cropped preview to `tmp/cpoint.png`.
  Do not pass `save` (the .blend stays untouched). Guard every loop (memory note: a float-accumulating
  `while` once hung Blender).
- Then run `Godot --headless --path . --import`. Check in the game with
  `--show=tool_collect` (Task 4) or with a short script that instances `Models.instance("building_collection_point")`.
- `PileView`:
  - `static func level_of(frac: float) -> int` (the existing `_level`, made static and public);
  - `func dress(node: Node3D, res: StringName, level: int, scale := 1.0) -> void`: the logs /
    planks / sacks / gravel placement of `_update`, factored out so that a building can dress goods
    on itself, at a smaller scale. Behaviour for ground piles is unchanged (`--show=piles` looks the
    same).
- If headless Blender fails, use the procedural fallback described in Architecture, made in
  `building_view.gd` by Task 4 instead (tell the controller).

**Tests:**
- `tmp/cpoint.png` render;
- `--show=piles` unchanged (`tmp/piles_s4.png`);
- `--import` clean.

**Cost:** none at runtime beyond one more GLB.

### Task 3: the Shed as a store, filters, demolition piles, save v5 (sim core 1, wave 1)

**Files:** `scripts/sim/world.gd`, `planner.gd`, `construction_site.gd`,
`scripts/core/save_game.gd`, `scripts/tools/logistics_test.gd`, `save_test.gd`.

**Consumes:** Task 1.

**Produces / rules:**

- **Room everywhere goods are put without a leg:**
  - `_store_for(res, near, kg := 0.0)` skips a store that does not take `res` or has
    `room() < kg`. `put_goods` passes the weight; nothing fitting → loose.
  - `deliver(w)` puts into the store it stands at only if it takes the good and has room, else
    `put_goods`.
  - `_put_carried`: the wheelbarrow goes into `t.dst` only if it takes wheelbarrows and has room for
    one, else `put_goods(&"wheelbarrow", 1, cell)`.
  - `_storage_for(v)` (the rest of a trip's cargo): the store nearest the garage with room for the
    whole cargo; failing that, a Storage Barn (capacity INF).
- **`_put_into` STORAGE** keeps putting what a leg brings (its room was reserved), even when the
  filter changed meanwhile. The clear pass below takes it out again.
- **`set_filter(s, filter)` (real):**
  1. Normalise through `Store.filter_for` when given a goods list, and set it.
  2. Drop the waiting legs not yet started that would still bring a good `s` no longer takes:
     - CARRY with `worker == null`, or RIDE with `trip == null`, whose `dst == s` → `tasks.remove`
       (claims released down the chain);
     - a queued leg whose later leg (`next` chain) goes to `s` with such a good → cut before that
       leg (release from it on, `prev.next = null`); the current leg goes on to its own destination.

     Generalise `_drop_legs_where` with a predicate on `(store, res)` and a flag "leave started legs
     alone", or write a sibling helper. Do not duplicate the chain walk.
  3. Emit `store_changed`, `stock_changed`.
- **Planner clear pass for rejected goods:**
  - In `tick`, a STORAGE store with a non-empty filter holding a good it does not take is added to
    the clears.
  - `_plan_clear` STORAGE branch: `_clear(s, res, s.available(res), true, barns)` for each such
    good.
  - `_clear` never picks `b == s` (`want()` is already 0 there).

  O(stores × goods held) per run.
- **Demolition and moving** of a non-barn store (Shed now, collection point too: same code, keyed on
  `b.store.kind == COLLECT` or `capacity < INF`):
  - `_empty_store` drops legs and frees claims as now, but **keeps** the contents.
  - After `_release(b)`, the new `_scatter_store(b, why)` puts every good down with `drop_goods(res,
    chunk, b.access or the footprint centre tile, Task.Category.TRANSPORT, Store.Origin.DROPPED,
    "%s was demolished; what was stored there was left here." % name)`. Chunks are at most
    `GROUND_PILE_CAPACITY` kg (whole pieces), because a new pile takes a whole drop.
  - What finds no free tile goes to `put_goods` (as `drop_goods` callers do today).
  - Moving uses the same scatter with reason "… is being moved". In `demolish` and
    `move_building`, call it after `_release`.
  - Barns: unchanged.
  - Cost: O(contents / 200 kg) drops, each ≤ 81 tiles.
- **A moved Shed or collection point keeps its filter:**
  - `ConstructionSite.store_filter := {}` is copied in `move_building`;
  - `_finish_site` (via `add_building`) and `_cancel_move` restore it;
  - it is saved with the site.
- **Save:** `SaveGame.VERSION = 5` (comment: "5: sheds and collection points; store kind and capacity
  from the def; a moved store's filter").
  - Building stores are saved as today (`store.to_dict()`, `_register_store` on load).
  - A site saves `"filter": keys` when `store_filter` is not empty.
  - Goods on a collection point are saved with it.

**Tests (logistics_test, new):**

- `_test_shed_serves_mill`:
  - a barn ≥ 60 walk tiles from a hand mill holds 300 wheat;
  - a Shed 6 tiles from the mill holds 100 wheat;
  - the mill wants wheat;
  - → the first legs fetch from the Shed's store, and the barn's wheat is untouched until the Shed's
    is promised.
- `_test_shed_takes_clear`:
  - a ground pile of logs beside a Shed, the barn far away, no pickup;
  - → the logs end in the Shed;
  - every tick: Shed weight + `reserved_in` ≤ `SHED_CAPACITY`;
  - with the Shed full (set its contents to capacity), the next logs go to the barn.
- `_test_filter`:
  - a Shed with filter {wheat} beside a ground pile of planks → the planks go to the barn;
  - with 200 wheat in the Shed and a waiting wheat leg to it, `set_filter(shed, {planks})` → the
    waiting leg is gone (claims released, `_reservations_match`), the wheat is planned out and ends
    in the barn, the planks pile now goes to the Shed, and the total is unchanged every tick;
  - `FILTER_NONE` takes nothing.
- `_test_shed_demolish_piles`:
  - a Shed with 450 kg wheat + 10 planks, a leg on its way to it and one from it;
  - `demolish` → ground piles within `GROUND_PILE_SEARCH` of its spot, each ≤ capacity, origin
    DROPPED with the reason;
  - totals equal before and after;
  - no leg touches the old store, `_reservations_match`;
  - the planner clears the piles.
- `_test_barn_rule`: with a Shed standing, the only Storage Barn still can't be demolished or moved.
- `_test_wheelbarrow_to_shed`: a wheelbarrow leg ending at a Shed that does not take wheelbarrows →
  the wheelbarrow ends in a barn.
- `_test_shed_save` (and `save_test`): Shed and collection point contents, filter, kind and capacity
  survive a save round trip; a moved Shed keeps its filter.
- Conservation and `_reservations_match` are checked every tick in the new tests.

**Cost:** one clear pass over STORAGE stores with a filter per planner run. The rest is
event-driven.

### Task 4: placement snap to the road; building views (PARALLEL, wave 1)

**Files:** `scripts/view/placement_tool.gd`, `scripts/view/building_view.gd`.

**Consumes:** Task 1 (`road_snap`, the `by_road` rule, `store_changed`), Task 2 (the GLB,
`PileView.dress`).

**Produces:**

- **Ghost snap (17d right):** for a `by_road` def, `_anchor()` / `rot` come from
  `world.road_snap(_cell, rot)` when it is not `{}`:
  - the ghost jumps to that tile, green;
  - the road tile it uses (`edge`) is outlined white in the overlay (`_draw_overlay`, dashed like
    the other tool outlines);
  - `R` asks for the next rotation as `pref_rot` (a tile at a road corner can turn its sign to either
    road);
  - beyond `COLLECT_SNAP`, the ghost follows the cursor in orange with the problem "Can't go here:
    no road — it must touch a road" (`_place_reason`).

  Recompute only when `_cell` or `rot` changed. The rest of the tool (click to place, Esc, Shift)
  is unchanged. Moving a collection point uses the same snap.
- **Building view:**
  - the Shed and the collection point use their models through the existing path;
  - construction sites scale the 4×3 site model to 1×1 and 2×2 already, so check they read.
  - A collection point's goods are dressed on its platform: the good with the most weight at the
    level `PileView.level_of(weight / capacity)`, scale ≈ 0.6, nothing when empty.
  - It is rebuilt on `stock_changed` / `store_changed` only for collection points whose key
    (`res#level`) changed. That is O(collection points) per signal, a handful.
- `debug_show("tool_collect")`: the placement tool armed with `collection_point` (unlocked),
  cursor 2 tiles off a road near the barn, snapped. Add `tool_collect` to the CLAUDE.md `--show`
  list.

**Tests:**
- `--show=tool_collect` screenshot (`tmp/tool_collect.png`, cropped with `sips`);
- `--show=tool_move`, `tool_demolish` and `piles` unchanged;
- no script errors.

**Cost:** snap ≤ 100 one-tile checks per cursor-cell change. The view does no per-frame work.

### Task 5: info panels — Shed and collection point (PARALLEL, wave 1)

**Files:** `scripts/ui/info_panel.gd` only.

**Consumes:** Task 1:
- `Defs.FILTER_GROUPS`;
- `Store.filter_for`, `takes_all`, `FILTER_NONE`, `Kind.COLLECT`;
- `World.set_filter`, `store_flows`, `place_of`, `store_changed`;
- icons `shed`, `cpoint`.

**Produces (17a right, 17b right):** one builder for both, chosen when the target building's store
is a Shed (`def_id == &"shed"`) or a collection point. Barns keep their panel.

- **Header:** icon `shed` / `cpoint`, title `display_name()`, the subtitle inline and soft,
  `world.place_of(b.access, b)` ("by Hand Mill"). For a renamed one: `"{default_name} · by …"`.
  Rename works as for other buildings.
- **STORED:** chips with icon, amount and unit, as in the barn panel ("Nothing stored yet" when
  empty). Then a bar: left `"{weight} stored"`, right `"room for {capacity − weight}"`
  (`Defs.format_kg`).
- **TAKES:**
  - section label with **All · None** links on the right;
  - a 3-column grid of toggle chips, one per `FILTER_GROUPS` entry: resource icon, name, and a check
    circle (filled green when on);
  - "on" = `takes_all()` or every good of the group accepted;
  - toggling builds the new goods list and calls `world.set_filter(s, Store.filter_for(goods))`.
  - Under it, soft text:
    - collection point: "Workers only bring goods that are on. Goods it no longer takes are carried
      away.";
    - Shed: "Workers carry each good to the cheapest place that takes it — a near Shed beats a far
      Barn."
- **INCOMING / OUTGOING:** a well with one row per `store_flows(s)` entry:
  - an `IN` / `OUT` tag (green / brown);
  - the good icon, `"{amount} · {text}"`;
  - right: the worker link (as on the road pile panel, clicking selects the worker) or
    "<pickup icon> Pickup".

  Show "Nothing on its way" when empty, and at most 6 rows plus "and N more".
- **Action:** "Demolish (contents are left as piles)", plus the refund text of the materials, with
  `demolish_blocker` as its tooltip when disabled.
- **Not shown** (see open questions): the Priority row (it has no effect on stores) and the
  "Upgrade to level 2" button (Bigger Shed is "coming later").
- **Layout key:** the filter, the stored goods and the flow count, so toggles and new legs rebuild
  the panel. Values update in `_update_*` at the existing rate. Also refresh on `store_changed`.
- **`debug_target` / `debug_show`:**
  - `info_shed`: a Shed added with `add_building` beside the hand mill (or the barn), with 640 kg
    wheat, 180 kg flour, 15 planks, filter {wheat, flour, planks}, and one leg in and one out made
    through the planner;
  - `info_collect`: a collection point by the road (`road_snap`) with 180 kg potatoes and 80 kg
    corn, filter {potato, corn, beet}.

  Add both names to the CLAUDE.md `--show` list.

**Tests:**
- screenshots `tmp/info_shed.png` and `tmp/info_collect.png` (cropped);
- toggling a chip in a short headless check calls `set_filter` with the expected dictionary;
- `info_mill`, `info_site`, `info_pile`, `info_road_pile` and `info_garage_trip` unchanged;
- no script errors.

**Cost:** `store_flows` O(tasks) per refresh of an open panel.

### Task 6: research Storage row, build dock Storage, stock tooltip (PARALLEL, wave 1)

**Files:** `scripts/ui/research_panel.gd`, `scripts/ui/build_dock.gd`, `scripts/ui/hud.gd`.

**Consumes:** Task 1 (`Tech` changes, `stock_places`, icons), Task 2 (model for the preview).

**Produces:**

- **Research (17e):**
  - The Storage band is the first row, labelled "Storage" with the house icon.
  - The start node (`storage_barn`) is drawn as done ("✓ Unlocked"), and its detail shows no unlock
    button.
  - Plan details show "Unlocks the {icon} Shed · 2×2" for `supply_storage` (the building name and
    size from the def).
  - The preview model is `Defs.def(...)["model"]` (already the rule).
  - The tree still fits, with no overlap now that there are 7 bands. Adjust `_fit` / band heights if
    needed.
  - `debug_show("research_storage")` selects `collection_point` with money 1 840 and
    `storage_barn` done. Add the name to the CLAUDE.md `--show` list.
- **Build dock (17f):**
  - `building_icon`: shed → `shed`, collection_point → `cpoint`.
  - Storage tiles in this order: Storage Barn, Collection point (label "Collection pt."), Shed
    (locked: "Research", as other locked plans already show).
  - After them, a dashed hint tile (not a button): pile icon, "Road piles", "appear on their own —
    not built".
  - Tile tooltip for a `by_road` def: `"{name} · 1×1\nHolds {capacity} · choose which goods\nMust touch a road — the pickup collects it"`.
    The Shed's: `"Holds {capacity} · choose which goods"`.
  - `BRANCH_CATEGORY` gets `"Storage": "Storage"`.
- **Stock chip tooltip (17b):**
  - a rich tooltip on the stock chips: header `"{Good} · {total}"`;
  - one row per `stock_places(res)` entry (icon by kind: barn `house`, shed `shed`, collection point
    `cpoint`, road piles `pile`; name left; amount right);
  - rows with `counted == false` in the soft colour, and greyed at 0;
  - then the existing short / "Construction needs N more" line in the warning colour.

  Use `_make_custom_tooltip` (a small inner class for the chip panel if it has no script yet). The
  seeds chip keeps its per-seed lines.
- `world.stock_split` is no longer used by the HUD.

**Tests:**
- screenshots `tmp/research_storage.png`, `tmp/build_storage.png` (`--show=build` with the Storage
  category; add a `build_storage` state if `build` shows another category) and
  `tmp/stock_tip.png` (a `--show=stock_tip` state that opens the planks chip tooltip with a Shed
  holding planks);
- `research`, `research_mixed` and `research_tech` unchanged apart from the extra row;
- no script errors.

**Cost:** none per frame. The tooltip is built when shown.

### Task 7: the collection point in the planner (sim core 2, wave 2)

**Files:** `scripts/sim/world.gd`, `planner.gd`, `scripts/tools/logistics_test.gd`.

**Consumes:** Tasks 1, 3.

**Produces / rules:**

- **Hand-off:** `Planner._handoff(s, res)` (the cache per store stays: itself, a road pile spot, or
  null):
  - when the store is not its own stop, first `_collect_for(s, res, spot)`;
  - only when that finds nothing, `_join` / the spot as today.
  - "No road pile spot" no longer returns null before a collection point is tried.

  `_collect_for` (memoised per run by `[store, res]`) picks, among `world.collects()` stores, one
  that:
  - accepts `res`;
  - has `room() ≥` the weight of a hand load;
  - is a reachable stop (`_reachable`);
  - lies at straight-line distance `d_cp ≤ ROAD_PILE_SEARCH` from `_spot(s)`, and
    `d_cp ≤ d_spot + COLLECT_PREFER` when a road pile spot exists.

  Among those it takes the nearest, else null. It is used on both sides of a route (A by the
  source, B by the destination): a hand-off, never an end. `_hand_store` already checks room (a full
  one → a new road pile). Cost: O(collection points) per (store, good) per run.
- **Never a final destination:** a collection point is not in `barns`, and `want()` is 0 for
  COLLECT. `_plan_sale` and `_clear` never pick it.
- **Clear source:** in `tick`, COLLECT stores go to `clears`. `_plan_clear` COLLECT clears every free
  good like GROUND (any route). Goods promised to an opened ride are reserved, so they are not
  cleared.
- **Need source only as the start of a ride:** in `_source`, COLLECT stores are suppliers, but a
  route is accepted only when `r["a"] == s` (via the pickup from it). A direct walk from a
  collection point never serves a need.
- **World:**
  - `_put_into` COLLECT: put while the building stands, else `drop_goods` at `at` (else
    `put_goods`); `stock_changed`.
  - `available()` and `waiting_clear()` count COLLECT like GROUND.
  - `_saves` treats COLLECT as a clear source.
  - `_source_taken(s)` for COLLECT emits `stock_changed`.
  - `is_road_pile` stays false for it, so "Carry to the barn now" is not offered.
  - Demolition and moving go through Task 3's scatter; `_drop_legs_where` already cuts chains through
    it, and a ride in a trip whose stop store is gone follows the step 3 rules.
- **Labels:** a chain through it reads "Logs → Collection point · then pickup to Storage Barn"
  (`Store.label()` is the building name; check the Tasks chips show the `cpoint` icon for a COLLECT
  hop if `tasks_panel.gd` picks icons by kind. If it does, that is a 2-line change there; note it).

**Tests (logistics_test, new):**

- `_test_collect_instead_of_pile`:
  - the far tree of step 3's `_test_far_pile_chain`, with a collection point by the road 3 tiles from
    where that test's road pile appears;
  - → after felling, no road pile is made, and the walking leg's `dst` is the collection point;
  - the RIDE opens from it, and the pickup brings the log to the barn;
  - the collection point ends empty, with conservation and `_reservations_match` every tick.
- `_test_collect_filter_full`:
  - the same with its filter {wheat} → a road pile is used;
  - with it full (contents = capacity) → a road pile is used.
- `_test_collect_not_destination`:
  - a ground pile beside a collection point, the barn far, no pickup → the pile is walked to the
    barn, and nothing ever goes to the collection point;
  - with a pickup and a hand mill by it, its wheat serves the mill only through a ride, never a
    walking leg from it.
- `_test_collect_leftover`: 120 kg put on a collection point with no ride → cleared to the barn
  (by the pickup when far, walked when near).
- `_test_collect_demolish`:
  - while a walking leg goes to it and a ride waits from it → the goods on it become ground piles;
  - the walker's chain is cut before the ride;
  - nothing is lost, `_reservations_match`.
- `_test_collect_save`: save with goods on it and a ride waiting → totals equal after loading; the
  ride is planned again.
- Planner timing over the long run and the 512² probe: still within budget plus one search (record
  it in the report).

**Cost:** O(collection points) per (store, good) per run for the hand-off, and one more clear source
per collection point.

### Task 8: the menu farm shows a Shed and a collection point (wave 3)

**Files:** `scripts/menu/menu_farm.gd` only.

**Consumes:** Tasks 3, 7.

**Produces (CLAUDE.md: new buildings go into the showcase):**
- `&"shed"` is added to `SHOWCASE`, placed by the hand mill if one stands, with a filter
  {wheat, flour}.
- One collection point is placed with `world.road_snap` by the road, between the barn and the demo
  road piles. If `_seed_road_piles` / the restock puts goods near it, they land on it and the
  pickup's run includes it as a stop. If it does not read well (the pickup skips it, or it hides the
  road piles), leave it out and say so.
- Keep the map size and agent count. Print the `_build` time before and after; it must not grow by
  more than about 10 %.

**Tests:** `-- --menu --snap=tmp/menu_s4.png` shows the Shed (and the collection point); no script
errors.

### Task 9: integration, screenshots, docs (controller)

- Full test run. Check the `--shots=tmp/shots` scenario for errors. Re-shoot the new states with
  real data:
  - `info_shed`, `info_collect`, `tool_collect`, `research_storage`, build Storage, `stock_tip`,
    the menu;
  - an in-world close-up of a collection point holding goods next to a road pile (17d).
- Docs:
  - spec status line (step 4 done);
  - CLAUDE.md decisions: the Shed is a STORAGE store with a filter; the collection point is a
    hand-off only, never a destination; filters, where empty = everything; demolition leaves piles;
    the `--show` names;
  - `docs/design/09-future-ideas.md`: Bigger Shed (upgrade), priority on stores (prefer this Shed),
    "keep N here" quotas, barn demolition leaving piles, collection point B-side use if it is turned
    off (see questions).

## Open questions for the controller

1. **The collection point on the destination side.** The plan lets it be hand-off B as well: goods
   ride to it and are walked on to a site or mill nearby. It is still never a final destination and
   never the walked source of a need planned from scratch. Is that within ruling 2, or should it be
   used only at the source side (A)?
2. **Barns on demolition.** Only Sheds and collection points leave their contents as piles; a
   demolished barn still moves its goods to the other barns, as today. The spec's sentence covers
   every store. Keep barns as they are, since a barn can hold tonnes, which would be dozens of piles?
3. **Priority row and "Upgrade to level 2"** on the Shed and collection point panels (17a/17b) are
   left out: a store's priority affects nothing, and Bigger Shed is "coming later". Should priority
   get a meaning instead (e.g. a High Shed wins clears at equal cost), or stay out?
4. **Shed model:** the existing `building_supply_storage` has a roller door and a timber gable.
   17d draws a double X door and a shingle roof. Accept it for now, or add a `shed()` builder in the
   new Blender set (cheap, headless)?
5. **Names:** the design writes "Shed by the mill" as if it were the name. The plan keeps the
   numbered names ("Shed", "Shed 2", per the CLAUDE.md decision), with "by Hand Mill" as the
   panel's subtitle, while the tooltip uses the name. OK?
6. **Stock chip:** collection points and road piles are listed in the tooltip as goods on the way
   (soft, not counted in the chip's number). Only barns, Sheds and loose goods make the total, as
   today. OK?
7. **Save version:** the plan bumps `SaveGame.VERSION` to 5. Kind and capacity now come from the
   def, and a moved store's filter is a new key. Older saves would load, but they are hidden by the
   usual rule. Fine?
