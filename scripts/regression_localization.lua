-- Private/addon-owned locale data only; never replaces GetLocale or other globals.
local QT = _G.QuestTogether
QT:RegisterTest("localization falls back and preserves separate Spanish locales without changing the client", function()
	local translate = QT.TranslateForLocale
	assert(translate("Settings", "xxXX") == "Settings")
	assert(translate("not in any dictionary", "deDE") == "not in any dictionary")
	assert(QT.localizations.esMX ~= QT.localizations.esES)
	assert(translate("Settings", "esMX") == QT.localizations.esMX["Settings"])
	assert(translate("Settings", "enGB") == "Settings")
	for _, locale in ipairs({ "deDE", "frFR", "esES", "esMX", "ptBR", "ruRU", "itIT", "koKR", "zhCN", "zhTW" }) do
		assert(translate("Settings", locale) ~= "Settings")
		assert(type(translate("Settings", locale)) == "string")
	end
end)
QT:RegisterTest("localization keeps quest status and sharing model values language independent", function()
	local previous = QT.localizationTestLocale
	for _, locale in ipairs({ "deDE", "frFR", "esES", "esMX", "ptBR", "ruRU", "itIT", "koKR", "zhCN", "zhTW" }) do
		QT.localizationTestLocale = locale
		assert(QT:GetQuestCompareShareableToYouLabel(true) == "Yes")
		assert(QT:GetQuestCompareShareableToYouLabel(false) == "No")
		assert(QT:GetQuestCompareRemoteStatusLabel(true) == "Complete")
		assert(QT:GetChatLogDestinationLabel("main") == QT.TranslateForLocale("Main Chat Window", locale))
		local a = setmetatable({
			GetQuestStatusLabel = function()
				return "Ready to Turn In"
			end,
		}, { __index = QT })
		assert(a:GetQuestStatusAnnouncementEventType(1) == "QUEST_READY_TO_TURN_IN")
	end
	QT.localizationTestLocale = previous
end)
QT:RegisterTest("localized patch notes preserve released version and section structure", function()
	for _, locale in ipairs({ "deDE", "frFR", "esES", "esMX", "ptBR", "ruRU", "itIT", "koKR", "zhCN", "zhTW" }) do
		local notes = QT.releaseNotesByLocale[locale]
		assert(notes.version == QT.releaseNotes.version)
		assert(notes.welcome ~= QT.releaseNotes.welcome)
		assert(#notes.sections == #QT.releaseNotes.sections)
		for i, section in ipairs(notes.sections) do
			assert(#section.items == #QT.releaseNotes.sections[i].items)
			assert(section.illustration == QT.releaseNotes.sections[i].illustration)
		end
	end
end)

QT:RegisterTest("Latin American Spanish keeps its native locale in events and patch notes", function()
	local a = setmetatable({
		localizationTestLocale = "esMX",
		releaseNotes = QT.releaseNotes,
		releaseNotesByLocale = QT.releaseNotesByLocale,
		GetAddonVersion = function()
			return QT.releaseNotes.version
		end,
	}, { __index = QT })
	assert(a:GetEventLocale() == "esMX")
	local facts = a:BuildAnnouncementFacts("QUEST_ACCEPTED")
	local packet = a:EncodeAnnouncementPayload({
		eventType = "QUEST_ACCEPTED",
		senderName = "Friend-Realm",
		questId = "12345",
		text = QT.TranslateForLocale("Quest Accepted: ", "esMX") .. "Una misión",
		eventFacts = facts,
	})
	local received = assert(a:DecodeAnnouncementPayload(packet))
	assert(a:DecodeAnnouncementFacts(received.eventFacts).locale == "esMX")
	assert(a:GetCurrentReleaseNotes() == QT.releaseNotesByLocale.esMX)
	assert(a:GetCurrentReleaseNotes() ~= QT.releaseNotesByLocale.esES)
	a.localizationTestLocale = "enUS"
	function a:GetLocalizedQuestTitle()
		return nil
	end
	assert(a:LocalizeAnnouncementEvent(received) == "Quest Accepted: Una misión")
	function a:GetLocalizedQuestTitle()
		return "A quest"
	end
	assert(a:LocalizeAnnouncementEvent(received) == "Quest Accepted: A quest")
end)
