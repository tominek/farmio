# Logistics Step 1 — Goods in Places Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the global `World.stock` with stores that hold their own goods (every Storage Barn has a `Store`), keeping today's behaviour with one barn.

**Architecture:** A new `Store` (RefCounted) holds contents, capacity, filter and in/out reservations. Storage buildings get one; `World` gets a `loose` store for goods with nowhere to go. All reads of `stock` become `World.total(res)` / `totals()`; all writes go through `put_goods` / `take_goods` / `set_stock`. Fetching claims goods in one store (reserved until taken); delivery puts goods into the store whose access tile the worker stands on. Steps 2–5 of the spec get their own plans after this lands.

**Tech Stack:** Godot 4.7, GDScript; headless test scripts in `scripts/tools/`.

**Spec:** `docs/superpowers/specs/2026-10-04-logistics-design.md` (section 1 and step 1 of section 4)

## Global Constraints

- Behaviour with a single Storage Barn must not change: every existing test prints OK after every task (tech_test, mill_test, road_test, river_test, save_test, tools_test).
- No save migrations: the save format may change freely (nobody has old saves).
- Goods are never lost or duplicated: the sum of `totals()` + carried goods + vehicle cargo + site/field/mill buffers is conserved by every operation except selling, buying, consuming and producing.
- Barn capacity stays unlimited in this step (`Store.capacity = INF`); filters exist but storage barns accept everything.
- Performance: `total(res)` is called from UI every 0.25 s and from the sim per task pick; it must not allocate per call beyond a small loop over storage buildings (expected ≤ 5 barns). Cache the list of storage buildings (`_stores`), rebuilt on building add/remove.
- Code style: tabs, typed GDScript, sparse `##` doc comments, English.
- Run Godot as `perl -e 'alarm 200; exec @ARGV' /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script scripts/tools/<test>.gd`. After adding a `class_name`, run `… --headless --path . --import` once.
- Commit only when Tomas asks (project rule); the "Commit" steps below mean "stage and leave ready", unless he has asked to commit.

## Review Focus

- Two barns: goods delivered go to the barn whose access tile the worker reached, not always the first barn — test in Task 3.
- A fetch claim that is never taken (task removed, worker aborted, worker removed) must release its reservation, or goods become permanently unavailable — test in Task 3.
- Demolishing a barn that holds goods: its contents move to the nearest other barn, or to `loose` if it was the last — test in Task 3.
- Saving while workers carry goods and the pickup holds cargo: totals after load equal totals before save — test in Task 4.
- UI and dev tools that used to write `stock[res] = x` (debug farms, dev menu, scenario) still produce the intended amounts — covered by Task 5's screenshot and scenario run.

---

## File Structure

- Create `scripts/sim/store.gd` — `Store`: contents, capacity, filter, reservations, (de)serialisation. Pure data, no World access.
- Modify `scripts/sim/building.gd` — `var store: Store` on storage buildings.
- Modify `scripts/sim/task.gd` — `fetch_from: Store`, `fetch_reserved: float` for claimed goods.
- Modify `scripts/sim/world.gd` — remove `stock`; add `GOODS`, `loose`, `_stores`, `stores()`, `total()`, `totals()`, `stock_split()`, `put_goods()`, `take_goods()`, `set_stock()`, `store_at()`, `settle_loose()`, `claim_fetch()`, `release_fetch()`; rewrite every `stock` use.
- Modify `scripts/sim/task_queue.gd`, `scripts/sim/worker.gd` — claim and release fetches.
- Modify `scripts/core/save_game.gd` — per-store contents, `loose`, carried goods.
- Modify UI/debug callers: `scripts/ui/hud.gd`, `dealer_panel.gd`, `info_panel.gd`, `tasks_panel.gd`, `build_dock.gd`, `dev_menu.gd`, `scripts/view/placement_tool.gd`, `scripts/menu/menu_farm.gd`, `scripts/game.gd`.
- Modify tests: `scripts/tools/tech_test.gd`, `mill_test.gd`, `road_test.gd`, `save_test.gd`, `tools_test.gd`, `balance.gd`.
- Create `scripts/tools/logistics_test.gd` — the step's own checks.

---

### Task 1: Store

**Files:**
- Create: `scripts/sim/store.gd`
- Create: `scripts/tools/logistics_test.gd`

**Interfaces:**
- Produces: `class_name Store` with `contents: Dictionary`, `capacity: float`, `filter: Dictionary`, `reserved_out: Dictionary`, `reserved_in: Dictionary`, `amount(res) -> float`, `available(res) -> float`, `accepts(res) -> bool`, `weight() -> float`, `room() -> float`, `put(res, amount) -> void`, `take(res, amount) -> float`, `reserve_out(res, amount) -> float`, `release_out(res, amount) -> void`, `to_dict() -> Dictionary`, `static from_dict(d) -> Store`.

