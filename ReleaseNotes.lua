-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "8.1.2",
	welcome = "Communication failures are now recorded quietly within QuestTogether.",
	sections = {
		{
			title = "Quieter error reporting",
			items = {
				"Server channel refusals and addon-message send failures no longer trigger BugSack or WoW’s global error handler.",
				"These failures remain available in QT’s debug log and /qt diagnostics, with the existing counters and limits on repeated entries.",
			},
		},
	},
}
