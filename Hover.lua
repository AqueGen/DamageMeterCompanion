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

-- Sources that carry a death recap open the death recap UI instead of the
-- source window, which would be hostile on a mere hover. deathRecapID is
-- documented NeverSecret, so reading it in combat is safe.
local function OpensDeathRecap(elementData)
    return type(elementData.deathRecapID) == "number" and elementData.deathRecapID ~= 0
end

local function OnInitEntry(sessionWindow, frame, elementData)
    frame:SetScript("OnEnter", function()
        if not ns.db.hover or OpensDeathRecap(elementData) then
            return
        end

        CancelPending()
        pendingTimer = C_Timer.NewTimer(ns.db.hoverDelay, function()
            pendingTimer = nil

            -- A sticky window was pinned by a click, and this one window
            -- serves both roles. Re-showing it would silently un-pin it,
            -- including when the click landed inside the hover delay.
            if frame:IsMouseOver()
                and frame:IsVisible()
                and not sessionWindow:GetSourceWindow():IsSticky() then
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
    ns.ForEachSessionWindow(function(window)
        ns.HookInstance(window, "InitEntry", OnInitEntry)
    end)
end

ns.RegisterModule("Hover", Hover)
