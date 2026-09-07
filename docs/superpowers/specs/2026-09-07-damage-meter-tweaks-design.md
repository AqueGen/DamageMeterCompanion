# DamageMeterTweaks - design

Date: 2026-09-07
Status: approved for planning

## Purpose

Blizzard shipped a built-in Damage Meter in 12.x (`Blizzard_DamageMeter`). It works, but four things are worse than in Details:

1. Seeing a player's spell breakdown requires a click. In Details a hover is enough.
2. Switching the tracked type (Damage Done, Healing, Interrupts, ...) or the segment requires aiming at the small dropdown widgets in the window header. In Details a right-click anywhere on a bar opens the switch panel.
3. Multiple meter windows cannot be attached to each other, and their sizes cannot be matched. Move one and the others stay behind; resize one and the row stops lining up.
4. Numbers are unreadable at current damage scales. `AbbreviateLargeNumbers` stops at thousands, so a spell row reads `56716 K (40,639) 18%` where Details reads `56.71M`.
5. Transparency is a single fixed value, so a meter placed over the play area is either always in the way or always too faint to read. Details has two: one for idle, one for hover.
6. There is no key binding for the meter at all - no `BINDING_NAME_*` for it exists in the UI source. Details binds show/hide of each window.
7. The meter sits on the `MEDIUM` strata with no way to change it, so it can end up under another addon's frames.

DamageMeterTweaks is a standalone addon that adds these behaviours on top of the Blizzard UI without replacing any of it. It is deliberately limited to control, placement and legibility: every piece of analysis stays Blizzard's.

Not in scope: our own data collection, our own bars, our own tooltip, our own window layout. We never compute a number - we only re-render one the game already gave us.

Deliberately rejected from Details, so the boundary is on record:

- **Per-window scale.** Edit Mode already exposes frame width, frame height, text size and bar height. A scale slider would fight Edit Mode's ownership of the primary window's size and duplicate the rest.
- **Auto switch to current segment.** The session dropdown already has a permanent Current mode; set it once and the window behaves that way.
- **Reset window position.** The window template is `clampedToScreen="true"`, so a window cannot be lost offscreen.
- **Skins, backdrops, row colours, statusbar colours.** Appearance, not control, and Blizzard ships four styles plus two transparency sliders.
- **Bookmarks.** Our right-click menu changes the type in fewer clicks than configuring bookmarks would take.
- **Report to chat.** That is data leaving the addon - analysis, not control.
- **Scroll key bindings and update interval.** The ScrollBox already handles the wheel, and the refresh cadence is engine-side.

## Constraints discovered while reading the source

These come from `Blizzard_DamageMeter` in the 12.x UI source and from Details, and they shape the design.

