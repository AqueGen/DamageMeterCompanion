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
    if type(index) ~= "number" then
        return nil
    end

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

    -- Alpha is deliberately absent: Presence owns it, and pushing the raw Edit
    -- Mode value here would yank every unhovered window to full opacity on any
    -- appearance change.
    window:SetBarHeight(Windows.ResolveAppearance(DamageMeter:GetBarHeight(), saved.barHeight))
    window:SetTextScale(Windows.ResolveAppearance(DamageMeter:GetTextScale(), saved.textSize))
end

function Windows.ApplyAppearanceToOurs()
    for index, window in pairs(ourWindows) do
        Windows.ApplyAppearance(window, index)
    end

    if ns.Presence then
        for _, window in pairs(ourWindows) do
            ns.Presence.ApplyAlpha(window)
        end
    end
end

local function Store(index, key, value)
    local saved = GetSaved()

    saved[index] = saved[index] or {}
    saved[index][key] = value
end

-- ClearLink is the second way one of our windows gets an absolute position,
-- and the only one that is not a drag, so it has to record it too or the
-- window returns to the cascade default next login.
function Windows.StorePosition(index, left, bottom)
    if not Windows.IsOurs(index) then
        return
    end

    Store(index, "left", left)
    Store(index, "bottom", bottom)
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

    -- sessionID is deliberately not persisted, for the reason Blizzard gives in
    -- SetSavedWindowData: it names one of the player's recent encounters and
    -- means nothing next session.
    Store(index, "sessionType", sessionType)
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
    -- The template is virtual XML, so it is not a Lua global and can only be
    -- asked about by name. This is also where a patch that renamed it would
    -- otherwise hard-error inside CreateFrame, during PLAYER_LOGIN, taking
    -- every other module's Enable down with it.
    if not C_XMLUtil.GetTemplateInfo("DamageMeterSessionWindowTemplate") then
        ns.Print("cannot create a window: the damage meter window template is missing")
        return nil
    end

    local saved = GetSaved()[index] or {}

    local window = CreateFrame("FRAME", "DamageMeterTweaksWindow" .. index, DamageMeter, "DamageMeterSessionWindowTemplate")

    window:SetDamageMeterOwner(Windows.proxyOwner, index)
    window:SetDamageMeterType(saved.damageMeterType or Enum.DamageMeterType.DamageDone)
    window:SetSession(saved.sessionType or DamageMeter:GetSessionType(), nil)
    window:SetMovable(true)
    window:SetResizable(true)

    -- Same rule as Blizzard's SetupSessionWindow: a later window renders above
    -- the ones before it.
    window:SetFrameLevel(index)

    -- Our own position rather than Blizzard's frame position cache, which is
    -- keyed on names it owns.
    window:SetUserPlaced(false)
    window:ClearAllPoints()
    if saved.left and saved.bottom then
        window:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", saved.left, saved.bottom)
    else
        -- Continues Blizzard's own series rather than restarting it, so our
        -- first window does not land exactly on top of its window 2.
        local offset = (index - 1) * 40
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
    -- Blizzard's owner reuses a hidden slot rather than allocating; without the
    -- same behaviour a hidden window is unreachable and its index is consumed
    -- for the rest of the character's life.
    for _, index in ipairs(Windows.SortedIndices(GetSaved())) do
        local saved = GetSaved()[index]

        -- Same guard as the Enable loop: a hand-edited entry at one of
        -- Blizzard's indices must never be built as one of ours.
        if Windows.IsOurs(index) and saved.shown == false then
            local window = ourWindows[index]
            if window then
                window:Show()
            elseif not BuildWindow(index) then
                -- The template is gone; leave the slot hidden rather than
                -- claim a window the player cannot see.
                return nil
            end

            saved.shown = true

            return index
        end
    end

    local taken = {}
    for index in pairs(GetSaved()) do
        taken[index] = true
    end
    for index in pairs(ourWindows) do
        taken[index] = true
    end

    local index = Windows.NextFreeIndex(taken)

    -- No saved entry until the frame actually exists, or a failed build would
    -- leave a window in the list that nothing can ever create.
    if not BuildWindow(index) then
        return nil
    end

    Store(index, "shown", true)

    if #Windows.Indices() > Windows.SOFT_CAP and not Windows.warnedAboutCount then
        Windows.warnedAboutCount = true
        ns.Print("that is a lot of windows - each one is a scroll box refreshed on every combat event, and the settings page does not scroll, so rows past the sixth or so will be off the page")
    end

    return index
