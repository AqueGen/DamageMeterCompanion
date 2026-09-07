local ns = {}

ns.RegisterModule = function() end
ns.Print = function() end

assert(loadfile("Windows.lua"))("DamageMeterTweaks", ns)

local Windows = ns.Windows

describe("Windows.IsOurs", function()
    it("treats Blizzard's three as not ours", function()
        assert.is_false(Windows.IsOurs(1))
        assert.is_false(Windows.IsOurs(3))
    end)

    it("treats anything above three as ours", function()
        assert.is_true(Windows.IsOurs(4))
        assert.is_true(Windows.IsOurs(97))
    end)
end)

describe("Windows.NextFreeIndex", function()
    it("starts just above Blizzard's range", function()
        assert.are.equal(4, Windows.NextFreeIndex({}))
    end)

    it("skips indices already taken", function()
        assert.are.equal(6, Windows.NextFreeIndex({ [4] = true, [5] = true }))
    end)

    it("fills a hole left by a removed window", function()
        assert.are.equal(5, Windows.NextFreeIndex({ [4] = true, [6] = true }))
    end)

    it("ignores Blizzard's indices being present", function()
        assert.are.equal(4, Windows.NextFreeIndex({ [1] = true, [2] = true, [3] = true }))
    end)
end)

describe("Windows.SortedIndices", function()
    it("returns ascending indices", function()
        assert.are.same({ 1, 4, 7 }, Windows.SortedIndices({ [7] = true, [1] = true, [4] = true }))
    end)

    it("returns an empty list for an empty set", function()
        assert.are.same({}, Windows.SortedIndices({}))
    end)
end)
