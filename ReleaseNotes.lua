-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "9.2.0",
	welcome = "Follow a teammate's quest focus with a command or keybinding, spot who you're following at a glance, and keep VIP stars more reliably.",
	sections = {
		{
			title = "Follow quest focus with a shortcut",
			items = {
				"Target a party member and type /qt focus, or use /qt focus <name>. Full names work, including Forever surnames and Retail realms. Short names work when they identify only one party member.",
				"Use /qt unfollow to stop. In WoW Key Bindings, look under QuestTogether for Follow target's quest focus and Stop following quest focus. Both start unassigned, and the commands also work in macros. These follow quest navigation, not your teammate's movement.",
			},
		},
		{
			title = "Clearer focus markers",
			items = {
				"Party focus markers beside the Objective Tracker now use thick, hollow rings in each player's class color. The ring fills in when you follow that player, replacing the green outline. Chain badges still show who is following you.",
			},
		},
		{
			title = "More reliable VIP stars",
			items = {
				"Fixed repeated VIP renewals displacing another player's valid status, and restored delivery of verified VIP status when nearby-player connections change. These fixes address causes of stars turning into ordinary dots while keeping the original verification and expiry rules.",
			},
		},
	},
}
