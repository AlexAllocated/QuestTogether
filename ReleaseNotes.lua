-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "7.4.3",
	welcome = "Clearer names and controls for party questing.",
	sections = {
		{
			title = "Party questing",
			items = {
				"Quest Tracker is now Party Objective Tracker (POT). Existing display settings and window placement are preserved.",
				"Use /qt pql to open Party Quest Log. /qt compare still works as an alias; help and tips now use /qt pql.",
				"Hide when not in a party is available in both HUD Edit Mode and Settings > Groups & Sharing > Party Objective Tracker. Both checkboxes control the same setting. It defaults on for new profiles and Reset to Default; existing saved choices are preserved.",
			},
		},
	},
}
