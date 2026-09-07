local ns = {}

ns.RegisterModule = function() end
ns.Print = function() end

-- Enough of the game to load the file. Only the pure selection logic is under
-- test; everything frame-bound lives behind Enable and is covered in game.
_G.CreateFrame = function() error("no frames in these tests") end
_G.GameTooltip = {}
_G.GameTooltip_Hide = function() end

-- Busted insulates a spec file's globals, so the loaded chunk only sees what
-- is written to _G explicitly.
_G.Enum = {
    DamageMeterType = {
        DamageDone = 0,
        Dps = 1,
        HealingDone = 2,
        Hps = 3,
        Absorbs = 4,
        Interrupts = 5,
        Dispels = 6,
        DamageTaken = 7,
        AvoidableDamageTaken = 8,
        Deaths = 9,
        EnemyDamageTaken = 10,
    },
}

local T = _G.Enum.DamageMeterType

ns.ContextMenu = {
    CATEGORIES = {
        { types = { T.DamageDone, T.Dps } },
        { types = { T.HealingDone, T.Hps } },
        { types = { T.Interrupts } },
    },
    GetTypeName = function(damageMeterType) return "type " .. damageMeterType end,
}

assert(loadfile("QuickButtons.lua"))("DamageMeterTweaks", ns)

local QuickButtons = ns.QuickButtons

-- Enable also touches frames, so the two things it does that the pure logic
-- needs are done here instead: build the order table and seed the defaults.
local function Reset(selection)
    ns.db = { quickButtons = true, quickTypes = selection or {} }
end

QuickButtons.RebuildAll = function() end
QuickButtons.BuildOrder()

describe("QuickButtons.SelectedTypes", function()
    before_each(function()
        Reset()
    end)

    it("returns nothing when nothing is ticked", function()
        assert.are.same({}, QuickButtons.SelectedTypes())
    end)

    it("returns ticked types in menu order, not tick order", function()
        Reset({ [T.Hps] = true, [T.DamageDone] = true })

        assert.are.same({ T.DamageDone, T.Hps }, QuickButtons.SelectedTypes())
    end)

    it("ignores a type that was ticked and then cleared", function()
        Reset({ [T.Dps] = true })
        QuickButtons.SetSelected(T.Dps, false)

        assert.are.same({}, QuickButtons.SelectedTypes())
    end)

    it("stores a cleared type as nil rather than false", function()
        Reset({ [T.Dps] = true })
        QuickButtons.SetSelected(T.Dps, false)

        assert.is_nil(ns.db.quickTypes[T.Dps])
    end)

    it("ignores a type the saved table holds that no category lists", function()
        Reset({ [T.Deaths] = true, [T.Dps] = true })

        assert.are.same({ T.Dps }, QuickButtons.SelectedTypes())
    end)
end)

describe("QuickButtons.IsSelected", function()
    it("is false for a type never ticked", function()
        Reset()
        assert.is_false(QuickButtons.IsSelected(T.Dps))
    end)

    it("is true only for the exact value true", function()
        Reset({ [T.Dps] = 1 })
        assert.is_false(QuickButtons.IsSelected(T.Dps))
    end)
end)
