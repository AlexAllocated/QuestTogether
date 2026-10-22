#!/usr/bin/env python3
"""Offline context-generation, historical-range and editorial replacement checks."""
import copy
import io
import json
import os
import urllib.request
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.dont_write_bytecode = True
import changelogs
import generate_localized_notes as N
import generate_release_notes as E
import localization as L
import test_release_notes as F
from translate_locales import translate


def draft(source, bullet='Natürlicher Text für Spieler.'):
    result = copy.deepcopy(source)
    result.pop('version')
    result['welcome'] = 'Neuigkeiten für deine Abenteuer.'
    for section in result['sections']:
        section.pop('illustration', None)
        section['items'] = [bullet, 'Ein weiterer kurzer Satz.']
    return result


def fact_draft(source):
    """Preserve fixture facts/tokens without mocking the extraction boundary away."""
    result = copy.deepcopy(source)
    result.pop('version')
    result['welcome'] = 'Release purpose for the shared factual brief.'
    for section in result['sections']:
        section.pop('illustration', None)
    return result


def staged_draft(payload, bullet='Natürlicher Text für Spieler.'):
    data = json.loads(payload)
    if 'approved_release_scope' in data:
        return fact_draft(data['approved_release_scope'])
    return draft(data['release_facts'], bullet)


