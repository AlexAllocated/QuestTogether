-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "6.5.5",
	welcome = "A fix for missing quest icons in Party Quest Log.",
	sections = {
		{
			title = "Party Quest Log icons",
			items = {
				"Fixed quest focus buttons sometimes appearing as empty circles after scrolling or updating the list. Reused buttons now reset their artwork correctly, with a fallback icon if the requested artwork cannot be applied.",
			},
		},
	},
}