- [ ] **Step 1: Write the failing test**

`scripts/tools/logistics_test.gd`:

```gdscript
extends SceneTree
## Logistics checks: stores, goods in places, fetch claims, delivery to the reached barn.
##   Godot --headless --path . --script scripts/tools/logistics_test.gd


func _init() -> void:
	var ok := true
	ok = _store_checks() and ok
	print("LOGISTICS TEST ", "OK" if ok else "FAILED")
	quit()


func _store_checks() -> bool:
	var ok := true
	var s := Store.new()
	s.put(&"wheat", 120.0)
	s.put(&"planks", 5.0)
	ok = _check("a store keeps what is put in", s.amount(&"wheat") == 120.0 and s.amount(&"planks") == 5.0) and ok
	ok = _check("weight counts pieces by their weight", absf(s.weight() - (120.0 + 5.0 * Defs.PLANK_WEIGHT)) < 0.001) and ok
	var got := s.reserve_out(&"wheat", 100.0)
	ok = _check("a reservation holds goods back", got == 100.0 and s.available(&"wheat") == 20.0 and s.amount(&"wheat") == 120.0) and ok
	ok = _check("a reservation never exceeds what is there", s.reserve_out(&"wheat", 50.0) == 20.0 and s.available(&"wheat") == 0.0) and ok
	s.release_out(&"wheat", 120.0)
	ok = _check("released goods are available again", s.available(&"wheat") == 120.0) and ok
	ok = _check("take never takes more than there is", s.take(&"planks", 9.0) == 5.0 and s.amount(&"planks") == 0.0
		and not s.contents.has(&"planks")) and ok
	s.filter = {&"wood": true}
	ok = _check("a filter limits what a store accepts", s.accepts(&"wood") and not s.accepts(&"wheat")) and ok
	s.filter = {}
	s.capacity = 200.0
	ok = _check("room is capacity minus weight", absf(s.room() - 80.0) < 0.001) and ok
	var back := Store.from_dict(s.to_dict())
	ok = _check("a store survives to_dict / from_dict", back.amount(&"wheat") == 120.0 and back.capacity == 200.0) and ok
	return ok


func _check(what: String, cond: bool) -> bool:
	print("%s %s" % ["  ok " if cond else "FAIL", what])
	return cond
```

- [ ] **Step 2: Run it to see it fail**

Run: `perl -e 'alarm 200; exec @ARGV' /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script scripts/tools/logistics_test.gd`
Expected: a parse error, `Store` is not declared.

- [ ] **Step 3: Write `Store`**

`scripts/sim/store.gd`:

```gdscript
class_name Store
extends RefCounted
## Goods kept in one place (a barn today; sheds, collection points and road piles later): what is
## there, how much fits (kg; pieces count by their weight), which goods it takes, and what legs have
## promised to take away or bring (reservations), so nothing is taken twice and nothing overfills.

var contents := {}            # resource -> amount (kg, or pieces for piece goods)
var capacity := INF           # kg
var filter := {}              # resource -> true; empty: takes everything
var reserved_out := {}        # resource -> amount promised to someone taking it away
var reserved_in := {}         # resource -> amount on its way here


func amount(res: StringName) -> float:
	return contents.get(res, 0.0)


## What is here and not promised to anyone.
func available(res: StringName) -> float:
	return maxf(0.0, amount(res) - reserved_out.get(res, 0.0))


func accepts(res: StringName) -> bool:
	return filter.is_empty() or filter.has(res)


func weight() -> float:
	var kg := 0.0
	for res: StringName in contents:
		kg += Defs.weight(res, contents[res])
	return kg


## Kg that still fit, counting what is on its way.
func room() -> float:
	var kg := weight()
	for res: StringName in reserved_in:
		kg += Defs.weight(res, reserved_in[res])
	return maxf(0.0, capacity - kg)


func put(res: StringName, n: float) -> void:
	if n <= 0.0:
		return
	contents[res] = amount(res) + n


## Takes up to `n`; returns what was taken.
func take(res: StringName, n: float) -> float:
	var got := minf(n, amount(res))
	if got <= 0.0:
		return 0.0
	contents[res] = amount(res) - got
	if contents[res] < 0.000001:
		contents.erase(res)
	return got


## Promises up to `n` of what is available; returns the promised amount.
func reserve_out(res: StringName, n: float) -> float:
	var got := minf(n, available(res))
	if got > 0.0:
		reserved_out[res] = reserved_out.get(res, 0.0) + got
	return got


func release_out(res: StringName, n: float) -> void:
	var left: float = reserved_out.get(res, 0.0) - n
	if left < 0.000001:
		reserved_out.erase(res)
	else:
		reserved_out[res] = left


func to_dict() -> Dictionary:
	return {"contents": contents.duplicate(), "capacity": capacity, "filter": filter.keys()}


## Reservations are not saved: claims are made again after loading.
static func from_dict(d: Dictionary) -> Store:
	var s := Store.new()
	for res in d.get("contents", {}):
		s.contents[StringName(res)] = float(d["contents"][res])
	s.capacity = float(d.get("capacity", INF))
	for res in d.get("filter", []):
		s.filter[StringName(res)] = true
	return s
```

