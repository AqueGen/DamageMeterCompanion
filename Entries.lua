local addonName, ns = ...

-- Right-click on the bars opens the window's own type menu - Damage, Healing,
-- Actions - with the window actions appended, without a line of ours running
-- when a type is chosen.
--
-- The trick is a secure action button. A hardware right-click on it makes the
-- engine itself click the window's type dropdown, in the secure context that
-- hardware input gets, so Blizzard's OnClick builds the menu and Blizzard's
-- closures run the type switch. Nothing is tainted, which is why this survives
-- in combat where a menu of our own could not: our own type switch ended in a
-- Refresh from our stack, and that poisons the window until /reload.
--
-- The window actions - lock, hide, reset, settings - are appended through
-- Menu.ModifyMenu, Blizzard's sanctioned extension point. Their callbacks are
-- ours, and each is one of the calls that is clean from addon code: a lock is
-- a field the refresh path never reads, a hide ends in Hide(), a reset takes
-- no arguments. What is deliberately not appended is the segment: switching
-- it is a Refresh from our stack. It stays on its own header dropdown.
--
-- The overlay covers the scroll box, passes the left button and mouse motion
-- through, and registers only the right button - so Blizzard's click, hover
-- tooltips and drag all still land on the bars underneath.
ns.Entries = {}
local Entries = ns.Entries

-- Keyed by window, weakly: a window is never destroyed, but the table must
-- not be the reason it cannot be.
local overlays = setmetatable({}, { __mode = "k" })

local function Attach(window)
    if overlays[window] then
        return
    end

    -- Secure frames cannot be created or anchored in combat; the sweep comes
    -- back next interval and picks the window up when the lockdown lifts.
    if InCombatLockdown() then
        return
    end

    local scrollBox = window:GetScrollBox()
    local dropdown = window:GetDamageMeterTypeDropdown()

    if not scrollBox or not dropdown then
        return
    end

    local overlay = CreateFrame("Button", nil, window, "SecureActionButtonTemplate")
    overlay:SetAllPoints(scrollBox)
    overlay:SetFrameLevel(scrollBox:GetFrameLevel() + 20)
    overlay:RegisterForClicks("RightButtonDown")
    overlay:SetAttribute("type2", "click")
    overlay:SetAttribute("clickbutton2", dropdown)

    -- Everything that is not a right-click belongs to the bars below. Both
    -- calls are protected - fine out of combat, which is where Attach runs -
    -- and pcall'd so a client that refuses them costs the feature, not login.
    pcall(overlay.SetPassThroughButtons, overlay, "LeftButton", "MiddleButton", "Button4", "Button5")
    pcall(overlay.SetPropagateMouseMotion, overlay, true)

    overlays[window] = overlay
end

function Entries.Sweep()
    ns.Windows.ForEach(function(window)
        Attach(window)

        local overlay = overlays[window]
        if overlay and not InCombatLockdown() then
            -- SetShown on a secure frame is protected in combat; out of combat
            -- it follows the option, and in combat it keeps whatever it had.
            overlay:SetShown(ns.db.menu and window:IsShown() and not window:IsNonInteractive())
        end
    end)
end

-- The same tag is on the header's type dropdown, so the header gains these
-- too. That is fine: they are the gear menu's own entries, one click closer.
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
    ns.OnSweep(Entries.Sweep)
end

ns.RegisterModule("Entries", Entries)
