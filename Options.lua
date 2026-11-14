-- Esc > Options > AddOns > HerbRings
--
-- Built once at login. The panel has no OnShow/OnHide/OnCommit/OnDefault/OnRefresh
-- handlers: addon code running while the game opens or closes its Options window
-- can taint it (Log Out / Exit get blocked). Our code only runs when you click one
-- of our own controls; the panel is kept in sync by ns.RefreshOptions after every
-- change (also changes made with /hrings).
local ADDON, ns = ...

local PANEL_W = 640
local category, panel
local controls = {}   -- refresh functions
local updating = false

local DIFFS = {
	{ key = "red",     label = "Red",     desc = "can't pick yet" },
	{ key = "orange",  label = "Orange",  desc = "skill-up guaranteed" },
	{ key = "yellow",  label = "Yellow",  desc = "skill-up likely" },
	{ key = "green",   label = "Green",   desc = "small chance" },
	{ key = "gray",    label = "Gray",    desc = "no skill-up" },
	{ key = "unknown", label = "Unknown", desc = "requirement unknown" },
}

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------
local function Text(parent, font, text)
	local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
	fs:SetJustifyH("LEFT")
	if text then fs:SetText(text) end
	return fs
end

local function Header(parent, text, y)
	local fs = Text(parent, "GameFontNormalLarge", text)
	fs:SetPoint("TOPLEFT", 16, y)
	local line = parent:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(1, 1, 1, 0.15)
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -4)
	line:SetPoint("RIGHT", parent, "RIGHT", -16, 0)
	return fs
end

