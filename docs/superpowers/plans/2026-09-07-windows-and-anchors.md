# DamageMeterTweaks phase 2 - windows and anchors Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make window placement work: fix the drag that never linked, show what a drag is about to attach to, lift the three-window ceiling, and let every window's size and the breakdown's side be set exactly.

**Architecture:** A new `Windows.lua` owns a registry every other module walks instead of counting to three, and a proxy owner object that lets us create real `DamageMeterSessionWindowTemplate` frames beyond Blizzard's limit — the seam is `GetDamageMeterOwner()`, which returns a plain field. `Snap.lua` keeps its link model but stops assuming three indices and hooks the drag script rather than the mixin method. A new `Breakdown.lua` post-hooks the spell breakdown's anchoring.

**Tech Stack:** Lua 5.1 (WoW client), no libraries, no Ace. Tests: busted 2.3.0 under WSL at `~/luaenv/bin/busted`.

**Spec:** `docs/superpowers/specs/2026-09-07-windows-and-anchors-design.md`

**Phase 1 spec, for context on what already exists:** `docs/superpowers/specs/2026-09-07-damage-meter-tweaks-design.md`, and `docs/DECISIONS.md` for the decisions behind it.

## Global Constraints

- Addon root: `g:\Games\World of Warcraft\_retail_\Interface\AddOns\DamageMeterTweaks`. All paths are relative to it.
- No external libraries. No Ace. No new dependencies of any kind.
- Never read a `C_DamageMeter` value without an `issecretvalue` guard, and never do arithmetic, comparison or string formatting on a value that guard has not cleared.
- **Blizzard's window 1 is Edit Mode's.** Never call `SetPoint`, `SetSize`, `Show` or `Hide` on it. Its size is changed only through `EditModeManagerFrame:OnSystemSettingChange`, wrapped so a refusal prints.
- **Never call a `DamageMeterMixin` owner method for a window index above 3.** Those methods route into `SetSavedWindowData`, which asserts on the index. Our windows go through the proxy owner instead.
- Mixin methods are copied onto a frame at creation, so `hooksecurefunc` on a mixin table only reaches frames created after the hook; frames that already exist need `ns.HookInstance`. For anything the engine invokes as a *script* rather than a method, use `HookScript`, which is unambiguous.
- All window sizes clamp to 200-600 wide by 120-400 tall. That is `ResizeBounds` on the session window template and the Edit Mode slider range for window 1 — one bound for every window.
- Every module file starts with `local addonName, ns = ...` and must be loadable headless via `loadfile("File.lua")("DamageMeterTweaks", ns)`. No WoW API calls at file scope. `Core.lua`'s single `CreateFrame` bootstrap is the one sanctioned exception.
- All file content in English, including comments.
- Test command, from the addon root:
  `MSYS_NO_PATHCONV=1 wsl bash -lc 'cd "/mnt/g/Games/World of Warcraft/_retail_/Interface/AddOns/DamageMeterTweaks" && ~/luaenv/bin/busted tests'`
  The `MSYS_NO_PATHCONV=1` prefix is required or Git Bash mangles the path. Phase 1 leaves 48 tests passing; every task must keep them passing.
- Syntax check: `~/luaenv/bin/luac -p <files>` under the same `wsl bash -lc` wrapper.
- Commits are local only. There is no remote; do not create one. No attribution or Co-Authored-By lines.
- **No subagent can run World of Warcraft.** In-game verification steps are listed in the report as pending, never performed and never claimed.

## File Structure

| File | Change | Responsibility |
| --- | --- | --- |
| `Windows.lua` | Create | Registry over all windows, proxy owner, creation and removal, appearance mirroring and overrides |
| `Breakdown.lua` | Create | Which side the spell breakdown opens on |
| `Core.lua` | Modify | `ns.ForEachSessionWindow` retired in favour of the registry; new saved-variable defaults |
| `Snap.lua` | Modify | Drag hook corrected, link gap, preview geometry, index assumptions removed |
| `Preview.lua` | Create | The two highlight bars drawn while a drag is about to snap |
| `Config.lua` | Modify | Variable-length window list with add, remove, gap and appearance overrides |
| `DamageMeterTweaks.toc` | Modify | Load `Windows.lua` early, `Preview.lua` and `Breakdown.lua` after `Snap.lua` |
| `tests/windows_spec.lua` | Create | Registry ordering, index allocation, appearance resolution |
| `tests/preview_spec.lua` | Create | Highlight bar geometry |
| `tests/snap_spec.lua` | Modify | Arbitrary index sets, gap offsets |

Load order in the TOC becomes: `Core.lua`, `Windows.lua`, `Format.lua`, `Hover.lua`, `ContextMenu.lua`, `Snap.lua`, `Preview.lua`, `Breakdown.lua`, `Presence.lua`, `Config.lua`. `Windows.lua` goes second because every module after it walks the registry.

---

### Task 1: Fix the drag that never linked

The smallest change in the plan and the one the user is waiting on. Phase 1 hooked `OnDragStop` as a mixin method; if the XML `method=` attribute binds at load time, that hook never fires for a window restored at login, no link is ever written, and windows only appear stuck because they were dropped adjacent.

**Files:**
- Modify: `Snap.lua`

