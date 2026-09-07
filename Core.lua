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
