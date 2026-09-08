local addonName, ns = ...

ns.Snap = {}
local Snap = ns.Snap
local Windows = ns.Windows

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

    for _, index in ipairs(Windows.SortedIndices(links)) do
        Place(index)
    end

    return order
end

-- The screen is a different kind of neighbour: the window's edge meets the
-- same edge of the screen rather than the opposite one, and there is nothing
-- to anchor to that could move, so a screen snap is a nudge into place, not a
-- link. Returns the shift that lands the nearest edge flush, or nil.
function Snap.FindScreenSnap(rect, screen, threshold)
    local edges = {
        { edge = "left", gap = math.abs(rect.left - screen.left), dx = screen.left - rect.left, dy = 0 },
        { edge = "right", gap = math.abs(rect.right - screen.right), dx = screen.right - rect.right, dy = 0 },
        { edge = "top", gap = math.abs(rect.top - screen.top), dx = 0, dy = screen.top - rect.top },
        { edge = "bottom", gap = math.abs(rect.bottom - screen.bottom), dx = 0, dy = screen.bottom - rect.bottom },
    }

    local best

    for _, candidate in ipairs(edges) do
        if candidate.gap <= threshold and (not best or candidate.gap < best.gap) then
            best = candidate
        end
    end

    return best
end

local function ScreenRect()
    local left, bottom, width, height = UIParent:GetRect()

    return { left = left, right = left + width, top = bottom + height, bottom = bottom }
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
--
-- A size is only set when it differs. Setting one runs the window's ScrollBox
-- update inside our taint (ScrollBox.lua:119-129, 762-792): its data range
-- fields and any rows it acquires are then ours, and every combat refresh
-- logs a warning per row until reload. At login Blizzard's frame cache has
-- already restored the matched sizes, so an equal size must be a no-op or
-- every session would start tainted. Returns whether anything was set.
local function PushSizeFrom(index, visited)
    if visited[index] then
        return false
    end

    visited[index] = true

    local source = Windows.Get(index)
    if not source then
        return false
    end

    local changed = false

    for otherIndex, link in pairs(GetLinks()) do
        if link.to == index then
            local target = Windows.Get(otherIndex)
            if target and target:CanMoveOrResize() then
                if link.matchWidth then
                    local width = Snap.Clamp(source:GetWidth(), Snap.MIN_WIDTH, Snap.MAX_WIDTH)
                    if math.abs(target:GetWidth() - width) > 0.5 then
                        target:SetWidth(width)
                        changed = true
                    end
                end

                if link.matchHeight then
                    local height = Snap.Clamp(source:GetHeight(), Snap.MIN_HEIGHT, Snap.MAX_HEIGHT)
                    if math.abs(target:GetHeight() - height) > 0.5 then
                        target:SetHeight(height)
                        changed = true
                    end
                end

                if PushSizeFrom(otherIndex, visited) then
                    changed = true
                end
            end
        end
    end

    return changed
end

-- The guard keeps the re-entrant OnSizeChanged events our own SetWidth and
-- SetHeight calls dispatch from starting a second walk on top of this one.
function Snap.PushSize(index)
    -- Out of combat only. SetWidth on a session window makes its ScrollBox
    -- re-run its initializers inside our execution, and in combat those
    -- compare Secret fields. A resize in combat is a rare gesture anyway.
    if applyingSize or InCombatLockdown() then
        return
    end

    applyingSize = true
    local changed = PushSizeFrom(index, {})
    applyingSize = false

    if changed then
        ns.RequestReload("size")
    end
end

-- The gap always separates the two windows, so its sign follows from which
-- edges were joined rather than being the caller's problem.
local GAP_DIRECTION = {
    ["TOPLEFT|BOTTOMLEFT"] = { 0, -1 },
    ["BOTTOMLEFT|TOPLEFT"] = { 0, 1 },
    ["TOPLEFT|TOPRIGHT"] = { 1, 0 },
    ["TOPRIGHT|TOPLEFT"] = { -1, 0 },
}

function Snap.OffsetForGap(point, relPoint, gap)
    local direction = GAP_DIRECTION[point .. "|" .. relPoint]

    if not direction or not gap then
        return 0, 0
    end

    return direction[1] * gap, direction[2] * gap
end

-- pushSize is passed only from a user gesture. At login this runs from the
-- SetupSessionWindow hook, before Blizzard's frame cache has restored the
-- windows' sizes, so a push here would resize template-sized windows from
-- our stack and taint them; the cache brings the matched sizes back itself.
function Snap.ApplyLink(index, pushSize)
    local link = GetLinks()[index]
    local window = Windows.Get(index)
    local target = link and Windows.Get(link.to)

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
    local x, y = Snap.OffsetForGap(link.point, link.relPoint, link.gap)
    window:SetPoint(link.point, target, link.relPoint, x, y)

    -- User-placed on purpose: Blizzard's frame cache saves only such frames,
    -- and it saves their size along with their position - which is how a
    -- matched size comes back after a reload without us setting it. The
    -- cached absolute point is harmless: this anchor goes back on top of it.
    window:SetUserPlaced(true)

    if pushSize then
        Snap.PushSize(link.to)
    end
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
    local window = Windows.Get(index)

    if not window
        or not DamageMeter:CanMoveOrResizeSessionWindow(window)
        or link.to == index
        or Snap.WouldCycle(GetLinks(), index, link.to) then
        return false
    end

    GetLinks()[index] = link
    Snap.ApplyLink(index, true)

    return true
end

