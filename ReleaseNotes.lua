-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "8.0.4",
	welcome = "Smoother player markers and shared waypoints on the world map.",
	sections = {
		{
			title = "World map",
			items = {
				"Player markers and shared party waypoints now follow the map smoothly as you zoom with the mouse wheel or drag to pan.",
				"Changing map levels, including right-clicking back to a broader view, updates QT markers immediately. Markers from the previous map no longer linger during the transition.",
			},
		},
	},
}
