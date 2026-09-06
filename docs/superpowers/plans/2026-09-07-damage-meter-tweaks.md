# DamageMeterTweaks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add hover details, a right-click menu, window snapping with size matching, readable numbers, idle transparency, strata control and key bindings on top of Blizzard's built-in Damage Meter, without touching any of its analysis.

**Architecture:** A standalone WoW addon that installs post-hooks on Blizzard's `Blizzard_DamageMeter` mixins at `PLAYER_LOGIN`. Every module is a table on the shared addon namespace with pure helper functions plus one `Enable()` that installs its hooks. Pure helpers - number formatting, snap geometry, link bookkeeping - carry no WoW API and are covered by headless busted tests; frame-bound behaviour is verified in game.

**Tech Stack:** Lua 5.1 (WoW client), no libraries, no Ace. Tests: busted 2.3.0 under WSL at `~/luaenv/bin/busted`.

**Spec:** `docs/superpowers/specs/2026-09-07-damage-meter-tweaks-design.md`

## Global Constraints

- Addon root: `g:\Games\World of Warcraft\_retail_\Interface\AddOns\DamageMeterTweaks`. All paths below are relative to it.
- `## Interface: 120100` (game 12.1.0). Title `DamageMeterTweaks`.
- SavedVariables: `DamageMeterTweaksDB` (account-wide settings). SavedVariablesPerCharacter: `DamageMeterTweaksCharDB` (window links).
- No external libraries. No Ace. No new dependencies of any kind.
- Never read a `C_DamageMeter` value without an `issecretvalue` guard. Never do arithmetic, comparison or string formatting on a value that guard has not cleared.
- Never call `SetPoint`, `SetSize`, `Show` or `Hide` on the primary session window (index 1). Edit Mode owns it. It may only be the target of another window's anchor.
- Maximum 3 session windows. Globals are `DamageMeterSessionWindow1` .. `DamageMeterSessionWindow3`.
- All file content in English, including comments.
- Test command, from the addon root:
  `MSYS_NO_PATHCONV=1 wsl bash -lc 'cd "/mnt/g/Games/World of Warcraft/_retail_/Interface/AddOns/DamageMeterTweaks" && ~/luaenv/bin/busted tests'`
  The `MSYS_NO_PATHCONV=1` prefix is required or Git Bash mangles the `/mnt/...` path.
- **Mixin methods are copied onto a frame when the frame is created** (`Mixin` does `object[k] = v`). `hooksecurefunc` on a mixin table therefore only reaches frames created *after* the hook. Frames that already exist at `PLAYER_LOGIN` - the `DamageMeter` frame and its session windows - must be hooked as instances. Use `ns.HookInstance(frame, method, handler)` for those and keep the mixin-table hook only where frames are created later. Getting this wrong produces an addon that loads cleanly and does nothing.
- Every module file starts with `local addonName, ns = ...` and must be loadable headless via `loadfile("File.lua")("DamageMeterTweaks", ns)`. That means **no WoW API calls at file scope** - all API use lives inside functions.
- Commits are local only. There is no remote; do not create one.

## File Structure

| File | Responsibility |
| --- | --- |
| `DamageMeterTweaks.toc` | Load order, saved variables |
| `Core.lua` | Namespace, defaults, saved variables, module registry, `PLAYER_LOGIN` bootstrap, slash commands, probe |
| `Format.lua` | Number abbreviation and entry value text; hook on `DamageMeterEntryMixin:UpdateValue` |
| `Hover.lua` | Hover-to-open source window; entry `OnEnter` / `OnLeave` |
| `ContextMenu.lua` | Right-click menu on bars; type, session and window actions |
| `Snap.lua` | Snap geometry, link bookkeeping, size matching, drag and restore wiring |
| `Presence.lua` | Idle vs hover transparency, frame strata |
| `Config.lua` | Settings panel: behaviour options and the per-window table |
| `Bindings.xml` | Key binding declarations (auto-loaded, not listed in the TOC) |
| `tests/*_spec.lua` | Headless busted tests for the pure helpers |

Hover, ContextMenu and Format all attach through hooks on Blizzard mixins and share nothing but `ns.db`. Snap owns all link state; Config only reads and writes settings and calls Snap's public functions.

---

### Task 1: Addon skeleton, Core and the in-game probe

The probe answers two questions the rest of the plan depends on: are entry values secret in combat, and can `damageMeterEnabled` be set in combat. Nothing else can be trusted until it has run.

**Files:**
- Create: `DamageMeterTweaks.toc`
- Create: `Core.lua`
- Create: `.busted`
- Create: `.gitignore`

- [ ] **Step 1: Initialise a local git repository**

```bash
cd "g:/Games/World of Warcraft/_retail_/Interface/AddOns/DamageMeterTweaks"
git init
```

- [ ] **Step 2: Write `.gitignore` and `.busted`**

`.gitignore`:

```gitignore
*.bak
nul
```

`.busted`:

```lua
return {
    default = {
        ROOT = { "tests" },
        pattern = "_spec",
    },
}
```

- [ ] **Step 3: Write the TOC**

`DamageMeterTweaks.toc`:

```toc
## Interface: 120100
## Title: DamageMeterTweaks
## Notes: Hover details, right-click menu, window snapping and readable numbers for the built-in Damage Meter.
## Version: 0.1.0
## SavedVariables: DamageMeterTweaksDB
## SavedVariablesPerCharacter: DamageMeterTweaksCharDB
## X-Category: Combat

Core.lua
Format.lua
Hover.lua
ContextMenu.lua
Snap.lua
Presence.lua
Config.lua
```

Files listed here do not exist yet; the client skips missing entries with a warning only in debug builds. They arrive in later tasks.

- [ ] **Step 4: Write `Core.lua`**

```lua
local addonName, ns = ...

ns.defaults = {
    hover = true,
    hoverDelay = 0.15,
    menu = true,
    format = true,
    snap = true,
    snapThreshold = 15,
    idleAlpha = 0.4,
    strata = "MEDIUM",
}

ns.charDefaults = {
    links = {},
}

local modules = {}

-- Modules register themselves at file scope and are enabled at PLAYER_LOGIN,
-- after the saved variables and the Blizzard damage meter both exist.
function ns.RegisterModule(name, module)
    modules[name] = module
end

function ns.Print(message)
    print("|cff33ff99DamageMeterTweaks|r: " .. message)
end

function ns.IsAvailable()
    return DamageMeter ~= nil
        and DamageMeterSessionWindowMixin ~= nil
        and DamageMeterEntryMixin ~= nil
end

-- Returns true if any of the passed values is secret. nil is never secret,
-- and must be filtered out because issecretvalue is only meaningful on a value.
function ns.IsAnySecret(...)
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if value ~= nil and issecretvalue(value) then
            return true
        end
    end

    return false
end

function ns.ForEachSessionWindow(func)
    for index = 1, 3 do
        local window = DamageMeter:GetSessionWindow(index)
        if window then
            func(window, index)
        end
    end
end

-- Mixin methods are copied onto a frame when the frame is created, so hooking
-- a mixin table only reaches frames created after the hook. Everything that
-- already exists at PLAYER_LOGIN has to be hooked one frame at a time. The
-- flag keeps a frame from being hooked twice.
-- Keyed by the handler, not by the method name: two modules legitimately hook
-- the same method with different handlers, and both must be installed.
function ns.HookInstance(frame, methodName, handler)
    frame.dmtHooks = frame.dmtHooks or {}

    if frame.dmtHooks[handler] then
        return
    end

    frame.dmtHooks[handler] = true
    hooksecurefunc(frame, methodName, handler)
end

-- Every entry frame that exists right now, across the bars of each session
-- window, its off-screen local player entry, and its spell breakdown.
function ns.ForEachEntryFrame(func)
    ns.ForEachSessionWindow(function(window)
        window:GetScrollBox():ForEachFrame(func)

        local localPlayerEntry = window:GetLocalPlayerEntry()
        if localPlayerEntry then
            func(localPlayerEntry)
        end

        window:GetSourceWindow():ForEachEntryFrame(func)
    end)
end

local function ApplyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if target[key] == nil then
            target[key] = (type(value) == "table") and {} or value
        end
    end
end

local function InitializeSavedVariables()
    DamageMeterTweaksDB = DamageMeterTweaksDB or {}
    DamageMeterTweaksCharDB = DamageMeterTweaksCharDB or {}

    ApplyDefaults(DamageMeterTweaksDB, ns.defaults)
    ApplyDefaults(DamageMeterTweaksCharDB, ns.charDefaults)

    ns.db = DamageMeterTweaksDB
    ns.charDb = DamageMeterTweaksCharDB
end

-- Prints what the design assumes about secrecy and CVar access so the
-- assumptions can be checked instead of trusted. Run it once in combat and
-- once out of combat.
function ns.Probe()
    local window = DamageMeter:GetPrimarySessionWindow()
    local dataProvider = window and window:GetScrollBox():GetDataProvider()
    local elementData = dataProvider and dataProvider:Find(1)

    ns.Print("in combat: " .. tostring(UnitAffectingCombat("player")))

    if not elementData then
        ns.Print("no entries in the primary window, deal some damage first")
    else
        ns.Print(("totalAmount secret: %s, amountPerSecond secret: %s, sessionTotalAmount secret: %s, deathRecapID secret: %s"):format(
            tostring(issecretvalue(elementData.totalAmount)),
            tostring(issecretvalue(elementData.amountPerSecond)),
            tostring(issecretvalue(elementData.sessionTotalAmount)),
            tostring(issecretvalue(elementData.deathRecapID))))
    end

    local current = C_CVar.GetCVar("damageMeterEnabled")
    local ok, err = pcall(C_CVar.SetCVar, "damageMeterEnabled", current)
    ns.Print("SetCVar(damageMeterEnabled) allowed: " .. tostring(ok) .. (ok and "" or (" - " .. tostring(err))))
end

local function HandleSlashCommand(input)
    local command = string.lower(string.trim(input or ""))

    if command == "probe" then
        ns.Probe()
    elseif command == "hover" or command == "snap" or command == "menu" or command == "format" then
        ns.db[command] = not ns.db[command]
        ns.Print(command .. ": " .. tostring(ns.db[command]))
    else
        ns.Print("commands: probe, hover, menu, format, snap")
    end
end

local bootstrap = CreateFrame("Frame")
bootstrap:RegisterEvent("PLAYER_LOGIN")
bootstrap:SetScript("OnEvent", function()
    InitializeSavedVariables()

    if not ns.IsAvailable() then
        ns.Print("Blizzard Damage Meter not found, nothing was installed.")
        return
    end

    for _, module in pairs(modules) do
        if module.Enable then
            module.Enable()
        end
    end

    SLASH_DAMAGEMETERTWEAKS1 = "/dmt"
    SlashCmdList["DAMAGEMETERTWEAKS"] = HandleSlashCommand
end)
```

