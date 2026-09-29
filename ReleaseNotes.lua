-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "5.13.1",
	welcome = "This maintenance update improves quest-plate recovery, clears stale bubbles and player logos, and keeps settings and the debug window behaving consistently.",
	sections = {
		{
			title = "Quest plates and player indicators",
			items = {
				"Quest icons and health tints recover correctly after restricted views close. Delayed quest scans retain their settling time, and temporarily missing tooltip data keeps its retry budget.",
				"Announcement bubbles are cleaned up when a player plate disappears or is reused during combat. Protected or forbidden frames wait for safe cleanup.",
				"Map locations and player presence recover after disabling QuestTogether, changing zones, and enabling it again. Departed players no longer regain a QT logo from late location or partner-status withdrawals.",
			},
		},
		{
			title = "Settings and window fixes",
			items = {
				"The Looking for Questing Partners checkbox stays synchronized when status changes through commands, menus, or profile settings.",
				"The debug window safely finishes interrupted drag and resize gestures when restrictions lift, even after it has been hidden.",
			},
		},
		{
			title = "Reliability improvements",
			items = {
				"Strengthened tests detect forbidden frame access even when an error is caught internally.",
				"Release checks now refuse to publish while implementation changes remain uncommitted, helping ensure fixes actually reach the download.",
			},
		},
	},
}
