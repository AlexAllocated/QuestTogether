#!/usr/bin/env python3
import tempfile,unittest,json
from pathlib import Path
import sys
sys.dont_write_bytecode = True
import localization as L
from translate_locales import translate
class LocalizationTests(unittest.TestCase):
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
    def test_hint_commands_allow_translated_prose_but_preserve_real_commands(self):
        L.validate_translation('Type /qt to open settings.', 'Tapez /qt pour ouvrir les options.')
        L.validate_translation('Type /qt followed by a message.', 'Escribe /qt seguido de un mensaje.')
        L.validate_translation('Use /qt lfg on or /qt lfg off.', 'Verwende /qt lfg on oder /qt lfg off.')
        L.validate_translation('Use /qt tip or /qt hint.', 'Utilisez /qt tip ou /qt hint.')
        for target in ['Use /qt tips or /qt hint.', 'Use /qt tip or /qt indice.']:
            with self.assertRaises(ValueError):L.validate_translation('Use /qt tip or /qt hint.', target)
        with self.assertRaises(ValueError):
            L.validate_translation('Use /qt lfg on.', 'Utilisez /qt lfg off.')
    def test_markup_scanning_preserves_escaped_pipe_literals(self):
        self.assertEqual(L.visible_markup_text('||cffffffff'), '||cffffffff')
        self.assertEqual(L.visible_markup_text('|Hquest:1|h|cffffffffQuest title|r|h'), 'Quest title')
    def test_notes_generation_preserves_structure_and_is_incremental(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);notes={'version':'1.0.0','welcome':'Welcome','sections':[{'title':'New','items':['First','Second'],'illustration':'quest-partners'}]}
            (root/'release_notes.json').write_text(json.dumps(notes));calls=[]
            def request(strings,locale,key,model):calls.append(strings);return ['Trad '+s for s in strings]
            self.assertTrue(translate(root,'frFR',True,request=request))
            result=L.read(root/'release_notes/frFR.json');self.assertEqual(result['source_sha256'],L.digest(notes))
            self.assertEqual(result['notes']['sections'][0]['illustration'],'quest-partners')
            self.assertFalse(translate(root,'frFR',True,request=request));self.assertEqual(len(calls),1)
    def test_notes_translation_flattens_tip_label_and_body_in_section_order(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            notes={'version':'1.0.0','welcome':'Welcome','sections':[
                {'title':'New tips','items':['First'], 'tip':{'label':'Tip:','text':'Use /qt tip; scale to 150%.'}},
                {'title':'Next section','items':['Second']}]}
            (root/'release_notes.json').write_text(json.dumps(notes))
            def request(strings,locale,key,model):
                self.assertEqual(strings,['Welcome','New tips','First','Tip:','Use /qt tip; scale to 150%.','Next section','Second'])
                return ['Bienvenue','Conseils','Premier','Conseil :','Utilisez /qt tip ; agrandissez à 150 %.','Suite','Deuxième']
            self.assertTrue(translate(root,'frFR',True,request=request))
            result=L.read(root/'release_notes/frFR.json')['notes']
            self.assertEqual(result['sections'][0]['tip'],{'label':'Conseil :','text':'Utilisez /qt tip ; agrandissez à 150 %.'})
            self.assertNotIn('tip',result['sections'][1])
            previous=(root/'release_notes/frFR.json').read_bytes()
            notes['welcome']='Updated welcome';(root/'release_notes.json').write_text(json.dumps(notes))
            with self.assertRaises(ValueError):
                translate(root,'frFR',True,request=lambda strings,*args:[s.replace('/qt tip','/qt conseil') for s in strings])
            self.assertEqual((root/'release_notes/frFR.json').read_bytes(),previous)
if __name__=='__main__':unittest.main()
