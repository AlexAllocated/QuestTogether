-- SPDX-License-Identifier: GPL-3.0-only
-- Addon identity and composition. Domain services own behavior and state.
local addonName, addonTable = ...
local LibChev = assert(addonTable and addonTable.LibChev, "libchev must load before Core.lua")

-- Reuse an existing global table if it already exists (for safety), otherwise use the loader table.
local QuestTogether = _G.QuestTogether or addonTable or {}
_G.QuestTogether = QuestTogether
QuestTogether.LibChev = LibChev
QuestTogether.Translate = addonTable.Translate
QuestTogether.TranslateForLocale = addonTable.TranslateForLocale
local L = QuestTogether.Translate

QuestTogether.addonName = addonName or "QuestTogether"
QuestTogether.commPrefix = "QuestTogether3"
QuestTogether.announcementChannelName = "QuestTogether"
QuestTogether.retiredAnnouncementChannelName = "QuestTogetherAnnounce1"
QuestTogether.questLogWindowName = "QuestTogether"
QuestTogether.CHAT_BUBBLE_SIZE_MIN = 80
QuestTogether.CHAT_BUBBLE_SIZE_MAX = 160
QuestTogether.CHAT_BUBBLE_SIZE_STEP = 5
QuestTogether.CHAT_BUBBLE_DURATION_MIN = 1
QuestTogether.CHAT_BUBBLE_DURATION_MAX = 8
QuestTogether.CHAT_BUBBLE_DURATION_STEP = 0.5
QuestTogether.ANNOUNCEMENT_NEARBY_RADIUS = 5
QuestTogether.NEARBY_RANGE_MIN = 5
QuestTogether.NEARBY_RANGE_MAX = 100
QuestTogether.PLAYER_PARTNER_ICON_TEXTURE = "Interface\\AddOns\\QuestTogether\\Media\\QuestTogetherPartnerIcon"
QuestTogether.PLAYER_DEVELOPER_ICON_TEXTURE = "Interface\\AddOns\\QuestTogether\\Media\\QuestTogetherDeveloperIcon"
QuestTogether.PLAYER_VIP_ICON_TEXTURE = "Interface\\AddOns\\QuestTogether\\Media\\QuestTogetherVIPIcon"
QuestTogether.PLAYER_VIP_PARTNER_ICON_TEXTURE = "Interface\\AddOns\\QuestTogether\\Media\\QuestTogetherVIPPartnerIcon"
QuestTogether.PLAYER_DEVELOPER_PARTNER_ICON_TEXTURE =
	"Interface\\AddOns\\QuestTogether\\Media\\QuestTogetherDeveloperPartnerIcon"

-- Runtime state flags.
QuestTogether.isInitialized = QuestTogether.isInitialized or false
QuestTogether.hasLoggedIn = QuestTogether.hasLoggedIn or false
QuestTogether.isEnabled = QuestTogether.isEnabled or false
QuestTogether.activeProfileKey = QuestTogether.activeProfileKey or nil
QuestTogether.activeCharacterKey = QuestTogether.activeCharacterKey or nil
QuestTogether.pendingPingRequests = QuestTogether.pendingPingRequests or {}
QuestTogether.pendingQuestCompareRequests = QuestTogether.pendingQuestCompareRequests or {}
QuestTogether.debugLogLines = QuestTogether.debugLogLines or {}
QuestTogether.debugLogTextLengthSum = QuestTogether.debugLogTextLengthSum or 0
QuestTogether.debugLogStoreNormalized = QuestTogether.debugLogStoreNormalized or false
QuestTogether.isRunningTests = QuestTogether.isRunningTests or false
QuestTogether.DEBUG_LOG_MAX_LINES = 1000
QuestTogether.DEBUG_LOG_MAX_CHARS = 200000
QuestTogether.DEBUG_DEFAULT_CATEGORY = "DEBUG"
QuestTogether.DEBUG_ALL_CATEGORIES = "ALL"

-- Work queues / state tables used by event handlers.
QuestTogether.onQuestLogUpdate = QuestTogether.onQuestLogUpdate or {}
QuestTogether.questsCompleted = QuestTogether.questsCompleted or {}
QuestTogether.pendingQuestRemovals = QuestTogether.pendingQuestRemovals or {}

QuestTogether.API = {}
QuestTogether.NativeAdapters = {}
function QuestTogether:RegisterNativeAPI(domain, adapters)
	assert(not self.NativeAdapters[domain], "duplicate native domain: " .. domain)
	self.NativeAdapters[domain] = adapters
	for name, adapter in pairs(adapters) do
		assert(self.API[name] == nil, "duplicate native adapter: " .. name)
		self.API[name] = adapter
	end
end