-- Dropping a link has to hand the window back its own position. It is still
-- anchored to its old target, so without this it would keep following that
-- window until the next reload. The size is left alone: the frame keeps it,
-- and setting it from here would run the ScrollBox update in our taint.
function Snap.ClearLink(index)
    local window = Windows.Get(index)

    if not GetLinks()[index] then
        return
    end

    GetLinks()[index] = nil

    if not window or not DamageMeter:CanMoveOrResizeSessionWindow(window) then
        return
    end

    local left, bottom = window:GetRect()

    -- A hidden window may have no resolved rect; there is nothing to hand back
    -- in that case, and the link is already gone.
    if not left then
        return
    end

    window:ClearAllPoints()
    window:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
    window:SetUserPlaced(true)

end

-- Moves a window by a fixed offset. ClearLink has already handed the window
-- its own point; the frame position cache records where it ends up.
function Snap.Nudge(window, index, dx, dy)
    local left, bottom = window:GetRect()

    if not left then
        return
    end

    window:ClearAllPoints()
    window:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left + dx, bottom + dy)
    window:SetUserPlaced(true)

end

local function CollectCandidates(exceptIndex)
    local candidates = {}

    Windows.ForEach(function(window, index)
        if index ~= exceptIndex and window:IsShown() then
            table.insert(candidates, RectOf(window, index))
        end
    end)

    return candidates
end

function Snap.Enable()
    local function OnDragStart(window, index)
        if not ns.db.snap or not window:CanMoveOrResize() then
            return
        end

        -- Preview owns the overlay's OnUpdate; we only hand it the per-tick
        -- poll. Driving this from the window's own OnUpdate instead would
        -- fight DamageMeterSessionWindowMixin:UpdateOnUpdateState, which sets
        -- and clears that script for its own mouse-over tracking.
        ns.Preview.Track(function()
            local rect = RectOf(window, index)
            local candidate = Snap.FindSnap(rect, CollectCandidates(index), ns.db.snapThreshold)

            if candidate then
                ns.Preview.Show(rect, RectOf(ns.Windows.Get(candidate.index), candidate.index), candidate)
                return
            end

            local screen = ScreenRect()
            local edge = Snap.FindScreenSnap(rect, screen, ns.db.snapThreshold)

            if edge then
                ns.Preview.ShowEdge(rect, screen, edge)
            else
                ns.Preview.Hide()
            end
        end)
    end

    local function OnDragStop(window)
        local index = window:GetSessionWindowIndex()
        ns.Preview.StopTracking()

        -- Blizzard's OnDragStart refuses to move a locked window but their
        -- OnDragStop runs regardless, so the lock has to be checked here or a
        -- stray drag on a locked window would link it.
        if not window:CanMoveOrResize() then
            return
        end

        -- Dropping the old link happens even with snapping switched off,
        -- otherwise turning the feature off would freeze existing links in
        -- place with no way left to break them.
        local result = ns.db.snap
            and Snap.FindSnap(RectOf(window, index), CollectCandidates(index), ns.db.snapThreshold)
            or nil

        if not result then
            Snap.ClearLink(index)

            -- A window snaps to the screen only when no window claimed it:
            -- another window is the more specific neighbour.
            if ns.db.snap then
                local rect = RectOf(window, index)
                local edge = Snap.FindScreenSnap(rect, ScreenRect(), ns.db.snapThreshold)

                if edge then
                    Snap.Nudge(window, index, edge.dx, edge.dy)
                end
            end

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

    -- HookScript, not a method hook: the engine invokes the XML-declared
    -- OnDragStop script, and whether `method="OnDragStop"` resolves the
    -- function at load or at call time is not determinable from source. A
    -- script hook is correct under either.
    -- Only a size change the player is making by hand propagates: Blizzard
    -- flags a secondary window with isResizing while its handle is dragged
    -- (DamageMeterSessionWindow.lua:536), and window 1 is sized in Edit Mode.
    -- The other OnSizeChanged sources - the frame cache restoring sizes at
    -- login, SetupSessionWindow - must not resize anything from our stack.
    local function OnSizeChanged(window, index)
        if window.isResizing or (index == 1 and EditModeManagerFrame:IsEditModeActive()) then
            Snap.PushSize(index)
        end
    end

    local function AttachWindow(window, index)
        window:HookScript("OnDragStop", OnDragStop)
        window:HookScript("OnDragStart", function() OnDragStart(window, index) end)

        window.dmtSizeHooked = true
        window:HookScript("OnSizeChanged", function() OnSizeChanged(window, index) end)
    end

    Windows.ForEach(AttachWindow)

    -- Windows created later, through Show new window, need the same size and
    -- drag hooks. DamageMeter already exists, so this one must be an instance
    -- hook.
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

            window:HookScript("OnSizeChanged", function() OnSizeChanged(window, windowDataIndex) end)

            window:HookScript("OnDragStop", OnDragStop)
            window:HookScript("OnDragStart", function() OnDragStart(window, windowDataIndex) end)
        end

        Snap.ApplyAll()
    end)

    -- Blizzard restores its saved frame positions during login; applying on the
    -- next frame puts our anchors on top of that rather than under it. Linked
    -- windows are user-placed now, so the cache restores an absolute point for
    -- them too - once more after PLAYER_ENTERING_WORLD covers the case where
    -- that lands after the first pass. SetPoint only, so repeating is free.
    C_Timer.After(0, Snap.ApplyAll)

    local reapply = CreateFrame("Frame")
    reapply:RegisterEvent("PLAYER_ENTERING_WORLD")
    reapply:SetScript("OnEvent", function()
        C_Timer.After(0, Snap.ApplyAll)
    end)
end

ns.RegisterModule("Snap", Snap)
