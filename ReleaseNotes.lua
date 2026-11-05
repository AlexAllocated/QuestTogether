-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "8.2.1",
	welcome = "Party quest data now refreshes in the background, with clearer focus and status indicators.",
	sections = {
		{
			title = "Party quest data",
			items = {
				"In parties of up to five, QT refreshes quest lists and objectives even while Party Quest Log is closed and Party Objective Tracker is hidden. Information fills in as it arrives; game communication delays can still affect updates.",
				"Moving the pointer away from a quest no longer interrupts the party data request. Progress already received remains available when you return.",
			},
		},
		{
			title = "Focus and status indicators",
			items = {
				"Class-colored dots beside quest titles in Blizzard’s Objective Tracker show which quests your party members have focused, whether or not you are following anyone.",
				"Each player’s Party Objective Tracker section now has status icons for active, ready-to-turn-in and completed quests, plus loading and unknown indicators. Fetching objective details does not erase known turn-in readiness.",
				"Fixed Focus and Hover losing the focused quest when unrelated waypoint information could not be read.",
			},
		},
	},
}
