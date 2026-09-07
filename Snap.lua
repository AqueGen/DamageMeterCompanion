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

-- Walks the links pointing at `index` and pushes this window's size onto each
-- one that asked to match an axis, then continues down that window's own
-- dependents.
--
-- The propagation is explicit rather than event-driven on purpose. Setting a
-- frame's size dispatches OnSizeChanged re-entrantly - Blizzard's own ScrollBox
-- nulls its handler during updates for exactly that reason - so the nested
-- event a SetWidth fires is swallowed by the guard below. Relying on it would
-- resize the first window in a chain and silently leave the rest behind.
--
-- A locked window is skipped: the lock means the user asked for that window to
-- stay put, and resizing it from a neighbour would break that promise.
local function PushSizeFrom(index, visited)
    if visited[index] then
        return
    end

    visited[index] = true

    local source = DamageMeter:GetSessionWindow(index)
    if not source then
        return
    end

    for otherIndex, link in pairs(GetLinks()) do
        if link.to == index then
            local target = DamageMeter:GetSessionWindow(otherIndex)
            if target and target:CanMoveOrResize() then
                if link.matchWidth then
                    target:SetWidth(Snap.Clamp(source:GetWidth(), Snap.MIN_WIDTH, Snap.MAX_WIDTH))
                end

                if link.matchHeight then
                    target:SetHeight(Snap.Clamp(source:GetHeight(), Snap.MIN_HEIGHT, Snap.MAX_HEIGHT))
                end

                PushSizeFrom(otherIndex, visited)
            end
        end
    end
end

-- The guard keeps the re-entrant OnSizeChanged events our own SetWidth and
-- SetHeight calls dispatch from starting a second walk on top of this one.
function Snap.PushSize(index)
    if applyingSize then
        return
    end

    applyingSize = true
    PushSizeFrom(index, {})
    applyingSize = false
end

function Snap.ApplyLink(index)
    local link = GetLinks()[index]
    local window = DamageMeter:GetSessionWindow(index)
    local target = link and DamageMeter:GetSessionWindow(link.to)

    -- SetLink refuses a self-link, but a hand-edited saved variable reaches
    -- here through ApplyAll at login and would anchor a frame to itself.
    if not link or link.to == index or not window or not target or not target:IsShown() then
        return
    end

    -- Deliberately the owner-level check, not the window's own CanMoveOrResize:
    -- restoring an anchor the window already has is not moving it against the
    -- user's wishes, so a locked window keeps its link across a reload instead
    -- of silently detaching.
    if not DamageMeter:CanMoveOrResizeSessionWindow(window) then
        return
    end

    window:ClearAllPoints()
    window:SetPoint(link.point, target, link.relPoint, 0, 0)

    -- Keeps our anchored position out of Blizzard's frame position cache, so
    -- next login does not re-impose it as an absolute point.
    window:SetUserPlaced(false)

    Snap.PushSize(link.to)
end

function Snap.ApplyAll()
    for _, index in ipairs(Snap.ApplyOrder(GetLinks())) do
        Snap.ApplyLink(index)
    end
end

-- Every validation lives here rather than at the call site, because the
-- settings panel in Task 9 sets links too. A link from the primary window, a
-- self-link, or one that closes a cycle is refused: the first cannot be
-- applied, the second is a frame anchored to itself, and the third would be
-- persisted past the check that exists to prevent it.
function Snap.SetLink(index, link)
    local window = DamageMeter:GetSessionWindow(index)

    if not window
        or not DamageMeter:CanMoveOrResizeSessionWindow(window)
        or link.to == index
        or Snap.WouldCycle(GetLinks(), index, link.to) then
        return false
    end

    GetLinks()[index] = link
    Snap.ApplyLink(index)

    return true
end