**Interfaces:**
- Consumes: `ns.HookInstance`, `ns.ForEachSessionWindow` (both from phase 1's `Core.lua`).
- Produces: nothing new; `Snap.Enable`'s behaviour changes only.

- [ ] **Step 1: Replace the drag hook**

In `Snap.Enable`, delete the line

```lua
    hooksecurefunc(DamageMeterSessionWindowMixin, "OnDragStop", OnDragStop)
```

and inside the existing `ns.ForEachSessionWindow(function(window, index)` block, replace

```lua
        ns.HookInstance(window, "OnDragStop", OnDragStop)
```

with

```lua
        -- HookScript, not a method hook: the engine invokes the XML-declared
        -- OnDragStop script, and whether `method="OnDragStop"` resolves the
        -- function at load or at call time is not determinable from source. A
        -- script hook is correct under either.
        window:HookScript("OnDragStop", OnDragStop)
```

- [ ] **Step 2: Hook windows created later the same way**

In the `SetupSessionWindow` instance hook further down `Snap.Enable`, the block currently guards on `window.dmtSizeHooked` and installs only the size hook. Change that block to install both:

```lua
        local window = windowData.sessionWindow
        if window and not window.dmtSizeHooked then
            window.dmtSizeHooked = true

            window:HookScript("OnSizeChanged", function()
                Snap.PushSize(windowDataIndex)
            end)

            window:HookScript("OnDragStop", OnDragStop)
        end
```

`OnDragStop` is a local declared above in `Snap.Enable`, so it is in scope here.

- [ ] **Step 3: Run the checks**

```bash
MSYS_NO_PATHCONV=1 wsl bash -lc 'cd "/mnt/g/Games/World of Warcraft/_retail_/Interface/AddOns/DamageMeterTweaks" && ~/luaenv/bin/luac -p Snap.lua'
MSYS_NO_PATHCONV=1 wsl bash -lc 'cd "/mnt/g/Games/World of Warcraft/_retail_/Interface/AddOns/DamageMeterTweaks" && ~/luaenv/bin/busted tests'
```

Expected: `luac` silent, busted 48 successes / 0 failures. This task changes no pure logic, so no new tests.

- [ ] **Step 4: Commit**

```bash
git add Snap.lua
git commit -m "fix: hook the drag script so snapping actually writes a link"
```

**Pending user verification, to list in the report:** drag window 2 so its top edge nears window 1's bottom edge and release; then move window 1 in Edit Mode and confirm window 2 travels with it. That is the behaviour that was broken.

---

### Task 2: The window registry

Every module currently loops `for index = 1, 3`. That assumption has to go before anything can create a fourth window.

**Files:**
- Create: `Windows.lua`
- Create: `tests/windows_spec.lua`
- Modify: `DamageMeterTweaks.toc`, `Core.lua`, `Snap.lua`, `Presence.lua`, `Config.lua`

**Interfaces:**
- Consumes: `ns.RegisterModule`, `ns.Print`.
- Produces:
  - `ns.Windows.BLIZZARD_WINDOW_COUNT` = 3
  - `ns.Windows.SOFT_CAP` = 10
  - `ns.Windows.IsOurs(index) -> boolean` — true for an index above `BLIZZARD_WINDOW_COUNT`
  - `ns.Windows.NextFreeIndex(taken) -> number` — pure; `taken` is a set of indices in use, returns the lowest free index above `BLIZZARD_WINDOW_COUNT`
  - `ns.Windows.SortedIndices(set) -> array` — pure; ascending
  - `ns.Windows.Get(index) -> frame or nil`
  - `ns.Windows.ForEach(func)` — calls `func(window, index)` for every existing window, Blizzard's and ours, in ascending index order
  - `ns.Windows.Indices() -> array` — ascending indices of windows that exist

- [ ] **Step 1: Write the failing test**

`tests/windows_spec.lua`:

```lua
local ns = {}

ns.RegisterModule = function() end
ns.Print = function() end

assert(loadfile("Windows.lua"))("DamageMeterTweaks", ns)

local Windows = ns.Windows

describe("Windows.IsOurs", function()
    it("treats Blizzard's three as not ours", function()
        assert.is_false(Windows.IsOurs(1))
        assert.is_false(Windows.IsOurs(3))
    end)

    it("treats anything above three as ours", function()
        assert.is_true(Windows.IsOurs(4))
        assert.is_true(Windows.IsOurs(97))
    end)
end)

describe("Windows.NextFreeIndex", function()
    it("starts just above Blizzard's range", function()
        assert.are.equal(4, Windows.NextFreeIndex({}))
    end)

    it("skips indices already taken", function()
        assert.are.equal(6, Windows.NextFreeIndex({ [4] = true, [5] = true }))
    end)

    it("fills a hole left by a removed window", function()
        assert.are.equal(5, Windows.NextFreeIndex({ [4] = true, [6] = true }))
    end)

    it("ignores Blizzard's indices being present", function()
        assert.are.equal(4, Windows.NextFreeIndex({ [1] = true, [2] = true, [3] = true }))
    end)
end)

describe("Windows.SortedIndices", function()
    it("returns ascending indices", function()
        assert.are.same({ 1, 4, 7 }, Windows.SortedIndices({ [7] = true, [1] = true, [4] = true }))
    end)

    it("returns an empty list for an empty set", function()
        assert.are.same({}, Windows.SortedIndices({}))
    end)
end)
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
MSYS_NO_PATHCONV=1 wsl bash -lc 'cd "/mnt/g/Games/World of Warcraft/_retail_/Interface/AddOns/DamageMeterTweaks" && ~/luaenv/bin/busted tests'
```

Expected: `loadfile("Windows.lua")` returns nil, assertion fails. The 48 existing tests still pass.

- [ ] **Step 3: Write `Windows.lua` with the registry only**

The proxy owner and window creation arrive in Task 3; this task delivers the registry and switches every caller onto it.

```lua
local addonName, ns = ...

ns.Windows = {}
local Windows = ns.Windows

-- Blizzard's own MAX_DAMAGE_METER_SESSION_WINDOWS, which is file-local to
-- DamageMeter.lua. Windows above this index are created and owned by us.
Windows.BLIZZARD_WINDOW_COUNT = 3

-- Not a limit. Past this many windows we say once that each one is a scroll
-- box refreshed on every combat event, and let the player decide.
Windows.SOFT_CAP = 10

function Windows.IsOurs(index)
    return index > Windows.BLIZZARD_WINDOW_COUNT
end

function Windows.NextFreeIndex(taken)
    local index = Windows.BLIZZARD_WINDOW_COUNT + 1

    while taken[index] do
        index = index + 1
    end

    return index
end

function Windows.SortedIndices(set)
    local indices = {}

    for index in pairs(set) do
        table.insert(indices, index)
    end

    table.sort(indices)

    return indices
end

-- Frames we created, keyed by index. Blizzard's live in its own window data
-- list and are reached through the owner.
local ourWindows = {}

function Windows.Get(index)
    if Windows.IsOurs(index) then
        return ourWindows[index]
    end

    return DamageMeter:GetSessionWindow(index)
end

function Windows.Indices()
    local present = {}

    for index = 1, Windows.BLIZZARD_WINDOW_COUNT do
        if DamageMeter:GetSessionWindow(index) then
            present[index] = true
        end
    end

    for index in pairs(ourWindows) do
        present[index] = true
    end

    return Windows.SortedIndices(present)
end

function Windows.ForEach(func)
    for _, index in ipairs(Windows.Indices()) do
        local window = Windows.Get(index)
        if window then
            func(window, index)
        end
    end
end

ns.RegisterModule("Windows", Windows)
```

- [ ] **Step 4: Add `Windows.lua` to the TOC**

In `DamageMeterTweaks.toc`, insert `Windows.lua` immediately after `Core.lua`, so it reads:

```toc
Core.lua
Windows.lua
Format.lua
Hover.lua
ContextMenu.lua
Snap.lua
Presence.lua
Config.lua
```

- [ ] **Step 5: Make module enable order deterministic**

Phase 1's `Core.lua` enables modules with `for _, module in pairs(modules) do`. That was safe when no module's `Enable` depended on another's having run, and it stops being safe here: `Snap.Enable` walks the registry to install drag hooks, and those windows only exist once `Windows.Enable` has built them.

In `Core.lua`, change `ns.RegisterModule` to record order:

```lua
local modules = {}
local moduleOrder = {}

-- Enable order follows registration order, which follows the TOC. Windows.lua
-- loads second and so is enabled first, before anything walks the registry.
function ns.RegisterModule(name, module)
    if modules[name] then
        return
    end

    modules[name] = module
    table.insert(moduleOrder, module)
end
```

and in the bootstrap, replace the enable loop with:

```lua
    for _, module in ipairs(moduleOrder) do
        if module.Enable then
            module.Enable()
        end
    end
```

- [ ] **Step 6: Retire `ns.ForEachSessionWindow`**

Delete it from `Core.lua` (lines 57-65, the `for index = 1, 3` loop). Then replace every call site with `ns.Windows.ForEach`:

- `Core.lua`, inside `ns.ForEachEntryFrame`
- `Snap.lua`, in `CollectCandidates` and in `Snap.Enable`
- `Presence.lua`, in `Presence.ApplyAlphaToAll` and `Presence.ApplyStrata`
- `Config.lua`, in the `format` checkbox's `onChange` and the idle-alpha `onChange`

The signature is identical — `func(window, index)` — so each call site changes only the function being called. Grep for `ForEachSessionWindow` afterwards and confirm no hits remain.

- [ ] **Step 7: Generalise `Snap.ApplyOrder`**

In `Snap.lua`, `ApplyOrder` ends with a loop over `1, 3`. Replace it so it walks the links themselves:

```lua
    for _, index in ipairs(Windows.SortedIndices(links)) do
        Place(index)
    end
```

and add `local Windows = ns.Windows` near the top of `Snap.lua`, below the existing locals. `SortedIndices` takes any table keyed by index, and a link table is exactly that, so a chain of five orders correctly with no further change.

- [ ] **Step 8: Add a test for the wider ordering**

Append to the existing `describe("Snap.ApplyOrder", ...)` block in `tests/snap_spec.lua`:

```lua
    it("orders a chain of five targets-first", function()
        local links = {
            [7] = { to = 6 },
            [6] = { to = 5 },
            [5] = { to = 4 },
            [4] = { to = 1 },
        }

        assert.are.same({ 4, 5, 6, 7 }, Snap.ApplyOrder(links))
    end)

    it("orders two independent chains without dropping either", function()
        local links = { [5] = { to = 4 }, [7] = { to = 6 } }
        local order = Snap.ApplyOrder(links)

        assert.are.equal(4, #order)
    end)
```

`tests/snap_spec.lua` loads only `Snap.lua`, which now reads `ns.Windows`, so add to that spec's fixture, above the `loadfile` call:

```lua
-- Snap reads the registry for index ordering; the spec does not load Windows.lua.
ns.Windows = {
    SortedIndices = function(set)
        local indices = {}
        for index in pairs(set) do
            table.insert(indices, index)
        end
        table.sort(indices)
        return indices
    end,
}
```

- [ ] **Step 9: Run the tests to verify they pass**

Same command as Step 2. Expected: 48 existing plus 9 new from `windows_spec` and `snap_spec` — 57 successes / 0 failures.

- [ ] **Step 10: Syntax-check every changed file**

```bash
MSYS_NO_PATHCONV=1 wsl bash -lc 'cd "/mnt/g/Games/World of Warcraft/_retail_/Interface/AddOns/DamageMeterTweaks" && ~/luaenv/bin/luac -p Core.lua Windows.lua Snap.lua Presence.lua Config.lua'
```

- [ ] **Step 11: Commit**

```bash
git add Windows.lua tests/windows_spec.lua tests/snap_spec.lua DamageMeterTweaks.toc Core.lua Snap.lua Presence.lua Config.lua
git commit -m "feat: window registry replacing the hardcoded three"
```

**Pending user verification:** everything from phase 1 still behaves — hover, right-click menu, snapping, transparency — since every module now reaches windows through the registry.

---

### Task 3: The proxy owner and extra windows

**Files:**
- Modify: `Windows.lua`
- Modify: `Core.lua`
- Modify: `tests/windows_spec.lua`

**Interfaces:**
- Consumes: `ns.charDb`, `ns.Print`, `Windows.NextFreeIndex`, `Windows.Get`.
- Produces:
  - `ns.Windows.Create() -> index or nil`
  - `ns.Windows.Remove(index)`
  - `ns.Windows.ApplyAppearance(window, index)`
  - `ns.Windows.ResolveAppearance(mirrored, override) -> value` — pure
  - `ns.Windows.proxyOwner` — the table given to our windows as their damage meter owner

- [ ] **Step 1: Write the failing test**

Append to `tests/windows_spec.lua`:

```lua
describe("Windows.ResolveAppearance", function()
    it("uses the mirrored value when there is no override", function()
        assert.are.equal(25, Windows.ResolveAppearance(25, nil))
    end)

    it("lets an override win", function()
        assert.are.equal(14, Windows.ResolveAppearance(25, 14))
    end)

    it("treats a cleared override as no override", function()
        assert.are.equal(25, Windows.ResolveAppearance(25, false))
    end)
end)
```

- [ ] **Step 2: Run the tests to verify they fail**

Same command as before. Expected: `attempt to call field 'ResolveAppearance' (a nil value)`.

- [ ] **Step 3: Add the saved-variable defaults**

In `Core.lua`, extend `ns.charDefaults`:

```lua
ns.charDefaults = {
    links = {},
    windows = {},
}
```

`windows` is keyed by index, and each entry holds `damageMeterType`, `sessionType`, `sessionID`, `shown`, `locked`, `nonInteractive`, `minimized`, `width`, `height`, `left`, `bottom`, `barHeight`, `textSize`. Only our indices appear there; Blizzard keeps its own for 1 to 3.

- [ ] **Step 4: Write the appearance and proxy code**

Add to `Windows.lua`, above `ns.RegisterModule`:

```lua
local function GetSaved()
    return ns.charDb.windows
end

function Windows.ResolveAppearance(mirrored, override)
    if override then
        return override
    end

    return mirrored
end

-- Blizzard pushes these onto its own three windows whenever Edit Mode changes
-- one. Ours are not in its list, so we mirror them. A setting Blizzard adds in
-- a future patch will not reach our windows until it is added here too - that
-- is the standing cost of having more windows than Blizzard supports.
function Windows.ApplyAppearance(window, index)
    local saved = GetSaved()[index] or {}

    window:SetUseClassColor(DamageMeter:ShouldUseClassColor())
    window:SetBarSpacing(DamageMeter:GetBarSpacing())
    window:SetShowBarIcons(DamageMeter:ShouldShowBarIcons())
    window:SetBackgroundAlpha(DamageMeter:GetBackgroundAlpha())
    window:SetStyle(DamageMeter:GetStyle())
    window:SetNumberDisplayType(DamageMeter:GetNumberDisplayType())
    window:SetAlpha(DamageMeter:GetWindowAlpha())

    window:SetBarHeight(Windows.ResolveAppearance(DamageMeter:GetBarHeight(), saved.barHeight))
    window:SetTextScale(Windows.ResolveAppearance(DamageMeter:GetTextScale(), saved.textSize))
end

function Windows.ApplyAppearanceToOurs()
    for index, window in pairs(ourWindows) do
        Windows.ApplyAppearance(window, index)
    end
end

local function Store(index, key, value)
    local saved = GetSaved()

    saved[index] = saved[index] or {}
    saved[index][key] = value
end

-- A session window calls its owner for sixteen things and never checks what the
-- owner is (DamageMeterSessionWindow.lua:792). Giving ours this table instead
-- of DamageMeter keeps every call away from SetSavedWindowData, which asserts
-- on any index above three.
Windows.proxyOwner = {}
local proxy = Windows.proxyOwner

function proxy:SetSessionWindowDamageMeterType(window, damageMeterType)
    Store(window:GetSessionWindowIndex(), "damageMeterType", damageMeterType)
    window:SetDamageMeterType(damageMeterType)
end

function proxy:SetSessionWindowSessionID(window, sessionType, sessionID)
    local index = window:GetSessionWindowIndex()

    Store(index, "sessionType", sessionType)
    Store(index, "sessionID", sessionID)
    window:SetSession(sessionType, sessionID)
end

function proxy:SetSessionWindowLocked(window, locked)
    Store(window:GetSessionWindowIndex(), "locked", locked)
    window:SetLocked(locked)
end

function proxy:SetSessionWindowNonInteractive(window, nonInteractive)
    Store(window:GetSessionWindowIndex(), "nonInteractive", nonInteractive)
    window:SetNonInteractive(nonInteractive)
end

function proxy:SetSessionWindowMinimized(window, minimized)
    Store(window:GetSessionWindowIndex(), "minimized", minimized)
    window:SetMinimized(minimized)
end

function proxy:HideSessionWindow(window)
    Store(window:GetSessionWindowIndex(), "shown", false)
    window:Hide()
end

-- Unlike Blizzard's owner, every window we own can be hidden and moved: none of
-- them is the primary window Edit Mode controls.
function proxy:CanHideSessionWindow()
    return true
end

function proxy:CanMoveOrResizeSessionWindow()
    return true
end

function proxy:CanShowNewSecondarySessionWindow()
    return true
end

function proxy:ShowNewSecondarySessionWindow()
    Windows.Create()
end

function proxy:GetSessionType()
    return DamageMeter:GetSessionType()
end

function proxy:GetSessionID()
    return DamageMeter:GetSessionID()
end
```

- [ ] **Step 5: Write creation, restoration and removal**

Add below the proxy, still above `ns.RegisterModule`:

```lua
local function BuildWindow(index)
    local saved = GetSaved()[index] or {}

    local window = CreateFrame("FRAME", "DamageMeterTweaksWindow" .. index, DamageMeter, "DamageMeterSessionWindowTemplate")

    window:SetDamageMeterOwner(Windows.proxyOwner, index)
    window:SetDamageMeterType(saved.damageMeterType or Enum.DamageMeterType.DamageDone)
    window:SetSession(saved.sessionType or DamageMeter:GetSessionType(), saved.sessionID)
    window:SetMovable(true)
    window:SetResizable(true)

    -- Our own position rather than Blizzard's frame position cache, which is
    -- keyed on names it owns.
    window:SetUserPlaced(false)
    window:ClearAllPoints()
    if saved.left and saved.bottom then
        window:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", saved.left, saved.bottom)
    else
        local offset = (index - Windows.BLIZZARD_WINDOW_COUNT) * 40
        window:SetPoint("TOPLEFT", UIParent, "TOPLEFT", offset, -offset)
    end

    window:SetSize(saved.width or 400, saved.height or 200)

    ourWindows[index] = window

    Windows.ApplyAppearance(window, index)

    if saved.locked then
        window:SetLocked(true)
    end

    if saved.nonInteractive then
        window:SetNonInteractive(true)
    end

    if type(saved.minimized) == "boolean" then
        window:SetMinimized(saved.minimized)
    end

    window:SetShown(saved.shown ~= false)

    -- Position is ours to remember, so record it whenever the player moves the
    -- window. A linked window's anchor wins, and Snap clears the link's target
    -- before restoring a position, so the two never disagree.
    window:HookScript("OnDragStop", function()
        if not ns.charDb.links[index] then
            local left, bottom = window:GetRect()
            Store(index, "left", left)
            Store(index, "bottom", bottom)
        end
    end)

    window:HookScript("OnSizeChanged", function()
        Store(index, "width", window:GetWidth())
        Store(index, "height", window:GetHeight())
    end)

    return window
end

function Windows.Create()
    if not DamageMeterSessionWindowTemplate then
        -- The template is XML, so this is how a patch that renamed it surfaces.
        ns.Print("cannot create a window: the damage meter window template is missing")
        return nil
    end

    local taken = {}
    for index in pairs(GetSaved()) do
        taken[index] = true
    end
    for index in pairs(ourWindows) do
        taken[index] = true
    end

    local index = Windows.NextFreeIndex(taken)

    Store(index, "shown", true)
    BuildWindow(index)

    if #Windows.Indices() > Windows.SOFT_CAP and not Windows.warnedAboutCount then
        Windows.warnedAboutCount = true
        ns.Print("that is a lot of windows - each one is a scroll box refreshed on every combat event, so watch your frame rate")
    end

    return index
end

function Windows.Remove(index)
    if not Windows.IsOurs(index) then
        return
    end

    local window = ourWindows[index]

    if window then
        window:Hide()
        window:SetParent(nil)
        ourWindows[index] = nil
    end

    GetSaved()[index] = nil

    -- A link pointing at a window that no longer exists would anchor nothing.
    for otherIndex, link in pairs(ns.charDb.links) do
        if link.to == index then
            ns.Snap.ClearLink(otherIndex)
        end
    end

    ns.charDb.links[index] = nil
end

function Windows.Enable()
    for _, index in ipairs(Windows.SortedIndices(GetSaved())) do
        BuildWindow(index)
    end

    -- A link naming a window that no longer exists - removed on another
    -- character, or lost to hand-edited saved variables - would anchor nothing
    -- and confuse the panel. Drop those once, at login, before anything reads
    -- the link table.
    for index, link in pairs(ns.charDb.links) do
        if not Windows.Get(index) or not Windows.Get(link.to) then
            ns.charDb.links[index] = nil
        end
    end

    -- Edit Mode pushes appearance onto Blizzard's three; ours have to be told.
    local appearanceMethods = {
        "OnUseClassColorChanged", "OnBarHeightChanged", "OnTextScaleChanged",
        "OnWindowAlphaChanged", "OnShowBarIconsChanged", "OnBarSpacingChanged",
        "OnStyleChanged", "OnNumberDisplayTypeChanged", "OnBackgroundAlphaChanged",
    }

    for _, methodName in ipairs(appearanceMethods) do
        ns.HookInstance(DamageMeter, methodName, Windows.ApplyAppearanceToOurs)
    end
end
```

`CreateFrame`, `Enum` and `DamageMeter` are all inside functions, so the headless load is unaffected. `Windows.warnedAboutCount` is a plain field on the module table, set once per session.

- [ ] **Step 6: Run the tests to verify they pass**

Same command. Expected: 60 successes / 0 failures.

- [ ] **Step 7: Syntax-check**

```bash
MSYS_NO_PATHCONV=1 wsl bash -lc 'cd "/mnt/g/Games/World of Warcraft/_retail_/Interface/AddOns/DamageMeterTweaks" && ~/luaenv/bin/luac -p Windows.lua Core.lua'
```

- [ ] **Step 8: Commit**

```bash
git add Windows.lua Core.lua tests/windows_spec.lua
git commit -m "feat: extra meter windows through a proxy owner"
```

**Pending user verification:** with a fourth window created, its own settings dropdown (the gear) must offer type, segment, lock, uninteractable, minimize and hide, and each must work and survive a reload. Its appearance must match Blizzard's windows, and changing bar height in Edit Mode must move it too.

---

### Task 4: Snap preview geometry

Pure functions and their tests; Task 5 draws them.

**Files:**
- Create: `Preview.lua`
- Create: `tests/preview_spec.lua`
- Modify: `DamageMeterTweaks.toc`

**Interfaces:**
- Consumes: `ns.RegisterModule`.
- Produces: `ns.Preview.BarRects(rect, target, result, thickness) -> movingBar, targetBar`, each `{ left, bottom, width, height }`, where `rect` and `target` are the rectangles `Snap.FindSnap` works on and `result` is what it returned.

- [ ] **Step 1: Write the failing test**

`tests/preview_spec.lua`:

```lua
local ns = {}

ns.RegisterModule = function() end

assert(loadfile("Preview.lua"))("DamageMeterTweaks", ns)

local Preview = ns.Preview

local function Rect(index, left, top, width, height)
    return { index = index, left = left, right = left + width, top = top, bottom = top - height }
end

describe("Preview.BarRects", function()
    it("draws horizontal bars across the shared width when snapping below", function()
        local moving = Rect(2, 100, 296, 400, 200)
        local target = Rect(1, 100, 500, 400, 200)
        local result = { index = 1, point = "TOPLEFT", relPoint = "BOTTOMLEFT", axis = "vertical" }

        local movingBar, targetBar = Preview.BarRects(moving, target, result, 3)

        assert.are.equal(100, movingBar.left)
        assert.are.equal(400, movingBar.width)
        assert.are.equal(3, movingBar.height)
        assert.are.equal(296, movingBar.bottom + movingBar.height)

        assert.are.equal(100, targetBar.left)
        assert.are.equal(400, targetBar.width)
        assert.are.equal(300, targetBar.bottom)
    end)

    it("draws vertical bars across the shared height when snapping to the right", function()
        local moving = Rect(2, 506, 500, 400, 200)
        local target = Rect(1, 100, 500, 400, 200)
        local result = { index = 1, point = "TOPLEFT", relPoint = "TOPRIGHT", axis = "horizontal" }

        local movingBar, targetBar = Preview.BarRects(moving, target, result, 3)

        assert.are.equal(3, movingBar.width)
        assert.are.equal(200, movingBar.height)
        assert.are.equal(506, movingBar.left)

        assert.are.equal(3, targetBar.width)
        assert.are.equal(200, targetBar.height)
        assert.are.equal(497, targetBar.left)
    end)

    it("spans only the overlapping part when the windows are different sizes", function()
        local moving = Rect(2, 300, 296, 400, 200)
        local target = Rect(1, 100, 500, 400, 200)
        local result = { index = 1, point = "TOPLEFT", relPoint = "BOTTOMLEFT", axis = "vertical" }

        local movingBar = Preview.BarRects(moving, target, result, 3)

        assert.are.equal(300, movingBar.left)
        assert.are.equal(200, movingBar.width)
    end)
end)
```

Working the third fixture by hand: moving spans 300 to 700, target spans 100 to 500, so the overlap is 300 to 500 — 200 wide, starting at 300.

- [ ] **Step 2: Run the tests to verify they fail**

Expected: `loadfile("Preview.lua")` returns nil.

- [ ] **Step 3: Write `Preview.lua`'s geometry**

```lua
local addonName, ns = ...

ns.Preview = {}
local Preview = ns.Preview

-- Two bars, one on each window's edge, spanning only the part of those edges
-- that actually meet. Answering "this edge, this side" is the whole point -
-- a trail between the windows' centres, which is how Details shows the same
-- thing, says only that something is near.
function Preview.BarRects(rect, target, result, thickness)
    if result.axis == "vertical" then
        local left = math.max(rect.left, target.left)
        local right = math.min(rect.right, target.right)
        local width = right - left

        local movingEdge = (result.point == "TOPLEFT") and rect.top or rect.bottom
        local targetEdge = (result.relPoint == "BOTTOMLEFT") and target.bottom or target.top

        return
            { left = left, bottom = movingEdge - thickness, width = width, height = thickness },
            { left = left, bottom = targetEdge, width = width, height = thickness }
    end

    local bottom = math.max(rect.bottom, target.bottom)
    local top = math.min(rect.top, target.top)
    local height = top - bottom

    local movingEdge = (result.point == "TOPLEFT") and rect.left or rect.right
    local targetEdge = (result.relPoint == "TOPRIGHT") and target.right or target.left

    return
        { left = movingEdge, bottom = bottom, width = thickness, height = height },
        { left = targetEdge - thickness, bottom = bottom, width = thickness, height = height }
end

ns.RegisterModule("Preview", Preview)
```

- [ ] **Step 4: Add `Preview.lua` to the TOC**

Insert it after `Snap.lua`.

- [ ] **Step 5: Run the tests to verify they pass**

Expected: 63 successes / 0 failures.

- [ ] **Step 6: Commit**

```bash
git add Preview.lua tests/preview_spec.lua DamageMeterTweaks.toc
git commit -m "feat: snap preview geometry"
```

---

### Task 5: Draw the snap preview

**Files:**
- Modify: `Preview.lua`, `Snap.lua`

**Interfaces:**
- Consumes: `Preview.BarRects`, `Snap.FindSnap`, `ns.db.snap`, `ns.db.snapThreshold`.
- Produces: `ns.Preview.Show(rect, target, result)`, `ns.Preview.Hide()`, `ns.Preview.Enable()`.

- [ ] **Step 1: Add the drawing half to `Preview.lua`**

Above `ns.RegisterModule`:

```lua
local THICKNESS = 3
local COLOR = { r = 0.2, g = 1, b = 0.4, a = 0.9 }

local overlay

local function GetOverlay()
    if overlay then
        return overlay
    end

    -- Our own frame, so nothing about Blizzard's windows is touched and the
    -- whole feature disappears with one Hide.
    overlay = CreateFrame("Frame", nil, UIParent)
    overlay:SetFrameStrata("TOOLTIP")
    overlay:SetAllPoints(UIParent)
    overlay:Hide()

    for _, key in ipairs({ "movingBar", "targetBar" }) do
        local texture = overlay:CreateTexture(nil, "OVERLAY")
        texture:SetColorTexture(COLOR.r, COLOR.g, COLOR.b, COLOR.a)
        overlay[key] = texture
    end

    return overlay
end

local function PlaceBar(texture, bar)
    texture:ClearAllPoints()
    texture:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", bar.left, bar.bottom)
    texture:SetSize(math.max(bar.width, 1), math.max(bar.height, 1))
    texture:Show()
end

function Preview.Show(rect, target, result)
    local frame = GetOverlay()
    local movingBar, targetBar = Preview.BarRects(rect, target, result, THICKNESS)

    PlaceBar(frame.movingBar, movingBar)
    PlaceBar(frame.targetBar, targetBar)
    frame:Show()
end

function Preview.Hide()
    if overlay then
        overlay:Hide()
    end
end
```

- [ ] **Step 2: Run the preview while a window is being dragged**

In `Snap.lua`, inside `Snap.Enable`, add a drag-start hook next to the drag-stop one. In the `ns.Windows.ForEach` block that installs `OnDragStop`, add:

```lua
        window:HookScript("OnDragStart", function()
            if not ns.db.snap or not window:CanMoveOrResize() then
                return
            end

            window:SetScript("OnUpdate", function()
                local candidate = Snap.FindSnap(RectOf(window, index), CollectCandidates(index), ns.db.snapThreshold)

                if candidate then
                    ns.Preview.Show(RectOf(window, index), RectOf(ns.Windows.Get(candidate.index), candidate.index), candidate)
                else
                    ns.Preview.Hide()
                end
            end)
        end)
```

and at the top of the existing `OnDragStop` local, before anything else:

```lua
        window:SetScript("OnUpdate", nil)
        ns.Preview.Hide()
```

`OnDragStop` is declared as `local function OnDragStop(window)` and does not have `index` in scope, so derive it there with `local index = window:GetSessionWindowIndex()` — it already does this a line later; move that line to the top and reuse it.

Blizzard's session windows use `OnUpdate` for their own mouse-over tracking through `SetOnUpdateReason`, so setting our own script would fight it. Check `DamageMeterSessionWindow.lua` before writing this: if the window's `OnUpdate` is already occupied, drive the preview from the overlay frame's own `OnUpdate` instead, started on drag and stopped on drop, and say in your report which one you used and why.

Preview deliberately has no `Enable`: `Snap` drives `Show` and `Hide` from the drag scripts, and the overlay is built lazily on first use. `Core.lua`'s bootstrap calls `module.Enable` only when it exists, so a module without one is skipped.

- [ ] **Step 3: Run the checks**

```bash
MSYS_NO_PATHCONV=1 wsl bash -lc 'cd "/mnt/g/Games/World of Warcraft/_retail_/Interface/AddOns/DamageMeterTweaks" && ~/luaenv/bin/luac -p Preview.lua Snap.lua'
MSYS_NO_PATHCONV=1 wsl bash -lc 'cd "/mnt/g/Games/World of Warcraft/_retail_/Interface/AddOns/DamageMeterTweaks" && ~/luaenv/bin/busted tests'
```

Expected: `luac` silent, 63 successes / 0 failures.

- [ ] **Step 4: Commit**

```bash
git add Preview.lua Snap.lua
git commit -m "feat: show which edge a drag is about to snap to"
```

**Pending user verification:** dragging a window near another shows a green bar on both edges that will meet, and nothing when out of range; the bars vanish on release; turning snapping off in the panel stops them appearing at all.

---

### Task 6: A gap between linked windows

**Files:**
- Modify: `Snap.lua`, `tests/snap_spec.lua`

**Interfaces:**
- Consumes: the existing link shape.
- Produces: `Snap.OffsetForGap(point, relPoint, gap) -> x, y`; links gain `gap`, and `ApplyLink` uses it.

- [ ] **Step 1: Write the failing test**

Add to `tests/snap_spec.lua`:

```lua
describe("Snap.OffsetForGap", function()
    it("pushes a window below its target further down", function()
        local x, y = Snap.OffsetForGap("TOPLEFT", "BOTTOMLEFT", 6)

        assert.are.equal(0, x)
        assert.are.equal(-6, y)
    end)

    it("pushes a window above its target further up", function()
        local x, y = Snap.OffsetForGap("BOTTOMLEFT", "TOPLEFT", 6)

        assert.are.equal(0, x)
        assert.are.equal(6, y)
    end)

    it("pushes a window to the right of its target further right", function()
        local x, y = Snap.OffsetForGap("TOPLEFT", "TOPRIGHT", 6)

        assert.are.equal(6, x)
        assert.are.equal(0, y)
    end)

    it("pushes a window to the left of its target further left", function()
        local x, y = Snap.OffsetForGap("TOPRIGHT", "TOPLEFT", 6)

        assert.are.equal(-6, x)
        assert.are.equal(0, y)
    end)

    it("is flush with no gap", function()
        local x, y = Snap.OffsetForGap("TOPLEFT", "BOTTOMLEFT", 0)

        assert.are.equal(0, x)
        assert.are.equal(0, y)
    end)
end)
```

- [ ] **Step 2: Run the tests to verify they fail**

Expected: `attempt to call field 'OffsetForGap' (a nil value)`.

- [ ] **Step 3: Implement it**

In `Snap.lua`, above `Snap.ApplyLink`:

```lua
-- The gap always separates the two windows, so its sign follows from which
-- edges were joined rather than being the caller's problem.
local GAP_DIRECTION = {
    ["TOPLEFT|BOTTOMLEFT"] = { 0, -1 },
    ["BOTTOMLEFT|TOPLEFT"] = { 0, 1 },
    ["TOPLEFT|TOPRIGHT"] = { 1, 0 },
    ["TOPRIGHT|TOPLEFT"] = { -1, 0 },
}

function Snap.OffsetForGap(point, relPoint, gap)
    local direction = GAP_DIRECTION[point .. "|" .. relPoint]

    if not direction or not gap then
        return 0, 0
    end

    return direction[1] * gap, direction[2] * gap
end
```

and in `Snap.ApplyLink`, replace

```lua
    window:SetPoint(link.point, target, link.relPoint, 0, 0)
```

with

```lua
    local x, y = Snap.OffsetForGap(link.point, link.relPoint, link.gap)
    window:SetPoint(link.point, target, link.relPoint, x, y)
```

- [ ] **Step 4: Run the tests to verify they pass**

Expected: 68 successes / 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Snap.lua tests/snap_spec.lua
git commit -m "feat: a settable gap between linked windows"
```

---

### Task 7: Pixel-precise sizes for every window

**Files:**
- Modify: `Config.lua`, `Windows.lua`

**Interfaces:**
- Consumes: `Snap.Clamp`, `Snap.MIN_WIDTH` and friends, `ns.Windows.Get`.
- Produces: `ns.Windows.SetSize(index, width, height) -> boolean` — routes window 1 through Edit Mode and everything else through `SetSize`.

- [ ] **Step 1: Write the sizing helper**

In `Windows.lua`, above `ns.RegisterModule`:

```lua
-- Window 1's size is an Edit Mode setting, written by Blizzard's own resize
-- handle with exactly this call (EditModeSystemTemplates.lua:3438). Our stack
-- is tainted, so a refusal is reported rather than allowed to error.
local function SetPrimarySize(width, height)
    local ok, err = pcall(function()
        EditModeManagerFrame:OnSystemSettingChange(DamageMeter, Enum.EditModeDamageMeterSetting.FrameWidth, width)
        EditModeManagerFrame:OnSystemSettingChange(DamageMeter, Enum.EditModeDamageMeterSetting.FrameHeight, height)
    end)

    if not ok then
        ns.Print("Edit Mode would not accept that size right now: " .. tostring(err))
    end

    return ok
end

function Windows.SetSize(index, width, height)
    local window = Windows.Get(index)

    if not window then
        return false
    end

    width = ns.Snap.Clamp(width, ns.Snap.MIN_WIDTH, ns.Snap.MAX_WIDTH)
    height = ns.Snap.Clamp(height, ns.Snap.MIN_HEIGHT, ns.Snap.MAX_HEIGHT)

    if index == 1 then
        return SetPrimarySize(width, height)
    end

    if not window:CanMoveOrResize() then
        return false
    end

    window:SetSize(width, height)

    return true
end
```

- [ ] **Step 2: Route the panel's size boxes through it**

In `Config.lua`, `CreateSizeBox`'s `OnEnterPressed` currently calls `window:SetWidth` / `window:SetHeight` directly. Replace the body of the `if window and value and window:CanMoveOrResize() then` block with a call that keeps the other dimension as it is:

```lua
        local window = ns.Windows.Get(index)
        local value = tonumber(self:GetText())

        if window and value then
            local width = (dimension == "width") and value or window:GetWidth()
            local height = (dimension == "height") and value or window:GetHeight()

            ns.Windows.SetSize(index, width, height)
        end

        self:ClearFocus()
        RefreshWindowPanel()
```

The `CanMoveOrResize` check moves into `Windows.SetSize`, which is also where the primary window's Edit Mode path lives — so the panel no longer needs to know the difference.

- [ ] **Step 3: Show the boxes for window 1 too**

In `RefreshWindowPanel`, the size boxes are hidden for the primary window and a note says Edit Mode owns it. Change that: show the boxes for every window, and change window 1's note to say its size is stored in the Edit Mode layout. The `resizable` computation becomes:

```lua
        local resizable = shown and (index == 1 or window:CanMoveOrResize())
```

and the `SetShown(not isPrimary)` calls on both boxes become `SetShown(true)`.

- [ ] **Step 4: Run the checks**

```bash
MSYS_NO_PATHCONV=1 wsl bash -lc 'cd "/mnt/g/Games/World of Warcraft/_retail_/Interface/AddOns/DamageMeterTweaks" && ~/luaenv/bin/luac -p Config.lua Windows.lua'
MSYS_NO_PATHCONV=1 wsl bash -lc 'cd "/mnt/g/Games/World of Warcraft/_retail_/Interface/AddOns/DamageMeterTweaks" && ~/luaenv/bin/busted tests'
```

Expected: 68 successes / 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Config.lua Windows.lua
git commit -m "feat: pixel-precise sizes for every window including the primary"
```

**Pending user verification:** typing a width for window 1 resizes it and the value survives a reload; an out-of-range value comes back clamped; a locked window refuses; doing it in combat either works or prints, never errors.

---

### Task 8: Which side the spell breakdown opens on

**Files:**
- Create: `Breakdown.lua`
- Modify: `DamageMeterTweaks.toc`, `Core.lua`, `Config.lua`

**Interfaces:**
- Consumes: `ns.db.breakdownSide`, `ns.Windows.ForEach`, `ns.HookInstance`.
- Produces: `ns.Breakdown.SIDES` — array of `"AUTO"`, `"LEFT"`, `"RIGHT"`, `"ABOVE"`, `"BELOW"`; `ns.Breakdown.Enable()`.

- [ ] **Step 1: Add the setting default**

In `Core.lua`, add to `ns.defaults`:

```lua
    breakdownSide = "AUTO",
```

- [ ] **Step 2: Write `Breakdown.lua`**

```lua
local addonName, ns = ...

ns.Breakdown = {}
local Breakdown = ns.Breakdown

Breakdown.SIDES = { "AUTO", "LEFT", "RIGHT", "ABOVE", "BELOW" }

-- Blizzard picks left or right from which half of the screen the window sits
-- in (DamageMeterSourceWindow.lua:280-329). Post-hooking lets Auto keep that
-- behaviour untouched while a chosen side overrides it.
local function Reanchor(sourceWindow, sessionWindow)
    local side = ns.db.breakdownSide

    if side == "AUTO" then
        return
    end

    sourceWindow:ClearAllPoints()

    if side == "LEFT" then
        sourceWindow:SetPoint("TOPRIGHT", sessionWindow, "TOPLEFT")
        sourceWindow:SetPoint("BOTTOMRIGHT", sessionWindow, "BOTTOMLEFT")
    elseif side == "RIGHT" then
        sourceWindow:SetPoint("TOPLEFT", sessionWindow, "TOPRIGHT")
        sourceWindow:SetPoint("BOTTOMLEFT", sessionWindow, "BOTTOMRIGHT")
    elseif side == "ABOVE" then
        sourceWindow:SetPoint("BOTTOMLEFT", sessionWindow, "TOPLEFT")
        sourceWindow:SetPoint("BOTTOMRIGHT", sessionWindow, "TOPRIGHT")
    else
        sourceWindow:SetPoint("TOPLEFT", sessionWindow, "BOTTOMLEFT")
        sourceWindow:SetPoint("TOPRIGHT", sessionWindow, "BOTTOMRIGHT")
    end
end

function Breakdown.Enable()
    hooksecurefunc(DamageMeterSourceWindowMixin, "AnchorToSessionWindow", Reanchor)

    ns.Windows.ForEach(function(window)
        ns.HookInstance(window:GetSourceWindow(), "AnchorToSessionWindow", Reanchor)
    end)
end

ns.RegisterModule("Breakdown", Breakdown)
```

Above and below anchor two corners each, so the breakdown takes the window's width; left and right take its height, matching Blizzard's own arrangement. The resize button stays where Blizzard put it: its corner and texture flip only knows left from right, and inventing a vertical variant would mean redrawing textures we do not own.

- [ ] **Step 3: Add it to the TOC**

Insert `Breakdown.lua` after `Preview.lua`.

- [ ] **Step 4: Add the dropdown to the panel**

In `Config.lua`'s `BuildBehaviourOptions`, alongside the strata dropdown:

```lua
    local breakdownSetting = Settings.RegisterProxySetting(category, "DMT_breakdownSide",
        Settings.VarType.String, "Breakdown side", ns.defaults.breakdownSide,
        function() return ns.db.breakdownSide end,
        function(value) ns.db.breakdownSide = value end)

    Settings.CreateDropdown(category, breakdownSetting, function()
        local container = Settings.CreateControlTextContainer()
        for _, side in ipairs(ns.Breakdown.SIDES) do
            container:Add(side, side)
        end
        return container:GetData()
    end, "Which side of the meter the spell breakdown opens on. Auto keeps Blizzard's choice, which is whichever side of the screen has more room.")
```

- [ ] **Step 5: Run the checks**

```bash
MSYS_NO_PATHCONV=1 wsl bash -lc 'cd "/mnt/g/Games/World of Warcraft/_retail_/Interface/AddOns/DamageMeterTweaks" && ~/luaenv/bin/luac -p Breakdown.lua Config.lua Core.lua'
MSYS_NO_PATHCONV=1 wsl bash -lc 'cd "/mnt/g/Games/World of Warcraft/_retail_/Interface/AddOns/DamageMeterTweaks" && ~/luaenv/bin/busted tests'
```

Expected: 68 successes / 0 failures.

- [ ] **Step 6: Commit**

```bash
git add Breakdown.lua DamageMeterTweaks.toc Core.lua Config.lua
git commit -m "feat: choose which side the spell breakdown opens on"
```

**Pending user verification:** each of the five settings puts the breakdown where it says, including on a window near a screen edge; Auto still behaves as before.

---

### Task 9: The window list becomes a list

**Files:**
- Modify: `Config.lua`

**Interfaces:**
- Consumes: `ns.Windows.Indices`, `ns.Windows.Get`, `ns.Windows.IsOurs`, `ns.Windows.Create`, `ns.Windows.Remove`, `ns.Windows.SetSize`, `ns.Snap.ClearLink`, `ns.charDb.windows`, `ns.charDb.links`.
- Produces: nothing other modules consume.

- [ ] **Step 1: Build rows on demand instead of three at load**

`Config.BuildWindowPanel` currently creates exactly three rows in a `for index = 1, 3` loop and `RefreshWindowPanel` walks the same range. Replace both with a row pool keyed by window index:

```lua
    windowPanel.rows = {}

    local function AcquireRow(index, position)
        local row = windowPanel.rows[index]

        if not row then
            row = CreateRow(windowPanel, index)
            windowPanel.rows[index] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", windowPanel, "TOPLEFT", 20, -20 - (position - 1) * 70)
        row:Show()

        return row
    end
```

where `CreateRow(parent, index)` is the existing per-row construction lifted out of the loop verbatim, taking the index it closes over as a parameter. `RefreshWindowPanel` then walks `ns.Windows.Indices()`, acquires a row per index in order, and hides any row whose index is no longer present:

```lua
    local present = {}

    for position, index in ipairs(ns.Windows.Indices()) do
        present[index] = true
        RefreshRow(AcquireRow(index, position), index)
    end

    for index, row in pairs(windowPanel.rows) do
        if not present[index] then
            row:Hide()
        end
    end
```

`RefreshRow(row, index)` is the existing per-row refresh body, likewise lifted out and taking its index.

- [ ] **Step 2: Add the Add window button**

Below the rows:

```lua
    windowPanel.AddWindow = CreateFrame("Button", nil, windowPanel, "UIPanelButtonTemplate")
    windowPanel.AddWindow:SetSize(120, 22)
    windowPanel.AddWindow:SetPoint("BOTTOMLEFT", windowPanel, "BOTTOMLEFT", 20, 20)
    windowPanel.AddWindow:SetText("Add window")
    windowPanel.AddWindow:SetScript("OnClick", function()
        ns.Windows.Create()
        RefreshWindowPanel()
    end)
```

- [ ] **Step 3: Add the per-row Remove button**

In `CreateRow`, next to Detach:

```lua
    row.Remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.Remove:SetSize(80, 22)
    row.Remove:SetPoint("LEFT", row.Detach, "RIGHT", 8, 0)
    row.Remove:SetText("Remove")
    row.Remove:SetScript("OnClick", function()
        ns.Windows.Remove(index)
        RefreshWindowPanel()
    end)
```

and in `RefreshRow`, `row.Remove:SetEnabled(ns.Windows.IsOurs(index))` — Blizzard's three cannot be removed.

- [ ] **Step 4: Add the gap field**

In `CreateRow`, an edit box beside the link label, built the same way `CreateSizeBox` builds its boxes:

```lua
    row.Gap = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    row.Gap:SetAutoFocus(false)
    row.Gap:SetNumeric(true)
    row.Gap:SetMaxLetters(3)
    row.Gap:SetSize(36, 20)
    row.Gap:SetPoint("LEFT", row.Link, "RIGHT", 8, 0)
    row.Gap:SetScript("OnEnterPressed", function(self)
        local link = ns.charDb.links[index]
        local value = tonumber(self:GetText())

        if link and value then
            link.gap = value
            ns.Snap.ApplyLink(index)
        end

        self:ClearFocus()
        RefreshWindowPanel()
    end)
```

In `RefreshRow`: enable it only when a link exists, and set its text from `link.gap or 0` unless it has focus.

- [ ] **Step 5: Add the appearance override fields**

Two more edit boxes per row, bar height and text size, writing into `ns.charDb.windows[index]` and re-applying:

```lua
    local function CreateOverrideBox(row, index, key)
        local box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        box:SetAutoFocus(false)
        box:SetNumeric(true)
        box:SetMaxLetters(3)
        box:SetSize(36, 20)
        box:SetScript("OnEnterPressed", function(self)
            local saved = ns.charDb.windows[index]

            if saved then
                -- An empty box means follow Edit Mode again.
                saved[key] = tonumber(self:GetText())
                ns.Windows.ApplyAppearance(ns.Windows.Get(index), index)
            end

            self:ClearFocus()
            RefreshWindowPanel()
        end)

        return box
    end
```

Enabled only for our windows — Blizzard's three take their appearance from Edit Mode and the panel says so in their row's note.

- [ ] **Step 6: Run the checks**

```bash
MSYS_NO_PATHCONV=1 wsl bash -lc 'cd "/mnt/g/Games/World of Warcraft/_retail_/Interface/AddOns/DamageMeterTweaks" && ~/luaenv/bin/luac -p Config.lua'
MSYS_NO_PATHCONV=1 wsl bash -lc 'cd "/mnt/g/Games/World of Warcraft/_retail_/Interface/AddOns/DamageMeterTweaks" && ~/luaenv/bin/busted tests'
```

Expected: 68 successes / 0 failures.

- [ ] **Step 7: Commit**

```bash
git add Config.lua
git commit -m "feat: variable-length window list with add, remove, gap and overrides"
```

**Pending user verification:** add three windows, chain them, set a gap, give one a smaller bar height, reload and confirm all of it survived; remove a window in the middle of a chain and confirm the one that pointed at it comes free rather than breaking.

---

## Notes for the executor

- Blizzard's damage meter source is at `G:/Games/wow-ui-source-live/Interface/AddOns/Blizzard_DamageMeter/`, and Edit Mode at `.../Blizzard_EditMode/`. Read them rather than guessing; every line number cited in this plan was checked against them.
- `docs/DECISIONS.md` records why phase 1 is shaped the way it is. If a change here seems to contradict one of those decisions, say so rather than quietly reversing it.
- The one place this plan asks you to make a judgement call is Task 5, Step 2: whether the session window's own `OnUpdate` is free to use. Check the source, pick, and report which.