Then `perl -e 'alarm 60; exec @ARGV' /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import`.

- [ ] **Step 4: Run the test to see it pass**

Run the same command as Step 2. Expected: all lines `ok`, last line `LOGISTICS TEST OK`.

- [ ] **Step 5: Stage**

```bash
git add scripts/sim/store.gd scripts/sim/store.gd.uid scripts/tools/logistics_test.gd
```

---

### Task 2: World keeps goods in barn stores

**Files:**
- Modify: `scripts/sim/building.gd` (add `store`)
- Modify: `scripts/sim/world.gd` (remove `var stock` at lines 26–32; every line listed in Step 3)

**Interfaces:**
- Consumes: `Store` from Task 1.
- Produces (on `World`):
  - `const GOODS: Array[StringName]` — the old `stock` keys in their order: `wood, wheat, potato, corn, beet, seed_wheat, seed_potato, seed_corn, seed_beet, flour, planks, gravel, wheelbarrow`.
  - `var loose: Store` — goods with no store to go to.
  - `func stores() -> Array[Building]` — finished storage buildings (cached in `_stores`).
  - `func total(res: StringName) -> float` — sum over stores and `loose`.
  - `func totals() -> Dictionary` — every key of `GOODS` (and any other good present) → total, in `GOODS` order.
  - `func stock_split(res: StringName) -> Array` — `[[building_name: String, amount: float], …]` for stores holding `res` (and `["Not stored", x]` for `loose`).
  - `func put_goods(res: StringName, n: float, near := Vector2i(-1, -1)) -> void` — into the nearest store (by straight distance to its access) that accepts `res`; `near` < 0 means the first store; no store → `loose`.
  - `func take_goods(res: StringName, n: float, near := Vector2i(-1, -1)) -> float` — takes from `loose` first, then stores nearest first, never touching reserved goods; returns the amount taken.
  - `func set_stock(res: StringName, n: float) -> void` — debug/test helper: removes `res` everywhere, puts `n` into the first store (or `loose`).
  - `func store_at(cell: Vector2i) -> Building` — the storage building whose access tile is `cell`, or null.
  - `func settle_loose() -> void` — moves everything in `loose` into stores (used after loading and when a barn is finished).
- `Building.store: Store` — non-null exactly for buildings whose def has `"storage": true`.

- [ ] **Step 1: Write the failing test**

Add to `scripts/tools/logistics_test.gd` (call it from `_init`: `ok = _world_checks() and ok`):

```gdscript
func _world_checks() -> bool:
	var ok := true
	var w := WorldGen.generate(256, 7)
	var barn: Building = w.stores()[0]
	ok = _check("the start barn has a store", w.stores().size() == 1 and barn.store != null) and ok
	w.set_stock(&"planks", 40.0)
	ok = _check("set_stock puts goods in the barn", barn.store.amount(&"planks") == 40.0 and w.total(&"planks") == 40.0) and ok
	w.put_goods(&"wheat", 100.0)
	ok = _check("put_goods adds to the barn", w.total(&"wheat") == 100.0) and ok
	ok = _check("take_goods takes what there is", w.take_goods(&"wheat", 150.0) == 100.0 and w.total(&"wheat") == 0.0) and ok
	ok = _check("totals lists every good in order", w.totals().keys().slice(0, World.GOODS.size()) == World.GOODS) and ok
	ok = _check("the split names the barn", w.stock_split(&"planks") == [[Defs.def(&"storage_barn")["name"], 40.0]]) and ok
	return ok
```

- [ ] **Step 2: Run it to see it fail**

Run: the logistics_test command. Expected: parse error, `stores` / `set_stock` not found on `World`.

- [ ] **Step 3: Implement**

`scripts/sim/building.gd` — add after the other `var` lines:

```gdscript
var store: Store = null             # storage buildings: the goods kept here
```

`scripts/sim/world.gd`:

1. Replace `var stock := { … }` (lines 26–32) with:

