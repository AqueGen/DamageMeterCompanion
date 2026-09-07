local ns = {}

-- Presence.lua registers itself at file scope; the real one lives in Core.lua,
-- which these tests do not load. ResolveStrata falls back to the default, so
-- the defaults table has to be present too.
ns.RegisterModule = function() end
ns.defaults = { strata = "MEDIUM" }

assert(loadfile("Presence.lua"))("DamageMeterCompanion", ns)

local Presence = ns.Presence

describe("Presence.ComputeAlpha", function()
    it("uses the Edit Mode alpha while hovered", function()
        assert.are.equal(0.8, Presence.ComputeAlpha(0.8, 0.4, true))
    end)

    it("scales the Edit Mode alpha while idle", function()
        -- 0.8 * 0.4 is not exactly 0.32 in doubles, so compare with tolerance.
        assert.is_true(math.abs(Presence.ComputeAlpha(0.8, 0.4, false) - 0.32) < 1e-9)
    end)

    it("follows a changed Edit Mode alpha in both states", function()
        assert.are.equal(1, Presence.ComputeAlpha(1, 0.4, true))
        assert.are.equal(0.4, Presence.ComputeAlpha(1, 0.4, false))
    end)
end)

describe("Presence.NextStrataUp", function()
    it("returns the next strata up", function()
        assert.are.equal("HIGH", Presence.NextStrataUp("MEDIUM"))
        assert.are.equal("DIALOG", Presence.NextStrataUp("HIGH"))
    end)

    it("stays at the top of the list", function()
        assert.are.equal("TOOLTIP", Presence.NextStrataUp("TOOLTIP"))
    end)

    it("falls back to HIGH for an unknown strata", function()
        assert.are.equal("HIGH", Presence.NextStrataUp("NONSENSE"))
    end)
end)

describe("Presence.ResolveStrata", function()
    it("passes a real strata through", function()
        assert.are.equal("DIALOG", Presence.ResolveStrata("DIALOG"))
    end)

    it("falls back to the default for an unknown strata", function()
        assert.are.equal("MEDIUM", Presence.ResolveStrata("NONSENSE"))
    end)

    it("falls back to the default for a nil strata", function()
        assert.are.equal("MEDIUM", Presence.ResolveStrata(nil))
    end)
end)
