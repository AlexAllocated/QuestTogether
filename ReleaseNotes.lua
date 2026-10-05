-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "6.0.2",
	welcome = "Find parties on the map, see who is questing together, and request to join through any party member. Player tooltips now put party details front and center.",
	sections = {
		{
			title = "See who is questing together",
			items = {
				"Grouped players now have a small two-person badge on their map and minimap dots. Hover a party member to give their companions a white outline, dim unrelated dots, and show a crown on the leader. Gold Looking for Questing Partners glows remain visible.",
				"Player tooltips list party members with class-colored dots and names, with the crowned leader first. Parties of up to five list all members; larger groups show only the leader. These details also appear when hovering player names in the QuestTogether log.",
				"Your own party uses the game’s roster. Remote party details load from updated QuestTogether peers when needed, with cached results and paced requests to keep channel traffic small. Older clients retain their normal dots and basic party-size information; full remote party details require an updated peer.",
			},
		},
		{
			title = "Join requests can reach the party leader",
			items = {
				"You can request to join through a party member who cannot invite you. If their leader is running QuestTogether and available to invite, the request is redirected to the leader using the usual confirmation and automatic-approval settings.",
				"If the leader is not known to be using QuestTogether, the member can announce “[QT] PlayerName is requesting to join the party.” in party chat when party-chat announcements are enabled. Someone with invite permission must then invite you manually.",
				"The requester and forwarding member need this update for redirected requests. Existing full-party, restriction, ignore, expiry, and request-rate checks still apply.",
			},
		},
		{
			title = "Cleaner player tooltips",
			items = {
				"Party information now sits immediately below the level, race, and class line, with compact member rows and space between sections. Alliance and Horde badges are twice as large.",
				"The addon version appears last in the shorter vX.Y.Z format. When a location’s age is shown, Last update sits directly above the version.",
				"Tracked quest counts have been removed from player and minimap-button tooltips. The active quest title for players looking for questing partners is still shown.",
			},
		},
	},
}
