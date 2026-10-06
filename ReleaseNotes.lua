-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "6.4.1",
	welcome = "Experimental layer detection for nearby QT players.",
	sections = {
		{
			title = "Experimental layer detection",
			items = {
				"Enabled by default under Settings > QuestTogether > Experimental. Turn off Detect different layers to stop comparisons and hide inferred phase indicators.",
				"In Forever's open world, nearby compatible QT clients compare NPC observations and visible players. A phased icon marks a likely different layer; hover for details. Location sharing is required.",
				"Estimates can be wrong. Missing players alone are inconclusive; seeing each other or a shared player overrides the NPC estimate. Stale evidence clears automatically. Older QT clients cannot participate.",
			},
		},
		{
			title = "Release screenshots",
			items = {
				"Screenshots in release notes now upload directly to Discord so images remain visible in changelog posts.",
			},
		},
	},
}
