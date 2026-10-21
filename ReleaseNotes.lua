-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "8.0.2",
	welcome = "More reliable map markers and VIP identification.",
	sections = {
		{
			title = "Reliability fixes",
			items = {
				"VIP stars now remain visible through your loading screens, and simultaneous VIP updates no longer block each other.",
				"Fixed a case where map markers could disappear when a location update temporarily had no coordinates.",
				"Improved reliability of shared updates during channel throttling.",
			},
		},
	},
}
