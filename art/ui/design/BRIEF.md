# UI redesign brief (for the agents working in parallel)

Game: **Acres & Quacks** (repo/folder still "farmio"), Godot 4.7, GDScript, no addons. The design is the
Claude Design concept kit "Acres and Quacks UI Kit". The rendered kit lives here:

- `art/ui/design/shots/*.png` — screenshots per section: `logo.png`, `kit.png` (palette, type,
  components, icons), `s00` main menu, `s01` main view (HUD, warnings, tool dock, hint, info panel),
  `s01b` tasks panel, `s02` build menu (dock, build list, cut-trees mode), `s03` research, `s04` info
  panels (worker, field, building, construction site), `s05a`/`s05b` Dealer sell/buy, `s06` priorities,
  `s07` game menu, `s08` settings, `s09` save, `s10` load, `s11` loading.
- `art/ui/design/Acres and Quacks UI Kit.dc.html` — the HTML source (exact colours, sizes, texts).
  Large; grep it for what you need instead of reading it whole.

## Rules
- **Values in the design are illustrative.** Prices, capacities, amounts, names of workers, "day 14",
  etc. come from the game (`Defs`, `World`, `Tech`), never from the mock-ups. Where the mock-up shows
  something the game does not have (seasons/days, audio, seed store building, …) leave it out and
  list it in your final report as an open question. Do not invent game mechanics beyond your task.
- UI text is English. Money is quacks: `Defs.format_money(x)` → "1 500 qk"; next to a coin icon use
  `UiStyle.money_number(x)` ("1 500") with `UiStyle.icon("qk")`.
- Use the shared look in `scripts/ui/ui_style.gd` (`UiStyle`): palette constants, `head_font()` /
  `body_font()`, `icon(name)` / `resource_icon(res)` / `icon_rect()`, `make_panel(title, icon)`
  (board header + paper body + close ✕), `status_line()` / `set_status()`, `bar()` /
  `set_bar_color()`, `amount()`, `key_cap()`, `box()`. Theme type variations: buttons
  `PrimaryButton`, `DangerButton`, `GhostButton`, `OpenButton` (plain `Button` = secondary);
  labels `TitleLabel`, `PanelTitle`, `SectionLabel`, `SmallLabel`, `SoftLabel`, `NumberLabel`;
  panels `Well`, `Chip`. The theme is the project default (`assets/ui/theme.tres`, built by
  `scripts/tools/make_theme.gd` from UiStyle). If you need a new shared style, add a small builder to
  UiStyle (append only, don't change existing signatures) and re-run make_theme.
- Icons: `assets/ui/icons/kit/*.svg` (qk, wheat, potato, corn, beet, seeds, logs, planks, flour,
  gravel, wheelbarrow, worker, idle, working, walking, locked, warning, plan, upgrade, tech, house,
  field, road, groad, egg, clock, build, move, cut, demolish).
- Match the surrounding code style (see `CLAUDE.md`-like conventions in existing files: `##` doc
  comments, typed GDScript, tabs, short comments only where useful).
- **Only edit the files you own** (listed in your task). Shared files you may touch minimally are
  named explicitly; re-read them right before editing, keep the edit small and local, never reformat.
- **Do not commit.** Do not delete or rename other people's files.
- After adding a `class_name` script run `Godot --headless --path . --import` once so the class is
  registered.

## Running and checking
- Godot: `/Applications/Godot.app/Contents/MacOS/Godot`. Wrap long runs: `perl -e 'alarm 300; exec @ARGV' <cmd>`.
- Screenshot of the game: `Godot --path . -- --seed=7 --sim=120 --zoom=60 --show=<name> --snap=/tmp/x.png`
  - `--sim=<s>`: unlocks all research, adds fields per crop, a hand mill and a sawmill, money, planks,
    then simulates `s` seconds (see `game.gd` `_debug_farm`).
  - `--show=<name>`: calls `debug_show(name: String, game: Node3D)` on every node in the group
    `"debug_show"`. Add your panel to that group and implement `debug_show` to open itself in a
    representative state when `name` is yours (e.g. "research", "dealer_buy", "info_mill").
  - Look at the PNG with the Read tool and compare with the design shot. Iterate until it is close.
- Tests (must still pass if you touched the simulation): `Godot --headless --path . --script scripts/tools/<x>_test.gd`
  for tech_test, mill_test, road_test, river_test, save_test (each prints `... OK`).
- Python is blocked in this environment; use perl / sed for scripted edits.

## Final report
Return: what you built (files), how it maps to the design, screenshots you checked, test results,
and a list of **open questions / decisions for the user** (things the design shows that need a
gameplay decision, or that you left out).
