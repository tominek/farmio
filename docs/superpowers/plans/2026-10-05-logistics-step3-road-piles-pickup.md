# Logistics step 3: road piles and the multi-stop pickup — implementation plan

> For agentic workers: each task is done by one implementer subagent and checked by a reviewer.
> Read `CLAUDE.md` (rules, commands, tests) before starting. Tasks marked **PARALLEL** may run at
> the same time in separate worktrees; their files do not overlap (or only by a few lines, noted).

**Goal:** Workers become lazy in a sensible way. When a carry is long, the planner compares walking
it with "walk to a road, let the pickup drive it, walk the rest" and picks the cheaper route by cost.
Goods handed off by a road lie on a **road pile** (an automatic ground pile beside a road). The
pickup collects waiting goods in one **multi-stop trip** that replaces today's three hard-wired trip
kinds (Dealer, field pickup, moved building); a Dealer visit (sell / buy / hire) is one more stop.
The player sees the chain in Tasks, the trip in the Garage panel, road piles on the map at three
fill levels, and can say "Carry to the barn now" on a road pile.

**Spec:** `docs/superpowers/specs/2026-10-04-logistics-design.md` (sections 1–3, step 3 of 5).
Step 2 plan (done): `docs/superpowers/plans/2026-10-05-logistics-step2-planner.md`.
Design: kit section 17 — `art/ui/design/shots/s17a.png` (road pile panel), `s17c.png` (Tasks legs
with chips, pickup trip groups, Garage panel with the stop list and load bar), `s17d.png` (road piles
at three fill levels for logs / planks / sacks / gravel). Sheds and collection points (17a right,
17b, 17d right, 17e, 17f) are step 4, **not** in this plan.

**Architecture:**

- **Route by cost (one rule).** For every carry the planner already plans (a need: source →
  consumer; a clear: source → cheapest barn) it now computes a *route*: either **direct** (one walking
  leg, as today) or **via the pickup**: walk source → hand-off A, ride A → hand-off B, walk B →
  destination. A store is its own hand-off when it is a **vehicle stop** (its spot is within
  `Defs.STOP_REACH` tiles of a connected road block: barns, field gates, mill outputs, moved-building
  piles, sites, ground piles that happen to lie by a road). Otherwise the hand-off is a **road pile**
  on a free tile beside the road block nearest that store. The via route is only evaluated when a
  vehicle can run trips and the direct walk is at least `Defs.ROUTE_MIN_WALK` tiles (or unwalkable).
