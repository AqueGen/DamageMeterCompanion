local addonName, ns = ...

-- Hover a bar and a breakdown of that source's spells appears beside the
-- window. It is our own frame, fed straight from C_DamageMeter - Blizzard's
-- source window is never touched, which is what lets this exist at all on
-- 12.x: opening theirs from addon code writes fields their refresh reads, and
-- that poisons the window until /reload.
--
-- Everything the rows show goes through APIs documented AllowedWhenTainted -
-- C_Spell.GetSpellName / GetSpellTexture, AbbreviateNumbers, SetText,
-- SetTexture - so a Secret spell ID in combat is a Secret name, a Secret
-- icon and a Secret string on the bar, never a value we read. The same chain
-- EnhanceQoL and Details paint with.
ns.Hover = {}
local Hover = ns.Hover

Hover.MAX_ROWS = 12
Hover.ROW_HEIGHT = 20
Hover.WIDTH = 260

local frame
local current -- { window = ..., guid = ..., creatureID = ... } while shown
local pendingTimer
local attached = setmetatable({}, { __mode = "k" })

local function CancelPending()
    if pendingTimer then
        pendingTimer:Cancel()
        pendingTimer = nil
    end
end

local PARTY_TOKENS = { "party1", "party2", "party3", "party4" }

-- The row's own GUID is Secret in combat and stays Secret in the rows until
-- Blizzard fetches again, but a GUID from a unit token is not, and passing a
-- plain GUID to the API is allowed. The player is trivial; a party member is
-- found by class when that class is unique in the party - the row's
-- classFilename is NeverSecret. Raids are too big for that guess.
local function ResolveSource(elementData)
    if not issecretvalue(elementData.sourceGUID) and elementData.sourceGUID then
        return elementData.sourceGUID, nil
    end

    if not issecretvalue(elementData.sourceCreatureID) and elementData.sourceCreatureID then
        return nil, elementData.sourceCreatureID
    end

    if elementData.isLocalPlayer then
        return UnitGUID("player"), nil
    end

    local classFilename = elementData.classFilename
    if type(classFilename) ~= "string" or classFilename == "" or IsInRaid() then
        return nil, nil
    end

    local match
    for _, token in ipairs(PARTY_TOKENS) do
        if UnitExists(token) then
            local _, unitClass = UnitClass(token)
            if unitClass == classFilename then
                if match then
                    return nil, nil
                end
                match = token
            end
        end
    end

    return match and UnitGUID(match) or nil, nil
end

local function Fetch(window, guid, creatureID)
    local damageMeterType = window:GetDamageMeterType()
    local sessionType = window:GetSessionType()

    if sessionType then
        return C_DamageMeter.GetCombatSessionSourceFromType(sessionType, damageMeterType, guid, creatureID)
    end

    local sessionID = window:GetSessionID()
    if sessionID then
        return C_DamageMeter.GetCombatSessionSourceFromID(sessionID, damageMeterType, guid, creatureID)
    end

    return nil
end

local function GetFrame()
    if frame then
        return frame
    end

    frame = CreateFrame("Frame", "DamageMeterCompanionDetails", UIParent)
    frame:SetSize(Hover.WIDTH, Hover.ROW_HEIGHT)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:Hide()

    frame.Background = frame:CreateTexture(nil, "BACKGROUND")
    frame.Background:SetAllPoints()
    frame.Background:SetColorTexture(0, 0, 0, 0.75)

    frame.rows = {}
    for i = 1, Hover.MAX_ROWS do
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(Hover.WIDTH, Hover.ROW_HEIGHT)
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(i - 1) * Hover.ROW_HEIGHT)

        row.Icon = row:CreateTexture(nil, "ARTWORK")
        row.Icon:SetSize(Hover.ROW_HEIGHT - 4, Hover.ROW_HEIGHT - 4)
        row.Icon:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        row.Value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.Value:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.Value:SetJustifyH("RIGHT")

        row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.Name:SetPoint("LEFT", row.Icon, "RIGHT", 6, 0)
        row.Name:SetPoint("RIGHT", row.Value, "LEFT", -6, 0)
        row.Name:SetJustifyH("LEFT")
        row.Name:SetWordWrap(false)

        row:Hide()
        frame.rows[i] = row
    end

    return frame
end

-- Beside the window on whichever side has more room, the way Blizzard's own
-- breakdown places itself.
local function Anchor(window)
    local f = GetFrame()
    f:ClearAllPoints()

    local centerX = window:GetCenter()
    local screenCenterX = UIParent:GetCenter()

    if centerX and screenCenterX and centerX < screenCenterX then
        f:SetPoint("TOPLEFT", window, "TOPRIGHT", 2, 0)
    else
        f:SetPoint("TOPRIGHT", window, "TOPLEFT", -2, 0)
    end
