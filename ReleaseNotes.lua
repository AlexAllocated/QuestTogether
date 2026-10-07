-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "6.5.8",
	welcome = "Native WoW dropdowns, clearer map controls, and developer diagnostics.",
	sections = {
		{
			title = "Settings and player maps",
			items = {
				"All nine settings dropdowns now use native WoW controls with gold selected text, black menus, and previous/next buttons.",
				"Players shown on maps replaces the separate visibility and party-override checkboxes. Choose all QT players, players looking for questing partners with or without your party, party only, or None. Existing preferences are retained; sharing your own location stays separate.",
				"The new Developer settings category contains Open Debug Window, Rescan Quest Log, and the diagnostic-sharing option.",
			},
		},
		{
			title = "Diagnostic replies",
			items = {
				"Share diagnostic data with the developer is enabled by default. It allows authenticated developer requests for QT diagnostics, addon settings, and in-game character, party, and location data, even when public location sharing is off. Disable it under Developer to stop sharing this data.",
				"Diagnostic replies use private addon whispers, split into paced pages so larger replies retain their fields. Remote diagnostics requires both players to use 6.5.8 or newer; published 6.5.7 clients cannot answer these requests.",
			},
		},
	},
}
