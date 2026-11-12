-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "9.0.12",
	welcome = "A fix for chat channels changing unexpectedly.",
	sections = {
		{
			title = "Chat channels",
			items = {
				"QuestTogether no longer automatically rearranges your chat channels. This prevents its channel sorting from changing chat colors or sending typed messages to the wrong channel.",
				"If your chat was already affected, select your intended channel again and restore its color in WoW’s chat settings.",
			},
		},
	},
}
