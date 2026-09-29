-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "5.14.0",
	welcome = "QuestTogether now speaks five more languages and helps you keep party members without QT informed.",
	sections = {
		{
			title = "Play in your language",
			items = {
				"The interface is now available in German, French, Spanish, Brazilian Portuguese, and Russian. QuestTogether follows your game language, with English as the fallback.",
				"Settings, menus, tooltips, quest comparisons, and patch notes are translated. Quest names and progress text received from other players stay in their original language.",
				"Find translated release announcements in the five language-specific changelog channels on our Discord.",
			},
		},
		{
			title = "Keep your whole party informed",
			items = {
				"A new Where to Announce option sends your enabled event announcements to party chat when someone in your party has not been recognized as a QT user. It starts enabled and can be turned off in settings.",
				"This also works in matched instance parties. Solo play and raids are excluded, and other players’ announcements are never relayed.",
			},
		},
	},
}