local function Checkbox(parent, label, x, y, get, set, tooltip)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetSize(24, 24)
	cb:SetPoint("TOPLEFT", x, y)
	local fs = Text(parent, "GameFontHighlight", label)
	fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
	cb.label = fs
	cb:SetScript("OnClick", function(self)
		set(self:GetChecked() and true or false)
		ns.Changed()
	end)
	if tooltip then
		cb:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(label, 1, 1, 1)
			GameTooltip:AddLine(tooltip, nil, nil, nil, true)
			GameTooltip:Show()
		end)
		cb:SetScript("OnLeave", GameTooltip_Hide)
	end
	controls[#controls + 1] = function() cb:SetChecked(get()) end
	return cb
end

local sliderCount = 0
local function Slider(parent, label, x, y, width, minV, maxV, step, get, set, fmt)
	sliderCount = sliderCount + 1
	local name = "HerbRingsOptionsSlider" .. sliderCount
	local ok, s = pcall(CreateFrame, "Slider", name, parent, "OptionsSliderTemplate")
	if not ok or not s then
		-- minimal fallback if the template doesn't exist on this client
		s = CreateFrame("Slider", name, parent)
		s:SetOrientation("HORIZONTAL")
		s:SetHeight(17)
		local bg = s:CreateTexture(nil, "BACKGROUND")
		bg:SetColorTexture(0, 0, 0, 0.5)
		bg:SetPoint("LEFT"); bg:SetPoint("RIGHT"); bg:SetHeight(6)
		local thumb = s:CreateTexture(nil, "OVERLAY")
		thumb:SetColorTexture(1, 0.82, 0, 1)
		thumb:SetSize(10, 16)
		s:SetThumbTexture(thumb)
	end
	for _, region in ipairs({ s.Low, s.High, s.Text, _G[name .. "Low"], _G[name .. "High"], _G[name .. "Text"] }) do
		if region and region.SetText then region:SetText("") end
	end
	s:SetWidth(width)
	s:SetPoint("TOPLEFT", x, y - 16)
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(step)
	if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end

	local title = Text(parent, "GameFontNormal", label)
	title:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 3)
	local value = Text(parent, "GameFontHighlightSmall")
	value:SetPoint("BOTTOMRIGHT", s, "TOPRIGHT", 0, 3)
	value:SetJustifyH("RIGHT")

	local function show(v) value:SetText(string.format(fmt or "%d", v)) end
	s:SetScript("OnValueChanged", function(_, v)
		v = math.floor(v / step + 0.5) * step
		show(v)
		if updating or v == get() then return end
		set(v)
		ns.Changed()
	end)
	controls[#controls + 1] = function() s:SetValue(get()); show(get()) end
	return s
end

local function Button(parent, text, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 22)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

-- Colour picker (new API first, then the classic one)
local function PickColor(c, onPick)
	local r, g, b = c[1], c[2], c[3]
	local function current()
		local nr, ng, nb = ColorPickerFrame:GetColorRGB()
		return { nr, ng, nb }
	end
	if ColorPickerFrame.SetupColorPickerAndShow then
		ColorPickerFrame:SetupColorPickerAndShow({
			r = r, g = g, b = b, hasOpacity = false,
			swatchFunc = function() onPick(current()) end,
			cancelFunc = function() onPick({ r, g, b }) end,
		})
	else
		ColorPickerFrame.hasOpacity = false
		ColorPickerFrame.func = function() onPick(current()) end
		ColorPickerFrame.cancelFunc = function() onPick({ r, g, b }) end
		ColorPickerFrame:SetColorRGB(r, g, b)
		ColorPickerFrame:Hide() -- re-show so it picks up the new values
		ColorPickerFrame:Show()
	end
end

-- A clickable colour square. getColor() -> {r,g,b}; setColor(c or nil) (nil = reset)
local function Swatch(parent, size, getColor, setColor, tooltip)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(size, size)
	local border = b:CreateTexture(nil, "BACKGROUND")
	border:SetAllPoints()
	border:SetColorTexture(0.8, 0.8, 0.8, 1)
	local fill = b:CreateTexture(nil, "ARTWORK")
	fill:SetPoint("TOPLEFT", 1, -1)
	fill:SetPoint("BOTTOMRIGHT", -1, 1)
	b.fill = fill
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetScript("OnClick", function(_, button)
		if button == "RightButton" then
			setColor(nil)
			ns.Changed()
		else
			PickColor(getColor(), function(c) setColor(c); ns.Changed() end)
		end
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(tooltip or "Colour", 1, 1, 1)
		GameTooltip:AddLine("Left-click: pick a colour", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("Right-click: reset", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	controls[#controls + 1] = function()
		local c = getColor()
		fill:SetColorTexture(c[1], c[2], c[3], 1)
	end
	return b
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------
local function SortedHerbs()
	local list = {}
	for id, h in pairs(ns.HERBS) do
		if id > 0 then list[#list + 1] = { id = id, name = h[1], req = h.req or nil } end
	end
	table.sort(list, function(a, b)
		local ra, rb = a.req or 9999, b.req or 9999
		if ra ~= rb then return ra < rb end
		return a.name < b.name
	end)
	return list
end

local function Build()
	local db = ns.db
	panel = CreateFrame("Frame")
	panel:Hide()

	local scroll = CreateFrame("ScrollFrame", "HerbRingsOptionsScroll", panel, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, -4)
	scroll:SetPoint("BOTTOMRIGHT", -28, 4)
	local c = CreateFrame("Frame", nil, scroll)
	c:SetSize(PANEL_W, 10)
	scroll:SetScrollChild(c)

	local y = -12
	local title = Text(c, "GameFontNormalHuge", "HerbRings")
	title:SetPoint("TOPLEFT", 16, y)
	local ver = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON, "Version") or ""
	if ver:find("@", 1, true) then ver = "dev" end -- unpackaged checkout
	local sub = Text(c, "GameFontDisableSmall", "v" .. ver .. "   /hrings help for slash commands")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	y = y - 52

	-- General ------------------------------------------------------------
	Header(c, "General", y); y = y - 30
	Checkbox(c, "Show rings on the minimap", 16, y,
		function() return db.enabled end, function(v) db.enabled = v end)
	Checkbox(c, "Tooltip when hovering a ring", 320, y,
		function() return db.ringTooltip end, function(v) db.ringTooltip = v end,
		"Herb name, required skill and your skill-up chance.")
	y = y - 28
	Checkbox(c, "Colour herb names in world tooltips", 16, y,
		function() return db.tooltip end, function(v) db.tooltip = v end,
		"Herbs you mouse over in the world. The minimap's own tooltip can't be changed by addons.")
	y = y - 40

	Slider(c, "Ring size", 24, y, 180, 6, 40, 1,
		function() return db.size end, function(v) db.size = v end, "%d px")
	Slider(c, "Ring opacity", 230, y, 180, 0.1, 1, 0.05,
		function() return db.alpha end, function(v) db.alpha = v end, "%.2f")
	Slider(c, "Range", 436, y, 180, 100, 2000, 50,
		function() return db.radius end, function(v) db.radius = v end, "%d yd")
	y = y - 56

	-- Colours ------------------------------------------------------------
	Header(c, "Colours", y); y = y - 26
	local note = Text(c, "GameFontHighlightSmall",
		"Click to change, right-click to reset. Untick to hide that colour.")
	note:SetPoint("TOPLEFT", 16, y); note:SetWidth(PANEL_W - 32); note:SetWordWrap(true)
	y = y - 30
	for i, d in ipairs(DIFFS) do
		local col = (i - 1) % 3
		local row = math.floor((i - 1) / 3)
		local x, yy = 16 + col * 205, y - row * 30
		local showKey = "show" .. d.label -- showRed, showOrange, ... showUnknown
		Checkbox(c, "", x, yy, function() return db[showKey] end, function(v) db[showKey] = v end,
			"Show rings for: " .. d.desc)
		local sw = Swatch(c, 16, function() return ns.BaseColor(d.key) end,
			function(v) db.colors[d.key] = v end, d.label .. ": " .. d.desc)
		sw:SetPoint("TOPLEFT", x + 28, yy - 4)
		local lbl = Text(c, "GameFontHighlight", d.label .. " |cff999999- " .. d.desc .. "|r")
		lbl:SetPoint("LEFT", sw, "RIGHT", 6, 0)
	end
	y = y - 66

	local bandsNote = Text(c, "GameFontHighlightSmall", "Colour changes at this much skill above the herb's requirement:")
	bandsNote:SetPoint("TOPLEFT", 16, y)
	y = y - 22
	Slider(c, "Yellow from", 24, y, 180, 0, 100, 1,
		function() return db.thresholds.yellow end, function(v) db.thresholds.yellow = v end, "+%d")
	Slider(c, "Green from", 230, y, 180, 0, 150, 1,
		function() return db.thresholds.green end, function(v) db.thresholds.green = v end, "+%d")
	Slider(c, "Gray from", 436, y, 180, 0, 200, 1,
		function() return db.thresholds.gray end, function(v) db.thresholds.gray = v end, "+%d")
	y = y - 56

	-- Herbs --------------------------------------------------------------
	Header(c, "Herbs", y); y = y - 26
	local hNote = Text(c, "GameFontHighlightSmall",
		"Untick to hide. Click the colour to pick one for that herb, right-click to go back.")
	hNote:SetPoint("TOPLEFT", 16, y); hNote:SetWidth(PANEL_W - 32); hNote:SetWordWrap(true)
	y = y - 26
	local showAll = Button(c, "Show all", 90, function() wipe(db.herbHidden); ns.Changed() end)
	showAll:SetPoint("TOPLEFT", 16, y)
	local hideAll = Button(c, "Hide all", 90, function()
		for id in pairs(ns.HERBS) do if id > 0 then db.herbHidden[id] = true end end
		ns.Changed()
	end)
	hideAll:SetPoint("LEFT", showAll, "RIGHT", 6, 0)
	local resetCols = Button(c, "Reset herb colours", 140, function() wipe(db.herbColor); ns.Changed() end)
	resetCols:SetPoint("LEFT", hideAll, "RIGHT", 6, 0)
	y = y - 30

	local colHdr = Text(c, "GameFontNormalSmall", "Req.")
	colHdr:SetPoint("TOPLEFT", 16, y)
	local colHdr2 = Text(c, "GameFontNormalSmall", "Herb")
	colHdr2:SetPoint("TOPLEFT", 84, y)
	local colHdr3 = Text(c, "GameFontNormalSmall", "Colour")
	colHdr3:SetPoint("TOPLEFT", 300, y)
	y = y - 16

	for i, h in ipairs(SortedHerbs()) do
		if i % 2 == 0 then
			local stripe = c:CreateTexture(nil, "BACKGROUND")
			stripe:SetColorTexture(1, 1, 1, 0.04)
			stripe:SetPoint("TOPLEFT", 12, y + 1)
			stripe:SetSize(PANEL_W - 24, 24)
		end
		local req = Text(c, "GameFontHighlight", h.req and tostring(h.req) or "?")
		req:SetPoint("TOPLEFT", 16, y - 5)
		req:SetWidth(30); req:SetJustifyH("RIGHT")
		local cb = Checkbox(c, "", 52, y, function() return not db.herbHidden[h.id] end,
			function(v) db.herbHidden[h.id] = (not v) or nil end)
		local name = Text(c, "GameFontHighlight", h.name)
		name:SetPoint("LEFT", cb, "RIGHT", 6, 0)
		local sw = Swatch(c, 16, function() return ns.HerbColor(h.id) end,
			function(v) db.herbColor[h.id] = v end, h.name)
		sw:SetPoint("TOPLEFT", 300, y - 4)
		local state = Text(c, "GameFontDisableSmall")
		state:SetPoint("LEFT", sw, "RIGHT", 8, 0)
		controls[#controls + 1] = function()
			local col = ns.HerbColor(h.id)
			name:SetTextColor(col[1], col[2], col[3])
			local diff = ns.Difficulty(h.id)
			state:SetText(db.herbColor[h.id] and "own colour" or diff)
			name:SetAlpha(db.herbHidden[h.id] and 0.4 or 1)
		end
		y = y - 24
	end
	y = y - 16

	local reset = Button(c, "Reset all HerbRings settings", 200, function()
		wipe(db)
		for k, v in pairs(ns.DEFAULTS) do
			if type(v) == "table" then
				db[k] = {}
				for k2, v2 in pairs(v) do db[k][k2] = v2 end
			else
				db[k] = v
			end
		end
		ns.Changed()
	end)
	reset:SetPoint("TOPLEFT", 16, y)
	y = y - 40

	c:SetHeight(-y)

	category = Settings.RegisterCanvasLayoutCategory(panel, "HerbRings")
	Settings.RegisterAddOnCategory(category)
	ns.RefreshOptions()
end

function ns.RefreshOptions()
	if not panel then return end
	updating = true
	for _, f in ipairs(controls) do pcall(f) end
	updating = false
end

function ns.BuildOptions()
	if panel or not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
	Build()
end

function ns.OpenOptions()
	if category and Settings.OpenToCategory then
		Settings.OpenToCategory(category.GetID and category:GetID() or category)
	end
end
