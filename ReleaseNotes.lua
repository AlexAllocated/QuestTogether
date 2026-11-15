-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "9.3.0",
	welcome = "Controller support is now in the stable release! No beta download is needed, and the latest focus shortcuts, rings and VIP fixes are included.",
	sections = {
		{
			title = "Get started with a controller",
			items = {
				"On WoW Forever 1.60.1 builds 70888 and 70938, enable WoW's Gamepad UI and leave Enable native gamepad navigation checked under QT's General settings. It is on by default. Other clients keep their existing mouse and keyboard controls.",
			},
		},
		{
			title = "Open and navigate QuestTogether",
			items = {
				"With the default controller layout, QT adds a quest-book PQL macro at LT + RT + D-pad Up on normal action page 1 if the slot is empty. Move or remove its button using WoW's action-bar editor. QT leaves occupied slots alone and won't replace the button while the macro exists; deleting the macro lets QT recreate it and place it in the empty default slot.",
				"In Party Quest Log, use the D-pad to move between quests and their controls, Select to activate, and Back to close. Selected quests scroll into view as you browse.",
				"Assign Open QuestTogether menu in WoW Key Bindings for contextual actions and Pending Requests; it has no default key. Navigate QT's native-style menus, dropdowns and confirmations with the controller. Incoming requests wait for you to open them, and confirmations start on Cancel or Decline.",
				"Patch notes shown after an update take controller focus. Use the right stick to scroll, the D-pad to select controls, and Back to close. The scrollbar follows the text. Text entry and HUD placement keep their existing controls.",
			},
		},
		{
			title = "Browse the tracker and world map",
			items = {
				"Browsing Blizzard's Objective Tracker with the controller now counts as hovering for Party Objective Tracker, without changing your quest focus or whom you follow.",
				"Move the world-map crosshair over QT players or clusters to highlight them. A still performs WoW's normal map action; QT menus use your assigned menu binding, and some native map controls can take priority over it. Panning, zooming and waypoints keep their normal behavior.",
				"QT's world-map party markers preserve verified VIP stars and developer artwork. Turning off QT map overlays restores Blizzard's party markers. The minimap is unchanged.",
			},
		},
	},
}
