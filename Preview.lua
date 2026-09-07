local addonName, ns = ...

ns.Preview = {}
local Preview = ns.Preview

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
