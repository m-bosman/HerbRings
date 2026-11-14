-- Pure logic (no WoW API), so it can be tested outside the game.
local _, ns = ...
ns = ns or {}

-- Returns "red", "orange", "yellow", "green", "gray" or "unknown".
--   req        required Herbalism skill for the node (nil = unknown)
--   rank       base Herbalism skill
--   mod        skill bonus from gear / enchants / consumables (may be nil)
--   th         { yellow = n, green = n, gray = n }: offsets above req where the
--              colour changes (defaults 25 / 50 / 100, the usual gathering bands)
-- The "can I pick it?" check uses rank + mod; the skill-up bands use the base
-- rank, because gear bonuses don't change the chance of a skill point.
function ns.GetDifficulty(req, rank, mod, th)
	if not req then return "unknown" end
	if not rank then return "red" end
	if rank + (mod or 0) < req then return "red" end
	local d = rank - req
	if d < th.yellow then return "orange" end
	if d < th.green then return "yellow" end
	if d < th.gray then return "green" end
	return "gray"
end

ns.COLORS = {
	red     = { 1.00, 0.13, 0.13 },
	orange  = { 1.00, 0.50, 0.25 },
	yellow  = { 1.00, 1.00, 0.00 },
	green   = { 0.25, 0.75, 0.25 },
	gray    = { 0.50, 0.50, 0.50 },
	unknown = { 0.40, 0.70, 1.00 },
}

-- c = { r, g, b } (0..1) -> "ffRRGGBB" for |c escapes
function ns.ColorHex(c)
	return string.format("ff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255)
end

-- Removes |T...|t textures, |cXXXXXXXX colour codes and |r, plus surrounding spaces.
function ns.StripEscapes(s)
	s = s:gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	return (s:match("^%s*(.-)%s*$"))
end

return ns
