local ns = {}

ns.RegisterModule = function() end
ns.Print = function() end
ns.HasDeathRecap = function() return false end

-- Busted insulates a spec file's globals, so the loaded chunk only sees what
-- is written to _G explicitly.
_G.Enum = { DamageMeterNumbers = { Minimal = 0, Compact = 1, Complete = 2 } }

-- A Secret is modelled as a table with a marker: it must be passed through
-- untouched and never compared or computed with.
local SECRET = {}
local function Secret(value) return { [SECRET] = true, value = value } end
_G.issecretvalue = function(value) return type(value) == "table" and value[SECRET] == true end

-- The client's abbreviation routine is stubbed to prove only that it received
-- the values we chose, Secret or not, and that its output is what we compose.
_G.AbbreviateNumbers = function(value)
    if _G.issecretvalue(value) then return "<secret " .. tostring(value.value) .. ">" end
    return "#" .. tostring(value)
end

_G.CreateAbbreviateConfig = function() return {} end
_G.CreateFrame = function() return { SetScript = function() end } end

assert(loadfile("Format.lua"))("DamageMeterCompanion", ns)

local Format = ns.Format
ns.db = { format = true }
ns.Windows = { ForEach = function() end }
Format.Enable()

local function Entry(fields)
    local entry = { GetNumberDisplayType = function() return fields.displayType end }
    for key, value in pairs(fields) do entry[key] = value end
    return entry
end

describe("Format.Choose", function()
    it("shows the total first and per-second in brackets for Compact", function()
        local main, parenthetical, wantPercentage = Format.Choose(Entry({ displayType = 1, value = 100, valuePerSecond = 5 }))
        assert.are.equal(100, main)
        assert.are.equal(5, parenthetical)
        assert.is_false(wantPercentage)
    end)

    it("swaps them for per-second displays", function()
        local main, parenthetical = Format.Choose(Entry({ displayType = 1, value = 100, valuePerSecond = 5, showsValuePerSecondAsPrimary = true }))
        assert.are.equal(5, main)
        assert.are.equal(100, parenthetical)
    end)

    it("drops the brackets for Minimal", function()
        local _, parenthetical = Format.Choose(Entry({ displayType = 0, value = 100, valuePerSecond = 5 }))
        assert.is_nil(parenthetical)
    end)

    it("drops per-second when the type suppresses it", function()
        local _, parenthetical = Format.Choose(Entry({ displayType = 2, value = 100, valuePerSecond = 5, suppressValuePerSecond = true }))
        assert.is_nil(parenthetical)
    end)

    it("wants a percentage only for Complete", function()
        local _, _, wantPercentage = Format.Choose(Entry({ displayType = 2, value = 100, valuePerSecond = 5 }))
        assert.is_true(wantPercentage)
    end)

    it("passes Secret values through without inspecting them", function()
        local secretValue, secretRate = Secret(100), Secret(5)
        local main, parenthetical = Format.Choose(Entry({ displayType = 1, value = secretValue, valuePerSecond = secretRate }))
        assert.are.equal(secretValue, main)
        assert.are.equal(secretRate, parenthetical)
    end)
end)

describe("Format.Compose", function()
    it("renders a lone value", function()
        assert.are.equal("#100", Format.Compose(100))
    end)

    it("renders the bracketed form", function()
        assert.are.equal("#100 (#5)", Format.Compose(100, 5))
    end)

    it("renders the complete form", function()
        assert.are.equal("#100 (#5) 18.0%", Format.Compose(100, 5, 0.18))
    end)

    it("renders a percentage without brackets", function()
        assert.are.equal("#100 18.0%", Format.Compose(100, nil, 0.18))
    end)

    it("hands Secret values to the client routine and composes what comes back", function()
        assert.are.equal("<secret 100> (<secret 5>)", Format.Compose(Secret(100), Secret(5)))
    end)

    it("returns nothing when there is no main value", function()
        assert.is_nil(Format.Compose(nil, 5))
    end)
end)