- **Chains of legs.** A via route becomes a chain of `Task`s linked by `Task.next`: `CARRY`
  (walk) and the new `Task.Kind.RIDE` (a vehicle leg). Only the first leg is in the queue; later legs
  wait in `next`, already holding the room they will need at their destination (so the final
  destination's `reserved_in` is held for the whole way). When a leg's goods arrive at the
  intermediate store, the next leg *opens*: it reserves those goods out of that store and joins the
  queue. Removing a leg (`TaskQueue.remove` → `Task.release()`) also releases every leg after it, so
  every existing abort path stays correct. If anything breaks, the goods stay where they are (a pile)
  and are planned again.
- **Trips.** A *dispatcher* (once a second) gathers waiting `RIDE` legs for a parked vehicle into
  one `TRIP` task with a list of stops (load at a store, unload at a store, the Dealer), built by
  cheapest insertion under the pickup's capacity and a detour limit. The existing trip runner
  (board, drive along `RoadNav` routes, helpers shuttling chunks with the carry animation, park) is
  kept and generalised: a stop step loads / unloads the goods of its rides at its store. The Dealer
  becomes a store too (`Store.Kind.DEALER`): its contents are the goods ordered and paid for, a ride
  *to* it sells, a ride *from* it collects a purchase.
- **Costs** (all illustrative, tuned in step 5) live in `defs.gd`; road drive times are memoised in
  `RoadNav`; walk costs stay `Nav.walk_cost` under `Defs.PLANNER_BUDGET_USEC`.

**Tech:** Godot 4.7, typed GDScript, headless test scripts in `scripts/tools/`.

## Global constraints

- Code, comments and UI texts in English; sparse `##` doc comments, tabs, typed GDScript; match the
  surrounding code. No new `class_name` unless the task says so (then run `--import`).
- Tuning numbers live in `scripts/sim/defs.gd`. No save migrations: Task 4 bumps
  `SaveGame.VERSION` to 4. Trips, rides and carry legs are not saved (planned again after loading);
  goods in the pickup are saved as loose goods → a barn, as today.
- Performance (CLAUDE.md): nothing per frame scales with the map or the number of stores; the
  planner and the dispatcher run on the 1 s timer; walk costs, hand-off spots and drive times are
  cached; the planner keeps its time budget. Every task states the cost of what it adds.
- Every existing test keeps passing: `logistics_test`, `tech_test`, `mill_test`, `road_test`,
  `river_test`, `save_test`, `tools_test` (run as in CLAUDE.md, wrapped in
  `perl -e 'alarm 300; exec @ARGV'`). A test that pins old behaviour on purpose changed by this plan
  is updated, and the report says which and why.
- Commit on the current branch (`restart/design-and-art`, or the worktree branch for PARALLEL
  tasks) with a clear message; never touch `.claude/`; scratch output to `tmp/`.

## Review focus

1. **Goods conservation through every leg**, vehicle legs included: walking to a road pile, loading
   (chunk in flight), in the cargo, unloading, selling, buying, a leg or ride dropped mid-way, a store
   demolished while the pickup is on its way to it, a save in the middle of a trip. The test sum is
   places + carried + loose + cargo (+ money for sold goods).
2. **Reservations through a chain:** the final destination's room is promised from planning to
   arrival; intermediate stores are never overfilled (`room()` counts promised goods); every claim
   (source out, every leg's room in, wheelbarrow) is released when any leg breaks; a leaked
   `reserved_in` on a road pile keeps an empty pile alive forever.
3. **No double planning:** goods on a road pile promised to a ride are not cleared by hand; a need
   served by a chain is not planned again; a ride is in at most one trip.
4. **Old trip behaviour still works** through the general trip: Dealer sale (keep amounts,
   processing demand first), purchases and hires, field pickup, moved building haul, garage moves
   (no trips meanwhile), passengers getting off.
5. **Cost:** planner runs stay inside the budget on the 512² probe; the dispatcher is cheap; a short
   carry never gets a hand-off.

---

## Parallel plan

| Wave | Tasks | Notes |
|---|---|---|
| 0 | **Task 1** (contracts) ∥ **Task 5** (pile art) | Task 5 touches only `pile_view.gd` and may start at once |
| 1 | **Task 2** (chains + road piles, sim) ∥ **Task 6** (Tasks panel) ∥ **Task 7** (info / dealer panels) ∥ Task 5 continues | UI tasks build on the Task 1 interface and render sample data |
| 2 | **Task 3** (general trip) | needs Task 2 |
| 3 | **Task 4** (Dealer as stops, save v4) ∥ **Task 8** (menu showcase) | Task 8 only touches `menu_farm.gd` |
| 4 | **Task 9** (integration, screenshots, docs — controller) | |

Tasks 2 → 3 → 4 are the sim core and run one after another (they all edit `world.gd`,
`planner.gd`). Tasks 5, 6, 7, 8 each own their files; the only shared file is `game.gd` (Task 7 adds
one signal connection; Task 4 edits the `--shots` scenario strings) — merge by hand.

---

### Task 1: contracts — constants, fields, interfaces (small, first)

**Files:** `scripts/sim/defs.gd`, `task.gd`, `task_queue.gd`, `store.gd`, `vehicle.gd`,
`road_nav.gd`, `world.gd` (stubs only, one block at the end of the file), a new icon
`assets/ui/icons/kit/pickup.svg` (a small pickup truck in the style of the kit icons, e.g. drawn
after `wheelbarrow.svg`; the design shows it in 17a / 17c), test in
`scripts/tools/road_test.gd`.

**Produces (exact names; later tasks and the UI rely on them):**

- `Defs` (comment each like the neighbours; all illustrative):
  `WALK_COST := 1.0` (per second a worker walks with a load), `DRIVE_COST := 0.15` (per second
  the pickup drives; it is shared by everything aboard), `HANDLING_COST := 15.0` (per load into /
  unload from a vehicle), `VEHICLE_WAIT_COST := 30.0` (expected wait for the pickup),
  `ROUTE_MIN_WALK := 40.0` (tiles; a shorter walk is never split), `STOP_REACH := 2` (tiles from a
  road block that make a store a vehicle stop), `ROAD_PILE_SEARCH := 24` (tiles searched for a road
  to put a road pile by), `ROAD_PILE_JOIN := 4` (a road pile of the same good with room this near is
  used instead of a new one), `TRIP_MAX_WAIT := 60.0` (s the oldest waiting ride waits before the
  pickup goes with a small load), `TRIP_MAX_STOPS := 8`, `TRIP_DETOUR := 0.5` and
  `TRIP_DETOUR_MIN := 20.0` (a ride joins a trip when the extra driving is at most
  `max(TRIP_DETOUR_MIN, TRIP_DETOUR × its own drive)` seconds). `MOVE_PICKUP_WALK` and
  `PICKUP_HAUL_MIN` stay until Task 3 removes them.
- `Task.Kind.RIDE` **appended** at the end of the enum (saved task kinds keep their ints). New fields:
  - `next: Task` — the following leg of the chain, not in the queue yet (holds `dst_reserved` at its
    `dst`; `fetch_from` null until it opens).
  - `plan: Array[Dictionary]` — shared by all legs of one chain: `{"by": &"walk" | &"ride",
    "from": Store, "to": Store}` per leg, in order; empty for a lone leg.
  - `leg_i := 0` — index of this leg in `plan`.
  - `trip: Task` — RIDE: the TRIP that carries it (null while waiting).
  - `loaded := 0.0` — RIDE: amount of `fetch` in the vehicle.
  - `urgent := false` — "Carry to the barn now": goes before everything else.
  - `stops: Array[Dictionary]` — TRIP: the stops (Task 3 fills it; see `World.trip_preview`).
  - `release()` also calls `next.release()` (recursively). `label()` for RIDE:
    `"Drive %s from %s to %s"`.
  - `func final_dst() -> Store` (`plan.back()["to"]` or `dst`).
- `TaskQueue`: `pick` skips RIDE (rides are done by trips); `pending_count` skips RIDE;
  `priority` returns `-1000` for `urgent`.
- `Store`: `Kind.DEALER` and `Origin.ROAD` appended; `var hand_only := false` (a road pile the
  player asked to carry by hand; not saved). `label()`: a GROUND pile with origin ROAD →
  `"road pile"`; DEALER → `"Dealer"`. `func vehicle_only() -> bool` (DEALER).
- `Vehicle`: `var trip: Task = null`, `var status := "In the garage"`,
  `func cargo_weight() -> float` (kg, pieces by `Defs.weight`).
- `RoadNav`: `var version := 0` (bumped by `add_block` / `remove_block`),
  `func drive_cost(from_block: Vector2i, to_block: Vector2i) -> float` — seconds of driving along
  the block path (blocks × `ROAD_BLOCK` / `PICKUP_SPEED`; surface ignored), `INF` when not
  connected, memoised by `Vector4i`, memo cleared when `version` changed, capped like `Nav`.
- `World` (new section "# --- vehicle stops and trips (logistics step 3)"):
  - `func stop_block(s: Store) -> Variant` — the road block a vehicle stops at for this store:
    `road_nav.block_near(store_spot(s))` (DEALER: near the Dealer's access), or null. Real
    implementation now (cheap: 25 cells).
  - `func is_road_pile(s: Store) -> bool` — GROUND and `stop_block(s) != null`. Real.
  - `func trip_preview(v: Vehicle) -> Dictionary` — **stub** returning the idle shape below; Task 3
    implements it. Shape:
    `{"state": &"idle" | &"gathering" | &"waiting" | &"running", "stops": Array[Dictionary],
    "stop_i": int (current stop, -1 when not running), "load": float (kg aboard),
    "capacity": float (kg), "starts_in": float (s until a gathering trip leaves, -1 unknown)}`;
    each stop `{"kind": &"load" | &"unload" | &"dealer", "store": Store, "label": String
    ("road pile by the forest", "Storage Barn", "Dealer"), "goods": Dictionary (res → amount loaded
    / unloaded / sold there), "buy": Dictionary (res → amount, dealer), "hires": int,
    "money": int (≈ quacks for the sale), "state": &"done" | &"current" | &"next",
    "eta": float (s from now, -1 unknown), "left": float (kg still to move at the current stop)}`.
  - `func carry_now(s: Store) -> bool` and `func carry_now_blocker(s: Store) -> String` — **stubs**
    (`false` / `"Not yet"`); Task 2 implements them.

**Tests (`road_test`):** `drive_cost` on a straight road of 5 blocks → `5 × 2 / PICKUP_SPEED`;
unconnected → INF; memo invalidated by `add_block` closing a gap. All tests pass unchanged.

**Cost:** none per frame; `drive_cost` one AStarGrid2D search per new pair on a grid of size²/4.

### Task 2: route by cost, chains and road piles (sim core 1)

**Files:** `scripts/sim/planner.gd`, `world.gd`, `worker.gd` (only if needed for `start`), tests in
`logistics_test.gd`.

**Consumes:** Task 1.

**Produces / rules:**

- `World.can_drive() -> bool` — some vehicle exists whose garage is not a construction site and
  whose block is a road block. Vehicle routes are planned only then.
- `World.road_pile_spot(near: Vector2i) -> Variant` — the free tile (`_pile_ok`, not a road tile)
  orthogonally next to a road block, nearest to `near` in a straight line, within
  `ROAD_PILE_SEARCH`; null if none. Scan road blocks ring by ring around `near` (≤ ~600 dict
  lookups); only blocks connected to the vehicle's block (`drive_cost` < INF) count.
- `World.add_road_pile(cell: Vector2i, res: StringName, category: int) -> Store` — an empty GROUND
  store, origin ROAD, capacity `GROUND_PILE_CAPACITY`, filter `{res}`; registered with
  `add_ground_pile` (signal `pile_added`).
- Empty piles: `_pile_taken` removes a pile only when empty **and** nothing is reserved in. The
  planner tick ends with a sweep removing empty GROUND piles without `reserved_in` (O(piles)).
- `Planner._route(src: Store, dst: Store, res: StringName) -> Dictionary` →
  `{"cost": float, "a": Variant, "b": Variant}`; `a` / `b` null = direct, else the hand-off at the
  source / destination side: a `Store` (the store itself when it is a stop; an existing road pile of
  the same good with room within `ROAD_PILE_JOIN` of the spot) or a `Vector2i` (a road pile still
  to make).
  - direct = `walk(src, dst) / WALK_SPEED × WALK_COST` (INF if either end is `vehicle_only`).
    A `hand_only` source is always routed direct.
  - via (only if `can_drive()`, `!src.hand_only`, and the direct walk ≥ `ROUTE_MIN_WALK` tiles or
    INF) = `walk(src, a) / WALK_SPEED × WALK_COST + 2 × HANDLING_COST + drive(a, b) × DRIVE_COST +
    VEHICLE_WAIT_COST + walk(b, dst) / WALK_SPEED × WALK_COST`; `walk(x, x) = 0`.
  - Hand-offs per store are cached per run (`_handoffs`), walk lookups go through `_walk` (budget).
- `_source` (needs) and the barn choice in `_clear` use `_route(...)["cost"]` instead of the plain
  walk; `_saves` stays walk-based. A moved building's own pile is still tried first.
- `Planner._send(src, dst, res, load, route)` replaces `_leg`:
  - direct → one CARRY leg exactly as `_leg` today (labels, category, served owner).
  - via → legs `walk src→A` (if A ≠ src), `ride A→B`, `walk B→dst` (if B ≠ dst); a `Vector2i`
    hand-off becomes `add_road_pile` now. All legs share `plan`, have `leg_i`, the chain's category
    and served owner (`site` / `building` / `field` as `_leg` decides), and `created` = now. First
    leg: `reserve_out` at src and `reserve_in` at its dst; every later leg: `reserve_in` at its dst
    (held in `dst_reserved`), linked by `next`, not queued. A RIDE as first leg goes into the queue.
  - Load size: a chain with any walking leg carries one hand load (as today). A ride-only chain
    (both ends stops) carries up to `PICKUP_CAPACITY`, and a new ride-only chain with the same
    src, dst and good as a waiting, untripped ride-only RIDE grows that ride instead (claims added).
- `World._open_next(t: Task, n: float)` — called when leg `t` put `n` into its intermediate store:
  `nxt = t.next; t.next = null` (**before** `t` is removed, so its release does not touch `nxt`);
  `nxt.fetch_from = t.dst`, `nxt.fetch_reserved = t.dst.reserve_out(res, n)`, `nxt.fetch_amount = n`;
  if `n` is less than planned, shrink every later leg's `dst_reserved` (release the difference);
  `tasks.add(nxt)`. `complete_task` for CARRY takes `next` off first, `_put_carried` puts the goods,
  then `_open_next`. Put into a GROUND dst emits `pile_changed`.
- Chains vs. removal: `_drop_legs(b)` and `_remove_pile(s)` also look down each queued leg's `next`
  chain: a later leg that goes to / from a removed store cuts the chain before it (release from that
  leg on, `prev.next = null`); the current leg goes on to its own destination, where the goods are
  cleared later. Waiting RIDE legs from / to a removed store are removed like CARRY legs (a RIDE
  already in a trip is handled in Task 3; until then rides never join trips).
- `_drop_stranded` also drops waiting RIDE legs (no trip) whose ends have no `stop_block` or no
  `drive_cost`.
- `World.available(res)` also counts goods held by waiting rides going to a barn (no false
  "order it at the Dealer" alert while the pickup brings them); `waiting_clear` stays CARRY-only.
  `category_counts` skips RIDE.
- `carry_now(s)` / `carry_now_blocker(s)` (real): blocker `"Nothing to carry"` (empty or all
  promised to a walking worker), `"No barn can take it"`; else: drop the pile's waiting legs and
  rides (claims released), set `s.hand_only = true`, plan direct CARRY legs to the cheapest barn by
  walk (one wheelbarrow load when a barn holds a free wheelbarrow: claimed like `_take_wheelbarrow`
  without its backlog rule, else hand loads), `urgent = true`, and hand the first leg to the nearest
  idle worker who can reach the pile (same start as the IDLE branch of `Worker.tick`: extract it as
  `Worker.start(world, t)`). Without an idle worker the urgent leg waits at the top of the queue.
- Rides wait (no trips yet in this task); the planner never plans them twice.

**Tests (logistics_test, new):**
- `_test_short_walk_direct`: a ground pile 15 tiles from a barn by the road, pickup present → one
  CARRY leg straight to the barn, no road pile.
- `_test_far_pile_chain`: a marked tree ≥ 80 walk tiles from the barn, a road 5 tiles from the tree
  connected to the barn's road, a garage with a pickup → after felling: a road pile appears beside
  the road (origin ROAD, nearer the tree than the barn), the walking leg brings the log there, a RIDE
  leg opens (pile `reserved_out` = the log), the barn's `reserved_in` holds the log from planning to
  now; without the garage the same tree is walked directly.
- `_test_chain_break`: demolish the destination while leg 1 walks → leg 1 still ends at the road
  pile, every downstream claim released, the log is planned again; and aborting leg 1's worker drops
  the log as a ground pile with all claims released.
- `_reservations_match` counts RIDE legs and unopened `next` legs; conservation every tick.
- `_test_carry_now`: a road pile with 120 kg → `carry_now` → an idle worker gets an urgent leg at
  once, with a wheelbarrow, and the pile ends in the barn by hand; no RIDE is planned from it.
- Timing: print the planner's average / max over the long run and the 512² probe from step 2
  (`tmp/planner_probe.gd` or a copy in the test); runs stay within budget + one search.

**Cost:** per run per store at most one hand-off scan (cached for the run) and two extra budgeted
walk lookups for long carries; chain creation O(legs).

### Task 3: one general multi-stop trip (sim core 2)

**Files:** `scripts/sim/world.gd`, `planner.gd` (gate rule), `construction_site.gd` (`by_pickup`
removed), `defs.gd` (remove `MOVE_PICKUP_WALK`, `PICKUP_HAUL_MIN`), `save_game.gd` (drop
`by_pickup`), `scripts/tools/logistics_test.gd`, `tools_test.gd`, `save_test.gd`.

**Consumes:** Tasks 1, 2.

**Produces / rules:**

- **Per vehicle:** `Vehicle.trip` replaces `World._trip_task`; `Vehicle.status` replaces the
  `trip_status` assignments. `World.trip_status` stays as a read-only property (`vehicles[0].status`
  or `"In the garage"`) so the UI keeps working. Everything that took `vehicles[0]` loops over
  vehicles where it is about trips.
- **Dispatcher** `World._dispatch()` replaces `_maybe_queue_trip` (same 1 s timer): for each parked
  vehicle without a trip, garage not a construction site: candidates = waiting RIDE legs with
  `trip == null` whose stops are connected to the vehicle. Start when the candidates weigh at least
  `MIN_TRIP_LOAD`, or the oldest has waited `TRIP_MAX_WAIT`, or `_force_trip`, or hires wait (Task 4).
  Then `_assemble(v, candidates) -> Task` and `tasks.add`; status "Waiting for a driver".
- **Assembly** (cheapest insertion): candidates sorted by `TaskQueue.priority`, then age. Start with
  the first ride (a load stop at its `fetch_from`, an unload stop at its `dst`); insert each next
  ride's load stop and its unload stop after it where the extra drive (`drive_cost` between stop
  blocks, from and back to the garage) is least; accept if the load never exceeds
  `PICKUP_CAPACITY` (kg) at any point, stops ≤ `TRIP_MAX_STOPS` and the extra drive ≤
  `max(TRIP_DETOUR_MIN, TRIP_DETOUR × the ride's own drive)`. Rides at the same store share its stop.
  A ride too big for the room left is split (claims moved) so the trip runs full. `trip.stops`:
  `{"store": Store, "block": Vector2i, "unload": Array[Task], "load": Array[Task], "dealer": bool}`;
  `ride.trip = trip`. Trip category = the most urgent category of its rides. Cost: candidates capped
  at 24, so ≤ 24 × 8² memoised `drive_cost` lookups, once per dispatch.
- **Steps** (built from stops): `board`; per stop `drive` + `unload` (if any) + `load` (if any)
  (Task 4 adds the dealer steps); then `unload_rest` at the barn stop nearest the garage, skipped
  when the cargo is empty (cargo whose ride was dropped, passengers get off there); `drive` home;
  `park`. Statuses: "Driving to {label}", "Loading at {label}", "Unloading at {label}", "Returning
  to the garage", "In the garage".
- **Runner:** keep `trip_tick`, `_drive`, `_transfer`, `help_tick`, `_shuttle` and the HELP
  helpers. `_prepare_transfer` builds the queue from the stop's rides: load items
  `[res, ride.fetch_reserved, ride]` (only what fits), unload items `[res, ride.loaded, ride]`;
  place = `store_spot(store)`; helpers as today (not at the Dealer). `_move_chunk(s, v, res, n, ride)`:
  - load: `store.release_out` + `take` (only what is there), `ride.fetch_reserved -= n`,
    `ride.loaded += got`, cargo += got, source reactions (GATE: dirty + `_try_switch_crop`;
    MOVE_PILE: `site_changed`; GROUND: `_pile_taken`).
  - unload: cargo −= n, `ride.loaded -= n`; the goods go into `ride.dst` through the same code as a
    walking leg's arrival (refactor `_put_carried` into `_put_into(t, res, n, at)` with the owner
    reactions: site starts building when supplied, mill `_update_building`, barn, gone → `put_goods`);
    `dst_reserved` shrinks by n. When the ride has nothing left aboard or to load: `_open_next` (if
    a chain goes on) and `tasks.remove(ride)`.
  - A load step whose ride was dropped or whose goods are gone skips it (claims released); an unload
    whose destination is gone leaves the goods aboard for `unload_rest`.
- **Removal while a trip runs:** `_drop_legs` / `_remove_pile` on a ride in a trip: not loaded yet →
  removed from its stop (claims released); loaded → the ride is removed, its goods stay in the cargo
  (unloaded by `unload_rest`). `demolish_blocker` / `move_blocker`: "The pickup is loading here" while
  the vehicle is at a stop step of that building's store (replaces the field-only rule).
- **Old trip kinds become rides:** delete `_plan_haul`, `_site_for_pickup`, `_pickup_hauls`,
  `_after_pickup`, `_field_for_pickup`, `pickup_collects`, the field/haul branches of `_plan_trip`
  and step types `pick_up`, `load_pile`, `unload_site`; `ConstructionSite.by_pickup` goes (a moved
  site wants its material once the old building is down; its own pile is tried first and the route
  by cost picks the pickup when far). The GATE clear rule loses the pickup branch; its "rest only
  when no harvest runs" rule stays for walking chains, a ride-only chain takes whatever is there
  (and grows). The Dealer trip (`_plan_trip` Dealer part, `load` / `sell` / `buy` / `hire` steps)
  stays as it is until Task 4, run by the same runner as a trip whose stops are built the old way.
- `trip_preview(v)` real: `idle` (parked, nothing waiting), `gathering` (rides waiting, no trip;
  `starts_in` = `TRIP_MAX_WAIT` − oldest wait, 0 when the load is enough), `waiting` (trip made, no
  driver), `running` (`stop_i`, `eta` from memoised drive costs plus ~`LOAD_TIME` per hand load, `left`).
- Save: no trip state; `by_pickup` neither written nor read. Goods aboard are saved as loose (as
  today); a load chunk in flight is still at its store, an unload chunk still in the cargo.

**Tests:**
- logistics_test `_test_pickup_brings_pile`: the far tree of Task 2 runs on: the pickup collects
  the road pile and unloads at the barn; the pile is removed; the log is in the barn; conservation
  (places + carried + loose + cargo) and `_reservations_match` every tick.
- `_test_multi_stop`: two road piles along one road and a field gate by the same road, barn at
  the end → one trip with ≥ 3 stops, `cargo_weight() ≤ PICKUP_CAPACITY` every tick, everything
  ends in the barn.
- `_test_field_pickup_trip`: a gate by the road far from the barn (walk ≥ `ROUTE_MIN_WALK`) → the
  harvest goes by a trip, never by a walking leg to the barn.
- `_test_stop_demolished`: demolish an unload stop's building while the goods are aboard → they end
  in the barn via `unload_rest`; nothing lost.
- `_test_save_mid_trip`: save while loading at a road pile and while driving with cargo → totals
  equal before / after load (extend `_test_save_mid_transfer`).
- tools_test `_pickup_haul`: no `by_pickup`; check that a RIDE from the move pile happened (or the
  status "Loading at Hand Mill (old spot)") and the mill stands; `_garage` keeps passing (order
  still collected by the old Dealer path).

**Cost:** dispatcher once a second, O(24 × 8²) memoised lookups; runner per frame only the current
step (as today).

### Task 4: the Dealer as stops; save v4 (sim core 3)

**Files:** `scripts/sim/world.gd`, `planner.gd`, `scripts/core/save_game.gd`, `scripts/game.gd`
(`--shots` scenario strings only), tests (`logistics_test`, `tools_test`, `save_test`).

**Consumes:** Task 3.

**Produces / rules:**
- `World.dealer_store: Store` (Kind DEALER, made in `_init`; `owner` / `cell` set when the Dealer
  building is added). `orders` becomes a property over `dealer_store.contents` (the getter returns
  the dictionary, so `world.orders[res]` / `.get` / `.is_empty()` keep working; the setter replaces
  the contents). `order()` puts into it.
- Planner: DEALER is a **supplier** for needs and a **clear** (everything to the cheapest barn by
  route), always via the pickup (direct is INF). So planks bought for a site may be driven straight
  to it.
- **Sale:** a planner pass after the clears: when `sellable_weight() ≥ MIN_TRIP_LOAD` or
  `_force_trip`, chains from barns to `dealer_store` (category DEALER) for `sellable(res)` per good,
  up to `PICKUP_CAPACITY` kg per run. Barns off the road walk to a road pile first (the general rule).
  `dealer_store` takes any good with a sell price; arriving goods are **sold** in `_move_chunk`
  (money, `book("sales: …")`) and never stored. `sellable()` keeps subtracting barn reservations,
  so goods are never sold twice.
- **Stops:** the dealer stop step is `dealer`: unload (sell) its rides, load (collect) the
  purchases of its rides, then `hire` while hires wait and seats are free. Dispatcher starts a trip
  when hires wait (a dealer stop with nothing else is fine). Statuses keep "Unloading at the Dealer",
  "Loading goods at the Dealer", "Hiring workers at the Dealer".
- `request_trip()` sets `_force_trip`; reset once a trip leaves.
- Delete `_plan_trip`, `_storage_for` (if unused), the old `load` / `sell` / `buy` / `hire` step code
  and `TRANSFER_STATUS` entries no longer used, and the save code that pushed an unfinished purchase
  back into the orders (a collect chunk in flight is still in `dealer_store`).
- Save: `SaveGame.VERSION = 4` (comment: "4: road piles, rides, the Dealer as a store"); `orders`
  saved / loaded as before (the dealer store's contents). Empty ground piles are not saved.
- `game.gd` scenario: update the status strings it waits for.

**Tests:**
- logistics_test `_test_dealer_stop`: 600 kg wheat in a barn, keep 100, auto-sell on → one trip
  sells 500 kg (money up by 500 × price), the barn keeps 100; with a mill wanting wheat the mill's
  share is not sold (existing `_test_sellable_keeps` still passes).
- `_test_order_collected`: order 40 planks → a trip collects them; they end in the barn (or at a
  site that wants planks, if one does).
- `_test_hire_stop`: hire 1 → a trip brings the worker; worker count +1.
- `_test_one_trip_mixed`: a road pile, a sale and an order at once → one trip with a load stop, the
  Dealer stop and an unload stop.
- tools_test `_garage` and save_test pass; `--shots` scenario runs without errors.

**Cost:** one extra pass over goods with an auto-sell rule per planner run (≤ 10 goods).

### Task 5: road piles in the world, three fill levels (PARALLEL, wave 0)

**Files:** `scripts/view/pile_view.gd` only (plus its `--show=piles` sample in
`placement_tool.gd`'s `debug_show` if it needs more goods — a few lines).

**Produces:** per design 17d, a pile's look by **fill level** `weight / capacity`: ≤ ⅓, ≤ ⅔, full.
Per good family: **logs** (1 / 3 / 6 logs stacked, existing `carry_logs` model), **planks** (one
thin stack, two stacks, a tall crossed stack; `carry_planks`), **sacks / crates** (1 / 3 / 6;
`carry_sack`, `carry_crate`, `carry_flour` as `WorkerFigure.CARRY_MODEL` maps), **gravel** (a low
procedural cone / squashed sphere `MeshInstance3D`, grey material, radius growing per level; built
once and shared). No Blender. Rebuild only on `pile_added` / `pile_changed` / `pile_removed`, and only
when the level or good changed (cache the last key per pile). An empty pile (a road pile still
waiting for its first load) shows nothing.

**Tests:** `--show=piles` screenshot with all four goods at three levels (drop piles of 30 / 100 /
200 kg beside the barn), cropped with `sips`, saved to `tmp/piles_levels.png`; the scenario
`--shots` runs without errors.

**Cost:** a handful of mesh instances per pile, no per-frame work.

### Task 6: Tasks panel — chains and pickup trips (PARALLEL, wave 1)

**Files:** `scripts/ui/tasks_panel.gd` only. Chip icons: `walking`, `pile`, `pickup` (added in Task 1),
`house` (or the destination good's icon).

**Consumes:** Task 1 interface (`Task.plan`, `leg_i`, `next`, `final_dst()`, Kind RIDE,
`World.trip_preview`).

**Produces (17c):**
- A chain leg row: title `"Logs → road pile · then pickup to Storage Barn"` (good → this leg's
  `dst.label()`, then "then pickup to {final}" / "then carried to {final}"); under it a row of chips,
  one per hop: walk / pile / pickup / place icons joined by arrows, each chip done / current / still
  to come (filled, outlined, faded); detail `"leg 1 of 3 · carrying 40 kg"` or `"waits for a free hand
  · one leg"`. A lone CARRY keeps today's title, with the two chips walk → place. Grouping of waiting
  rows stays (`src>dst` key plus the plan's hops).
- RIDE legs are never rows of their own. Instead, in the Transport section (or the category of the
  trip), one collapsible group per vehicle trip: `"Pickup trip · N stops"`, right side
  `"in progress · stop 2 of 4"` / `"waiting · starts in ~40 s"` / `"waiting for a driver"`; expanded:
  numbered stop rows `"Load 160 kg logs · road pile by the forest"` with `"≈ 0:30 after start"` /
  `"done"`; the running trip starts collapsed, a waiting one expanded (state kept in `_expanded`).
- All of it read through `world.trip_preview(v)`; a `debug_show("tasks_legs")` sample builds a
  chain (`Task`s with a shared `plan`) and renders the trip group from a sample preview dictionary
  through the same render function (the stub returns idle until Task 3).

**Tests:** `--show=tasks_legs` screenshot (`tmp/tasks_legs.png`); `--show=tasks` still looks as
before when no chains exist; no script errors. Add `tasks_legs` to the CLAUDE.md `--show` list.

**Cost:** the panel already rebuilds at 4 Hz on a signature; `trip_preview` is O(stops).

### Task 7: info panels — road pile, Garage trip; Dealer strip (PARALLEL, wave 1)

**Files:** `scripts/ui/info_panel.gd`, `scripts/ui/dealer_panel.gd` (trip strip only),
`scripts/view/camera_rig.gd` (follow a vehicle), `scripts/game.gd` (one signal connection).

**Consumes:** Task 1 interface (`World.is_road_pile`, `carry_now`, `carry_now_blocker`,
`trip_preview`, `Vehicle.cargo_weight`, `Task.Kind.RIDE`).

**Produces:**
- **Road pile** (17a): the ground pile panel with header "Road pile" when `is_road_pile(s)`;
  subtitle "one kind only · by the road"; the GOING TO card shows a waiting ride as
  `"Waiting for the pickup · next trip in ~40 s"` (from `trip_preview`), a ride in a trip as
  `"In the pickup's trip · stop 2 of 4"`; a section **ON ITS WAY** lists walking legs with
  `dst == s` (amount, good icon, worker link); the action button **"Carry to the barn now"**
  (wheelbarrow icon) calls `world.carry_now(s)`, disabled with `carry_now_blocker(s)` as tooltip;
  footer note "Piles form on their own by the road when the way is long, and vanish once empty —
  nothing to demolish." `_pile_leg` also understands RIDE legs.
- **Garage** (17c right): under the status line, when the garage has a vehicle: a status card
  `"Pickup · loading at stop 2 of 4"`, a stop strip (dots, the current one with the pickup icon),
  **Load** bar `"Load 310 kg of 800 kg"` (`cargo_weight` / `PICKUP_CAPACITY`), **TRIP** list of
  stops (state circle ✓ / number, icon by kind, label, goods line, ETA right: "done", "~10 s",
  "~0:50"; Dealer: "Dealer: sell 400 kg wheat · ≈ 360 qk · then home"), and **"Follow the pickup"**
  (`follow_requested(v)` signal; `CameraRig.follow` accepts a Worker or a Vehicle — anything with
  `pos`). Gathering / waiting trips show their planned stops with "starts in ~40 s". Rebuild the list
  only when the stop count or states change (layout key), update texts otherwise.
- **Dealer panel** trip strip: progress = `stop_i / stops.size()` from `trip_preview`; text keeps
  `trip_status`.
- `debug_show` states `info_road_pile` and `info_garage_trip`, rendered from sample data through
  the same render code until Task 3 lands.

**Tests:** screenshots `tmp/info_road_pile.png`, `tmp/info_garage_trip.png`; `info_site`,
`info_worker`, `piles`, `dealer_sell` unchanged; add the new names to the CLAUDE.md `--show` list.

**Cost:** panels refresh at their existing rate; `trip_preview` O(stops).

### Task 8: the menu farm shows a multi-stop run (PARALLEL, wave 3)

**Files:** `scripts/menu/menu_farm.gd` only.

**Consumes:** Task 3 (multi-stop trips; Task 4 for Dealer stops if it has landed).

**Produces:** in `_build`, cheaply: put two ground piles of logs / sacks beside the road far from the
barn (or fell a few trees there) and give one field an auto-sell rule, so during `PREWARM` and on
screen the pickup does a run with 2–3 stops. Keep the map size and agent count; measure `_build`
time before / after (print once) — it must not grow by more than ~10 %.

**Tests:** `-- --menu --snap=tmp/menu.png` shows the pickup out on the road (try a few seconds of
offset if needed); no script errors.

### Task 9: integration, screenshots, docs (controller)

- Re-shoot the UI states with real data (Tasks 6 and 7 switch their `debug_show` samples to a real
  world setup where cheap: fell a far tree, run until the road pile and the trip exist).
- Full test run; `--shots=tmp/shots` scenario checked for errors; planner timing (long run, the
  `--shots` scenario, the 512² probe) recorded in the report.
- Spec status line (step 3 done), CLAUDE.md decisions (road piles, rides, the Dealer as a store,
  "Carry to the barn now"), `--show` names; `docs/design/09-future-ideas.md`: trips that wait for
  goods on the way ("waits for Tilda's 40 kg", 17c), late joining of a running trip, the light
  tractor as a second vehicle.

## Open questions for the controller

1. **Orders as the Dealer store's contents** (Task 4) make buying one more clear / supplier and let
   bought planks be driven straight to a site. It changes what `world.orders` is underneath (a
   property). Accept, or keep `orders` as a separate dictionary with a special "buy" step?
2. **Field gates near the barn lose the pickup.** Today any field the pickup can reach leaves its
   harvest for the pickup; with costs, a gate fewer than `ROUTE_MIN_WALK` tiles from the barn is
   always carried by hand (with wheelbarrows). This is the "one general rule" but changes the feel
   of small farms. OK?
3. **17c "waits for Tilda's 40 kg"** — a trip waiting for goods still being walked to a pile, and
   joining a running trip late, are left for later (future ideas). OK?
4. **"Carry to the barn now"** only on road piles (as designed), not on every ground pile?
