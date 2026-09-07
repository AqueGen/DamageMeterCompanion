local addonName, ns = ...

-- The registry of Blizzard's meter windows: which exist, in order, and the
-- few operations on them that are clean on 12.x.
--
-- Everything here is C-side frame state or a call whose Blizzard body writes
-- nothing its render path reads back. What is deliberately absent, and why,
-- is in docs/DECISIONS.md: showing a window from addon code, creating windows
-- of our own, and switching a window's type or segment all run Blizzard's
-- Refresh inside our taint, and that poisons the window until /reload.
ns.Windows = {}
local Windows = ns.Windows

-- Blizzard's own MAX_DAMAGE_METER_SESSION_WINDOWS, which is file-local to
-- DamageMeter.lua.
Windows.BLIZZARD_WINDOW_COUNT = 3

function Windows.SortedIndices(set)
    local indices = {}

    for index in pairs(set) do
        table.insert(indices, index)
    end

    table.sort(indices)

    return indices
end

function Windows.Get(index)
    if type(index) ~= "number" then
        return nil
    end

    return DamageMeter:GetSessionWindow(index)
end

-- Only windows whose frame exists. Blizzard builds a secondary window's frame
-- the first time it is shown, so a slot that has never been opened is absent.
function Windows.Indices()
    local present = {}

    for index = 1, Windows.BLIZZARD_WINDOW_COUNT do
        if DamageMeter:GetSessionWindow(index) then
            present[index] = true
        end
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

function Windows.IsIndexShown(index)
    local window = Windows.Get(index)
    return window ~= nil and window:IsShown()
end

-- Hiding is clean: HideSessionWindow ends in Hide(), and the OnHide it runs
-- only clears fields. Showing is not - see Windows.Show.
function Windows.Hide(index)
    local window = Windows.Get(index)

    if window and index ~= 1 and window:IsShown() and DamageMeter:CanHideSessionWindow(window) then
        DamageMeter:HideSessionWindow(window)
    end
end

-- Showing from addon code is the one thing here that is not clean, and it is
-- offered anyway because the panel is where the player expects to switch a
-- window on. SetupSessionWindow runs Blizzard's whole setup - two refreshes -
-- inside our taint, and that window then logs a Secret-comparison warning per
-- row in every fight until the UI is reloaded. A reload clears it entirely:
-- Blizzard restores the window itself at login, untainted, because its saved
-- data says shown. So the caller prompts for one.
--
-- Addressed by index, not through ShowNewSecondarySessionWindow: that picks
-- the first free slot, so on a character that has never opened a second
-- window "show 3" would open 2.
function Windows.Show(index)
    if index == 1 or Windows.IsIndexShown(index) or InCombatLockdown() then
        return false
    end

    if not DamageMeter:CanShowNewSecondarySessionWindow() then
        return false
    end

    local window = DamageMeter:GetSessionWindow(index)
    local windowData = DamageMeter:GetWindowDataList()[index]

    if windowData then
        DamageMeter:SetupSessionWindow(index, windowData)

        -- SetupSessionWindow alone does not record that the window is showing;
        -- the function Blizzard uses for that is file-local. Re-setting the
        -- lock to the value it already has is a no-op that runs the same save.
        DamageMeter:SetSessionWindowLocked(window or DamageMeter:GetSessionWindow(index), windowData.locked or false)
    else
        DamageMeter:CreateWindowData(index)
    end

    return true
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

-- Routes window 1 through Edit Mode (the only path that can move its size)
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

function Windows.Enable()
    -- A link naming a slot that has no frame yet is left alone: Blizzard's
    -- windows come back when the player shows them again, and Snap's
    -- SetupSessionWindow hook re-applies the link at that moment.
end

ns.RegisterModule("Windows", Windows)
