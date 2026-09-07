local addonName, ns = ...

ns.Config = {}
local Config = ns.Config

local category

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

local function BuildBehaviourOptions()
    AddCheckbox("hover", "Open details on hover",
        "Hovering a bar opens the spell breakdown instead of requiring a click.")

    AddSlider("hoverDelay", "Hover delay",
        "How long the cursor must rest on a bar before the breakdown opens.", 0, 1, 0.05, "%.2f")

    AddCheckbox("menu", "Right-click menu",
        "Right-clicking a bar opens a menu for the tracked type, the segment and window actions.")

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
    category = Settings.RegisterVerticalLayoutCategory("DamageMeterCompanion")
    BuildBehaviourOptions()
    Settings.RegisterAddOnCategory(category)

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

-- ApplyAppearance feeds barHeight to SetBarHeight and textSize to SetTextScale,
-- so the stored text override is a scale around 1. Edit Mode's own control
-- shows that as a percentage, so the box speaks percent and converts - which
-- also keeps a whole-number box useful, since 1 would otherwise be the only
-- reachable value below double size.
-- The bounds are Edit Mode's own, from EditModeSettingDisplayInfo.lua. Below
-- the minimum means "follow Edit Mode again", because a zero bar height is a
-- legal number, a broken window, and something that would persist and be
-- re-applied on every login.
local OVERRIDE_RANGES = {
    barHeight = { minimum = 15, maximum = 40, unit = 1 },
    textSize = { minimum = 50, maximum = 150, unit = 100 },
}

local function CreateOverrideBox(row, index, key)
    local range = OVERRIDE_RANGES[key]
    local box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetMaxLetters(3)
    box:SetSize(36, 20)

    box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        RefreshWindowPanel()
    end)

    box:SetScript("OnEnterPressed", function(self)
        local saved = ns.charDb.windows[index]

        if saved then
            local value = tonumber(self:GetText())

            -- An empty box, or one below the range, means follow Edit Mode
            -- again. Anything else is clamped, and the refresh below shows the
            -- clamped value - the same contract the size boxes already keep.
            if value and value >= range.minimum then
                saved[key] = ns.Snap.Clamp(value, range.minimum, range.maximum) / range.unit
            else
                saved[key] = nil
            end

            local window = ns.Windows.Get(index)
            if window then
                ns.Windows.ApplyAppearance(window, index)
            end
        end

        self:ClearFocus()
        RefreshWindowPanel()
    end)

    return box
end

local function RefreshOverrideBox(box, index, key)
    local saved = ns.charDb.windows[index]

    -- Blizzard's three take their appearance from Edit Mode, and their row says
    -- so in its note rather than offering a box that could not be honoured.
    local enabled = ns.Windows.IsOurs(index) and saved ~= nil

    box:SetEnabled(enabled)

    -- Never overwrite a box the user is typing in; the throttled refresh in
    -- BuildWindowPanel runs while the page is open.
    if box:HasFocus() then
        return
    end

    local value = enabled and saved[key]

    box:SetText(value and math.floor(value * OVERRIDE_RANGES[key].unit + 0.5) or "")
end

-- Blizzard's own toggle only knows about its three windows: calling it for one
-- of ours would reach a DamageMeterMixin method with an index its window data
-- list has no entry for. Ours are shown and hidden through their saved entry.
local function ToggleShown(index)
    if not ns.Windows.IsOurs(index) then
        DamageMeterCompanion_ToggleWindow(index)
        return
    end

    local window = ns.Windows.Get(index)
    local saved = ns.charDb.windows[index]

    if window and saved then
        saved.shown = not window:IsShown()
        window:SetShown(saved.shown)
    end
end

