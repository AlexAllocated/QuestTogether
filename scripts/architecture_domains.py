# SPDX-License-Identifier: GPL-3.0-only
"""Validation impact of audited module boundaries. Unclassified paths stay full."""
PRESENTATION = {
    "Options.lua", "PresetWindow.lua", "ReleaseNotesWindow.lua", "Hints.lua",
    "QuestCompareWindow.lua", "QuestComparePreview.lua", "QuestCompareChainPreview.lua",
    "QuestCompareFilters.lua", "QuestCompareGamepad.lua", "QuestCompareInteraction.lua",
    "QuestCompareChains.lua", "WindowLayout.lua", "WindowTheme.lua", "OwnedUI.lua",
    "MapOverlayPool.lua", "PartyWaypointPins.lua", "PlayerTooltipPresenter.lua",
    "ReleaseNotes.lua", "ReleaseNotesHistory.lua", "LocalizedReleaseNotes.lua", "Locales.lua",
}
PRESENTATION.update({
    "NameplateAccess.lua", "NameplateQuests.lua", "NameplateDecorations.lua",
    "PersonalBubbles.lua", "PersonalBubbleSettings.lua", "AnnouncementBubbles.lua",
    "Nameplates.lua", "ChatLog.lua", "ChatActions.lua", "AnnouncementPresentation.lua",
    "WaypointActions.lua", "Commands.lua", "ClientDiagnostics.lua", "QuestComparePresenter.lua",
})
# Changes at these boundaries can affect traffic or shared lifetimes. Keep the
# large population simulations, order checks and tooling coverage for them.
SHARED_RUNTIME = {
    "Core.lua", "Lifecycle.lua", "NativeAccess.lua", "NativeQuestValues.lua",
    "NativeChat.lua", "NativeUnits.lua", "NativeQuests.lua", "NativeMap.lua", "NativeUI.lua",
    "SettingsCatalog.lua", "Settings.lua", "SettingsEffects.lua", "FeatureOptions.lua",
    "HotPathState.lua", "HotPathRuntime.lua", "QuestTracking.lua", "AnnouncementPolicy.lua",
}