```gdscript
## Goods in their usual order (top bar chips, Dealer lists).
const GOODS: Array[StringName] = [&"wood", &"wheat", &"potato", &"corn", &"beet",
	&"seed_wheat", &"seed_potato", &"seed_corn", &"seed_beet", &"flour", &"planks", &"gravel", &"wheelbarrow"]
var loose := Store.new()           # goods with no store to go to (no barn yet, a save being loaded)
var _stores: Array[Building] = []  # finished storage buildings (cache)
```

2. In `add_building` (line 493), after `b.level = level`:

```gdscript
	if Defs.def(def_id).get("storage", false):
		b.store = Store.new()
		_stores.append(b)
```

and at the end of `add_building`, before `return b`: `settle_loose()` when `b.store` (goods waiting for a barn move in).

3. In `_release(b)` (find `func _release`), add at the top: `_stores.erase(b)`.

4. Add the store API next to `delivery_target` (around line 1294):

```gdscript
# --- goods in places -----------------------------------------------------------

func stores() -> Array[Building]:
	return _stores


func total(res: StringName) -> float:
	var n := loose.amount(res)
	for b in _stores:
		n += b.store.amount(res)
	return n


func totals() -> Dictionary:
	var out := {}
	for res in GOODS:
		out[res] = total(res)
	for s: Store in [loose] + _stores.map(func(b: Building) -> Store: return b.store):
		for res: StringName in s.contents:
			if not out.has(res):
				out[res] = total(res)
	return out


## Where the good is: [[place name, amount], …] (the top bar chip tooltip).
func stock_split(res: StringName) -> Array:
	var out := []
	for b in _stores:
		if b.store.amount(res) > 0.0005:
			out.append([Defs.def(b.def_id)["name"], b.store.amount(res)])
	if loose.amount(res) > 0.0005:
		out.append(["Not stored", loose.amount(res)])
	return out


## The storage building that would take `res` nearest to `near` (any store for near < 0), or null.
func _store_for(res: StringName, near: Vector2i) -> Building:
	var best: Building = null
	var best_d := INF
	for b in _stores:
		if not b.store.accepts(res) or b.store.room() <= 0.0:
			continue
		var d := 0.0 if near.x < 0 else Vector2(near).distance_squared_to(b.access)
		if d < best_d:
			best_d = d
			best = b
	return best


func put_goods(res: StringName, n: float, near := Vector2i(-1, -1)) -> void:
	var b := _store_for(res, near)
	(b.store if b else loose).put(res, n)


func take_goods(res: StringName, n: float, near := Vector2i(-1, -1)) -> float:
	var got := loose.take(res, n)
	var order := _stores.duplicate()
	if near.x >= 0:
		order.sort_custom(func(a: Building, b: Building) -> bool:
			return Vector2(near).distance_squared_to(a.access) < Vector2(near).distance_squared_to(b.access))
	for b: Building in order:
		if got >= n - 0.000001:
			break
		got += b.store.take(res, minf(n - got, b.store.available(res)))
	return got


## Debug and tests: exactly `n` of `res` on the farm, all of it in the first store.
func set_stock(res: StringName, n: float) -> void:
	loose.take(res, INF)
	for b in _stores:
		b.store.take(res, INF)
	put_goods(res, n)
	stock_changed.emit()


func store_at(cell: Vector2i) -> Building:
	for b in _stores:
		if b.access == cell:
			return b
	return null


func settle_loose() -> void:
	if _stores.is_empty():
		return
	for res: StringName in loose.contents.keys():
		put_goods(res, loose.take(res, INF))
```

5. Rewrite every `stock` use in world.gd (line numbers as of commit `a0c49bc`):

| Line | Today | Becomes |
|---|---|---|
| 629 | `stock[res] = stock.get(res, 0.0) + site.pile[res]` | `put_goods(res, site.pile[res], site.access)` |
| 841, 843, 849 | refunds on demolish `stock[res] = … + x` | `put_goods(res, x, b.access)` |
| 853–854, 986–987 | mill contents back on demolish / move | `put_goods(r["in"], b.input, b.access)` / `put_goods(r["out"], b.output, b.access)` |
| 1042 | moved-site delivered back | `put_goods(res, site.delivered[res], site.access)` |
| 1145 | `fetch_have`: `stock.get(t.fetch, 0.0)` | see Task 3 (claims); for now `total(t.fetch)` |
| 1272 | `stock.get(&"wheelbarrow", 0.0) >= 1.0` | `total(&"wheelbarrow") >= 1.0` |
| 1309, 1312 | `deliver(w)`: `stock[x] += …` | `_deliver_into(w, x, amount)` — see Task 3; for now `put_goods(x, amount, w.cell())` |
| 1520, 1539 | `stock.get(res_in, 0.0)` | `total(res_in)` |
| 1625, 1652 | `take_fetch`: `stock[t.fetch] = have - …` | `take_goods(t.fetch, 1.0, w.cell())` / `take_goods(t.fetch, amount, w.cell())` (Task 3 replaces with the claimed store) |
| 1667 | `seed_shortage`: `stock.get(res, 0.0)` | `total(res)` |
| 1761 | sell amount: `stock.get(res, 0.0)` | `total(res)` |
| 2232 | trip `"load"`: `stock[res] -= n` | `take_goods(res, n, _storage_for(v).access if _storage_for(v) else Vector2i(-1, -1))` |
| 2246 | trip `"unload"` | `put_goods(res, n, _storage_for(v).access if _storage_for(v) else Vector2i(-1, -1))` |
| 2260 | cancelled site during unload | `put_goods(res, n, site.access)` |

