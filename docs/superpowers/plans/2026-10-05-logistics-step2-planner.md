# Logistics step 2: board and planner (on foot) — implementation plan

> For agentic workers: each task is done by one implementer subagent and checked by a reviewer.
> Read `CLAUDE.md` (rules, commands, tests) before starting.

**Goal:** Goods move between places by *carry legs* planned centrally by cost (real path lengths),
instead of hard-wired DELIVER / HAUL tasks that always end at the nearest barn. Felled wood is left
as a ground pile and cleared by the planner (logs go straight to a sawmill that wants them).
Buildings get numbered default names ("Storage Barn 2") the player can rename.

**Spec:** `docs/superpowers/specs/2026-10-04-logistics-design.md` (sections 1, 2 and step 2 of 4).
Step 1 plan (done): `docs/superpowers/plans/2026-10-04-logistics-step1-goods-in-places.md`.

**Architecture:** every place that holds goods is a `Store` with a `kind` (storage barn, site
supply, mill input, mill output, field gate pile, moved-building pile, ground pile). The old
buffer fields (`Field.pile`, `Building.input/output`, `ConstructionSite.delivered/pile`) become
GDScript properties over those stores, so views, UI and tests keep reading them. A `Planner`
(runs every `Defs.PLANNER_INTERVAL` s of game time) reads wants (Need) and goods to clear (Clear)
from the stores and creates `Task.Kind.CARRY` legs: source store → destination store, chosen by
`Nav.walk_cost` (path length, cached until the grid changes), with reservations out at the source
and in at the destination.

**Tech:** Godot 4.7, typed GDScript, headless test scripts in `scripts/tools/`.

## Global constraints

- Code, comments and UI texts in English; sparse `##` doc comments, tabs, typed GDScript; match the
  surrounding code.
- No save migrations: format changes bump `SaveGame.VERSION` (Task 4 bumps it to 3).
- Tuning numbers live in `scripts/sim/defs.gd`.
- Performance (CLAUDE.md): nothing per frame that scales with the map; the planner runs on a timer;
  path lengths are cached and the cache is dropped only when the grid changes.
- Every existing test keeps passing: `logistics_test`, `tech_test`, `mill_test`, `road_test`,
  `river_test`, `save_test`, `tools_test` (run as in CLAUDE.md, wrapped in `perl -e 'alarm 300; exec @ARGV'`).
- Commit on the current branch with a clear message; never touch `.claude/`; scratch output to `tmp/`.

## Review focus

1. Goods are never lost or duplicated through a leg (pick-up, drop, abort, cancelled destination,
   demolished source, save in the middle).
2. Reservations are always released (task removed, worker aborts, store removed) — a leaked
   `reserved_out` makes goods unusable forever, a leaked `reserved_in` blocks a mill or site.
3. A mill input never ends up above `in_cap` (input + reserved_in ≤ in_cap).
4. Construction sites still start building only once all material is there; moved buildings still
   use their own pile first and the pickup path still works (tools_test).
5. Planner cost stays small: a quick measurement of `Planner.tick` on the scenario.

---

### Task 1: `Nav.walk_cost` — cached path lengths (parallel, worktree)

**Files:** modify `scripts/sim/nav.gd`; test: extend `scripts/tools/road_test.gd` (it already builds a
World) or `logistics_test.gd` — pick `logistics_test.gd`, new function `_test_walk_cost()` called from
the main runner.

**Produces:**
- `var version := 0` on `Nav`, incremented by `set_solid`, `set_cost`, `set_pen`, `remove_pen`.
- `func walk_cost(from: Vector2i, to: Vector2i) -> float` — length of `find_path(from, to)` in tiles
  (straight step 1.0, diagonal step `sqrt(2)`, each step multiplied by the weight scale of the tile
  stepped onto via `astar.get_point_weight_scale`; pen tiles count 1.0), `INF` when unreachable,
  `0.0` when `from == to`. Memoised in a Dictionary keyed by `Vector4i(from.x, from.y, to.x, to.y)`;
  the memo is cleared when `version` changed since it was filled. Cap the memo at 20 000 entries
  (clear it when full).

**Tests (`_test_walk_cost`):** open ground straight line of 10 tiles → 10.0 (±0.01); a wall that
forces a detour → cost greater than straight distance and equal to a second call (memo); after
`set_solid` opening a gap the cost drops (memo invalidated); unreachable target → `INF`.

### Task 2: numbered building names, player renaming (parallel, worktree)

**Files:** `scripts/sim/building.gd`, `scripts/sim/world.gd` (placing, finishing sites, moving,
`stock_split`), `scripts/core/save_game.gd`, `scripts/ui/info_panel.gd` (header rename, the same way
workers are renamed there), test in `scripts/tools/tools_test.gd`.

