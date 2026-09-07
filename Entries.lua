local addonName, ns = ...

-- Hover-to-open and the right-click menu, attached to Blizzard's entry frames
-- from our own sweep rather than from a hook on InitEntry.
--
-- Why not the hook: a hooksecurefunc on anything Blizzard calls while it
-- renders the list runs their body inside our taint, and their entry setup
-- compares Secret fields - the game logs a warning per row per refresh in
-- combat. Confirmed in game with the hook alone installed.
--
-- Why once per frame is enough: SetupEntry registers clicks only when a frame
-- is acquired, and Blizzard never sets OnEnter, OnLeave or OnMouseDown on an
-- entry, so what we attach stays attached. The element data is read at event
-- time through the accessor the scroll box puts on every acquired frame, so a
-- handler is never holding a stale row.
ns.Entries = {}
local Entries = ns.Entries

-- Keyed by frame, weakly. A field on Blizzard's frame would be a write from
-- tainted code into a table their render pass reads.
local attached = setmetatable({}, { __mode = "k" })

local pendingTimer

local function CancelPending()
    if pendingTimer then
        pendingTimer:Cancel()
        pendingTimer = nil
    end
end

-- The scroll box hands acquired frames a GetElementData; the local player row
-- sits outside the scroll box and is initialised by index instead.
local function ElementDataOf(window, frame)
    if frame.GetElementData then
        return frame:GetElementData()
    end

    if frame == window:GetLocalPlayerEntry() and window.localPlayerIndex then
        return window:GetScrollBox():FindElementData(window.localPlayerIndex)
    end

    return nil
end

local function OnEnter(window, frame)
    if not ns.db.hover then
        return
    end

    local elementData = ElementDataOf(window, frame)
    if not elementData or ns.HasDeathRecap(elementData) then
        return
    end

    -- ShowSourceWindow hands the row's GUID to
    -- C_DamageMeter.GetCombatSessionSourceFromType, which is documented
    -- SecretArguments = "AllowedWhenUntainted": a Secret GUID from our stack
    -- is a hard error, not a warning. The GUID is Secret while combat
    -- restrictions are on and stays Secret in the data Blizzard fetched then,
    -- until RefreshAfterCombat below fetches again. Hover simply waits.
    if issecretvalue(elementData.sourceGUID) or issecretvalue(elementData.sourceCreatureID) then
        return
    end

    CancelPending()
    pendingTimer = C_Timer.NewTimer(ns.db.hoverDelay, function()
        pendingTimer = nil

        -- A pinned breakdown was put there by a click, and this one window
        -- serves both roles, so re-showing it would silently un-pin it. Only
        -- while it is on screen, though: Blizzard's OnHide clears the source
        -- but not the sticky flag, so a breakdown pinned once and then closed
        -- stays flagged for the session.
        local sourceWindow = window:GetSourceWindow()

        if frame:IsMouseOver()
            and frame:IsVisible()
            and not (sourceWindow:IsShown() and sourceWindow:IsSticky()) then
            local sticky = false
            window:ShowSourceWindow(elementData, sticky)
        end
    end)
end

local function OnLeave(window, frame)
    if not ns.db.hover then
        return
    end

    CancelPending()

    local sourceWindow = window:GetSourceWindow()
    if sourceWindow:IsShown() and not sourceWindow:IsSticky() then
        -- One frame of grace so moving the cursor from the bar into the
        -- breakdown, which sits flush against the window edge, does not
        -- close it.
        C_Timer.After(0, function()
            if sourceWindow:IsShown()
                and not sourceWindow:IsSticky()
                and not sourceWindow:IsMouseOver()
                and not frame:IsMouseOver() then
                window:HideSourceWindow()
            end
        end)
    end
end

-- Right opens the menu. Left is deliberately left to Blizzard's own OnClick:
-- it opens the breakdown untainted, so it works in combat where a call of
-- ours could not (see OnEnter), and Shift-click pins, which is their
-- convention. Attach keeps the left button registered and drops the right one
-- so a right-click reaches us without also reaching them.
local function OnMouseDown(window, frame, mouseButtonName)
    if mouseButtonName ~= "RightButton" or not ns.db.menu then
        return
    end

    if ElementDataOf(window, frame) then
        ns.ContextMenu.Open(frame, window)
    end
end

local function Attach(window, frame)
    -- Every sweep, not once: SetupEntry re-registers both buttons whenever
    -- the scroll box re-acquires the frame, and this is the cheapest way to
    -- win that race within one interval.
    frame:RegisterForClicks("LeftButtonDown")

    if attached[frame] then
        return
    end

    attached[frame] = true

    frame:HookScript("OnEnter", function() OnEnter(window, frame) end)
    frame:HookScript("OnLeave", function() OnLeave(window, frame) end)
    frame:HookScript("OnMouseDown", function(_, mouseButtonName) OnMouseDown(window, frame, mouseButtonName) end)
end

function Entries.Sweep()
    if not ns.db.hover and not ns.db.menu then
        return
    end

    ns.Windows.ForEach(function(window)
        if not window:IsShown() then
            return
        end

        window:GetScrollBox():ForEachFrame(function(frame)
            Attach(window, frame)
        end)

        local localPlayerEntry = window:GetLocalPlayerEntry()
        if localPlayerEntry then
            Attach(window, localPlayerEntry)
        end
    end)
end

-- Blizzard's window re-fetches only on the meter's own events, which arrive in
-- combat, so after a pull its rows still carry the Secret GUIDs fetched then
-- and hover would stay dead until the next pull refreshed them. One fetch of
-- our own once the restrictions lift hands back plain values; out of combat
-- C_DamageMeter returns them (SecretWhenInCombat), and the only comparisons
-- Refresh makes are of values that are Secret only while restricted.
--
-- Except through an open breakdown: it holds the Secret GUID it was opened
-- with, and Refresh would compare a fresh row against it. Closing it first is
-- the one thing that is always safe.
function Entries.RefreshAfterCombat()
    if InCombatLockdown() then
        return
    end

    ns.Windows.ForEach(function(window)
        if not window:IsShown() then
            return
        end

        local sourceWindow = window:GetSourceWindow()
        if sourceWindow:IsShown() and issecretvalue(sourceWindow.sourceGUID) then
            window:HideSourceWindow()
        end

        pcall(window.Refresh, window, ScrollBoxConstants.RetainScrollPosition)
    end)
end

function Entries.Enable()
    ns.OnSweep(Entries.Sweep)

    local driver = CreateFrame("Frame")
    driver:RegisterEvent("PLAYER_REGEN_ENABLED")
    driver:SetScript("OnEvent", function()
        -- Next frame, not this one: the event fires as the lockdown lifts.
        C_Timer.After(0, Entries.RefreshAfterCombat)
    end)
end

ns.RegisterModule("Entries", Entries)
