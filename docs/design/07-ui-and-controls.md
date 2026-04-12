# UI & Controls

## Camera

- Fixed orthographic camera, top-down (or slight ~30-45° angle for depth)
- No rotation, no tilt
- WASD or edge-scroll to pan
- Mouse wheel for **smooth zoom** in/out
- Smooth zoom works naturally with 3D — no fixed zoom levels needed

## Core Controls (defaults — all rebindable)

| Input | Action |
|-------|--------|
| Left Click | Select / place building / confirm action |
| Left Click + Drag | Draw fields, paint roads, draw routes |
| Right Click | Cancel placement / deselect |
| WASD | Pan camera |
| Scroll Wheel | Smooth zoom |
| R | Rotate building (90° increments during placement) |
| B | Open build menu |
| T | Open tech tree |
| P | Open priority panel |
| Escape | Close menus / cancel |
| Space | Pause / unpause |
| 1, 2, 3 | Game speed (1x, 2x, 3x) |
| Delete | Demolish selected building |

All keybindings are **configurable via the settings menu**. Player can rebind any action.

## HUD Elements

### Top Bar
- Money display
- Plank count
- Worker count (idle / total)
- Game speed controls (pause, 1x, 2x, 3x)

### Build Menu
- Side panel or bottom bar
- Categories: Fields, Forestry, Processing, Storage, Infrastructure, Roads
- Shows cost (money + planks), size, and description for each building
- Locked buildings shown greyed out with research requirement
- Ghost preview on grid before placement

### Building Info Panel
- Click a building to open its info panel
- Shows: what it produces, input/output resources, current status (active/idle/disabled)
- Buttons: Disable/Enable, Set crop type (for fields), Upgrade (if available)
- Supply Storage: shows resource type and current stock

### Worker Info Panel
- Click a worker to see their info
- Current task, current equipment, status
- Any active restrictions (zone, task type)
- Option to set restrictions

### Task Queue Panel
- Overview of all pending tasks across the farm
- Grouped by category (field work, processing, transport)
- Shows how many tasks are waiting vs. being worked on
- Highlights bottlenecks (many pending tasks = need more workers or equipment)

### Dealer Panel
- Opens when clicking the Dealer (or via hotkey)
- Buy tab: seeds, fertilizer, spray, vehicles, equipment
- Sell tab: auto-sell configuration with thresholds per resource
- Shows current stock at dealer (delivery delay?)

### Equipment Panel
- Overview of all owned vehicles and attachments
- Shows status: available, in use (by which worker), stored at which garage
- Quick view to spot equipment shortages

### Tech Tree Panel
- Full tree visible from the start
- Researched items highlighted, available items clickable
- Shows cost and what each unlock enables

## Notifications

Unobtrusive toast messages in the corner for events:
- "No seeds available — order at Dealer"
- "Storage full — barn at capacity"
- "Field cleared — construction complete"
- "New research available"
- "Worker idle — no tasks"
- "Equipment shortage — tasks waiting for tractor"

Notifications should be clickable — clicking jumps the camera to the relevant building/worker.

## Settings Menu

- **Controls**: Full keybinding remapping
- **Audio**: Music volume, SFX volume, ambient volume
- **Game**: Default game speed, edge-scroll toggle, edge-scroll speed
- **Display**: Resolution, fullscreen/windowed, VSync

## Open Questions

- ~~Minimap~~ — **Deferred.** When added, consider Factorio-style schematic view at far zoom levels (icons/colored blocks instead of actual 3D models) — real models become unreadable at extreme zoom-out.
- ~~Tutorial~~ — **Deferred but required before any public release** (including early access/alpha). Interactive guided tutorial preferred over text-heavy instructions.
- ~~Info overlays~~ — **Deferred.** Traffic density, building input/output flow, bottleneck highlighting. Add when transport system is mature.
- ~~Notification history~~ — **Yes, include at launch.** Scrollable log panel so player can review past notifications. Clickable entries jump to the source.
