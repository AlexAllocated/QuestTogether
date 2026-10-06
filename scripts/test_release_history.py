#!/usr/bin/env python3
"""History packaging and release gates, entirely within temporary repositories."""
import copy
import json
import shutil
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import release_history as h
from check_release_notes import check_manifest, main as notes_main
from localization import LOCALES, dumps
import test_changelogs


class HistoryTests(test_changelogs.ChangelogTests):
    def test_silent_archives_are_excluded_from_browsable_history(self):
        entry = {loc: {'version': '0.9.0', 'welcome': '', 'sections': []} for loc in ['enUS', *LOCALES]}
        self.dates['0.9.0'] = '2026-10-04'
        self.write_dates()
        (self.root / 'changelogs/history.json').write_text(dumps({'schema': 1, 'releases': [entry]}))
        self.generate()
        lua = (self.root / h.LUA_FILE).read_text().split('namespace.releaseNotesDates')[0]
        self.assertNotIn('0.9.0', lua)
        self.assertNotIn('## 0.9.0', (self.root / 'CHANGELOG.md').read_text())

    def setUp(self):
        super().setUp()
        toc = self.root / 'QuestTogether.toc'
        toc.write_text(toc.read_text() + 'ReleaseNotesHistory.lua\nWelcome.lua\n')
        shutil.copyfile(Path(h.__file__), self.root / 'scripts/release_history.py')
        self.dates = {'1.0.0': '2026-10-04'}
        self.write_dates()
        (self.root / h.LEGACY_FILE).write_text('[]\n')

    def write_dates(self):
        (self.root / h.DATES_FILE).write_text(dumps(self.dates))

    def entry(self, version):
        entry = {}
        for loc in ['enUS', *LOCALES]:
            notes = copy.deepcopy(self.notes)
            notes['version'] = version
            notes['welcome'] = loc + ': Prior release notes.'
            entry[loc] = notes
        self.dates[version] = '2026-09-26'
        self.write_dates()
        return entry

    # Parent checks intentionally allow pre-localization archives. History-enabled
    # builds now require backfills; retain the old contract in test_changelogs.
    def test_history_preserves_languages_available_at_each_release(self):
        entry = self.entry('0.9.0')
        del entry['frFR']
        (self.root / 'changelogs/history.json').write_text(dumps({'schema': 1, 'releases': [entry]}))
        self.assertEqual(notes_main(['--root', str(self.root), '--write']), 1)
        self.assertFalse((self.root / h.LUA_FILE).exists())

    def test_sorted_localized_legacy_history_is_in_lua_and_markdown(self):
        legacy = [self.entry('0.8.0-beta.1'), self.entry('0.8.0'), self.entry('0.8.0-beta.2')]
        archived = self.entry('0.9.0')
        (self.root / h.LEGACY_FILE).write_text(dumps(legacy))
        (self.root / 'changelogs/history.json').write_text(dumps({'schema': 1, 'releases': [archived]}))
        self.generate()
        output = (self.root / h.LUA_FILE).read_text()
        self.assertLess(output.index('0.9.0'), output.index('0.8.0"'))
        self.assertLess(output.index('0.8.0"'), output.index('0.8.0-beta.2'))
        self.assertLess(output.index('0.8.0-beta.2'), output.index('0.8.0-beta.1'))
        for loc in ['enUS', *LOCALES]:
            self.assertIn(loc + ': Prior release notes.', output)
            file = 'CHANGELOG.md' if loc == 'enUS' else 'changelogs/' + loc + '.md'
            self.assertIn('## 0.8.0-beta.1', (self.root / file).read_text())
        self.assertEqual(notes_main(['--root', str(self.root), '--check']), 0)
        (self.root / h.LUA_FILE).write_text('-- stale\n')
        self.assertEqual(notes_main(['--root', str(self.root), '--check']), 1)

    def test_missing_invalid_dates_and_duplicate_versions_block_generation(self):
        entry = self.entry('0.9.0')
        path = self.root / h.LEGACY_FILE
        for entries in [[entry, entry], [self.entry('1.0.0')], [self.entry('2.0.0')]]:
            path.write_text(dumps(entries))
            self.assertEqual(notes_main(['--root', str(self.root), '--write']), 1)
        path.write_text(dumps([entry]))
        for value in [None, '2026-02-30', '2026-9-26', 123]:
            dates = dict(self.dates)
            if value is None: dates.pop('0.9.0')
            else: dates['0.9.0'] = value
            (self.root / h.DATES_FILE).write_text(dumps(dates))
            self.assertEqual(notes_main(['--root', str(self.root), '--write']), 1)

    def test_manifest_checks_history_order_and_duplicates(self):
        for tail in ['ReleaseNotesHistory.lua\nReleaseNotesHistory.lua\n',
                     'Welcome.lua\nReleaseNotesHistory.lua\n']:
            with self.assertRaises(ValueError):
                check_manifest('Core.lua\nReleaseNotes.lua\nLocalizedReleaseNotes.lua\n' + tail)
        with self.assertRaises(ValueError):
            check_manifest('Core.lua\nReleaseNotesHistory.lua\nReleaseNotes.lua\nLocalizedReleaseNotes.lua\n')

    def test_version_bump_records_date_once_and_archives_baseline(self):
        self.generate()
        self.git('init', '-q'); self.git('add', '.'); self.git('commit', '-qm', 'Baseline'); self.git('tag', 'v1.0.0')
        draft = copy.deepcopy(self.notes); draft['welcome'] = 'A new release with browsing.'
        self.write_source(draft)
        toc = self.root / 'QuestTogether.toc'; toc.write_text(toc.read_text().replace('1.0.0', '1.0.1'))
        self.assertEqual(notes_main(['--root', str(self.root), '--write', '--set-version', '1.0.1']), 0)
        dates = json.loads((self.root / h.DATES_FILE).read_text())
        self.assertIn('1.0.1', dates)
        output = (self.root / h.LUA_FILE).read_text()
        self.assertIn('Find questing partners.', output)
        self.assertNotIn('A new release with browsing.', output)
        with patch.object(h, 'datetime') as clock:
            self.assertEqual(notes_main(['--root', str(self.root), '--check']), 0)
            clock.now.assert_not_called()
        self.assertEqual(json.loads((self.root / h.DATES_FILE).read_text()), dates)


if __name__ == '__main__': unittest.main()
