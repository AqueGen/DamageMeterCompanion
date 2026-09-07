local addonName, ns = ...

ns.QuickButtons = {}
local QuickButtons = ns.QuickButtons

QuickButtons.HEIGHT = 18

-- The strip is only as wide as the window, so the full type names would not
-- fit even two to a row. The button's tooltip carries the full name, which is
-- where a player who does not recognise a label will look.
QuickButtons.SHORT_NAMES = {
    DamageDone = "DMG",
    Dps = "DPS",
    HealingDone = "HEAL",
    Hps = "HPS",
    Absorbs = "ABSORB",
    Interrupts = "KICKS",
    Dispels = "DISPEL",
    DamageTaken = "TAKEN",
    AvoidableDamageTaken = "AVOID",
    Deaths = "DEATHS",
    EnemyDamageTaken = "ENEMY",
}

-- Enum.DamageMeterType only exists once Blizzard's damage meter has loaded, so
-- the ordered list is built at enable time rather than at file scope.
local order = {}
local shortName = {}

-- Keyed by window, not by index: a window removed and rebuilt at the same index
-- is a different frame and must get a different strip.
local strips = {}

function QuickButtons.Order()
    return order
end

function QuickButtons.ShortName(damageMeterType)
    return shortName[damageMeterType] or tostring(damageMeterType)
end

-- Public so the tests can build the order table without Enable, which needs
-- frames.
function QuickButtons.BuildOrder()
    order, shortName = {}, {}

    -- The context menu's categories are already the order Blizzard groups these
    -- in, so the settings list reads the same way the menu does.
    for _, category in ipairs(ns.ContextMenu.CATEGORIES) do
        for _, damageMeterType in ipairs(category.types) do
            table.insert(order, damageMeterType)
        end
    end

    for name, value in pairs(Enum.DamageMeterType) do
        shortName[value] = QuickButtons.SHORT_NAMES[name] or name:upper()
    end
end

function QuickButtons.IsSelected(damageMeterType)
    return ns.db.quickTypes[damageMeterType] == true
end

function QuickButtons.SetSelected(damageMeterType, selected)
    ns.db.quickTypes[damageMeterType] = selected or nil
    QuickButtons.RebuildAll()
end

-- Only the types the player asked for, in the fixed order above rather than in
-- the order they happened to be ticked.
function QuickButtons.SelectedTypes()
    local selected = {}

    for _, damageMeterType in ipairs(order) do
        if QuickButtons.IsSelected(damageMeterType) then
            table.insert(selected, damageMeterType)
        end
    end

    return selected
end

local function ApplyHighlight(strip)
    local current = strip.window:GetDamageMeterType()

    for _, button in ipairs(strip.buttons) do
        if button.damageMeterType == current then
            button:LockHighlight()
        else
            button:UnlockHighlight()
        end
    end
end

-- Widths are recomputed rather than anchored to each other so the row always
-- fills the strip exactly, whatever the window is resized to.
local function LayoutStrip(strip)
    local count = #strip.buttons
    if count == 0 then
        return
    end

    local width = strip:GetWidth()
    if not width or width <= 0 then
        return
    end

    local each = width / count

    for position, button in ipairs(strip.buttons) do
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", strip, "TOPLEFT", math.floor((position - 1) * each + 0.5), 0)
        button:SetSize(math.floor(position * each + 0.5) - math.floor((position - 1) * each + 0.5), QuickButtons.HEIGHT)
    end
end

local function RebuildStrip(strip)
    for _, button in ipairs(strip.buttons) do
        button:Hide()
        button:ClearAllPoints()
    end

    strip.buttons = {}

    if not ns.db.quickButtons then
        strip:Hide()
        return
    end

    local window = strip.window

    for _, damageMeterType in ipairs(QuickButtons.SelectedTypes()) do
        -- Pooled by position: rebuilds happen on every settings change, and a
        -- frame cannot be destroyed, so reuse is the only way this does not
        -- leak a button per change.
        local position = #strip.buttons + 1
        local button = strip.pool[position]

        if not button then
            button = CreateFrame("Button", nil, strip, "UIPanelButtonTemplate")
            local label = button:GetFontString()
            if label then
                label:SetFontObject("GameFontNormalSmall")
            end

            button:SetScript("OnClick", function(self)
                window:GetDamageMeterOwner():SetSessionWindowDamageMeterType(window, self.damageMeterType)
                ApplyHighlight(strip)
            end)

            button:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(ns.ContextMenu.GetTypeName(self.damageMeterType))
                GameTooltip:Show()
            end)

            button:SetScript("OnLeave", GameTooltip_Hide)

            strip.pool[position] = button
        end

        button.damageMeterType = damageMeterType
        button:SetText(QuickButtons.ShortName(damageMeterType))
        button:Show()

        table.insert(strip.buttons, button)
    end

    -- A window whose mouse is off should not offer buttons that still take
    -- clicks, and an empty selection leaves nothing to draw.
    strip:SetShown(#strip.buttons > 0 and not window:IsNonInteractive())

    LayoutStrip(strip)
    ApplyHighlight(strip)
end

local function AttachWindow(window)
    if strips[window] then
        return
    end

    local strip = CreateFrame("Frame", nil, window)
    strip.window = window
    strip.buttons = {}
    strip.pool = {}

    -- Above the window rather than inside it: the header is Blizzard's and the
    -- body is bars, so anywhere inside would cost the player a row of data.
    -- Above also keeps the strip out of the window's own rect, which is what
    -- snapping measures.
    strip:SetHeight(QuickButtons.HEIGHT)
    strip:SetPoint("BOTTOMLEFT", window, "TOPLEFT", 0, 1)
    strip:SetPoint("BOTTOMRIGHT", window, "TOPRIGHT", 0, 1)

    strip:SetScript("OnSizeChanged", function()
        LayoutStrip(strip)
    end)

    strips[window] = strip

    -- Covers every path that changes the type - our buttons, the right-click
    -- menu and the window's own header dropdown - rather than only the ones we
    -- own.
    ns.HookInstance(window, "SetDamageMeterType", function()
        ApplyHighlight(strip)
    end)

    ns.HookInstance(window, "SetNonInteractive", function()
        RebuildStrip(strip)
    end)

    RebuildStrip(strip)
end

function QuickButtons.RebuildAll()
    for _, strip in pairs(strips) do
        RebuildStrip(strip)
    end
end

function QuickButtons.Enable()
    QuickButtons.BuildOrder()

    if not ns.db.quickTypes then
        ns.db.quickTypes = {
            [Enum.DamageMeterType.DamageDone] = true,
            [Enum.DamageMeterType.Dps] = true,
            [Enum.DamageMeterType.HealingDone] = true,
            [Enum.DamageMeterType.Hps] = true,
        }
    end

    ns.Windows.ForEach(AttachWindow)
    ns.Windows.OnCreated(AttachWindow)

    -- Blizzard's windows 2 and 3 are built the first time they are shown, which
    -- is after this walk.
    ns.HookInstance(DamageMeter, "SetupSessionWindow", function(_, _, windowData)
        if windowData.sessionWindow then
            AttachWindow(windowData.sessionWindow)
        end
    end)
end

ns.RegisterModule("QuickButtons", QuickButtons)
