local addonName, ns = ...

ns.Config = {}
local Config = ns.Config

local category
local categoryLayout

local function AddCheckbox(variableKey, name, tooltip, onChange)
    local setting = Settings.RegisterProxySetting(category, "DMC_" .. variableKey,
        Settings.VarType.Boolean, name, ns.defaults[variableKey],
        function() return ns.db[variableKey] end,
        function(value)
            ns.db[variableKey] = value
            if onChange then
                onChange()
            end
        end)

    return Settings.CreateCheckbox(category, setting, tooltip)
end

-- labelFormat is a format string, applied to the value shown beside the slider.
-- Without it a fractional slider prints the raw number, float noise and all.
local function AddSlider(variableKey, name, tooltip, minimum, maximum, step, labelFormat, onChange)
    local setting = Settings.RegisterProxySetting(category, "DMC_" .. variableKey,
        Settings.VarType.Number, name, ns.defaults[variableKey],
        function() return ns.db[variableKey] end,
        function(value)
            ns.db[variableKey] = value
            if onChange then
                onChange()
            end
        end)

    local options = Settings.CreateSliderOptions(minimum, maximum, step)

    -- CreateMinimalSliderFormatter treats a non-function second argument as a
    -- constant label, so the format string has to be applied in a closure.
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, labelFormat and function(value)
        return labelFormat:format(value)
    end or nil)

    Settings.CreateSlider(category, setting, options, tooltip)
end

-- The game's own two damage meter switches, mirrored so that everything about
-- the meter is on one page. They are the CVars Blizzard's Gameplay
-- Enhancements page edits, read and written through C_CVar under our own
-- setting names so nothing collides with Blizzard's registration of the same
-- CVars. The labels and tooltips are Blizzard's strings, so they read the same
-- in every locale, and the section says whose settings these are.
local function AddBlizzardCVarCheckbox(cvar, variableKey, label, tooltip)
    local setting = Settings.RegisterProxySetting(category, "DMC_blizzard_" .. variableKey,
        Settings.VarType.Boolean, label, true,
        function() return C_CVar.GetCVarBool(cvar) end,
        function(value)
            -- SetCVar signals refusal by returning false rather than by
            -- throwing, and the meter's enable switch is one it can refuse in
            -- combat - say so rather than show a box that silently reverts.
            local ok, result = pcall(C_CVar.SetCVar, cvar, value and "1" or "0")
            if not ok or result == false then
                ns.Print("the game refused to change " .. label .. " right now")
            end
        end)

    Settings.CreateCheckbox(category, setting, function()
        local isAvailable, failureReason = C_DamageMeter.IsDamageMeterAvailable()
        local text = tooltip .. "|n|n|cff808080The game's own setting, from Gameplay Enhancements. Shown here so the meter is configured in one place.|r"
        if not isAvailable then
            text = text .. "|n|n" .. failureReason
        end
        return text
    end)
end

local function BuildBlizzardOptions()
    if categoryLayout and CreateSettingsListSectionHeaderInitializer then
        categoryLayout:AddInitializer(CreateSettingsListSectionHeaderInitializer(DAMAGE_METER_LABEL .. " (Blizzard)"))
    end

    AddBlizzardCVarCheckbox("damageMeterEnabled", "enabled", ENABLE_DAMAGE_METER, ENABLE_DAMAGE_METER_TOOLTIP)
    AddBlizzardCVarCheckbox("damageMeterResetOnNewInstance", "autoReset", AUTO_RESET_DAMAGE_METER, AUTO_RESET_DAMAGE_METER_TOOLTIP)
end

