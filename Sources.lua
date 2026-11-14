-- Herb spots come from QuestieDB (installed with Questie): the game's spawn list for
-- every herb object on Forever. Herbs are identified by GatherMate2-style node IDs
-- (see Data.lua), which keeps names and requirements in one place.
local _, ns = ...



local sources = {}

-- QuestieDB (installed with Questie): the game's own spawn list for every herb
-- object, including Forever-only spawns (objects 657xxx) that GatherMate2's
-- player-collected data doesn't have. Object ID -> GatherMate2 node ID.
-- IDs found by name in QuestieDB_Forever.toc (QuestieDB 1.1.1, 2026-11-14).
local QUESTIE_HERB_OBJECTS = {
	[1618] = 401, [3724] = 401, [657382] = 401, [657456] = 401,  -- Peacebloom
	[1617] = 402, [3725] = 402, [657380] = 402, [657457] = 402,  -- Silverleaf
	[1619] = 403, [3726] = 403, [657383] = 403, [657458] = 403,  -- Earthroot
	[1620] = 404, [3727] = 404, [657459] = 404,                  -- Mageroyal
	[1621] = 405, [3729] = 405, [657385] = 405, [657460] = 405,  -- Briarthorn
	[2045] = 407, [657394] = 407,                                -- Stranglekelp
	[1622] = 408, [3730] = 408, [657386] = 408, [657461] = 408,  -- Bruiseweed
	[1623] = 409, [657387] = 409,                                -- Wild Steelbloom
	[1628] = 410, [657389] = 410,                                -- Grave Moss
	[1624] = 411,                                                -- Kingsblood
	[2041] = 412, [657390] = 412,                                -- Liferoot
	[2042] = 413,                                                -- Fadeleaf
	[2046] = 414,                                                -- Goldthorn
	[2043] = 415,                                                -- Khadgar's Whisker
	[2044] = 416,                                                -- Wintersbite
	[2866] = 417,                                                -- Firebloom
	[142140] = 418, [180165] = 418,                              -- Purple Lotus
	[142141] = 420, [176642] = 420,                              -- Arthas' Tears
	[142142] = 421, [176636] = 421, [180164] = 421,              -- Sungrass
	[142143] = 422, [183046] = 422,                              -- Blindweed
	[142144] = 423,                                              -- Ghost Mushroom
	[142145] = 424, [176637] = 424,                              -- Gromsblood
	[176583] = 425, [176638] = 425, [180167] = 425,              -- Golden Sansam
	[176584] = 426, [176639] = 426, [180168] = 426,              -- Dreamfoil
	[176586] = 427, [176640] = 427, [180166] = 427,              -- Mountain Silversage
	[176587] = 428, [176641] = 428,                              -- Plaguebloom
	[176588] = 429,                                              -- Icecap
	[176589] = 431,                                              -- Black Lotus
}
ns.HERB_OBJECTS = QUESTIE_HERB_OBJECTS

-- uiMapID -> Questie area ID (QuestieDB support/Forever/Zones/uiMapIdToAreaId.lua),
-- used when Questie's own ZoneDB isn't reachable.
local AREA_FOR_MAP = {
	[1411] = 14, [1412] = 215, [1413] = 17, [1416] = 36, [1417] = 45, [1418] = 3, [1419] = 4,
	[1420] = 85, [1421] = 130, [1422] = 28, [1423] = 139, [1424] = 267, [1425] = 47, [1426] = 1,
	[1427] = 51, [1428] = 46, [1429] = 12, [1430] = 41, [1431] = 10, [1432] = 38, [1433] = 44,
	[1434] = 33, [1435] = 8, [1436] = 40, [1437] = 11, [1438] = 141, [1439] = 148, [1440] = 331,
	[1441] = 400, [1442] = 406, [1443] = 405, [1444] = 357, [1445] = 15, [1446] = 440, [1447] = 16,
	[1448] = 361, [1449] = 490, [1450] = 493, [1451] = 1377, [1452] = 618,
}

local function QuestieArea(uiMapID)
	local loader = _G.QuestieLoader
	if type(loader) == "table" and loader.ImportModule then
		local ok, zoneDB = pcall(loader.ImportModule, loader, "ZoneDB")
		if ok and zoneDB and zoneDB.GetAreaIdByUiMapId then
			local ok2, area = pcall(zoneDB.GetAreaIdByUiMapId, zoneDB, uiMapID)
			if ok2 and area then return area end
		end
	end
	return AREA_FOR_MAP[uiMapID]
end

sources[#sources + 1] = {
	key = "questie",
	name = "Questie spawn data",
	available = function()
		local db = _G.ObjectDB
		return type(db) == "table" and type(db.spawns) == "function"
	end,
	each = function(zone, add)
		local area = QuestieArea(zone)
		if not area then return end
		local spawnsOf = _G.ObjectDB.spawns
		for objectID, nodeID in pairs(QUESTIE_HERB_OBJECTS) do
			local ok, spawns = pcall(spawnsOf, objectID)
			local list = ok and type(spawns) == "table" and spawns[area]
			if type(list) == "table" then
				for _, p in ipairs(list) do
					local x, y = p[1], p[2]
					if type(x) == "number" and type(y) == "number" and x > 0 and y > 0 then
						add(x / 100, y / 100, nodeID) -- Questie uses 0..100
					end
				end
			end
		end
	end,
}

-- Herbs you picked at spots the other sources don't have (saved by Core.lua).
-- HerbRingsFound = { [uiMapID] = { {x, y, nodeID}, ... } }, x/y 0..1.
sources[#sources + 1] = {
	key = "found",
	name = "your finds",
	available = function()
		return ns.db and ns.db.useFinds and type(_G.HerbRingsFound) == "table"
	end,
	each = function(zone, add)
		local list = _G.HerbRingsFound[zone]
		if type(list) ~= "table" then return end
		for _, p in ipairs(list) do
			if type(p[1]) == "number" and type(p[2]) == "number" and p[3] then
				add(p[1], p[2], p[3])
			end
		end
	end,
}

ns.SOURCES = sources

function ns.HerbIDForName(name)
	return name and ns.HERB_BY_NAME[name] or nil
end

-- All herb spots of a zone. Spots of the same herb closer than ~DEDUPE_YARDS are
-- merged (some herbs exist as several objects with overlapping spawn lists).
local DEDUPE_YARDS = 12
function ns.CollectZone(zone, zoneW, zoneH)
	local out, grid = {}, {}
	local cw, ch = DEDUPE_YARDS / zoneW, DEDUPE_YARDS / zoneH
	local function add(x, y, id)
		local gx, gy = math.floor(x / cw), math.floor(y / ch)
		for i = gx - 1, gx + 1 do
			for j = gy - 1, gy + 1 do
				local cell = grid[i * 100000 + j]
				if cell then
					for _, p in ipairs(cell) do
						if p.id == id and math.abs(p.x - x) < cw and math.abs(p.y - y) < ch then return end
					end
				end
			end
		end
		local p = { x = x, y = y, id = id }
		out[#out + 1] = p
		local key = gx * 100000 + gy
		grid[key] = grid[key] or {}
		table.insert(grid[key], p)
	end
	local used = {}
	for _, src in ipairs(sources) do
		if src.available() then
			local ok, err = pcall(src.each, zone, add)
			if ok then used[#used + 1] = src.name else ns.Debug("source " .. src.name .. " failed: " .. tostring(err)) end
		end
	end
	return out, used
end
