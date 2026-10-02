-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "5.16.5",
	welcome = "A shorter prefix keeps party announcements compact.",
	sections = {
		{
			title = "Compact party announcements",
			items = {
				"Quest progress posted to party members without QuestTogether now starts with [QT] instead of [QuestTogether].",
				"Announcements still respect the chat message limit and preserve complete characters in every language.",
			},
		},
	},
}
