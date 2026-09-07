local addonName, ns = ...

ns.Preview = {}
local Preview = ns.Preview

local THICKNESS = 3
local COLOR = { r = 0.2, g = 1, b = 0.4, a = 0.9 }

local overlay

local function GetOverlay()
    if overlay then
        return overlay
    end

    -- Our own frame, so nothing about Blizzard's windows is touched and the
    -- whole feature disappears with one Hide. It stays shown for the whole
    -- drag (see Track below) since a hidden frame never receives OnUpdate;
    -- the two bar textures are what actually toggle on screen.
    overlay = CreateFrame("Frame", nil, UIParent)
    overlay:SetFrameStrata("TOOLTIP")
    overlay:SetAllPoints(UIParent)
    overlay:Hide()

    for _, key in ipairs({ "movingBar", "targetBar" }) do
        local texture = overlay:CreateTexture(nil, "OVERLAY")
        texture:SetColorTexture(COLOR.r, COLOR.g, COLOR.b, COLOR.a)
        texture:Hide()
        overlay[key] = texture
    end

    return overlay
end

local function PlaceBar(texture, bar)
    texture:ClearAllPoints()
    texture:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", bar.left, bar.bottom)
    texture:SetSize(math.max(bar.width, 1), math.max(bar.height, 1))
    texture:Show()
end

-- Shows both bars for one snap candidate. Called every OnUpdate tick while a
-- candidate is in range, so it just repositions the existing textures.
function Preview.Show(rect, target, result)
    local frame = GetOverlay()
    local movingBar, targetBar = Preview.BarRects(rect, target, result, THICKNESS)

    PlaceBar(frame.movingBar, movingBar)
    PlaceBar(frame.targetBar, targetBar)
end

-- Hides the bars only, not the overlay frame itself: the frame has to stay
-- shown for Track's OnUpdate to keep firing while the drag continues out of
-- range and then back into it.
function Preview.Hide()
    if overlay then
        overlay.movingBar:Hide()
        overlay.targetBar:Hide()
    end
end

-- Starts polling for a snap candidate for the duration of one drag. Driven
-- from the overlay's own OnUpdate rather than the session window's: Blizzard
-- drives the window's OnUpdate script itself for its mouse-over tracking
-- (DamageMeterSessionWindowMixin:UpdateOnUpdateState sets and clears it), so
-- claiming that script would both clobber Blizzard's tracking and get
-- clobbered back the next time that function runs. pollFn is called on every
-- tick and is expected to call Preview.Show or Preview.Hide itself.
function Preview.Track(pollFn)
    local frame = GetOverlay()
    frame:Show()
    frame:SetScript("OnUpdate", pollFn)
end

function Preview.StopTracking()
    if overlay then
        overlay:SetScript("OnUpdate", nil)
        overlay:Hide()
    end

    Preview.Hide()
end

-- Two bars, one on each window's edge, spanning only the part of those edges
-- that actually meet. Answering "this edge, this side" is the whole point -
-- a trail between the windows' centres, which is how Details shows the same
-- thing, says only that something is near.
function Preview.BarRects(rect, target, result, thickness)
    if result.axis == "vertical" then
        local left = math.max(rect.left, target.left)
        local right = math.min(rect.right, target.right)
        local width = right - left

        local movingEdge = (result.point == "TOPLEFT") and rect.top or rect.bottom
        local targetEdge = (result.relPoint == "BOTTOMLEFT") and target.bottom or target.top

        -- Which way is inward depends on which edge was picked: subtracting the
        -- thickness only moves into the window when the edge is its top.
        local movingBottom = (result.point == "TOPLEFT") and (movingEdge - thickness) or movingEdge
        local targetBottom = (result.relPoint == "BOTTOMLEFT") and targetEdge or (targetEdge - thickness)

        return
            { left = left, bottom = movingBottom, width = width, height = thickness },
            { left = left, bottom = targetBottom, width = width, height = thickness }
    end

    local bottom = math.max(rect.bottom, target.bottom)
    local top = math.min(rect.top, target.top)
    local height = top - bottom

    local movingEdge = (result.point == "TOPLEFT") and rect.left or rect.right
    local targetEdge = (result.relPoint == "TOPRIGHT") and target.right or target.left

    local movingLeft = (result.point == "TOPLEFT") and movingEdge or (movingEdge - thickness)
    local targetLeft = (result.relPoint == "TOPRIGHT") and (targetEdge - thickness) or targetEdge

    return
        { left = movingLeft, bottom = bottom, width = thickness, height = height },
        { left = targetLeft, bottom = bottom, width = thickness, height = height }
end

ns.RegisterModule("Preview", Preview)
