-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "10.1.5",
	welcome = "A new way to suggest your party’s next quest, a familiar focus click, and smoother following after turn-ins.",
	sections = {
		{
			title = "Suggest the next quest",
			items = {
				"While following someone’s quest focus, select another quest and choose Suggest focus. Your follow stays active, and they can approve the change if the quest is in their log. Both players need this update.",
				"Manual following still offers Cancel and Change focus. Automatic party-leader following offers Cancel or Suggest focus while keeping local overrides blocked.",
				"Allow quest focus suggestions is in Groups & Sharing. Quest Log Only and Little Sidekick turn incoming suggestions off; existing opt-outs from QT share-request prompts are also respected when upgrading.",
			},
		},
		{
			title = "A familiar focus sound",
			items = {
				"The default automatic focus-change sound now uses WoW’s own quest-selection click. Its loudness follows WoW’s Sound Effects volume; setting either QT volume slider to zero still mutes it. Other selected sounds are unchanged.",
			},
		},
		{
			title = "Keep following after turn-ins",
			items = {
				"Fixed stale focused quests being shared after leaving the log and outdated break-follow prompts during turn-in transitions. Following stays active, ready for the next shared quest.",
			},
		},
	},
}
