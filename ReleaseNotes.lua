-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "5.16.3",
	welcome = "Keep your bubble settings when leaving Edit Mode and find nearby questing companions on crowded maps.",
	sections = {
		{
			title = "Bubble settings stay saved",
			items = {
				"Closing HUD Edit Mode now preserves your QT bubble font size, display duration, and position instead of reverting them.",
				"The QT bubble panel now has its own Save Changes button and saved-state message. Settings apply automatically; Save Changes sets the point that Revert Changes returns to.",
				"After saving and making further adjustments, Revert Changes restores your last saved QT settings.",
			},
		},
		{
			title = "Nearby players get priority",
			items = {
				"When more than 128 eligible dots compete for space on the map or minimap, the closest players get priority based on distance from your character.",
				"When the 512-location cache fills, closer players are retained ahead of more distant arrivals. Map panning and zooming do not change proximity priority.",
				"These changes keep the existing dot and cache limits without sending additional communication messages.",
			},
		},
	},
}
