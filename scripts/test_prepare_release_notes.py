#!/usr/bin/env python3
"""Session authoring contracts, using real isolated Git history and no network."""
import copy
import hashlib
import io
import json
import os
from pathlib import Path
import sys
import unittest
from unittest import mock
import urllib.request

sys.dont_write_bytecode = True
import prepare_release_notes as P
import test_release_notes as F
from generate_localized_notes import load_context
from localization import LOCALES, dumps, read, release_note_outputs


class SessionNotesTests(unittest.TestCase):
    run_process = F.NotesTests.run_process
    git = F.NotesTests.git
    new_repo = F.NotesTests.new_repo

    def setUp(self):
        F.NotesTests.setUp(self)
        network = mock.patch.object(urllib.request, 'urlopen', side_effect=AssertionError('no paid or network requests'))
        network.start()
        self.addCleanup(network.stop)
        (self.root / 'Core.lua').write_text('-- Newly added player map markers.\n')
        self.git('add', 'Core.lua')
        self.git('commit', '-qm', 'Add map markers')
        self.draft_dir = self.directory / 'authored drafts'
        self.draft_dir.mkdir()
        self.source = F.sample_notes(item='Locate nearby players with class-colored map dots. Open /qt to configure them.')
        self.source['sections'][0]['illustration'] = 'quest-partners'
        self.source['sections'][0]['tip'] = {'label': 'Tip:', 'text': 'Use /qt pql for party quests.'}
        self.facts = copy.deepcopy(self.source)
        self.facts['welcome'] = 'Release scope: nearby player map markers.'
        self.facts['sections'][0]['title'] = 'Map markers'
        self.facts['sections'][0]['items'] = ['Nearby players: class-colored dots.', 'Settings command: /qt.']
        (self.draft_dir / 'facts.json').write_text(dumps(self.facts))
        (self.draft_dir / 'enUS.json').write_text(dumps(self.source))
        for locale in LOCALES:
            notes = copy.deepcopy(self.source)
            notes['welcome'] = locale + ': fixture prose, not a language-quality assertion.'
            # The structural contract permits different item counts. These
            # fixtures deliberately make no claim about natural-language quality.
            notes['sections'][0]['items'] = ['Class-colored dots identify nearby players.', 'Open /qt for settings.']
            (self.draft_dir / (locale + '.json')).write_text(dumps(notes))
        self.context = P.prepare_context(self.root)

    def canonical_bytes(self):
        paths = [self.root / 'release_notes.json', self.root / 'ReleaseNotes.lua',
                 *self.root.glob('release_notes/*.json'), *self.root.glob('changelogs/*.json')]
        return {str(p.relative_to(self.root)): p.read_bytes() for p in paths if p.is_file()}

    def test_complete_authored_set_installs_without_api_and_renders_with_existing_tools(self):
        before_tag = self.git('rev-parse', 'v1.2.3')
        before_head = self.git('rev-parse', 'HEAD')
        with mock.patch.dict(os.environ, {'OPENAI_API_KEY': 'must-not-be-used'}):
            outputs = P.finalize(self.root, self.draft_dir, self.context)
        self.assertEqual(len(outputs), 12)
        self.assertEqual(read(self.root / 'release_notes.json'), self.source)
        expected = hashlib.sha256(json.dumps(
            {k: v for k, v in self.source.items() if k != 'version'},
            sort_keys=True, ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()
        for locale in LOCALES:
            wrapper = read(self.root / 'release_notes' / (locale + '.json'))
            self.assertEqual(wrapper['source_sha256'], expected)
            self.assertEqual(len(wrapper['notes']['sections'][0]['items']), 2)
        rendered = release_note_outputs(self.root, self.source)
        self.assertIn(self.root / 'LocalizedReleaseNotes.lua', rendered)
        self.assertIn('Newly added player map markers', load_context(self.root, self.source))
        self.assertEqual(self.git('rev-parse', 'HEAD'), before_head)
        self.assertEqual(self.git('rev-parse', 'v1.2.3'), before_tag)
        self.assertEqual(P.toc_version((self.root / 'QuestTogether.toc').read_text()), '1.2.3')

    def test_context_has_implementation_and_glossary_paths_without_finished_note_prose(self):
        self.assertIn('Newly added player map markers', self.context['evidence'])
        self.assertNotIn(F.sample_notes()['welcome'], self.context['evidence'])
        self.assertNotIn('PREVIOUS NOTES', self.context['evidence'])
        self.assertEqual(self.context['ui_glossaries']['deDE'], 'locales/deDE.json')
        self.assertEqual(set(self.context['locales']), {'enUS', *LOCALES})

    def test_missing_or_invalid_last_locale_leaves_every_canonical_file_unchanged(self):
        path = self.draft_dir / 'zhTW.json'
        original = path.read_bytes()
        for invalid in (None, 'not JSON', dumps({**self.source, 'version': '9.9.9'})):
            with self.subTest(invalid=invalid):
                if invalid is None:
                    path.unlink()
                else:
                    path.write_text(invalid)
                before = self.canonical_bytes()
                with self.assertRaises((ValueError, OSError)):
                    P.finalize(self.root, self.draft_dir, self.context)
                self.assertEqual(self.canonical_bytes(), before)
                path.write_bytes(original)

    def test_lost_command_asset_or_fact_blocks_installation(self):
        path = self.draft_dir / 'deDE.json'
        original = read(path)
        mutations = [
            lambda n: n['sections'][0].update(items=['No settings command remains.']),
            lambda n: n['sections'][0].pop('illustration'),
            lambda n: n['sections'][0].pop('tip'),
        ]
        for mutate in mutations:
            changed = copy.deepcopy(original)
            mutate(changed)
            path.write_text(dumps(changed))
            before = self.canonical_bytes()
            with self.assertRaises(ValueError):
                P.finalize(self.root, self.draft_dir, self.context)
            self.assertEqual(self.canonical_bytes(), before)
        path.write_text(dumps(original))
        self.facts['sections'][0]['items'].append('New limit: 12345 players.')
        (self.draft_dir / 'facts.json').write_text(dumps(self.facts))
        before = self.canonical_bytes()
        with self.assertRaisesRegex(ValueError, 'numeric values'):
            P.finalize(self.root, self.draft_dir, self.context)
        self.assertEqual(self.canonical_bytes(), before)

    def test_stale_uncommitted_implementation_is_rejected_even_outside_evidence_excerpt(self):
        text = '-- start\n' + ''.join('-- line %04d original\n' % i for i in range(1000)) + '-- end\n'
        path = self.root / 'NewFeature.lua'
        path.write_text(text)
        context = P.prepare_context(self.root, include_working_tree=True)
        self.assertNotIn('line 0500 original', context['evidence'])
        path.write_text(text.replace('line 0500 original', 'line 0500 modified'))
        fresh = P.prepare_context(self.root, include_working_tree=True)
        self.assertEqual(context['evidence'], fresh['evidence'])
        self.assertNotEqual(context['implementation_sha256'], fresh['implementation_sha256'])
        before = self.canonical_bytes()
        with self.assertRaisesRegex(ValueError, 'implementation changed'):
            P.finalize(self.root, self.draft_dir, context)
        self.assertEqual(self.canonical_bytes(), before)

    def test_mixed_new_and_repeated_baseline_bullets_cannot_be_finalized(self):
        repeated = F.sample_notes()['sections'][0]['items'][0].upper()
        for path in self.draft_dir.glob('*.json'):
            notes = read(path)
            notes['sections'][0]['items'].append(repeated)
            path.write_text(dumps(notes))
        before = self.canonical_bytes()
        with self.assertRaisesRegex(ValueError, 'repeats a previous release item'):
            P.finalize(self.root, self.draft_dir, self.context)
        self.assertEqual(self.canonical_bytes(), before)

    def test_new_commit_requires_a_fresh_context_but_note_drafts_do_not(self):
        (self.root / 'release_notes.json').write_text(dumps(self.source))
        (self.root / 'CHANGELOG.md').write_text('Generated publication prose must not invalidate implementation context.\n')
        P.validate_context(self.root, self.context)
        self.git('add', 'release_notes.json')
        self.git('commit', '-qm', 'Save reviewed note draft')
        with self.assertRaisesRegex(ValueError, 'release range changed'):
            P.finalize(self.root, self.draft_dir, self.context)

    def test_prior_published_localization_correction_survives_next_release_draft(self):
        previous = F.sample_notes()
        revision = {'enUS': previous}
        for locale in LOCALES:
            revision[locale] = {**copy.deepcopy(previous), 'welcome': locale + ': corrected published welcome.'}
        path = self.root / 'changelogs/localized_revisions.json'
        path.parent.mkdir()
        path.write_text(dumps({'schema': 1, 'releases': [revision]}))
        before = path.read_bytes()
        P.finalize(self.root, self.draft_dir, self.context)
        self.assertEqual(path.read_bytes(), before)

    def test_real_cli_context_and_finalize_use_local_files_without_credentials(self):
        context_file = self.directory / 'packet.json'
        before = self.canonical_bytes()
        with mock.patch.dict(os.environ, {'OPENAI_API_KEY': 'unused'}), mock.patch('sys.stdout', new_callable=io.StringIO):
            self.assertEqual(P.main(['--root', str(self.root), 'context', '--output', str(context_file)]), 0)
            self.assertEqual(self.canonical_bytes(), before)
            self.assertEqual(P.main(['--root', str(self.root), 'finalize', '--context', str(context_file),
                                     '--draft-dir', str(self.draft_dir)]), 0)
        self.assertEqual(read(self.root / 'release_notes.json'), self.source)


if __name__ == '__main__':
    unittest.main()