end

function Windows.Remove(index)
    if not Windows.IsOurs(index) then
        return
    end

    -- The links come first, and the order is load bearing: ClearLink puts the
    -- dependent back on an absolute point read from its own GetRect, and a
    -- window still anchored to a frame we had already unparented has no rect to
    -- read - it would be left floating on a dead anchor, the exact state
    -- ClearLink exists to prevent.
    ns.charDb.links[index] = nil

    -- A link pointing at a window that no longer exists would anchor nothing.
    for otherIndex, link in pairs(ns.charDb.links) do
        if link.to == index then
            ns.Snap.ClearLink(otherIndex)
        end
    end

    local window = ourWindows[index]

    if window then
        window:Hide()
        window:SetParent(nil)
        ourWindows[index] = nil
    end

    GetSaved()[index] = nil
end

function Windows.Enable()
    for _, index in ipairs(Windows.SortedIndices(GetSaved())) do
        -- A hand-edited saved file naming one of Blizzard's indices would
        -- otherwise build a proxy-owned frame that Windows.Get never returns.
        if Windows.IsOurs(index) then
            BuildWindow(index)
        end
    end

    -- A link naming a window that no longer exists - removed through the panel,
    -- or lost to hand-edited saved variables - would anchor nothing and confuse
    -- the panel. Drop those once, at login, before anything reads the link
    -- table.
    --
    -- Only our own windows can vanish for good. Blizzard's 1-3 come back when
    -- the player shows them again, and Snap's SetupSessionWindow hook re-applies
    -- the link at that moment - pruning here would destroy it first.
    for index, link in pairs(ns.charDb.links) do
        local sourceGone = Windows.IsOurs(index) and not Windows.Get(index)
        local targetGone = Windows.IsOurs(link.to) and not Windows.Get(link.to)

        if sourceGone or targetGone then
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

-- Window 1's size is an Edit Mode setting, written by Blizzard's own resize
-- handle with exactly this call (EditModeSystemTemplates.lua:3438). Our stack
-- is tainted, so a refusal is reported rather than allowed to error.
local function SetPrimarySize(width, height)
    local window = Windows.Get(1)

    local ok, err = pcall(function()
        EditModeManagerFrame:OnSystemSettingChange(DamageMeter, Enum.EditModeDamageMeterSetting.FrameWidth, width)
        EditModeManagerFrame:OnSystemSettingChange(DamageMeter, Enum.EditModeDamageMeterSetting.FrameHeight, height)
    end)

    if not ok then
        ns.Print("Edit Mode would not accept that size right now: " .. tostring(err))
        return false
    end

    -- OnSystemSettingChange returns silently when the damage meter is not in
    -- the active layout, so a call that threw nothing still may have done
    -- nothing. The frame's own size is the only honest answer.
    if window and (math.floor(window:GetWidth() + 0.5) ~= math.floor(width + 0.5)
        or math.floor(window:GetHeight() + 0.5) ~= math.floor(height + 0.5)) then
        ns.Print("Edit Mode did not take that size - the damage meter may not be in the active layout")
        return false
    end

    return true
end

-- Routes window 1 through Edit Mode (the only path that can move its size,
-- per the constraint against calling SetSize on the primary window directly)
-- and everything else through SetSize. Either path trips OnSizeChanged, so
-- Snap.PushSize still propagates a matched size the same way a mouse resize
-- would.
function Windows.SetSize(index, width, height)
    local window = Windows.Get(index)

    if not window then
        return false
    end

    width = ns.Snap.Clamp(width, ns.Snap.MIN_WIDTH, ns.Snap.MAX_WIDTH)
    height = ns.Snap.Clamp(height, ns.Snap.MIN_HEIGHT, ns.Snap.MAX_HEIGHT)

    if index == 1 then
        -- No lock check for the primary window: Blizzard's owner refuses it for
        -- move and resize regardless of lock state, so it can never be locked in
        -- the first place, and Edit Mode is the only thing that sizes it.
        return SetPrimarySize(width, height)
    end

    if not window:CanMoveOrResize() then
        return false
    end

    window:SetSize(width, height)

    return true
end

ns.RegisterModule("Windows", Windows)