**Produces:**
- `Building.number := 1` and `Building.custom_name := ""`. `display_name()` returns `custom_name`
  when set, else the def name, plus `" %d" % number` when `number > 1` ("Storage Barn 2").
  `ConstructionSite.display_name()` keeps its suffixes on top of that.
- Numbers: when a site or building is created, `number` = the lowest positive number not used by
  another building / site / field with the same `def_id`. A site's number and custom name carry
  over to the finished building; a moved building keeps its number and name (the new site gets
  them, the dismantle site shows them too). Roads are not numbered.
- `World.rename_building(b: Building, name: String) -> bool`: trims, max 24 characters, empty
  resets to the default name; emits `building_changed(b)`.
- `stock_split` uses `display_name()` so two barns read "Storage Barn" and "Storage Barn 2".
- Save: per building `"number"` and `"name"` (read with `.get` defaults).
- Info panel: the building title can be renamed like a worker's name (same widget / interaction).

**Tests (tools_test):** two barns → "Storage Barn" and "Storage Barn 2"; demolish the first, place a
third → it gets number 1; rename → `display_name()` is the new name, empty name → default again;
save round trip keeps numbers and names; the split tooltip lists both barns by their names.

### Task 3: places become stores (behaviour unchanged)

**Files:** `scripts/sim/store.gd`, `building.gd`, `field.gd`, `construction_site.gd`, `world.gd`,
`scripts/core/save_game.gd`; tests keep passing, add `_test_places()` in `logistics_test.gd`.

**Produces:**
- `Store`: `enum Kind { STORAGE, SITE, INPUT, OUTPUT, GATE, MOVE_PILE, GROUND }`, `var kind`,
  `var cell: Vector2i` (where a worker stands to put / take), `var owner: Building` (null for ground
  piles), `func reserve_in(res, n) -> void`, `func release_in(res, n) -> void` (mirror of out), and
  `func label() -> String` (owner's `display_name()`, ground pile: "Pile").
- `Building.input_store` / `output_store` (kinds INPUT / OUTPUT) for buildings with a recipe;
  `input` / `output` become properties reading / writing the amount of the recipe's in / out good.
  `Field.gate_store` (GATE); `pile` becomes a property over the amount of the field's crop there.
  `ConstructionSite.supply` (SITE) with `delivered` a property returning / replacing
  `supply.contents`; `pile_store` (MOVE_PILE) with `pile` likewise. Barns keep `Building.store`
  (kind STORAGE). Store `cell` follows the owner's access tile (also after a field gate change:
  update it in `set_field_gate`; moved pile: `pile_cell`).
- `World.places() -> Array[Store]`: every store on the map (barns, site supplies and move piles,
  mill buffers, field gate piles; ground piles join in Task 5), computed on demand.
- `stores()` / `total()` keep meaning storage barns (+ loose) only.

**Tests:** all existing tests pass unchanged (they read the properties). `_test_places`: a field,
a mill and a site each show up in `places()` with the right kind and cell; writing `f.pile` /
`mill.input` / `site.delivered[...]` is visible in the store and back.

### Task 4: planner and carry legs

**Files:** create `scripts/sim/planner.gd` (`class_name Planner`); modify `task.gd`,
`task_queue.gd`, `worker.gd`, `world.gd`, `defs.gd`, `save_game.gd`, `scripts/ui/tasks_panel.gd`,
`scripts/ui/info_panel.gd`, `scripts/view/worker_figure.gd`, tests.

**Consumes:** `Nav.walk_cost` (Task 1), `Store` kinds and `World.places()` (Task 3).

**Produces / rules:**
- `Task.Kind.CARRY` replaces `DELIVER` and `HAUL` (remove both). A leg: `fetch` = good,
  `fetch_amount` = load, `fetch_from` = source store (reserved out when the leg is made),
  new `var dst: Store` and `var dst_reserved := 0.0` (reserved in), `cell` = `dst.cell` (sites: the
  usual site spots), `site` / `building` / `field` = the owner the leg serves (for Priorities: the
  destination owner for a need, the source owner for a clear). `label()`:
  `"Carry %s from %s to %s"` (good lower-case, `Store.label()` of both ends).
