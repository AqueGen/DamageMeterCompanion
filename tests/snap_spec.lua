local ns = {}

-- Snap.lua registers itself at file scope; the real one lives in Core.lua,
-- which these tests do not load.
ns.RegisterModule = function() end

-- Snap reads the registry for index ordering; the spec does not load Windows.lua.
ns.Windows = {
    SortedIndices = function(set)
        local indices = {}
        for index in pairs(set) do
            table.insert(indices, index)
        end
        table.sort(indices)
        return indices
    end,
}

assert(loadfile("Snap.lua"))("DamageMeterTweaks", ns)

local Snap = ns.Snap

-- A 400x200 window with its top-left corner at (100, 500).
local function Rect(index, left, top, width, height)
    return { index = index, left = left, right = left + width, top = top, bottom = top - height }
end

describe("Snap.FindSnap", function()
    it("snaps below a window when the top edge is near its bottom edge", function()
        local dragged = Rect(2, 100, 296, 400, 200)
        local target = Rect(1, 100, 500, 400, 200)

        local result = Snap.FindSnap(dragged, { target }, 15)

        assert.are.equal(1, result.index)
        assert.are.equal("TOPLEFT", result.point)
        assert.are.equal("BOTTOMLEFT", result.relPoint)
        assert.are.equal("vertical", result.axis)
    end)

    it("snaps above a window", function()
        local dragged = Rect(2, 100, 704, 400, 200)
        local target = Rect(1, 100, 500, 400, 200)

        local result = Snap.FindSnap(dragged, { target }, 15)

        assert.are.equal("BOTTOMLEFT", result.point)
        assert.are.equal("TOPLEFT", result.relPoint)
        assert.are.equal("vertical", result.axis)
    end)

    it("snaps to the right of a window", function()
        local dragged = Rect(2, 506, 500, 400, 200)
        local target = Rect(1, 100, 500, 400, 200)

        local result = Snap.FindSnap(dragged, { target }, 15)

        assert.are.equal("TOPLEFT", result.point)
        assert.are.equal("TOPRIGHT", result.relPoint)
        assert.are.equal("horizontal", result.axis)
    end)

    it("snaps to the left of a window", function()
        local dragged = Rect(2, -306, 500, 400, 200)
        local target = Rect(1, 100, 500, 400, 200)

        local result = Snap.FindSnap(dragged, { target }, 15)

        assert.are.equal("TOPRIGHT", result.point)
        assert.are.equal("TOPLEFT", result.relPoint)
        assert.are.equal("horizontal", result.axis)
    end)

    it("returns nothing when the gap is beyond the threshold", function()
        local dragged = Rect(2, 100, 200, 400, 200)
        local target = Rect(1, 100, 500, 400, 200)

        assert.is_nil(Snap.FindSnap(dragged, { target }, 15))
    end)

    it("returns nothing when the edges are near but do not overlap", function()
        local dragged = Rect(2, 900, 296, 400, 200)
        local target = Rect(1, 100, 500, 400, 200)

        assert.is_nil(Snap.FindSnap(dragged, { target }, 15))
    end)

    it("picks the closest candidate", function()
        local dragged = Rect(3, 100, 296, 400, 200)
        local far = Rect(1, 100, 506, 400, 200)
        local near = Rect(2, 100, 500, 400, 200)

        assert.are.equal(2, Snap.FindSnap(dragged, { far, near }, 15).index)
    end)

    it("never snaps a window to itself", function()
        local dragged = Rect(1, 100, 500, 400, 200)

        assert.is_nil(Snap.FindSnap(dragged, { dragged }, 15))
    end)

    it("keeps the first candidate when two are equidistant", function()
        local dragged = Rect(3, 100, 296, 400, 200)
        local first = Rect(1, 100, 500, 400, 200)
        local second = Rect(2, 100, 500, 400, 200)

        assert.are.equal(1, Snap.FindSnap(dragged, { first, second }, 15).index)
    end)

    it("rejects a window that only touches at a corner", function()
        -- Sits exactly below and to the right: its top equals the target's
        -- bottom and its left equals the target's right, so neither axis
        -- overlaps and neither near edge may snap.
        local dragged = Rect(2, 500, 300, 400, 200)
        local target = Rect(1, 100, 500, 400, 200)

        assert.is_nil(Snap.FindSnap(dragged, { target }, 15))
    end)
end)

