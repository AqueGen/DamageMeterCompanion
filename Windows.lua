local addonName, ns = ...

ns.Windows = {}
local Windows = ns.Windows

-- Blizzard's own MAX_DAMAGE_METER_SESSION_WINDOWS, which is file-local to
-- DamageMeter.lua. Windows above this index are created and owned by us.
Windows.BLIZZARD_WINDOW_COUNT = 3

-- Not a limit. Past this many windows we say once that each one is a scroll
-- box refreshed on every combat event, and let the player decide.
Windows.SOFT_CAP = 10

function Windows.IsOurs(index)
    return index > Windows.BLIZZARD_WINDOW_COUNT
end

function Windows.NextFreeIndex(taken)
    local index = Windows.BLIZZARD_WINDOW_COUNT + 1

    while taken[index] do
        index = index + 1
    end

    return index
end

function Windows.SortedIndices(set)
    local indices = {}

    for index in pairs(set) do
        table.insert(indices, index)
    end

    table.sort(indices)

    return indices
end

-- Frames we created, keyed by index. Blizzard's live in its own window data
-- list and are reached through the owner.
local ourWindows = {}

function Windows.Get(index)
    if Windows.IsOurs(index) then
        return ourWindows[index]
    end

    return DamageMeter:GetSessionWindow(index)
end

function Windows.Indices()
    local present = {}

    for index = 1, Windows.BLIZZARD_WINDOW_COUNT do
        if DamageMeter:GetSessionWindow(index) then
            present[index] = true
        end
    end

    for index in pairs(ourWindows) do
        present[index] = true
    end

    return Windows.SortedIndices(present)
end

function Windows.ForEach(func)
    for _, index in ipairs(Windows.Indices()) do
        local window = Windows.Get(index)
        if window then
            func(window, index)
        end
    end
end

ns.RegisterModule("Windows", Windows)
