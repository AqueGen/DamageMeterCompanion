local addonName, ns = ...

ns.defaults = {
    hover = true,
    hoverDelay = 0.15,
    menu = true,
    format = true,
    snap = true,
    snapThreshold = 50,
    idleAlpha = 0.4,
    strata = "MEDIUM",
}

-- windows is keyed by index and holds only our own indices: damageMeterType,
-- sessionType, sessionID, shown, locked, nonInteractive, minimized, width,
-- height, left, bottom, barHeight, textSize. Blizzard keeps its own for 1 to 3.
ns.charDefaults = {
    links = {},
    windows = {},
}

local modules = {}
local moduleOrder = {}

-- Modules register themselves at file scope and are enabled at PLAYER_LOGIN,
-- after the saved variables and the Blizzard damage meter both exist. Enable
-- order follows registration order, which follows the TOC. Windows.lua loads
-- second and so is enabled first, before anything walks the registry.
function ns.RegisterModule(name, module)
    if modules[name] then
        return
    end

    modules[name] = module
    table.insert(moduleOrder, module)
end

function ns.Print(message)
    print("|cff33ff99DamageMeterCompanion|r: " .. message)
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

-- Rows that carry a death recap render a timestamp rather than a number, and
-- clicking one opens the death recap UI instead of the breakdown. Both the
-- hover path and the formatting path have to leave them alone. deathRecapID is
-- documented NeverSecret, so reading it in combat is safe.
function ns.HasDeathRecap(source)
    return type(source.deathRecapID) == "number" and source.deathRecapID ~= 0
end

-- Mixin methods are copied onto a frame when the frame is created, so hooking
-- a mixin table only reaches frames created after the hook. Everything that
-- already exists at PLAYER_LOGIN has to be hooked one frame at a time. The
-- flag keeps a frame from being hooked twice.
-- Keyed by method and handler together: two modules legitimately hook the same
-- method with different handlers and both must install, and one module
-- legitimately hooks several methods with one shared handler - which a
-- handler-only key silently collapsed into a single hook.
function ns.HookInstance(frame, methodName, handler)
    frame.dmtHooks = frame.dmtHooks or {}

    local key = methodName .. tostring(handler)

    if frame.dmtHooks[key] then
        return
    end

    frame.dmtHooks[key] = true
    hooksecurefunc(frame, methodName, handler)
end

