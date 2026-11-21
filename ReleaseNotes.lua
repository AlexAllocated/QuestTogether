-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "10.1.4",
	welcome = "Smoother quest updates in combat and more consistent tooltip placement.",
	sections = {
		{
			title = "Quest updates during combat",
			items = {
				"Progress and ready-to-turn-in announcements for quests you are already tracking can now appear during ordinary combat, using your existing announcement settings.",
				"Unreadable quest data and other active restrictions still wait for a safe update. Announcements made during combat are not repeated when combat ends.",
			},
		},
		{
			title = "Party Objective Tracker placement",
			items = {
				"When QT hides the native quest tooltip, the snapped Party Objective Tracker now keeps that tooltip’s position instead of jumping back beside Blizzard’s tracker. It also follows movement and scale changes of the hovered quest row.",
			},
		},
	},
}
