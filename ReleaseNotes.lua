-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "6.2.3",
	welcome = "A new Party Quest Log, shared destinations, and optional quest following make it easier to quest together.",
	sections = {
		{
			title = "Party Quest Log",
			items = {
				"Party Quest Compare is now Party Quest Log. Expand several quests at once to see each member's objectives and progress, with an overall party readiness summary.",
				"Search quests and combine ownership, progress, and sharing filters. Refresh updates remote snapshots; older clients can still compare quest lists but cannot provide objective details.",
				"Resize the parchment window and scroll smoothly. Class-colored columns, clickable padded player headers, and rounded objective panels make progress easier to read.",
			},
		},
		{
			title = "Party focus and shared waypoints",
			items = {
				"See each member's active quest beneath their name. Choose Follow quest focus from their header or QT menu to follow quests you own. Missing or cleared quests preserve your navigation; manual navigation, leaving the party, or reloading ends following.",
				"Other members' Blizzard waypoints appear as class-colored world-map and nearby minimap pins. Overlapping pins list every owner; Navigate here uses TomTom or native navigation. Receiving a pin never redirects you, and pins do not imply a shared phase.",
				"Share my focused quest, Share my waypoint, and Show party waypoints default on in Groups & Sharing, independently of public location sharing and partner status. Following is opt-in. These features require updated peers in parties of up to five, including dungeons; raids are excluded.",
			},
		},
		{
			title = "Window and menu polish",
			items = {
				"Patch notes now share the dark parchment theme, with optional Light mode. Drag or resize the window, browse cleaner history rows, and use arrows to move between releases or jump to either end. Join our Discord and Settings are in the footer.",
				"Player tooltips fit their content more closely. The minimap menu now separates questing tools from patch notes, log placement, and icon visibility. Settings and Send QT chat message are removed from that menu; settings remain available through /qt options.",
			},
		},
	},
}
