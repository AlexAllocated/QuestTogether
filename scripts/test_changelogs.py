#!/usr/bin/env python3
"""Changelog synchronization contracts, using only temporary files/repos."""
import copy
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
import changelogs as c
from localization import LOCALES, digest, dumps
from check_release_notes import main as notes_main
from discord_changelog import build_messages, DEFAULT_REPOSITORY, load_notes


class ChangelogTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'changelogs').mkdir()
        (self.root / 'release_notes').mkdir()
        (self.root / 'scripts').mkdir()
        shutil.copyfile(Path(c.__file__), self.root / 'scripts/changelogs.py')
        self.notes = {'version': '1.0.0', 'welcome': 'Find questing partners.',
                      'sections': [{'title': 'Partners', 'items': ['Find friends nearby.', 'Share quest progress.']}]}
        (self.root / c.HISTORY).write_text(dumps({'schema': 1, 'releases': []}))
        (self.root / 'QuestTogether.toc').write_text('## Version: 1.0.0\nCore.lua\nReleaseNotes.lua\nLocalizedReleaseNotes.lua\n')
        self.write_source(self.notes)

    def write_source(self, notes):
        (self.root / 'release_notes.json').write_text(dumps(notes))
        for locale in LOCALES:
            translated = copy.deepcopy(notes)
            translated['welcome'] = locale + ': ' + notes['welcome']
            (self.root / 'release_notes' / (locale + '.json')).write_text(dumps({'source_sha256': digest(notes), 'notes': translated}))

    def generate(self):
        self.assertEqual(notes_main(['--root', str(self.root), '--write']), 0)

    def git(self, *args):
        return subprocess.check_output(['git', '-c', 'user.name=Offline test', '-c', 'user.email=test@example.invalid',
                                       '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null', *args], cwd=self.root, stderr=subprocess.DEVNULL)

    def test_all_files_match_same_text_as_discord(self):
        self.generate()
        c.check(self.root)
        for locale in c.TITLES:
            source = self.notes if locale == 'enUS' else json.loads((self.root / 'release_notes' / (locale + '.json')).read_text())['notes']
            path = self.root / ('CHANGELOG.md' if locale == 'enUS' else 'changelogs/' + locale + '.md')
            markdown = path.read_text()
            payloads = build_messages(source, DEFAULT_REPOSITORY, 'v1.0.0', locale)
            embeds = [e for p in payloads for e in p['embeds']]
            self.assertIn(embeds[0]['description'], markdown)
            for section in source['sections']:
                self.assertIn('### ' + section['title'], markdown)
                for item in section['items']: self.assertIn('- ' + item, markdown)

    def test_missing_or_edited_markdown_blocks_notes_and_discord(self):
        self.generate()
        path = self.root / 'changelogs/frFR.md'
        path.unlink()
        self.assertEqual(notes_main(['--root', str(self.root), '--check']), 1)
        with self.assertRaises(ValueError): load_notes(self.root)
        self.generate()
        path.write_text(path.read_text().replace('Share quest progress.', 'Unrelated manual text.'))
        with self.assertRaises(ValueError): c.check(self.root)
        self.generate()
        c.check(self.root)

    def test_history_preserves_languages_available_at_each_release(self):
        old = copy.deepcopy(self.notes); old['version'] = '0.9.0'; old['welcome'] = 'Earlier English notes.'
        (self.root / c.HISTORY).write_text(dumps({'schema': 1, 'releases': [{'enUS': old}]}))
        self.generate()
        self.assertIn('## 0.9.0', (self.root / 'CHANGELOG.md').read_text())
        self.assertNotIn('## 0.9.0', (self.root / 'changelogs/frFR.md').read_text())

    def test_version_bump_archives_published_notes_not_draft(self):
        self.generate()
        self.git('init', '-q'); self.git('add', '.'); self.git('commit', '-qm', 'Published baseline'); self.git('tag', 'v1.0.0')
        draft = copy.deepcopy(self.notes); draft['welcome'] = 'New release welcome.'
        self.write_source(draft); self.generate()
        toc = self.root / 'QuestTogether.toc'; toc.write_text(toc.read_text().replace('1.0.0', '1.0.1'))
        self.assertEqual(notes_main(['--root', str(self.root), '--write', '--set-version', '1.0.1']), 0)
        history = json.loads((self.root / c.HISTORY).read_text())['releases']
        self.assertEqual(history[0]['enUS'], self.notes)
        text = (self.root / 'CHANGELOG.md').read_text()
        self.assertEqual(text.count('## 1.0.0'), 1)
        self.assertIn('## 1.0.1\n\nNew release welcome.', text)
        self.assertLess(text.index('## 1.0.1'), text.index('## 1.0.0'))
        c.check(self.root)

    def test_release_preflight_accepts_generated_changelogs_and_rejects_drift(self):
        shutil.copyfile(Path(c.__file__).with_name('bump_version.sh'), self.root / 'scripts/bump_version.sh')
        shutil.copyfile(Path(c.__file__).with_name('check_release_notes.py'), self.root / 'scripts/check_release_notes.py')
        shutil.copyfile(Path(c.__file__).with_name('localization.py'), self.root / 'scripts/localization.py')
        self.generate()
        self.git('init', '-q'); self.git('add', '.'); self.git('commit', '-qm', 'Published baseline'); self.git('tag', 'v1.0.0')
        draft = copy.deepcopy(self.notes); draft['welcome'] = 'New release welcome.'
        self.write_source(draft); self.generate()
        result = subprocess.run(['bash', 'scripts/bump_version.sh', 'patch', '--check'], cwd=self.root, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        path = self.root / 'changelogs/deDE.md'; path.write_text('Wrong changelog content.')
        result = subprocess.run(['bash', 'scripts/bump_version.sh', 'patch', '--check'], cwd=self.root, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('stale', result.stderr)

    def test_invalid_translation_cannot_partially_update_changelogs(self):
        self.generate()
        original = (self.root / 'CHANGELOG.md').read_bytes()
        path = self.root / 'release_notes/zhTW.json'
        data = json.loads(path.read_text()); data['source_sha256'] = 'wrong'; path.write_text(dumps(data))
        self.assertEqual(notes_main(['--root', str(self.root), '--write']), 1)
        self.assertEqual((self.root / 'CHANGELOG.md').read_bytes(), original)

    def test_duplicate_history_is_rejected(self):
        (self.root / c.HISTORY).write_text(dumps({'schema': 1, 'releases': [{'enUS': self.notes}, {'enUS': self.notes}]}))
        with self.assertRaises(ValueError): c.outputs(self.root, self.notes)


if __name__ == '__main__': unittest.main()