- [ ] **Step 5: Verify it loads in game**

Reload the client (`/reload` if it is running, otherwise start it). Expect no Lua error and `/dmt` to print the command list.

- [ ] **Step 6: Run the probe out of combat**

Hit a target dummy so the meter has entries, leave combat, then `/dmt probe`. Expected: all four `secret` values `false`, `SetCVar ... allowed: true`.

- [ ] **Step 7: Run the probe in combat**

While still attacking a dummy, `/dmt probe`. Record the output. The design expects `totalAmount`, `amountPerSecond` and `sessionTotalAmount` to be `true` and `deathRecapID` to be `false`.

**If the values are NOT secret in combat**, stop and report: Task 2's guard becomes a no-op and the formatting feature covers combat too, which is a better outcome than planned. **If `SetCVar` is not allowed in combat**, Task 8's toggle binding must refuse in combat, as the spec already anticipates.

- [ ] **Step 8: Commit**

```bash
git add .gitignore .busted DamageMeterTweaks.toc Core.lua docs
git commit -m "feat: addon skeleton, core bootstrap and secrecy probe"
```

---

### Task 2: Number formatting

**Files:**
- Create: `Format.lua`
- Test: `tests/format_spec.lua`

**Interfaces:**
- Consumes: `ns.RegisterModule`, `ns.db`, `ns.IsAnySecret` from Task 1.
- Produces: `ns.Format.Abbreviate(value, decimals) -> string`, `ns.Format.SelectValues(entry) -> main, parenthetical, percentage`, `ns.Format.Compose(main, parenthetical, percentage) -> string`, `ns.Format.Enable()`.

- [ ] **Step 1: Write the failing test**

`tests/format_spec.lua`:

```lua
local ns = {}

_G.Enum = {
    DamageMeterNumbers = { Minimal = 0, Compact = 1, Complete = 2 },
}

assert(loadfile("Format.lua"))("DamageMeterTweaks", ns)

local Format = ns.Format

describe("Format.Abbreviate", function()
    it("leaves values below a thousand alone", function()
        assert.are.equal("0", Format.Abbreviate(0, 2))
        assert.are.equal("999", Format.Abbreviate(999, 2))
    end)

    it("switches to K at a thousand", function()
        assert.are.equal("1.00K", Format.Abbreviate(1000, 2))
        assert.are.equal("40.6K", Format.Abbreviate(40639, 1))
        assert.are.equal("999.99K", Format.Abbreviate(999990, 2))
    end)

    it("switches to M at a million", function()
        assert.are.equal("1.00M", Format.Abbreviate(1000000, 2))
        assert.are.equal("56.72M", Format.Abbreviate(56716000, 2))
    end)

    it("switches to B at a billion", function()
        assert.are.equal("2.50B", Format.Abbreviate(2500000000, 2))
    end)

    it("keeps trailing zeros so widths stay stable", function()
        assert.are.equal("5.00M", Format.Abbreviate(5000000, 2))
    end)

    it("handles negatives", function()
        assert.are.equal("-1.50M", Format.Abbreviate(-1500000, 2))
    end)

    it("treats nil as zero", function()
        assert.are.equal("0", Format.Abbreviate(nil, 2))
    end)
end)

describe("Format.SelectValues", function()
    it("returns only the main value in Minimal", function()
        local main, parenthetical, percentage = Format.SelectValues({
            numberDisplayType = Enum.DamageMeterNumbers.Minimal,
            value = 100, valuePerSecond = 10, sessionTotalValue = 400,
        })

        assert.are.equal(100, main)
        assert.is_nil(parenthetical)
        assert.is_nil(percentage)
    end)

    it("adds the rate in Compact", function()
        local main, parenthetical, percentage = Format.SelectValues({
            numberDisplayType = Enum.DamageMeterNumbers.Compact,
            value = 100, valuePerSecond = 10, sessionTotalValue = 400,
        })

        assert.are.equal(100, main)
        assert.are.equal(10, parenthetical)
        assert.is_nil(percentage)
    end)

    it("adds the share in Complete", function()
        local main, parenthetical, percentage = Format.SelectValues({
            numberDisplayType = Enum.DamageMeterNumbers.Complete,
            value = 100, valuePerSecond = 10, sessionTotalValue = 400,
        })

        assert.are.equal(100, main)
        assert.are.equal(10, parenthetical)
        assert.are.equal(0.25, percentage)
    end)

    it("swaps main and parenthetical when the rate is primary", function()
        local main, parenthetical = Format.SelectValues({
            numberDisplayType = Enum.DamageMeterNumbers.Compact,
            value = 100, valuePerSecond = 10, showsValuePerSecondAsPrimary = true,
        })

        assert.are.equal(10, main)
        assert.are.equal(100, parenthetical)
    end)

    it("drops the rate when the entry suppresses it", function()
        local _, parenthetical = Format.SelectValues({
            numberDisplayType = Enum.DamageMeterNumbers.Compact,
            value = 100, valuePerSecond = 10, suppressValuePerSecond = true,
        })

        assert.is_nil(parenthetical)
    end)

    it("reports a zero share when the session total is zero", function()
        local _, _, percentage = Format.SelectValues({
            numberDisplayType = Enum.DamageMeterNumbers.Complete,
            value = 100, sessionTotalValue = 0,
        })

        assert.are.equal(0, percentage)
    end)
end)

describe("Format.Compose", function()
    it("renders the main value alone", function()
        assert.are.equal("56.72M", Format.Compose(56716000))
    end)

    it("renders the rate in parentheses", function()
        assert.are.equal("56.72M (40.6K)", Format.Compose(56716000, 40639))
    end)

    it("renders the full form", function()
        assert.are.equal("56.72M (40.6K) 18.0%", Format.Compose(56716000, 40639, 0.18))
    end)

    it("renders a share without a rate", function()
        assert.are.equal("56.72M 18.0%", Format.Compose(56716000, nil, 0.18))
    end)
end)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
MSYS_NO_PATHCONV=1 wsl bash -lc 'cd "/mnt/g/Games/World of Warcraft/_retail_/Interface/AddOns/DamageMeterTweaks" && ~/luaenv/bin/busted tests'
```

Expected: an error from `loadfile("Format.lua")` returning nil, because the file does not exist yet.

- [ ] **Step 3: Write `Format.lua`**

