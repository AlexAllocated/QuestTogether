-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "5.10.0",
	welcome = "QuestTogether shares quest progress with your party and nearby players. Use the minimap button for settings, party quest comparisons, your quest journal, and these latest notes.",
	sections = {
		{
			title = "Compare and share party quests",
			items = {
				"Open Compare Party Quests from the minimap or quest and player menus, or type /qt compare. See who has each quest and how far everyone has progressed.",
				"All party quests appear by default. Check Hide quests I don't have to focus on quests in your own journal.",
				"Request shareable quests from party members using the updated addon. Requests ask permission by default; automatic sharing is an optional setting.",
				"Comparisons recover after map or combat restrictions. Refreshes replace older replies, and request cooldowns and failures explain when you can try again.",
			},
		},
		{
			title = "Shortcuts and quest menus",
			items = {
				"Drag the scroll-shaped minimap button to reposition it. Its menu opens settings, comparisons, the quest journal, patch notes, and the log-window destination control. Hide it from the menu and restore it in Miscellaneous settings.",
				"Quest-name menus offer Status, Share, Open in Quest Journal, and Compare Party Quests. Sharing and journal actions recheck the current quest and restrictions when clicked.",
				"Quest status links keep their titles intact after a quest leaves your log. The automatic-sharing checkbox now follows saved settings and profile changes.",
			},
		},
		{
			title = "Help and latest notes",
			items = {
				"Read the welcome and latest patch notes in their own window instead of repeated chat messages. Choose Patch Notes from the minimap menu or main Settings page, or use /qt notes, /qt changelog, or /qt patchnotes.",
				"The notes window opens automatically for major and minor upgrades. Patch updates still include fresh notes without opening the window automatically.",
				"Use /qt help for normal commands and /qt help debug for previews, diagnostics, and developer commands.",
			},
		},
	},
}
