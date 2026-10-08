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
    only(r"peerUpdateContext|WithPeerUpdateContext", set(), "peer observations must be explicit")
    only(r"function (?:QuestTogether|QT):(?:ConfigureWindowController|DismissManagedWindow)\(",
         {"WindowController.lua"}, "window lifecycle belongs to WindowController")
    only(r"function (?:QuestTogether|QT):(?:SetOption|SetOptions|ApplyActiveProfileState|InitializeDatabase)\(",
         {"Settings.lua"}, "settings mutations belong to Settings")
    only(r"function (?:QuestTogether|QT):(?:UpdatePlayerCommunications|InitializeRuntimeCoordinator)\(",
         {"RuntimeCoordinator.lua"}, "periodic publication belongs to RuntimeCoordinator")
    if re.search(r"API\.(?:GetQuestLogInfo|GetNumQuestLogEntries)", sources["TaskArea.lua"]):
        errors.append("TaskArea must reduce observations, not scan the log")
    if re.search(r"(?:owner|live)\.partyNavigationState\s*=", sources["QuestComparePreview.lua"]):
        errors.append("preview cannot replace live focus state")
    toc = [line.strip() for line in (root / "QuestTogether.toc").read_text().splitlines()
           if line.strip() and not line.startswith("#")]
    if len(toc) != len(set(toc)): errors.append("duplicate TOC module")
    order = [("Core.lua", "Settings.lua"), ("OwnedUI.lua", "WindowController.lua"),
             ("WindowController.lua", "WindowTheme.lua"), ("HotPathState.lua", "QuestObservations.lua"),
             ("QuestObservations.lua", "TaskArea.lua"), ("PeerState.lua", "PeerLifecycle.lua"),
             ("Transport.lua", "BulkTransfer.lua"), ("BulkTransfer.lua", "PingPages.lua"),
             ("PartyFocusController.lua", "PartyNavigation.lua"), ("MapOverlayPool.lua", "LocationPins.lua"),
             ("PlayerTooltipPresenter.lua", "LocationPins.lua"), ("Tests.lua", "scripts/ui_fixture.lua")]
    for before, after in order:
        if before not in toc or after not in toc or toc.index(before) >= toc.index(after):
            errors.append(f"load {before} before {after}")
    for name in sources:
        if name not in toc: errors.append("production module is not in the live manifest: " + name)
    for name in toc:
        if not (root / name).is_file(): errors.append("missing live module: " + name)
    if errors: raise ValueError("\n".join(errors))
    return len(toc)

if __name__ == "__main__":
    print(f"Architecture ownership and load order verified across {check()} live modules")