```lua
local addonName, ns = ...

ns.Format = {}
local Format = ns.Format

local UNITS = {
    { threshold = 1e9, suffix = "B" },
    { threshold = 1e6, suffix = "M" },
    { threshold = 1e3, suffix = "K" },
}

-- Blizzard's AbbreviateLargeNumbers stops at thousands, which produces
-- unreadable strings like "56716 K" at current damage scales.
function Format.Abbreviate(value, decimals)
    value = value or 0

    if value < 0 then
        return "-" .. Format.Abbreviate(-value, decimals)
    end

    for _, unit in ipairs(UNITS) do
        if value >= unit.threshold then
            return ("%." .. decimals .. "f%s"):format(value / unit.threshold, unit.suffix)
        end
    end

    return ("%d"):format(value)
end

-- Mirrors the selection rules of GetMainValue, GetParentheticalValue and
-- GetPercentageValue in Blizzard_DamageMeter/DamageMeterEntry.lua, which are
-- file-local and cannot be reused.
function Format.SelectValues(entry)
    local numbers = Enum.DamageMeterNumbers
    local displayType = entry.numberDisplayType or numbers.Minimal

    local main
    if entry.valuePerSecond and entry.showsValuePerSecondAsPrimary then
        main = entry.valuePerSecond
    else
        main = entry.value or 0
    end

    local parenthetical
    if displayType ~= numbers.Minimal then
        if entry.value and entry.showsValuePerSecondAsPrimary then
            parenthetical = entry.value
        elseif not entry.suppressValuePerSecond then
            parenthetical = entry.valuePerSecond or 0
        end
    end

    local percentage
    if displayType == numbers.Complete then
        if entry.value and entry.sessionTotalValue and entry.sessionTotalValue > 0 then
            percentage = entry.value / entry.sessionTotalValue
        else
            percentage = 0
        end
    end

    return main, parenthetical, percentage
end

function Format.Compose(main, parenthetical, percentage)
    local mainText = Format.Abbreviate(main, 2)

    if parenthetical and percentage then
        return ("%s (%s) %.1f%%"):format(mainText, Format.Abbreviate(parenthetical, 1), percentage * 100)
    elseif percentage then
        return ("%s %.1f%%"):format(mainText, percentage * 100)
    elseif parenthetical then
        return ("%s (%s)"):format(mainText, Format.Abbreviate(parenthetical, 1))
    end

    return mainText
end

-- Runs after Blizzard has already set its own text, so bailing out simply
-- leaves the original string in place.
local function OnUpdateValue(entry)
    if not ns.db.format then
        return
    end

    if ns.IsAnySecret(entry.value, entry.valuePerSecond, entry.sessionTotalValue) then
        return
    end

    entry:GetValue():SetText(Format.Compose(Format.SelectValues(entry)))
end

function Format.Enable()
    -- Entry frames are pooled and mostly created later, which the mixin hook
    -- covers. Any that the meter already built before we loaded carry a copy
    -- of the original method and need hooking individually.
    hooksecurefunc(DamageMeterEntryMixin, "UpdateValue", OnUpdateValue)
    ns.ForEachEntryFrame(function(entry)
        ns.HookInstance(entry, "UpdateValue", OnUpdateValue)
    end)
end

ns.RegisterModule("Format", Format)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the same command as Step 2. Expected: all tests pass.

- [ ] **Step 5: Verify in game**

`/reload`, hit a dummy, leave combat. Expected: bars and the spell breakdown read `56.72M (40.6K) 18.0%` instead of `56716 K (40,639) 18%`. During combat the old format is expected unless Task 1's probe said otherwise.

- [ ] **Step 6: Commit**

```bash
git add Format.lua tests/format_spec.lua
git commit -m "feat: readable number formatting on meter entries"
```

---

### Task 3: Hover to open the source window

**Files:**
- Create: `Hover.lua`

**Interfaces:**
- Consumes: `ns.RegisterModule`, `ns.db` from Task 1.
- Produces: `ns.Hover.Enable()`. Installs `OnEnter` and `OnLeave` on entry frames from a hook on `DamageMeterSessionWindowMixin:InitEntry`. Task 4 hooks the same function for `OnClick`; the two hooks are independent and order does not matter.

- [ ] **Step 1: Write `Hover.lua`**

```lua
local addonName, ns = ...

ns.Hover = {}
local Hover = ns.Hover

local pendingTimer

local function CancelPending()
    if pendingTimer then
        pendingTimer:Cancel()
        pendingTimer = nil
    end
end

-- Sources that carry a death recap open the death recap UI instead of the
-- source window, which would be hostile on a mere hover. deathRecapID is
-- documented NeverSecret, so reading it in combat is safe.
local function OpensDeathRecap(elementData)
    return type(elementData.deathRecapID) == "number" and elementData.deathRecapID ~= 0
end

local function OnInitEntry(sessionWindow, frame, elementData)
        frame:SetScript("OnEnter", function()
            if not ns.db.hover or OpensDeathRecap(elementData) then
                return
            end

            CancelPending()
            pendingTimer = C_Timer.NewTimer(ns.db.hoverDelay, function()
                pendingTimer = nil

                if frame:IsMouseOver() and frame:IsVisible() then
                    local sticky = false
                    sessionWindow:ShowSourceWindow(elementData, sticky)
                end
            end)
        end)

        frame:SetScript("OnLeave", function()
            if not ns.db.hover then
                return
            end

            CancelPending()

            local sourceWindow = sessionWindow:GetSourceWindow()
            if sourceWindow:IsShown() and not sourceWindow:IsSticky() then
                -- One frame of grace so moving the cursor from the bar into the
                -- source window, which sits flush against the window edge, does
                -- not close it.
                C_Timer.After(0, function()
                    if sourceWindow:IsShown()
                        and not sourceWindow:IsSticky()
                        and not sourceWindow:IsMouseOver()
                        and not frame:IsMouseOver() then
                        sessionWindow:HideSourceWindow()
                    end
                end)
            end
        end)
end

function Hover.Enable()
    -- The session windows already exist and carry copies of InitEntry, so the
    -- mixin hook alone would never fire for them.
    hooksecurefunc(DamageMeterSessionWindowMixin, "InitEntry", OnInitEntry)
    ns.ForEachSessionWindow(function(window)
        ns.HookInstance(window, "InitEntry", OnInitEntry)
    end)
end

ns.RegisterModule("Hover", Hover)
```

The body of `OnInitEntry` above is indented one level deeper than it needs to be, a leftover from lifting it out of an inline closure. Re-indent it to four spaces per level as you transcribe it.

- [ ] **Step 2: Verify in game**

`/reload`, hit a dummy. Expected, checked one by one:

1. Hovering a bar opens the spell breakdown after a short delay.
2. Moving the cursor off the bar closes it.
3. Moving the cursor from the bar into the breakdown keeps it open.
4. Left-clicking a bar still opens it and it stays open after the cursor leaves (Blizzard's own click path is untouched in this task).
5. Hovering a row in the Deaths display does not open the death recap; clicking it still does.
6. `/dmt hover` turns the behaviour off and clicking still works.

- [ ] **Step 3: Commit**

```bash
git add Hover.lua
git commit -m "feat: open the spell breakdown on hover"
```

---

### Task 4: Right-click context menu

**Files:**
- Create: `ContextMenu.lua`

**Interfaces:**
- Consumes: `ns.RegisterModule`, `ns.db`, `ns.Print` from Task 1.
- Produces: `ns.ContextMenu.CATEGORIES` (array of `{ name = string, types = { number, ... } }`), `ns.ContextMenu.Enable()`. Task 9 reuses `CATEGORIES` to build the type dropdown in the settings panel.

- [ ] **Step 1: Write `ContextMenu.lua`**

The category and name tables mirror `DAMAGE_METER_CATEGORIES` and `DAMAGE_METER_TYPE_NAMES`, which are file-local in `DamageMeterSessionWindow.lua`. The global strings themselves are available, so no locale files are needed. `VerifyTypeCoverage` prints a warning when a future patch adds a type we do not list.

```lua
local addonName, ns = ...

ns.ContextMenu = {}
local ContextMenu = ns.ContextMenu

ContextMenu.CATEGORIES = {
    {
        name = DAMAGE_METER_CATEGORY_DAMAGE,
        types = {
            Enum.DamageMeterType.DamageDone,
            Enum.DamageMeterType.Dps,
            Enum.DamageMeterType.DamageTaken,
            Enum.DamageMeterType.AvoidableDamageTaken,
            Enum.DamageMeterType.EnemyDamageTaken,
        },
    },
    {
        name = DAMAGE_METER_CATEGORY_HEALING,
        types = {
            Enum.DamageMeterType.HealingDone,
            Enum.DamageMeterType.Hps,
            -- Blizzard's own menu omits Absorbs even though the type and its
            -- name string both exist. We list it: leaving a reachable type out
            -- of a menu whose whole point is reaching types would be odd. If it
            -- turns out to render an empty window, drop it here and note why.
            Enum.DamageMeterType.Absorbs,
        },
    },
    {
        name = DAMAGE_METER_CATEGORY_ACTIONS,
        types = {
            Enum.DamageMeterType.Interrupts,
            Enum.DamageMeterType.Dispels,
            Enum.DamageMeterType.Deaths,
        },
    },
}

