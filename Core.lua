local ADDON, ns = ...

local HBD = LibStub("HereBeDragons-2.0")
local Pins = LibStub("HereBeDragons-Pins-2.0")

local HERBALISM_SKILL_LINE = 182
local RING_TEXTURE = "Interface\\AddOns\\HerbRings\\Media\\Ring.tga"
local ZONE_RESCAN_SECONDS = 300 -- spawn data is static; an occasional rescan is plenty

local DEFAULTS = {
	enabled     = true,
	showRed     = true,
	showOrange  = true,
	showYellow  = true,
	showGreen   = true,
	showGray    = true,
	showUnknown = true,
	tooltip     = true,  -- colour herb names in world tooltips
	ringTooltip = true,  -- hovering a ring shows its herb and skill-up chance
	useFinds    = true,  -- save herbs you pick at spots Questie doesn't have, and show them
	debug       = false,
	size        = 12,    -- ring size in pixels
	alpha       = 0.9,
	radius      = 400,   -- only place rings for spots within this many yards
	thresholds  = { yellow = 25, green = 50, gray = 100 },
	colors      = {},    -- [difficulty] = { r, g, b }: base colour overrides
	herbColor   = {},    -- [nodeID] = { r, g, b }: per-herb colour, wins over the base colour
	herbHidden  = {},    -- [nodeID] = true: no rings for this herb
}
ns.DEFAULTS = DEFAULTS

local db
local skillRank, skillMod = nil, 0

local zoneSpots, zoneSources, zoneScannedAt = {}, {}, 0 -- spots of the current zone
local active = {}   -- spot -> ring frame (currently registered with HBD-Pins)
local pool = {}     -- spare ring frames
local lastZone, lastX, lastY
local dirty = true

local function Print(msg)
	print("|cff40c040HerbRings|r: " .. msg)
end

function ns.Debug(msg)
	if db and db.debug then Print("|cff999999" .. msg .. "|r") end
end

local function CopyDefaults(src, dst)
	for k, v in pairs(src) do
		if type(v) == "table" then
			dst[k] = type(dst[k]) == "table" and dst[k] or {}
			CopyDefaults(v, dst[k])
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
end

---------------------------------------------------------------------------
-- Herbalism skill
---------------------------------------------------------------------------
local function ReadHerbSkill()
	-- 1) GetProfessions / GetProfessionInfo: 7th return is the skill line ID.
	if GetProfessions and GetProfessionInfo then
		local profs = { GetProfessions() }
		for i = 1, select("#", GetProfessions()) do
			local idx = profs[i]
			if idx then
				local _, _, rank, _, _, _, skillLine, mod = GetProfessionInfo(idx)
				if skillLine == HERBALISM_SKILL_LINE then return rank, mod or 0 end
			end
		end
	end
	-- 2) C_SkillInfo by ID (returns either a table or several values).
	if C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID then
		local ok, a, b, _, d = pcall(C_SkillInfo.GetSkillLineInfoByID, HERBALISM_SKILL_LINE)
		if ok and type(a) == "table" then
			if a.rank or a.skillLineRank then
				return a.rank or a.skillLineRank, a.modifier or a.skillLineModifier or 0
			end
		elseif ok and a and b then
			return b, d or 0
		end
	end
	-- 3) Classic-style skill list, matched on the profession name.
	if GetNumSkillLines and GetSkillLineInfo then
		for i = 1, GetNumSkillLines() do
			local name, isHeader, _, rank, _, mod = GetSkillLineInfo(i)
			if not isHeader and name == "Herbalism" then return rank, mod or 0 end
		end
	end
	return nil, 0
end

local function Difficulty(id)
	return ns.GetDifficulty(ns.HerbReq(id), skillRank, skillMod, db.thresholds)
end

ns.Difficulty = function(id) return Difficulty(id) end
function ns.GetSkill() return skillRank, skillMod end

-- Colour for a difficulty (base colours), and for a herb (its own colour wins).
function ns.BaseColor(diff)
	return db.colors[diff] or ns.COLORS[diff] or ns.COLORS.unknown
end
function ns.HerbColor(id, diff)
	return db.herbColor[id] or ns.BaseColor(diff or Difficulty(id))
end

