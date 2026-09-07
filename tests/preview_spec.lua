local ns = {}

ns.RegisterModule = function() end

assert(loadfile("Preview.lua"))("DamageMeterTweaks", ns)

local Preview = ns.Preview

local function Rect(index, left, top, width, height)
    return { index = index, left = left, right = left + width, top = top, bottom = top - height }
end

describe("Preview.BarRects", function()
    it("draws horizontal bars across the shared width when snapping below", function()
        local moving = Rect(2, 100, 296, 400, 200)
        local target = Rect(1, 100, 500, 400, 200)
        local result = { index = 1, point = "TOPLEFT", relPoint = "BOTTOMLEFT", axis = "vertical" }

        local movingBar, targetBar = Preview.BarRects(moving, target, result, 3)

        assert.are.equal(100, movingBar.left)
        assert.are.equal(400, movingBar.width)
        assert.are.equal(3, movingBar.height)
        assert.are.equal(296, movingBar.bottom + movingBar.height)

        assert.are.equal(100, targetBar.left)
        assert.are.equal(400, targetBar.width)
        assert.are.equal(300, targetBar.bottom)
    end)

    it("draws vertical bars across the shared height when snapping to the right", function()
        local moving = Rect(2, 506, 500, 400, 200)
        local target = Rect(1, 100, 500, 400, 200)
        local result = { index = 1, point = "TOPLEFT", relPoint = "TOPRIGHT", axis = "horizontal" }

        local movingBar, targetBar = Preview.BarRects(moving, target, result, 3)

        assert.are.equal(3, movingBar.width)
        assert.are.equal(200, movingBar.height)
        assert.are.equal(506, movingBar.left)

        assert.are.equal(3, targetBar.width)
        assert.are.equal(200, targetBar.height)
        assert.are.equal(497, targetBar.left)
    end)

    it("spans only the overlapping part when the windows are different sizes", function()
        local moving = Rect(2, 300, 296, 400, 200)
        local target = Rect(1, 100, 500, 400, 200)
        local result = { index = 1, point = "TOPLEFT", relPoint = "BOTTOMLEFT", axis = "vertical" }

        local movingBar = Preview.BarRects(moving, target, result, 3)

        assert.are.equal(300, movingBar.left)
        assert.are.equal(200, movingBar.width)
    end)
end)
