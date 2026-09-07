local addonName, ns = ...

ns.ContextMenu = {}
local ContextMenu = ns.ContextMenu

ContextMenu.CATEGORIES = {
    {
        name = DAMAGE_METER_CATEGORY_DAMAGE,
        types = {
            Enum.DamageMeterType.DamageDone,
            Enum.DamageMeterType.Dps,
            Enum.DamageMeterType.DamageTaken,
            Enum.DamageMeterType.AvoidableDamageTaken,
            Enum.DamageMeterType.EnemyDamageTaken,
        },
    },
    {
        name = DAMAGE_METER_CATEGORY_HEALING,
        types = {
            Enum.DamageMeterType.HealingDone,
            Enum.DamageMeterType.Hps,
            -- Blizzard's own menu omits Absorbs even though the type and its
            -- name string both exist. We list it: leaving a reachable type out
            -- of a menu whose whole point is reaching types would be odd. If it
            -- turns out to render an empty window, drop it here and note why.
            Enum.DamageMeterType.Absorbs,
        },
    },
    {
        name = DAMAGE_METER_CATEGORY_ACTIONS,
        types = {
            Enum.DamageMeterType.Interrupts,
            Enum.DamageMeterType.Dispels,
            Enum.DamageMeterType.Deaths,
        },
    },
}

local TYPE_NAMES = {
    [Enum.DamageMeterType.DamageDone] = DAMAGE_METER_TYPE_DAMAGE_DONE,
    [Enum.DamageMeterType.Dps] = DAMAGE_METER_TYPE_DPS,
    [Enum.DamageMeterType.HealingDone] = DAMAGE_METER_TYPE_HEALING_DONE,
    [Enum.DamageMeterType.Hps] = DAMAGE_METER_TYPE_HPS,
    [Enum.DamageMeterType.Absorbs] = DAMAGE_METER_TYPE_ABSORBS,
    [Enum.DamageMeterType.Interrupts] = DAMAGE_METER_TYPE_INTERRUPTS,
    [Enum.DamageMeterType.Dispels] = DAMAGE_METER_TYPE_DISPELS,
    [Enum.DamageMeterType.DamageTaken] = DAMAGE_METER_TYPE_DAMAGE_TAKEN,
    [Enum.DamageMeterType.AvoidableDamageTaken] = DAMAGE_METER_TYPE_AVOIDABLE_DAMAGE_TAKEN,
    [Enum.DamageMeterType.Deaths] = DAMAGE_METER_TYPE_DEATHS,
    [Enum.DamageMeterType.EnemyDamageTaken] = DAMAGE_METER_TYPE_ENEMY_DAMAGE_TAKEN,
}

function ContextMenu.GetTypeName(damageMeterType)
    return TYPE_NAMES[damageMeterType] or UNKNOWN
end

-- A patch that adds a damage meter type would silently drop it from our menu.
-- Say so rather than lose it.
local function VerifyTypeCoverage()
    local listed = {}
    for _, category in ipairs(ContextMenu.CATEGORIES) do
        for _, damageMeterType in ipairs(category.types) do
            listed[damageMeterType] = true
        end
    end

    for name, value in pairs(Enum.DamageMeterType) do
        if not listed[value] then
            ns.Print("unlisted damage meter type: " .. name .. " - the right-click menu needs updating")
        end
    end
end

local function AddTypeEntries(rootDescription, sessionWindow)
    local function IsSelected(damageMeterType)
        return sessionWindow:GetDamageMeterType() == damageMeterType
    end

    -- Through the window's own owner, never DamageMeter directly: our windows
    -- have the proxy as their owner, and DamageMeter's own setters look the
    -- index up in a window data list that only holds Blizzard's three, then
    -- index the nil they get back.
    local function SetSelected(damageMeterType)
        sessionWindow:GetDamageMeterOwner():SetSessionWindowDamageMeterType(sessionWindow, damageMeterType)
    end

    for _, category in ipairs(ContextMenu.CATEGORIES) do
        local submenu = rootDescription:CreateButton(category.name)
        for _, damageMeterType in ipairs(category.types) do
            submenu:CreateRadio(ContextMenu.GetTypeName(damageMeterType), IsSelected, SetSelected, damageMeterType)
        end
    end
end

