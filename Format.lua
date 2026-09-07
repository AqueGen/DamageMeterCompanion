local addonName, ns = ...

ns.Format = {}
local Format = ns.Format

-- The shape Details uses for its per-second column (Details/functions/util.lua),
-- copied because it is known to pass the client's restricted-breakpoint check
-- and because it renders exactly the strings this feature was specified to:
-- 56716000 -> 56.72M, 40639 -> 40.6K. Largest first, as the API requires.
Format.BREAKPOINTS = {
    { breakpoint = 1000000000, abbreviation = "B", significandDivisor = 10000000, fractionDivisor = 100, abbreviationIsGlobal = false },
    { breakpoint = 1000000, abbreviation = "M", significandDivisor = 10000, fractionDivisor = 100, abbreviationIsGlobal = false },
    { breakpoint = 1000, abbreviation = "K", significandDivisor = 100, fractionDivisor = 10, abbreviationIsGlobal = false },
    { breakpoint = 0.000001, abbreviation = "", significandDivisor = 1, fractionDivisor = 1, abbreviationIsGlobal = false },
}

-- Built once in Enable: CreateAbbreviateConfig refuses Secret input and the
-- breakpoints are plain numbers, so it is safe there and never needed again.
local options

-- True for a value we may hand on, whether or not we may look at it. A Secret
-- is never nil, and nil is never Secret, so the two checks cannot disagree.
local function Present(value)
    return issecretvalue(value) or value ~= nil
end

-- Decides what goes on the bar without ever comparing or computing with the
-- amounts themselves, so the same code serves both Secret and plain values.
-- Mirrors the choices of GetMainValue and GetParentheticalValue in
-- Blizzard_DamageMeter/DamageMeterEntry.lua, which are file-local.
function Format.Choose(entry)
    local displayType = entry:GetNumberDisplayType()
    local numbers = Enum.DamageMeterNumbers
    local primaryPerSecond = entry.showsValuePerSecondAsPrimary == true

    local main, parenthetical

    if primaryPerSecond and Present(entry.valuePerSecond) then
        main = entry.valuePerSecond
    else
        main = entry.value
    end

    if displayType ~= numbers.Minimal then
        if primaryPerSecond then
            if Present(entry.value) then
                parenthetical = entry.value
            end
        elseif not entry.suppressValuePerSecond then
            parenthetical = entry.valuePerSecond
        end
    end

    return main, parenthetical, displayType == numbers.Complete
end

-- The percentage is the one thing that needs arithmetic on the amounts, and
-- arithmetic on a Secret is refused. So it is shown when the values are
-- readable - out of combat - and dropped while they are not, which is the
-- honest version of what the numbers are in that moment.
local function Percentage(entry)
    local value, total = entry.value, entry.sessionTotalValue

    if issecretvalue(value) or issecretvalue(total) then
        return nil
    end

    if value == nil or total == nil or total <= 0 then
        return 0
    end

    return value / total
end

-- AbbreviateNumbers, string.format and SetText all accept Secret arguments from
-- tainted code - documented AllowedWhenTainted, and the exact chain Details
-- paints its own bars with. What we get back is a Secret string we cannot read,
-- which is fine: the bar can.
function Format.Compose(main, parenthetical, percentage)
    if not Present(main) then
        return nil
    end

    local mainText = AbbreviateNumbers(main, options)
    local parentheticalText = Present(parenthetical) and AbbreviateNumbers(parenthetical, options) or nil

    if parentheticalText and percentage then
        return ("%s (%s) %.1f%%"):format(mainText, parentheticalText, percentage * 100)
    elseif percentage then
        return ("%s %.1f%%"):format(mainText, percentage * 100)
    elseif parentheticalText then
        return ("%s (%s)"):format(mainText, parentheticalText)
    end

    return mainText
end

local function Repaint(entry)
    if ns.HasDeathRecap(entry) then
        return
    end

    local main, parenthetical, wantPercentage = Format.Choose(entry)
    local text = Format.Compose(main, parenthetical, wantPercentage and Percentage(entry) or nil)

    if text then
        entry:GetValue():SetText(text)
    end
end

-- Every entry frame on screen: each window's bars, its off-screen local player
-- row, and its spell breakdown.
local function ForEachEntry(func)
    ns.Windows.ForEach(function(window)
        if not window:IsShown() then
            return
        end

        window:GetScrollBox():ForEachFrame(func)

        local localPlayerEntry = window:GetLocalPlayerEntry()
        if localPlayerEntry and localPlayerEntry:IsShown() then
            func(localPlayerEntry)
        end

        local sourceWindow = window:GetSourceWindow()
        if sourceWindow:IsShown() then
            sourceWindow:ForEachEntryFrame(func)
        end
    end)
end

function Format.Sweep()
    if not ns.db.format or not options then
        return
    end

    ForEachEntry(function(entry)
        -- One bad row must not stop the rest, and a patch that renames a field
        -- would otherwise turn a cosmetic feature into an error five times a
        -- second.
        pcall(Repaint, entry)
    end)
end

-- Turning the feature off has to hand the bars back. Their UpdateValue rebuilds
-- Blizzard's own string and, called from here rather than from inside their
-- render pass, compares nothing of ours.
function Format.Restore()
    ForEachEntry(function(entry)
        pcall(entry.UpdateValue, entry)
    end)
end

-- Deliberately not a hook, and deliberately not reading the numbers.
--
-- The first version hooked DamageMeterEntryMixin:UpdateValue and did its own
-- arithmetic. Both were wrong on 12.x: a hooksecurefunc on anything Blizzard
-- calls while rendering the list carries our taint into their Secret
-- comparisons, and the amounts are Secret to addon code in combat, so there
-- was nothing to compute with. The client's own abbreviation routine takes a
-- Secret and hands back a Secret string, and the bar takes that string, which
-- is all the feature ever needed. Painting from our own timer keeps our code
-- off Blizzard's stack entirely.
function Format.Enable()
    local ok, config = pcall(CreateAbbreviateConfig, Format.BREAKPOINTS)

    if not ok or not config then
        ns.Print("readable numbers unavailable: the client refused the abbreviation breakpoints - " .. tostring(config))
        return
    end

    options = { config = config }

    -- Every frame, in and out of combat. In combat the meter rewrites every
    -- bar on each of its events, many times a second; out of combat it does
    -- so whenever a click opens the breakdown. An interval sweep left
    -- Blizzard's format on screen between our passes either way - visible as
    -- the numbers flickering between 3267 K and 3.27M. Painting every frame,
    -- after the frame's events and before its draw, means theirs is never
    -- what gets drawn. The walk is a handful of visible rows.
    ns.OnFrame(Format.Sweep)
end

ns.RegisterModule("Format", Format)
