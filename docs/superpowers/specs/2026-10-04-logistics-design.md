# Logistics: goods in places, a planner, road piles and the pickup

Status: approved in conversation (2026-10-04). Steps 1–3 implemented (plans in `docs/superpowers/plans/`).

## Why

Acres & Quacks is largely a logistics game, but today goods teleport into one global `stock` the
moment a worker reaches the nearest barn, and a worker who fells a tree far away walks all the way
back with the logs. Workers should be "lazy" in a sensible way: drop the logs by the nearest road and
let the pickup take them, carry seeds from the shed by the field rather than from the far barn. This
must come from one general mechanism (costs), not a pile of special cases.

## Decisions (from the brainstorm)

- Full logistics, built in steps (below); each step leaves a playable game.
- Piles appear automatically by roads, and the player may also build collection points and sheds,
  which are preferred and more efficient.
- Goods are physically somewhere: every store has its own contents.
- A pile is worse than a shed by capacity and space (no spoilage, no slower handling for now).
- Goods move on demand (someone needs them) from the cheapest source; sheds and collection points
  have a filter of goods they accept. No "keep N here" quotas for now.
- Planning approach A: a central planner over a board of requests that splits each route into legs
  and picks the route by cost.
- No save migrations (nobody has old saves).

## 1. Where goods are

A **Store** is anything that holds goods:

| Store | Size | Capacity | Filter | Notes |
|---|---|---|---|---|
| Storage Barn | 4×3 (as today) | large | none | the start store |
| Shed (new, "Supply storage" node) | 2×2 | medium | yes | built from planks, unlocked in the tree |
| Collection point (new) | 1×1 by a road | small | yes | cheap |
| Road pile (automatic) | 1 tile by a road | small (≈200 kg or 20 pieces) | one good | created by the planner, removed when empty |
| Building buffers | — | as today | fixed | field gate pile, mill input/output, site materials, moved-building pile |

Every store has: an access cell, contents `{res: amount}`, a capacity in kg (pieces count by their
weight, `Defs.PIECE_WEIGHT`), an optional filter, and **reservations** in and out (amounts promised to
legs on their way), so two workers never take the same plank and a store never overfills.

- `World.stock` becomes a derived total (sum over stores) for the HUD, the Dealer and alerts; the
  stock chip tooltip shows the split by place ("Planks 120: Barn 80 · Shed by the mill 40").
- The Dealer sells from any store (the pickup collects it); bought goods are unloaded at the store
  by the garage, or straight where they are needed.
- Demolishing a store leaves its contents as road piles / a pile on its spot (nothing is lost).

## 2. The planner

A **board** of requests:

- **Need**: a consumer wants goods — a site wants planks, a mill wants wheat up to its input
  target, a field wants seed, a Dealer trip wants cargo to sell.
- **Clear**: goods must leave a place — logs after felling or clearing, a harvest at the field gate,
  mill output, materials from a dismantled building. The destination is a consumer that needs the
  good (logs straight to the sawmill), otherwise the cheapest store that accepts it.

The planner runs about once a second (not every frame). For each open request it picks a source, a
destination and a **route**, comparing:

1. On foot (with a wheelbarrow when it pays off) straight from source to destination.
2. On foot to a road → drop at a collection point / road pile → pickup (one trip collects several
   piles) → road near the destination → on foot.

**Cost** of a route = walk time × `WALK_COST` + drive time × `DRIVE_COST` + `HANDLING_COST` per
load/unload + expected wait for a free vehicle. "Laziness" is tuned only by these numbers (walking
expensive, driving cheap; handling makes a hand-off for a few metres not worth it). Walk times come
from real path lengths (8-direction walking as `Nav` already does), not straight lines.

A route becomes a chain of **legs**; each leg is an ordinary task:

- carry on foot (generalising today's HAUL and DELIVER),
- a stop on a vehicle trip (load here / unload there).

The next leg opens when the goods arrive at the intermediate store. Legs keep the request's
category (Construction, Processing, Transport…), so the Priorities panel works as now. If something
breaks (no path, a store demolished), the goods stay where they are as a pile and the request is
planned again.

**Performance**: walking distances from each store are cached as distance fields (Dijkstra from the
store's access cell) and rebuilt only when buildings or roads change; road distances use `RoadNav`.
Step 2 uses cached A* path lengths instead (`Nav.walk_cost`; opening a tile keeps the cache, closing
one flushes it) and a time budget per planner run (`Defs.PLANNER_BUDGET_USEC`). One search to an
unreachable place can still cost 7–10 ms on 512²; connected-area labels or real distance fields are
the fix, due in step 5. Options agreed with Tomas (2026-10-05): first label connected areas (an unreachable target is
answered at once, no search); if long searches still stall frames, run path searches on a worker thread
and let the worker "think" for a few frames (results checked against grid changes before use).

## 3. Vehicles, hand-off points, UI

- The pickup's three hard-wired trip kinds (Dealer, field pile, moved building) become one
  **multi-stop trip** assembled by the planner from waiting vehicle legs along the roads, so it runs
  full and without detours. A Dealer visit is one more stop (sell / buy / hire). More vehicles (the
  light tractor) plug into the same thing later.
- A road pile is created on a free tile right next to a road, as close as possible to where the
  carrier starts. A player's collection point or shed nearby that accepts the good is preferred.
- Piles and collection points are visible on the map (a small heap of crates / planks / logs by
  content).
- UI:
  - Info panel for a pile / store: contents, capacity, filter (sheds, collection points), what is on
    its way in and out.
  - Tasks: legs read e.g. "Logs → road pile · then pickup to Shed", so it is clear why a worker
    doesn't walk to the barn.
  - Research: Shed ("Supply storage") and Collection point nodes.
  - Visual design: Claude Design kit section 17 (`art/ui/design/shots/s17a.png` … `s17f.png`): road pile
    and collection point panels (17a), Shed and the stock split tooltip (17b), Tasks legs and the
    pickup trip (17c), in-world piles at three fill levels, the collection point, the Shed and its
    placement ghost snapping to a road (17d), research nodes (17e), the Storage build category (17f).
  - A road pile offers one action, "Carry to the barn now": a free worker with a wheelbarrow takes it
    straight away (overrides the planner for that pile).

## 4. Steps

1. **Goods in places.** Stores with contents, derived totals, reservations. Behaviour unchanged:
   the barn is the only store, piles are today's buffers.
2. **Board and planner, on foot only.** Today's DELIVER / HAUL become requests and legs; workers use
   real path lengths; felled wood becomes a Clear request.
3. **Road piles and the pickup.** Automatic road piles, multi-stop trips, the Dealer as a stop. The
   lazy behaviour appears here.
4. **Shed and collection point.** New buildings with filters, research nodes, info panels (Claude
   Design).
5. **Tuning.** Walk / drive / handling costs, capacities, the balance bot.

## Testing

- A headless `logistics_test.gd`:
  - a tree felled far from the barn ends up by a road and the pickup brings it in;
  - goods are never lost or duplicated (the totals add up through every leg);
  - reservations never overfill a store;
  - a demolished shed leaves its contents as piles;
  - a need is served from the cheapest source (the shed by the mill, not the far barn).
- After each step the existing tests pass (mill, road, river, save, tools, tech).
- `--show` screenshots for the new info panel states and Tasks rows.
- All tuning numbers live together in `defs.gd`.