local TYPE_NAMES = {
    [Enum.DamageMeterType.DamageDone] = DAMAGE_METER_TYPE_DAMAGE_DONE,
    [Enum.DamageMeterType.Dps] = DAMAGE_METER_TYPE_DPS,
    [Enum.DamageMeterType.HealingDone] = DAMAGE_METER_TYPE_HEALING_DONE,
    [Enum.DamageMeterType.Hps] = DAMAGE_METER_TYPE_HPS,
    [Enum.DamageMeterType.Absorbs] = DAMAGE_METER_TYPE_ABSORBS,
    [Enum.DamageMeterType.Interrupts] = DAMAGE_METER_TYPE_INTERRUPTS,
    [Enum.DamageMeterType.Dispels] = DAMAGE_METER_TYPE_DISPELS,
    [Enum.DamageMeterType.DamageTaken] = DAMAGE_METER_TYPE_DAMAGE_TAKEN,
    [Enum.DamageMeterType.AvoidableDamageTaken] = DAMAGE_METER_TYPE_AVOIDABLE_DAMAGE_TAKEN,
    [Enum.DamageMeterType.Deaths] = DAMAGE_METER_TYPE_DEATHS,
    [Enum.DamageMeterType.EnemyDamageTaken] = DAMAGE_METER_TYPE_ENEMY_DAMAGE_TAKEN,
}

function ContextMenu.GetTypeName(damageMeterType)
    return TYPE_NAMES[damageMeterType] or UNKNOWN
end

-- A patch that adds a damage meter type would silently drop it from our menu.
-- Say so rather than lose it.
local function VerifyTypeCoverage()
    local listed = {}
    for _, category in ipairs(ContextMenu.CATEGORIES) do
        for _, damageMeterType in ipairs(category.types) do
            listed[damageMeterType] = true
        end
    end

    for name, value in pairs(Enum.DamageMeterType) do
        if not listed[value] then
            ns.Print("unlisted damage meter type: " .. name .. " - the right-click menu needs updating")
        end
    end
end

local function AddTypeEntries(rootDescription, sessionWindow)
    local function IsSelected(damageMeterType)
        return sessionWindow:GetDamageMeterType() == damageMeterType
    end

    local function SetSelected(damageMeterType)
        DamageMeter:SetSessionWindowDamageMeterType(sessionWindow, damageMeterType)
    end

    for _, category in ipairs(ContextMenu.CATEGORIES) do
        local submenu = rootDescription:CreateButton(category.name)
        for _, damageMeterType in ipairs(category.types) do
            submenu:CreateRadio(ContextMenu.GetTypeName(damageMeterType), IsSelected, SetSelected, damageMeterType)
        end
    end
end

-- Mirrors InitializeSessionDropdown so the segment list reads identically to
-- the one on the window header.
local function AddSessionEntries(rootDescription, sessionWindow)
    local function IsSelected(option)
        return sessionWindow:GetSessionType() == option.type
            and sessionWindow:GetSessionID() == option.sessionID
    end

    local function SetSelected(option)
        DamageMeter:SetSessionWindowSessionID(sessionWindow, option.type, option.sessionID)
    end

    -- No global string names the concept, and labelling the submenu with one
    -- of the segments it contains would read as a selection rather than a
    -- category, so this one is ours.
    local submenu = rootDescription:CreateButton("Segment")

    for _, availableSession in ipairs(C_DamageMeter.GetAvailableCombatSessions()) do
        local sessionName = availableSession.name
        if not sessionName or sessionName == "" then
            sessionName = DAMAGE_METER_COMBAT_NUMBER:format(availableSession.sessionID)
        end

        if availableSession.durationSeconds then
            sessionName = ("%s [%s]"):format(sessionName, SecondsToClock(availableSession.durationSeconds))
        end

        submenu:CreateRadio(sessionName, IsSelected, SetSelected, { type = nil, sessionID = availableSession.sessionID })
    end

    submenu:CreateDivider()
    submenu:CreateRadio(DAMAGE_METER_CURRENT_SESSION, IsSelected, SetSelected,
        { type = Enum.DamageMeterSessionType.Current, sessionID = nil })
    submenu:CreateRadio(DAMAGE_METER_OVERALL_SESSION, IsSelected, SetSelected,
        { type = Enum.DamageMeterSessionType.Overall, sessionID = nil })
end

local function AddWindowEntries(rootDescription, sessionWindow)
    if DamageMeter:CanMoveOrResizeSessionWindow(sessionWindow) then
        local locked = sessionWindow:IsLocked()
        rootDescription:CreateButton(locked and DAMAGE_METER_UNLOCK_WINDOW or DAMAGE_METER_LOCK_WINDOW, function()
            DamageMeter:SetSessionWindowLocked(sessionWindow, not locked)
        end)
    end

    local newWindow = rootDescription:CreateButton(DAMAGE_METER_SHOW_NEW_WINDOW, function()
        DamageMeter:ShowNewSecondarySessionWindow()
    end)
    newWindow:SetEnabled(DamageMeter:CanShowNewSecondarySessionWindow())

    local hideWindow = rootDescription:CreateButton(DAMAGE_METER_HIDE_WINDOW, function()
        DamageMeter:HideSessionWindow(sessionWindow)
    end)
    hideWindow:SetEnabled(DamageMeter:CanHideSessionWindow(sessionWindow))

    rootDescription:CreateButton(DAMAGE_METER_RESET_ALL_SESSIONS, function()
        C_DamageMeter.ResetAllCombatSessions()
    end)
end

-- Replaces the OnClick Blizzard installed in InitEntry immediately above; the
-- left button keeps its behaviour, the right button gains the menu.
local function OnInitEntry(sessionWindow, frame, elementData)
    frame:SetScript("OnClick", function(_, mouseButtonName)
        if mouseButtonName == "RightButton" and ns.db.menu then
            MenuUtil.CreateContextMenu(frame, function(_, rootDescription)
                AddTypeEntries(rootDescription, sessionWindow)
                rootDescription:CreateDivider()
                AddSessionEntries(rootDescription, sessionWindow)
                rootDescription:CreateDivider()
                AddWindowEntries(rootDescription, sessionWindow)

                -- Snap adds its match-size checkboxes here once it exists.
                if ns.Snap and ns.Snap.AddMenuEntries then
                    ns.Snap.AddMenuEntries(rootDescription, sessionWindow)
                end
            end)
            return
        end

        local sticky = true
        sessionWindow:ShowSourceWindow(elementData, sticky)
    end)
end

function ContextMenu.Enable()
    VerifyTypeCoverage()

    -- Mixin hook for windows created later, instance hooks for the ones that
    -- already exist and carry their own copy of InitEntry.
    hooksecurefunc(DamageMeterSessionWindowMixin, "InitEntry", OnInitEntry)
    ns.ForEachSessionWindow(function(window)
        ns.HookInstance(window, "InitEntry", OnInitEntry)
    end)
end

ns.RegisterModule("ContextMenu", ContextMenu)
```

`ns.Snap.AddMenuEntries` does not exist yet and the `if ns.Snap then` guard keeps this task working without it. Task 6 supplies it.

- [ ] **Step 2: Verify in game**

`/reload`, hit a dummy. Expected:

1. Right-clicking a bar opens a menu at the cursor with three type submenus, a segment submenu and the window actions.
2. Picking Healing Done switches the window, and the header dropdown agrees.
3. Picking a segment switches it, and the header segment widget agrees.
4. Show new window and Hide window work, and Hide is greyed out on the primary window.
5. Left-clicking a bar still pins the breakdown.
6. No message about an unlisted damage meter type appears at login.

- [ ] **Step 3: Commit**

```bash
git add ContextMenu.lua
git commit -m "feat: right-click menu for type, segment and window actions"
```

---

### Task 5: Snap geometry and link bookkeeping

Pure functions only. No frames, no WoW API. Task 6 wires them to the game.

**Files:**
- Create: `Snap.lua`
- Test: `tests/snap_spec.lua`

**Interfaces:**
- Consumes: `ns.RegisterModule` from Task 1.
- Produces:
  - `ns.Snap.FindSnap(rect, candidates, threshold) -> result or nil`, where `rect` and each candidate are `{ index = number, left, right, top, bottom }` and `result` is `{ index, point, relPoint, axis }` with `axis` either `"vertical"` or `"horizontal"`.
  - `ns.Snap.WouldCycle(links, from, to) -> boolean`
  - `ns.Snap.ApplyOrder(links) -> array of window indices, targets before dependents`
  - `ns.Snap.Clamp(value, minimum, maximum) -> number`

- [ ] **Step 1: Write the failing test**

`tests/snap_spec.lua`:

```lua
local ns = {}

assert(loadfile("Snap.lua"))("DamageMeterTweaks", ns)

local Snap = ns.Snap

-- A 400x200 window with its top-left corner at (100, 500).
local function Rect(index, left, top, width, height)
    return { index = index, left = left, right = left + width, top = top, bottom = top - height }
end