Also in `demolish(b)` when `b.store` is set (a barn): before `_release(b)`, move its contents out:

```gdscript
	if b.store:
		var held := b.store.contents.duplicate()
		_stores.erase(b)
		for res: StringName in held:
			put_goods(res, held[res], b.access)      # to the nearest other barn, or loose
```

After the rewrite, `grep -n "stock\[\|stock\.get\|stock\.merge\|stock\.duplicate" scripts/sim/world.gd` must print nothing.

- [ ] **Step 4: Run the tests**

Run logistics_test (expect `LOGISTICS TEST OK`). The other tests still use `stock` and fail to parse; they are fixed in Task 5 — do not run them yet.

- [ ] **Step 5: Stage** `scripts/sim/building.gd scripts/sim/world.gd scripts/tools/logistics_test.gd`.

---

### Task 3: Fetch claims and delivery to the reached barn

**Files:**
- Modify: `scripts/sim/task.gd`, `scripts/sim/task_queue.gd:61-93`, `scripts/sim/worker.gd:58-64,118-136`, `scripts/sim/world.gd` (`fetch_have`, `fetch_target`, `take_fetch`, `deliver`, `delivery_target`, `remove_worker` line ~1350)

**Interfaces:**
- Consumes: Task 2's store API.
- Produces:
  - `Task.fetch_from: Store` (null when nothing is claimed), `Task.fetch_reserved: float`.
  - `World.claim_fetch(t: Task, from: Vector2i) -> Variant` — picks the nearest reachable store with `available(t.fetch) >= fetch_min(t)`, reserves `min(t.fetch_amount, available)`, sets `t.fetch_from`, returns that store's access tile; for moved-building piles returns `_pile_spot(t.site)` without reserving; null when nothing fits.
  - `World.release_fetch(t: Task) -> void` — idempotent; releases `t.fetch_reserved` from `t.fetch_from` and clears both.
  - `World.fetch_have(t)` — pile amount, or the largest `available` in a single store.
  - `World.delivery_target(from: Vector2i, res := &"") -> Variant` — nearest reachable store that accepts `res` (any when empty).
  - `World.deliver(w)` — into `store_at(w.cell())` when the worker stands on a store's access tile, else `put_goods(…, w.cell())`.

- [ ] **Step 1: Write the failing tests**

Add `ok = _claim_checks() and ok` to `_init` and:

```gdscript
## A second barn next to the first one, by the same road.
func _second_barn(w: World) -> Building:
	var first: Building = w.stores()[0]
	for r in range(4, 40):
		for dy in range(-r, r + 1):
			for dx in [-r, r]:
				var a: Vector2i = first.anchor + Vector2i(dx, dy)
				if w.can_place(&"storage_barn", a, first.rot) \
						and not w.nav.find_path(first.access, Defs.access_cell(&"storage_barn", a, first.rot)).is_empty():
					return w.add_building(&"storage_barn", a, first.rot)
	return null


func _claim_checks() -> bool:
	var ok := true
	var w := WorldGen.generate(256, 7)
	var a: Building = w.stores()[0]
	var b := _second_barn(w)
	ok = _check("a second barn gets its own store", b != null and w.stores().size() == 2 and b.store != null) and ok
	b.store.put(&"planks", 30.0)
	var t := Task.new(Task.Kind.DELIVER, b.access, 1.0, 0.0)
	t.fetch = &"planks"
	t.fetch_amount = 20.0
	var target: Variant = w.claim_fetch(t, a.access)
	ok = _check("a claim goes to the barn that has the goods", target == b.access and t.fetch_from == b.store
		and b.store.available(&"planks") == 10.0) and ok
	var t2 := Task.new(Task.Kind.DELIVER, b.access, 1.0, 0.0)
	t2.fetch = &"planks"
	t2.fetch_amount = 20.0
	w.claim_fetch(t2, a.access)
	ok = _check("claimed goods are not claimed twice", t2.fetch_reserved <= 10.0) and ok
	w.release_fetch(t)
	w.release_fetch(t)
	ok = _check("releasing twice is harmless", b.store.available(&"planks") == 30.0 - t2.fetch_reserved) and ok
	w.tasks.add(t2)
	w.tasks.remove(t2)
	ok = _check("a removed task releases its claim", b.store.available(&"planks") == 30.0 and t2.fetch_from == null) and ok

	# a worker standing on barn B's access tile delivers into B
	var wk: Worker = w.workers[0]
	wk.pos = Vector2(b.access) + Vector2(0.5, 0.5)
	wk.carrying = &"wood"
	wk.carry_amount = 2.0
	w.deliver(wk)
	ok = _check("delivery goes into the barn the worker reached", b.store.amount(&"wood") == 2.0 and a.store.amount(&"wood") == 0.0) and ok

	# demolishing B moves its goods to A
	var before := w.total(&"planks") + w.total(&"wood")
	w.demolish(b)
	ok = _check("a demolished barn's goods move to the other barn", w.stores() == [a]
		and absf(a.store.amount(&"planks") + a.store.amount(&"wood") - before) < 0.001) and ok
	return ok
```