local function IsHidden(diff, id)
	return (id and db.herbHidden[id])
		or (diff == "red" and not db.showRed)
		or (diff == "orange" and not db.showOrange)
		or (diff == "yellow" and not db.showYellow)
		or (diff == "green" and not db.showGreen)
		or (diff == "gray" and not db.showGray)
		or (diff == "unknown" and not db.showUnknown)
end

---------------------------------------------------------------------------
-- Minimap rings
---------------------------------------------------------------------------
-- Ring hover tooltip. The minimap's own tooltip text is a secret value on Forever
-- (addons can't read it), so this one is built from our herb data instead.
local DIFF_TEXT = {
	red     = "can't pick yet",
	orange  = "skill-up guaranteed",
	yellow  = "skill-up likely",
	green   = "small chance of a skill-up",
	gray    = "no skill-up",
	unknown = "requirement unknown",
}
local ringTip

local function RingOnEnter(f)
	local spot = f.spot
	if not (db.ringTooltip and spot) then return end
	ringTip = ringTip or CreateFrame("GameTooltip", "HerbRingsTooltip", UIParent, "GameTooltipTemplate")
	ringTip:SetOwner(f, "ANCHOR_NONE")
	ringTip:ClearAllPoints()
	if GameTooltip:IsShown() and GameTooltip:GetBottom() and GameTooltip:GetBottom() > 120 then
		ringTip:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", 0, -2) -- under the minimap's own tooltip
	else
		ringTip:SetPoint("TOPRIGHT", f, "BOTTOMLEFT", -4, -4)
	end
	local h = ns.HERBS[spot.id]
	local req = ns.HerbReq(spot.id)
	local diff = Difficulty(spot.id)
	local c = ns.HerbColor(spot.id, diff)
	ringTip:AddDoubleLine(h and h[1] or "?", req and tostring(req) or "?", c[1], c[2], c[3], 0.6, 0.6, 0.6)
	local skill = skillRank and (tostring(skillRank) .. ((skillMod or 0) > 0 and (" +" .. skillMod) or "")) or "not learned"
	ringTip:AddLine(DIFF_TEXT[diff] .. " (Herbalism " .. skill .. ")", 0.8, 0.8, 0.8)
	ringTip:AddLine("Spawn point, may not be up", 0.5, 0.5, 0.5)
	ringTip:Show()
end

local function RingOnLeave()
	if ringTip then ringTip:Hide() end
end

local function AcquireRing()
	local f = table.remove(pool)
	if not f then
		f = CreateFrame("Frame")
		f.tex = f:CreateTexture(nil, "OVERLAY")
		f.tex:SetAllPoints()
		f.tex:SetTexture(RING_TEXTURE)
		f:SetScript("OnEnter", RingOnEnter)
		f:SetScript("OnLeave", RingOnLeave)
		-- hover only: clicks (and ideally motion) still reach the minimap underneath
		if f.SetMouseClickEnabled then f:SetMouseClickEnabled(false) end
		if f.SetPropagateMouseMotion then f:SetPropagateMouseMotion(true) end
	end
	if f.SetMouseMotionEnabled then f:SetMouseMotionEnabled(db.ringTooltip) else f:EnableMouse(db.ringTooltip) end
	f:SetSize(db.size, db.size)
	f:SetAlpha(db.alpha)
	return f
end

local function ReleaseRing(spot)
	local f = active[spot]
	if ringTip and ringTip:IsShown() and ringTip:GetOwner() == f then ringTip:Hide() end
	f.spot = nil
	Pins:RemoveMinimapIcon(ADDON, f)
	f:Hide()
	active[spot] = nil
	pool[#pool + 1] = f
end

local function ClearRings()
	for spot in pairs(active) do ReleaseRing(spot) end
end

local function ScanZone(zone, w, h)
	ClearRings()
	zoneSpots, zoneSources = ns.CollectZone(zone, w, h)
	zoneScannedAt = GetTime()
	ns.Debug(string.format("zone %d: %d herb spots from %s", zone, #zoneSpots,
		#zoneSources > 0 and table.concat(zoneSources, ", ") or "no source"))
end

local function Refresh(force)
	if not db.enabled then ClearRings(); return end

	local x, y, zone = HBD:GetPlayerZonePosition()
	if not (x and y and zone) then ClearRings(); lastZone = nil; return end

	local w, h = HBD:GetZoneSize(zone)
	if not w or w == 0 then ClearRings(); return end

	if zone ~= lastZone or dirty or GetTime() - zoneScannedAt > ZONE_RESCAN_SECONDS then
		ScanZone(zone, w, h)
		force = true
	end

	-- Skip the distance pass unless forced or we've moved ~25 yards.
	if not force and lastX then
		local dx, dy = (x - lastX) * w, (y - lastY) * h
		if dx * dx + dy * dy < 625 then return end
	end
	lastZone, lastX, lastY, dirty = zone, x, y, false

	local r2 = db.radius * db.radius
	local wanted = {}
	for _, spot in ipairs(zoneSpots) do
		local dx, dy = (spot.x - x) * w, (spot.y - y) * h
		if dx * dx + dy * dy <= r2 and not IsHidden(Difficulty(spot.id), spot.id) then
			wanted[spot] = true
		end
	end

	for spot in pairs(active) do
		if not wanted[spot] then ReleaseRing(spot) end
	end
	for spot in pairs(wanted) do
		if not active[spot] then
			local f = AcquireRing()
			local c = ns.HerbColor(spot.id)
			f.tex:SetVertexColor(c[1], c[2], c[3])
			f.spot = spot
			Pins:AddMinimapIconMap(ADDON, f, zone, spot.x, spot.y, false, false)
			active[spot] = f
		end
	end
end

-- Re-read the spawn data on the next refresh (own finds changed).
function ns.Rescan() dirty = true end

-- Full rebuild (after settings / skill changes): new colours, sizes, visibility.
local function Rebuild()
	ClearRings()
	lastX = nil
	Refresh(true)
end
-- Called by the options panel after a change; refreshes the panel too.
function ns.Changed()
	Rebuild()
	if ns.RefreshOptions then ns.RefreshOptions() end
end

---------------------------------------------------------------------------
-- Tooltips (minimap dot hover and herb in the world)
---------------------------------------------------------------------------
local annotated = setmetatable({}, { __mode = "k" }) -- fontstring -> text we set

-- Forever (like Retail 12.x) can hand addons "secret" values: shown by the game,
-- but any attempt to inspect them (compare, gsub, concat) is a Lua error.
local function IsSecret(v)
	if issecretvalue and issecretvalue(v) then return true end
	if canaccessvalue and not canaccessvalue(v) then return true end
	return false
end
-- Text of a fontstring, or nil plus "secret" when the game hides it from addons.
local function ReadText(fs)
	if not fs then return nil end
	local ok, text = pcall(fs.GetText, fs)
	if not ok then return nil, "error" end
	if IsSecret(text) then return nil, "secret" end -- check before touching it at all
	if text == nil then return nil end
	return text
end

local function AnnotateSegment(seg)
	local name = ns.StripEscapes(seg)
	if name == "" then return seg, false end
	local id = ns.HerbIDForName(name)
	if not id then return seg, false end
	local req = ns.HerbReq(id)
	local diff = ns.GetDifficulty(req, skillRank, skillMod, db.thresholds)
	local prefix = seg:match("^(.-)" .. name:gsub("%p", "%%%0")) or ""
	prefix = prefix:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	return string.format("%s|c%s%s|r |cff999999(%s)|r", prefix, ns.ColorHex(ns.HerbColor(id, diff)), name, req and tostring(req) or "?"), true
end

-- /hrings trace: print what each tooltip shows and who owns it, for a while
local traceUntil, traceLast = 0, nil

local function FrameLabel(f)
	if not f then return "nil" end
	local ok, name = pcall(f.GetName, f)
	if ok and name then return name end
	return tostring(f):gsub("table: ", "")
end

local function OwnerChain(f)
	local parts = {}
	for _ = 1, 4 do
		if not f then break end
		parts[#parts + 1] = FrameLabel(f)
		f = f.GetParent and f:GetParent()
	end
	return table.concat(parts, " < ")
end

local function Trace(tt, how)
	if GetTime() > traceUntil then return end
	local fs = tt:GetName() and _G[tt:GetName() .. "TextLeft1"]
	local text, why = ReadText(fs)
	text = text or ("<" .. (why or "empty") .. ">")
	local key = tostring(tt) .. how .. text
	if key == traceLast then return end
	traceLast = key
	Print(string.format("|cff999999[%s %s] owner: %s | text: %s|r", tt:GetName() or "?", how,
		OwnerChain(tt:GetOwner()), text:gsub("|", "||"):gsub("\n", " \\n ")))
end

local function AnnotateTooltipUnsafe(tt, how)
	if not db or tt ~= GameTooltip or (tt.IsForbidden and tt:IsForbidden()) then return end
	Trace(tt, type(how) == "string" and how or "hook")
	if not db.tooltip then return end
	-- Only minimap hovers and world objects; skip bags, AH, chat links (item "Peacebloom").
	local owner = tt:GetOwner()
	local isMinimap = false
	local o = owner
	for _ = 1, 3 do -- Minimap itself, or a child of it (skinned minimaps)
		if not o then break end
		if o == Minimap or o == MinimapCluster then isMinimap = true break end
		o = o.GetParent and o:GetParent()
	end
	if not isMinimap and owner ~= UIParent then return end

	local changed = false
	for i = 1, tt:NumLines() do
		local fs = _G["GameTooltipTextLeft" .. i]
		local text = ReadText(fs)
		if text and annotated[fs] ~= text then
			local parts, any = {}, false
			for seg in (text .. "\n"):gmatch("(.-)\n") do
				local newSeg, hit = AnnotateSegment(seg)
				parts[#parts + 1] = newSeg
				any = any or hit
			end
			if any then
				local newText = table.concat(parts, "\n")
				fs:SetText(newText)
				annotated[fs] = newText
				changed = true
			end
		end
	end
	if changed and tt:IsShown() then tt:Show() end -- resize to fit
end

local reportedError = false
local function AnnotateTooltip(tt, how)
	local ok, err = pcall(AnnotateTooltipUnsafe, tt, how)
	if not ok and not reportedError then
		reportedError = true
		Print("tooltip error (shown once, tooltips keep working where possible): " .. tostring(err))
	end
end

local function HookTooltips()
	GameTooltip:HookScript("OnShow", function(tt) AnnotateTooltip(tt, "OnShow") end)
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and TooltipDataProcessor.AllTypes then
		TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes, function(tt) AnnotateTooltip(tt, "TooltipData") end)
	end
	if GameTooltip.SetText then
		hooksecurefunc(GameTooltip, "SetText", function(tt) AnnotateTooltip(tt, "SetText") end)
	end
	-- Other tooltips (only traced, not coloured): shows if the minimap uses another one
	for _, name in ipairs({ "ItemRefTooltip", "ShoppingTooltip1", "EmbeddedItemTooltip", "MinimapTooltip" }) do
		local t = _G[name]
		if t and t.HookScript then t:HookScript("OnShow", function(tt) pcall(Trace, tt, "OnShow") end) end
	end
end

---------------------------------------------------------------------------
-- Own finds: a herb picked where no known spot is gets saved as a spot
---------------------------------------------------------------------------
local FIND_YARDS = 25   -- a pick this close to a known spot of the same herb is that spot
local FORGET_YARDS = 40 -- /hrings forget removes own finds this close to you
local pendingCast       -- { id, guid } of a Herb Gathering cast in progress

local function PlayerPos()
	local x, y, zone = HBD:GetPlayerZonePosition()
	if not (x and y and zone) then return end
	local w, h = HBD:GetZoneSize(zone)
	if not w or w == 0 then return end
	return x, y, zone, w, h
end

local function RecordFind(id)
	if not (db.useFinds and id and ns.HERBS[id]) then return end
	local x, y, zone, w, h = PlayerPos()
	if not x then return end
	local r2 = FIND_YARDS * FIND_YARDS
	for _, s in ipairs((ns.CollectZone(zone, w, h))) do -- includes earlier own finds
		local dx, dy = (s.x - x) * w, (s.y - y) * h
		if s.id == id and dx * dx + dy * dy <= r2 then
			ns.Debug(ns.HERBS[id][1] .. " picked at a known spot")
			return
		end
	end
	HerbRingsFound[zone] = HerbRingsFound[zone] or {}
	table.insert(HerbRingsFound[zone], {
		math.floor(x * 10000 + 0.5) / 10000, math.floor(y * 10000 + 0.5) / 10000, id,
	})
	Print("new " .. ns.HERBS[id][1] .. " spot saved (not in Questie). /hrings forget removes it.")
	dirty = true
	Refresh(true)
end

-- Remove own finds near you, or all of them. Returns how many.
local function ForgetFinds(all)
	local n = 0
	if all then
		for _, list in pairs(HerbRingsFound) do n = n + #list end
		wipe(HerbRingsFound)
	else
		local x, y, zone, w, h = PlayerPos()
		local list = x and HerbRingsFound[zone]
		if not list then return 0 end
		local r2 = FORGET_YARDS * FORGET_YARDS
		for i = #list, 1, -1 do
			local dx, dy = (list[i][1] - x) * w, (list[i][2] - y) * h
			if dx * dx + dy * dy <= r2 then
				table.remove(list, i)
				n = n + 1
			end
		end
		if #list == 0 then HerbRingsFound[zone] = nil end
	end
	dirty = true
	return n
end

local function CountFinds()
	local total, here = 0, 0
	local _, _, zone = HBD:GetPlayerZonePosition()
	for z, list in pairs(HerbRingsFound) do
		total = total + #list
		if z == zone then here = #list end
	end
	return here, total
end

-- Herb Gathering: the cast's target is the herb's name.
local function OnSpellcastSent(unit, target, castGUID)
	pendingCast = nil
	if unit ~= "player" then return end
	if IsSecret(target) or IsSecret(castGUID) then ns.Debug("cast target hidden, using loot instead"); return end
	if type(target) ~= "string" then return end
	local id = ns.HerbIDForName(target)
	if id then pendingCast = { id = id, guid = castGUID } end
end

local function OnSpellcastSucceeded(unit, castGUID)
	if unit ~= "player" or not pendingCast or IsSecret(castGUID) then return end
	if castGUID == pendingCast.guid then
		local id = pendingCast.id
		pendingCast = nil
		RecordFind(id)
	end
end

-- Fallback when the cast target isn't readable: the loot window's source GUID
-- (GameObject-0-server-instance-zone-objectID-spawn) names the herb object.
local function OnLootOpened()
	if not (GetLootSourceInfo and GetNumLootItems) then return end
	for i = 1, GetNumLootItems() do
		local ok, guid = pcall(GetLootSourceInfo, i)
		if ok and not IsSecret(guid) and type(guid) == "string" then
			local kind, _, _, _, _, objectID = strsplit("-", guid)
			if kind == "GameObject" and objectID then
				RecordFind(ns.HERB_OBJECTS[tonumber(objectID)])
			end
			return
		end
	end
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function OnOff(v)
	return v and "|cff40c040on|r" or "|cffc04040off|r"
end

local function Status()
	local n = 0
	for _ in pairs(active) do n = n + 1 end
	Print(string.format("enabled %s | Herbalism %s%s | %d herb spots in zone, %d rings shown",
		OnOff(db.enabled), tostring(skillRank or "not learned"),
		(skillMod and skillMod ~= 0) and (" (+" .. skillMod .. ")") or "", #zoneSpots, n))
	Print("data: " .. (#zoneSources > 0 and table.concat(zoneSources, ", ") or "|cffc04040Questie not found|r (HerbRings needs Questie/QuestieDB for herb spots)"))
	Print(string.format("show red %s, orange %s, yellow %s, green %s, gray %s, unknown %s | tooltip %s",
		OnOff(db.showRed), OnOff(db.showOrange), OnOff(db.showYellow), OnOff(db.showGreen),
		OnOff(db.showGray), OnOff(db.showUnknown), OnOff(db.tooltip)))
	Print(string.format("size %d, alpha %.2f, radius %d yd | bands: yellow +%d, green +%d, gray +%d",
		db.size, db.alpha, db.radius, db.thresholds.yellow, db.thresholds.green, db.thresholds.gray))
	local here, total = CountFinds()
	Print(string.format("your finds %s: %d in this zone, %d in total", OnOff(db.useFinds), here, total))
end

local function Help()
	Print("/hrings ...")
	print("  config - settings")
	print("  toggle - rings on/off")
	print("  red, orange, yellow, green, gray, unknown on|off - show/hide a colour")
	print("  hover on|off - ring tooltips")
	print("  tooltip on|off - world tooltip colouring")
	print("  finds on|off - save herbs you pick that Questie doesn't have")
	print("  forget - remove your finds near you (forget all: every zone)")
	print("  size <px>, alpha <0-1>, radius <yards>")
	print("  bands <yellow> <green> <gray> - default 25 50 100")
	print("  status, reset")
end

local SHOW_KEYS = { red = "showRed", orange = "showOrange", yellow = "showYellow", green = "showGreen", gray = "showGray", grey = "showGray", unknown = "showUnknown", tooltip = "tooltip", hover = "ringTooltip", finds = "useFinds", debug = "debug" }

SLASH_HERBRINGS1 = "/herbrings"
SLASH_HERBRINGS2 = "/hrings"
SlashCmdList.HERBRINGS = function(msg)
	local cmd, a, b, c = strsplit(" ", strtrim(msg or ""):lower())
	if cmd == "" or cmd == "help" then
		Help()
		return
	elseif cmd == "status" then
		Status()
		return
	elseif cmd == "config" or cmd == "options" then
		if ns.OpenOptions then ns.OpenOptions() end
		return
	elseif cmd == "trace" then
		traceUntil, traceLast = GetTime() + 60, nil
		Print("tracing tooltips for 60 seconds: hover a herb dot on the minimap")
		return
	elseif cmd == "toggle" then
		db.enabled = not db.enabled
		Print("rings " .. OnOff(db.enabled))
	elseif SHOW_KEYS[cmd] then
		local key = SHOW_KEYS[cmd]
		if a == "on" then db[key] = true elseif a == "off" then db[key] = false else db[key] = not db[key] end
		Print(cmd .. " " .. OnOff(db[key]))
		if key == "useFinds" then dirty = true end
	elseif cmd == "forget" then
		Print(string.format("removed %d of your finds", ForgetFinds(a == "all")))
	elseif cmd == "size" and tonumber(a) then
		db.size = math.max(6, math.min(64, tonumber(a)))
	elseif cmd == "alpha" and tonumber(a) then
		db.alpha = math.max(0.1, math.min(1, tonumber(a)))
	elseif cmd == "radius" and tonumber(a) then
		db.radius = math.max(50, math.min(5000, tonumber(a)))
	elseif cmd == "bands" and tonumber(a) and tonumber(b) and tonumber(c) then
		db.thresholds.yellow, db.thresholds.green, db.thresholds.gray = tonumber(a), tonumber(b), tonumber(c)
	elseif cmd == "reset" then
		wipe(db)
		CopyDefaults(DEFAULTS, db)
		Print("settings reset")
	else
		Help()
		return
	end
	ns.Changed()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function UpdateSkill()
	local rank, mod = ReadHerbSkill()
	if rank ~= skillRank or mod ~= skillMod then
		skillRank, skillMod = rank, mod
		ns.Changed()
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_LOGIN" then
		HerbRingsDB = HerbRingsDB or {}
		HerbRingsFound = type(HerbRingsFound) == "table" and HerbRingsFound or {} -- own finds, kept apart so a settings reset leaves them
		db = HerbRingsDB
		-- default ring size changed 18 -> 10 (0.7.0) -> 12 (0.7.1); follow it unless set by hand
		if not db.migratedSize12 and (db.size == 18 or db.size == 10) then db.size = 12 end
		db.migratedSize10, db.migratedSize12 = nil, true
		-- default range 600 -> 400 (0.7.2), unless set by hand
		if not db.migratedRadius400 and db.radius == 600 then db.radius = 400 end
		db.migratedRadius400 = true
		CopyDefaults(DEFAULTS, db)

		HookTooltips()
		skillRank, skillMod = ReadHerbSkill()
		ns.db = db
		if ns.BuildOptions then
			local ok, err = pcall(ns.BuildOptions)
			if not ok then Print("options panel failed to load: " .. tostring(err)) end
		end

		frame:RegisterEvent("SKILL_LINES_CHANGED")
		frame:RegisterEvent("CHAT_MSG_SKILL")
		frame:RegisterEvent("PLAYER_ENTERING_WORLD")
		frame:RegisterEvent("UNIT_SPELLCAST_SENT")
		frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
		frame:RegisterEvent("LOOT_OPENED")
		HBD.RegisterCallback(ADDON, "PlayerZoneChanged", function() Refresh() end)
		C_Timer.NewTicker(1, function() Refresh() end)
		Refresh(true)
	elseif event == "PLAYER_ENTERING_WORLD" then
		dirty = true
		Refresh()
	elseif event == "UNIT_SPELLCAST_SENT" then
		OnSpellcastSent(...)
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		OnSpellcastSucceeded(...)
	elseif event == "LOOT_OPENED" then
		OnLootOpened()
	else -- SKILL_LINES_CHANGED, CHAT_MSG_SKILL
		UpdateSkill()
	end
end)
