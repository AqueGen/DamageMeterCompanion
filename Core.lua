local addonName, ns = ...

ns.defaults = {
    format = true,
    snap = true,
    snapThreshold = 50,
    idleAlpha = 0.4,
    strata = "MEDIUM",
}

ns.charDefaults = {
    links = {},
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

-- One reload prompt per session. A lock, a size or a show that goes through
-- Blizzard's own code runs it inside our taint (docs/DECISIONS.md), and a
-- reload is what clears that: Blizzard restores the lock, the size and the
-- window itself at login, untainted. Asking once is enough - the taint does
-- not get worse, and the popup would otherwise follow every keystroke.
local reloadRequested = false

StaticPopupDialogs["DAMAGEMETERCOMPANION_RELOAD"] = {
    text = "DamageMeterCompanion changed a window's %s through Blizzard's code. Until the UI is reloaded the meter carries the addon's taint and logs a warning per row in combat. Reload now?",
    button1 = RELOADUI,
    button2 = CANCEL,
    OnAccept = function() ReloadUI() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function ns.RequestReload(what)
    if reloadRequested then
        return
    end

    reloadRequested = true
    StaticPopup_Show("DAMAGEMETERCOMPANION_RELOAD", what)
end

function ns.IsAvailable()
    return DamageMeter ~= nil
        and DamageMeterSessionWindowMixin ~= nil
        and DamageMeterEntryMixin ~= nil
end

-- Rows that carry a death recap render a timestamp rather than a number, so
-- the formatting has to leave them alone. deathRecapID is documented
-- NeverSecret, so reading it in combat is safe.
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

-- One timer for every module that repaints or re-attaches from outside
-- Blizzard's render pass. Five times a second is the ceiling of how long
-- Blizzard's own state can show before ours is on top of it again, and the
-- work per tick is a walk over the visible bars.
ns.SWEEP_INTERVAL = 0.2

local sweeps = {}
local frameSweeps = {}

function ns.OnSweep(func)
    table.insert(sweeps, func)
end

-- Every frame, not every interval. OnUpdate runs after the frame's events
-- have been handled and before it is drawn, so work done here lands on top of
-- whatever Blizzard's event handlers just did and is what the player sees.
-- The callback decides for itself whether this frame needs it.
function ns.OnFrame(func)
    table.insert(frameSweeps, func)
end

local function StartSweeps()
    local elapsed = 0
    local driver = CreateFrame("Frame", nil, UIParent)

    local function OnUpdate(_, delta)
        -- The engine runs OnUpdate handlers in registration order, and a
        -- ScrollBox that defers a full update registers its own handler in the
        -- same frame - after ours, so its repaint would land on top of our
        -- paint. Re-registering every frame keeps ours at the end of the list.
        driver:SetScript("OnUpdate", nil)
        driver:SetScript("OnUpdate", driver.OnUpdate)

        for _, func in ipairs(frameSweeps) do
            func()
        end

        elapsed = elapsed + delta

        if elapsed < ns.SWEEP_INTERVAL then
            return
        end

        elapsed = 0

        for _, func in ipairs(sweeps) do
            func()
        end
    end

    driver.OnUpdate = OnUpdate
    driver:SetScript("OnUpdate", OnUpdate)
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

    -- The rows above hold whatever Blizzard fetched last, which was probably
    -- during combat. This is a fetch made right now, and it is the one that
    -- decides whether anything can become readable again after a pull.
    local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType,
        Enum.DamageMeterSessionType.Current, Enum.DamageMeterType.DamageDone)
    local fresh = ok and session and session.combatSources and session.combatSources[1]

    if not fresh then
        ns.Print("fresh fetch: no current session data" .. (ok and "" or (" - " .. tostring(session))))
    else
        ns.Print(("fresh fetch right now: sourceGUID secret %s, totalAmount secret %s, name secret %s"):format(
            tostring(issecretvalue(fresh.sourceGUID)),
            tostring(issecretvalue(fresh.totalAmount)),
            tostring(issecretvalue(fresh.name))))
    end

    local current = C_CVar.GetCVar("damageMeterEnabled")
    local ok, err = pcall(C_CVar.SetCVar, "damageMeterEnabled", current)
    ns.Print("SetCVar(damageMeterEnabled) allowed: " .. tostring(ok) .. (ok and "" or (" - " .. tostring(err))))
end

-- One line per window: what the addon can see about it, for bug reports.
function ns.Diagnose()
    ns.Print(("snap %s, threshold %d, format %s"):format(
        tostring(ns.db.snap), ns.db.snapThreshold, tostring(ns.db.format)))

    for _, index in ipairs(ns.Windows.Indices()) do
        local window = ns.Windows.Get(index)
        local left, bottom, width, height = window:GetRect()
        local _, relativeTo = window:GetPoint(1)
        local link = ns.charDb.links[index]

        ns.Print(("window %d: shown %s, locked %s, rect %s,%s %sx%s, anchored to %s, link %s"):format(
            index,
            tostring(window:IsShown()),
            tostring(window:IsLocked()),
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
    elseif command == "snap" or command == "format" then
        ns.db[command] = not ns.db[command]
        ns.Print(command .. ": " .. tostring(ns.db[command]))
    elseif command == "" then
        ns.Config.Open()
    else
        ns.Print("commands: diag, probe, format, snap")
    end
end

BINDING_NAME_DAMAGEMETERCOMPANION_TOGGLE = "Show or hide the damage meter"
BINDING_NAME_DAMAGEMETERCOMPANION_HIDEALL = "Hide all extra windows"
BINDING_NAME_DAMAGEMETERCOMPANION_RESET = "Reset damage meter data"

-- The primary window cannot be hidden (CanHideSessionWindow is false for it),
-- so the only way to put the whole meter away is the CVar the settings
-- checkbox uses. The CVar callback runs from Blizzard's registry, not from our
-- stack, which is what keeps this clean.
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

-- Hide only, never show: showing a window from addon code runs Blizzard's
-- setup inside our taint and poisons that window until /reload. Bringing one
-- back is the meter's own gear menu, Show new window - untainted.
function DamageMeterCompanion_HideAll()
    if not ns.IsAvailable() then
        return
    end

    for _, index in ipairs(ns.Windows.Indices()) do
        ns.Windows.Hide(index)
    end
end

-- Same call the gear dropdown's Reset makes. Nothing Secret is touched.
function DamageMeterCompanion_ResetData()
    if ns.IsAvailable() then
        C_DamageMeter.ResetAllCombatSessions()
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
    StartSweeps()

    SLASH_DAMAGEMETERCOMPANION1 = "/dmc"
    SLASH_DAMAGEMETERCOMPANION2 = "/dmt"
    SlashCmdList["DAMAGEMETERCOMPANION"] = HandleSlashCommand
end)
