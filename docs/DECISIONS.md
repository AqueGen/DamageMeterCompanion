# DamageMeterCompanion - decisions taken while building it

Written 2026-09-07, at the end of the first build. These are the forks where the plan turned out to be wrong, or where two defensible answers existed and one had to be picked. Each says what was decided and why, so a later change does not undo them by accident.

## Engine facts that shaped the design

**Mixin methods are copied onto a frame when the frame is created.** `Mixin` does `object[k] = v`, so `hooksecurefunc` on a mixin table only reaches frames created after the hook. The `DamageMeter` frame and its session windows exist before `PLAYER_LOGIN`, so every hook that must reach them is installed per instance via `ns.HookInstance`. Getting this wrong yields an addon that loads cleanly and does nothing.

`ns.HookInstance` is keyed by **method name and handler together**. Both halves are load-bearing and each was learned from a bug: keying on the method alone would drop the second of two modules hooking the same method, and keying on the handler alone silently collapsed nine appearance hooks that share one handler into a single hook, so eight of them never installed and our own windows ignored every Edit Mode appearance change.

**For anything the engine invokes as a *script* rather than a method, use `HookScript`.** Whether an XML `method="X"` attribute resolves the function at load or at call time cannot be determined from Blizzard's source, and hooking the mixin method is only correct under late binding. This cost a whole feature once: window snapping wrote no links at all, because the drag hook never fired for any window restored at login.

**Combat session values are Secret to addon code, and the way through is to never look at them.** `C_DamageMeter` is documented `SecretWhenInCombat`, and `canaccesssecrets()` grants access only to untainted code. Blizzard's window re-fetches only on the meter's own events, which arrive in combat, so after a pull its data provider still holds the Secret objects fetched during it - `/dmc probe` out of combat reported every value Secret, and the first formatter, which did its own arithmetic, had never once applied. Comparing a Secret is refused, arithmetic is refused, and the rendered FontString cannot be read back either (`Text` aspect, `RequiresFontStringTextAccess`). The feature was removed on that evidence, then reinstated the same day after the user asked how Details manages: `AbbreviateNumbers`, `string.format` and `FontString:SetText` are all documented `SecretArguments = "AllowedWhenTainted"`. A Secret number goes into the client's own abbreviation routine, a Secret string comes out, and the bar accepts it - no addon code ever reads the amount. The breakpoints are Details' (`Details/functions/util.lua`), known to satisfy `RequiresRestrictedAbbreviationBreakpoints`. The only casualty is the percentage, which needs a division and so is shown only when the values are readable, i.e. out of combat.

**Any `hooksecurefunc` on a function Blizzard calls while rendering the list carries our taint into their Secret comparisons**, whatever the hook body does. Both `InitEntry` (Hover, ContextMenu) and `UpdateValue` (the first Format) produced `attempt to compare field 'sourceDisplayType' (a secret number value, while execution tainted by ...)` in combat, each confirmed in game by disabling one at a time. Nothing hooks the render path any more: Format paints and Entries attaches its handlers from one shared timer (`ns.OnSweep`), so our code is never on Blizzard's stack. Entries unregisters each bar's clicks so Blizzard's OnClick stays silent and a right-click can be ours, and hooks OnEnter, OnLeave and OnMouseDown once per frame - scripts Blizzard never sets on an entry.

**Setting a frame's size dispatches `OnSizeChanged` re-entrantly.** A re-entrancy guard held across a size push therefore swallows the nested event. `Snap` propagates down a chain by explicit recursion and keeps the guard only to stop a second walk starting on top of the first.

**`DamageMeterMixin:SetupSessionWindow` re-anchors every secondary window to UIParent on every call**, including when reusing a hidden frame. Any anchor this addon imposes has to be re-applied from a hook on it, which is why both `Snap` and `Presence` hook it.

## Product decisions

**Left-click pins, right-click opens the menu, and Blizzard's own click handler is switched off on the bars.** Blizzard shows the breakdown on either button and pins only with Shift; ours is the Details convention. The handlers are ours from tainted code, so whether opening the breakdown or switching type from them warns in combat is a question for the in-game checklist, not for the design.

**Hover never touches a pinned breakdown.** Details retargets on hover, but Details hovers into a tooltip and pins into a separate window - it has two surfaces. We have one, so retargeting would destroy the pin the user just made, including when the click lands inside the hover delay and the timer fires afterwards.

