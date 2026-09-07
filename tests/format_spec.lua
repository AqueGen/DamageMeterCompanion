local ns = {}
ns.RegisterModule = function() end

_G.Enum = {
    DamageMeterNumbers = { Minimal = 0, Compact = 1, Complete = 2 },
}

assert(loadfile("Format.lua"))("DamageMeterTweaks", ns)

local Format = ns.Format

describe("Format.Abbreviate", function()
    it("leaves values below a thousand alone", function()
        assert.are.equal("0", Format.Abbreviate(0, 2))
        assert.are.equal("999", Format.Abbreviate(999, 2))
    end)

    it("switches to K at a thousand", function()
        assert.are.equal("1.00K", Format.Abbreviate(1000, 2))
        assert.are.equal("40.6K", Format.Abbreviate(40639, 1))
        assert.are.equal("999.99K", Format.Abbreviate(999990, 2))
    end)

    it("switches to M at a million", function()
        assert.are.equal("1.00M", Format.Abbreviate(1000000, 2))
        assert.are.equal("56.72M", Format.Abbreviate(56716000, 2))
    end)

    it("switches to B at a billion", function()
        assert.are.equal("2.50B", Format.Abbreviate(2500000000, 2))
    end)

    it("keeps trailing zeros so widths stay stable", function()
        assert.are.equal("5.00M", Format.Abbreviate(5000000, 2))
    end)

    it("handles negatives", function()
        assert.are.equal("-1.50M", Format.Abbreviate(-1500000, 2))
    end)

    it("treats nil as zero", function()
        assert.are.equal("0", Format.Abbreviate(nil, 2))
    end)
end)

describe("Format.SelectValues", function()
    it("returns only the main value in Minimal", function()
        local main, parenthetical, percentage = Format.SelectValues({
            GetNumberDisplayType = function() return Enum.DamageMeterNumbers.Minimal end,
            value = 100, valuePerSecond = 10, sessionTotalValue = 400,
        })

        assert.are.equal(100, main)
        assert.is_nil(parenthetical)
        assert.is_nil(percentage)
    end)

    it("adds the rate in Compact", function()
        local main, parenthetical, percentage = Format.SelectValues({
            GetNumberDisplayType = function() return Enum.DamageMeterNumbers.Compact end,
            value = 100, valuePerSecond = 10, sessionTotalValue = 400,
        })

        assert.are.equal(100, main)
        assert.are.equal(10, parenthetical)
        assert.is_nil(percentage)
    end)

    it("adds the share in Complete", function()
        local main, parenthetical, percentage = Format.SelectValues({
            GetNumberDisplayType = function() return Enum.DamageMeterNumbers.Complete end,
            value = 100, valuePerSecond = 10, sessionTotalValue = 400,
        })

        assert.are.equal(100, main)
        assert.are.equal(10, parenthetical)
        assert.are.equal(0.25, percentage)
    end)

    it("swaps main and parenthetical when the rate is primary", function()
        local main, parenthetical = Format.SelectValues({
            GetNumberDisplayType = function() return Enum.DamageMeterNumbers.Compact end,
            value = 100, valuePerSecond = 10, showsValuePerSecondAsPrimary = true,
        })

        assert.are.equal(10, main)
        assert.are.equal(100, parenthetical)
    end)

    it("drops the rate when the entry suppresses it", function()
        local _, parenthetical = Format.SelectValues({
            GetNumberDisplayType = function() return Enum.DamageMeterNumbers.Compact end,
            value = 100, valuePerSecond = 10, suppressValuePerSecond = true,
        })

        assert.is_nil(parenthetical)
    end)

    it("reports a zero share when the session total is zero", function()
        local _, _, percentage = Format.SelectValues({
            GetNumberDisplayType = function() return Enum.DamageMeterNumbers.Complete end,
            value = 100, sessionTotalValue = 0,
        })

        assert.are.equal(0, percentage)
    end)
end)

describe("Format.Compose", function()
    it("renders the main value alone", function()
        assert.are.equal("56.72M", Format.Compose(56716000))
    end)

    it("renders the rate in parentheses", function()
        assert.are.equal("56.72M (40.6K)", Format.Compose(56716000, 40639))
    end)

    it("renders the full form", function()
        assert.are.equal("56.72M (40.6K) 18.0%", Format.Compose(56716000, 40639, 0.18))
    end)

    it("renders a share without a rate", function()
        assert.are.equal("56.72M 18.0%", Format.Compose(56716000, nil, 0.18))
    end)
end)
