-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "10.1.1",
	welcome = "Keep questing with your controller!",
	sections = {
		{
			title = "Controller compatibility",
			items = {
				"Compatible updates to WoW Forever no longer disable QT controller support just because the build number changed. Required API and security checks remain in place.",
				"Fixed the build check that prevented new characters from receiving the PQL controller shortcut. After reloading, QT can add it to an empty LT + RT + D-pad Up slot on action page 1 when automatic installation is enabled. Existing macros and custom bindings are preserved.",
				"QT’s world-map party markers now use the same approach: compatible client builds remain supported without an exact build-number match.",
			},
		},
		{
			title = "Ready for combat",
			items = {
				"QT windows and their menus now close automatically when combat begins, keeping your view clear and returning controller input to the game.",
				"This includes the debug log and diagnostic reports, even when QuestTogether is disabled in its settings.",
			},
		},
	},
}
