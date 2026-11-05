-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "8.3.1",
	welcome = "More reliable party quest refreshes after sharing quests.",
	sections = {
		{
			title = "Party quest updates",
			items = {
				"Refresh now requests a fresh party quest list even if an older update is stalled. Your existing data stays visible while the new list loads.",
				"QuestTogether also refreshes a party member's quest list when WoW confirms that they accepted a shared quest or already have it.",
				"Late objective replies can no longer overwrite newer quest ownership or progress and make an accepted quest appear missing.",
			},
		},
	},
}
