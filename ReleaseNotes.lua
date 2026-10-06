-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "6.4.3",
	welcome = "Fixes for quest focus and party tooltips, plus simpler map display settings.",
	sections = {
		{
			title = "Your quest focus",
			items = {
				"Your Party Quest Log header now reads your own focused quest directly, including while solo or with quest-focus sharing off. Changing your super-tracked quest updates the header without needing Refresh.",
			},
		},
		{
			title = "Party tooltip rosters",
			items = {
				"Small-party tooltips immediately list the hovered player alongside the leader while the full roster loads. The loading message appears only when other members are still missing; groups larger than five still show only the leader.",
			},
		},
		{
			title = "Simpler map settings",
			items = {
				"One Show other players on the map and minimap checkbox now controls both displays. Sharing your own location stays independent. Existing settings keep display enabled if either map was enabled, or disabled if both were off.",
			},
		},
	},
}
