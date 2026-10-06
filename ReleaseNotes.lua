-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "6.2.3",
	welcome = "Fewer repeated ready-to-turn-in announcements.",
	sections = {
		{
			title = "Quest readiness fixes",
			items = {
				"Quests already ready or complete when tracking starts are recorded quietly. Missing readiness data and later refreshes no longer replay already-observed ready-to-turn-in announcements.",
				"New completions still announce, and accepting a quest again resets its notification history. The sending player needs this update; older versions can still send bursts.",
			},
		},
	},
}
