-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "6.2.0",
	welcome = "Smoother nearby dots, faster player details, and more reliable communication.",
	sections = {
		{
			title = "Smoother minimap movement",
			items = {
				"Nearby players can exchange positions through paced addon whispers. Smooth movement favors up to four closest eligible peers and respects sharing preferences, filters, ignores, and traffic limits.",
				"Both players need this update for nearby streams and direct hover replies. Older versions keep normal broadcasts; server delays and restrictions can still affect delivery.",
			},
		},
		{
			title = "Faster discovery and party details",
			items = {
				"Hovering a player name or dot can request fresh details directly. Requests are rate-limited, and unchanged party member lists no longer expire after two minutes.",
				"Recent locations, partner status, and known party details survive /reload for up to three minutes from their original samples. Entering a zone also requests a paced discovery refresh.",
				"Tooltips use known solo or grouped status while waiting for an exact party size. Party member rows now identify QT users with a small logo, keeping names aligned.",
			},
		},
		{
			title = "Clearer localization and presentation",
			items = {
				"Race names, ping details, quest data, and more interface text use local translations when available. Unavailable quest translations retain readable sender text; progress avoids borrowing unrelated local objective descriptions.",
				"Generic announcements now use the QT logo. Looking for Questing Partners is the first option in the minimap menu.",
			},
		},
		{
			title = "Communication and reliability",
			items = {
				"Comparisons, party rosters, join and share requests, and ping replies prefer direct whispers with compatible peers. Consolidated heartbeats and fewer unchanged location updates reduce redundant public traffic.",
				"Fixed repeated quest scans, excessive nameplate retries, dialogs that could not close during restrictions, and /qt set accepting non-toggle settings. Disabling location sharing no longer drops unrelated queued requests.",
			},
		},
	},
}
