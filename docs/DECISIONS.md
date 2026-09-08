# DamageMeterCompanion - decisions taken while building it

Written 2026-09-07, at the end of the first build. These are the forks where the plan turned out to be wrong, or where two defensible answers existed and one had to be picked. Each says what was decided and why, so a later change does not undo them by accident.

## Engine facts that shaped the design

**Mixin methods are copied onto a frame when the frame is created.** `Mixin` does `object[k] = v`, so `hooksecurefunc` on a mixin table only reaches frames created after the hook. The `DamageMeter` frame and its session windows exist before `PLAYER_LOGIN`, so every hook that must reach them is installed per instance via `ns.HookInstance`. Getting this wrong yields an addon that loads cleanly and does nothing.

`ns.HookInstance` is keyed by **method name and handler together**. Both halves are load-bearing and each was learned from a bug: keying on the method alone would drop the second of two modules hooking the same method, and keying on the handler alone silently collapsed nine appearance hooks that share one handler into a single hook, so eight of them never installed and our own windows ignored every Edit Mode appearance change.

**For anything the engine invokes as a *script* rather than a method, use `HookScript`.** Whether an XML `method="X"` attribute resolves the function at load or at call time cannot be determined from Blizzard's source, and hooking the mixin method is only correct under late binding. This cost a whole feature once: window snapping wrote no links at all, because the drag hook never fired for any window restored at login.

**Combat session values are Secret to addon code, and the way through is to never look at them.** `C_DamageMeter` is documented `SecretWhenInCombat`, and `canaccesssecrets()` grants access only to untainted code. Blizzard's window re-fetches only on the meter's own events, which arrive in combat, so after a pull its data provider still holds the Secret objects fetched during it - `/dmc probe` out of combat reported every value Secret, and the first formatter, which did its own arithmetic, had never once applied. Comparing a Secret is refused, arithmetic is refused, and the rendered FontString cannot be read back either (`Text` aspect, `RequiresFontStringTextAccess`). The feature was removed on that evidence, then reinstated the same day after the user asked how Details manages: `AbbreviateNumbers`, `string.format` and `FontString:SetText` are all documented `SecretArguments = "AllowedWhenTainted"`. A Secret number goes into the client's own abbreviation routine, a Secret string comes out, and the bar accepts it - no addon code ever reads the amount. The breakpoints are Details' (`Details/functions/util.lua`), known to satisfy `RequiresRestrictedAbbreviationBreakpoints`. The only casualty is the percentage, which needs a division and so is shown only when the values are readable, i.e. out of combat.

**Any `hooksecurefunc` on a function Blizzard calls while rendering the list carries our taint into their Secret comparisons**, whatever the hook body does. Both `InitEntry` (Hover, ContextMenu) and `UpdateValue` (the first Format) produced `attempt to compare field 'sourceDisplayType' (a secret number value, while execution tainted by ...)` in combat, each confirmed in game by disabling one at a time. Nothing hooks the render path any more: Format paints from one shared timer (`ns.OnSweep` / `ns.OnFrame`), so our code is never on Blizzard's stack.

**Setting a frame's size dispatches `OnSizeChanged` re-entrantly.** A re-entrancy guard held across a size push therefore swallows the nested event. `Snap` propagates down a chain by explicit recursion and keeps the guard only to stop a second walk starting on top of the first.

**`DamageMeterMixin:SetupSessionWindow` re-anchors every secondary window to UIParent on every call**, including when reusing a hidden frame. Any anchor this addon imposes has to be re-applied from a hook on it, which is why both `Snap` and `Presence` hook it.

**The rule, written after a day of learning it one warning at a time.** Addon code may set C-side frame properties on Blizzard's meter frames (points, size, alpha, strata, click registration, script hooks on scripts Blizzard leaves unset) and may paint text through `AllowedWhenTainted` APIs. It may not cause any Blizzard Lua field on a meter frame to be written - not directly and not by calling a Blizzard method that does - because Blizzard's render path reads several of its own fields before rewriting them (`DamageMeterEntry.lua:46,54,103` - `iconAtlasElement`, `iconTexture`, `nameText`; `DamageMeterSessionWindow.lua:610,702` - `localPlayerIndex`, `needsSourceWindowRefresh`; `DamageMeterSourceWindow.lua:292` - `previousSessionWindowCenterX/Y`), and a single tainted write to one of those is permanent until `/reload`: the read taints the execution, the rewrite re-taints the field, and every combat refresh from then on compares Secret values inside our taint and logs a warning per row. Taint propagates by value, not by call: the stacks that proved this had no addon frame on them. The same rule is why Details, EnhanceQoL and EUI render their own frames from `C_DamageMeter` and never write into Blizzard's windows.

**Cut on the evening of 2026-09-07, each a permanent taint source under that rule:** hover-to-open (`ShowSourceWindow` from our stack poisons the source window and its spell-entry pool); the right-click menu (its type and segment entries end in `Refresh`, and what remained duplicated the gear menu); windows beyond Blizzard's three (built entirely from addon code, tainted by construction, unfixable); showing a hidden window from a keybind (`SetupSessionWindow` runs two refreshes inside our taint; the panel's Shown box was put back at the user's request and offers a reload right after, which clears the taint because Blizzard restores the window itself at login); any `Refresh()` of our own. The analysis behind the cut, with every line, is the session's `opus-taint-analysis.md`; the in-game evidence was four distinct warning stacks over one afternoon.

