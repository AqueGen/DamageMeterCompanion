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

-- labelFormat is a format string, applied to the value shown beside the slider.
-- Without it a fractional slider prints the raw number, float noise and all.
local function AddSlider(variableKey, name, tooltip, minimum, maximum, step, labelFormat, onChange)
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

    AddCheckbox("format", "Readable numbers",
        "Show 56.72M instead of 56716 K. Only applies once the values stop being secret, which is after combat.",
        function()
            -- Our text is written from a post-hook on UpdateValue, so nothing
            -- already on screen changes until something re-renders it. Out of
            -- combat that could be minutes, which would read as a dead toggle.
            -- In combat there is nothing to repaint - the values are secret and
            -- the formatting does not apply - and Refresh compares them, so
            -- calling it from our tainted stack would be all risk and no gain.
            if UnitAffectingCombat("player") then
                return
            end

            ns.Windows.ForEach(function(window)
                window:Refresh(ScrollBoxConstants.RetainScrollPosition)
                window:GetSourceWindow():Refresh(ScrollBoxConstants.RetainScrollPosition)
            end)
        end)

    AddCheckbox("snap", "Snap windows together",
        "Dragging a window near another attaches it, and they move and resize together.")

    AddSlider("snapThreshold", "Snap distance",
        "How close an edge must be, in pixels, before it snaps.", 5, 40, 1)

    AddSlider("idleAlpha", "Idle transparency",
        "How visible the meter is when the mouse is not on it, as a fraction of the Edit Mode transparency. "
            .. "A window set to uninteractable stays at the idle value, because its mouse is disabled.",
        0.1, 1, 0.05, "%.2f", function()
            ns.Presence.ApplyAlphaToAll()
        end)

    local strataSetting = Settings.RegisterProxySetting(category, "DMT_strata",
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

-- Forward declared: CreateSizeBox below refreshes the panel after an edit.
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
        local window = DamageMeter:GetSessionWindow(index)
        local value = tonumber(self:GetText())

        -- The window-level check, not the owner-level one: it is the only
        -- variant that consults the lock, and every other resize path in this
        -- addon already honours it.
        if window and value and window:CanMoveOrResize() then
            if dimension == "width" then
                window:SetWidth(ns.Snap.Clamp(value, ns.Snap.MIN_WIDTH, ns.Snap.MAX_WIDTH))
            else
                window:SetHeight(ns.Snap.Clamp(value, ns.Snap.MIN_HEIGHT, ns.Snap.MAX_HEIGHT))
            end
        end

        self:ClearFocus()
        RefreshWindowPanel()
    end)

    return box
end

function RefreshWindowPanel()
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

        -- Window 1 never gets the size boxes: Edit Mode owns its size, which is
        -- what the note says. A locked window keeps them, greyed out, so the
        -- panel says why the edit is refused instead of swallowing it.
        local resizable = shown and window:CanMoveOrResize()

        row.Width:SetShown(not isPrimary)
        row.Width:SetEnabled(resizable)
        row.Height:SetShown(not isPrimary)
        row.Height:SetEnabled(resizable)

        if shown and not isPrimary then
            -- Never overwrite a box the user is typing in; the throttled
            -- refresh below runs while the page is open.
            if not row.Width:HasFocus() then
                row.Width:SetText(math.floor(window:GetWidth() + 0.5))
            end

            if not row.Height:HasFocus() then
                row.Height:SetText(math.floor(window:GetHeight() + 0.5))
            end
        else
            row.Width:SetText("")
            row.Height:SetText("")
        end

        row.Note:SetText(isPrimary and "Size and position are controlled by Edit Mode." or "")
        row.Link:SetText(link and ("attached to window " .. link.to) or "not attached")
        row.MatchWidth:SetChecked(link and link.matchWidth or false)
        row.MatchWidth:SetEnabled(link ~= nil and not isPrimary)
        row.MatchHeight:SetChecked(link and link.matchHeight or false)
        row.MatchHeight:SetEnabled(link ~= nil and not isPrimary)
        row.Detach:SetEnabled(link ~= nil and not isPrimary)
    end
end

-- The panel deliberately offers no way to attach a window: snapping is a drag
-- gesture, and a control duplicating it would be a second way to do the same
-- thing. The page shows the link, its match flags and a Detach button.
function Config.BuildWindowPanel()
    -- A plain frame, not SettingsListTemplate: the canvas subcategory sizes the
    -- frame to fill the panel, and the template would add a list we do not use.
    -- Nothing here scrolls - SettingsCanvas nops the mouse wheel - so the three
    -- rows are laid out to fit; a fourth would overflow with no way to reach it.
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

        row.Width = CreateSizeBox(row, index, "width")
        row.Width:SetPoint("LEFT", row.Size, "RIGHT", 12, 0)

        row.Height = CreateSizeBox(row, index, "height")
        row.Height:SetPoint("LEFT", row.Width, "RIGHT", 8, 0)

        row.Note = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        row.Note:SetPoint("LEFT", row.Height, "RIGHT", 20, 0)

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
