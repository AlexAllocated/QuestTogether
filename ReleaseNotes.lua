-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "5.15.0",
	welcome = "QuestTogether now supports every WoW language and can display other players’ quest updates in your client’s language.",
	sections = {
		{
			title = "Play in more languages",
			items = {
				"Menus, settings, and patch notes now support all WoW language locales: English, German, French, European Spanish, Latin American Spanish, Brazilian Portuguese, Russian, Italian, Korean, Simplified Chinese, and Traditional Chinese.",
				"Latin American Spanish now has its own text instead of sharing European Spanish.",
			},
		},
		{
			title = "Localized quest progress",
			items = {
				"Supported quest events from updated QT players can appear in your client language in QT chat logs and bubbles, using local quest titles when available and the sender’s actual progress numbers.",
				"When a translated objective description cannot be chosen safely, QT uses a localized objective number with counts, percentages, completion, or progress status instead.",
				"Older QT versions and public party chat retain the sender’s wording. When WoW cannot supply a local quest title, QT keeps the source title or shows the quest ID. Same-language events keep their detailed native wording.",
			},
		},
		{
			title = "Quest title polish",
			items = {
				"Quest comparison now prefers your local quest title when available.",
				"Localized quest titles with non-ASCII punctuation stay clickable more reliably.",
			},
		},
	},
}
