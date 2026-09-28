-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "5.12.0",
	welcome = "Find questing partners at a glance with highlighted map dots and player logos, simpler location settings, and reminders when another player has a newer stable QuestTogether release.",
	sections = {
		{
			title = "Spot questing partners",
			items = {
				"Players looking for questing partners have a soft gold glow around their class-colored map and minimap dots.",
				"Their QuestTogether nameplate logo gets a soft gold glow. Highlights disappear when the status is turned off or expires.",
				"Player Locations settings includes Only show players looking for questing partners. It starts off and filters both maps when enabled.",
				"The in-game What's New window shows regular and glowing logos and map dots side by side. Gold glow means looking for questing partners.",
			},
			illustration = "quest-partners",
		},
		{
			title = "Simpler location settings",
			items = {
				"Share my location and Show other players each apply to both the world map and minimap.",
				"Both options start enabled for new profiles. Existing location-sharing opt-outs are preserved when upgrading.",
			},
		},
		{
			title = "New-version reminders",
			items = {
				"QuestTogether notices when another player reports a newer stable addon version and prints an update reminder in your chosen QuestTogether chat window.",
				"The reminder is saved across characters and appears once each reload until you install the detected release or a newer one. Alpha and beta versions do not trigger reminders.",
				"Version announcements are small and infrequent. QuestTogether also recognizes version information in existing ping replies.",
			},
		},
	},
}
