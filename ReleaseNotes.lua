-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "7.1.1",
	welcome = "Discover more of QuestTogether with helpful tips.",
	sections = {
		{
			title = "QuestTogether Tips",
			items = {
				"QT now shows a tip when you log in or reload, drawing from a shuffled pool without repeats until it runs out.",
				"You can disable automatic tips under General on the main QuestTogether settings page. /qt tip and /qt hint remain available.",
			},
			tip = {
				label = "Tip:",
				text = "Type /qt tip or /qt hint to see another QuestTogether tip whenever you like.",
			},
		},
	},
}
