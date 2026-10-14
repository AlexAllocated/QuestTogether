-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "7.2.1",
	welcome = "Fixes for private notes and collapsed Party Quest Log columns.",
	sections = {
		{
			title = "Fixes and Polish",
			items = {
				"Fixed the missing text cursor in private player notes and made the focus border more subtle.",
				"Improved scrolling while editing longer player notes.",
				"Collapsed Party Quest Log columns now use reliable icons for ready and completed quests instead of characters that could appear as empty boxes.",
			},
		},
	},
}