describe("Snap.FindSnap", function()
    it("snaps below a window when the top edge is near its bottom edge", function()
        local dragged = Rect(2, 100, 296, 400, 200)
        local target = Rect(1, 100, 500, 400, 200)

        local result = Snap.FindSnap(dragged, { target }, 15)

        assert.are.equal(1, result.index)
        assert.are.equal("TOPLEFT", result.point)
        assert.are.equal("BOTTOMLEFT", result.relPoint)
        assert.are.equal("vertical", result.axis)
    end)

    it("snaps above a window", function()
        local dragged = Rect(2, 100, 704, 400, 200)
        local target = Rect(1, 100, 500, 400, 200)

        local result = Snap.FindSnap(dragged, { target }, 15)

        assert.are.equal("BOTTOMLEFT", result.point)
        assert.are.equal("TOPLEFT", result.relPoint)
        assert.are.equal("vertical", result.axis)
    end)

    it("snaps to the right of a window", function()
        local dragged = Rect(2, 506, 500, 400, 200)
        local target = Rect(1, 100, 500, 400, 200)

        local result = Snap.FindSnap(dragged, { target }, 15)

        assert.are.equal("TOPLEFT", result.point)
        assert.are.equal("TOPRIGHT", result.relPoint)
        assert.are.equal("horizontal", result.axis)
    end)

    it("snaps to the left of a window", function()
        local dragged = Rect(2, -306, 500, 400, 200)
        local target = Rect(1, 100, 500, 400, 200)

        local result = Snap.FindSnap(dragged, { target }, 15)

        assert.are.equal("TOPRIGHT", result.point)
        assert.are.equal("TOPLEFT", result.relPoint)
        assert.are.equal("horizontal", result.axis)
    end)

    it("returns nothing when the gap is beyond the threshold", function()
        local dragged = Rect(2, 100, 200, 400, 200)
        local target = Rect(1, 100, 500, 400, 200)

        assert.is_nil(Snap.FindSnap(dragged, { target }, 15))
    end)

    it("returns nothing when the edges are near but do not overlap", function()
        local dragged = Rect(2, 900, 296, 400, 200)
        local target = Rect(1, 100, 500, 400, 200)

        assert.is_nil(Snap.FindSnap(dragged, { target }, 15))
    end)

    it("picks the closest candidate", function()
        local dragged = Rect(3, 100, 296, 400, 200)
        local far = Rect(1, 100, 506, 400, 200)
        local near = Rect(2, 100, 500, 400, 200)

        assert.are.equal(2, Snap.FindSnap(dragged, { far, near }, 15).index)
    end)

    it("never snaps a window to itself", function()
        local dragged = Rect(1, 100, 500, 400, 200)

        assert.is_nil(Snap.FindSnap(dragged, { dragged }, 15))
    end)
end)

describe("Snap.WouldCycle", function()
    it("allows a fresh link", function()
        assert.is_false(Snap.WouldCycle({}, 2, 1))
    end)

    it("refuses a direct loop", function()
        local links = { [1] = { to = 2 } }

        assert.is_true(Snap.WouldCycle(links, 2, 1))
    end)

    it("refuses an indirect loop", function()
        local links = { [3] = { to = 2 }, [2] = { to = 1 } }

        assert.is_true(Snap.WouldCycle(links, 1, 3))
    end)

    it("refuses a self link", function()
        assert.is_true(Snap.WouldCycle({}, 2, 2))
    end)
end)

