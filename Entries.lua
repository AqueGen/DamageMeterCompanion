local addonName, ns = ...

-- Lock, hide, reset and our settings, appended to the type menu every window
-- already has in its header, through Menu.ModifyMenu - Blizzard's sanctioned
-- extension point, whose modifiers run inside securecallfunction.
--
-- The callbacks are ours and each is a call that is clean from addon code: a
-- lock is a field the refresh path never reads, a hide ends in Hide(), a reset
-- takes no arguments, settings touches nothing of the meter's. The segment is
-- deliberately not here - switching it is a Refresh from our stack.
--
-- What this file no longer tries: a right-click on the bars that opens that
-- menu. Blizzard's dropdowns open in OnMouseDown (MenuTemplates.xml:46,77),
-- and the one thing a secure action button can synthesise is a click, which
-- runs OnClick and does nothing there. Opening the menu from our own code
-- builds it under our taint, and a type chosen from it would poison the
-- window the same way our own menu did.
ns.Entries = {}
local Entries = ns.Entries

local function AddWindowActions()
    if not Menu or not Menu.ModifyMenu then
        return
    end

    Menu.ModifyMenu("MENU_DAMAGE_METER_WINDOW_TRACKED_TYPE", function(dropdown, rootDescription)
        local window = dropdown and dropdown:GetParent()
        if not window or not window.GetDamageMeterOwner then
            return
        end

        local owner = window:GetDamageMeterOwner()

        rootDescription:CreateDivider()

        if owner:CanMoveOrResizeSessionWindow(window) then
            local locked = window:IsLocked()
            rootDescription:CreateButton(locked and DAMAGE_METER_UNLOCK_WINDOW or DAMAGE_METER_LOCK_WINDOW, function()
                owner:SetSessionWindowLocked(window, not locked)
            end)
        end

        if owner:CanHideSessionWindow(window) then
            rootDescription:CreateButton(DAMAGE_METER_HIDE_WINDOW, function()
                owner:HideSessionWindow(window)
            end)
        end

        rootDescription:CreateButton(DAMAGE_METER_RESET_ALL_SESSIONS, function()
            C_DamageMeter.ResetAllCombatSessions()
        end)

        rootDescription:CreateButton("DamageMeterCompanion settings", function()
            ns.Config.Open()
        end)
    end)
end

function Entries.Enable()
    AddWindowActions()
end

ns.RegisterModule("Entries", Entries)
