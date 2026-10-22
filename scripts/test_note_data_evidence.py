#!/usr/bin/env python3
"""Note-only releases expose neutral evidence, never finalized multilingual prose."""
import copy
import hashlib
import json
import sys
import unittest
from unittest import mock

sys.dont_write_bytecode = True
import author_release_notes as A
import generate_release_notes as G
import prepare_release_notes as P
import test_release_notes as F
from localization import digest, dumps, read


class NoteDataEvidenceTests(unittest.TestCase):
    run_process = F.NotesTests.run_process
    git = F.NotesTests.git
    new_repo = F.NotesTests.new_repo

    def setUp(self):
        F.NotesTests.setUp(self)
        self.current = self.root / 'release_notes/deDE.json'
        self.current.parent.mkdir()
        notes = F.sample_notes()
        notes['welcome'] = 'GERMAN_PUBLICATION_SENTINEL: previously reviewed wording.'
        self.current.write_text(dumps({'source_sha256': digest(F.sample_notes()), 'notes': notes}), encoding='utf-8')
        self.history = self.root / 'changelogs/history.json'
        self.history.parent.mkdir()
        self.history.write_text(dumps({'schema': 1, 'releases': [self.entry('1.2.2')]}), encoding='utf-8')
        self.git('add', '.')
        self.git('commit', '-qm', 'Fixture canonical release-note data')
        self.git('tag', '-f', '-a', 'v1.2.3', '-m', 'Fixture release with canonical notes')

    def entry(self, version):
        source = F.sample_notes(version)
        source['welcome'] = 'ENGLISH_PUBLICATION_SENTINEL: approved archived wording.'
        translated = copy.deepcopy(source)
        translated['welcome'] = 'GERMAN_PUBLICATION_SENTINEL: archived localized wording.'
        return {'enUS': source, 'deDE': translated}

    def change_current(self, suffix='Corrected localized wording.'):
        data = read(self.current)
        data['notes']['welcome'] = 'GERMAN_PUBLICATION_SENTINEL: ' + suffix
        self.current.write_text(dumps(data), encoding='utf-8')

    def records(self, text):
        return json.loads(text.split('these changes do not establish gameplay changes):\n', 1)[1])

    def metadata(self, working=True):
        return G.note_data_evidence(self.root, 'v1.2.3', 'HEAD', working)

    def test_notes_only_archive_restore_and_untracked_legacy_are_useful_prose_free_evidence(self):
        self.change_current()
        history = read(self.history)
        history['releases'][0]['deDE']['welcome'] = 'GERMAN_PUBLICATION_SENTINEL: corrected archive wording.'
        history['releases'].append(self.entry('1.2.1'))
        self.history.write_text(dumps(history), encoding='utf-8')
        legacy = self.root / 'changelogs/legacy_notes.json'
        legacy.write_text(dumps([self.entry('1.0.0')]), encoding='utf-8')
        before = {path: path.read_bytes() for path in (self.current, self.history, legacy)}
        context = P.prepare_context(self.root, include_working_tree=True)
        evidence = A.full_evidence(self.root, context)
        for text in (context['evidence'], evidence):
            self.assertIn('NOTE DATA CHANGE METADATA', text)
            self.assertNotIn('PUBLICATION_SENTINEL', text)
            self.assertNotIn(F.sample_notes()['welcome'], text)
            self.assertNotIn('BEGIN UNTRUSTED SOURCE', text)
        records = {entry['path']: entry for entry in self.records(evidence)}
        current = records['release_notes/deDE.json']
        self.assertEqual(current['changed_locales'], ['deDE'])
        self.assertEqual(current['changed_versions'], ['1.2.3'])
        self.assertFalse(current['english_changed'])
        self.assertEqual(current['after_sha256'], hashlib.sha256(self.current.read_bytes()).hexdigest())
        self.assertEqual(records['changelogs/history.json']['added_versions'], ['1.2.1'])
        self.assertTrue(records['changelogs/history.json']['english_changed'])
        self.assertEqual(records['changelogs/history.json']['changed_locale_version_count'], 3)
        self.assertIsNone(records['changelogs/legacy_notes.json']['before_sha256'])
        P.validate_context(self.root, context)
        self.assertEqual({path: path.read_bytes() for path in before}, before)
        with mock.patch.object(A, 'MAX_EVIDENCE', len(evidence) - 1):
            with self.assertRaisesRegex(ValueError, 'exceeds'):
                A.full_evidence(self.root, context)

    def test_same_count_text_edit_invalidates_committed_context_and_changes_full_hash(self):
        self.change_current()
        self.git('add', 'release_notes/deDE.json')
        self.git('commit', '-qm', 'Revise current localized notes')
        context = P.prepare_context(self.root)
        recorded = self.metadata(working=False)
        before = self.records(recorded)[0]
        self.change_current('Another localized wording correction.')
        after = self.records(self.metadata())[0]
        self.assertEqual(before['changed_locale_count'], after['changed_locale_count'])
        self.assertEqual(before['changed_version_count'], after['changed_version_count'])
        self.assertNotEqual(before['after_sha256'], after['after_sha256'])
        self.assertEqual(self.metadata(working=False), recorded, 'committed evidence must ignore dirty prose')
        with self.assertRaisesRegex(ValueError, 'implementation changed'):
            P.validate_context(self.root, context)

    def test_generated_private_and_duplicate_retention_files_do_not_authorize_notes(self):
        paths = ('CHANGELOG.md', 'changelogs/deDE.md', 'changelogs/private.json',
                 'changelogs/localized_revisions.json', 'release_notes/context.json',
                 'release_notes/enUS.json', 'release_notes/deDE.private.json',
                 'LocalizedReleaseNotes.lua', 'ReleaseNotesHistory.lua')
        for name in paths:
            (self.root / name).write_text('EXCLUDED_PRIVATE_OR_GENERATED_SENTINEL', encoding='utf-8')
        self.assertEqual(self.metadata(), '')
        with self.assertRaisesRegex(ValueError, 'no player-facing'):
            P.prepare_context(self.root, include_working_tree=True)

    def test_formatting_and_source_digest_changes_alone_do_not_authorize_notes(self):
        data = read(self.current)
        data['source_sha256'] = 'f' * 64
        self.current.write_text(json.dumps(data), encoding='utf-8')
        self.assertEqual(self.metadata(), '')
        with self.assertRaisesRegex(ValueError, 'no player-facing'):
            P.prepare_context(self.root, include_working_tree=True)

    def test_symlinked_files_and_parent_directories_are_not_followed(self):
        outside = self.directory / 'outside notes'
        outside.mkdir()
        secret = outside / 'deDE.json'
        secret.write_text('PRIVATE_SENTINEL_INVALID_JSON', encoding='utf-8')
        self.current.unlink()
        self.current.symlink_to(secret)
        self.assertEqual(self.metadata(), '')
        with self.assertRaisesRegex(ValueError, 'no player-facing'):
            P.prepare_context(self.root, include_working_tree=True)
        self.current.unlink()
        self.current.parent.rmdir()
        self.current.parent.symlink_to(outside, target_is_directory=True)
        self.assertEqual(self.metadata(), '')
        with self.assertRaisesRegex(ValueError, 'no player-facing'):
            P.prepare_context(self.root, include_working_tree=True)
        self.assertEqual(secret.read_text(encoding='utf-8'), 'PRIVATE_SENTINEL_INVALID_JSON')

    def test_invalid_canonical_json_is_rejected_before_it_can_be_evidence(self):
        invalid = [
            '{"notes": {}}',
            '{"source_sha256": "' + 'a' * 64 + '", "notes": {}, "notes": {}}',
            dumps({'source_sha256': 'not-a-digest', 'notes': F.sample_notes()}),
        ]
        for text in invalid:
            with self.subTest(text=text):
                self.current.write_text(text, encoding='utf-8')
                with self.assertRaises(ValueError):
                    P.prepare_context(self.root, include_working_tree=True)
                self.assertEqual(self.current.read_text(encoding='utf-8'), text)


if __name__ == '__main__':
    unittest.main()
