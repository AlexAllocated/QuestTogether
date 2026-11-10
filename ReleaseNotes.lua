-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "9.0.5",
	welcome = "Choose when QuestTogether appears below player tooltips, with further fixes for unwanted whisper failure notices.",
	sections = {
		{
			title = "Player tooltip visibility",
			items = {
				"Under Player Plates > Player tooltips, use QuestTogether tooltip to show the section for everyone or hide it for friends, party members, both, or everyone. Hide for friends is the default.",
				"The choice covers the entire section: logo, quest-partner status, and private notes. The section is always hidden on your own character. Your saved notes and sharing preferences are unchanged.",
			},
		},
		{
			title = "Whisper notices",
			items = {
				"Fixed several cases where hidden addon whispers could still produce “No player named…” messages, including delayed failures after a reply. Errors that could belong to your ordinary whispers remain visible.",
			},
		},
	},
}
