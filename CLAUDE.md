# Acres & Quacks

A top-down farm-management automation game in Godot 4.7 (GDScript). The repo, folder and some
class names still say "farmio". Vision: `docs/design/01-vision.md`; the rest of `docs/design/` and
`docs/superpowers/specs/` hold the agreed designs.

## Every idea is checked before it is built

Tomas has many ideas; not every good-sounding idea is good for the game. Before designing or
implementing a feature (his or yours), check it against the two gates below and **say the result
out loud**: what it serves, what it costs, and any conflict. Push back when an idea fails a gate,
even if he is enthusiastic about it, and offer a smaller or different version that passes. He has
asked for this explicitly.

### 1. Vision and fun

- Does it serve the pillars in `docs/design/01-vision.md`?
  - Automation over action: the player plans and manages, never does manual labour.
  - Visible workforce: watching workers and vehicles bustle is the payoff.
  - Simple to start, deep to optimise: early game easy, late game rewards logistics.
  - Peaceful and satisfying: no combat or threats.
- Does it fit with the systems already there, or is it one more special case? Prefer one general
  mechanism over a pile of ifs (e.g. logistics by cost, not per-situation rules).
- Is it fun for a new player as well as for Tomas? Does it add a decision or a nice moment, or
  only clicks and micromanagement?
- Does it fit what has been decided (see "Decisions" below and the specs)? If it contradicts an
  earlier decision, name the contradiction and let him choose.
- Is it the right time? Park nice-to-haves in `docs/design/09-future-ideas.md` instead of building
  them now.

### 2. Performance

Starting budgets (to be tuned; measure, don't guess):

- 60 FPS on a mid-range PC on a 512² map with ~50 workers, ~10 vehicles and a fully built farm.
- The simulation tick stays well under a frame (aim for ≤ 4 ms at 1× speed); fast-forward (3×, and
  50× in the dev menu) must not stall the game.
- No per-frame work that scales with the whole map. Pathfinding and distance fields are cached
  and rebuilt only when the grid changes; planners run on a timer (about once a second), not every
  frame.
- Rendering: MultiMesh for many identical things (crops, trees), few draw calls per field or
  building, no per-frame mesh rebuilds.
- For any feature that adds per-worker, per-tile or per-tick work, state its rough cost (what it
  touches and how often) in the design, and add a quick measurement when in doubt.

## Working rules

- Talk to Tomas in Czech; code, UI texts and docs in English.
- Commit only when asked. Work directly on `master` (no feature branches); push when asked. `.claude/` is never committed.
- No save migrations until v1 is tuned (nobody has old saves).
- Values in the Claude Design mockups are illustrative; game logic and balance decide.
- Larger features: brainstorm → spec in `docs/superpowers/specs/` → plan → implement.
- Write code like the surrounding code: sparse `##` doc comments, tabs, typed GDScript.

## Decisions to remember

- Currency: Quacks ("1 500 qk"). Credits: "Tominek". Version chip "v0.1".
- Research tree unlocks plans and upgrades for quacks; buildings cost materials (planks, gravel).
- Seasons later: days are counted now; later growth by days/months, no growing in winter, animal
  feed and water. No day/night cycle for now; open questions (what workers do at night, how the
  player gets through it) are in `docs/design/08-technical.md`.
- Logistics: goods are physically in places, a central planner splits routes into legs by cost,
  road piles and the pickup (`docs/superpowers/specs/2026-10-04-logistics-design.md`). Every place
  that holds goods is a `Store` (barns, site supplies, mill input/output, field gates, ground piles);
  `scripts/sim/planner.gd` turns wants and goods to clear into `CARRY` legs. Felled wood and dropped
  goods lie as ground piles until the planner clears them. Long carries go walk → road pile (or a store by the
  road) → one multi-stop pickup trip → walk, chosen by cost per hand load (`Defs` route costs). The
  Dealer is a store and a trip stop (sell, collect orders, hire). All pickup driving is the "Pickup
  trips" priority category; switched off, everything walks. Sheds (2×2, research "Supply storage") are
  real stores with capacity and a filter (default: all goods); collection points (1×1, must touch a
  road) are pickup hand-off points only, never a final destination. Demolished Sheds and collection
  points leave their goods as ground piles.
- Buildings are numbered per type ("Storage Barn 2") and the player can rename them in the info panel.
- Info panels: several can be open at once, each beside its object, closed by hand, draggable by
  the header.
- The main menu's live farm (`scripts/menu/menu_farm.gd`) shows a farm well into a game to lure
  players: when a new building, vehicle or machine (tractors, carts, combines…) lands, add it to
  its `SHOWCASE` / build. Keep it light (small map, a few dozen agents).
- Save format changes bump `SaveGame.VERSION`; older saves are hidden from the lists, not migrated.

## Running and checking

- Godot: `/Applications/Godot.app/Contents/MacOS/Godot`. Python is blocked; wrap runs in
  `perl -e 'alarm 120; exec @ARGV' …` so a hang can't block the session. Long runs go to the
  background.
- After adding a `class_name`: `Godot --headless --path . --import`.
- Tests (each prints `… OK`): `Godot --headless --path . --script scripts/tools/<name>.gd` for
  `logistics_test`, `tech_test`, `mill_test`, `road_test`, `river_test`, `save_test`, `tools_test`. Scripts run with
  `--script` can't use the `Models` / `Settings` autoloads statically.
- Screenshots: `Godot --path . -- --seed=7 --sim=150 --zoom=45 --show=<name> --snap=tmp/x.png`
  (`--show` calls `debug_show(name, game)` on nodes in the `debug_show` group: hud, build, build_storage, stock_tip,
  tasks, tasks_legs, tasks_legs_open, road, cut, toast, dev, research, research_mixed, research_upgrade, research_tech,
  research_storage, research_shed, research_barn, dealer_sell,
  dealer_buy, dealer_sell_empty, dealer_buy_orders, info_mill, info_site, info_field, info_worker,
  info_pile, info_pile_dropped, info_road_pile, info_garage_trip, info_shed, info_collect, info_drag, info_rename, info_renamed, priorities, game_menu, leave, settings, settings_game, settings_audio,
  settings_controls, settings_access, save, load, delete, tool_cut, tool_move, tool_demolish,
  tool_gate, tool_road, tool_collect, tool_collect_far, piles, cpoints). Main menu: `-- --menu --snap=tmp/menu.png` (splash: `--splash-snap=`, loading screens: `--menu-show=play|continue --loading-snap=`). Full scenario: `-- --shots=tmp/shots`.
  Screenshots on the ultrawide come out large; crop with `sips`.
- Screenshots, renders and other scratch output go to `tmp/` in the project (git-ignored; its
  `.gdignore` keeps Godot from importing it), never to the system `/tmp`, so Tomas can see them.

## Where things are

- `scripts/sim/`: simulation without nodes (World, Defs, Tech, tasks, navigation, world gen).
- `scripts/view/`: 3D views and the placement tool. `scripts/ui/`: HUD and panels.
  `scripts/menu/`: menus, saves, settings. `scripts/core/`: save game, settings autoload, names.
- Look: `scripts/ui/ui_style.gd` (palette, fonts, icons, builders). The project theme
  `assets/ui/theme.tres` is generated by `scripts/tools/make_theme.gd`; run it after changing
  `UiStyle.theme()`.
- Design kit (Claude Design): `art/ui/design/` (HTML source, `shots/` renders per screen,
  `BRIEF.md`). DesignSync can't read files over 256 KB; ask Tomas for an export zip instead.
