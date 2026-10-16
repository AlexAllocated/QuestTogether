-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "7.3.5",
	welcome = "Clearer map markers, easier player navigation, and fresher party information.",
	sections = {
		{
			title = "Maps and player information",
			items = {
				"Hover the QT map button for a visual legend of map icons and states.",
				"Left-click a world-map player dot to highlight it and open the most detailed map available for that location. At the final map level, left-click opens the player menu; right-click always opens it.",
				"Find on Map also opens the most detailed available map. Its green highlight follows map changes and clears after one minute, when the map closes, or when another player is selected.",
				"Hovering a player, cluster, or shared waypoint dims the map and unrelated markers while keeping the focused markers bright. The QT map button no longer dims the map on hover.",
				"Player glows now use one consistent effect, and party tooltips and clusters share fresher membership information with better recovery from delayed requests.",
				"Improved developer diagnostics while preserving diagnostic-sharing preferences and public location privacy.",
			},
		},
	},
}