**Lock and size are kept, with a reload prompt, on the user's decision (2026-09-08).** Both go through Blizzard code that writes Lua state: `SetSessionWindowLocked` (`DamageMeter.lua:472-480`) writes `windowData.locked`, `isLocked` and re-runs `InitializeSettingsDropdown` (`DamageMeterSessionWindow.lua:442-467`), whose `SetupMenu` closure is then ours - opening the gear menu in combat hits the same `Menu.lua:999` Secret-rect error the type menu did. Any size we set fires the ScrollBox's `OnSizeChanged` (`ScrollBox.lua:119-129`), whose `Update` (`762-792`) writes the data range and, if more rows fit, acquires them through `AcquireInternal` (`ScrollBoxListView.lua:361-386`) and runs `InitEntry` inside our execution - the per-row warnings. Position is clean: nothing in Blizzard_DamageMeter reacts to a move, and the ScrollBox reacts only to size. A reload clears both, because Blizzard restores locks from saved data and sizes from its frame cache, so `ns.RequestReload` asks once per session after the first size change or show; the user chose no prompt for locks. Three changes make the reload actually clean: linked windows stay user-placed so the cache restores their size; `PushSize` sets a size only when it differs; and sizes are pushed only from a user gesture - a typed size, or the `OnSizeChanged` hook while Blizzard's `isResizing` flag (`DamageMeterSessionWindow.lua:536`) or Edit Mode is on. The login pass and the `SetupSessionWindow` hook re-apply anchors only: they run before the frame cache has restored sizes, so pushing there resized template-sized windows from our stack and, before commit `70fa60f`'s follow-up, tainted every session with a matched link from the start (seen as the reload popup on every login).

## Product decisions

**The panel does offer numeric size entry**, because that was the point of asking for it. Values are clamped to the window's resize bounds and the panel shows the clamped result rather than silently ignoring the request.

**Window locks are honoured when dragging and when resizing, but not when re-applying an anchor.** Refusing to re-apply an anchor a window already has would silently detach a locked window on every reload, which is worse than honouring the lock too literally.

**Quick type buttons were built and removed.** A strip of one-click type buttons above each window, with a configurable set - Details has them and the type menu does cost two clicks. Built, shipped, and rejected on sight: it looked bad. The window has no room for a strip that is not either eating a bar row or floating above the frame looking bolted on, and a feature whose whole value is convenience does not survive being ugly. Rebuilding it means solving the appearance first, not the behaviour.

**The settings panel does not offer type, segment or an attach control**: the header dropdowns switch type and segment untainted, and attaching is a drag gesture.

**Hover-to-open is gone for good.** Through Blizzard's breakdown it poisons that window's rows until reload (`DamageMeterEntry.lua:54` reads `iconTexture` before writing it), which the user saw as 86 warnings on their own click in the next fight. A breakdown of our own fed from `C_DamageMeter` (commit `7a46e33`) is the only clean form and is kept in history; the user chose to drop the feature. Windows beyond Blizzard's three were confirmed in game the same night: a fresh reload, no action, first fight - 24 warnings from the fourth window alone.

**A right-click on the bars that opens Blizzard's menu was tried and does not exist.** Their dropdowns open in `OnMouseDown` (`MenuTemplates.xml:46,77`); a secure action button can synthesise only a click, which runs `OnClick` and does nothing there, and opening the menu from our code builds it under our taint. The `Menu.ModifyMenu` additions to the header's type menu went the same way: an entry of ours is a tainted value in the description, and the menu layout (`Menu.lua:989-999`) then measures region rects that are Secret in combat under our taint - a hard error on opening the menu in a fight. The one surviving entry, settings in the gear menu, is added only out of combat.

**These were considered and left out of scope**, each because Blizzard already covers it or because it is analysis rather than control: per-window scale, auto-switch to current segment, reset window position, skins and colours, display bookmarks, report-to-chat, scroll bindings, and the update interval.

## Where the code deliberately differs from Blizzard's

## Known limitations

Nothing here has been verified in a running game client - see `IN-GAME-CHECKLIST.md`. Only pure logic is unit-tested; frame-bound behaviour has no automated coverage.

Hiding one of Blizzard's windows 2 and 3 is the only clean direction. Showing, locking and sizing run Blizzard's code inside our taint and are followed by a reload prompt.

## The rename

The addon was built as DamageMeterTweaks and renamed to DamageMeterCompanion before its first release. The old name was already taken on CurseForge by another author's addon, and - the deciding argument - the two would have shared an AddOns folder name, so a player with both installed would have had one overwrite the other.

The old saved variables are still declared in the TOC and adopted once at login by `AdoptOldSavedVariables`, because a SavedVariable that is not declared is never loaded. Both declarations and that function come out once a release has shipped under the new name. `/dmt` survives as a second slash alias for the same reason.

## Minor issues left open on purpose

- Three `hooksecurefunc` remain, all on the `DamageMeter` manager: `SetupSessionWindow` (Snap, Presence) and `OnWindowAlphaChanged` (Presence). They are post-hooks, so Blizzard's body - including the refresh SetupSessionWindow triggers - completes untainted before ours runs, and ours call only C-side setters.

- `Snap.PushSize` sets its guard without a `pcall`, so an error inside the walk would latch it until a reload.
- `Snap.SetLink` does not check that `link.to` names a real window index. A bogus number is persisted and then inert; a non-number is now refused by `Windows.Get`'s type guard rather than throwing during login.
- A size edit in progress is cleared if the window is hidden mid-typing. Nothing was committed, so it is UX only.
- The breakdown stays dim if it is pinned, the cursor leaves the whole meter, and then re-enters the breakdown directly from outside. Hooking `DamageMeterSourceWindowMixin:OnEnter` would close it.
