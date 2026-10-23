-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "8.0.5",
	welcome = "Smoother minimap markers and clearer player tooltips.",
	sections = {
		{
			title = "Maps and player tooltips",
			items = {
				"Player dots on the minimap move more smoothly as you walk or turn, reducing the wobble of stationary players.",
				"Player and cluster tooltips stay open while your mouse is still, even when the markers move away. Move the mouse away to dismiss them.",
				"Individual player tooltips now group party members inside the same white outline, with a party icon and total count, used in cluster tooltips. Solo players have no party decoration.",
				"For groups larger than five, player tooltips show both the leader and the player you are hovering. Hovering the leader shows them only once.",
			},
		},
	},
}