local function BuildBehaviourOptions()
    AddCheckbox("hover", "Details on hover",
        "Resting the cursor on a bar shows that source's spells beside the window. It is the addon's own panel fed from the meter's data, so it works in combat; Blizzard's own breakdown, opened by clicking a bar, takes priority while it is open.")

    AddSlider("hoverDelay", "Hover delay",
        "How long the cursor must rest on a bar before the panel appears.", 0, 1, 0.05, "%.2f")

    AddCheckbox("format", "Readable numbers",
        "Show 56.72M instead of 56716 K. The percentage is shown only out of combat, because it is the one part that needs arithmetic on values that are Secret in combat.",
        function()
            -- Switching on needs nothing: the sweep paints within a fifth of a
            -- second. Switching off has to put Blizzard's own text back.
            if not ns.db.format then
                ns.Format.Restore()
            end
        end)

    AddCheckbox("snap", "Snap windows together",
        "Dragging a window near another attaches it, and they move and resize together.")

    AddSlider("snapThreshold", "Snap distance",
        "How close an edge must be, in pixels, before it snaps.", 5, 50, 1)

    AddSlider("idleAlpha", "Idle transparency",
        "How visible the meter is when the mouse is not on it, as a fraction of the Edit Mode transparency. "
            .. "A window set to uninteractable stays at the idle value, because its mouse is disabled.",
        0.1, 1, 0.05, "%.2f", function()
            ns.Presence.ApplyAlphaToAll()
        end)

    local strataSetting = Settings.RegisterProxySetting(category, "DMC_strata",
        Settings.VarType.String, "Layer", ns.defaults.strata,
        -- Resolved, not raw: a hand-edited saved variable can hold a strata the
        -- meter refuses, and the dropdown must show what is actually applied.
        function() return ns.Presence.ResolveStrata(ns.db.strata) end,
        function(value)
            ns.db.strata = value
            ns.Presence.ApplyStrata()
        end)

    Settings.CreateDropdown(category, strataSetting, function()
        local container = Settings.CreateControlTextContainer()
        for _, strata in ipairs(ns.Presence.STRATA_ORDER) do
            container:Add(strata, strata)
        end
        return container:GetData()
    end, "Which layer the meter draws on. Raise it if another addon covers it.")

    BuildBlizzardOptions()
end

-- The gear dropdown on every meter window is tagged, which is Blizzard's own
-- extension point: Menu.ModifyMenu callbacks run through securecallfunction
-- at the boundary, so adding an entry is clean. What the entry does when
-- pressed is our code - opening the settings panel touches nothing of the
-- meter's.
local function AddSettingsToWindowDropdown()
    if not Menu or not Menu.ModifyMenu then
        return
    end

    Menu.ModifyMenu("MENU_DAMAGE_METER_WINDOW_SETTINGS", function(_, rootDescription)
        rootDescription:CreateDivider()
        rootDescription:CreateButton("DamageMeterCompanion settings", function()
            ns.Config.Open()
        end)
    end)
end

-- Settings.OpenToCategory reaches the protected OpenSettingsPanel, which an
-- addon may not call in combat. Blizzard's own entry in the same dropdown works
-- because their code is not tainted; ours is blocked and would otherwise fail
-- silently apart from a line in the error log.
function Config.Open()
    if InCombatLockdown() then
        ns.Print("the settings panel cannot be opened in combat")
        return
    end

    Settings.OpenToCategory(category:GetID())
end

function Config.Enable()
    category, categoryLayout = Settings.RegisterVerticalLayoutCategory("DamageMeterCompanion")
    BuildBehaviourOptions()
    Settings.RegisterAddOnCategory(category)

    AddSettingsToWindowDropdown()
    ns.Config.BuildWindowPanel()
end

local windowPanel

-- Forward declared: the row controls below refresh the panel after an edit.
local RefreshWindowPanel

-- Setting the size here deliberately goes through SetSize on the window, so it
-- trips the OnSizeChanged hook and propagates to anything matched to it,
-- exactly as a mouse resize would. The refresh afterwards shows the clamped
-- value rather than what was typed - silently ignoring an out-of-range request
-- would be worse than correcting it in front of the user.
local function CreateSizeBox(row, index, dimension)
    local box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetMaxLetters(4)
    box:SetSize(44, 20)

    box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        RefreshWindowPanel()
    end)

    box:SetScript("OnEnterPressed", function(self)
        local window = ns.Windows.Get(index)
        local value = tonumber(self:GetText())

        if window and value then
            local width = (dimension == "width") and value or window:GetWidth()
            local height = (dimension == "height") and value or window:GetHeight()

            -- Windows.SetSize does the lock check and, for the primary window,
            -- the Edit Mode routing - so this box does not need to know which
            -- kind of window it is editing.
            ns.Windows.SetSize(index, width, height)
        end

        self:ClearFocus()
        RefreshWindowPanel()
    end)

    return box
