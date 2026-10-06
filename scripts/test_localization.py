#!/usr/bin/env python3
import tempfile,unittest,json
from pathlib import Path
import sys
sys.dont_write_bytecode = True
import localization as L
from translate_locales import translate
class LocalizationTests(unittest.TestCase):
    def test_catalogs_match_native_wow_text_locales(self):
        # WoW has separate esES/esMX and zhCN/zhTW text locales. English is source.
        self.assertEqual(set(L.LOCALES), {'deDE','frFR','esES','esMX','ptBR','ruRU','itIT','koKR','zhCN','zhTW'})
        root=Path(__file__).resolve().parents[1]
        self.assertNotEqual(L.read(root/'locales/esMX.json'),L.read(root/'locales/esES.json'))
        toc=(root/'QuestTogether.toc').read_text()
        for locale in L.LOCALES:
            self.assertEqual(toc.count('## Notes-'+locale+':'),1)
    def test_format_and_boundary_contracts(self):
        for target in ['Anzahl %s', ' Anzahl %d', 'Anzahl %d ', 'Anzahl']:
            with self.assertRaises(ValueError):L.validate_translation('Count %d',target)
        L.validate_translation('Count %d','Anzahl %d')
        with self.assertRaises(ValueError):L.validate_translation('Value %s','Wert %z %s')
        with self.assertRaises(ValueError):L.validate_translation('/qt options opens settings','/qt einstellungen öffnet Optionen')
        with self.assertRaises(ValueError):L.validate_translation('/qt options opens settings','Einstellungen öffnen')
    def test_release_note_percentages_are_plain_text(self):
        source = 'Scale from 80% to 150% and use /qt resetlayout.'
        target = 'Skalierung von 80 % bis 150 %; verwende /qt resetlayout.'
        L.validate_translation(source, target, formatted=False)
        with self.assertRaises(ValueError):
            L.validate_translation(source, target.replace('/qt resetlayout', '/qt reset'), formatted=False)
        with self.assertRaises(ValueError):
            L.validate_translation('Value %s', 'Wert %d')
    def test_notes_request_disables_only_printf_validation(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            (root/'release_notes.json').write_text(json.dumps({'version':'1.0.0','welcome':'Scale 150% and more','sections':[{'title':'New','items':['One']}]}))
            with patch('translate_locales.request_translation', return_value=['150 % und mehr', 'Neu', 'Eins']) as request:
                translate(root, 'deDE', notes=True)
                self.assertIs(request.call_args.kwargs['formatted'], False)
    def test_command_names_allow_korean_particles_but_reject_renames(self):
        L.validate_translation('Open /qtd, then run /qt test.', '/qtd를 열고 /qt test를 실행하세요.')
        for target in ['/qtdx를 열고 /qt test를 실행하세요.', '/qtd를 열고 /qt 검사 실행하세요.']:
            with self.assertRaises(ValueError):
                L.validate_translation('Open /qtd, then run /qt test.', target)
    def test_source_audit_finds_visible_text_inside_wow_markup(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            strings=['QUEST', 'LEVEL', '|cffff8800Warning:|r', '|cff33ff99available|r', '|cffff4444unavailable|r',
                     '|Hquest:12345|hQuestName|h', '|TInterface\\\\Icons\\\\Logo:14|tWarning:']
            ignored=['|TInterface\\\\Icons\\\\Logo:14|t', '|A:QuestNormal:14:14|a', '|cffffffff', '|r',
                     'Interface\\\\Icons\\\\Logo']
            (root/'Example.lua').write_text('\n'.join('local text = '+json.dumps(value) for value in strings+ignored)
                + '\nlocal translated = L(\n "Settings")\n-- "Not a label"\n')
            self.assertEqual(L.untranslated_literals(root), {'Example.lua':sorted(strings)})
    def test_markup_scanning_preserves_escaped_pipe_literals(self):
        self.assertEqual(L.visible_markup_text('||cffffffff'), '||cffffffff')
        self.assertEqual(L.visible_markup_text('|Hquest:1|h|cffffffffQuest title|r|h'), 'Quest title')
    def test_duplicate_keys_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            p=Path(directory)/'duplicate.json';p.write_text('{"a":"b","a":"c"}')
            with self.assertRaises(ValueError):L.read(p)
    def test_catalog_complete_and_generated_exact(self):
        root=Path(__file__).resolve().parents[1]
        self.assertGreater(L.check(root),300)
    def test_notes_digest_ignores_version_but_not_words(self):
        self.assertEqual(L.digest({'version':'1','welcome':'Hello'}),L.digest({'version':'2','welcome':'Hello'}))
        self.assertNotEqual(L.digest({'version':'1','welcome':'Hello'}),L.digest({'version':'1','welcome':'Goodbye'}))
    def test_notes_generation_preserves_structure_and_is_incremental(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);notes={'version':'1.0.0','welcome':'Welcome','sections':[{'title':'New','items':['First','Second'],'illustration':'quest-partners'}]}
            (root/'release_notes.json').write_text(json.dumps(notes));calls=[]
            def request(strings,locale,key,model):calls.append(strings);return ['Trad '+s for s in strings]
            self.assertTrue(translate(root,'frFR',True,request=request))
            result=L.read(root/'release_notes/frFR.json');self.assertEqual(result['source_sha256'],L.digest(notes))
            self.assertEqual(result['notes']['sections'][0]['illustration'],'quest-partners')
            self.assertFalse(translate(root,'frFR',True,request=request));self.assertEqual(len(calls),1)
if __name__=='__main__':unittest.main()