-- Every entry frame that exists right now, across the bars of each session
-- window, its off-screen local player entry, and its spell breakdown.
function ns.ForEachEntryFrame(func)
    ns.Windows.ForEach(function(window)
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

-- The addon shipped nothing under its old name, but it did run under it here,
-- so a player who used it before the rename would otherwise lose every window,
-- link and size. Adopt the old tables once, then drop the old ones so the
-- migration cannot run twice.
--
-- Both old variables are still declared in the TOC, because a SavedVariable
-- that is not declared is not loaded. Once a release has shipped under the new
-- name for a while, both declarations and this function come out.
local function AdoptOldSavedVariables()
    if DamageMeterCompanionDB == nil and DamageMeterTweaksDB ~= nil then
        DamageMeterCompanionDB = DamageMeterTweaksDB
    end

    if DamageMeterCompanionCharDB == nil and DamageMeterTweaksCharDB ~= nil then
        DamageMeterCompanionCharDB = DamageMeterTweaksCharDB
    end

    DamageMeterTweaksDB = nil
    DamageMeterTweaksCharDB = nil
end

local function InitializeSavedVariables()
    AdoptOldSavedVariables()

    DamageMeterCompanionDB = DamageMeterCompanionDB or {}
    DamageMeterCompanionCharDB = DamageMeterCompanionCharDB or {}

    ApplyDefaults(DamageMeterCompanionDB, ns.defaults)
    ApplyDefaults(DamageMeterCompanionCharDB, ns.charDefaults)

    -- The snap distance default moved from 15 to 50 after the first version
    -- shipped. ApplyDefaults only fills nils, so a profile that already carries
    -- the old default would never see the new one. Move it once, and only when
    -- it is still exactly the old default - a value the player chose is theirs.
    if not DamageMeterCompanionDB.snapThresholdDefaultMoved then
        DamageMeterCompanionDB.snapThresholdDefaultMoved = true

        if DamageMeterCompanionDB.snapThreshold == 15 then
            DamageMeterCompanionDB.snapThreshold = ns.defaults.snapThreshold
        end
    end

    ns.db = DamageMeterCompanionDB
    ns.charDb = DamageMeterCompanionCharDB
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

-- Reports, per window, whether our per-window hooks actually landed on it.
-- Written because the right-click menu and the number formatting both worked
-- on window 1 and on nothing else, and both are installed per frame - so the
-- question is which frames we reached, not what the handlers do.
function ns.Diagnose()
    ns.Print(("snap %s, threshold %d, menu %s, format %s, hover %s"):format(
        tostring(ns.db.snap), ns.db.snapThreshold,
        tostring(ns.db.menu), tostring(ns.db.format), tostring(ns.db.hover)))

    local indices = ns.Windows.Indices()
    ns.Print("registry sees " .. #indices .. " window(s)")

    for _, index in ipairs(indices) do
        local window = ns.Windows.Get(index)
        local hookCount = 0

        for _ in pairs(window.dmtHooks or {}) do
            hookCount = hookCount + 1
        end

        local entries, hookedEntries = 0, 0
        window:GetScrollBox():ForEachFrame(function(entry)
            entries = entries + 1
            if entry.dmtHooks then
                hookedEntries = hookedEntries + 1
            end
        end)

        local link = ns.charDb.links[index]
        local left, bottom, width, height = window:GetRect()

        -- The anchor is what settles the snapping report: a link that is present
        -- but whose frame is not actually anchored to its target means ApplyLink
        -- ran and something re-anchored afterwards, which is a different bug from
        -- a link that was never written.
        local _, relativeTo = window:GetPoint(1)

        ns.Print(("window %d: %s, shown %s, noninteractive %s, our hooks %d, drag hooked %s, entries %d, entry hooks %d"):format(
            index,
            ns.Windows.IsOurs(index) and "ours" or "blizzard",
            tostring(window:IsShown()),
            tostring(window:IsNonInteractive()),
            hookCount,
            tostring(window.dmtSizeHooked == true),
            entries,
            hookedEntries))

        ns.Print(("  rect %s,%s %sx%s, anchored to %s, link %s"):format(
            tostring(left and math.floor(left)), tostring(bottom and math.floor(bottom)),
            tostring(width and math.floor(width)), tostring(height and math.floor(height)),
            relativeTo and (relativeTo:GetName() or "unnamed") or "none",
            link and ("to " .. tostring(link.to)) or "none"))
    end
end

local function HandleSlashCommand(input)
    local command = string.lower(string.trim(input or ""))

    if command == "probe" then
        ns.Probe()
    elseif command == "diag" then
        ns.Diagnose()
    elseif command == "hover" or command == "snap" or command == "menu" or command == "format" then
        ns.db[command] = not ns.db[command]
        ns.Print(command .. ": " .. tostring(ns.db[command]))
    elseif command == "" then
        ns.Config.Open()
    else
        ns.Print("commands: diag, probe, hover, menu, format, snap")
    end
end

BINDING_NAME_DAMAGEMETERCOMPANION_TOGGLE = "Show or hide the damage meter"
BINDING_NAME_DAMAGEMETERCOMPANION_WINDOW2 = "Toggle meter window 2"
BINDING_NAME_DAMAGEMETERCOMPANION_WINDOW3 = "Toggle meter window 3"

-- The primary window cannot be hidden (CanHideSessionWindow is false for it),
-- so the only way to put the whole meter away is the CVar the settings
-- checkbox uses.
function DamageMeterCompanion_ToggleMeter()
    local enabled = C_CVar.GetCVarBool("damageMeterEnabled")

    -- SetCVar signals a refusal by returning false rather than by throwing, so
    -- both outcomes need reporting: without the second branch a refused toggle
    -- would be a key that silently does nothing.
    local ok, result = pcall(C_CVar.SetCVar, "damageMeterEnabled", enabled and "0" or "1")

    if not ok then
        ns.Print("cannot toggle the meter right now: " .. tostring(result))
    elseif result == false then
        ns.Print("the game refused to toggle the meter right now")
    end
end

-- Deliberately does not go through ShowNewSecondarySessionWindow: that picks
-- the first free slot, so on a character that has never opened a second window
-- the "window 3" key would open window 2. Addressing the index directly is
-- what the binding's own label promises.
function DamageMeterCompanion_ToggleWindow(index)
    if not ns.IsAvailable() or index == 1 then
        return
    end

    local window = DamageMeter:GetSessionWindow(index)

    if window and window:IsShown() then
        DamageMeter:HideSessionWindow(window)
        return
    end

    if not DamageMeter:CanShowNewSecondarySessionWindow() then
        return
    end

    local windowData = DamageMeter:GetWindowDataList()[index]

    if windowData then
        DamageMeter:SetupSessionWindow(index, windowData)

        -- SetupSessionWindow alone does not record that the window is showing;
        -- the function Blizzard uses for that is file-local. Re-setting the
        -- lock to the value it already has is a no-op that runs the same save.
        DamageMeter:SetSessionWindowLocked(window or DamageMeter:GetSessionWindow(index), windowData.locked or false)
    else
        -- CreateWindowData records the new window itself.
        DamageMeter:CreateWindowData(index)
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

    for _, module in ipairs(moduleOrder) do
        if module.Enable then
            module.Enable()
        end
    end

    -- /dmt stays as the second alias: it is what the addon answered to before
    -- the rename, and muscle memory outlives a name change.
    SLASH_DAMAGEMETERCOMPANION1 = "/dmc"
    SLASH_DAMAGEMETERCOMPANION2 = "/dmt"
    SlashCmdList["DAMAGEMETERCOMPANION"] = HandleSlashCommand
end)
