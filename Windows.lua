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

local function GetSaved()
    return ns.charDb.windows
end

local creationCallbacks = {}

-- A module that installs per-window hooks registers here, and gets called for
-- every window we build afterwards. Registering is idempotent from the
-- module's side: HookInstance is keyed by handler and HookScript chains, so a
-- window that was also covered by an enable-time walk is not hooked twice in
-- any way that matters.
function Windows.OnCreated(callback)
    table.insert(creationCallbacks, callback)
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

    -- Every module installs its per-window hooks once, when it is enabled.
    -- Blizzard's windows created later are covered because those modules also
    -- hook SetupSessionWindow, which never fires for ours - so without this a
    -- window added from the panel would have no drag hook, no hover, no
    -- right-click menu and no idle transparency.
    for _, callback in ipairs(creationCallbacks) do
        callback(window, index)
    end

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

ns.RegisterModule("Windows", Windows)