class ContextTests(unittest.TestCase):
    run_process = F.NotesTests.run_process
    git = F.NotesTests.git
    new_repo = F.NotesTests.new_repo

    def setUp(self):
        F.NotesTests.setUp(self)
        self.network = mock.patch.object(urllib.request, 'urlopen', side_effect=AssertionError('offline tests must not use network'))
        self.network.start()
        self.addCleanup(self.network.stop)

    def test_retired_generation_and_cli_ignore_credentials_and_preserve_files(self):
        before = {p: p.read_bytes() for p in self.root.rglob('*') if p.is_file() and '.git' not in p.parts}
        with self.assertRaisesRegex(N.NotesError, 'active Codex subscription session'):
            N.regenerate(self.root, since='1.2.3', write=True, key='offline-secret')
        environment_get = os.environ.get
        def reject_credentials(name, *args):
            if name in {'OPENAI_API_KEY', 'CHANGELOG_OPENAI_MODEL'}:
                raise AssertionError('retired CLI must not read model credentials or settings')
            return environment_get(name, *args)
        with mock.patch.dict(os.environ, {'OPENAI_API_KEY': 'offline-secret', 'CHANGELOG_OPENAI_MODEL': 'paid-model'}), \
                mock.patch.object(os.environ, 'get', side_effect=reject_credentials), \
                mock.patch.object(N, 'regenerate', side_effect=AssertionError('retired CLI must not begin generation')), \
                mock.patch('sys.stderr', new_callable=io.StringIO) as error:
            self.assertEqual(N.main(['--root', str(self.root), '--since', '1.2.3', '--write', '--model', 'paid-model']), 1)
        self.assertIn('prepare_release_notes.py finalize', error.getvalue())
        self.assertNotIn('offline-secret', error.getvalue())
        self.assertEqual(before, {p: p.read_bytes() for p in self.root.rglob('*') if p.is_file() and '.git' not in p.parts})

    def save_context(self, notes, evidence='Actual code changes and commit evidence.'):
        path, text = N.context_output(self.root, notes, evidence)
        path.parent.mkdir(exist_ok=True)
        path.write_text(text)

    def test_full_context_glossary_and_independent_bullets_reach_provider(self):
        source = F.sample_notes(item='Open Party Quest Log with /qt pql.')
        source['welcome'] = 'FINAL ENGLISH WELCOME MUST NOT REACH LOCALE WRITERS'
        source['sections'][0]['illustration'] = 'party-quest-log'
        (self.root/'locales').mkdir()
        (self.root/'locales/deDE.json').write_text(L.dumps({'Party Quest Log':'Gruppenquestlog','Unrelated label':'Not supplied'}))
        passes = []
        scope_passes = []
        facts = {'version': source['version'], 'welcome': 'Party quest log access.', 'sections': [
            {'title': 'Party Quest Log access', 'items': ['Party Quest Log command: /qt pql.'],
             'illustration': 'party-quest-log'}]}
        def provider(payload, key, model, **kwargs):
            request = json.loads(payload)
            if 'approved_release_scope' in request:
                scope_passes.append(request)
                self.assertEqual(request['approved_release_scope'], source)
                result = copy.deepcopy(facts)
                result.pop('version')
                result['sections'][0].pop('illustration')
                return result
            passes.append(request)
            self.assertEqual(request['release_evidence'], 'Actual context of the change')
            self.assertEqual(request['release_facts'], facts)
            self.assertNotIn('approved_coverage_reference', request)
            self.assertNotIn('approved_release_scope', request)
            self.assertNotIn(source['welcome'], payload)
            self.assertNotIn(source['sections'][0]['items'][0], payload)
            self.assertEqual(request['ui_terminology'], {'Party Quest Log':'Gruppenquestlog'})
            self.assertIn('do not translate line by line', kwargs['instructions'])
            if 'draft_to_edit' in request:
                self.assertIn('minimap launcher button belongs only to its owner', kwargs['instructions'])
            return draft(source, 'Öffne das Gruppenquestlog mit /qt pql.')
        result = N.compose(self.root, source, 'Actual context of the change', 'deDE', None, generator=provider)
        self.assertEqual(len(result['sections'][0]['items']), 2)
        self.assertEqual(result['sections'][0]['illustration'], 'party-quest-log')
        self.assertEqual(changelogs.validate_entry({'enUS':source,'deDE':result}), source['version'])
        self.assertEqual(len(scope_passes), 2)
        self.assertNotIn('candidate_facts', scope_passes[0])
        self.assertIn('candidate_facts', scope_passes[1])
        self.assertEqual(len(passes), 2)
        self.assertNotIn('draft_to_edit', passes[0])
        self.assertIn('draft_to_edit', passes[1])
        self.assertEqual(passes[0]['release_evidence'], passes[1]['release_evidence'])

    def test_old_translation_command_uses_context_and_never_reuses_flattened_strings(self):
        source = F.sample_notes()
        self.save_context(source)
        p=self.root/'release_notes/deDE.json'
        p.write_text(L.dumps({'source_sha256':L.digest(source), 'notes':{**source,'welcome':'OLD AWKWARD TRANSLATION'}}))
        def provider(payload, *args, **kwargs):
            self.assertNotIn('OLD AWKWARD TRANSLATION',payload)
            self.assertIn('release_evidence', json.loads(payload))
            return staged_draft(payload)
        self.assertTrue(translate(self.root,'deDE',True,request=provider))
        self.assertNotIn('OLD AWKWARD TRANSLATION',p.read_text())
        before=p.read_bytes()
        source['welcome']='Edited factual scope'
        (self.root/'release_notes.json').write_text(L.dumps(source))
        with self.assertRaisesRegex(ValueError,'stale'):
            translate(self.root,'deDE',True,request=provider)
        self.assertEqual(p.read_bytes(),before)
        (self.root/N.CONTEXT_PATH).unlink()
        with self.assertRaisesRegex(ValueError,'missing release context'):
            translate(self.root,'deDE',True,request=provider)

    def test_missing_topics_and_changed_tip_commands_fail_before_replacement(self):
        source=F.sample_notes()
        source['sections'][0]['tip']={'label':'Tip:','text':'Use /qt tip at 150%.'}
        (self.root/'release_notes.json').write_text(L.dumps(source))
        self.save_context(source)
        path=self.root/'release_notes/deDE.json'
        path.write_text('unchanged sentinel')
        good=draft(source)
        good['sections'][0]['tip']={'label':'Tipp:','text':'Nutze /qt tip bei 150 %.'}
        bad=copy.deepcopy(good);bad['sections'][0]['tip']['text']='Nutze /qt tipp.'
        for value in [bad,{**good,'sections':[]}]:
            def invalid_locale(payload, *args, **kwargs):
                data = json.loads(payload)
                return fact_draft(data['approved_release_scope']) if 'approved_release_scope' in data else copy.deepcopy(value)
            with self.assertRaises(ValueError):
                translate(self.root,'deDE',True,request=invalid_locale)
            self.assertEqual(path.read_text(),'unchanged sentinel')
        def valid_locale(payload, *args, **kwargs):
            data = json.loads(payload)
            return fact_draft(data['approved_release_scope']) if 'approved_release_scope' in data else good
        result=N.compose(self.root,source,'Evidence','deDE',None,generator=valid_locale)
        self.assertEqual(result['sections'][0]['tip']['label'],'Tipp:')
        def failed_editor(payload,*args,**kwargs):
            return bad if 'draft_to_edit' in json.loads(payload) else valid_locale(payload)
        with self.assertRaises(ValueError):
            translate(self.root,'deDE',True,request=failed_editor)
        self.assertEqual(path.read_text(),'unchanged sentinel')

    def publish(self, version, feature):
        source=F.sample_notes(version,feature)
        (self.root/'Core.lua').write_text('-- '+feature+'\n')
        (self.root/'QuestTogether.toc').write_text('## Version: '+version+'\nCore.lua\nReleaseNotes.lua\n')
        (self.root/'release_notes.json').write_text(L.dumps(source))
        (self.root/'release_notes').mkdir(exist_ok=True)
        entry={'enUS':source}
        for locale in L.LOCALES:
            entry[locale]=copy.deepcopy(source)
            (self.root/'release_notes'/f'{locale}.json').write_text(L.dumps({'source_sha256':L.digest(source),'notes':source}))
        self.git('add','.');self.git('commit','-qm',feature);self.git('tag','v'+version)
        return entry

    def test_committed_historical_english_corrections_remain_scope_without_changing_evidence(self):
        first = self.publish('2.0.0', 'Original feature implementation')
        second = self.publish('2.0.1', 'Second feature implementation')
        corrected = copy.deepcopy(first)
        for notes in corrected.values():
            notes['sections'][0]['items'] = ['Corrected name for the original feature.']
        history = self.root / 'changelogs/history.json'
        history.parent.mkdir()
        history.write_text(L.dumps({'schema': 1, 'releases': [corrected]}))
        self.git('add', 'changelogs/history.json')
        self.git('commit', '-qm', 'Correct an already published feature name')
        self.assertEqual(changelogs.approved_english(self.root, '2.0.0'), corrected['enUS'])
        self.assertEqual(changelogs.approved_english(self.root, '2.0.1'), second['enUS'])
        def provider(payload, *args, **kwargs):
            data = json.loads(payload)
            scope = data.get('approved_release_scope', data.get('release_facts'))
            if scope['version'] == '2.0.0':
                if 'approved_release_scope' in data:
                    self.assertEqual(scope, corrected['enUS'])
                self.assertIn('Original feature implementation', data['release_evidence'])
                self.assertNotIn('Second feature implementation', data['release_evidence'])
                self.assertNotIn('Correct an already published feature name', data['release_evidence'])
            return staged_draft(payload)
        N.regenerate(self.root, since='2.0.0', write=True, generator=provider)
        self.assertEqual(changelogs.tagged_entry(self.root, '2.0.0')['enUS'], corrected['enUS'])
        dirty = L.read(history)
        dirty['releases'][0]['enUS']['welcome'] = 'Unapproved change in a dirty history file'
        history.write_text(L.dumps(dirty))
        with self.assertRaisesRegex(ValueError, 'committed editorial correction'):
            N.regenerate(self.root, since='2.0.0', write=True, generator=provider)

    def test_silent_historical_release_remains_empty_without_requesting_a_draft(self):
        source = {'version': '2.0.0', 'welcome': '', 'sections': []}
        with mock.patch.object(N, 'request_notes', side_effect=AssertionError('silent releases have no text to generate')):
            self.assertEqual(N.compose(self.root, source, 'Actual historical release evidence', 'deDE', None), source)

    def test_full_history_includes_legacy_translations_and_recovers_an_omitted_published_release(self):
        self.git('rm', 'release_notes.json')
        (self.root / 'QuestTogether.toc').write_text('## Version: 1.2.3\nCore.lua\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'Legacy fixture before structured notes')
        self.git('tag', '-f', 'v1.2.3')
        (self.root / 'QuestTogether.toc').write_text('## Version: 1.2.4\nCore.lua\n')
        (self.root / 'Core.lua').write_text('-- Old feature implementation evidence.\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'Ship the old feature')
        self.git('tag', 'v1.2.4')
        legacy = {locale: F.sample_notes('1.2.4', 'The old feature is available.') for locale in ('enUS', *L.LOCALES)}
        first = self.publish('2.0.0', 'First structured release')
        omitted = self.publish('2.0.1', 'Accidentally omitted published release')
        current = self.publish('2.1.0', 'Current release')
        (self.root / 'changelogs').mkdir()
        (self.root / 'changelogs/history.json').write_text(L.dumps({'schema': 1, 'releases': [first]}))
        (self.root / 'changelogs/legacy_notes.json').write_text(L.dumps([legacy]))
        self.git('add', '.')
        self.git('commit', '-qm', 'Archive historical release notes')
        seen = set()
        def provider(payload, *args, **kwargs):
            data = json.loads(payload)
            source = data.get('approved_release_scope', data.get('release_facts'))
            seen.add(source['version'])
            if source['version'] == '1.2.4':
                self.assertIn('Old feature implementation evidence', data['release_evidence'])
                self.assertNotIn('First structured release', data['release_evidence'])
                if 'approved_release_scope' in data:
                    self.assertEqual(source, legacy['enUS'])
            return staged_draft(payload)
        N.regenerate(self.root, since='1.2.4', write=True, generator=provider)
        self.assertEqual(seen, {'1.2.4', '2.0.0', '2.0.1', '2.1.0'})
        archived = L.read(self.root / 'changelogs/history.json')['releases']
        self.assertEqual([e['enUS']['version'] for e in archived], ['2.0.1', '2.0.0'])
        self.assertEqual(archived[0]['enUS'], omitted['enUS'])
        self.assertEqual(L.read(self.root / 'release_notes.json'), current['enUS'])
        revised_legacy = L.read(self.root / 'changelogs/legacy_notes.json')[0]
        self.assertEqual(revised_legacy['enUS'], legacy['enUS'])
        self.assertNotEqual(revised_legacy['deDE'], legacy['deDE'])
        self.assertEqual(changelogs.localized_revisions(self.root)['1.2.4'], revised_legacy)
        changelogs.outputs(self.root, current['enUS'])
        revised_legacy['deDE']['welcome'] = 'Stale legacy text'
        (self.root / 'changelogs/legacy_notes.json').write_text(L.dumps([revised_legacy]))
        with self.assertRaisesRegex(ValueError, 'legacy localization differs'):
            changelogs.outputs(self.root, current['enUS'])

    def test_historical_regeneration_uses_each_tag_range_and_survives_next_bump(self):
        first=self.publish('2.0.0','First new feature')
        second=self.publish('2.0.1','Second fixed behavior')
        # An older-numbered maintenance tag merged later is not the baseline
        # for a historical release that predates that maintenance branch.
        branch=self.git('branch','--show-current')
        self.git('checkout','-qb','maintenance','v1.2.3')
        (self.root/'Maintenance.lua').write_text('-- LATER_MERGED_BACKPORT\n')
        self.git('add','.');self.git('commit','-qm','LATER_MERGED_BACKPORT')
        self.git('tag','v1.9.0');self.git('checkout','-q',branch)
        self.git('merge','--no-ff','-qm','Merge old maintenance branch','maintenance')
        (self.root/'changelogs').mkdir()
        (self.root/'changelogs/history.json').write_text(L.dumps({'schema':1,'releases':[first]}))
        # Deliberately newer and dirty work must not leak into historical notes.
        (self.root/'Core.lua').write_text('-- FUTURE UNPUBLISHED FEATURE\n')
        seen=[]
        def provider(payload,*args,**kwargs):
            data=json.loads(payload);source=data.get('approved_release_scope',data.get('release_facts'))
            seen.append(source['version'])
            self.assertNotIn('FUTURE UNPUBLISHED FEATURE',data['release_evidence'])
            self.assertNotIn('LATER_MERGED_BACKPORT',data['release_evidence'])
            self.assertIn('First new feature' if source['version']=='2.0.0' else 'Second fixed behavior',data['release_evidence'])
            return staged_draft(payload)
        before={p:p.read_bytes() for p in self.root.rglob('*.json')}
        calls=0
        def failed(payload,*args,**kwargs):
            nonlocal calls
            calls+=1
            if calls==12:raise ValueError('provider interrupted')
            return provider(payload,*args,**kwargs)
        with self.assertRaisesRegex(ValueError,'interrupted'):
            N.regenerate(self.root,since='2.0.0',write=True,generator=failed,workers=1)
        self.assertEqual(before,{p:p.read_bytes() for p in self.root.rglob('*.json')})
        seen.clear()
        N.regenerate(self.root,since='2.0.0',write=True,generator=provider)
        self.assertEqual(len(seen),44)  # Two fact passes per release, then two per locale.
        self.assertEqual(L.read(self.root/'release_notes.json'),second['enUS'])
        corrected=changelogs.tagged_entry(self.root,'2.0.1')
        self.assertNotEqual(corrected['deDE'],second['deDE'])
        self.assertEqual(corrected['enUS'],second['enUS'])
        # Both regeneration entry points retain subsequent editorial changes.
        N.regenerate(self.root,write=True,generator=lambda payload,*a,**k:staged_draft(payload,'Verbesserter Text.'))
        translate(self.root,'deDE',True,request=lambda payload,*a,**k:staged_draft(payload,'Noch klarer formulierter Text.'))
        corrected=changelogs.tagged_entry(self.root,'2.0.1')
        self.assertEqual(corrected['deDE']['sections'][0]['items'][0],'Noch klarer formulierter Text.')
        self.assertEqual(corrected['frFR']['sections'][0]['items'][0],'Verbesserter Text.')
        with (self.root/'QuestTogether.toc').open('a') as manifest:
            manifest.write('LocalizedReleaseNotes.lua\n')
        F.CHECKER.check_reused_translations(self.root,self.git('rev-parse','v2.0.1'))
        stale=self.root/'release_notes/deDE.json'
        corrected_bytes=stale.read_bytes()
        stale.write_text(L.dumps({'source_sha256':L.digest(second['enUS']),'notes':second['deDE']}))
        with self.assertRaisesRegex(ValueError,'reused translation differs'):
            F.CHECKER.check_reused_translations(self.root,self.git('rev-parse','v2.0.1'))
        stale.write_bytes(corrected_bytes)
        self.assertEqual(N.revision_output(self.root,{'2.0.1':{'enUS':F.sample_notes('2.0.1','Upcoming release draft')}}),{})
        next_notes=F.sample_notes('2.0.2','Third change')
        localized={self.root/'release_notes'/f'{loc}.json':L.dumps({'source_sha256':L.digest(next_notes),'notes':next_notes}) for loc in L.LOCALES}
        outputs=changelogs.outputs(self.root,next_notes,localized,previous_version='2.0.1')
        archived=json.loads(outputs[self.root/'changelogs/history.json'])['releases']
        self.assertEqual(archived[0],corrected)
        revisions=L.read(self.root/N.REVISION_PATH)
        revisions['releases'][0]['enUS']['welcome']='Invented historical fact'
        (self.root/N.REVISION_PATH).write_text(L.dumps(revisions))
        with self.assertRaisesRegex(ValueError,'published English'):
            changelogs.tagged_entry(self.root,'2.0.1')


if __name__=='__main__':unittest.main()