- `Defs.PLANNER_INTERVAL := 1.0`. `World` holds a `Planner`, ticked from `World.tick`.
- Need (destination wants goods): SITE supply while the site is in `Stage.DELIVERY` and not waiting
  for a move (partner / by_pickup): `material - delivered - reserved_in` per good; INPUT store of a
  working (not upgrading) mill: `in_cap - input - reserved_in`. Loads of `Defs.hand_load`, pieces
  whole. Source = the supplier with `available > 0` at the lowest `walk_cost(src.cell, dst.cell)`
  (unreachable skipped). Suppliers: STORAGE, OUTPUT, GATE, GROUND, and a MOVE_PILE only for its own
  site — tried first for that site.
- Clear (goods must leave): OUTPUT (full hand loads; the smaller rest once the mill is idle, as
  today), GATE (today's `_queue_hauls` rule, including leaving the pile for the pickup when
  `pickup_collects`), GROUND (everything). Needs are planned first, so wheat at a gate can go
  straight into a mill. The rest goes to the STORAGE store with room that accepts it at the lowest
  walk cost. No barn → nothing is planned.
- Worker flow for CARRY: walk to the source, take the reserved goods, walk to the destination,
  `LOAD_TIME` work, put them into the destination store (release `dst_reserved`). Then owner
  reactions: a site with all material starts building (`_start_building`); a mill input runs
  `_update_building`; a source gate re-checks the crop switch; storage emits `stock_changed`.
- Wheelbarrow: a leg from a GATE store with a backlog of at least two hand loads, when a barn holds
  a wheelbarrow: the worker first walks to that barn for it, merges other waiting legs with the same
  source and destination into the leg up to `WHEELBARROW_CAPACITY` (moving their reservations), and
  tops up at the gate with what was harvested since. The wheelbarrow is put back at the destination
  barn (or carried to the nearest barn).
- Cancelling: removing a store (building demolished, site cancelled, field removed) removes its
  waiting legs and aborts workers on legs to or from it; every reservation is released.
- Seed for field rows stays with the sowing task, but the barn is chosen by `walk_cost`.
- Old code removed: `_queue_hauls`, `_fetch_pending`, `_from_pile`, `_split_fetch`, DELIVER creation
  in `_after_clearing` / `_update_building`, `Field.pile_reserved`, `Building.incoming` /
  `out_reserved` (read `reserved_in` / `reserved_out` instead). `seed_shortage`, `alerts`,
  `processing_demand`, the info panel's in-transit counts and the Tasks panel use the legs.
- Save: legs are not saved (planned again after loading, like pickup trips); `SaveGame.VERSION = 3`.
- Measure: print the average and max `Planner.tick` time over the scenario run in
  `logistics_test` (or a quick timing in the scenario), keep it well under 1 ms average.

**Tests (logistics_test):** need served from the cheapest source by path (a straight-line-closer barn
behind a wall loses); wheat at a field gate with an empty barn goes straight into a mill that wants
it; goods conserved over a long run (sum of `places()` + carried + loose constant); mill
`input + reserved_in <= in_cap` every tick; demolishing a site with legs in flight releases every
reservation and loses nothing. Existing tests updated where they built DELIVER / HAUL tasks by hand.

### Task 5: felled wood as a ground pile

**Files:** `world.gd`, `worker.gd`, `defs.gd`, `save_game.gd`, new `scripts/view/pile_view.gd` (+ wiring
where other views are created), tests.

**Produces:**
- `World.ground_piles: Array[Store]` (kind GROUND, `cell`, a `category` for its legs),
  `func drop_goods(res, n, cell, category) -> Store`: adds to a ground pile of the same good within
  2 tiles that has room (`Defs.GROUND_PILE_CAPACITY := 200.0` kg), else a new pile on the nearest
  walkable tile outside building / site / field footprints (search up to radius 4). Signals
  `pile_added(s)`, `pile_changed(s)`, `pile_removed(s)`; an empty ground pile is removed.
- CHOP completion drops `WOOD_PER_TREE` logs at the worker's spot (category FELLING for marked
  trees, CONSTRUCTION for site clearing) instead of the worker carrying them; the planner clears it
  (sawmill input that wants wood first, else the cheapest barn).
- A worker whose leg breaks (abort while carrying) drops the goods as a ground pile; the planner
  plans them again.
- `places()` includes ground piles. Saved as `"ground_piles"` (cell, category, store).
- View: a small heap at each pile using existing models (logs / crates / sacks by good), scaled by
  fill, updated on the signals (no per-frame rebuild).

**Tests (logistics_test):** a marked tree is felled → a pile with the logs appears, then the logs end
in the barn and the pile is gone; with a sawmill wanting wood the logs go straight to it; a pile
survives a save round trip; conservation holds.

### Task 6: docs, screenshots, sweep (controller)

Spec status line, CLAUDE.md decisions (names, ground piles), full test run, scenario screenshots
(`--shots=tmp/shots`) checked for errors, menu farm still loads.