- **Combat session data is Secret in combat.** Every `C_DamageMeter` getter is marked `SecretWhenInCombat = true`, and `canaccesssecrets()` grants the right to operate on such values only to untainted code. An addon cannot do arithmetic on, format, or concatenate the returned amounts while in combat. Two consequences: we never build our own spell tooltip (we open Blizzard's existing source window and pass the element data through untouched), and our number formatting can only run while the values are not secret.
- **Details lives under the same rule.** `containerIsOpen` in `Details/core/parser_nocleu1.lua:712` calls `issecretvalue()` on name, GUID, amount and class, refuses to ingest the session if any is secret, and spins `waitSecretDropTimer` until secrecy lifts. Details' well-formatted numbers are post-secrecy data, not a technique we are missing.
- **The maximum number of windows is 3**, not 4 (`MAX_DAMAGE_METER_SESSION_WINDOWS` in `DamageMeter.lua`). Globals are `DamageMeterSessionWindow1` .. `DamageMeterSessionWindow3`.
- **The primary window is Edit Mode controlled.** `DamageMeterMixin:SetupSessionWindow` anchors window 1 to the `DamageMeter` frame with TOPLEFT/BOTTOMRIGHT, and `CanMoveOrResizeSessionWindow` returns false for it. Secondary windows can be attached to the primary; the primary can never be attached to anything.
- **Mouse-over state is already tracked.** `DamageMeterSessionWindowMixin:OnEnter` sets the `MouseOver` OnUpdate reason, and the OnUpdate clears it once the mouse is off both the window and its resize button. Hooking `SetOnUpdateReason` gives us enter and leave without an OnUpdate of our own.
- **Window alpha is owned by Edit Mode.** `DamageMeterMixin:SetWindowAlpha` pushes the Transparency setting onto every session window, so anything we set can be overwritten when that setting changes.
- **The source window declares `frameStrata="HIGH"` explicitly**, which overrides inheritance from its parent. Raising the meter's strata without raising the source window's would push the spell breakdown behind the bars.
- **Session windows resize between 200x120 and 600x400** (`ResizeBounds` in `DamageMeterSessionWindow.xml`). The primary window is exempt: it inherits the size of the Edit Mode `DamageMeter` frame and can exceed that box, so matching a secondary window to it may clamp.
- **Nothing here is protected.** `DamageMeter` is a plain `Frame` on `UIParent`, session windows are plain frames created by `CreateFrame`. Hooking scripts and calling `SetPoint` is safe.
- **All number text goes through one function.** `DamageMeterEntryMixin:UpdateValue` calls `GetValueText`, which dispatches on the Edit Mode Numbers setting (Minimal, Compact, Complete) and builds the string with `AbbreviateLargeNumbers` plus `DAMAGE_METER_ENTRY_FORMAT_*`. `DamageMeterSpellEntryMixin` inherits it and forces Complete, so one hook covers both the session window bars and the source window spell rows.
- **Bar clicks are wired per entry init.** `DamageMeterSessionWindowMixin:InitEntry` calls `frame:SetScript("OnClick", ...)`, and `SetupEntry` calls `frame:RegisterForClicks("LeftButtonDown", "RightButtonDown")`. Left and right button currently do the same thing: `ShowSourceWindow(elementData, IsShiftKeyDown())`.
- **Entry frames are pooled** by a ScrollBox. `SetupEntry` runs on acquire, `InitEntry` runs on every data refresh. Scripts must be installed from a hook on one of those, not once at load.
- **The type and session menus already exist** as `DamageMeterTypeDropdown` and `SessionDropdown` on each session window, but their menu generators are file-local closures. Their content is reproducible from public API and global strings.
- **The source window auto-hides on `GLOBAL_MOUSE_DOWN`** when it is not sticky (`DamageMeterSourceWindow.lua`). There is no leave-based hiding today, so hover mode needs its own.

## Reference: how Details does it

- Numbers: `56.71M`, `40.6K`, `18.0%` in three aligned columns. Two significant decimals on the amount, one on the rate and the percentage, unit letter attached with no space. We copy the number style, not the column layout.
- Right-click on a bar (`window_main.lua`, `lineScript_Onmousedown`) calls `Details.switch:ShowMe(instance)`, a custom overlay panel of ~1445 lines showing display tiles plus a segment block. The content is display type plus segment - the same two axes we need. We reproduce the content with `MenuUtil`, not the panel.
- Hover on a bar (`lineScript_Onenter`) calls `MontaTooltip`, which builds a GameCooltip listing the source's spells; the full breakdown window opens on click. We cannot build that tooltip (Secret data), so hover opens Blizzard's source window instead. It carries the same information.

## Architecture

Four Lua files plus a TOC, no libraries, no Ace.

```text
DamageMeterTweaks/
  DamageMeterTweaks.toc
  Core.lua          -- saved variables, defaults, slash command, hook installation
  Hover.lua         -- hover-to-open source window
  Format.lua        -- readable numbers on bars and spell rows
  ContextMenu.lua   -- right-click menu on bars
  Config.lua        -- settings panel: global toggles plus a per-window table
  Snap.lua          -- magnetic anchoring and size matching between session windows
  Presence.lua      -- idle/hover transparency and frame strata
  Bindings.xml      -- key bindings, with their handlers in Core
```

Each file registers itself with Core and owns exactly one behaviour. Nothing is shared between Hover, Format, ContextMenu, Snap, Presence and Config except the settings table and a helper that maps a frame to its session window. Config only reads and writes that table and calls into Snap's public apply function; it holds no logic of its own.

### Load order and the hook seam

`Blizzard_DamageMeter` is a load-on-demand-free addon that loads with the UI, but our TOC cannot depend on load order alone for the frames to exist. Core waits for `PLAYER_LOGIN`, then verifies `DamageMeter` and `DamageMeterSessionWindowMixin` exist. If either is missing (feature disabled by CVar, or a future patch renamed things), the addon prints one line and installs nothing. Every hook is installed exactly once.

The single shared seam is:

```lua
hooksecurefunc(DamageMeterSessionWindowMixin, "InitEntry", function(sessionWindow, frame, elementData)
    -- runs after Blizzard's own SetScript("OnClick", ...)
end)
```

Both Hover and ContextMenu attach from this one hook. `hooksecurefunc` on a table plus key is used so we never replace Blizzard's function, only append to it.

### Hover

On `OnEnter` of a bar, start a `C_Timer` of `settings.hoverDelay` (default 0.15s). When it fires and the mouse is still on the bar, call `sessionWindow:ShowSourceWindow(elementData, false)` - the same call the click path makes, with sticky false.

On `OnLeave`, if the source window is not sticky and the mouse is not over the source window, hide it. A short grace period (one frame plus the mouse-over check) covers moving the cursor from the bar into the source window, which sits flush against the session window edge.

Left click keeps working and now means "pin": it calls `ShowSourceWindow(elementData, true)` so the window stays and gets a close button. Shift is no longer needed but keeps working.

Deaths entries are untouched: `ShowSourceWindow` routes any source with a `deathRecapID` to `OpenDeathRecapUI`, and opening the death recap on hover would be hostile. Hover skips entries where `elementData.deathRecapID` is a non-zero number; that field is documented `NeverSecret`, so reading it is safe in combat.

### Context menu

Our `OnClick` replaces the one Blizzard installed in `InitEntry` (installed after it, from the same hook):

- `LeftButton` -> `sessionWindow:ShowSourceWindow(elementData, true)`
- `RightButton` -> `MenuUtil.CreateContextMenu(frame, generator)`, anchored at the cursor

The generator builds, in order:

1. Type radios in three submenus - Damage, Healing, Actions - mirroring `DAMAGE_METER_CATEGORIES`. Selection reads `sessionWindow:GetDamageMeterType()`, setting goes through `DamageMeter:SetSessionWindowDamageMeterType(sessionWindow, type)`.
2. A divider, then session radios: the entries of `C_DamageMeter.GetAvailableCombatSessions()` formatted the way `InitializeSessionDropdown` formats them (`DAMAGE_METER_COMBAT_NUMBER` for unnamed sessions, duration in brackets via `SecondsToClock`), then Current and Overall. Setting goes through `DamageMeter:SetSessionWindowSessionID(sessionWindow, type, sessionID)`.
3. A divider, then window actions: show new window, hide this window, lock/unlock, reset all sessions - each calling the matching public `DamageMeterMixin` method - plus, when the window is linked to another, two checkboxes for match width and match height, and an entry that opens our settings panel.

All labels come from existing global strings (`DAMAGE_METER_TYPE_*`, `DAMAGE_METER_CATEGORY_*`, `DAMAGE_METER_CURRENT_SESSION`, `DAMAGE_METER_OVERALL_SESSION`, `DAMAGE_METER_SHOW_NEW_WINDOW`, ...), so the addon is localised for free and ships no locale files.

The type and category tables are duplicated from `DamageMeterSessionWindow.lua` because the originals are file-local. This is the one piece of the design that can drift when Blizzard adds a type. A unit test asserts that every value in `Enum.DamageMeterType` appears in our table, so a new patch surfaces as a test failure rather than a silently missing menu entry.

### Number formatting

A post-hook on `DamageMeterEntryMixin:UpdateValue` runs after Blizzard has set its own text:

```lua
hooksecurefunc(DamageMeterEntryMixin, "UpdateValue", function(entry)
    -- entry.value, entry.valuePerSecond, entry.sessionTotalValue
end)
```

If `issecretvalue(entry.value)` is true we return immediately and Blizzard's string stands. Otherwise we build our own string and `SetText` it on the same FontString. Layout is untouched: one right-aligned string, exactly where Blizzard puts it, so a narrow window degrades the way it does today.

The format mirrors Details' numbers within Blizzard's single-string shape, and respects the Edit Mode Numbers setting the same way `GetValueText` does:

| Numbers setting | Blizzard today | Ours |
| --- | --- | --- |
| Minimal | `56716 K` | `56.72M` |
| Compact | `56716 K (40,639)` | `56.72M (40.6K)` |
| Complete | `56716 K (40,639) 18%` | `56.72M (40.6K) 18.0%` |

(Rounded, not truncated - Details truncates, but a rounded 56,716,000 is `56.72M` and being right beats matching Details digit for digit.)

Abbreviation rules: below 1000 the raw number, then `K`, `M`, `B` with two decimals for the main value and one for the parenthetical rate, trailing zeros kept so column widths stay stable, unit letter attached with no space. Percentage gets one decimal.

The secrecy check is per entry and per update, not a global combat check, because the two are not the same thing: the flag lives on the value. `issecretvalue` is the same predicate Details uses.

Because our text only appears once secrecy lifts, numbers visibly change format at the end of a pull. That is inherent - the alternative is not formatting at all - but it is worth stating in the addon description so it does not read as a bug. A setting turns the whole feature off.

### Snap and size matching

State lives in `DamageMeterTweaksCharDB.links`, keyed by window index. Links are per character because Blizzard's own window data is (`DamageMeterPerCharacterSettings`), so a link would otherwise point at a window that does not exist on the alt. Behaviour settings stay account-wide in `DamageMeterTweaksDB`.

```lua
links[2] = {
    to = 1,
    point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = 0, y = -4,
    matchWidth = true, matchHeight = false,
}
```

A post-hook on `DamageMeterSessionWindowMixin:OnDragStop` runs the snap decision:

1. For each other shown session window, test the dragged window's four edges against the target's four edges. If the gap is within `SNAP_THRESHOLD` (15px) and the perpendicular overlap is non-zero, take the closest candidate.
2. On a match: `ClearAllPoints`, `SetPoint(point, target, relPoint, x, y)`, `SetUserPlaced(false)` so Blizzard's frame position cache stops fighting us, and record the link.
3. On no match: clear any existing link for that window and leave Blizzard's own `StopMovingOrSizing` result alone.

Once anchored, the frames move together for free - that is what frame anchoring does. No OnUpdate, no position polling.

A snap also sets one size-matching flag, the one perpendicular to the edge it landed on: snapping above or below a window sets `matchWidth`, snapping to its left or right sets `matchHeight`. That is the axis that has to agree for the pair to read as one block. The other axis is left alone and can be turned on from the right-click menu or the settings panel, where both flags appear as checkboxes on the linked window.

Applying a size match means `SetWidth(target:GetWidth())` or `SetHeight(target:GetHeight())`, clamped to the window's own resize bounds (200..600 by 120..400). When the target is the primary window and it is larger than the bound, the secondary clamps and the panel shows the effective value rather than the requested one - silently ignoring the request would be worse.

Matched sizes stay matched: each session window gets `HookScript("OnSizeChanged", ...)`, which fires for a mouse resize, for a size set from our own panel, and for the primary window being resized in Edit Mode. The handler pushes the new size to every window linked to it with the matching flag set. A re-entry guard stops the push when the size is already correct, so a chain of three windows settles in one pass and a mutual match cannot loop.

Cycle prevention: before recording `a -> b`, walk the link chain from `b`; if it reaches `a`, refuse the snap. Depth is at most 3, so this is a two-iteration loop.

Restore: on `PLAYER_ENTERING_WORLD`, after a `C_Timer.After(0)` so Blizzard's saved frame position cache has been applied, re-apply every stored link in dependency order (targets before dependents). Links whose target window is hidden, or whose source window index is the primary, are dropped.

The primary window is never a snap source (`CanMoveOrResizeSessionWindow` is false for it and it has no drag), only a target.

### Presence: idle transparency and strata

Two settings that Blizzard has no equivalent for, both applying to the meter as a whole rather than per window.

**Idle transparency.** Edit Mode's Transparency stays the authority for the hover value - whatever the player already set is what they see when the mouse is on the window. We add a second, lower value used when it is not. Enter and leave both come from one hook:

```lua
hooksecurefunc(DamageMeterSessionWindowMixin, "SetOnUpdateReason", function(window, reason, enabled)
    if reason == "MouseOver" then -- enabled true on enter, false when the OnUpdate sees the mouse leave
```

The applied alpha is the Edit Mode value when hovered and `editModeAlpha * idleFactor` when not, so raising or lowering the Edit Mode slider keeps working and the two never drift apart. `DamageMeterMixin:OnWindowAlphaChanged` is hooked as well so an Edit Mode change re-applies through our path instead of overwriting it.

Windows made non-interactive never receive OnEnter, because their mouse is disabled. Those stay at the idle value permanently, which is the sensible reading of "uninteractable", and the panel says so next to the setting rather than leaving it as a surprise.

**Strata.** A dropdown over the standard strata list, applied to the `DamageMeter` frame - session windows are its children and inherit. The source window does not: its template pins `HIGH`. So whenever we set the meter's strata we also set each source window one level above it, keeping the spell breakdown in front of the bars it belongs to.

### Key bindings

`Bindings.xml` declares three bindings under one header, with the handler bodies living in Core:

| Binding | Action |
| --- | --- |
| Toggle meter | Flips the `damageMeterEnabled` CVar - the same switch the settings checkbox uses. The primary window cannot be hidden any other way (`CanHideSessionWindow` is false for it) |
| Toggle window 2, toggle window 3 | `GetSessionWindow(i)` then hide it, or set it up again if it is hidden or missing |

Whether `SetCVar` on `damageMeterEnabled` is permitted in combat is unverified, so the in-game probe checks it alongside the secrecy questions. If it is blocked, the binding refuses with a message in combat rather than erroring, and the window bindings - plain frame Show and Hide - are unaffected either way.

### Settings panel

Registered with the built-in Settings API - no Ace, no libraries. Two parts under one category named DamageMeterTweaks, reachable from the game's options and from `/dmt`.

The behaviour half uses the standard vertical layout, so it looks like every other options page: hover on/off, hover delay slider, right-click menu on/off, number formatting on/off, snap on/off, snap threshold slider, idle transparency slider, strata dropdown.

The window half is a canvas subcategory holding one row per session window, three rows maximum, rebuilt whenever a window is shown, hidden or relinked:

| Column | Window 1 (primary) | Windows 2-3 |
| --- | --- | --- |
| Shown | read-only, always on | checkbox, calls `ShowNewSecondarySessionWindow` / `HideSessionWindow` |
| Width, Height | read-only, with a note that Edit Mode owns it | numeric entry, clamped to the resize bounds |
| Attached to | read-only "-" | dropdown of the other windows plus "none", and the edge to attach on |
| Match width, Match height | read-only | two checkboxes |

The primary window's size and position cells are read-only because `CanMoveOrResizeSessionWindow` returns false for it - the panel says so in place rather than offering a control that would do nothing.

The type and segment columns this table originally carried were dropped during Task 9, on the same reasoning the Attached-to column was: the right-click menu already changes both in fewer clicks than opening a settings page, and a second way to do one thing is worse than one good way. What the panel is for is the state the menu cannot show at a glance - which windows exist, how big they are, and what is attached to what.

Editing a size cell calls `SetSize` on the window, which trips the `OnSizeChanged` hook and propagates to anything matched to it, so there is one code path for sizing regardless of where the change came from.

`/dmt` with no argument opens the panel. `/dmt hover`, `/dmt snap`, `/dmt menu` still toggle from chat for quick testing. Settings persist in `DamageMeterTweaksDB`, window links in `DamageMeterTweaksCharDB`. Toggling a feature off makes its handlers no-op rather than uninstalling hooks, which keeps the install path single-shot.

## Error handling

- Missing Blizzard globals at login: print one message, install nothing, do not error.
- Any `elementData` field read is limited to `deathRecapID`, documented `NeverSecret`. No amounts, no names, nothing conditionally secret is read, compared or formatted.
- `C_DamageMeter.GetAvailableCombatSessions` is called only from the menu generator, i.e. only on a right-click, i.e. only from an untainted user interaction. If it returns an empty list the session section still shows Current and Overall.
- Formatting checks `issecretvalue` on every value before touching it and bails out on the first secret one. It never reads a value it has not cleared.
- The toggle binding refuses with a printed message if the CVar cannot be set in combat, rather than letting the error surface.
- Snap restore refuses to anchor to a hidden or non-existent window rather than throwing.

## Testing

Logic that does not touch WoW frames is testable headless with busted (the existing WSL Lua 5.1 setup):

- Snap geometry: given two rectangles and a threshold, which edge pair wins, and does an out-of-range pair correctly produce no snap.
- Which size flag a snap sets: a bottom or top landing sets width, a side landing sets height.
- Size clamping: a requested size outside 200..600 by 120..400 comes back clamped, and the clamped value is what the panel reports.
- Cycle prevention: a chain 3 -> 2 -> 1 refuses a 1 -> 3 link, and a mutual size match settles instead of looping.
- Restore ordering: a link set is applied targets-first.
- Menu completeness is checked at `Enable()` against the live `Enum.DamageMeterType` rather than in a spec file: a headless test would have to supply its own enum, which would only prove our table matches a copy of itself. The runtime check prints a warning naming any type a patch added and we do not list.
- Number formatting: a table of inputs to expected strings covering each magnitude boundary (999, 1000, 999999, 1000000, 1e9), each Numbers setting, and a zero value.

- Idle alpha maths: the applied value tracks the Edit Mode alpha times the idle factor, and a changed Edit Mode alpha moves both states.
- Strata ordering: the source window always lands one level above whatever the meter is set to, including at the top of the list.

Before any of the formatting work starts, a throwaway probe runs in game: a slash command that prints `issecretvalue` for `value`, `valuePerSecond` and `sessionTotalValue` of the first entry, in combat and out, and attempts `SetCVar("damageMeterEnabled", ...)` in combat. The design assumes all three values are secret in combat and none out of it; the probe confirms that before we build on it, and its result may widen or narrow both the formatting feature and the toggle binding.

The frame-bound parts - hover timing, menu appearance, actual anchoring, number rendering, transparency, strata, bindings, the panel - are verified in game: two windows, snap one under the other and confirm the width lines up, drag-resize the upper one and confirm the lower follows, move the primary in Edit Mode and confirm the secondary follows, set a size from the panel and confirm it propagates the same way, reload and confirm links and sizes survive, then enter combat and confirm hover and the right-click menu still work with Secret data live.

## Open items for the implementation plan

- ~~Whether hover should suppress itself while the source window is sticky on a different source, or retarget it.~~ **Settled during Task 3: hover never touches a pinned window.** Retargeting looked right because Details does it, but Details hovers into a tooltip and pins into a separate window, so it has two surfaces. We have one, and retargeting it would destroy the pin the user just made - including when the click lands inside the hover delay and the timer fires afterwards.
- Snap indicator while dragging (a highlight on the edge about to be snapped to) is desirable but not required for v1.
- Whether the decimal separator should follow the client locale rather than always being a dot. Proposed: always a dot, because Blizzard's own `AbbreviateLargeNumbers` output and Details both use one.
