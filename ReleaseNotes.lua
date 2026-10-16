-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "7.3.0",
	welcome = "Find players on busy maps, reconnect with recent companions, and follow quest progress with fewer repeated announcements.",
	sections = {
		{
			title = "Player Maps",
			items = {
				"World-map dots cluster when they overlap. Clustering is on by default and can be disabled in Player Locations.",
				"Click a cluster to open the most detailed map containing all its players. Any remaining cluster expands into individual dots for normal hovers and menus; scroll over the cluster to browse larger groups.",
				"The QT button at the top right of the world map toggles QT player and shared-waypoint markers. Hover it to dim the map behind them. Minimap markers and location sharing stay unchanged.",
				"Find on Map opens a player's recent shared location and highlights their dot.",
			},
		},
		{
			title = "Recent Companions",
			items = {
				"Use /qt companions or the minimap menu to open a private history of people you grouped with, with player menus for whispers, invitations, and private notes.",
				"History is shared across your characters on the same client and realm. It stores up to 100 companions for 90 days; remove entries or clear the list whenever you like.",
			},
		},
		{
			title = "Quest Updates and Player Details",
			items = {
				"Rapid updates to the same objective combine into one announcement showing the latest progress. Completed objectives still announce promptly.",
				"Signature-verified QuestTogether developers have class-colored gear markers and a developer label in tooltips. Cluster hover lists show the same class colors, QT icons, and questing-partner status as party rosters.",
			},
		},
	},
}
