local ns = {}

ns.RegisterModule = function() end
ns.Print = function() end

assert(loadfile("Windows.lua"))("DamageMeterCompanion", ns)

local Windows = ns.Windows

describe("Windows.SortedIndices", function()
    it("returns ascending indices", function()
        assert.are.same({ 1, 4, 7 }, Windows.SortedIndices({ [7] = true, [1] = true, [4] = true }))
    end)

    it("returns an empty list for an empty set", function()
        assert.are.same({}, Windows.SortedIndices({}))
    end)
end)