describe("Snap.WouldCycle", function()
    it("allows a fresh link", function()
        assert.is_false(Snap.WouldCycle({}, 2, 1))
    end)

    it("refuses a direct loop", function()
        local links = { [1] = { to = 2 } }

        assert.is_true(Snap.WouldCycle(links, 2, 1))
    end)

    it("refuses an indirect loop", function()
        local links = { [3] = { to = 2 }, [2] = { to = 1 } }

        assert.is_true(Snap.WouldCycle(links, 1, 3))
    end)

    it("refuses a self link", function()
        assert.is_true(Snap.WouldCycle({}, 2, 2))
    end)

    it("refuses a link into a chain that already loops, without hanging", function()
        -- A corrupt saved link set can hold a cycle that does not pass through
        -- the window being linked. Without a visited set this call never
        -- returns, and Lua has no preemption, so it would freeze the client.
        local links = { [1] = { to = 2 }, [2] = { to = 1 } }

        assert.is_true(Snap.WouldCycle(links, 3, 1))
    end)
end)

describe("Snap.ApplyOrder", function()
    it("returns targets before dependents", function()
        local links = { [3] = { to = 2 }, [2] = { to = 1 } }

        assert.are.same({ 2, 3 }, Snap.ApplyOrder(links))
    end)

    it("handles independent links", function()
        local links = { [2] = { to = 1 }, [3] = { to = 1 } }
        local order = Snap.ApplyOrder(links)

        assert.are.equal(2, #order)
    end)

    it("returns an empty list when there are no links", function()
        assert.are.same({}, Snap.ApplyOrder({}))
    end)

    it("orders a chain of five targets-first", function()
        local links = {
            [7] = { to = 6 },
            [6] = { to = 5 },
            [5] = { to = 4 },
            [4] = { to = 1 },
        }

        assert.are.same({ 4, 5, 6, 7 }, Snap.ApplyOrder(links))
    end)

    it("orders two independent chains without dropping either", function()
        -- Only windows that have a link appear in the order; 4 and 6 are
        -- targets, not dependents.
        local links = { [5] = { to = 4 }, [7] = { to = 6 } }
        local order = Snap.ApplyOrder(links)

        assert.are.same({ 5, 7 }, order)
    end)
end)

describe("Snap.Clamp", function()
    it("clamps below the minimum", function()
        assert.are.equal(200, Snap.Clamp(150, 200, 600))
    end)

    it("clamps above the maximum", function()
        assert.are.equal(600, Snap.Clamp(900, 200, 600))
    end)

    it("leaves a value inside the range alone", function()
        assert.are.equal(400, Snap.Clamp(400, 200, 600))
    end)

    it("returns the minimum when the bounds are inverted", function()
        assert.are.equal(600, Snap.Clamp(400, 600, 200))
    end)
end)

describe("Snap.OffsetForGap", function()
    it("pushes a window below its target further down", function()
        local x, y = Snap.OffsetForGap("TOPLEFT", "BOTTOMLEFT", 6)

        assert.are.equal(0, x)
        assert.are.equal(-6, y)
    end)

    it("pushes a window above its target further up", function()
        local x, y = Snap.OffsetForGap("BOTTOMLEFT", "TOPLEFT", 6)

        assert.are.equal(0, x)
        assert.are.equal(6, y)
    end)

    it("pushes a window to the right of its target further right", function()
        local x, y = Snap.OffsetForGap("TOPLEFT", "TOPRIGHT", 6)

        assert.are.equal(6, x)
        assert.are.equal(0, y)
    end)

    it("pushes a window to the left of its target further left", function()
        local x, y = Snap.OffsetForGap("TOPRIGHT", "TOPLEFT", 6)

        assert.are.equal(-6, x)
        assert.are.equal(0, y)
    end)

    it("is flush with no gap", function()
        local x, y = Snap.OffsetForGap("TOPLEFT", "BOTTOMLEFT", 0)

        assert.are.equal(0, x)
        assert.are.equal(0, y)
    end)
end)