-- Dropping a link has to hand the window back its own position. It is still
-- anchored to its old target and still flagged not-user-placed, so without
-- this it would keep following that window until the next reload and then come
-- back at Blizzard's default offset with nothing to move it.
function Snap.ClearLink(index)
    local window = DamageMeter:GetSessionWindow(index)

    if not GetLinks()[index] then
        return
    end

    GetLinks()[index] = nil

    if not window or not DamageMeter:CanMoveOrResizeSessionWindow(window) then
        return
    end

    local left, bottom, width, height = window:GetRect()

    -- A hidden window may have no resolved rect; there is nothing to hand back
    -- in that case, and the link is already gone.
    if not left then
        return
    end

    window:ClearAllPoints()
    window:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
    window:SetSize(width, height)
    window:SetUserPlaced(true)
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

local MATCH_WIDTH_TEXT = "Match width"
local MATCH_HEIGHT_TEXT = "Match height"

-- The callbacks look the link up on every call rather than capturing it. A
-- drag while the menu is open replaces the link table, and a captured
-- reference would then be writing to a table nothing reads.
function Snap.AddMenuEntries(rootDescription, sessionWindow)
    local index = sessionWindow:GetSessionWindowIndex()

    if not GetLinks()[index] then
        return
    end

    local function Toggle(field)
        local link = GetLinks()[index]
        if link then
            link[field] = not link[field]
            Snap.PushSize(link.to)
        end

        -- Keeps the menu open so both axes can be flipped in one visit.
        return MenuResponse.Refresh
    end

    rootDescription:CreateDivider()

    rootDescription:CreateCheckbox(MATCH_WIDTH_TEXT,
        function()
            local link = GetLinks()[index]
            return link and link.matchWidth
        end,
        function() return Toggle("matchWidth") end)

    rootDescription:CreateCheckbox(MATCH_HEIGHT_TEXT,
        function()
            local link = GetLinks()[index]
            return link and link.matchHeight
        end,
        function() return Toggle("matchHeight") end)
end

function Snap.Enable()
    local function OnDragStop(window)
        -- Blizzard's OnDragStart refuses to move a locked window but their
        -- OnDragStop runs regardless, so the lock has to be checked here or a
        -- stray drag on a locked window would link it.
        if not window:CanMoveOrResize() then
            return
        end

        local index = window:GetSessionWindowIndex()

        -- Dropping the old link happens even with snapping switched off,
        -- otherwise turning the feature off would freeze existing links in
        -- place with no way left to break them.
        local result = ns.db.snap
            and Snap.FindSnap(RectOf(window, index), CollectCandidates(index), ns.db.snapThreshold)
            or nil

        if not result then
            Snap.ClearLink(index)
            return
        end

        -- SetLink refuses a link it cannot apply; clear the old one so the
        -- window is not left following a target the user dragged away from.
        local linked = Snap.SetLink(index, {
            to = result.index,
            point = result.point,
            relPoint = result.relPoint,
            -- The axis perpendicular to the edge we landed on is the one that
            -- has to agree for the pair to read as one block.
            matchWidth = result.axis == "vertical",
            matchHeight = result.axis == "horizontal",
        })

        if not linked then
            Snap.ClearLink(index)
        end
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
    --
    -- SetupSessionWindow also re-anchors the window to UIParent at a fixed
    -- offset every time it runs, including when it is reusing a frame that was
    -- hidden earlier. So hiding and re-showing a snapped window detaches it
    -- unless the links are re-applied here, and a link whose target was hidden
    -- at login gets its retry the moment that target comes back.
    ns.HookInstance(DamageMeter, "SetupSessionWindow", function(_, windowDataIndex, windowData)
        local window = windowData.sessionWindow
        if window and not window.dmtSizeHooked then
            window.dmtSizeHooked = true
            window:HookScript("OnSizeChanged", function()
                Snap.PushSize(windowDataIndex)
            end)
        end

        Snap.ApplyAll()
    end)

    -- Blizzard restores its saved frame positions during login; applying on the
    -- next frame puts our anchors on top of that rather than under it.
    C_Timer.After(0, Snap.ApplyAll)
end

ns.RegisterModule("Snap", Snap)
