# DamageMeterTweaks phase 2 - windows and anchors

Date: 2026-09-07
Status: draft for review
Follows: `2026-09-07-damage-meter-tweaks-design.md`

## Purpose

Phase 1 shipped hover details, a right-click menu, magnetic snapping, readable numbers, transparency, strata and key bindings. Using it revealed that the placement half does not survive contact with how the meter is actually arranged:

1. **Snapping gives no feedback.** Dragging a window near another shows nothing about whether releasing will attach it, so the feature feels unreliable even where it works, and there is no way to tell a successful attach from two windows that merely ended up adjacent.
2. **Snapped windows do not travel together.** Moving window 1 leaves the others behind. The link is never created; see the diagnosis below.
3. **There is no pixel-precise sizing.** Window 1's size cannot be set at all from the panel, and the others only through a box whose value the user cannot compare against window 1's.
4. **The spell breakdown opens where it likes.** It picks left or right from which half of the screen the window sits in, and lands on top of other panels.
5. **Three windows is not enough,** and Blizzard's limit is three.
6. **Windows cannot be chained arbitrarily** - 2 under 3, 3 under 4, 4 under 5 - because the link machinery counts to three.

The through-line: phase 1 built the right gesture and then broke it, hid it, and capped how far it could reach.

Not in scope, unchanged from phase 1: our own data collection, our own bars, our own tooltip, anything that reads combat numbers.

Rejected during this design, so the reasoning is on record: **an explicit anchor picker in the settings panel** - attach to window N, at side S, corner to corner. It was designed in response to a belief that Edit Mode owning window 1 made drag-snapping to it impossible. That belief was wrong: only the window being moved has to be draggable, and window 1 never moves during the gesture. With the drag hook fixed and the snap visible, the picker would be a second way to do one thing, and a wordier one.

## Constraints discovered while reading the source

- **`GetDamageMeterOwner()` returns a plain field** set by `SetDamageMeterOwner` (`DamageMeterSessionWindow.lua:786-794`). A session window calls its owner for sixteen things but never checks what the owner is. This is the seam that makes extra windows possible: we supply our own owner object and Blizzard's three-window assertions are never on the path.
- **A session window is self-sufficient once configured.** `OnShow` registers its own events, and `OnEvent` refreshes from its own damage meter type and session (`DamageMeterSessionWindow.lua:181-211`). Given a type and a session it populates and updates itself with no help from any owner.
- **`assertsafe` does not halt** (`Blizzard_SharedXMLBase/ErrorUtil.lua:8-29`) - it reports through the error handler and returns. So a mistake that reaches Blizzard's index assertions degrades into error spam rather than a broken client. We still avoid that path entirely.
- **`MAX_DAMAGE_METER_SESSION_WINDOWS = 3` is file-local** to `DamageMeter.lua`, as is `SetSavedWindowData`, which asserts on it. Blizzard's own three windows keep their real owner and are untouched by any of this.
- **Window 1's size is an Edit Mode setting.** Blizzard's own resize handle writes it with `EditModeManagerFrame:OnSystemSettingChange(self, Enum.EditModeDamageMeterSetting.FrameWidth, width)` (`EditModeSystemTemplates.lua:3438-3441`). The bounds are 200-600 wide and 120-400 tall (`EditModeSettingDisplayInfo.lua:1278-1300`) - the same as every other window's `ResizeBounds`, so one clamp serves all windows.
- **The breakdown's side is chosen by screen half** in `DamageMeterSourceWindowMixin:AnchorToSessionWindow` (`DamageMeterSourceWindow.lua:280-329`), which also flips the resize button's corner and texture to match. It is a plain mixin method and can be post-hooked.
- **Drag scripts are declared in XML as `<OnDragStop method="OnDragStop"/>`** (`DamageMeterSessionWindow.xml:150`). Whether that resolves the method at load or at call time is not determinable from source, and phase 1's final review flagged it as the one unsettled question. `HookScript` on the script itself sidesteps it.

## Diagnosis: why snapped windows do not travel together

Phase 1 hooks `OnDragStop` as a mixin method, on the table for windows created later and per instance for those that already exist. If the XML `method=` attribute binds the function at load time, neither reaches a window restored from saved data at login, `Snap.FindSnap` never runs, no link is ever written, and the windows only appear stuck because they were dropped next to each other.

The fix is not to guess which binding applies: `window:HookScript("OnDragStop", handler)` hooks the script the engine actually invokes, which is true under either. Phase 1 already uses `HookScript` for `OnSizeChanged` for the same reason.

This also stops mattering as the primary path once anchors are explicit - a link set from the panel is written whether or not a drag was ever observed.

## Architecture