-- Mirrors InitializeSessionDropdown so the segment list reads identically to
-- the one on the window header.
local function AddSessionEntries(rootDescription, sessionWindow)
    local function IsSelected(option)
        return sessionWindow:GetSessionType() == option.type
            and sessionWindow:GetSessionID() == option.sessionID
    end

    local function SetSelected(option)
        sessionWindow:GetDamageMeterOwner():SetSessionWindowSessionID(sessionWindow, option.type, option.sessionID)
    end

    -- No global string names the concept, and labelling the submenu with one
    -- of the segments it contains would read as a selection rather than a
    -- category, so this one is ours.
    local submenu = rootDescription:CreateButton("Segment")

    for _, availableSession in ipairs(C_DamageMeter.GetAvailableCombatSessions()) do
        local sessionName = availableSession.name
        if not sessionName or sessionName == "" then
            sessionName = DAMAGE_METER_COMBAT_NUMBER:format(availableSession.sessionID)
        end

        if availableSession.durationSeconds then
            sessionName = ("%s [%s]"):format(sessionName, SecondsToClock(availableSession.durationSeconds))
        end

        submenu:CreateRadio(sessionName, IsSelected, SetSelected, { type = nil, sessionID = availableSession.sessionID })
    end

    submenu:CreateDivider()
    submenu:CreateRadio(DAMAGE_METER_CURRENT_SESSION, IsSelected, SetSelected,
        { type = Enum.DamageMeterSessionType.Current, sessionID = nil })
    submenu:CreateRadio(DAMAGE_METER_OVERALL_SESSION, IsSelected, SetSelected,
        { type = Enum.DamageMeterSessionType.Overall, sessionID = nil })
end

local function AddWindowEntries(rootDescription, sessionWindow)
    local owner = sessionWindow:GetDamageMeterOwner()

    if owner:CanMoveOrResizeSessionWindow(sessionWindow) then
        local locked = sessionWindow:IsLocked()
        rootDescription:CreateButton(locked and DAMAGE_METER_UNLOCK_WINDOW or DAMAGE_METER_LOCK_WINDOW, function()
            owner:SetSessionWindowLocked(sessionWindow, not locked)
        end)
    end

    -- The predicates would survive going to DamageMeter directly, but routing
    -- every owner call the same way makes the rule greppable, and it is what
    -- lets Show new window keep working from one of ours once Blizzard's three
    -- are up.
    local newWindow = rootDescription:CreateButton(DAMAGE_METER_SHOW_NEW_WINDOW, function()
        owner:ShowNewSecondarySessionWindow()
    end)
    -- The predicate, not its result: only a function is re-polled while the
    -- menu stays open, which is what Blizzard's own menu passes here.
    newWindow:SetEnabled(function() return owner:CanShowNewSecondarySessionWindow() end)

    local hideWindow = rootDescription:CreateButton(DAMAGE_METER_HIDE_WINDOW, function()
        owner:HideSessionWindow(sessionWindow)
    end)
    hideWindow:SetEnabled(function() return owner:CanHideSessionWindow(sessionWindow) end)

    rootDescription:CreateButton(DAMAGE_METER_RESET_ALL_SESSIONS, function()
        C_DamageMeter.ResetAllCombatSessions()
    end)

    if ns.Config and ns.Config.Open then
        rootDescription:CreateButton(SETTINGS, function()
            ns.Config.Open()
        end)
    end
end

-- Replaces the OnClick Blizzard installed in InitEntry immediately above; the
-- left button keeps its behaviour, the right button gains the menu.
local function OnInitEntry(sessionWindow, frame, elementData)
    frame:SetScript("OnClick", function(_, mouseButtonName)
        if mouseButtonName == "RightButton" and ns.db.menu then
            MenuUtil.CreateContextMenu(frame, function(_, rootDescription)
                AddTypeEntries(rootDescription, sessionWindow)
                rootDescription:CreateDivider()
                AddSessionEntries(rootDescription, sessionWindow)
                rootDescription:CreateDivider()
                AddWindowEntries(rootDescription, sessionWindow)

                -- Snap adds its match-size checkboxes here once it exists.
                if ns.Snap and ns.Snap.AddMenuEntries then
                    ns.Snap.AddMenuEntries(rootDescription, sessionWindow)
                end
            end)
            return
        end

        local sticky = true
        sessionWindow:ShowSourceWindow(elementData, sticky)
    end)
end

function ContextMenu.Enable()
    VerifyTypeCoverage()

    -- Mixin hook for windows created later, instance hooks for the ones that
    -- already exist and carry their own copy of InitEntry.
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

ns.RegisterModule("ContextMenu", ContextMenu)
