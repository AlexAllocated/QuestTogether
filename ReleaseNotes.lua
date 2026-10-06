-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "6.3.1",
	welcome = "Refined QT windows and quicker access to party quests.",
	sections = {
		{
			title = "Party Quest Log",
			items = {
				"Take a closer look at the Party Quest Log introduced in 6.3: compare up to five players in class-colored columns, see who has each quest, and spot missing quests or a party ready to turn in. Search and combine ownership, progress, and action filters; Share and Request Share are available where supported.",
				"Each player’s header shows their focused quest. Click a teammate’s name to follow their quest focus; following is opt-in and leaves your navigation alone when you lack their quest. Use Refresh for a fresh snapshot of remote progress. Screenshots show fictional preview data.",
				"Quests you own now have a small book button that opens their details in Blizzard’s Quest Log. Clicking the row still expands objectives.",
				"A crown marks the party leader and updates when leadership changes. Your own column stays first.",
			},
			illustration = "party-quest-log",
		},
		{
			title = "Expand everyone’s objectives",
			items = {
				"Click a quest to expand each member’s objective counts, progress bars, and completed steps. Keep several quests expanded at once. This release makes these sections more compact, with matching class-colored headings and bodies; a typical five-player quest with two objectives each fits at the default window size. Longer quests may still need scrolling.",
			},
			illustration = "party-quest-objectives",
		},
		{
			title = "Windows and minimap",
			items = {
				"Left-click the minimap icon to open or close the Party Quest Log; right-click opens the menu. Settings is back in the menu, and the tooltip explains the shortcuts.",
				"Party-chat reminders, share and join requests, bubble settings, and the Discord link dialog now use QT’s scroll frame and light/dark themes, with more padding and room for slider values.",
				"Window dragging preserves the cursor offset, including in the compare preview. Menus and tooltips now consistently call Blizzard’s window the Quest Log.",
			},
		},
		{
			title = "Preview commands",
			items = {
				"Use /qt preview to list the window and announcement previews. The older preview commands still work; mock actions do not invite players, share quests, or send messages.",
				"The compare preview now shows a full five-player party, including a Hunter and Rogue, with varied objectives, focused quests, and a leader crown.",
			},
		},
	},
}
