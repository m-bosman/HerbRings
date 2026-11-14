local wow = require("spec.wow")

-- Elwynn Forest is uiMapID 1429, Questie area 12. Zone is 1000x1000 yards in the fake.
local ELWYNN = 12
local PEACEBLOOM, SILVERLEAF = 401, 402

describe("GetDifficulty", function()
	local ns = assert(loadfile("Difficulty.lua"))("HerbRings", {})
	local th = { yellow = 25, green = 50, gray = 100 }

	it("goes red, orange, yellow, green, gray as skill rises", function()
		assert.equal("red", ns.GetDifficulty(50, 49, 0, th))
		assert.equal("orange", ns.GetDifficulty(50, 50, 0, th))
		assert.equal("yellow", ns.GetDifficulty(50, 75, 0, th))
		assert.equal("green", ns.GetDifficulty(50, 100, 0, th))
		assert.equal("gray", ns.GetDifficulty(50, 150, 0, th))
	end)

	it("lets gear bonus unlock a herb but not change the band", function()
		assert.equal("orange", ns.GetDifficulty(50, 40, 10, th))
		assert.equal("orange", ns.GetDifficulty(50, 70, 50, th))
	end)

	it("handles unknown requirement and no skill", function()
		assert.equal("unknown", ns.GetDifficulty(nil, 100, 0, th))
		assert.equal("red", ns.GetDifficulty(1, nil, 0, th))
	end)
end)

describe("CollectZone", function()
	it("merges the same herb from overlapping Questie objects", function()
		local addon = wow.load({ spawns = {
			[1618] = { [ELWYNN] = { { 50, 50 } } },
			[3724] = { [ELWYNN] = { { 50.5, 50 } } }, -- 5 yards off: same spot
			[1617] = { [ELWYNN] = { { 50, 50 } } },   -- Silverleaf, same place: kept
		} })
		local spots = addon.ns.CollectZone(1429, 1000, 1000)
		assert.equal(2, #spots)
	end)
end)

describe("own finds", function()
	local addon
	before_each(function()
		addon = wow.load({ spawns = { [1618] = { [ELWYNN] = { { 50, 50 } } } } })
	end)

	it("saves a herb picked where Questie has no spot", function()
		addon.at(0.3, 0.3)
		addon.gather("Peacebloom")
		local found = addon.found()
		assert.equal(1, #found)
		assert.same({ 0.3, 0.3, PEACEBLOOM }, found[1])
		assert.matches("new Peacebloom spot saved", addon.lastPrint())
	end)

	it("skips a herb picked at a Questie spot", function()
		addon.at(0.505, 0.5) -- 5 yards from the Questie spot
		addon.gather("Peacebloom")
		assert.equal(0, #addon.found())
	end)

	it("saves a different herb at a Questie spot of another herb", function()
		addon.at(0.5, 0.5)
		addon.gather("Silverleaf")
		assert.equal(1, #addon.found())
		assert.equal(SILVERLEAF, addon.found()[1][3])
	end)

	it("saves a spot only once", function()
		addon.at(0.3, 0.3)
		addon.gather("Peacebloom")
		addon.at(0.31, 0.3) -- 10 yards away, picked again after respawn
		addon.gather("Peacebloom")
		assert.equal(1, #addon.found())
	end)

	it("ignores casts on things that aren't herbs, and casts that don't finish", function()
		addon.at(0.3, 0.3)
		addon.gather("Copper Vein")
		addon.fire("UNIT_SPELLCAST_SENT", "player", "Peacebloom", "Cast-x", 2366)
		addon.fire("UNIT_SPELLCAST_FAILED", "player", "Cast-x", 2366)
		assert.equal(0, #addon.found())
	end)

	it("falls back to the loot GUID when the cast target is secret", function()
		addon.at(0.3, 0.3)
		addon.gather(wow.SECRET)
		assert.equal(0, #addon.found())
		addon.loot = "GameObject-0-1-0-1-3724-0000ABCD" -- Peacebloom object
		addon.fire("LOOT_OPENED")
		assert.equal(1, #addon.found())
		assert.equal(PEACEBLOOM, addon.found()[1][3])
	end)

	it("doesn't save twice when both the cast and the loot see the pick", function()
		addon.at(0.3, 0.3)
		addon.gather("Peacebloom")
		addon.loot = "GameObject-0-1-0-1-1618-0000ABCD"
		addon.fire("LOOT_OPENED")
		assert.equal(1, #addon.found())
	end)

	it("ignores loot from creatures and non-herb objects", function()
		addon.at(0.3, 0.3)
		addon.loot = "Creature-0-1-0-1-299-0000ABCD"
		addon.fire("LOOT_OPENED")
		addon.loot = "GameObject-0-1-0-1-1731-0000ABCD" -- Copper Vein
		addon.fire("LOOT_OPENED")
		assert.equal(0, #addon.found())
	end)

	it("saves nothing with finds turned off", function()
		addon.slash("finds off")
		addon.at(0.3, 0.3)
		addon.gather("Peacebloom")
		assert.equal(0, #addon.found())
	end)

	it("saves nothing without a map position (instances)", function()
		addon.pos = nil
		addon.gather("Peacebloom")
		assert.same({}, _G.HerbRingsFound)
	end)

	it("shows saved finds as spots, unless turned off", function()
		local loaded = wow.load({ found = { [1429] = { { 0.3, 0.3, PEACEBLOOM } } } })
		assert.equal(1, #loaded.ns.CollectZone(1429, 1000, 1000))
		loaded.slash("finds off")
		assert.equal(0, #loaded.ns.CollectZone(1429, 1000, 1000))
	end)

	it("forget removes finds near you only", function()
		addon.at(0.3, 0.3); addon.gather("Peacebloom")
		addon.at(0.8, 0.8); addon.gather("Peacebloom")
		addon.at(0.31, 0.3) -- 10 yards from the first
		addon.slash("forget")
		assert.equal(1, #addon.found())
		assert.same({ 0.8, 0.8, PEACEBLOOM }, addon.found()[1])
		assert.matches("removed 1", addon.lastPrint())
	end)

	it("forget all removes every find", function()
		addon.at(0.3, 0.3); addon.gather("Peacebloom")
		addon.pos.zone = 1426; addon.gather("Silverleaf")
		addon.slash("forget all")
		assert.same({}, _G.HerbRingsFound)
		assert.matches("removed 2", addon.lastPrint())
	end)

	it("keeps finds when settings are reset", function()
		addon.at(0.3, 0.3); addon.gather("Peacebloom")
		addon.slash("reset")
		assert.equal(1, #addon.found())
	end)
end)
