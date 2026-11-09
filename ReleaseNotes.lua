-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "9.0.0",
	welcome = "QuestTogether has a new communication system. Everyone you use QT with needs to update for your addons to exchange information.",
	sections = {
		{
			title = "Update together",
			items = {
				"This version cannot communicate with older versions of QuestTogether. Your settings, profiles, VIP credentials and quest-focus following preferences are preserved.",
			},
		},
		{
			title = "A new way to connect",
			items = {
				"QT uses channel member lists to discover players, then exchanges addon data through whispers and party channels. It no longer sends addon messages into custom chat channels.",
				"Public updates can reach you through other QT players, with their source verified before use. Your current zone and the zone you are viewing take priority. Coverage builds gradually; some players may remain unreachable.",
			},
		},
		{
			title = "Sharing and reliability",
			items = {
				"Party quest logs, objectives, focus, waypoints and private replies still travel directly. Diagnostic data is shared only with the verified developer when you allow it. Your sharing settings still apply.",
				"Background traffic is limited to leave room for party updates. Recovery and peer validation have been strengthened, but slow or unavailable delivery is still possible.",
			},
		},
		{
			title = "Party Objective Tracker",
			items = {
				"Character and bag windows, along with item tooltips, now appear in front of POT. It still docks to Blizzard's quest tooltip using your chosen placement.",
			},
		},
	},
}
