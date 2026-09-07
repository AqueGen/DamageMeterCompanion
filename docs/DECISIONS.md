# DamageMeterTweaks - decisions taken while building it

Written 2026-09-07, at the end of the first build. These are the forks where the plan turned out to be wrong, or where two defensible answers existed and one had to be picked. Each says what was decided and why, so a later change does not undo them by accident.

## Engine facts that shaped the design

**Mixin methods are copied onto a frame when the frame is created.** `Mixin` does `object[k] = v`, so `hooksecurefunc` on a mixin table only reaches frames created after the hook. The `DamageMeter` frame and its session windows exist before `PLAYER_LOGIN`, so every hook that must reach them is installed per instance via `ns.HookInstance`, keyed by handler so two modules can hook one method. Getting this wrong yields an addon that loads cleanly and does nothing.

**Combat session values are Secret in combat**, and `canaccesssecrets()` grants access only to untainted code. We never compute a number - the formatting only runs once `issecretvalue` says the values are readable, which in practice means after combat. Details lives under the same rule and solves it the same way, by waiting.

**Setting a frame's size dispatches `OnSizeChanged` re-entrantly.** A re-entrancy guard held across a size push therefore swallows the nested event. `Snap` propagates down a chain by explicit recursion and keeps the guard only to stop a second walk starting on top of the first.

**`DamageMeterMixin:SetupSessionWindow` re-anchors every secondary window to UIParent on every call**, including when reusing a hidden frame. Any anchor this addon imposes has to be re-applied from a hook on it, which is why both `Snap` and `Presence` hook it.

## Product decisions

**Hover never touches a pinned breakdown.** Details retargets on hover, but Details hovers into a tooltip and pins into a separate window - it has two surfaces. We have one, so retargeting would destroy the pin the user just made, including when the click lands inside the hover delay and the timer fires afterwards.

**The settings panel does not offer type, segment, or an attach control.** The right-click menu changes type and segment in fewer clicks than opening a settings page, and attaching is a drag gesture. A second way to do one thing is worse than one good way. What the panel is for is the state the menu cannot show at a glance: which windows exist, how big they are, what is attached to what.

**The panel does offer numeric size entry**, because that was the point of asking for it. Values are clamped to the window's resize bounds and the panel shows the clamped result rather than silently ignoring the request.

**Window locks are honoured when dragging and when resizing, but not when re-applying an anchor.** Refusing to re-apply an anchor a window already has would silently detach a locked window on every reload, which is worse than honouring the lock too literally.

**These were considered and left out of scope**, each because Blizzard already covers it or because it is analysis rather than control: per-window scale, auto-switch to current segment, reset window position, skins and colours, display bookmarks, report-to-chat, scroll bindings, and the update interval.

## Where the code deliberately differs from Blizzard's

**`Absorbs` appears in the type menu** although Blizzard's own category list omits it. The type and its name string both exist; leaving a reachable type out of a menu whose whole purpose is reaching types would be odd. If it turns out to render an empty window, drop it and note why.

**`ContextMenu.CATEGORIES` and `TYPE_NAMES` duplicate file-local Blizzard tables.** `VerifyTypeCoverage` runs at login against the live `Enum.DamageMeterType` and prints a warning naming any type a patch adds that we do not list. A headless test could only have compared our table against a copy of itself.

**Numbers are rounded, not truncated.** Details truncates; a rounded 56,716,000 is `56.72M` and being right beats matching Details digit for digit.

## Known limitations

Nothing here has been verified in a running game client - see `IN-GAME-CHECKLIST.md`. Only pure logic is unit-tested; frame-bound behaviour has no automated coverage.

The number formatting visibly changes at the end of a pull, because that is when the values stop being secret. This is inherent, not a bug.

There are at most three meter windows. That is Blizzard's limit, not ours.

## Minor issues left open on purpose

- `Format.Abbreviate` checks the unit threshold before rounding, so 999999 renders as `1000.00K` rather than `1.00M`. Narrow band, cosmetic.
- A full scroll-box rebuild during the hover delay can leave the pending timer holding a stale element snapshot. Needs a roster change within ~150ms of a hover; self-corrects.
- `Snap.PushSize` sets its guard without a `pcall`, so an error inside the walk would latch it until a reload.
- `Snap.SetLink` does not check that `link.to` names a real window index. A bogus value is persisted and then inert.
- `hovered[window]` can stay set if a window is hidden while the cursor is over it. Bounded at three entries, self-corrects.
- A size edit in progress is cleared if the window is hidden mid-typing. Nothing was committed, so it is UX only.
- `Format.SelectValues` reads `showsValuePerSecondAsPrimary` as a field where Blizzard's method compares it to `true`. Blizzard only ever assigns it a real boolean, so the two agree on every path that exists today.
- The breakdown stays dim if it is pinned, the cursor leaves the whole meter, and then re-enters the breakdown directly from outside. Hooking `DamageMeterSourceWindowMixin:OnEnter` would close it.