Phase 1's modules stay. Three change and one is new.

```text
Core.lua        -- unchanged apart from the window registry helpers
Format.lua      -- unchanged
Hover.lua       -- unchanged
ContextMenu.lua -- unchanged apart from reaching windows through the registry
Presence.lua    -- unchanged apart from reaching windows through the registry
Snap.lua        -- link model generalised, drag hook corrected, gap offsets
Config.lua      -- the window table becomes a variable-length list with anchor controls
Windows.lua     -- NEW: the proxy owner, extra window creation, and the registry
Breakdown.lua   -- NEW: which side the spell breakdown opens on
```

### Windows.lua - the registry and the proxy owner

Every other module currently asks `DamageMeter:GetSessionWindow(index)` and loops 1 to 3. That becomes `ns.Windows.Get(index)` and `ns.Windows.ForEach(func)`, which cover Blizzard's three and ours alike. This is the single change that makes every other feature index-agnostic; without it each feature would grow its own special case.

Extra windows are real `DamageMeterSessionWindowTemplate` frames, parented to `DamageMeter` so they inherit its strata and hide with it, created with `CreateFrame` and given our proxy as their owner:

```lua
window:SetDamageMeterOwner(ns.Windows.proxyOwner, index)
```

The proxy implements the methods a window calls on its owner, reading and writing our saved variables instead of Blizzard's:

| Called by the window for | Proxy behaviour |
| --- | --- |
| `SetSessionWindowDamageMeterType` | store, then `window:SetDamageMeterType` |
| `SetSessionWindowSessionID` | store, then `window:SetSession` |
| `SetSessionWindowLocked`, `SetSessionWindowNonInteractive`, `SetSessionWindowMinimized` | store, then the matching window setter |
| `HideSessionWindow` | hide and store; unlike Blizzard's, any of our windows may be hidden |
| `CanHideSessionWindow`, `CanMoveOrResizeSessionWindow` | true for every window we own |
| `ShowNewSecondarySessionWindow`, `CanShowNewSecondarySessionWindow` | create another of ours; true unless the soft cap warning applies |
| `GetSessionType`, `GetSessionID` | our stored defaults for a new window |

The window's own settings dropdown therefore works on our windows exactly as on Blizzard's, with no changes to that code.

**Appearance.** Blizzard pushes bar height, spacing, text scale, alpha, style, number display, background alpha, class colour and spec icons onto its own three whenever Edit Mode changes. Our windows mirror those, read through the public getters on `DamageMeterMixin`, re-applied whenever Edit Mode changes any of them and once at creation. On top of that, a window may carry per-window overrides for bar height and text size, because a narrow companion window next to a large main one is the reason to have more than one in the first place. An override, when set, wins over the mirrored value; clearing it returns the window to following Edit Mode.

This mirroring is the part most exposed to a future patch: a new appearance setting Blizzard adds will not reach our windows until we mirror it too. That is the price of the feature and is called out here so it is not a surprise later.

**Persistence.** Extra windows live in `DamageMeterTweaksCharDB.windows`, keyed by index, each holding type, session, shown, locked, non-interactive, minimized, size, position, and any appearance overrides. Position is ours rather than Blizzard's frame position cache, because that cache is keyed on names Blizzard owns. A window with a link does not persist a position - its anchor determines where it is.

**Soft cap.** There is no hard limit. Creating an eleventh window prints one line saying that each window is a scroll box refreshed on every combat event and that the cost is not free. It does not refuse.

### Snap.lua - links stop being capped at three

The link keeps an explicit anchor pair and loses its dependence on a three-window world:

```lua
links[4] = { to = 2, point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = 0, y = -4, matchWidth = true, matchHeight = false }
```

The stored form is the raw `SetPoint` argument list, which is what `ApplyLink` needs anyway. Dragging is the only thing that writes it: the side follows from which edge the window was released against, and the gap is an offset the panel can adjust afterwards.

An explicit anchor picker in the panel - attach to window N, at side S, corner to corner - was designed and then dropped. It would have been the second way to do one thing, and the case that seemed to demand it turned out not to exist: attaching window 2 to window 1 only requires dragging window 2, so Edit Mode owning window 1's position never blocked anything. What blocked it was the drag hook not firing at all.

`FindSnap`, `WouldCycle` and `ApplyOrder` are already written against an arbitrary link graph; only `ApplyOrder`'s `for index = 1, 3` and the callers' loops become registry walks. Cycle prevention already covers 2 to 3 to 4 back to 2.

The drag hook moves from the mixin method to `HookScript("OnDragStop", ...)`, installed per window at creation, for Blizzard's three and ours alike.

