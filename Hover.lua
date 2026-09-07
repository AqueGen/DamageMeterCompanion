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

local function OnInitEntry(sessionWindow, frame, elementData)
    frame:SetScript("OnEnter", function()
        if not ns.db.hover or ns.HasDeathRecap(elementData) then
            return
        end

        CancelPending()
        pendingTimer = C_Timer.NewTimer(ns.db.hoverDelay, function()
            pendingTimer = nil

            -- A pinned breakdown was put there by a click, and this one window
            -- serves both roles, so re-showing it would silently un-pin it -
            -- including when the click landed inside the hover delay.
            --
            -- Only while it is on screen, though. Blizzard's OnHide clears the
            -- source but not the sticky flag, so a breakdown that was pinned
            -- once and then closed stays flagged sticky for the rest of the
            -- session, and checking the flag alone would kill hover for good
            -- after a single click.
            local sourceWindow = sessionWindow:GetSourceWindow()

            if frame:IsMouseOver()
                and frame:IsVisible()
                and not (sourceWindow:IsShown() and sourceWindow:IsSticky()) then
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
    ns.Windows.ForEach(function(window)
        ns.HookInstance(window, "InitEntry", OnInitEntry)
    end)

    -- Our own windows also carry their own copy of InitEntry, and the mixin
    -- hook above cannot reach them either.
    ns.Windows.OnCreated(function(window)
        ns.HookInstance(window, "InitEntry", OnInitEntry)
    end)
end

ns.RegisterModule("Hover", Hover)