- [ ] **Step 2: Run it to see it fail** — expected: `claim_fetch` not found.

- [ ] **Step 3: Implement**

`scripts/sim/task.gd`, after `var fetch_amount := 0.0`:

```gdscript
var fetch_from: Store = null        # the store whose goods this task has claimed (see World.claim_fetch)
var fetch_reserved := 0.0
```

`scripts/sim/world.gd` — replace `fetch_have` and `fetch_target`:

```gdscript
## What the task can fetch right now: the pile, or the most any single store can give.
func fetch_have(t: Task) -> float:
	if _from_pile(t):
		return t.site.pile.get(t.fetch, 0.0)
	if t.fetch_from:
		return t.fetch_reserved
	var best := loose.available(t.fetch)
	for b in _stores:
		best = maxf(best, b.store.available(t.fetch))
	return best


## Claims the task's goods in the nearest reachable store that has enough and returns its access
## tile (a moved building's pile: the pile spot, nothing is reserved). Null when nothing fits.
func claim_fetch(t: Task, from: Vector2i) -> Variant:
	release_fetch(t)
	if _from_pile(t):
		return _pile_spot(t.site)
	var need := fetch_min(t)
	var order := _stores.filter(func(b: Building) -> bool: return b.store.available(t.fetch) >= need - 0.000001)
	order.sort_custom(func(a: Building, b: Building) -> bool:
		return Vector2(from).distance_squared_to(a.access) < Vector2(from).distance_squared_to(b.access))
	for b: Building in order:
		if nav.find_path(from, b.access).is_empty():
			continue
		t.fetch_from = b.store
		t.fetch_reserved = b.store.reserve_out(t.fetch, t.fetch_amount)
		return b.access
	return null


func release_fetch(t: Task) -> void:
	if t.fetch_from:
		t.fetch_from.release_out(t.fetch, t.fetch_reserved)
	t.fetch_from = null
	t.fetch_reserved = 0.0
```

Keep `fetch_target(t, from)` as a thin alias: `return claim_fetch(t, from)` (other callers read it).

In `take_fetch(t, w)`: replace the two non-pile `stock[...] = have - …` writes with taking from the claim, and release the claim:

```gdscript
	# (wheelbarrow branch)
	if t.fetch == &"wheelbarrow":
		var store := t.fetch_from
		release_fetch(t)
		if store == null or store.take(t.fetch, 1.0) < 1.0:
			return false
		w.equipment = t.fetch
		stock_changed.emit()
		return true
	…
	else:
		var store := t.fetch_from
		release_fetch(t)
		amount = store.take(t.fetch, amount) if store else take_goods(t.fetch, amount, w.cell())
```

(`have` at the top of `take_fetch` already comes from `fetch_have`, which returns the reserved amount for a claimed task.)

`delivery_target(from, res := &"")`: keep its shape, but loop over `_stores` (not all buildings) and skip `not b.store.accepts(res)` when `res != &""`. In `worker.gd:_go_deliver`, call `world.delivery_target(cell(), carrying)`.

`deliver(w)`:

```gdscript
func deliver(w: Worker) -> void:
	var at := store_at(w.cell())
	if w.equipment != &"":
		if at:
			at.store.put(w.equipment, 1.0)          # the wheelbarrow goes back to the barn
		else:
			put_goods(w.equipment, 1.0, w.cell())
		w.equipment = &""
	if w.carrying != &"":
		if at and at.store.accepts(w.carrying):
			at.store.put(w.carrying, w.carry_amount)
		else:
			put_goods(w.carrying, w.carry_amount, w.cell())
	w.carrying = &""
	w.carry_amount = 0.0
	stock_changed.emit()
```