**Match width and match height live only in the settings panel.** They were in the right-click menu too, and having one control in two places was the thing the panel section below argues against - the menu is for what you change often, the panel for the state you set once. The menu keeps type, segment and window actions.

**The settings panel does not offer type, segment, or an attach control.** The right-click menu changes type and segment in fewer clicks than opening a settings page, and attaching is a drag gesture. A second way to do one thing is worse than one good way. What the panel is for is the state the menu cannot show at a glance: which windows exist, how big they are, what is attached to what.

**The panel does offer numeric size entry**, because that was the point of asking for it. Values are clamped to the window's resize bounds and the panel shows the clamped result rather than silently ignoring the request.

**Window locks are honoured when dragging and when resizing, but not when re-applying an anchor.** Refusing to re-apply an anchor a window already has would silently detach a locked window on every reload, which is worse than honouring the lock too literally.

**Quick type buttons were built and removed.** A strip of one-click type buttons above each window, with a configurable set - Details has them and the type menu does cost two clicks. Built, shipped, and rejected on sight: it looked bad. The window has no room for a strip that is not either eating a bar row or floating above the frame looking bolted on, and a feature whose whole value is convenience does not survive being ugly. Rebuilding it means solving the appearance first, not the behaviour.

**These were considered and left out of scope**, each because Blizzard already covers it or because it is analysis rather than control: per-window scale, auto-switch to current segment, reset window position, skins and colours, display bookmarks, report-to-chat, scroll bindings, and the update interval.

## Where the code deliberately differs from Blizzard's

**`Absorbs` appears in the type menu** although Blizzard's own category list omits it. The type and its name string both exist; leaving a reachable type out of a menu whose whole purpose is reaching types would be odd. If it turns out to render an empty window, drop it and note why.

**`ContextMenu.CATEGORIES` and `TYPE_NAMES` duplicate file-local Blizzard tables.** `VerifyTypeCoverage` runs at login against the live `Enum.DamageMeterType` and prints a warning naming any type a patch adds that we do not list. A headless test could only have compared our table against a copy of itself.

## Known limitations

Nothing here has been verified in a running game client - see `IN-GAME-CHECKLIST.md`. Only pure logic is unit-tested; frame-bound behaviour has no automated coverage.

Removing one of Blizzard's windows 2 and 3 hides it rather than destroying it. Their slots are part of its window data list for the life of the character, so the row stays in the panel as an empty slot. Saying that plainly is better than a permanently greyed button that never explains itself.

Blizzard supports three meter windows. Phase 2 added our own beyond that, and the seam is `GetDamageMeterOwner()`, which returns a plain field a window never inspects: our windows are given a proxy owner that stores state in our saved variables. **The rule that keeps this safe is that a `DamageMeterMixin` owner method must never be called for a window index above three.** Those methods route into `SetSavedWindowData`, which asserts on the index, or `GetSessionWindowData`, which returns nil and is then indexed. `assertsafe` reports and continues rather than halting, so a violation is not a crash - it silently writes into Blizzard's own saved window list and persists across reloads. Reach a window's owner through `window:GetDamageMeterOwner()` and the rule holds by construction.

Blizzard pushes appearance settings only to its own three windows, so ours mirror them through the public getters on `DamageMeterMixin`. A setting Blizzard adds in a future patch will not reach our windows until it is mirrored too. That is the standing maintenance cost of having more windows than Blizzard supports.

## The rename

The addon was built as DamageMeterTweaks and renamed to DamageMeterCompanion before its first release. The old name was already taken on CurseForge by another author's addon, and - the deciding argument - the two would have shared an AddOns folder name, so a player with both installed would have had one overwrite the other.

The old saved variables are still declared in the TOC and adopted once at login by `AdoptOldSavedVariables`, because a SavedVariable that is not declared is never loaded. Both declarations and that function come out once a release has shipped under the new name. `/dmt` survives as a second slash alias for the same reason.

## Minor issues left open on purpose

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
- The breakdown stays dim if it is pinned, the cursor leaves the whole meter, and then re-enters the breakdown directly from outside. Hooking `DamageMeterSourceWindowMixin:OnEnter` would close it.
