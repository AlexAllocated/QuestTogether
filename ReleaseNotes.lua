-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "5.11.0",
	welcome = "Find people to quest with using the new Looking for Questing Partners status. This update also improves minimap tooltip visibility and separates Retail War Mode and realm behavior from Forever.",
	sections = {
		{
			title = "Looking for Questing Partners",
			items = {
				"Let other QuestTogether users know you want company. Your status appears in your player menu and on map-dot tooltips; it does not enable location sharing or send invitations.",
				"Toggle the status from the minimap menu, Settings > Miscellaneous, or /qt lfg. Use /qt lfg on, off, or status to set or check it. It starts off and is saved per profile.",
				"Partner status expires when updates stop. Ignored players are excluded, and disabling QuestTogether pauses your advertisement.",
			},
		},
		{
			title = "Retail and Forever",
			items = {
				"Forever no longer shows War Mode in player-dot tooltips, quest location details, or ping output. Forever pings also omit realm labels while preserving complete player names.",
				"Nearby quest updates on Forever no longer require Retail War Mode information. Map dots remain visible across phases so you can find people to group with.",
				"Retail uses the active War Mode state when available. Unknown or unsupported War Mode is no longer reported as Off.",
			},
		},
		{
			title = "More stable player dots",
			items = {
				"Briefly missing coordinates no longer remove your dot immediately. Last reported positions remain for up to two minutes, and older reports show their age in the tooltip. Sharing opt-outs still withdraw immediately when communication is available.",
				"Movement broadcasts are limited to once every ten seconds, reducing location traffic. Stationary heartbeats remain every twenty seconds so older clients stay compatible.",
				"The location cache now retains up to 512 players. Each map still draws at most 128 visible dots, and players outside the displayed map no longer use up that drawing limit.",
			},
		},
		{
			title = "Reliable player logos",
			items = {
				"Fix missing logos on friendly player nameplates in current Forever and Retail clients by reading the current friendly-player visibility setting.",
				"Left-positioned logos move outward to make room for visible buffs, then return to their usual position when the buffs disappear.",
				"All supported QuestTogether messages now identify their sender. A bounded cache remembers players for the current UI session, so missed heartbeats no longer remove their logos. Explicit departures and ignored players are still cleared; no extra messages are sent.",
			},
		},
		{
			title = "Minimap polish",
			items = {
				"The QuestTogether minimap tooltip now uses an independent tooltip layer so it can appear over action bar UI. It hides when the button becomes unavailable or restrictions begin.",
			},
		},
	},
}
