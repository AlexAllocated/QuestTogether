#!/usr/bin/env python3
"""Offline local-authoring behavior with isolated Git repositories and a fake CLI."""
from collections import Counter
import sys
import unittest
from unittest import mock
import urllib.request

sys.dont_write_bytecode = True
import author_release_notes as A
import test_release_notes as F
from localization import LOCALES, dumps, read


class InterruptedRun(RuntimeError):
    pass


class FakeClient:
    """Return schema-shaped fixtures, without claiming translation quality."""

    def __init__(self, *, fail_at=None, on_request=None, lose_command_at=None):
        self.fail_at = fail_at
        self.on_request = on_request
        self.lose_command_at = lose_command_at
        self.calls = []
        self.logins = 0

    def check_login(self):
        self.logins += 1

    def request(self, prompt, *, schema, output_dir, stage):
        self.calls.append((stage, prompt))
        if stage == self.fail_at:
            raise InterruptedRun('Simulated interruption during ' + stage)
        if self.on_request:
            self.on_request(stage)
        locale, _phase = stage.rsplit('-', 1)
        if locale == 'facts':
            welcome = 'Factual scope: nearby player map markers.'
            items = ['Nearby players: class-colored map dots.', 'Settings command: /qt.']
        elif locale == 'enUS':
            welcome = 'English publication sentinel: see your companions nearby.'
            items = ['Find nearby players by their class-colored dots. Open /qt for settings.']
        else:
            welcome = locale + ': independently authored fixture.'
            items = [locale + ': nearby players have class-colored dots.',
                     locale + ': open /qt for settings.']
        if stage == self.lose_command_at:
            items = [locale + ': nearby players have class-colored dots.']
        return {'welcome': welcome, 'sections': [{
            'title': 'Map markers' if locale == 'facts' else locale + ': Map markers',
            'items': items, 'tip': None,
        }]}