end

function Hover.Paint()
    if not current then
        return
    end

    local f = GetFrame()
    local source = Fetch(current.window, current.guid, current.creatureID)
    local spells = source and source.combatSpells or {}
    local shown = 0

    for i, row in ipairs(f.rows) do
        local spell = spells[i]

        if spell then
            -- Secret in, Secret out, and the widgets accept it: no arithmetic,
            -- no comparison, no reading on our side.
            local spellID = spell.spellID
            local hasSpell = issecretvalue(spellID) or spellID ~= nil
            local texture = hasSpell and C_Spell.GetSpellTexture(spellID) or nil
            local name = hasSpell and C_Spell.GetSpellName(spellID) or nil

            if issecretvalue(texture) or texture ~= nil then
                row.Icon:SetTexture(texture)
                row.Icon:Show()
            else
                row.Icon:Hide()
            end

            row.Name:SetText((issecretvalue(name) or name ~= nil) and name or "")
            row.Value:SetText(ns.Format.Compose(spell.totalAmount, spell.amountPerSecond) or "")
            row:Show()
            shown = shown + 1
        else
            row:Hide()
        end
    end

    f:SetHeight(math.max(shown, 1) * Hover.ROW_HEIGHT)
end

function Hover.Show(window, elementData)
    local guid, creatureID = ResolveSource(elementData)
    if not guid and not creatureID then
        return
    end

    current = { window = window, guid = guid, creatureID = creatureID }
    Anchor(window)
    Hover.Paint()
    GetFrame():Show()
end

function Hover.Hide()
    current = nil
    if frame then
        frame:Hide()
    end
end

local function ElementDataOf(window, entry)
    if entry.GetElementData then
        return entry:GetElementData()
    end

    if entry == window:GetLocalPlayerEntry() and window.localPlayerIndex then
        return window:GetScrollBox():FindElementData(window.localPlayerIndex)
    end

    return nil
end

local function OnEnter(window, entry)
    if not ns.db.hover then
        return
    end

    -- Blizzard's own breakdown on screen means the player clicked; theirs wins.
    if window:GetSourceWindow():IsShown() then
        return
    end

    local elementData = ElementDataOf(window, entry)
    if not elementData or ns.HasDeathRecap(elementData) then
        return
    end

    CancelPending()
    pendingTimer = C_Timer.NewTimer(ns.db.hoverDelay, function()
        pendingTimer = nil
        if entry:IsMouseOver() and entry:IsVisible() and not window:GetSourceWindow():IsShown() then
            Hover.Show(window, elementData)
        end
    end)
end

local function OnLeave()
    CancelPending()

    -- One frame of grace so the cursor can cross into the breakdown itself.
    C_Timer.After(0, function()
        if frame and frame:IsShown() and not frame:IsMouseOver() then
            local stillOnBar = false
            ns.Windows.ForEach(function(window)
                window:GetScrollBox():ForEachFrame(function(entry)
                    if entry:IsMouseOver() then
                        stillOnBar = true
                    end
                end)
            end)

            if not stillOnBar then
                Hover.Hide()
            end
        end
    end)
end

-- Script hooks on scripts Blizzard never sets for an entry: C-side, and our
-- handler is the only body, so nothing of Blizzard's runs inside our taint.
local function Attach(window, entry)
    if attached[entry] then
        return
    end

    attached[entry] = true
    entry:HookScript("OnEnter", function() OnEnter(window, entry) end)
    entry:HookScript("OnLeave", OnLeave)
end

function Hover.Sweep()
    if ns.db.hover then
        ns.Windows.ForEach(function(window)
            if window:IsShown() then
                window:GetScrollBox():ForEachFrame(function(entry)
                    Attach(window, entry)
                end)

                local localPlayerEntry = window:GetLocalPlayerEntry()
                if localPlayerEntry then
                    Attach(window, localPlayerEntry)
                end
            end
        end)
    end

    if current then
        if not current.window:IsShown() or current.window:GetSourceWindow():IsShown() then
            Hover.Hide()
            return
        end

        Hover.Paint()
    end
end

function Hover.Enable()
    ns.OnSweep(Hover.Sweep)

    -- The breakdown's own frame holds the mouse while the cursor is inside it;
    -- leaving it is the one edge the entries' OnLeave cannot see.
    local f = GetFrame()
    f:SetScript("OnLeave", OnLeave)
    f:EnableMouse(true)
end

ns.RegisterModule("Hover", Hover)
