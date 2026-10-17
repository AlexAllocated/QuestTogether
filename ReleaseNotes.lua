-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "7.4.1",
	welcome = "Keep your party's quest progress in view with the new Quest Tracker.",
	sections = {
		{
			title = "Quest Tracker",
			items = {
				"See your party's objective counts and progress bars in a compact, class-colored window. Party members need QuestTogether to share their progress.",
				"Progress updates as party announcements arrive, independently of chat and bubble display settings. Quests without objective counters show their status, such as ready to turn in.",
				"Fixed unfinished one-step objectives incorrectly showing 1/1 progress in Forever, including Use Walk on Air. The correction applies to the Quest Tracker and Party Quest Log.",
			},
			illustration = "quest-tracker",
		},
		{
			title = "Choose what to track",
			items = {
				"Choose Hidden, Focused Quest, Hovered Quest, or Focus and Hover. The default, Focus and Hover, previews quests under the mouse in Blizzard's objective tracker, then returns to your focused quest.",
				"With no eligible quest, the window stays hidden. Change the display mode in HUD Edit Mode or Settings > Groups & Sharing > Quest Tracker.",
				"Enable Hide when not in a party in HUD Edit Mode to hide the tracker while solo. This option is off by default, and the placement preview remains available in Edit Mode.",
			},
			illustration = "quest-tracker-display",
		},
		{
			title = "Make it fit your UI",
			items = {
				"Open HUD Edit Mode and select Quest Tracker to move or resize it and adjust background opacity. Save, Revert, and Reset to Default include its display mode and layout.",
				"Snap to Blizzard's Objective Tracker is enabled by default, placing QT flush against its outer edge. Dragging QT away disables snapping and enables corner resizing. Turn snapping back on to reset its position; the width and maximum-height sliders work in either mode.",
				"The tracker shrinks to fit its content up to your configured maximum height, then scrolls. The default maximum height is now 600; existing saved sizes are preserved.",
				"Player sections fill the available width and scroll when needed. Light and dark themes are supported. Class-colored sections retain a constant 25% fill opacity, independent of the window background slider, with readable text on transparent backgrounds.",
			},
			illustration = "quest-tracker-edit-mode",
		},
	},
}
