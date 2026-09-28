-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "5.11.0",
	welcome = "QuestTogether now adds player locations, player plate logos, focused quest comparisons, and easier Discord feedback and support. Settings let you choose what you share and what you see while quest progress stays coordinated with other QuestTogether users.",
	sections = {
		{
			title = "Find QuestTogether players nearby",
			items = {
				"Show the scroll logo beside friendly QuestTogether players when WoW's friendly nameplates are on. Player Plates are enabled by default, with a padded Left position; choose Left, Right, Top, or Prefix without changing health-bar colors.",
				"Class-colored player dots can appear on the world map and minimap for players sharing their location. Hover a dot for name, faction, race, class, and level; click it for the QuestTogether player menu.",
				"Player Locations has separate sharing and viewing switches for the world map and minimap, and all four start enabled. Presence for player plate logos can continue even when both location sharing switches are off.",
				"Locations refresh periodically and disappear when they expire. Both players need the updated addon; a dot does not guarantee that you share the same phase or layer.",
			},
		},
		{
			title = "Compare one player or the whole party",
			items = {
				"The player menu Compare Quests action now compares only you and the selected player, including reachable nonparty QuestTogether peers. Whole-party comparison stays available from the minimap menu, quest-name menus, and /qt compare.",
				"Quest sharing and share requests remain party-only. Targeted comparisons explain when a party is needed for sharing and when the selected player needs QuestTogether to respond.",
				"If a share request is already waiting on another player, the comparison now shows who it is waiting for after you switch targets.",
			},
		},
		{
			title = "Feedback and support",
			items = {
				"The welcome window and main settings page now include Discord — Feedback & Support. It opens a copyable invite when available, or prints the invite in chat if the link window cannot open.",
			},
		},
		{
			title = "Fixes and polish",
			items = {
				"Ignored players are now filtered more completely. New logs, bubbles, dots, comparisons, and share work are suppressed, while existing bubbles and locations are cleared when the ignore list changes.",
				"Fixed false quest plates caused by unavailable tooltip boundaries matching another quest's objective text.",
				"Turning off map or minimap sharing now retries the update after temporary communication failures. Turning off both sharing options also removes location details from other addon updates.",
				"Player logos clear correctly when a player's presence expires just before they leave. Whisper from map dots opens your chat window, and changing the log destination from Settings is unavailable during restrictions.",
			},
		},
	},
}