Releases on every way a task loses its worker or leaves the queue:
- `scripts/sim/task_queue.gd` `pick`: replace `target = world.fetch_target(t, from)` with `world.claim_fetch(t, from)`; when the following `path.is_empty()` check fails, call `world.release_fetch(t)` before `continue`. `TaskQueue` has no world reference in `remove`, so:
- `scripts/sim/task_queue.gd` `remove(task)`: add `if task.fetch_from: task.fetch_from.release_out(task.fetch, task.fetch_reserved); task.fetch_from = null; task.fetch_reserved = 0.0` (same as `release_fetch`, written inline to avoid a world reference).
- `scripts/sim/worker.gd:64` (where `task.worker = null` on a failed fetch) and `abort`: call `world.release_fetch(task)` before dropping the task.
- `scripts/sim/world.gd` `remove_worker` (line ~1350, `t.worker = null`): `release_fetch(t)` first.

- [ ] **Step 4: Run** logistics_test → `LOGISTICS TEST OK`.

- [ ] **Step 5: Stage** the modified sim files and the test.

---

### Task 4: Saves keep goods in their places

**Files:**
- Modify: `scripts/core/save_game.gd:212-224` (serialise), `:313` (deserialise), building dicts (`:250`, `:265`, `:339-382`)

**Interfaces:**
- Consumes: `Building.store`, `World.loose`, `World.settle_loose()`, `Store.to_dict/from_dict`.
- Produces: save keys `"loose"` (a `Store.to_dict()`) and, per storage building, `"store"`. The `"stock"` key is gone.

- [ ] **Step 1: Write the failing test**

Add `ok = _save_checks() and ok` to logistics_test `_init`:

```gdscript
func _save_checks() -> bool:
	var ok := true
	var w := WorldGen.generate(256, 7)
	var a: Building = w.stores()[0]
	var b := _second_barn(w)
	a.store.put(&"wheat", 300.0)
	b.store.put(&"planks", 25.0)
	var wk: Worker = w.workers[0]
	wk.carrying = &"wood"
	wk.carry_amount = 3.0
	var before := w.totals()
	before[&"wood"] += 3.0                 # carried goods land in a store when loaded
	SaveGame.save(w, "logistics_test")
	var w2 := SaveGame.load_world("logistics_test")
	var b2: Building = w2.buildings.get(b.id)
	ok = _check("each barn keeps its own goods", b2 != null and b2.store.amount(&"planks") == 25.0
		and w2.buildings[a.id].store.amount(&"wheat") == 300.0) and ok
	ok = _check("totals survive a save, carried goods included", w2.totals() == before) and ok
	ok = _check("nothing is left loose after loading", w2.loose.contents.is_empty()) and ok
	SaveGame.delete("logistics_test")
	return ok
```

- [ ] **Step 2: Run** → FAIL (`"stock"` missing / stores empty after load).

- [ ] **Step 3: Implement**

In `_serialize`: replace `var stock: Dictionary = w.stock.duplicate()` and its three `stock[...] +=` lines with a copy of `loose` that collects carried goods and vehicle cargo:

```gdscript
	var loose := Store.from_dict(w.loose.to_dict())
	# carried goods and the pickup's cargo are saved as loose goods; loading puts them in a barn
	for wk in w.workers:
		if wk.carrying != &"":
			loose.put(wk.carrying, wk.carry_amount)
		if wk.equipment != &"":
			loose.put(wk.equipment, 1.0)
	for v in w.vehicles:
		for res in v.cargo:
			loose.put(res, v.cargo[res])
```

Save `"loose": loose.to_dict()` instead of `"stock"`. In the building dict writer, add `"store": b.store.to_dict()` when `b.store`. In `_deserialize`: drop `w.stock.merge(...)`; after buildings are rebuilt, set `b.store = Store.from_dict(bd["store"])` when the dict has it (the building was created through `add_building`, so the cache already lists it; replace its empty store), then `w.loose = Store.from_dict(d["loose"])` and `w.settle_loose()`.

- [ ] **Step 4: Run** logistics_test → OK.

- [ ] **Step 5: Stage** `scripts/core/save_game.gd` and the test.

---

### Task 5: Callers outside the sim, tests, and the stock split tooltip