describe("Snap.ApplyOrder", function()
    it("returns targets before dependents", function()
        local links = { [3] = { to = 2 }, [2] = { to = 1 } }

        assert.are.same({ 2, 3 }, Snap.ApplyOrder(links))
    end)

    it("handles independent links", function()
        local links = { [2] = { to = 1 }, [3] = { to = 1 } }
        local order = Snap.ApplyOrder(links)

        assert.are.equal(2, #order)
    end)

    it("returns an empty list when there are no links", function()
        assert.are.same({}, Snap.ApplyOrder({}))
    end)
end)

describe("Snap.Clamp", function()
    it("clamps below the minimum", function()
        assert.are.equal(200, Snap.Clamp(150, 200, 600))
    end)

    it("clamps above the maximum", function()
        assert.are.equal(600, Snap.Clamp(900, 200, 600))
    end)

    it("leaves a value inside the range alone", function()
        assert.are.equal(400, Snap.Clamp(400, 200, 600))
    end)
end)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
MSYS_NO_PATHCONV=1 wsl bash -lc 'cd "/mnt/g/Games/World of Warcraft/_retail_/Interface/AddOns/DamageMeterTweaks" && ~/luaenv/bin/busted tests'
```

Expected: `loadfile("Snap.lua")` returns nil, assertion fails.

- [ ] **Step 3: Write the pure part of `Snap.lua`**

```lua
local addonName, ns = ...

ns.Snap = {}
local Snap = ns.Snap

Snap.MIN_WIDTH, Snap.MAX_WIDTH = 200, 600
Snap.MIN_HEIGHT, Snap.MAX_HEIGHT = 120, 400

function Snap.Clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function Overlaps(aLow, aHigh, bLow, bHigh)
    return aLow < bHigh and bLow < aHigh
end

-- Each edge pairing snaps the dragged window flush against the target. The
-- perpendicular offset is dropped on purpose: flush plus the matching size
-- flag from the caller is what makes a pair read as one block.
local function EdgeCandidates(rect, candidate)
    return {
        {
            gap = math.abs(rect.top - candidate.bottom),
            overlaps = Overlaps(rect.left, rect.right, candidate.left, candidate.right),
            point = "TOPLEFT", relPoint = "BOTTOMLEFT", axis = "vertical",
        },
        {
            gap = math.abs(rect.bottom - candidate.top),
            overlaps = Overlaps(rect.left, rect.right, candidate.left, candidate.right),
            point = "BOTTOMLEFT", relPoint = "TOPLEFT", axis = "vertical",
        },
        {
            gap = math.abs(rect.left - candidate.right),
            overlaps = Overlaps(rect.bottom, rect.top, candidate.bottom, candidate.top),
            point = "TOPLEFT", relPoint = "TOPRIGHT", axis = "horizontal",
        },
        {
            gap = math.abs(rect.right - candidate.left),
            overlaps = Overlaps(rect.bottom, rect.top, candidate.bottom, candidate.top),
            point = "TOPRIGHT", relPoint = "TOPLEFT", axis = "horizontal",
        },
    }
end

function Snap.FindSnap(rect, candidates, threshold)
    local best

    for _, candidate in ipairs(candidates) do
        if candidate.index ~= rect.index then
            for _, edge in ipairs(EdgeCandidates(rect, candidate)) do
                if edge.overlaps and edge.gap <= threshold and (not best or edge.gap < best.gap) then
                    best = {
                        gap = edge.gap,
                        index = candidate.index,
                        point = edge.point,
                        relPoint = edge.relPoint,
                        axis = edge.axis,
                    }
                end
            end
        end
    end

    return best
end

-- Walks the chain from the prospective target back up. Depth is at most three.
function Snap.WouldCycle(links, from, to)
    local current = to

    while current do
        if current == from then
            return true
        end

        local link = links[current]
        current = link and link.to or nil
    end

    return false
end

function Snap.ApplyOrder(links)
    local order = {}
    local placed = {}

    local function Place(index)
        if placed[index] or not links[index] then
            return
        end

        placed[index] = true
        Place(links[index].to)
        table.insert(order, index)
    end

    for index = 1, 3 do
        Place(index)
    end

    return order
end

ns.RegisterModule("Snap", Snap)
```

`Place` marks the index before recursing, so a corrupt saved link that forms a cycle terminates instead of overflowing the stack.

- [ ] **Step 4: Run the tests to verify they pass**

Run the same command as Step 2. Expected: all format and snap tests pass.

- [ ] **Step 5: Commit**

```bash
git add Snap.lua tests/snap_spec.lua
git commit -m "feat: snap geometry and link bookkeeping"
```

---

### Task 6: Snap wiring, persistence and size matching

**Files:**
- Modify: `Snap.lua` (append to the file from Task 5, above the `ns.RegisterModule` line)

**Interfaces:**
- Consumes: Task 5's pure functions, `ns.charDb.links`, `ns.db.snap`, `ns.db.snapThreshold`, `ns.ForEachSessionWindow`.
- Produces: `ns.Snap.Enable()`, `ns.Snap.SetLink(index, link)`, `ns.Snap.ClearLink(index)`, `ns.Snap.ApplyLink(index)`, `ns.Snap.ApplyAll()`, `ns.Snap.PushSize(index)`, `ns.Snap.AddMenuEntries(rootDescription, sessionWindow)`. Task 9's panel calls `SetLink`, `ClearLink` and `PushSize`; Task 4's menu calls `AddMenuEntries`.

- [ ] **Step 1: Append the wiring to `Snap.lua`**

```lua
local function RectOf(window, index)
    local left, bottom, width, height = window:GetRect()

    return {
        index = index,
        left = left,
        right = left + width,
        top = bottom + height,
        bottom = bottom,
    }
end

local function GetLinks()
    return ns.charDb.links
end

local applyingSize = false

-- Pushes this window's size onto every window linked to it that asked to match
-- an axis. The guard stops a mutual match from bouncing; a chain settles in one
-- pass because each SetWidth that actually changes the size fires OnSizeChanged
-- again from the child.
function Snap.PushSize(index)
    if applyingSize then
        return
    end

    local source = DamageMeter:GetSessionWindow(index)
    if not source then
        return
    end

    applyingSize = true

    for otherIndex, link in pairs(GetLinks()) do
        if link.to == index then
            local target = DamageMeter:GetSessionWindow(otherIndex)
            if target and DamageMeter:CanMoveOrResizeSessionWindow(target) then
                if link.matchWidth then
                    target:SetWidth(Snap.Clamp(source:GetWidth(), Snap.MIN_WIDTH, Snap.MAX_WIDTH))
                end

                if link.matchHeight then
                    target:SetHeight(Snap.Clamp(source:GetHeight(), Snap.MIN_HEIGHT, Snap.MAX_HEIGHT))
                end
            end
        end
    end

    applyingSize = false
end

function Snap.ApplyLink(index)
    local link = GetLinks()[index]
    local window = DamageMeter:GetSessionWindow(index)
    local target = link and DamageMeter:GetSessionWindow(link.to)

    if not link or not window or not target or not target:IsShown() then
        return
    end

    if not DamageMeter:CanMoveOrResizeSessionWindow(window) then
        return
    end

    window:ClearAllPoints()
    window:SetPoint(link.point, target, link.relPoint, 0, 0)

    -- Blizzard's saved frame position cache would otherwise fight the anchor.
    window:SetUserPlaced(false)

    Snap.PushSize(link.to)
end

function Snap.ApplyAll()
    for _, index in ipairs(Snap.ApplyOrder(GetLinks())) do
        Snap.ApplyLink(index)
    end
end

function Snap.SetLink(index, link)
    GetLinks()[index] = link
    Snap.ApplyLink(index)
end

function Snap.ClearLink(index)
    GetLinks()[index] = nil
end

local function CollectCandidates(exceptIndex)
    local candidates = {}

    ns.ForEachSessionWindow(function(window, index)
        if index ~= exceptIndex and window:IsShown() then
            table.insert(candidates, RectOf(window, index))
        end
    end)

    return candidates
end

function Snap.AddMenuEntries(rootDescription, sessionWindow)
    local index = sessionWindow:GetSessionWindowIndex()
    local link = GetLinks()[index]

    if not link then
        return
    end

    rootDescription:CreateDivider()

    rootDescription:CreateCheckbox(DAMAGE_METER_TWEAKS_MATCH_WIDTH,
        function() return link.matchWidth end,
        function()
            link.matchWidth = not link.matchWidth
            Snap.PushSize(link.to)
        end)

    rootDescription:CreateCheckbox(DAMAGE_METER_TWEAKS_MATCH_HEIGHT,
        function() return link.matchHeight end,
        function()
            link.matchHeight = not link.matchHeight
            Snap.PushSize(link.to)
        end)
end

function Snap.Enable()
    DAMAGE_METER_TWEAKS_MATCH_WIDTH = "Match width"
    DAMAGE_METER_TWEAKS_MATCH_HEIGHT = "Match height"

    local function OnDragStop(window)
        if not ns.db.snap then
            return
        end

        local index = window:GetSessionWindowIndex()
        if not DamageMeter:CanMoveOrResizeSessionWindow(window) then
            return
        end

        local result = Snap.FindSnap(RectOf(window, index), CollectCandidates(index), ns.db.snapThreshold)

        if not result or Snap.WouldCycle(GetLinks(), index, result.index) then
            Snap.ClearLink(index)
            return
        end

        Snap.SetLink(index, {
            to = result.index,
            point = result.point,
            relPoint = result.relPoint,
            -- The axis perpendicular to the edge we landed on is the one that
            -- has to agree for the pair to read as one block.
            matchWidth = result.axis == "vertical",
            matchHeight = result.axis == "horizontal",
        })
    end

    -- Mixin hook for windows created later, instance hooks for the ones that
    -- already exist and carry their own copy of OnDragStop.
    hooksecurefunc(DamageMeterSessionWindowMixin, "OnDragStop", OnDragStop)

    ns.ForEachSessionWindow(function(window, index)
        ns.HookInstance(window, "OnDragStop", OnDragStop)

        window.dmtSizeHooked = true
        window:HookScript("OnSizeChanged", function()
            Snap.PushSize(index)
        end)
    end)

    -- Blizzard restores its saved frame positions during login; applying on the
    -- next frame puts our anchors on top of that rather than under it.
    C_Timer.After(0, Snap.ApplyAll)
end
```

`ns.ForEachSessionWindow` only sees windows that exist at `Enable()` time. A window created later through Show new window has no size hook. Step 2 covers that by hooking creation as well.

- [ ] **Step 2: Hook newly created windows**

Add inside `Snap.Enable()`, after the existing `ForEachSessionWindow` block:

```lua
    -- Windows created later, through Show new window, need the same size hook.
    -- DamageMeter already exists, so this one must be an instance hook.
    ns.HookInstance(DamageMeter, "SetupSessionWindow", function(_, windowDataIndex, windowData)
        local window = windowData.sessionWindow
        if window and not window.dmtSizeHooked then
            window.dmtSizeHooked = true
            window:HookScript("OnSizeChanged", function()
                Snap.PushSize(windowDataIndex)
            end)
        end
    end)
```

The `ForEachSessionWindow` block in Step 1 already sets `window.dmtSizeHooked = true`, so a window that exists now is never size-hooked a second time when `SetupSessionWindow` runs for it later.

- [ ] **Step 3: Wire the menu entries**

`ContextMenu.lua` already calls `ns.Snap.AddMenuEntries` behind an `if ns.Snap then` guard, so nothing to change there. Confirm by reading `ContextMenu.Enable`.

- [ ] **Step 4: Run the tests**

Run:

```bash
MSYS_NO_PATHCONV=1 wsl bash -lc 'cd "/mnt/g/Games/World of Warcraft/_retail_/Interface/AddOns/DamageMeterTweaks" && ~/luaenv/bin/busted tests'
```

Expected: still all passing. This task added no pure logic, so no new tests; the wiring is verified in game.

- [ ] **Step 5: Verify in game**

`/reload`, then from the right-click menu choose Show new window twice so all three exist. Expected:

1. Dragging window 2 so its top edge comes near the bottom of window 1 makes it jump flush, and its width becomes window 1's width.
2. Moving window 1 in Edit Mode carries window 2 with it.
3. Resizing window 1 in Edit Mode resizes window 2's width to match, clamped at 600 if window 1 is wider.
4. Dragging window 2 well away from window 1 breaks the link and it moves freely.
5. Snapping window 3 to the right of window 2 matches heights instead of widths.
6. Right-clicking a bar in a linked window shows Match width and Match height, and toggling them takes effect immediately.
7. `/reload` keeps every link and every matched size.
8. Trying to snap window 1 to anything does nothing - it cannot be dragged at all.

- [ ] **Step 6: Commit**

```bash
git add Snap.lua
git commit -m "feat: magnetic window snapping with size matching"
```

---

### Task 7: Idle transparency and strata

**Files:**
- Create: `Presence.lua`
- Test: `tests/presence_spec.lua`

**Interfaces:**
- Consumes: `ns.RegisterModule`, `ns.db.idleAlpha`, `ns.db.strata`, `ns.ForEachSessionWindow` from Task 1.
- Produces: `ns.Presence.Enable()`, `ns.Presence.ComputeAlpha(editModeAlpha, idleFactor, isHovered) -> number`, `ns.Presence.NextStrataUp(strata) -> string`, `ns.Presence.ApplyAlpha(window)`, `ns.Presence.ApplyStrata()`, `ns.Presence.STRATA_ORDER` (array of strata names in ascending order, used by Task 9's dropdown).

- [ ] **Step 1: Write the failing test**

`tests/presence_spec.lua`:

```lua
local ns = {}

assert(loadfile("Presence.lua"))("DamageMeterTweaks", ns)

local Presence = ns.Presence

describe("Presence.ComputeAlpha", function()
    it("uses the Edit Mode alpha while hovered", function()
        assert.are.equal(0.8, Presence.ComputeAlpha(0.8, 0.4, true))
    end)

    it("scales the Edit Mode alpha while idle", function()
        -- 0.8 * 0.4 is not exactly 0.32 in doubles, so compare with tolerance.
        assert.is_true(math.abs(Presence.ComputeAlpha(0.8, 0.4, false) - 0.32) < 1e-9)
    end)

    it("follows a changed Edit Mode alpha in both states", function()
        assert.are.equal(1, Presence.ComputeAlpha(1, 0.4, true))
        assert.are.equal(0.4, Presence.ComputeAlpha(1, 0.4, false))
    end)
end)

describe("Presence.NextStrataUp", function()
    it("returns the next strata up", function()
        assert.are.equal("HIGH", Presence.NextStrataUp("MEDIUM"))
        assert.are.equal("DIALOG", Presence.NextStrataUp("HIGH"))
    end)

    it("stays at the top of the list", function()
        assert.are.equal("TOOLTIP", Presence.NextStrataUp("TOOLTIP"))
    end)

    it("falls back to HIGH for an unknown strata", function()
        assert.are.equal("HIGH", Presence.NextStrataUp("NONSENSE"))
    end)
end)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
MSYS_NO_PATHCONV=1 wsl bash -lc 'cd "/mnt/g/Games/World of Warcraft/_retail_/Interface/AddOns/DamageMeterTweaks" && ~/luaenv/bin/busted tests'
```

Expected: `loadfile("Presence.lua")` returns nil, assertion fails.

- [ ] **Step 3: Write `Presence.lua`**

```lua
local addonName, ns = ...

ns.Presence = {}
local Presence = ns.Presence

Presence.STRATA_ORDER = {
    "BACKGROUND",
    "LOW",
    "MEDIUM",
    "HIGH",
    "DIALOG",
    "FULLSCREEN",
    "FULLSCREEN_DIALOG",
    "TOOLTIP",
}

local hovered = {}

-- Edit Mode's Transparency setting stays the authority for the hovered state.
-- The idle state is a factor of it, so moving that slider keeps working and the
-- two states never drift apart.
function Presence.ComputeAlpha(editModeAlpha, idleFactor, isHovered)
    if isHovered then
        return editModeAlpha
    end

    return editModeAlpha * idleFactor
end

function Presence.ApplyAlpha(window)
    window:SetAlpha(Presence.ComputeAlpha(DamageMeter:GetWindowAlpha(), ns.db.idleAlpha, hovered[window]))
end

local function ApplyAlphaToAll()
    ns.ForEachSessionWindow(Presence.ApplyAlpha)
end

-- The source window template pins frameStrata="HIGH", which overrides
-- inheritance from its parent. Raising the meter without raising it too would
-- push the spell breakdown behind the bars.
function Presence.NextStrataUp(strata)
    for index, name in ipairs(Presence.STRATA_ORDER) do
        if name == strata then
            return Presence.STRATA_ORDER[math.min(index + 1, #Presence.STRATA_ORDER)]
        end
    end

    return "HIGH"
end

function Presence.ApplyStrata()
    local strata = ns.db.strata

    DamageMeter:SetFrameStrata(strata)

    ns.ForEachSessionWindow(function(window)
        window:GetSourceWindow():SetFrameStrata(Presence.NextStrataUp(strata))
    end)
end

function Presence.Enable()
    -- OnEnter sets the MouseOver reason; the window's own OnUpdate clears it
    -- once the mouse is off both the window and its resize button. One hook
    -- gives us both edges without an OnUpdate of our own.
    local function OnSetOnUpdateReason(window, reason, enabled)
        if reason ~= "MouseOver" then
            return
        end

        hovered[window] = enabled and true or nil
        Presence.ApplyAlpha(window)
    end

    -- Mixin hook for windows created later, instance hooks for the ones that
    -- already exist and carry their own copy of SetOnUpdateReason.
    hooksecurefunc(DamageMeterSessionWindowMixin, "SetOnUpdateReason", OnSetOnUpdateReason)
    ns.ForEachSessionWindow(function(window)
        ns.HookInstance(window, "SetOnUpdateReason", OnSetOnUpdateReason)
    end)

    -- An Edit Mode transparency change pushes a raw alpha onto every window;
    -- re-apply through our path so the idle state survives it. DamageMeter
    -- already exists, so this is an instance hook.
    ns.HookInstance(DamageMeter, "OnWindowAlphaChanged", ApplyAlphaToAll)

    ApplyAlphaToAll()
    Presence.ApplyStrata()
end

ns.RegisterModule("Presence", Presence)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the same command as Step 2. Expected: all format, snap and presence tests pass.

- [ ] **Step 5: Verify in game**

`/reload`. Expected:

1. With the mouse away, the meter sits at roughly 40 percent of its Edit Mode transparency.
2. Moving the mouse over it brings it to the Edit Mode value, and moving away dims it again.
3. Hovering a bar opens the breakdown and both stay at full alpha while the cursor is on either.
4. Changing Transparency in Edit Mode still works, and both states move with it.
5. A window set to uninteractable from the settings dropdown stays dim - expected, since its mouse is disabled.
6. Setting `DamageMeterTweaksDB.strata = "DIALOG"` and reloading puts the meter above other frames, with the breakdown still in front of the bars.

- [ ] **Step 6: Commit**

```bash
git add Presence.lua tests/presence_spec.lua
git commit -m "feat: idle transparency and configurable strata"
```

---

### Task 8: Key bindings

**Files:**
- Create: `Bindings.xml`
- Modify: `Core.lua` (add the binding handlers and the binding name globals)

**Interfaces:**
- Consumes: `ns.Print`, `ns.charDb` from Task 1.
- Produces: globals `DamageMeterTweaks_ToggleMeter()`, `DamageMeterTweaks_ToggleWindow(index)`.

`Bindings.xml` at the addon root is loaded automatically and must not be listed in the TOC.

- [ ] **Step 1: Write `Bindings.xml`**

```xml
<Bindings>
    <Binding name="DAMAGEMETERTWEAKS_TOGGLE" header="DAMAGEMETERTWEAKS_HEADER" category="DamageMeterTweaks">
        DamageMeterTweaks_ToggleMeter()
    </Binding>
    <Binding name="DAMAGEMETERTWEAKS_WINDOW2" category="DamageMeterTweaks">
        DamageMeterTweaks_ToggleWindow(2)
    </Binding>
    <Binding name="DAMAGEMETERTWEAKS_WINDOW3" category="DamageMeterTweaks">
        DamageMeterTweaks_ToggleWindow(3)
    </Binding>
</Bindings>
```

- [ ] **Step 2: Add the handlers to `Core.lua`**

Insert above the `local bootstrap = CreateFrame("Frame")` line:

```lua
BINDING_HEADER_DAMAGEMETERTWEAKS_HEADER = "DamageMeterTweaks"
BINDING_NAME_DAMAGEMETERTWEAKS_TOGGLE = "Show or hide the damage meter"
BINDING_NAME_DAMAGEMETERTWEAKS_WINDOW2 = "Toggle meter window 2"
BINDING_NAME_DAMAGEMETERTWEAKS_WINDOW3 = "Toggle meter window 3"

-- The primary window cannot be hidden (CanHideSessionWindow is false for it),
-- so the only way to put the whole meter away is the CVar the settings
-- checkbox uses.
function DamageMeterTweaks_ToggleMeter()
    local enabled = C_CVar.GetCVarBool("damageMeterEnabled")
    local ok, err = pcall(C_CVar.SetCVar, "damageMeterEnabled", enabled and "0" or "1")

    if not ok then
        ns.Print("cannot toggle the meter right now: " .. tostring(err))
    end
end

function DamageMeterTweaks_ToggleWindow(index)
    if not ns.IsAvailable() then
        return
    end

    local window = DamageMeter:GetSessionWindow(index)

    if window and window:IsShown() then
        DamageMeter:HideSessionWindow(window)
    else
        DamageMeter:ShowNewSecondarySessionWindow()
    end
end
```

`ShowNewSecondarySessionWindow` reuses the first free secondary slot rather than exactly `index`. With three windows the difference is invisible in practice, and using the public method avoids reaching into `windowDataList`.

- [ ] **Step 3: Verify in game**

`/reload`, then Options - Key Bindings. Expected:

1. A DamageMeterTweaks category exists with three bindings.
2. Bound out of combat, the toggle hides and shows the whole meter.
3. The window bindings show and hide the secondary windows.
4. Pressed in combat, the toggle either works or prints a message - it never throws. Which one it is was determined by Task 1's probe.

- [ ] **Step 4: Commit**

```bash
git add Bindings.xml Core.lua
git commit -m "feat: key bindings for the meter and its windows"
```

---

### Task 9: Settings panel

**Files:**
- Create: `Config.lua`

**Interfaces:**
- Consumes: `ns.db`, `ns.charDb`, `ns.ContextMenu.CATEGORIES`, `ns.ContextMenu.GetTypeName`, `ns.Presence.STRATA_ORDER`, `ns.Presence.ApplyStrata`, `ns.Presence.ApplyAlpha`, `ns.Snap.SetLink`, `ns.Snap.ClearLink`, `ns.Snap.PushSize`, `ns.Snap.Clamp`.
- Produces: `ns.Config.Open()`, called by `/dmt` with no argument.

- [ ] **Step 1: Write the behaviour half of `Config.lua`**

```lua
local addonName, ns = ...

ns.Config = {}
local Config = ns.Config

local category

local function AddCheckbox(variableKey, name, tooltip, onChange)
    local setting = Settings.RegisterProxySetting(category, "DMT_" .. variableKey,
        Settings.VarType.Boolean, name, ns.defaults[variableKey],
        function() return ns.db[variableKey] end,
        function(value)
            ns.db[variableKey] = value
            if onChange then
                onChange()
            end
        end)

    Settings.CreateCheckbox(category, setting, tooltip)
end

local function AddSlider(variableKey, name, tooltip, minimum, maximum, step, onChange)
    local setting = Settings.RegisterProxySetting(category, "DMT_" .. variableKey,
        Settings.VarType.Number, name, ns.defaults[variableKey],
        function() return ns.db[variableKey] end,
        function(value)
            ns.db[variableKey] = value
            if onChange then
                onChange()
            end
        end)

    local options = Settings.CreateSliderOptions(minimum, maximum, step)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)

    Settings.CreateSlider(category, setting, options, tooltip)
end

local function BuildBehaviourOptions()
    AddCheckbox("hover", "Open details on hover",
        "Hovering a bar opens the spell breakdown instead of requiring a click.")

    AddSlider("hoverDelay", "Hover delay",
        "How long the cursor must rest on a bar before the breakdown opens.", 0, 1, 0.05)

    AddCheckbox("menu", "Right-click menu",
        "Right-clicking a bar opens a menu for the tracked type, the segment and window actions.")

    AddCheckbox("format", "Readable numbers",
        "Show 56.72M instead of 56716 K. Only applies once the values stop being secret, which is after combat.")

    AddCheckbox("snap", "Snap windows together",
        "Dragging a window near another attaches it, and they move and resize together.")

    AddSlider("snapThreshold", "Snap distance",
        "How close an edge must be, in pixels, before it snaps.", 5, 40, 1)

    AddSlider("idleAlpha", "Idle transparency",
        "How visible the meter is when the mouse is not on it, as a fraction of the Edit Mode transparency.",
        0.1, 1, 0.05, function()
            ns.ForEachSessionWindow(ns.Presence.ApplyAlpha)
        end)

    local strataSetting = Settings.RegisterProxySetting(category, "DMT_strata",
        Settings.VarType.String, "Layer", ns.defaults.strata,
        function() return ns.db.strata end,
        function(value)
            ns.db.strata = value
            ns.Presence.ApplyStrata()
        end)

    Settings.CreateDropdown(category, strataSetting, function()
        local container = Settings.CreateControlTextContainer()
        for _, strata in ipairs(ns.Presence.STRATA_ORDER) do
            container:Add(strata, strata)
        end
        return container:GetData()
    end, "Which layer the meter draws on. Raise it if another addon covers it.")
end

function Config.Open()
    Settings.OpenToCategory(category:GetID())
end

function Config.Enable()
    category = Settings.RegisterVerticalLayoutCategory("DamageMeterTweaks")
    BuildBehaviourOptions()
    Settings.RegisterAddOnCategory(category)

    ns.Config.BuildWindowPanel()
end

ns.RegisterModule("Config", Config)
```

- [ ] **Step 2: Add the window table as a canvas subcategory**

Append to `Config.lua`, above `ns.RegisterModule`:

```lua
local windowPanel

local function WindowRowValues(index)
    local window = DamageMeter:GetSessionWindow(index)
    local isPrimary = index == 1
    local link = ns.charDb.links[index]

    return window, isPrimary, link
end

local function RefreshWindowPanel()
    if not windowPanel or not windowPanel:IsShown() then
        return
    end

    for index = 1, 3 do
        local row = windowPanel.rows[index]
        local window, isPrimary, link = WindowRowValues(index)
        local shown = window ~= nil and window:IsShown()

        row.Title:SetText(isPrimary and "Window 1 (primary)" or ("Window " .. index))
        row.Shown:SetChecked(shown)
        row.Shown:SetEnabled(not isPrimary)

        if shown then
            row.Size:SetText(("%d x %d"):format(window:GetWidth(), window:GetHeight()))
        else
            row.Size:SetText("-")
        end

        row.Note:SetText(isPrimary and "Size and position are controlled by Edit Mode." or "")
        row.Link:SetText(link and ("attached to window " .. link.to) or "not attached")
        row.MatchWidth:SetChecked(link and link.matchWidth or false)
        row.MatchWidth:SetEnabled(link ~= nil and not isPrimary)
        row.MatchHeight:SetChecked(link and link.matchHeight or false)
        row.MatchHeight:SetEnabled(link ~= nil and not isPrimary)
        row.Detach:SetEnabled(link ~= nil)
    end
end

function Config.BuildWindowPanel()
    -- A plain frame, not SettingsListTemplate: the canvas subcategory owns the
    -- scrolling and sizing, and the template would add a list we do not use.
    windowPanel = CreateFrame("Frame")
    windowPanel:SetSize(600, 240)
    windowPanel:Hide()
    windowPanel.rows = {}

    for index = 1, 3 do
        local row = CreateFrame("Frame", nil, windowPanel)
        row:SetSize(560, 60)
        row:SetPoint("TOPLEFT", windowPanel, "TOPLEFT", 20, -20 - (index - 1) * 70)

        row.Title = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        row.Title:SetPoint("TOPLEFT")

        row.Shown = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.Shown:SetPoint("TOPLEFT", row.Title, "BOTTOMLEFT", 0, -2)
        row.Shown:SetScript("OnClick", function(self)
            DamageMeterTweaks_ToggleWindow(index)
            RefreshWindowPanel()
        end)

        row.Size = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.Size:SetPoint("LEFT", row.Shown, "RIGHT", 40, 0)

        row.Note = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        row.Note:SetPoint("LEFT", row.Size, "RIGHT", 20, 0)

        row.Link = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.Link:SetPoint("TOPLEFT", row.Shown, "BOTTOMLEFT", 0, -4)

        row.MatchWidth = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.MatchWidth:SetPoint("LEFT", row.Link, "RIGHT", 20, 0)
        row.MatchWidth.text = row.MatchWidth:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.MatchWidth.text:SetPoint("LEFT", row.MatchWidth, "RIGHT", 2, 0)
        row.MatchWidth.text:SetText("match width")
        row.MatchWidth:SetScript("OnClick", function(self)
            local link = ns.charDb.links[index]
            if link then
                link.matchWidth = self:GetChecked()
                ns.Snap.PushSize(link.to)
                RefreshWindowPanel()
            end
        end)

        row.MatchHeight = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.MatchHeight:SetPoint("LEFT", row.MatchWidth.text, "RIGHT", 20, 0)
        row.MatchHeight.text = row.MatchHeight:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.MatchHeight.text:SetPoint("LEFT", row.MatchHeight, "RIGHT", 2, 0)
        row.MatchHeight.text:SetText("match height")
        row.MatchHeight:SetScript("OnClick", function(self)
            local link = ns.charDb.links[index]
            if link then
                link.matchHeight = self:GetChecked()
                ns.Snap.PushSize(link.to)
                RefreshWindowPanel()
            end
        end)

        row.Detach = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.Detach:SetSize(80, 22)
        row.Detach:SetPoint("LEFT", row.MatchHeight.text, "RIGHT", 20, 0)
        row.Detach:SetText("Detach")
        row.Detach:SetScript("OnClick", function()
            ns.Snap.ClearLink(index)
            RefreshWindowPanel()
        end)

        windowPanel.rows[index] = row
    end

    windowPanel:SetScript("OnShow", RefreshWindowPanel)

    local subcategory = Settings.RegisterCanvasLayoutSubcategory(category, windowPanel, "Windows")
    Settings.RegisterAddOnCategory(subcategory)
end
```

The panel shows link state and lets a link be dropped or its match flags changed. Attaching is done by dragging, which is the interaction the snap feature exists for; a dropdown that duplicates it would be a second way to do the same thing.

- [ ] **Step 3: Wire `/dmt` with no argument to the panel**

In `Core.lua`, change the final `else` branch of `HandleSlashCommand` to:

```lua
    elseif command == "" then
        ns.Config.Open()
    else
        ns.Print("commands: probe, hover, menu, format, snap")
    end
```

- [ ] **Step 4: Verify in game**

`/reload`, then `/dmt`. Expected:

1. The panel opens with the behaviour options and a Windows subcategory.
2. Every checkbox and slider changes behaviour immediately and survives a reload.
3. The Layer dropdown moves the meter, and the breakdown stays in front of the bars.
4. The Windows page lists three rows; window 1 says its size is controlled by Edit Mode and its Shown box is disabled.
5. Snapping two windows and reopening the page shows the link and the match flags.
6. Detach drops the link, and the window then moves freely.

- [ ] **Step 5: Run the tests one final time**

Run:

```bash
MSYS_NO_PATHCONV=1 wsl bash -lc 'cd "/mnt/g/Games/World of Warcraft/_retail_/Interface/AddOns/DamageMeterTweaks" && ~/luaenv/bin/busted tests'
```

Expected: all format and snap tests pass.

- [ ] **Step 6: Commit**

```bash
git add Config.lua Core.lua
git commit -m "feat: settings panel with behaviour options and a window table"
```

---

## Notes for the executor

- Blizzard's damage meter files are readable at `G:/Games/wow-ui-source-live/Interface/AddOns/Blizzard_DamageMeter/`. Read them before changing a hook; every mixin method named in this plan exists there.
- If a hook target has been renamed by a patch, the addon must degrade rather than error: `ns.IsAvailable()` in `Core.lua` is the single place that decides whether anything installs at all. Extend that check rather than scattering `if X then` guards.
- The `Settings` API names used in Task 9 (`RegisterProxySetting`, `CreateCheckbox`, `CreateSlider`, `CreateDropdown`, `RegisterCanvasLayoutSubcategory`) are the current ones; if any signature has drifted, check `Blizzard_Settings` in the UI source rather than guessing.
