#!/usr/bin/env python3
"""Small ownership tripwires; behavioral regressions remain the primary gate."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def check(root=ROOT, source_overrides=None):
    root = Path(root)
    sources = {p.name: p.read_text() for p in root.glob("*.lua") if p.name != "Tests.lua"}
    sources.update(source_overrides or {})
    errors = []
    def only(pattern, owners, description):
        for name, text in sources.items():
            if name not in owners and re.search(pattern, text): errors.append(name + ": " + description)
    only(r"\.API\.(?:IsWorldQuest|GetTaskQuestInfoByQuestID)\s*\(", {"QuestObservations.lua"},
         "native quest classification belongs to QuestObservations")
    only(r"\b[A-Za-z_]\w*\.API\.SendAddonMessage\b", {"Transport.lua"}, "native addon sends belong to Transport")
    only(r"\b(?:PlaySoundFile|StopSound)\s*\(", {"Audio.lua"}, "native QT audio playback belongs to Audio")
    only(r"peerUpdateContext|WithPeerUpdateContext", set(), "peer observations must be explicit")
    only(r"function (?:QuestTogether|QT):(?:ConfigureWindowController|DismissManagedWindow)\(",
         {"WindowController.lua"}, "window lifecycle belongs to WindowController")
    only(r"function (?:QuestTogether|QT):(?:SetOption|SetOptions|ApplyActiveProfileState|InitializeDatabase)\(",
         {"Settings.lua"}, "settings mutations belong to Settings")
    only(r"function (?:QuestTogether|QT):(?:UpdatePlayerCommunications|InitializeRuntimeCoordinator)\(",
         {"RuntimeCoordinator.lua"}, "periodic publication belongs to RuntimeCoordinator")
    only(r"function (?:QuestTogether|QT):(?:Publish|Emit|Request|Respond|SubmitCommunication)\(",
         {"CommunicationCoordinator.lua"}, "typed submissions belong to CommunicationCoordinator")
    only(r"\b(?:global|db\.global)\.recentCompanions\b", {"RecentCompanions.lua"},
         "private companion history belongs to RecentCompanions")
    only(r"function (?:QuestTogether|QT):(?:PublishPreparedAnnouncement|ResetObjectiveAnnouncements)\(",
         {"ObjectiveAnnouncements.lua"}, "objective burst aggregation belongs to ObjectiveAnnouncements")
    only(r"function (?:QuestTogether|QT):(?:BuildCommFrames|DecodeCommFrame|EncodeCommRecord|DecodeCommRecord)\(",
         {"CommsProtocol.lua"}, "wire schemas and framing belong to CommsProtocol")
    only(r"\b(?:BulkTransfer|PingPages|EncodePingResponsePayload|SerializeWireMessage|DeserializeWireMessage|SendWireMessageToAnnouncementRoutes|RememberDirectCommPeer|ScheduleGeographicPingReply)\b",
         set(), "retired communication paths must not return")
    for name in ("CommsTransfer.lua", "Transport.lua", "CommunicationCoordinator.lua", "PingCommunication.lua", "QuestCompareCommunication.lua", "PartyQuestSync.lua", "PartyQuestProgress.lua", "DeveloperDiagnostics.lua", "DeveloperAnnouncements.lua", "VIPIdentity.lua", "MeshNetwork.lua", "MeshPublications.lua"):
        if re.search(r"\.API\.(?:Delay|NewTicker|NewTimer)\s*\(", sources.get(name, "")):
            errors.append(name + ": network progression belongs to RuntimeCoordinator")
    only(r'\bdistribution\s*=\s*"CHANNEL"', set(), "channel membership is directory-only; never publish addon payloads")
    only(r'QuestTogether2|HandleGeographicDiscovery|RecordTransportChannelRefusal', set(), "retired protocol and channel send recovery must not return")
    only(r'\.API\.(?:GetChannelRosterInfo|GetChannelDisplayInfo|SetSelectedDisplayChannel)\s*\(', {"MeshNetwork.lua"},
         "directory roster selection belongs to MeshNetwork")
    only(r'function (?:QuestTogether|QT):DispatchVerifiedMeshRecord\(', {"CommunicationCoordinator.lua"},
         "verified public observations enter through the coordinator")
    if re.search(r"API\.(?:GetQuestLogInfo|GetNumQuestLogEntries)", sources["TaskArea.lua"]):
        errors.append("TaskArea must reduce observations, not scan the log")
    if re.search(r"(?:owner|live)\.partyNavigationState\s*=", sources["QuestComparePreview.lua"]):
        errors.append("preview cannot replace live focus state")
    toc = [line.strip() for line in (root / "QuestTogether.toc").read_text().splitlines()
           if line.strip() and not line.startswith("#")]
    test_toc = [line.strip() for line in (root / "QuestTogether_Tests.toc").read_text().splitlines()
                if line.strip() and not line.startswith("#")]
    from package import validate_test_manifest, validate_test_completion, PackageError
    try:
        validate_test_manifest((root / "QuestTogether_Tests.toc").read_text(), (root / "QuestTogether.toc").read_text())
        for name in test_toc:
            validate_test_completion(name, (root / name).read_bytes())
    except PackageError as error:
        errors.append(str(error))
    if any(name == "Tests.lua" or name.startswith("scripts/") or name.endswith("/SelfTests.lua") for name in toc):
        errors.append("test fixtures must load only through the on-demand test companion")
    combined = toc + test_toc
    if test_toc[0] != "scripts/test_bootstrap.lua" or test_toc[-1] != "scripts/test_complete.lua":
        errors.append("test companion must bracket all fixtures with its namespace and completion markers")
    if len(combined) != len(set(combined)): errors.append("duplicate module across live and test manifests")
    if len(toc) != len(set(toc)): errors.append("duplicate TOC module")
    order = [("Core.lua", "Audio.lua"), ("Audio.lua", "Settings.lua"), ("Core.lua", "Settings.lua"), ("QuestProgressStyle.lua", "QuestCompareWindow.lua"),
             ("QuestProgressStyle.lua", "QuestFocusWindow.lua"), ("OwnedUI.lua", "WindowController.lua"),
             ("WindowController.lua", "WindowTheme.lua"), ("HotPathState.lua", "QuestObservations.lua"),
             ("QuestObservations.lua", "TaskArea.lua"), ("PeerState.lua", "PeerLifecycle.lua"),
             ("CommsProtocol.lua", "Transport.lua"), ("Transport.lua", "CommsTransfer.lua"),
             ("CommsTransfer.lua", "CommunicationCoordinator.lua"),
             ("CommunicationCoordinator.lua", "MeshNetwork.lua"), ("MeshNetwork.lua", "MeshPublications.lua"),
             ("CommunicationCoordinator.lua", "QuestCompareCommunication.lua"),
             ("CommunicationCoordinator.lua", "PingCommunication.lua"),
             ("scripts/network_fixture.lua", "scripts/regression_network_v2.lua"),
             ("PartyFocusController.lua", "PartyNavigation.lua"), ("MapOverlayPool.lua", "LocationPins.lua"),
             ("PlayerTooltipPresenter.lua", "MapOverlayControls.lua"),
             ("MapOverlayControls.lua", "LocationPins.lua"), ("Tests.lua", "scripts/ui_fixture.lua")]
    order.extend([("PlayerNotes.lua", "RecentCompanions.lua"),
                  ("PlayerLocations.lua", "MapLocationPresentation.lua"),
                  ("MapLocationPresentation.lua", "LocationPins.lua"),
                  ("ObjectiveAnnouncements.lua", "EventHandlers.lua")])
    for before, after in order:
        if before not in combined or after not in combined or combined.index(before) >= combined.index(after):
            errors.append(f"load {before} before {after}")
    for name in sources:
        if name not in toc: errors.append("production module is not in the live manifest: " + name)
    for name in combined:
        if not (root / name).is_file(): errors.append("missing live module: " + name)
    if errors: raise ValueError("\n".join(errors))
    return len(toc)

if __name__ == "__main__":
    print(f"Architecture ownership and load order verified across {check()} live modules")
