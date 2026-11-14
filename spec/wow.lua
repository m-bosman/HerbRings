-- A small fake of the WoW API: just enough to load HerbRings and drive it with events.
-- Usage: local wow = require("spec.wow"); local addon = wow.load()
local M = {}

M.SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })

-- Frames: methods are no-ops unless defined here. Only names starting with a
-- capital are faked, so plain fields (f.spot, f.tex) still read as nil.
local function NewObject()
	local o = { scripts = {}, events = {} }
	function o:SetScript(name, fn) self.scripts[name] = fn end
	function o:HookScript(name, fn) self.scripts[name] = fn end
	function o:RegisterEvent(e) self.events[e] = true end
	function o:CreateTexture() return NewObject() end
	function o:CreateFontString() return NewObject() end
	return setmetatable(o, {
		__index = function(_, k)
			if type(k) == "string" and k:match("^%u") then return function() end end
		end,
	})
end

local function Split(sep, s)
	local out = {}
	for piece in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = piece end
	return unpack(out)
end

-- Loads the addon fresh. Returns a handle to drive it.
-- opts.spawns: { [objectID] = { [areaID] = { {x, y} } } } (0..100, like QuestieDB)
-- opts.found:  HerbRingsFound as saved from an earlier session
function M.load(opts)
	opts = opts or {}
	local h = {
		printed = {},
		frames = {},
		pins = 0,
		pos = { x = 0.2, y = 0.2, zone = 1429 }, -- Elwynn Forest
		zoneSize = { 1000, 1000 },               -- yards, so 0.001 = 1 yard
		loot = nil,                              -- GUID GetLootSourceInfo returns
		time = 0,
	}

	_G.HerbRingsDB = opts.db
	_G.HerbRingsFound = opts.found
	_G.SlashCmdList = {}
	_G.print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
		h.printed[#h.printed + 1] = table.concat(parts, " ")
	end
	_G.strsplit = Split
	_G.strtrim = function(s) return (s:match("^%s*(.-)%s*$")) end
	_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
	_G.hooksecurefunc = function() end
	_G.issecretvalue = function(v) return v == M.SECRET end
	_G.GetTime = function() return h.time end
	_G.C_Timer = { NewTicker = function() end }
	_G.CreateFrame = function()
		local f = NewObject()
		h.frames[#h.frames + 1] = f
		return f
	end
	_G.UIParent = NewObject()
	_G.Minimap = NewObject()
	_G.GameTooltip = NewObject()
	_G.GetNumLootItems = function() return h.loot and 1 or 0 end
	_G.GetLootSourceInfo = function() return h.loot, 1 end
	_G.ObjectDB = { spawns = function(id) return (opts.spawns or {})[id] end }

	local HBD = {
		RegisterCallback = function() end,
		GetPlayerZonePosition = function()
			if not h.pos then return end
			return h.pos.x, h.pos.y, h.pos.zone
		end,
		GetZoneSize = function() return h.zoneSize[1], h.zoneSize[2] end,
	}
	local Pins = {
		AddMinimapIconMap = function() h.pins = h.pins + 1 end,
		RemoveMinimapIcon = function() h.pins = h.pins - 1 end,
	}
	_G.LibStub = function(name)
		if name == "HereBeDragons-2.0" then return HBD end
		if name == "HereBeDragons-Pins-2.0" then return Pins end
	end

	local ns = {}
	for _, file in ipairs({ "Difficulty.lua", "Data.lua", "Sources.lua", "Core.lua", "Options.lua" }) do
		assert(loadfile(file))("HerbRings", ns)
	end
	h.ns = ns

	for _, f in ipairs(h.frames) do
		if f.events.PLAYER_LOGIN then h.eventFrame = f end
	end
	function h.fire(event, ...)
		h.eventFrame.scripts.OnEvent(h.eventFrame, event, ...)
	end
	function h.slash(msg) _G.SlashCmdList.HERBRINGS(msg) end
	function h.at(x, y) h.pos = { x = x, y = y, zone = h.pos and h.pos.zone or 1429 } end
	-- A Herb Gathering cast on `name` that finishes.
	local castN = 0
	function h.gather(name)
		castN = castN + 1
		local guid = "Cast-" .. castN
		h.fire("UNIT_SPELLCAST_SENT", "player", name, guid, 2366)
		h.fire("UNIT_SPELLCAST_SUCCEEDED", "player", guid, 2366)
	end
	function h.lastPrint() return h.printed[#h.printed] or "" end
	function h.found(zone) return _G.HerbRingsFound[zone or 1429] or {} end

	h.fire("PLAYER_LOGIN")
	return h
end

return M
