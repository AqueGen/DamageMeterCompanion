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

local function RectOf(window, index)
    local left, bottom, width, height = window:GetRect()

    return {
        index = index,
        left = left,
        right = left + width,
        top = bottom + height,
        bottom = bottom,
    }
end

local function GetLinks()
    return ns.charDb.links
end

local applyingSize = false

-- Pushes this window's size onto every window linked to it that asked to match
-- an axis. The guard stops a mutual match from bouncing; a chain settles in one
-- pass because each SetWidth that actually changes the size fires OnSizeChanged
-- again from the child.
function Snap.PushSize(index)
    if applyingSize then
        return
    end

    local source = DamageMeter:GetSessionWindow(index)
    if not source then
        return
    end

    applyingSize = true

    for otherIndex, link in pairs(GetLinks()) do
        if link.to == index then
            local target = DamageMeter:GetSessionWindow(otherIndex)
            if target and DamageMeter:CanMoveOrResizeSessionWindow(target) then
                if link.matchWidth then
                    target:SetWidth(Snap.Clamp(source:GetWidth(), Snap.MIN_WIDTH, Snap.MAX_WIDTH))
                end

                if link.matchHeight then
                    target:SetHeight(Snap.Clamp(source:GetHeight(), Snap.MIN_HEIGHT, Snap.MAX_HEIGHT))
                end
            end
        end
    end

    applyingSize = false
end

function Snap.ApplyLink(index)
    local link = GetLinks()[index]
    local window = DamageMeter:GetSessionWindow(index)
    local target = link and DamageMeter:GetSessionWindow(link.to)

    if not link or not window or not target or not target:IsShown() then
        return
    end

    if not DamageMeter:CanMoveOrResizeSessionWindow(window) then
        return
    end

    window:ClearAllPoints()
    window:SetPoint(link.point, target, link.relPoint, 0, 0)

    -- Blizzard's saved frame position cache would otherwise fight the anchor.
    window:SetUserPlaced(false)

    Snap.PushSize(link.to)
end

function Snap.ApplyAll()
    for _, index in ipairs(Snap.ApplyOrder(GetLinks())) do
        Snap.ApplyLink(index)
    end
end

function Snap.SetLink(index, link)
    GetLinks()[index] = link
    Snap.ApplyLink(index)
end

function Snap.ClearLink(index)
    GetLinks()[index] = nil
end

local function CollectCandidates(exceptIndex)
    local candidates = {}

    ns.ForEachSessionWindow(function(window, index)
        if index ~= exceptIndex and window:IsShown() then
            table.insert(candidates, RectOf(window, index))
        end
    end)

    return candidates
end

function Snap.AddMenuEntries(rootDescription, sessionWindow)
    local index = sessionWindow:GetSessionWindowIndex()
    local link = GetLinks()[index]

    if not link then
        return
    end

    rootDescription:CreateDivider()

    rootDescription:CreateCheckbox(DAMAGE_METER_TWEAKS_MATCH_WIDTH,
        function() return link.matchWidth end,
        function()
            link.matchWidth = not link.matchWidth
            Snap.PushSize(link.to)
        end)

    rootDescription:CreateCheckbox(DAMAGE_METER_TWEAKS_MATCH_HEIGHT,
        function() return link.matchHeight end,
        function()
            link.matchHeight = not link.matchHeight
            Snap.PushSize(link.to)
        end)
end

function Snap.Enable()
    DAMAGE_METER_TWEAKS_MATCH_WIDTH = "Match width"
    DAMAGE_METER_TWEAKS_MATCH_HEIGHT = "Match height"

    local function OnDragStop(window)
        if not ns.db.snap then
            return
        end

        local index = window:GetSessionWindowIndex()
        if not DamageMeter:CanMoveOrResizeSessionWindow(window) then
            return
        end

        local result = Snap.FindSnap(RectOf(window, index), CollectCandidates(index), ns.db.snapThreshold)

        if not result or Snap.WouldCycle(GetLinks(), index, result.index) then
            Snap.ClearLink(index)
            return
        end

        Snap.SetLink(index, {
            to = result.index,
            point = result.point,
            relPoint = result.relPoint,
            -- The axis perpendicular to the edge we landed on is the one that
            -- has to agree for the pair to read as one block.
            matchWidth = result.axis == "vertical",
            matchHeight = result.axis == "horizontal",
        })
    end

    -- Mixin hook for windows created later, instance hooks for the ones that
    -- already exist and carry their own copy of OnDragStop.
    hooksecurefunc(DamageMeterSessionWindowMixin, "OnDragStop", OnDragStop)

    ns.ForEachSessionWindow(function(window, index)
        ns.HookInstance(window, "OnDragStop", OnDragStop)

        window.dmtSizeHooked = true
        window:HookScript("OnSizeChanged", function()
            Snap.PushSize(index)
        end)
    end)

    -- Windows created later, through Show new window, need the same size hook.
    -- DamageMeter already exists, so this one must be an instance hook.
    ns.HookInstance(DamageMeter, "SetupSessionWindow", function(_, windowDataIndex, windowData)
        local window = windowData.sessionWindow
        if window and not window.dmtSizeHooked then
            window.dmtSizeHooked = true
            window:HookScript("OnSizeChanged", function()
                Snap.PushSize(windowDataIndex)
            end)
        end
    end)

    -- Blizzard restores its saved frame positions during login; applying on the
    -- next frame puts our anchors on top of that rather than under it.
    C_Timer.After(0, Snap.ApplyAll)
end

ns.RegisterModule("Snap", Snap)
