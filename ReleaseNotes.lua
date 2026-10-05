-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "6.2.1",
	welcome = "Clearer control over party-chat announcements.",
	sections = {
		{
			title = "Know when QT posts to party chat",
			items = {
				"The setting under Where to Announce now clearly says that QT also posts to party chat when a member is not recognized as a QT user. It remains on by default.",
				"A new dialog with the QT logo appears after a short discovery delay. Choose Keep enabled or Turn off announcements before forwarding starts. Don't remind me again saves your acknowledgement for the current profile.",
				"The localized reminder names the affected members and can return when new unidentified members join. It disappears if they are recognized as QT users. Events held back while waiting are not replayed.",
			},
		},
	},
}