end

StaticPopupDialogs["DAMAGEMETERCOMPANION_RELOAD"] = {
    text = "Window %d is shown. Until the UI is reloaded it carries the addon's taint and will log a warning per row in combat. Reload now?",
    button1 = RELOADUI,
    button2 = CANCEL,
    OnAccept = function() ReloadUI() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function ToggleShown(index)
    if ns.Windows.IsIndexShown(index) then
        ns.Windows.Hide(index)
        return
    end

    if InCombatLockdown() then
        ns.Print("a window cannot be shown in combat")
        return
    end

    if ns.Windows.Show(index) then
        StaticPopup_Show("DAMAGEMETERCOMPANION_RELOAD", index)
    end
end

-- Windows.Indices only lists a Blizzard window once it has been shown; the
-- panel lists all three slots so a hidden one still has a row saying how to
-- bring it back. RefreshRow already handles a nil window.
local function PanelIndices()
    local present = {}

    for index = 1, ns.Windows.BLIZZARD_WINDOW_COUNT do
        present[index] = true
    end

    return ns.Windows.SortedIndices(present)
end

local function CreateRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(560, 60)

    row.Title = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.Title:SetPoint("TOPLEFT")

    row.Shown = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.Shown:SetPoint("TOPLEFT", row.Title, "BOTTOMLEFT", 0, -2)
    row.Shown:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Show or hide this window")
        GameTooltip:AddLine("Hiding is clean. Showing from here runs Blizzard's setup inside the addon's taint, so the window logs a warning per row in combat until the UI is reloaded - you will be offered a reload. The gear menu's Show new window needs no reload.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    row.Shown:SetScript("OnLeave", GameTooltip_Hide)
    row.Shown:SetScript("OnClick", function()
        ToggleShown(index)
        RefreshWindowPanel()
    end)

    row.Size = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.Size:SetPoint("LEFT", row.Shown, "RIGHT", 6, 0)
    row.Size:SetWidth(70)
    row.Size:SetJustifyH("LEFT")

    row.Width = CreateSizeBox(row, index, "width")
    row.Width:SetPoint("LEFT", row.Size, "RIGHT", 12, 0)

    row.Height = CreateSizeBox(row, index, "height")
    row.Height:SetPoint("LEFT", row.Width, "RIGHT", 8, 0)

    -- The same lock the window's own gear dropdown offers, brought here so the
    -- page that sets a size can also stop that size being dragged away. Routed
    -- through the window's owner, never DamageMeter, so it is correct for ours.
    row.Lock = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.Lock:SetPoint("LEFT", row.Height, "RIGHT", 16, 0)
    row.Lock.Text:SetText("lock")
    row.Lock:SetScript("OnClick", function(self)
        local window = ns.Windows.Get(index)
        if window then
            window:GetDamageMeterOwner():SetSessionWindowLocked(window, self:GetChecked())
        end
        RefreshWindowPanel()
    end)

    row.Note = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    row.Note:SetPoint("LEFT", row.Lock.Text, "RIGHT", 16, 0)

    row.Link = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.Link:SetPoint("TOPLEFT", row.Shown, "BOTTOMLEFT", 0, -4)

    row.GapLabel = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    row.GapLabel:SetPoint("LEFT", row.Link, "RIGHT", 12, 0)
    row.GapLabel:SetText("gap")

    row.Gap = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    row.Gap:SetAutoFocus(false)
    row.Gap:SetNumeric(true)
    row.Gap:SetMaxLetters(3)
    row.Gap:SetSize(36, 20)
    row.Gap:SetPoint("LEFT", row.GapLabel, "RIGHT", 8, 0)

    row.Gap:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        RefreshWindowPanel()
    end)

    row.Gap:SetScript("OnEnterPressed", function(self)
        local link = ns.charDb.links[index]
        local value = tonumber(self:GetText())

        if link and value then
            link.gap = value
            ns.Snap.ApplyLink(index)
        end

        self:ClearFocus()
        RefreshWindowPanel()
    end)

    -- UICheckButtonTemplate already ships the caption font string as Text,
    -- anchored to the right of the box, so it only needs its text set.
    row.MatchWidth = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.MatchWidth:SetPoint("LEFT", row.Gap, "RIGHT", 16, 0)
    row.MatchWidth.Text:SetText("match width")
    row.MatchWidth:SetScript("OnClick", function(self)
        local link = ns.charDb.links[index]
        if link then
            link.matchWidth = self:GetChecked()
            ns.Snap.PushSize(link.to)
            RefreshWindowPanel()
        end
    end)

    row.MatchHeight = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.MatchHeight:SetPoint("LEFT", row.MatchWidth.Text, "RIGHT", 20, 0)
    row.MatchHeight.Text:SetText("match height")
    row.MatchHeight:SetScript("OnClick", function(self)
        local link = ns.charDb.links[index]
        if link then
            link.matchHeight = self:GetChecked()
            ns.Snap.PushSize(link.to)
            RefreshWindowPanel()
        end
    end)

    row.Detach = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.Detach:SetSize(80, 22)
    row.Detach:SetPoint("LEFT", row.MatchHeight.Text, "RIGHT", 20, 0)
    row.Detach:SetText("Detach")
    row.Detach:SetScript("OnClick", function()
        ns.Snap.ClearLink(index)
        RefreshWindowPanel()
    end)

    row.Remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.Remove:SetSize(80, 22)
    row.Remove:SetPoint("LEFT", row.Detach, "RIGHT", 8, 0)
    row.Remove:SetText("Hide")
    row.Remove:SetScript("OnClick", function()
        ns.Windows.Hide(index)
        RefreshWindowPanel()
    end)

    return row
end

-- The four pairs Snap.FindSnap produces, named the way the player sees them.
local SIDE_NAMES = {
    ["TOPLEFT|BOTTOMLEFT"] = "below",
    ["BOTTOMLEFT|TOPLEFT"] = "above",
    ["TOPLEFT|TOPRIGHT"] = "right of",
    ["TOPRIGHT|TOPLEFT"] = "left of",
}

local function RefreshRow(row, index)
    local window = ns.Windows.Get(index)
    local isPrimary = index == 1
    local link = ns.charDb.links[index]
    local shown = window ~= nil and window:IsShown()

    row.Title:SetText(isPrimary and "Window 1 (primary)" or ("Window " .. index))
    row.Shown:SetChecked(shown)
    row.Shown:SetEnabled(not isPrimary)

    if shown then
        row.Size:SetText(("%d x %d"):format(window:GetWidth(), window:GetHeight()))
    else
        row.Size:SetText("hidden")
    end

    -- Window 1 gets the size boxes too: Windows.SetSize routes it through
    -- Edit Mode. A locked window keeps them, greyed out, so the panel says
    -- why the edit is refused instead of swallowing it.
    local resizable = shown and (index == 1 or window:CanMoveOrResize())

    row.Width:SetShown(true)
    row.Width:SetEnabled(resizable)
    row.Height:SetShown(true)
    row.Height:SetEnabled(resizable)

    -- Never overwrite a box the user is typing in; the throttled refresh below
    -- runs while the page is open, and hiding the window from this same row is
    -- enough to take the shown branch out from under a half-typed number.
    if not row.Width:HasFocus() then
        row.Width:SetText(shown and math.floor(window:GetWidth() + 0.5) or "")
    end

    if not row.Height:HasFocus() then
        row.Height:SetText(shown and math.floor(window:GetHeight() + 0.5) or "")
    end

    -- Window 1 is never lockable: Blizzard's owner refuses to move or resize it
    -- whatever the flag says, so offering the box would promise nothing.
    row.Lock:SetChecked(shown and window:IsLocked() or false)
    row.Lock:SetEnabled(shown and not isPrimary)

    if isPrimary then
        row.Note:SetText("Size comes from Edit Mode.")
    elseif not shown then
        row.Note:SetText("Ticking Shown reloads the UI afterwards - see the tooltip.")
    else
        row.Note:SetText("")
    end

    if link then
        local side = SIDE_NAMES[tostring(link.point) .. "|" .. tostring(link.relPoint)]
        row.Link:SetText(("attached %s window %s"):format(side or "to", link.to))
    else
        row.Link:SetText("not attached")
    end
    row.Gap:SetEnabled(link ~= nil and not isPrimary)

    if not row.Gap:HasFocus() then
        row.Gap:SetText(link and (link.gap or 0) or "")
    end

    row.MatchWidth:SetChecked(link and link.matchWidth or false)
    row.MatchWidth:SetEnabled(link ~= nil and not isPrimary)
    row.MatchHeight:SetChecked(link and link.matchHeight or false)
    row.MatchHeight:SetEnabled(link ~= nil and not isPrimary)
    row.Detach:SetEnabled(link ~= nil and not isPrimary)

    -- Hiding is the only direction that is clean from addon code; see Windows.Hide.
    row.Remove:SetEnabled(not isPrimary and shown)
end

function RefreshWindowPanel()
    if not windowPanel or not windowPanel:IsShown() then
        return
    end

    local present = {}

    for position, index in ipairs(PanelIndices()) do
        present[index] = true
        RefreshRow(windowPanel:AcquireRow(index, position), index)
    end

    for index, row in pairs(windowPanel.rows) do
        if not present[index] then
            row:Hide()
        end
    end
end

-- The panel deliberately offers no way to attach a window: snapping is a drag
-- gesture, and a control duplicating it would be a second way to do the same
-- thing. The page shows the link, its gap, its match flags and a Detach button.
function Config.BuildWindowPanel()
    -- A plain frame, not SettingsListTemplate: the canvas subcategory sizes the
    -- frame to fill the panel, and the template would add a list we do not use.
    windowPanel = CreateFrame("Frame")
    windowPanel:SetSize(600, 240)
    windowPanel:Hide()

    -- Rows are pooled by window index.
    windowPanel.rows = {}

    function windowPanel:AcquireRow(index, position)
        local row = self.rows[index]

        if not row then
            row = CreateRow(self, index)
            self.rows[index] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self, "TOPLEFT", 20, -20 - (position - 1) * 70)
        row:Show()

        return row
    end

    -- Window 1 is skipped: its owner refuses the lock regardless.
    local function SetAllLocked(locked)
        ns.Windows.ForEach(function(window, index)
            if index ~= 1 then
                window:GetDamageMeterOwner():SetSessionWindowLocked(window, locked)
            end
        end)

        RefreshWindowPanel()
    end

    windowPanel.LockAll = CreateFrame("Button", nil, windowPanel, "UIPanelButtonTemplate")
    windowPanel.LockAll:SetSize(100, 22)
    windowPanel.LockAll:SetPoint("BOTTOMLEFT", windowPanel, "BOTTOMLEFT", 20, 20)
    windowPanel.LockAll:SetText("Lock all")
    windowPanel.LockAll:SetScript("OnClick", function() SetAllLocked(true) end)

    windowPanel.UnlockAll = CreateFrame("Button", nil, windowPanel, "UIPanelButtonTemplate")
    windowPanel.UnlockAll:SetSize(100, 22)
    windowPanel.UnlockAll:SetPoint("LEFT", windowPanel.LockAll, "RIGHT", 8, 0)
    windowPanel.UnlockAll:SetText("Unlock all")
    windowPanel.UnlockAll:SetScript("OnClick", function() SetAllLocked(false) end)

    windowPanel:SetScript("OnShow", RefreshWindowPanel)

    -- Everything shown here can change from outside the panel: the keybinds,
    -- Blizzard's own Hide, a mouse resize. Polling twice a second is cheaper
    -- than hooking all of them.
    windowPanel:SetScript("OnUpdate", function(self, elapsed)
        self.sinceRefresh = (self.sinceRefresh or 0) + elapsed

        if self.sinceRefresh >= 0.5 then
            self.sinceRefresh = 0
            RefreshWindowPanel()
        end
    end)

    -- The parent category is registered before this runs, so the category list
    -- has already been built; registering the subcategory is what rebuilds it
    -- and makes the page appear.
    local subcategory = Settings.RegisterCanvasLayoutSubcategory(category, windowPanel, "Windows")
    Settings.RegisterAddOnCategory(subcategory)
end

ns.RegisterModule("Config", Config)
