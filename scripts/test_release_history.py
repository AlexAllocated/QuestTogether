#!/usr/bin/env python3
"""History packaging and release gates, entirely within temporary repositories."""
import copy
from contextlib import redirect_stderr
import io
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


class HistoryTests(test_changelogs.ChangelogFixture, unittest.TestCase):
    def test_manual_major_bump_cannot_hide_a_missing_published_patch(self):
        previous = self.entry('7.4.3')
        (self.root / 'changelogs/history.json').write_text(dumps({'schema': 1, 'releases': [previous]}))
        self.notes['version'] = '7.4.4'
        self.notes['welcome'] = 'Read each feature update and its patches together.'
        self.write_source(self.notes)
        toc = self.root / 'QuestTogether.toc'
        toc.write_text(toc.read_text().replace('1.0.0', '7.4.4'))
        self.dates['7.4.4'] = '2026-10-05'
        self.write_dates()
        self.generate()
        published = {'enUS': copy.deepcopy(self.notes)}
        for locale in LOCALES:
            published[locale] = json.loads((self.root / 'release_notes' / (locale + '.json')).read_text())['notes']
        self.git('init', '-q'); self.git('add', '.'); self.git('commit', '-qm', 'Publish grouped patch notes')
        self.git('tag', '-a', 'v7.4.4', '-m', 'Release 7.4.4')

        # Reproduce the manual 8.0.0 jump: current notes change, but the archive
        # still ends at 7.4.3. All Lua and Markdown are internally synchronized,
        # exactly as the previous generation-only checks allowed.
        self.notes['version'] = '8.0.0'
        self.notes['welcome'] = 'A new feature release.'
        self.write_source(self.notes)
        toc.write_text(toc.read_text().replace('7.4.4', '8.0.0'))
        self.dates['8.0.0'] = '2026-10-06'
        self.write_dates()
        with patch.object(h, 'require_complete_history'):
            self.generate()
        self.git('add', '.'); self.git('commit', '-qm', 'Manual major release without archiving the patch')
        self.git('tag', 'v8.0.0')
        before = {p: p.read_bytes() for p in self.root.rglob('*') if p.is_file() and '.git' not in p.parts}
        for mode in (['--check'], ['--check', '--release-history'],
                     ['--check', '--baseline-ref', 'v7.4.4'], ['--write']):
            with self.subTest(mode=mode), redirect_stderr(io.StringIO()) as errors:
                self.assertEqual(notes_main(['--root', str(self.root), *mode]), 1)
                self.assertIn('published releases missing from changelog history: 7.4.4', errors.getvalue())
        self.assertEqual({p: p.read_bytes() for p in before}, before)

        (self.root / 'changelogs/history.json').write_text(dumps({'schema': 1, 'releases': [published, previous]}))
        self.generate()
        self.assertEqual(notes_main(['--root', str(self.root), '--check', '--release-history']), 0)
        self.assertIn('Read each feature update and its patches together.', (self.root / h.LUA_FILE).read_text())

    def test_completeness_covers_prereleases_and_accepts_legacy_archive_entries(self):
        self.git('init', '-q')
        toc = self.root / 'QuestTogether.toc'
        notes_path = self.root / 'release_notes.json'

        def tag(version, *, structured=True, notes_version=None):
            toc.write_text('## Version: ' + version + '\nCore.lua\nReleaseNotes.lua\n')
            if structured:
                notes_path.write_text(dumps({**self.notes, 'version': notes_version or version}))
            elif notes_path.exists():
                notes_path.unlink()
            self.git('add', '.'); self.git('commit', '-qm', 'Release ' + version)
            self.git('tag', 'v' + version)

        tag('0.8.0', structured=False)
        tag('0.9.0-beta.1')
        tag('0.9.0', notes_version='0.9.1')  # Not a matching structured release.
        tag('1.1.0')  # Reachable but newer than the release being validated.
        tag('1.0.0')  # The current release is never an archived requirement.
        self.git('tag', 'vnot-a-release')
        self.git('checkout', '-qb', 'unmerged-release')
        tag('0.9.0-beta.2')
        self.git('checkout', '-q', 'v1.0.0')
        with self.assertRaisesRegex(ValueError, 'missing from changelog history: 0.9.0-beta.1'):
            h.require_complete_history(self.root, '1.0.0', set())
        legacy = self.entry('0.9.0-beta.1')
        (self.root / h.LEGACY_FILE).write_text(dumps([legacy]))
        self.write_source(self.notes)
        toc.write_text('## Version: 1.0.0\nCore.lua\nReleaseNotes.lua\nLocalizedReleaseNotes.lua\nReleaseNotesHistory.lua\nWelcome.lua\n')
        self.generate()
        self.assertEqual(notes_main(['--root', str(self.root), '--check']), 0)

    def test_completeness_rejects_shallow_history_even_when_archive_looks_complete(self):
        self.git('init', '-q'); self.git('add', '.'); self.git('commit', '-qm', 'Initial release')
        self.git('tag', 'v1.0.0')
        clone = Path(self.temp.name) / 'shallow'
        self.git('clone', '--quiet', '--depth', '1', self.root.as_uri(), str(clone))
        with self.assertRaisesRegex(ValueError, 'require a full checkout'):
            h.require_complete_history(clone, '1.0.0', set())

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

    # Changelog-only builds allow pre-localization archives. History-enabled
    # builds require backfills; the independent changelog suite keeps the old contract.
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
        self.notes['sections'][0]['tip']={'label':'Tip:','text':'Try /qt compare for party quests.'}
        self.write_source(self.notes)
        self.generate()
        self.git('init', '-q'); self.git('add', '.'); self.git('commit', '-qm', 'Baseline'); self.git('tag', 'v1.0.0')
        draft = copy.deepcopy(self.notes); draft['welcome'] = 'A new release with browsing.'
        draft['sections'][0]['tip']['text']='Try /qt hint for a new tip.'
        self.write_source(draft)
        toc = self.root / 'QuestTogether.toc'; toc.write_text(toc.read_text().replace('1.0.0', '1.0.1'))
        self.assertEqual(notes_main(['--root', str(self.root), '--write', '--set-version', '1.0.1']), 0)
        dates = json.loads((self.root / h.DATES_FILE).read_text())
        self.assertIn('1.0.1', dates)
        output = (self.root / h.LUA_FILE).read_text()
        self.assertIn('Find questing partners.', output)
        self.assertNotIn('A new release with browsing.', output)
        self.assertIn('["tip"]={["label"]="Tip:",["text"]="Try /qt compare for party quests."}',output)
        self.assertNotIn('Try /qt hint for a new tip.',output)
        with patch.object(h, 'datetime') as clock:
            self.assertEqual(notes_main(['--root', str(self.root), '--check']), 0)
            clock.now.assert_not_called()
        self.assertEqual(json.loads((self.root / h.DATES_FILE).read_text()), dates)


if __name__ == '__main__': unittest.main()
