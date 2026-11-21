-- SPDX-License-Identifier: GPL-3.0-only
-- Shared PQL behavior. Instances own session, window, provider and input state;
-- the class contains functions only and cannot fall through to live state.
local QT = _G.QuestTogether
local methods = {}
QT.PartyQuestPresentation = methods
function QT:RegisterPartyQuestPresentation(definitions)
	for name, method in pairs(definitions) do
		assert(type(method) == "function" and methods[name] == nil, "duplicate PQL method: " .. name)
		methods[name], self[name] = method, method
	end
end
local serviceMethods = {
	"NewRuntimeStateStore",
	"EnsureRuntimeStateStore",
	"GetRuntimeWorkStateStore",
	"GetDeferredWorkStateStore",
	"GetRuntimeUIWorkState",
	"CreateRuntimeUIWorkFrame",
	"StopRuntimeUIWorkWakeup",
	"EnsureRuntimeUIWorkWakeup",
	"FlushRuntimeUIWork",
	"CancelRuntimeWorkOwner",
	"RefreshPartyQuestLocalHistory",
	"BuildPartyQuestDiffRows",
	"CallOwnedUI",
	"CanMutateOwnedUI",
	"CancelOwnedUICleanup",
	"CancelQuestChainProvider",
	"ConfigureRequestPrompt",
	"ConfigureWindowController",
	"CreateOwnedScrollBar",
	"CreateOwnedUIFrame",
	"CreateOwnedWindowFrame",
	"DismissManagedWindow",
	"EvaluateQuestChainRequirements",
	"FlushOwnedUICleanup",
	"GetOwnedUICleanupState",
	"GetOwnedUIParent",
	"GetPartyQuestAbsenceState",
	"GetPartyQuestCachedShareRequirements",
	"GetPartyQuestEligibilityStatus",
	"GetPartyQuestMemberShareReadiness",
	"GetPartyQuestShareReadiness",
	"GetPartyQuestSnapshotLabel",
	"GetQuestChainGraph",
	"GetQuestChainProviderCapability",
	"GetQuestChainQuestInfo",
	"GetQuestChainStarterLocations",
	"GetScrollWindowTheme",
	"GetWindowClassColor",
	"GetWindowController",
	"HasPendingPartyQuestProgress",
	"HideOwnedUI",
	"IsPartyQuestCompareBackgroundSynced",
	"NormalizeQuestDisplayTitleText",
	"NormalizeQuestID",
	"NormalizeQuestObjectiveCounters",
	"OnQuestChainDataEvent",
	"PreparePartyQuestPresentation",
	"QueueOwnedUICleanup",
	"ReadCharacterQuestHistoryStatus",
	"RefreshManagedWindow",
	"RequestQuestChainMetadata",
	"RevalidateQuestChainProvider",
	"SafeTrimString",
	"SanitizeAnnouncementText",
	"SetQuestChainMetadataInterest",
	"StopOwnedScrollBar",
	"StopWindowInteraction",
	"UpdateOwnedScrollBar",
}
function QT:NewPartyQuestPresenter(data)
	assert(type(data) == "table" and getmetatable(data) == nil, "presenter requires owned data")
	local services = {}
	for _, name in ipairs(serviceMethods) do
		assert(type(self[name]) == "function", "missing PQL service: " .. name)
		services[name] = self[name]
	end
	-- A missing member is absent, never a lookup in the live addon instance.
	return setmetatable(data, {
		__index = function(_, name)
			return methods[name] or services[name]
		end,
	})
end
