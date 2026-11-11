-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "9.0.8",
	welcome = "This patch fixes an error that could interrupt party quest-data updates.",
	sections = {
		{
			title = "Fixes",
			items = {
				"Fixed an error that could occur after grouping with another QuestTogether user when a background whisper failed. Party quest data can now continue loading normally.",
			},
		},
	},
}