-- Windows.Indices only lists a Blizzard window once it has been shown, but the
-- panel is where the player switches windows 2 and 3 on in the first place, so
-- their rows have to be there whether or not the frame exists yet. RefreshRow
-- already handles a nil window.
local function PanelIndices()
    local present = {}

    for index = 1, ns.Windows.BLIZZARD_WINDOW_COUNT do
        present[index] = true
    end

    for _, index in ipairs(ns.Windows.Indices()) do
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
    row.Shown:SetScript("OnClick", function()
        ToggleShown(index)
        RefreshWindowPanel()
    end)

    row.Size = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.Size:SetPoint("LEFT", row.Shown, "RIGHT", 40, 0)

    row.Width = CreateSizeBox(row, index, "width")
    row.Width:SetPoint("LEFT", row.Size, "RIGHT", 12, 0)

    row.Height = CreateSizeBox(row, index, "height")
    row.Height:SetPoint("LEFT", row.Width, "RIGHT", 8, 0)

    row.BarHeightLabel = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    row.BarHeightLabel:SetPoint("LEFT", row.Height, "RIGHT", 16, 0)
    row.BarHeightLabel:SetText("bar h")

    row.BarHeight = CreateOverrideBox(row, index, "barHeight")
    row.BarHeight:SetPoint("LEFT", row.BarHeightLabel, "RIGHT", 8, 0)

    row.TextSizeLabel = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    row.TextSizeLabel:SetPoint("LEFT", row.BarHeight, "RIGHT", 12, 0)
    row.TextSizeLabel:SetText("text %")

    row.TextSize = CreateOverrideBox(row, index, "textSize")
    row.TextSize:SetPoint("LEFT", row.TextSizeLabel, "RIGHT", 8, 0)

    -- The same lock the window's own gear dropdown offers, brought here so the
    -- page that sets a size can also stop that size being dragged away. Routed
    -- through the window's owner, never DamageMeter, so it is correct for ours.
    row.Lock = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.Lock:SetPoint("LEFT", row.TextSize, "RIGHT", 16, 0)
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
    row.Remove:SetText("Remove")
    row.Remove:SetScript("OnClick", function()
        ns.Windows.Remove(index)
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
        row.Size:SetText("-")
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

    RefreshOverrideBox(row.BarHeight, index, "barHeight")
    RefreshOverrideBox(row.TextSize, index, "textSize")

    -- Window 1 is never lockable: Blizzard's owner refuses to move or resize it
    -- whatever the flag says, so offering the box would promise nothing.
    row.Lock:SetChecked(shown and window:IsLocked() or false)
    row.Lock:SetEnabled(shown and not isPrimary)

    if isPrimary then
        row.Note:SetText("Size and appearance come from Edit Mode.")
    elseif not ns.Windows.IsOurs(index) then
        row.Note:SetText("Appearance comes from Edit Mode.")
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

    -- Window 1 is the primary and cannot go away. Ours are destroyed; Blizzard's
    -- 2 and 3 are put away through its own owner, since their slots are part of
    -- its window data list whatever we do.
    row.Remove:SetEnabled(not isPrimary and (ns.Windows.IsOurs(index) or shown))
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

    -- A removed window leaves its row behind rather than destroying it: frames
    -- cannot be destroyed, and the index can come back.
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
    -- Nothing here scrolls - SettingsCanvas nops the mouse wheel - so a player
    -- who keeps adding windows eventually pushes a row off the bottom of the
    -- page with no way to reach it. The soft cap warning is what stands between
    -- them and that.
    windowPanel = CreateFrame("Frame")
    windowPanel:SetSize(600, 240)
    windowPanel:Hide()

    -- Rows are pooled by window index, not by position: an index that comes
    -- back after a Remove finds the row it had, and the position only decides
    -- where that row is anchored this refresh.
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

    windowPanel.AddWindow = CreateFrame("Button", nil, windowPanel, "UIPanelButtonTemplate")
    windowPanel.AddWindow:SetSize(120, 22)
    windowPanel.AddWindow:SetPoint("BOTTOMLEFT", windowPanel, "BOTTOMLEFT", 20, 20)
    windowPanel.AddWindow:SetText("Add window")
    windowPanel.AddWindow:SetScript("OnClick", function()
        ns.Windows.Create()
        RefreshWindowPanel()
    end)

    windowPanel:SetScript("OnShow", RefreshWindowPanel)

    -- Everything shown here can change from outside the panel: the right-click
    -- menu's match entries, the window keybinds, Blizzard's own Hide, a mouse
    -- resize. Polling twice a second is cheaper than hooking all of them.
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
