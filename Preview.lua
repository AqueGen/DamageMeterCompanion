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

        return
            { left = left, bottom = movingEdge - thickness, width = width, height = thickness },
            { left = left, bottom = targetEdge, width = width, height = thickness }
    end

    local bottom = math.max(rect.bottom, target.bottom)
    local top = math.min(rect.top, target.top)
    local height = top - bottom

    local movingEdge = (result.point == "TOPLEFT") and rect.left or rect.right
    local targetEdge = (result.relPoint == "TOPRIGHT") and target.right or target.left

    return
        { left = movingEdge, bottom = bottom, width = thickness, height = height },
        { left = targetEdge - thickness, bottom = bottom, width = thickness, height = height }
end

ns.RegisterModule("Preview", Preview)