Dragging still snaps, and writes exactly the link the panel writes. It is a shortcut over the same model, not a second mechanism - which is what keeps it from being the second way to do one thing that phase 1 argued against.

### Snap preview

Today a drag gives no sign whether releasing will attach or not, which is most of why the feature feels unreliable even where it works.

While a window is being dragged, `FindSnap` runs on each frame. When it returns a match, a highlight appears along the edge the window will attach to - a thin bar on the target's edge and a matching one on the dragged window's, both in the same colour, so the pair reads as one join. No match, no highlight. Release attaches, and the highlight goes away with the drag.

Details solves the same problem with a trail of small textures drawn between the two windows' centres, green when a snap is available and red when not (`Details/frames/window_main.lua:554-584`). Edge highlighting is chosen over that because the trail answers "something is near" while the highlight answers "this edge, this side" - and the second is the question being asked when four windows are on screen. It is also cheaper: two textures that move, rather than one per fifty pixels of distance.

The highlight is drawn on our own overlay frame, not on Blizzard's windows, so nothing about their appearance is touched and the whole feature disappears cleanly when snapping is switched off.

### Config.lua - the window list

The Windows page becomes a variable-length list with an Add window button and, per row:

| Control | Window 1 | Our windows |
| --- | --- | --- |
| Shown | read-only, always on | checkbox |
| Width, Height | numeric entry, written through Edit Mode | numeric entry, clamped to 200-600 by 120-400 |
| Attached to | read-only "-" | read-only, naming the window and the side, with a Detach button |
| Gap | - | numeric, pixels between the two windows |
| Match width, Match height | - | checkboxes |
| Bar height, Text size | read-only, Edit Mode owns it | numeric override, blank means follow Edit Mode |
| Remove | - | button, on our windows only |

Window 1 gains size entry it did not have, because `OnSystemSettingChange` is the same call Blizzard's own resize handle makes. That call is made from our tainted stack, so it is wrapped: a refusal prints one line rather than erroring, and the panel re-reads the effective size afterwards so what is shown is what took.

Removing a window destroys the frame, drops its saved entry, and clears every link pointing at it.

### Breakdown.lua - which side the spell breakdown opens

A post-hook on `DamageMeterSourceWindowMixin:AnchorToSessionWindow` re-anchors when the setting is not Auto. Auto leaves Blizzard's screen-half choice alone.

Left and right reuse Blizzard's own anchoring, including the resize button's corner and texture flip, by choosing which branch to redo. Above and below anchor the breakdown's bottom to the window's top, or its top to the window's bottom, matching horizontal edges. The resize button stays in the bottom-right corner for those two: Blizzard's flip logic only knows left from right, and inventing a vertical variant would mean redrawing textures we do not own. The button still works; it is only in a less natural corner.

The setting is global rather than per window, because the reason to change it is where the meter sits relative to the rest of the UI, which is one arrangement.

## Error handling

- Every window index that comes from saved variables is checked against the registry before use. An entry naming a window that no longer exists is dropped at login rather than carried.
- `OnSystemSettingChange` for window 1's size is wrapped so a refusal - in combat, or if Edit Mode declines a tainted caller - prints and leaves the size alone.
- Extra window creation is refused, with a printed reason, if `DamageMeterSessionWindowTemplate` is missing, which is how a patch that renames it would surface.
- Links form a forest, not a graph: a window has at most one target, cycles are refused, and the apply order is computed targets-first. Corrupt saved data cannot produce an infinite walk.

## Testing

Headless with busted, extending phase 1's 48 tests:

- Link shape: the edge a drag lands on resolves to the right anchor point pair, and a gap applies with the right sign for each of the four sides.
- Snap preview geometry: given a snap result and two rectangles, where the two highlight bars go and how long they are.
- `ApplyOrder` over an arbitrary index set, not just 1 to 3, including a chain of five and two independent chains.
- `WouldCycle` over the same, including a cycle that does not contain the window being linked.
- The registry: enumeration order, an index that does not exist, and removal clearing inbound links.
- Appearance resolution: an override wins over the mirrored value, and clearing it returns to the mirrored value.
- Size clamping against the shared 200-600 by 120-400 bounds.

Frame-bound behaviour is verified in game as before, and the checklist grows a section for extra windows: create four, chain them, move window 1 in Edit Mode and confirm the whole chain follows, reload and confirm the arrangement survives, remove a middle window and confirm the windows that pointed at it come free rather than break.

## Open items for the implementation plan

- Whether an extra window should be offered in the type dropdown of Blizzard's own settings menu. Proposed: yes, since the proxy makes it work for free.
- Whether the per-window bar height override should also cover bar spacing. Proposed: no until asked, since spacing rarely differs without height differing too.
