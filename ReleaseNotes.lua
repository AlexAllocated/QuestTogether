-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "8.2.0",
	welcome = "Follow your questing partner once, even when you're waiting for them to catch up.",
	sections = {
		{
			title = "Stay ready for the next shared quest",
			items = {
				"Follow quest focus now stays active when your friend selects a quest you don't have. Your current navigation stays in place, and Party Quest Log shows Waiting for a shared quest instead of interrupting you with a popup.",
				"QT automatically resumes syncing when your friend focuses a quest in your log, or when you pick up the quest they already have focused. You don't need to follow them again.",
				"Quest pickups and turn-ins won't cancel following while you're waiting. Your chosen player is still remembered across reloads; syncing resumes after fresh party information arrives.",
			},
			tip = {
				label = "Tip:",
				text = "Open /qt pql, open your friend's player menu, and choose Follow quest focus. You can do this before you share any quests. Use Stop following to end it.",
			},
		},
	},
}
