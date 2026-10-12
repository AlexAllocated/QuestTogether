-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "7.1.3",
	welcome = "More reliable quest text in your client’s language.",
	sections = {
		{
			title = "Quest Text Fixes",
			items = {
				"Quest announcements, Party Quest Log, and quest-following notices now pick up locally available quest names more reliably.",
				"Quest updates stay in order while names are loading. Quest Details also recovers correctly when tooltip text arrives late.",
				"Improved handling of quest names received from other players.",
			},
		},
	},
}
