local ns = {}

ns.RegisterModule = function() end

assert(loadfile("Preview.lua"))("DamageMeterCompanion", ns)

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

    it("keeps the bars inside both windows when snapping above", function()
        local moving = Rect(2, 100, 600, 400, 200)
        local target = Rect(1, 100, 300, 400, 200)
        local result = { index = 1, point = "BOTTOMLEFT", relPoint = "TOPLEFT", axis = "vertical" }

        local movingBar, targetBar = Preview.BarRects(moving, target, result, 3)

        -- Moving occupies y 400 to 600, so its bar sits on 400 upwards.
        assert.are.equal(400, movingBar.bottom)
        -- Target occupies y 100 to 300, so its bar sits just under 300.
        assert.are.equal(297, targetBar.bottom)
        assert.are.equal(400, movingBar.width)
    end)

    it("keeps the bars inside both windows when snapping to the left", function()
        local moving = Rect(2, 50, 500, 400, 200)
        local target = Rect(1, 497, 500, 400, 200)
        local result = { index = 1, point = "TOPRIGHT", relPoint = "TOPLEFT", axis = "horizontal" }

        local movingBar, targetBar = Preview.BarRects(moving, target, result, 3)

        -- Moving occupies x 50 to 450, so its bar sits just inside 450.
        assert.are.equal(447, movingBar.left)
        -- Target occupies x 497 to 897, so its bar sits on 497 rightwards.
        assert.are.equal(497, targetBar.left)
        assert.are.equal(200, movingBar.height)
    end)
end)

describe("Preview.EdgeBarRects", function()
    local screen = { left = 0, right = 1920, top = 1080, bottom = 0 }

    it("draws vertical bars on the window's and the screen's left edges", function()
        local moving, target = Preview.EdgeBarRects(Rect(2, 12, 500, 400, 200), screen, { edge = "left" }, 3)
        assert.are.equal(12, moving.left)
        assert.are.equal(0, target.left)
        assert.are.equal(200, moving.height)
        assert.are.equal(300, target.bottom)
    end)

    it("draws horizontal bars inside the top edges", function()
        local moving, target = Preview.EdgeBarRects(Rect(2, 100, 1075, 400, 200), screen, { edge = "top" }, 3)
        assert.are.equal(1072, moving.bottom)
        assert.are.equal(1077, target.bottom)
        assert.are.equal(400, target.width)
        assert.are.equal(100, target.left)
    end)
end)
