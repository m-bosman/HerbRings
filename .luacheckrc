-- luacheck config. Run: luacheck .
std = "lua51"
max_line_length = false
exclude_files = { "Libs/", "spec/", ".luarocks/" }

-- Globals the addon sets
globals = {
	"HerbRingsDB", "HerbRingsFound", "ColorPickerFrame",
	"SLASH_HERBRINGS1", "SLASH_HERBRINGS2",
	SlashCmdList = { fields = { "HERBRINGS" } },
}

-- WoW API and other addons' globals the addon reads
read_globals = {
	"LibStub", "CreateFrame", "UIParent", "GameTooltip", "GameTooltip_Hide", "Minimap", "MinimapCluster",
	"Settings", "C_AddOns", "GetAddOnMetadata", "C_Timer", "C_SkillInfo",
	"GetProfessions", "GetProfessionInfo", "GetNumSkillLines", "GetSkillLineInfo",
	"GetTime", "GetLootSourceInfo", "GetNumLootItems", "TooltipDataProcessor",
	"hooksecurefunc", "issecretvalue", "canaccessvalue",
	"strsplit", "strtrim", "wipe",
	"QuestieLoader", "ObjectDB",
}
