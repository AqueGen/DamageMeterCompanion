local addonName, ns = ...

ns.Snap = {}
local Snap = ns.Snap

Snap.MIN_WIDTH, Snap.MAX_WIDTH = 200, 600
Snap.MIN_HEIGHT, Snap.MAX_HEIGHT = 120, 400

function Snap.Clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function Overlaps(aLow, aHigh, bLow, bHigh)
    return aLow < bHigh and bLow < aHigh
end

-- Each edge pairing snaps the dragged window flush against the target. The
-- perpendicular offset is dropped on purpose: flush plus the matching size
-- flag from the caller is what makes a pair read as one block.
local function EdgeCandidates(rect, candidate)
    return {
        {
            gap = math.abs(rect.top - candidate.bottom),
            overlaps = Overlaps(rect.left, rect.right, candidate.left, candidate.right),
            point = "TOPLEFT", relPoint = "BOTTOMLEFT", axis = "vertical",
        },
        {
            gap = math.abs(rect.bottom - candidate.top),
            overlaps = Overlaps(rect.left, rect.right, candidate.left, candidate.right),
            point = "BOTTOMLEFT", relPoint = "TOPLEFT", axis = "vertical",
        },
        {
            gap = math.abs(rect.left - candidate.right),
            overlaps = Overlaps(rect.bottom, rect.top, candidate.bottom, candidate.top),
            point = "TOPLEFT", relPoint = "TOPRIGHT", axis = "horizontal",
        },
        {
            gap = math.abs(rect.right - candidate.left),
            overlaps = Overlaps(rect.bottom, rect.top, candidate.bottom, candidate.top),
            point = "TOPRIGHT", relPoint = "TOPLEFT", axis = "horizontal",
        },
    }
end

function Snap.FindSnap(rect, candidates, threshold)
    local best

    for _, candidate in ipairs(candidates) do
        if candidate.index ~= rect.index then
            for _, edge in ipairs(EdgeCandidates(rect, candidate)) do
                if edge.overlaps and edge.gap <= threshold and (not best or edge.gap < best.gap) then
                    best = {
                        gap = edge.gap,
                        index = candidate.index,
                        point = edge.point,
                        relPoint = edge.relPoint,
                        axis = edge.axis,
                    }
                end
            end
        end
    end

    return best
end

-- Walks the chain from the prospective target back up. Depth is at most three
-- in a healthy link set, but a corrupt saved set can hold a cycle that does not
-- pass through `from`, so the walk records what it has seen. A repeat means the
-- structure is already broken: refuse the link rather than extend it, and above
-- all return rather than spin - Lua has no preemption here, so a spin freezes
-- the whole client.
function Snap.WouldCycle(links, from, to)
    local current = to
    local seen = {}

    while current do
        if current == from or seen[current] then
            return true
        end

        seen[current] = true

        local link = links[current]
        current = link and link.to or nil
    end

    return false
end

function Snap.ApplyOrder(links)
    local order = {}
    local placed = {}

    local function Place(index)
        if placed[index] or not links[index] then
            return
        end

        placed[index] = true
        Place(links[index].to)
        table.insert(order, index)
    end

    for index = 1, 3 do
        Place(index)
    end

    return order
end

ns.RegisterModule("Snap", Snap)
