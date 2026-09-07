# DamageMeterTweaks - decisions taken while building it

Written 2026-09-07, at the end of the first build. These are the forks where the plan turned out to be wrong, or where two defensible answers existed and one had to be picked. Each says what was decided and why, so a later change does not undo them by accident.

## Engine facts that shaped the design

**Mixin methods are copied onto a frame when the frame is created.** `Mixin` does `object[k] = v`, so `hooksecurefunc` on a mixin table only reaches frames created after the hook. The `DamageMeter` frame and its session windows exist before `PLAYER_LOGIN`, so every hook that must reach them is installed per instance via `ns.HookInstance`. Getting this wrong yields an addon that loads cleanly and does nothing.

`ns.HookInstance` is keyed by **method name and handler together**. Both halves are load-bearing and each was learned from a bug: keying on the method alone would drop the second of two modules hooking the same method, and keying on the handler alone silently collapsed nine appearance hooks that share one handler into a single hook, so eight of them never installed and our own windows ignored every Edit Mode appearance change.

**For anything the engine invokes as a *script* rather than a method, use `HookScript`.** Whether an XML `method="X"` attribute resolves the function at load or at call time cannot be determined from Blizzard's source, and hooking the mixin method is only correct under late binding. This cost a whole feature once: window snapping wrote no links at all, because the drag hook never fired for any window restored at login.

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

Blizzard supports three meter windows. Phase 2 added our own beyond that, and the seam is `GetDamageMeterOwner()`, which returns a plain field a window never inspects: our windows are given a proxy owner that stores state in our saved variables. **The rule that keeps this safe is that a `DamageMeterMixin` owner method must never be called for a window index above three.** Those methods route into `SetSavedWindowData`, which asserts on the index, or `GetSessionWindowData`, which returns nil and is then indexed. `assertsafe` reports and continues rather than halting, so a violation is not a crash - it silently writes into Blizzard's own saved window list and persists across reloads. Reach a window's owner through `window:GetDamageMeterOwner()` and the rule holds by construction.

Blizzard pushes appearance settings only to its own three windows, so ours mirror them through the public getters on `DamageMeterMixin`. A setting Blizzard adds in a future patch will not reach our windows until it is mirrored too. That is the standing maintenance cost of having more windows than Blizzard supports.

## Minor issues left open on purpose

- `Format.Abbreviate` checks the unit threshold before rounding, so 999999 renders as `1000.00K` rather than `1.00M`. Narrow band, cosmetic.
- A full scroll-box rebuild during the hover delay can leave the pending timer holding a stale element snapshot. Needs a roster change within ~150ms of a hover; self-corrects.
- `Snap.PushSize` sets its guard without a `pcall`, so an error inside the walk would latch it until a reload.
- `Snap.SetLink` does not check that `link.to` names a real window index. A bogus number is persisted and then inert; a non-number is now refused by `Windows.Get`'s type guard rather than throwing during login.
- `Windows.Remove` cannot destroy a frame, and the index it frees is handed back to the next `Create`, which builds a second frame under the same global name while the first lingers hidden and unparented. The orphan is inert - nothing in the addon walks frame children and it is out of every table - but it leaks one frame per remove-then-add cycle.
- The settings panel does not scroll. Past roughly six or seven windows a row lands off the page; the soft-cap message says so. An off-page window can still be hidden from its own right-click menu, so nothing is stranded.
- Re-dragging a linked window replaces the whole link, discarding a gap and the match flags it was given in the panel. Defensible as "a drag re-states the link", but it is invisible and has to be retyped.
- `Windows.SortedIndices` sorts the raw keys of the saved windows table, so a hand-edited file carrying a string key would throw inside `table.sort`. Same class as the nil-index guard in `Windows.IsOurs`, which is now closed; this sibling is not, and is only reachable by editing saved variables by hand.
- `Windows.IsOurs` returning false for a non-number, and the reuse branch of `Windows.Create` reverting its shown flag when a build fails, have no regression tests. Both were found by review rather than by the suite.
- `hovered[window]` can stay set if a window is hidden while the cursor is over it. Bounded at three entries, self-corrects.
- A size edit in progress is cleared if the window is hidden mid-typing. Nothing was committed, so it is UX only.
- `Format.SelectValues` reads `showsValuePerSecondAsPrimary` as a field where Blizzard's method compares it to `true`. Blizzard only ever assigns it a real boolean, so the two agree on every path that exists today.
- The breakdown stays dim if it is pinned, the cursor leaves the whole meter, and then re-enters the breakdown directly from outside. Hooking `DamageMeterSourceWindowMixin:OnEnter` would close it.
