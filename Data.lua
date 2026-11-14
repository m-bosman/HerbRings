local _, ns = ...

-- Herbs by GatherMate2 node ID (a handy, stable numbering).
--   [1], [2]...  English tooltip name, then variants
--   req          required Herbalism skill, false if unknown
-- Requirements are the Classic ones, which Forever kept.
ns.HERBS = {
	[401] = { req = 1,   "Peacebloom", "Wilted Peacebloom" },
	[402] = { req = 1,   "Silverleaf", "Stunted Silverleaf" },
	[403] = { req = 15,  "Earthroot" },
	[404] = { req = 50,  "Mageroyal" },
	[405] = { req = 70,  "Briarthorn" },
	[407] = { req = 85,  "Stranglekelp" },
	[408] = { req = 100, "Bruiseweed" },
	[409] = { req = 115, "Wild Steelbloom" },
	[410] = { req = 120, "Grave Moss" },
	[411] = { req = 125, "Kingsblood" },
	[412] = { req = 150, "Liferoot" },
	[413] = { req = 160, "Fadeleaf" },
	[414] = { req = 170, "Goldthorn" },
	[415] = { req = 185, "Khadgar's Whisker" },
	[416] = { req = 195, "Wintersbite" },
	[417] = { req = 205, "Firebloom" },
	[418] = { req = 210, "Purple Lotus" },
	[420] = { req = 220, "Arthas' Tears" },
	[421] = { req = 230, "Sungrass" },
	[422] = { req = 235, "Blindweed" },
	[423] = { req = 245, "Ghost Mushroom" },
	[424] = { req = 250, "Gromsblood" },
	[425] = { req = 260, "Golden Sansam" },
	[426] = { req = 270, "Dreamfoil" },
	[427] = { req = 280, "Mountain Silversage" },
	[428] = { req = 285, "Plaguebloom" },
	[429] = { req = 290, "Icecap" },
	[431] = { req = 300, "Black Lotus" },
	-- Forever-only, requirement unknown so far
	[4401] = { req = false, "Demonsage" },
	[4402] = { req = false, "Marefoil" },
	[-1]   = { req = false, "Death Lotus" }, -- tooltip only, no spawn data yet
}

-- name -> id, for tooltips (English names only for now)
ns.HERB_BY_NAME = {}
for id, h in pairs(ns.HERBS) do
	for _, name in ipairs(h) do ns.HERB_BY_NAME[name] = id end
end

function ns.HerbReq(id)
	local h = ns.HERBS[id]
	return h and h.req or nil
end
