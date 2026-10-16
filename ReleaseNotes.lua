-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "7.3.4",
	welcome = "Clearer player tooltips and more consistent QuestTogether indicators.",
	sections = {
		{
			title = "Player tooltips and chat",
			items = {
				"Party rosters now show QT icons as soon as valid player location data is available, including after a reload.",
				"Party and cluster member lists keep status indicators compact. Developer and hidden-location explanations appear only when hovering that player directly; hidden-location indicators remain visible only to the developer.",
				"Verified developer announcements now use a scroll-and-gear icon, with a gold glow while looking for questing partners.",
			},
		},
	},
}
