#!/usr/bin/env python3
"""Subscription CLI boundary tests with a local fake CLI and no model calls."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

sys.dont_write_bytecode = True
import codex_note_author as A


FAKE_CLI = r'''
import json
import os
from pathlib import Path
import sys
import time

if sys.argv[1:] == ['login', 'status']:
    counter = Path(__file__).with_name('login-count')
    counter.write_text(str(int(counter.read_text()) + 1) if counter.exists() else '1')
    print(LOGIN, file=sys.stderr)
    raise SystemExit(LOGIN_CODE)

args = sys.argv[1:]
result = Path(args[args.index('--output-last-message') + 1])
payload = json.loads(sys.stdin.read())
(result.parent / 'invocation.json').write_text(json.dumps({
    'args': args, 'cwd': os.getcwd(), 'environment_keys': sorted(os.environ),
    'schema': json.loads(Path(args[args.index('--output-schema') + 1]).read_text()),
}))
if 'raw_result' in payload:
    result.write_text(payload['raw_result'])
elif not payload.get('missing_result'):
    result.write_text(json.dumps(payload.get('result', {'welcome': 'A complete draft.'})))
for event in payload.get('events', [{'type': 'turn.completed'}]):
    print(json.dumps(event), flush=True)
if payload.get('stderr'):
    print(payload['stderr'], file=sys.stderr, flush=True)
if payload.get('sleep'):
    time.sleep(payload['sleep'])
raise SystemExit(payload.get('exit', 0))
'''


class CodexAuthorTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='codex-note-author-test-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.output = self.root / 'draft notes'
        self.schema = {'type': 'object', 'properties': {'welcome': {'type': 'string'}},
                       'required': ['welcome'], 'additionalProperties': False}
        self.fake_cli()
        environment = mock.patch.dict(os.environ, {
            'PATH': str(self.bin) + os.pathsep + os.environ.get('PATH', ''),
            'OPENAI_API_KEY': 'never-use-this-api-key',
            'CODEX_API_KEY': 'never-use-this-codex-key',
            'OPENAI_BASE_URL': 'https://not-the-subscription-endpoint.invalid',
            'CODEX_ACCESS_TOKEN': 'never-replace-the-signed-in-user',
            'UNRELATED_SECRET': 'do-not-pass-to-the-cli',
        })
        environment.start()
        self.addCleanup(environment.stop)
        self.author = A.CodexAuthor(timeout=5)

    def fake_cli(self, login='Logged in using ChatGPT', code=0):
        path = self.bin / 'codex'
        path.write_text('#!' + sys.executable + '\nLOGIN = ' + repr(login) +
                        '\nLOGIN_CODE = ' + str(code) + '\n' + FAKE_CLI)
        path.chmod(0o700)

    def request(self, payload=None, **kwargs):
        return self.author.request(json.dumps(payload or {}), schema=self.schema,
                                   output_dir=self.output, stage=kwargs.pop('stage', 'facts-author'),
                                   **kwargs)

    def attempts(self):
        return sorted((self.output / '.attempts').iterdir())

    def test_subscription_only_isolated_request_preserves_prompt_and_schema(self):
        expected = {'welcome': 'Hallo!'}
        self.assertEqual(self.request({'result': expected}), expected)
        attempt, = self.attempts()
        invocation = json.loads((attempt / 'invocation.json').read_text())
        args = invocation['args']
        self.assertEqual(args[:3], ['--no-daemon', 'exec', '--ignore-user-config'])
        for flag in ('--ignore-rules', '--ephemeral', '--skip-git-repo-check', '--json'):
            self.assertIn(flag, args)
        self.assertEqual(args[args.index('--sandbox') + 1], 'read-only')
        self.assertEqual(args[args.index('--model') + 1], 'gpt-6.1-sol')
        for config in ('forced_login_method="chatgpt"', 'model_provider="openai"',
                       'approval_policy="never"', 'project_doc_max_bytes=0',
                       'web_search="disabled"'):
            self.assertIn(config, args)
        disabled = {args[index + 1] for index, value in enumerate(args) if value == '--disable'}
        self.assertTrue({'shell_tool', 'hooks', 'apps', 'plugins', 'memories', 'multi_agent'} <= disabled)
        self.assertEqual(args[-1], '-')
        self.assertEqual(invocation['schema'], self.schema)
        self.assertFalse(Path(invocation['cwd']).is_relative_to(self.root))
        self.assertFalse(Path(invocation['cwd']).exists())
        for name in ('OPENAI_API_KEY', 'CODEX_API_KEY', 'OPENAI_BASE_URL',
                     'CODEX_ACCESS_TOKEN', 'UNRELATED_SECRET'):
            self.assertNotIn(name, invocation['environment_keys'])
        self.assertEqual(json.loads((attempt / 'prompt.txt').read_text()), {'result': expected})
        self.assertEqual(attempt.stat().st_mode & 0o777, 0o700)

    def test_explicit_login_check_is_reused_and_auth_status_is_not_logged(self):
        self.author.check_login()
        self.request()
        self.request(stage='facts-editor')
        self.assertEqual((self.bin / 'login-count').read_text(), '1')
        self.assertEqual(len(self.attempts()), 2)
        self.assertFalse(any('Logged in' in path.read_text() for attempt in self.attempts()
                             for path in attempt.iterdir()))

    def test_api_sign_in_is_rejected_without_logging_out_or_exposing_key(self):
        self.fake_cli('Logged in using an API key - fake-secret-suffix')
        with self.assertRaisesRegex(A.NotesError, 'Run codex login') as error:
            self.request()
        self.assertNotIn('fake-secret-suffix', str(error.exception))
        self.assertFalse(self.output.exists())
        self.assertEqual((self.bin / 'login-count').read_text(), '1')

    def test_unsuccessful_login_status_is_not_accepted_even_with_chatgpt_text(self):
        self.fake_cli(code=1)
        with self.assertRaisesRegex(A.NotesError, 'not signed in with ChatGPT'):
            self.author.check_login()
        self.assertFalse(self.author._login_checked)

    def test_missing_cli_error_is_actionable_and_does_not_expose_os_error(self):
        with mock.patch.object(A.subprocess, 'Popen', side_effect=OSError('sensitive diagnostic')):
            with self.assertRaisesRegex(A.NotesError, 'Could not start Codex') as error:
                self.author.check_login()
        self.assertNotIn('sensitive diagnostic', str(error.exception))

    def test_failed_attempt_never_accepts_its_complete_output_or_reuses_an_old_result(self):
        original = self.request()
        first, = self.attempts()
        first_bytes = (first / 'result.json').read_bytes()
        with self.assertRaisesRegex(A.NotesError, 'exit 12') as error:
            self.request({'exit': 12, 'result': {'welcome': 'Must not be accepted.'},
                          'stderr': 'private error diagnostic'})
        self.assertNotIn('private error diagnostic', str(error.exception))
        self.assertEqual((first / 'result.json').read_bytes(), first_bytes)
        self.assertEqual(original, {'welcome': 'A complete draft.'})
        with self.assertRaisesRegex(A.NotesError, 'valid JSON result'):
            self.request({'missing_result': True})
        self.assertEqual(len(self.attempts()), 3)

    def test_rejects_malformed_duplicate_nonfinite_and_nonobject_json(self):
        for value in ('not JSON', '{"welcome": "a", "welcome": "b"}',
                      '{"welcome": NaN}', '{"welcome": 1e999}', '["a"]', 'null'):
            with self.subTest(value=value):
                with self.assertRaises(A.NotesError):
                    self.request({'raw_result': value})

    def test_requires_successful_tool_free_terminal_event_even_when_exit_is_zero(self):
        for events in ([], [{'type': 'turn.failed', 'error': {'message': 'private error'}}],
                       [{'type': 'turn.completed'}, {'type': 'error', 'message': 'private error'}],
                       [{'type': 'item.completed', 'item': {'type': 'command_execution'}},
                        {'type': 'turn.completed'}]):
            with self.subTest(events=events):
                with self.assertRaisesRegex(A.NotesError, 'tool-free authoring turn') as error:
                    self.request({'events': events})
                self.assertNotIn('private error', str(error.exception))

    def test_accepts_reasoning_and_agent_message_events(self):
        events = [{'type': 'thread.started', 'thread_id': 'fixture'},
                  {'type': 'turn.started'},
                  {'type': 'item.completed', 'item': {'type': 'reasoning', 'text': 'Review.'}},
                  {'type': 'item.completed', 'item': {'type': 'agent_message', 'text': '{}'}},
                  {'type': 'turn.completed', 'usage': {'input_tokens': 1, 'output_tokens': 1}}]
        self.assertEqual(self.request({'events': events}), {'welcome': 'A complete draft.'})

    def test_timeout_rejects_output_already_written_by_attempt(self):
        self.author.check_login()
        self.author.timeout = 0.2
        with self.assertRaisesRegex(A.NotesError, 'timed out'):
            self.request({'sleep': 10})
        attempt, = self.attempts()
        self.assertTrue((attempt / 'result.json').is_file())

    @unittest.skipUnless(os.name == 'posix', 'POSIX process-group behavior')
    def test_timeout_kills_and_reaps_entire_process_group(self):
        process = mock.Mock(pid=12345)
        process.communicate.side_effect = [subprocess.TimeoutExpired('codex', 5), (b'', b'')]
        with mock.patch.object(A.subprocess, 'Popen', return_value=process) as popen:
            with mock.patch.object(A.os, 'killpg') as killpg:
                with self.assertRaisesRegex(A.NotesError, 'timed out'):
                    self.author.check_login()
        killpg.assert_called_once_with(12345, signal.SIGKILL)
        self.assertEqual(process.communicate.call_count, 2)
        self.assertTrue(popen.call_args.kwargs['start_new_session'])

    def test_keyboard_interrupt_also_stops_and_reaps_attempt(self):
        process = mock.Mock(pid=12345)
        process.communicate.side_effect = [KeyboardInterrupt, (b'', b'')]
        with mock.patch.object(A.subprocess, 'Popen', return_value=process):
            with mock.patch.object(A, '_stop') as stop:
                with self.assertRaises(KeyboardInterrupt):
                    self.author.check_login()
        stop.assert_called_once_with(process)

    def test_rejects_attempt_directory_symlink(self):
        self.output.mkdir()
        target = self.root / 'other-artifacts'
        target.mkdir()
        (self.output / '.attempts').symlink_to(target, target_is_directory=True)
        with self.assertRaisesRegex(A.NotesError, 'must not be a symlink'):
            self.request()
        self.assertEqual(list(target.iterdir()), [])

    def test_invalid_inputs_are_rejected_before_auth_or_subprocess(self):
        for timeout in (0, -1, True, float('inf'), float('nan'), '30'):
            with self.subTest(timeout=timeout):
                with self.assertRaises(A.NotesError):
                    A.CodexAuthor(timeout=timeout)
        for stage in ('../escape', '', 'a/b', 'a\n', 'a' * 81):
            with self.subTest(stage=stage):
                with self.assertRaises(A.NotesError):
                    self.request(stage=stage)
        with self.assertRaises(A.NotesError):
            self.author.request('', schema=self.schema, output_dir=self.output, stage='facts')
        for schema in (None, {'title': '\ud800'}, {'minimum': float('nan')}, {'type': object()}):
            with self.subTest(schema=repr(schema)):
                with self.assertRaises(A.NotesError):
                    self.author.request('prompt', schema=schema, output_dir=self.output, stage='facts')
        self.assertFalse((self.bin / 'login-count').exists())


if __name__ == '__main__':
    unittest.main()
