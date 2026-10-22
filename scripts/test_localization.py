#!/usr/bin/env python3
import tempfile,unittest,json,io,os
from pathlib import Path
from unittest import mock
import sys
sys.dont_write_bytecode = True
import localization as L
import translate_locales as T
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

    def test_retired_note_translation_never_reads_credentials_or_changes_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            (root/'release_notes').mkdir()
            (root/'release_notes.json').write_text('English sentinel')
            (root/'release_notes/deDE.json').write_text('German sentinel')
            before={p:p.read_bytes() for p in root.rglob('*') if p.is_file()}
            environment_get=os.environ.get
            def reject_credentials(name,*args):
                if name in {'OPENAI_API_KEY','CHANGELOG_OPENAI_MODEL'}:
                    raise AssertionError('retired note command must not read credentials or settings')
                return environment_get(name,*args)
            with mock.patch.object(T.urllib.request,'urlopen',side_effect=AssertionError('notes must not use network')) as network, \
                    mock.patch.dict(os.environ,{'OPENAI_API_KEY':'offline-secret','CHANGELOG_OPENAI_MODEL':'paid-model'}), \
                    mock.patch.object(os.environ,'get',side_effect=reject_credentials):
                with self.assertRaisesRegex(T.NotesError,'active Codex subscription session'):
                    T.translate(root,'deDE',notes=True,key='offline-secret')
                with self.assertRaisesRegex(T.NotesError,'active Codex subscription session'):
                    T.request_translation(['Release note'],'deDE','offline-secret','paid-model',formatted=False)
                for selection in ([],['--locale','deDE']):
                    with self.subTest(selection=selection), mock.patch('sys.stderr',new_callable=io.StringIO) as error:
                        self.assertEqual(T.main(['--root',str(root),'--write','--notes',*selection]),1)
                        self.assertIn('prepare_release_notes.py finalize',error.getvalue())
                        self.assertNotIn('offline-secret',error.getvalue())
                network.assert_not_called()
            self.assertEqual(before,{p:p.read_bytes() for p in root.rglob('*') if p.is_file()})

    def test_optional_ui_translation_keeps_existing_labels_and_uses_ui_model(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            (root/'locales').mkdir()
            path=root/'locales/deDE.json'
            path.write_text(L.dumps({'Existing label':'Vorhandener Text'}))
            request=mock.Mock(return_value=['Neuer Text'])
            with mock.patch.object(T,'source_strings',return_value=['Existing label','New label']), \
                    mock.patch('sys.stdout',new_callable=io.StringIO):
                T.translate(root,'deDE',key='offline-key',request=request)
            request.assert_called_once_with(['New label'],'deDE','offline-key',T.UI_MODEL)
            self.assertEqual(L.read(path),{'Existing label':'Vorhandener Text','New label':'Neuer Text'})
            self.assertFalse((root/'release_notes').exists())
if __name__=='__main__':unittest.main()
