#!/usr/bin/env python3
"""Regression checks for the Forever zero-division test-fixture boundary."""
from pathlib import Path
import tempfile
import unittest

import check_live_test_numeric as numeric


class LiveNumericTests(unittest.TestCase):
    def test_original_failures_and_formatting_variants_are_rejected(self):
        for source in (
            'a:EncodeCommRecord("LOC", { mask = 0 / 0 })',
            'a:EncodeCommRecord("STATE", { records = {{ revision = 0 / 0 }} })',
            'a.db.profile.windowLayouts = { log = { width = 0 / 0 } }',
            "local nan = 0/0",
            "local nan = 0 /\n (0)",
            "local nan = 0 / ( -0.0 )",
            "local nan = 0 / ((+0e99))",
            "local nan = 0 / -- explanation\n 0",
            "local nan = 0 / 0x0",
        ):
            with self.subTest(source=source):
                self.assertTrue(numeric.violations(source))

    def test_comment_and_string_examples_are_ignored(self):
        for source in (
            '-- do not use 0 / 0\nlocal value = math.huge',
            '--[=[ local value = 0/0 ]=]\nlocal value = math.huge',
            'local example = "0 / 0"',
            "local example = 'escaped \\' 0/0'",
            'local example = [==[ 0/0 ]==]',
            'local ratio = 0 / 0.5',
            'local ratio = 0 / (0 + 1)',
            'local ratio = 0 / count',
        ):
            with self.subTest(source=source):
                self.assertEqual(numeric.violations(source), [])

    def test_line_numbers_survive_multiline_comments_and_literals(self):
        self.assertEqual(numeric.violations('--[[\n 0/0\n]]\nlocal nan = 0/0'), [4])

    def test_only_manifest_loaded_fixtures_are_checked(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'scripts').mkdir()
            (root / 'QuestTogether.toc').write_text('## Title: QT\nTests.lua\nscripts/regression_protocol_v2.lua\n')
            (root / 'Tests.lua').write_text('local value = math.huge')
            (root / 'scripts/regression_protocol_v2.lua').write_text('local value = math.huge')
            (root / 'scripts/offline_numeric_tests.lua').write_text('local nan = 0/0')
            self.assertEqual(numeric.check(root), 2)
            with self.assertRaisesRegex(ValueError, 'regression_protocol_v2.lua:1'):
                numeric.check(root, {'scripts/regression_protocol_v2.lua': 'local nan = 0/0'})

if __name__ == '__main__':
    unittest.main()
