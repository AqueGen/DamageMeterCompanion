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

-- Left pins the breakdown, right opens the menu. Blizzard's own OnClick never
-- fires because Attach unregisters the frame's clicks; that is what lets a
-- right-click be ours instead of also pinning.
local function OnMouseDown(window, frame, mouseButtonName)
    local elementData = ElementDataOf(window, frame)
    if not elementData then
        return
    end

    if mouseButtonName == "RightButton" then
        if ns.db.menu then
            ns.ContextMenu.Open(frame, window)
        end
        return
    end

    if mouseButtonName == "LeftButton" then
        local sticky = true
        window:ShowSourceWindow(elementData, sticky)
    end
end

local function Attach(window, frame)
    -- Every sweep, not once: SetupEntry re-registers clicks whenever the scroll
    -- box re-acquires the frame, and this is the cheapest way to win that race
    -- within one interval.
    frame:RegisterForClicks()

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

function Entries.Enable()
    ns.OnSweep(Entries.Sweep)
end

ns.RegisterModule("Entries", Entries)
