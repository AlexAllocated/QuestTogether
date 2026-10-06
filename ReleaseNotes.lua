-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "6.4.1",
	welcome = "Thanks for using QuestTogether! This update adds more control over quest progress snapshots, player location displays, and window accessibility. Settings are easier to tune, and Discord is still the best place for feedback and support.",
	sections = {
		{
			title = "Party Quest Log updates",
			items = {
				"Player headers now show how fresh each quest snapshot is. Open a player header menu to refresh just that player without refreshing everyone.",
				"Filters now includes an optional auto-refresh setting. When enabled, the Party Quest Log refreshes about every 30 seconds while the real window is open.",
				"Refreshing keeps your search, expanded quests, horizontal position, and visible quest position when possible while new snapshot data arrives.",
				"Quest focus labels now distinguish waiting, expired, unsupported, unavailable, and unshared states, and the menu warns when following would create a loop.",
			},
		},
		{
			title = "Accessibility and window layout",
			items = {
				"Settings now includes Accessibility options for window scale from 80% to 150% and reduced motion for instant scrolling and objective expansion.",
				"Window scale enlarges text and controls together, but may be capped when needed to keep the full window on screen.",
				"The Party Quest Log and welcome window now save their size and screen-relative position per profile, and QuestTogether windows are refit after display size or UI scale changes.",
				"Use Reset window layout in Accessibility, or /qt resetlayout, to clear saved QuestTogether window layouts and recenter them.",
			},
		},
		{
			title = "Player location controls",
			items = {
				"World map and minimap display can now be toggled separately from location sharing, so you can hide local pins without changing what you share.",
				"The player location filter now offers all QuestTogether players, questing partners, or party only.",
				"Always show my party is on by default, so party members still appear when using the questing-partner filter if their location permissions allow it.",
			},
		},
		{
			title = "Fixes and polish",
			items = {
				"Experimental layer detection keeps the same settings and UI, with smoother request handling when local evidence changes or nearby candidates are cooling down.",
				"QuestTogether dialogs now handle Escape through their normal close actions, and the Party Quest Log can be assigned a key in the native Key Bindings menu with no default key set.",
				"Percent signs in translated release notes are handled as normal text.",
			},
		},
	},
}
