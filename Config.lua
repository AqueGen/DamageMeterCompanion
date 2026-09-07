local addonName, ns = ...

ns.Config = {}
local Config = ns.Config

local category

local function AddCheckbox(variableKey, name, tooltip, onChange)
    local setting = Settings.RegisterProxySetting(category, "DMT_" .. variableKey,
        Settings.VarType.Boolean, name, ns.defaults[variableKey],
        function() return ns.db[variableKey] end,
        function(value)
            ns.db[variableKey] = value
            if onChange then
                onChange()
            end
        end)

    Settings.CreateCheckbox(category, setting, tooltip)
end

local function AddSlider(variableKey, name, tooltip, minimum, maximum, step, onChange)
    local setting = Settings.RegisterProxySetting(category, "DMT_" .. variableKey,
        Settings.VarType.Number, name, ns.defaults[variableKey],
        function() return ns.db[variableKey] end,
        function(value)
            ns.db[variableKey] = value
            if onChange then
                onChange()
            end
        end)

    local options = Settings.CreateSliderOptions(minimum, maximum, step)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)

    Settings.CreateSlider(category, setting, options, tooltip)
end

local function BuildBehaviourOptions()
    AddCheckbox("hover", "Open details on hover",
        "Hovering a bar opens the spell breakdown instead of requiring a click.")

    AddSlider("hoverDelay", "Hover delay",
        "How long the cursor must rest on a bar before the breakdown opens.", 0, 1, 0.05)

    AddCheckbox("menu", "Right-click menu",
        "Right-clicking a bar opens a menu for the tracked type, the segment and window actions.")

    AddCheckbox("format", "Readable numbers",
        "Show 56.72M instead of 56716 K. Only applies once the values stop being secret, which is after combat.")

    AddCheckbox("snap", "Snap windows together",
        "Dragging a window near another attaches it, and they move and resize together.")

    AddSlider("snapThreshold", "Snap distance",
        "How close an edge must be, in pixels, before it snaps.", 5, 40, 1)

    AddSlider("idleAlpha", "Idle transparency",
        "How visible the meter is when the mouse is not on it, as a fraction of the Edit Mode transparency.",
        0.1, 1, 0.05, function()
            ns.ForEachSessionWindow(ns.Presence.ApplyAlpha)
        end)

    local strataSetting = Settings.RegisterProxySetting(category, "DMT_strata",
        Settings.VarType.String, "Layer", ns.defaults.strata,
        function() return ns.db.strata end,
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

function Config.Open()
    Settings.OpenToCategory(category:GetID())
end

function Config.Enable()
    category = Settings.RegisterVerticalLayoutCategory("DamageMeterTweaks")
    BuildBehaviourOptions()
    Settings.RegisterAddOnCategory(category)

    ns.Config.BuildWindowPanel()
end

local windowPanel

local function RefreshWindowPanel()
    if not windowPanel or not windowPanel:IsShown() then
        return
    end

    for index = 1, 3 do
        local row = windowPanel.rows[index]
        local window = DamageMeter:GetSessionWindow(index)
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

        row.Note:SetText(isPrimary and "Size and position are controlled by Edit Mode." or "")
        row.Link:SetText(link and ("attached to window " .. link.to) or "not attached")
        row.MatchWidth:SetChecked(link and link.matchWidth or false)
        row.MatchWidth:SetEnabled(link ~= nil and not isPrimary)
        row.MatchHeight:SetChecked(link and link.matchHeight or false)
        row.MatchHeight:SetEnabled(link ~= nil and not isPrimary)
        row.Detach:SetEnabled(link ~= nil)
    end
end

-- The panel deliberately offers no way to attach a window: snapping is a drag
-- gesture, and a control duplicating it would be a second way to do the same
-- thing. The page shows the link, its match flags and a Detach button.
function Config.BuildWindowPanel()
    -- A plain frame, not SettingsListTemplate: the canvas subcategory owns the
    -- scrolling and sizing, and the template would add a list we do not use.
    windowPanel = CreateFrame("Frame")
    windowPanel:SetSize(600, 240)
    windowPanel:Hide()
    windowPanel.rows = {}

    for index = 1, 3 do
        local row = CreateFrame("Frame", nil, windowPanel)
        row:SetSize(560, 60)
        row:SetPoint("TOPLEFT", windowPanel, "TOPLEFT", 20, -20 - (index - 1) * 70)

        row.Title = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        row.Title:SetPoint("TOPLEFT")

        row.Shown = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.Shown:SetPoint("TOPLEFT", row.Title, "BOTTOMLEFT", 0, -2)
        row.Shown:SetScript("OnClick", function()
            DamageMeterTweaks_ToggleWindow(index)
            RefreshWindowPanel()
        end)

        row.Size = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.Size:SetPoint("LEFT", row.Shown, "RIGHT", 40, 0)

        row.Note = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        row.Note:SetPoint("LEFT", row.Size, "RIGHT", 20, 0)

        row.Link = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.Link:SetPoint("TOPLEFT", row.Shown, "BOTTOMLEFT", 0, -4)

        -- UICheckButtonTemplate already ships the caption font string as Text,
        -- anchored to the right of the box, so it only needs its text set.
        row.MatchWidth = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.MatchWidth:SetPoint("LEFT", row.Link, "RIGHT", 20, 0)
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

        windowPanel.rows[index] = row
    end

    windowPanel:SetScript("OnShow", RefreshWindowPanel)

    -- The parent category is registered before this runs, so the category list
    -- has already been built; registering the subcategory is what rebuilds it
    -- and makes the page appear.
    local subcategory = Settings.RegisterCanvasLayoutSubcategory(category, windowPanel, "Windows")
    Settings.RegisterAddOnCategory(subcategory)
end

ns.RegisterModule("Config", Config)
