local addonName, ns = ...

ns.Format = {}
local Format = ns.Format

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

-- Runs after Blizzard has already set its own text, so bailing out simply
-- leaves the original string in place.
local function OnUpdateValue(entry)
    if not ns.db.format then
        return
    end

    if ns.HasDeathRecap(entry) then
        return
    end

    if ns.IsAnySecret(entry.value, entry.valuePerSecond, entry.sessionTotalValue) then
        return
    end

    entry:GetValue():SetText(Format.Compose(Format.SelectValues(entry)))
end

function Format.Enable()
    -- Entry frames are pooled and mostly created later, which the mixin hook
    -- covers. Any that the meter already built before we loaded carry a copy
    -- of the original method and need hooking individually.
    hooksecurefunc(DamageMeterEntryMixin, "UpdateValue", OnUpdateValue)
    ns.ForEachEntryFrame(function(entry)
        ns.HookInstance(entry, "UpdateValue", OnUpdateValue)
    end)
end

ns.RegisterModule("Format", Format)