**Files:**
- Modify (every line from `grep -rn "stock\[\|stock\.get\|\.stock\b" scripts --include="*.gd" | grep -v stock_changed`): `scripts/game.gd` (157–161, 363, 375, 406, 441, 540, 548, 570, 603, 610), `scripts/ui/dev_menu.gd` (80, 86–87), `scripts/ui/hud.gd` (346–391 chips, 930–931), `scripts/ui/dealer_panel.gd` (132–133, 142, 802, 852, 874, 883), `scripts/ui/info_panel.gd` (287, 373–375, 420, 533, 731, 1149), `scripts/ui/tasks_panel.gd` (127, 131, 135), `scripts/ui/build_dock.gd` (411, 416, 424), `scripts/view/placement_tool.gd` (732, 773), `scripts/menu/menu_farm.gd` (42–45), and the tests `tech_test.gd`, `mill_test.gd`, `road_test.gd`, `save_test.gd`, `tools_test.gd`, `balance.gd`.

**Interfaces:**
- Consumes: `total`, `totals`, `set_stock`, `put_goods`, `stock_split` from Task 2.

- [ ] **Step 1: Rewrite by these rules**

| Pattern | Replacement |
|---|---|
| `world.stock.get(res, 0.0)` / `world.stock[res]` (read) | `world.total(res)` |
| `for res in world.stock:` | `for res: StringName in world.totals():` (and `world.totals()[res]` / `world.total(res)` inside) |
| `world.stock[res] = x` (debug, scenario, tests) | `world.set_stock(res, x)` |
| `world.stock[res] += x` / `= get + x` | `world.put_goods(res, x)` then `world.stock_changed.emit()` where the old code emitted |
| `world.stock[res] = maxf(world.stock[res], x)` | `world.set_stock(res, maxf(world.total(res), x))` |
| `world.stock[res] = minf(world.stock[res], x)` | `world.set_stock(res, minf(world.total(res), x))` |
| `print(..., world.stock, ...)` | `print(..., world.totals(), ...)` |

In `info_panel.gd:_stored()` (373–375), list the goods of the selected barn's own store (`(target as Building).store.contents`), not the farm total — the barn panel shows what is in that barn. Update its "stored" capacity line to `store.weight()`.

In `hud.gd` chip tooltips (around 384–391), append the split when there is more than one place:

```gdscript
		var split := world.stock_split(key)
		if split.size() > 1:
			tip.append(" · ".join(split.map(func(p: Array) -> String: return "%s %s" % [p[0], Defs.format_amount(key, p[1])])))
```

User-facing texts that say "in the barn" stay as they are in this step (there is only one kind of store).

- [ ] **Step 2: Verify nothing is left**

Run: `grep -rn "stock\[\|stock\.get\|\.stock\b\|stock\.merge\|stock\.duplicate" scripts --include="*.gd" | grep -v "stock_changed\|stock_split"`
Expected: no output.

- [ ] **Step 3: Run every test**

```bash
for t in logistics_test tech_test mill_test road_test river_test save_test tools_test; do
  printf "%s: " $t
  perl -e 'alarm 200; exec @ARGV' /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script scripts/tools/$t.gd 2>&1 | grep -E "TEST OK|ROUND TRIP OK|FAIL|SCRIPT ERROR" | tr '\n' ' '; echo
done
```

Expected: every line ends in OK, no FAIL or SCRIPT ERROR.

- [ ] **Step 4: Check the game visually**

```bash
perl -e 'alarm 120; exec @ARGV' /Applications/Godot.app/Contents/MacOS/Godot --path . -- --seed=7 --sim=150 --zoom=45 --show=hud --snap=tmp/step1_hud.png
perl -e 'alarm 120; exec @ARGV' /Applications/Godot.app/Contents/MacOS/Godot --path . -- --seed=7 --sim=150 --zoom=45 --show=dealer_buy --snap=tmp/step1_dealer.png
perl -e 'alarm 500; exec @ARGV' /Applications/Godot.app/Contents/MacOS/Godot --path . -- --shots=tmp/step1_shots 2>&1 | grep -E "SCRIPT ERROR" | head
```

Expected: the top bar shows the same chips and amounts as before; the Dealer lists "in barn" amounts; the scenario prints no SCRIPT ERROR and writes about 40 shots.

- [ ] **Step 5: Stage** all modified files. Report to Tomas; commit only if he asks.

---

## Self-review notes

- Spec section 1 coverage in this step: stores with contents, capacity, filter, reservations (Task 1–3); derived totals and the split tooltip (Tasks 2, 5); demolished store contents move on (Task 3). Dealer selling from any store and unloading near the garage: trip `load`/`unload` use the store nearest the garage (Task 2 table) — the same as today with one barn. Road piles, sheds, collection points, the planner and multi-stop trips are steps 2–5 (later plans).
- Performance: `total()` loops over `_stores` (cached) plus `loose`; `claim_fetch` sorts the stores that have the good and runs one path search per candidate until one is reachable, the same cost as today's `delivery_target`.
