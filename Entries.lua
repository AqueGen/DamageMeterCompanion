local addonName, ns = ...

-- The right-click menu, attached to Blizzard's entry frames
-- from our own sweep rather than from a hook on InitEntry.
--
-- Why not the hook: a hooksecurefunc on anything Blizzard calls while it
-- renders the list runs their body inside our taint, and their entry setup
-- compares Secret fields - the game logs a warning per row per refresh in
-- combat. Confirmed in game with the hook alone installed.
--
-- Why once per frame is enough: SetupEntry registers clicks only when a frame
-- is acquired, and Blizzard never sets OnMouseDown on an
-- entry, so what we attach stays attached. The element data is read at event
-- time through the accessor the scroll box puts on every acquired frame, so a
-- handler is never holding a stale row.
ns.Entries = {}
local Entries = ns.Entries

-- Keyed by frame, weakly. A field on Blizzard's frame would be a write from
-- tainted code into a table their render pass reads.
local attached = setmetatable({}, { __mode = "k" })

local function ElementDataOf(window, frame)
    if frame.GetElementData then
        return frame:GetElementData()
    end

    if frame == window:GetLocalPlayerEntry() and window.localPlayerIndex then
        return window:GetScrollBox():FindElementData(window.localPlayerIndex)
    end

    return nil
end

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

    frame:HookScript("OnMouseDown", function(_, mouseButtonName) OnMouseDown(window, frame, mouseButtonName) end)
end

function Entries.Sweep()
    if not ns.db.menu then
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
