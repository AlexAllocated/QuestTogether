-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "6.5.10",
	welcome = "Smoother Party Quest Log updates, more reliable requests and map refreshes, and fixes for profiles and progress bubbles.",
	sections = {
		{
			title = "Party Quest Log",
			items = {
				"With automatic refresh enabled, unchanged quest lists use less addon traffic. Manual Refresh still requests a full update.",
				"Quest lists recover correctly after objective changes or ignoring and unignoring a player, instead of keeping stale progress or getting stuck loading.",
			},
		},
		{
			title = "Windows and profiles",
			items = {
				"Switching, copying, or resetting a profile restores its saved window layouts or the defaults. Changing display size still keeps windows on-screen without discarding your preferred size and position.",
				"Closing a party-join or quest-share confirmation now correctly shows the next waiting request.",
				"Opening settings during Blizzard Edit Mode no longer prevents Revert from restoring your personal progress bubble's original layout.",
				"Open support windows continue adapting to theme and display changes while QuestTogether is disabled.",
			},
		},
		{
			title = "Tracking and communication",
			items = {
				"Expired or no-longer-needed party-join and quest-share requests are cancelled before they are sent.",
				"Bonus objective and world quest completions keep their correct announcement type even when the quest disappears from the log before the completion event arrives.",
				"Manual location refreshes now use public replies from older QuestTogether versions to update normal map dots, while preserving newer positions and location-sharing choices.",
			},
		},
	},
}
