-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "6.5.0",
	welcome = "Control quest focus directly in Party Quest Log, and keep following your party through reloads.",
	sections = {
		{
			title = "Quest focus buttons",
			items = {
				"Blizzard-style quest buttons now appear in each player’s quest column, replacing focused quest titles in the headers. Click a button in your column to change your super-tracked quest. Selected buttons show each teammate’s focus; click theirs to follow them.",
			},
		},
		{
			title = "Following that lasts",
			items = {
				"Your follow choice is saved per character across reloads and waits through temporary data gaps. Fresh party updates keep your focus matched when you own the quest. Choosing your own navigation stops following, as do a departed teammate, a disbanded party, or conversion to a raid.",
			},
		},
		{
			title = "When you are missing the quest",
			items = {
				"If the player you follow focuses a quest you do not have, following stops without changing your navigation. A themed dialog explains and opens Party Quest Log so you can request the quest and follow again. Try /qt preview focus for the dialog, or /qt preview compare to test the buttons and simulated focus changes.",
			},
		},
	},
}
