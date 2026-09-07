local addonName, ns = ...

ns.Format = {}
local Format = ns.Format

-- How often the visible bars are repainted. This is what replaces the hook that
-- used to do the same work at exactly the right moment.
Format.INTERVAL = 0.2

local UNITS = {
    { threshold = 1e9, suffix = "B" },
    { threshold = 1e6, suffix = "M" },
    { threshold = 1e3, suffix = "K" },
}

-- Blizzard's AbbreviateLargeNumbers stops at thousands, which produces
-- unreadable strings like "56716 K" at current damage scales.
function Format.Abbreviate(value, decimals)
    value = value or 0

    if value < 0 then
        return "-" .. Format.Abbreviate(-value, decimals)
    end

    for _, unit in ipairs(UNITS) do
        if value >= unit.threshold then
            return ("%." .. decimals .. "f%s"):format(value / unit.threshold, unit.suffix)
        end
    end

    return ("%d"):format(value)
end

-- Mirrors the selection rules of GetMainValue, GetParentheticalValue and
-- GetPercentageValue in Blizzard_DamageMeter/DamageMeterEntry.lua, which are
-- file-local and cannot be reused.
function Format.SelectValues(entry)
    local numbers = Enum.DamageMeterNumbers
    -- The method, not the field: DamageMeterSpellEntryMixin overrides it to
    -- force Complete, and the field is nil on every spell row.
    local displayType = entry:GetNumberDisplayType()

    local main
    if entry.valuePerSecond and entry.showsValuePerSecondAsPrimary then
        main = entry.valuePerSecond
    else
        main = entry.value or 0
    end

    local parenthetical
    if displayType ~= numbers.Minimal then
        if entry.value and entry.showsValuePerSecondAsPrimary then
            parenthetical = entry.value
        elseif not entry.suppressValuePerSecond then
            parenthetical = entry.valuePerSecond or 0
        end
    end

    local percentage
    if displayType == numbers.Complete then
        if entry.value and entry.sessionTotalValue and entry.sessionTotalValue > 0 then
            percentage = entry.value / entry.sessionTotalValue
        else
            percentage = 0
        end
    end

    return main, parenthetical, percentage
end

function Format.Compose(main, parenthetical, percentage)
    local mainText = Format.Abbreviate(main, 2)

    if parenthetical and percentage then
        return ("%s (%s) %.1f%%"):format(mainText, Format.Abbreviate(parenthetical, 1), percentage * 100)
    elseif percentage then
        return ("%s %.1f%%"):format(mainText, percentage * 100)
    elseif parenthetical then
        return ("%s (%s)"):format(mainText, Format.Abbreviate(parenthetical, 1))
    end

    return mainText
end

-- Set when a row's values turn out to be Secret, which means the sweep has
-- nothing more to do this tick: secrecy is a property of the moment, not of one
-- row. Reading it is what tells us whether combat blocks us, instead of
-- assuming it always does.
local secretSeen = false

local function Repaint(entry)
    if ns.HasDeathRecap(entry) then
        return
    end

    if ns.IsAnySecret(entry.value, entry.valuePerSecond, entry.sessionTotalValue) then
        secretSeen = true
        return
    end

    entry:GetValue():SetText(Format.Compose(Format.SelectValues(entry)))
end

-- Puts Blizzard's own string back. Their UpdateValue is the only thing that
-- knows how to build it, and calling it out of combat is safe because nothing
-- it reads is Secret then. Only ever called from the sweep, so it never runs
-- inside Blizzard's own execution.
local function Restore(entry)
    if type(entry.UpdateValue) == "function" then
        entry:UpdateValue()
    end
end

local restorePending = false

-- Turning the feature off has to hand the bars back, and a single pass does it:
-- there is nothing to keep repainting afterwards.
function Format.RequestRestore()
    restorePending = true
end

function Format.Sweep()
    local apply = ns.db.format and Repaint or (restorePending and Restore or nil)

    if not apply then
        return
    end

    restorePending = false
    secretSeen = false

    ns.ForEachEntryFrame(function(entry)
        -- One bad row must not stop the rest of the list being painted, and a
        -- patch that renames a field would otherwise turn a cosmetic feature
        -- into an error every fifth of a second.
        if not secretSeen then
            pcall(apply, entry)
        end
    end)
end

-- Deliberately not a hook.
--
-- Every earlier version hooked DamageMeterEntryMixin:UpdateValue, which put our
-- taint on Blizzard's own execution: their entry setup then compares Secret
-- fields - sourceDisplayType among them - and the game logs
-- "attempt to compare field ... while execution tainted by ...". That is true
-- of any hooksecurefunc on a function Blizzard calls while it renders the list,
-- whatever the hook body does.
--
-- Painting from our own timer instead means our code is never on their stack.
-- It costs up to one interval of Blizzard's formatting after a change.
--
-- The sweep deliberately does NOT refuse to run in combat. Whether the values
-- can be read is a question issecretvalue answers per row, and answering it is
-- free; assuming combat always hides them was a guess, and it cost the feature
-- exactly when the numbers are worth reading.
function Format.Enable()
    local elapsed = 0

    local driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta

        if elapsed < Format.INTERVAL then
            return
        end

        elapsed = 0

        Format.Sweep()
    end)

    Format.driver = driver
end

ns.RegisterModule("Format", Format)
