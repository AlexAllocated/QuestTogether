-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "6.0.0",
	welcome = "QuestTogether 6.0 prepares for Forever launch with a communication system designed to reduce background traffic as the community grows.",
	sections = {
		{
			title = "Local activity, worldwide discovery",
			items = {
				"Quest announcements and frequent player updates now use zone channels. Party announcements still reach your group across zone boundaries.",
				"Player dots remain available across the world, with slower background updates. Opening another zone on the world map temporarily subscribes to its updates.",
				"QT text chat stays on the global QuestTogether channel. Your Global or Zone Only chat setting still controls which messages you see.",
			},
		},
		{
			title = "Less background traffic",
			items = {
				"Presence, version, quest counts, partner status and location are bundled into compact updates. Crowded zones update less often to reduce traffic.",
				"Announcements are paced and take priority over background updates. Ping replies are spread out to avoid a reply burst. WoW can still delay channel delivery; this update does not guarantee instant messages.",
				"Player tooltips show the age of older locations. Diagnostics now report message counts, throttling and sender-reported announcement delays.",
			},
		},
		{
			title = "A major update during beta",
			items = {
				"We are making this larger communication change now in anticipation of Forever launch. Beta is the best time to make these foundational decisions, before more players depend on the old behavior.",
				"Version 6.0 leaves QuestTogetherAnnounce1 and no longer sends or receives on that legacy channel. It uses QuestTogether for global chat and discovery, plus zone channels for local activity.",
				"QuestTogether keeps its channels after your other chat channels, with the main chat channel before its zone channels. Your location-sharing, ignore-list and announcement preferences are preserved.",
			},
		},
		{
			title = "Compatibility with older versions",
			items = {
				"Please update together. Older versions cannot read the new bundled player updates or listen to the new zone channels, so mixed-version players may miss map dots, partner status and nearby quest announcements.",
				"Players using only the legacy channel are no longer discoverable through that channel in 6.0. Some exchanges with newer 5.x versions can still work through the shared global channel or a group, but this is partial compatibility, not the full experience.",
				"Manual /qt ping still uses the global channel. It can hear compatible older clients there, but it is a best-effort discovery tool, not a complete count of everyone using QuestTogether.",
			},
		},
	},
}
