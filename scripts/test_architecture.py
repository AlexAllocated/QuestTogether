# SPDX-License-Identifier: GPL-3.0-only
import unittest
from check_architecture import check

class ArchitectureTests(unittest.TestCase):
    def test_current_composition(self):
        self.assertGreater(check(), 0)

    def test_rejects_client_gate(self):
        with self.assertRaisesRegex(ValueError, "diagnostics only"):
            check(source_overrides={"GamepadIntegration.lua": "local version = GetBuildInfo()"})
        with self.assertRaisesRegex(ValueError, "must not gate"):
            check(source_overrides={"GamepadIntegration.lua": 'if clientVersion == "1.60.1" then return true end'})

    def test_rejects_legacy_state_and_constructors(self):
        for source in ["self.nameplateQuestTextCache = {}", "function QT:NewRuntimeStateStore() end"]:
            with self.assertRaises(ValueError):
                check(source_overrides={"Nameplates.lua": source})

    def test_rejects_duplicate_presence_owner_and_preview_scheduler(self):
        with self.assertRaisesRegex(ValueError, "player presence"):
            check(source_overrides={"PlayerPlates.lua": "function QT:NewPlayerPresenceState() end"})
        with self.assertRaisesRegex(ValueError, "shared work scheduler"):
            check(source_overrides={"QuestCompareChainPreview.lua": "self.API.Delay(0, callback)"})

if __name__ == "__main__": unittest.main()