class LocalAuthoringTests(unittest.TestCase):
    run_process = F.NotesTests.run_process
    git = F.NotesTests.git
    new_repo = F.NotesTests.new_repo
    release_note_bytes = F.NotesTests.release_note_bytes

    def setUp(self):
        F.NotesTests.setUp(self)
        network = mock.patch.object(urllib.request, 'urlopen',
                                    side_effect=AssertionError('no model API or network requests'))
        network.start()
        self.addCleanup(network.stop)
        (self.root / 'Core.lua').write_text(
            '-- Newly added class-colored nearby-player map dots.\n'
            '-- Open /qt for settings.\n', encoding='utf-8')
        (self.root / 'locales').mkdir()
        for locale in LOCALES:
            (self.root / 'locales' / (locale + '.json')).write_text(
                dumps({'Map dots': locale + ': map-dot UI label'}), encoding='utf-8')
        self.git('add', '.')
        self.git('commit', '-qm', 'Add nearby player map markers')
        self.output = self.directory / 'local authoring drafts'
        self.before = self.canonical_bytes()
        self.head = self.git('rev-parse', 'HEAD')

    def author(self, client, **kwargs):
        return A.author(self.root, self.output, client=client,
                        progress=lambda message: None, **kwargs)

    def canonical_bytes(self):
        snapshot = self.release_note_bytes()
        for pattern in ('release_notes/*.json', 'changelogs/*.json', 'changelogs/*.md'):
            snapshot.update({str(path.relative_to(self.root)): path.read_bytes()
                             for path in self.root.glob(pattern)})
        return snapshot

    def assert_canonical_unchanged(self):
        self.assertEqual(self.canonical_bytes(), self.before)
        self.assertEqual(self.git('rev-parse', 'HEAD'), self.head)
        self.assertEqual(self.git('rev-parse', 'v1.2.3^{commit}'),
                         self.git('rev-parse', 'HEAD^'))

    def test_complete_draft_reviews_every_language_without_leaking_english_or_installing(self):
        client = FakeClient()
        entry = self.author(client)
        self.assertGreater(client.logins, 0)
        stages = ['facts-draft', 'facts-edit']
        stages += [locale + '-' + phase for locale in ('enUS', *LOCALES)
                   for phase in ('draft', 'edit')]
        self.assertEqual([stage for stage, _ in client.calls], stages)
        self.assertEqual(set(entry), {'enUS', *LOCALES})
        self.assertTrue((self.output / 'context.json').is_file())
        self.assertEqual(read(self.output / 'facts.json')['version'], '1.2.3')
        for locale, notes in entry.items():
            self.assertEqual(notes, read(self.output / (locale + '.json')))
            self.assertEqual(notes['version'], '1.2.3')
            self.assertNotIn('tip', notes['sections'][0])
        for stage, prompt in client.calls:
            self.assertNotIn(F.sample_notes()['welcome'], prompt)
            if stage.split('-')[0] in LOCALES:
                self.assertIn('Factual scope: nearby player map markers.', prompt)
                self.assertIn('Newly added class-colored', prompt)
                self.assertNotIn('English publication sentinel', prompt)
        self.assert_canonical_unchanged()

    def test_interrupted_run_resumes_completed_passes_without_reauthoring(self):
        first = FakeClient(fail_at='frFR-edit')
        with self.assertRaises(InterruptedRun):
            self.author(first)
        saved = (self.output / 'deDE.json').read_bytes()
        self.assertFalse((self.output / 'frFR.json').exists())
        self.assert_canonical_unchanged()
        resumed = FakeClient()
        entry = self.author(resumed, resume=True)
        self.assertEqual(set(entry), {'enUS', *LOCALES})
        self.assertEqual((self.output / 'deDE.json').read_bytes(), saved)
        completed = [stage for stage, _ in first.calls if stage != 'frFR-edit']
        self.assertTrue(set(completed).isdisjoint(stage for stage, _ in resumed.calls))
        counts = Counter(stage for stage, _ in first.calls + resumed.calls)
        self.assertEqual(counts.pop('frFR-edit'), 2)
        self.assertEqual(set(counts.values()), {1})
        self.assert_canonical_unchanged()

    def test_resume_rejects_changed_evidence_model_or_scope_before_more_model_calls(self):
        original = (self.root / 'Core.lua').read_text(encoding='utf-8')
        for change in ('evidence', 'model', 'scope'):
            with self.subTest(change=change):
                self.output = self.directory / ('draft-' + change)
                first = FakeClient(fail_at='enUS-draft')
                with self.assertRaises(InterruptedRun):
                    self.author(first, include_working_tree=True)
                context = (self.output / 'context.json').read_bytes()
                kwargs = {'include_working_tree': True, 'resume': True}
                if change == 'evidence':
                    (self.root / 'Core.lua').write_text(original + '-- New behavior.\n', encoding='utf-8')
                elif change == 'model':
                    kwargs['model'] = 'another-subscription-model'
                else:
                    kwargs['scope'] = 'Only discuss the map setting.'
                resumed = FakeClient()
                try:
                    with self.assertRaises(ValueError):
                        self.author(resumed, **kwargs)
                    self.assertEqual(resumed.calls, [])
                    self.assertEqual((self.output / 'context.json').read_bytes(), context)
                    self.assert_canonical_unchanged()
                finally:
                    (self.root / 'Core.lua').write_text(original, encoding='utf-8')

    def test_resume_preserves_and_refuses_user_edited_completed_draft(self):
        with self.assertRaises(InterruptedRun):
            self.author(FakeClient(fail_at='frFR-draft'))
        path = self.output / 'deDE.json'
        edited = read(path)
        edited['welcome'] = 'User-authored correction that must be preserved.'
        path.write_text(dumps(edited), encoding='utf-8')
        before = path.read_bytes()
        resumed = FakeClient()
        with self.assertRaises(ValueError):
            self.author(resumed, resume=True)
        self.assertEqual(path.read_bytes(), before)
        self.assertEqual(resumed.calls, [])
        self.assert_canonical_unchanged()

    def test_source_change_during_final_review_aborts_without_canonical_writes(self):
        def change_source(stage):
            if stage == 'zhTW-edit':
                with (self.root / 'Core.lua').open('a', encoding='utf-8') as stream:
                    stream.write('-- Implementation changed while authoring.\n')

        with self.assertRaises(ValueError):
            self.author(FakeClient(on_request=change_source), include_working_tree=True)
        self.assert_canonical_unchanged()

    def test_english_terminology_change_during_review_invalidates_completed_set(self):
        def change_glossary(stage):
            if stage == 'zhTW-edit':
                (self.root / 'locales/enUS.json').write_text(dumps({'Map dots': 'Player markers'}))

        with self.assertRaisesRegex(ValueError, 'UI terminology changed'):
            self.author(FakeClient(on_request=change_glossary), include_working_tree=True)
        self.assertNotEqual(read(self.output / 'authoring.json')['status'], 'complete')
        self.assert_canonical_unchanged()

    def test_review_that_loses_required_command_cannot_complete_or_install(self):
        client = FakeClient(lose_command_at='deDE-edit')
        with self.assertRaises(ValueError):
            self.author(client)
        self.assertFalse((self.output / 'deDE.json').exists())
        self.assertFalse((self.output / '.checkpoints/deDE-edit.json').exists())
        retry = FakeClient()
        self.author(retry, resume=True)
        self.assertEqual(retry.calls[0][0], 'deDE-edit')
        self.assertEqual(len(retry.calls), 19)
        self.assert_canonical_unchanged()

    def test_evidence_is_complete_and_oversize_aborts_before_model_or_draft_writes(self):
        text = '-- beginning\n' + '-- context for the change\n' * 500 + '-- middle sentinel\n' + '-- tail\n' * 500
        (self.root / 'Core.lua').write_text(text, encoding='utf-8')
        context = A.prepare_context(self.root, include_working_tree=True)
        self.assertIn('evidence excerpt shortened', context['evidence'])
        evidence = A.full_evidence(self.root, context)
        self.assertIn('-- middle sentinel', evidence)
        self.assertNotIn(F.sample_notes()['welcome'], evidence)
        client = FakeClient()
        with mock.patch.object(A, 'MAX_EVIDENCE', 100):
            with self.assertRaisesRegex(ValueError, 'complete evidence exceeds'):
                self.author(client, include_working_tree=True)
        self.assertEqual(client.calls, [])
        self.assertFalse(self.output.exists())
        self.assert_canonical_unchanged()

    def test_existing_nonempty_output_is_not_overwritten_with_or_without_resume(self):
        self.output.mkdir()
        path = self.output / 'enUS.json'
        path.write_text('Existing user draft.\n', encoding='utf-8')
        for resume in (False, True):
            with self.subTest(resume=resume):
                client = FakeClient()
                with self.assertRaises(ValueError):
                    self.author(client, resume=resume)
                self.assertEqual(client.calls, [])
                self.assertEqual(path.read_text(encoding='utf-8'), 'Existing user draft.\n')
                self.assert_canonical_unchanged()

    def test_concurrent_author_cannot_enter_locked_output_directory(self):
        blocked = FakeClient()

        def try_second_author(stage):
            if stage == 'facts-draft':
                with self.assertRaises(ValueError):
                    self.author(blocked, resume=True)

        self.author(FakeClient(on_request=try_second_author))
        self.assertEqual(blocked.calls, [])
        self.assert_canonical_unchanged()


if __name__ == '__main__':
    unittest.main()
