#!/usr/bin/env python3
"""Run isolated, subscription-authenticated Codex note-authoring attempts.

This module never reads or copies authentication files and has no API fallback.
The caller owns semantic note validation and resumable authoring checkpoints.
"""
import json
import math
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
from check_release_notes import NotesError


MODEL = 'gpt-6.1-sol'
STAGE = re.compile(r'[A-Za-z0-9][A-Za-z0-9_-]{0,79}\Z')
# Keep the existing login/keyring, executable lookup and TLS settings. In
# particular, never inherit API keys, endpoint overrides or an access token
# that could silently replace the user's existing subscription sign-in.
ENVIRONMENT = frozenset({
    'HOME', 'PATH', 'USER', 'LOGNAME', 'SHELL', 'LANG', 'LANGUAGE', 'CODEX_HOME',
    'XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_CACHE_HOME', 'XDG_STATE_HOME',
    'XDG_RUNTIME_DIR', 'DBUS_SESSION_BUS_ADDRESS', 'GNOME_KEYRING_CONTROL',
    'SSL_CERT_FILE', 'SSL_CERT_DIR', 'REQUESTS_CA_BUNDLE', 'CURL_CA_BUNDLE',
    'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'NO_PROXY',
    'http_proxy', 'https_proxy', 'all_proxy', 'no_proxy',
    'NIX_LD', 'NIX_LD_LIBRARY_PATH', 'SYSTEMROOT', 'WINDIR', 'PATHEXT',
    'APPDATA', 'LOCALAPPDATA', 'USERPROFILE',
})
DISABLED_FEATURES = (
    'shell_tool', 'shell_snapshot', 'hooks', 'apps', 'plugins', 'remote_plugin',
    'memories', 'multi_agent', 'browser_use', 'computer_use', 'image_generation',
    'goals', 'skill_search', 'skill_mcp_dependency_install',
)


def _environment():
    return {key: value for key, value in os.environ.items()
            if key in ENVIRONMENT or key.startswith('LC_')}


def _object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('duplicate JSON key')
        result[key] = value
    return result


def _constant(value):
    raise ValueError('non-finite JSON value')


def _float(value):
    result = float(value)
    if not math.isfinite(result):
        raise ValueError('non-finite JSON value')
    return result


def _json(text):
    return json.loads(text, object_pairs_hook=_object, parse_constant=_constant, parse_float=_float)


def _stop(process):
    """Kill the complete POSIX attempt, including any child processes, and reap."""
    try:
        if os.name == 'posix':
            os.killpg(process.pid, signal.SIGKILL)
        else:
            process.kill()
    except ProcessLookupError:
        pass
    process.communicate()


class CodexAuthor:
    def __init__(self, model=MODEL, timeout=600):
        if not isinstance(model, str) or not model.strip() or model != model.strip():
            raise NotesError('Codex authoring requires a nonempty model name')
        if (isinstance(timeout, bool) or not isinstance(timeout, (int, float))
                or not math.isfinite(timeout) or timeout <= 0):
            raise NotesError('Codex authoring timeout must be a positive number of seconds')
        self.model = model
        self.timeout = timeout
        self._login_checked = False

    def _run(self, command, *, cwd, prompt=None, stdout=subprocess.PIPE,
             stderr=subprocess.PIPE, timeout=None):
        try:
            process = subprocess.Popen(
                command, cwd=cwd, env=_environment(), stdin=subprocess.PIPE,
                stdout=stdout, stderr=stderr, start_new_session=True,
            )
        except OSError:
            raise NotesError('Could not start Codex CLI. Install it and run codex login, then retry.') from None
        try:
            out, err = process.communicate(
                input=prompt.encode('utf-8') if prompt is not None else None,
                timeout=self.timeout if timeout is None else timeout,
            )
        except subprocess.TimeoutExpired:
            _stop(process)
            raise NotesError('Codex CLI timed out; the attempt was stopped. Retry to continue authoring.') from None
        except BaseException:
            _stop(process)
            raise
        return process.returncode, out, err

    def check_login(self):
        """Check the method without forcing it, which could log other users out."""
        self._login_checked = False
        with tempfile.TemporaryDirectory(prefix='questtogether-codex-login-') as cwd:
            code, out, err = self._run(
                ['codex', 'login', 'status'], cwd=cwd, timeout=min(self.timeout, 30),
            )
        status = ((out or b'') + b'\n' + (err or b'')).decode('utf-8', errors='replace')
        if code != 0 or 'Logged in using ChatGPT' not in status.splitlines():
            # Login status may include an API-key suffix. Never echo it or save
            # it in attempt artifacts, and never switch authentication for users.
            raise NotesError('Codex is not signed in with ChatGPT. Run codex login with your subscription, then retry; API authentication is not supported.')
        self._login_checked = True

    def _command(self, schema_path, result_path):
        command = [
            'codex', '--no-daemon', 'exec', '--ignore-user-config', '--ignore-rules',
            '--ephemeral', '--skip-git-repo-check', '--sandbox', 'read-only',
            '--json', '--color', 'never', '--model', self.model,
            '--output-schema', str(schema_path), '--output-last-message', str(result_path),
        ]
        for setting in (
            'approval_policy="never"', 'forced_login_method="chatgpt"',
            'model_provider="openai"', 'web_search="disabled"',
            'project_doc_max_bytes=0', 'shell_environment_policy.inherit="none"',
            'shell_environment_policy.experimental_use_profile=false',
            'notify=[]', 'mcp_servers={}',
        ):
            command.extend(['-c', setting])
        for feature in DISABLED_FEATURES:
            command.extend(['--disable', feature])
        return [*command, '-']

    def request(self, prompt, *, schema, output_dir, stage):
        if not isinstance(prompt, str) or not prompt.strip():
            raise NotesError('Codex authoring requires a nonempty prompt')
        if not isinstance(stage, str) or not STAGE.fullmatch(stage):
            raise NotesError('Codex authoring stage must be a short name containing letters, numbers, underscores or hyphens')
        if not isinstance(schema, dict):
            raise NotesError('Codex authoring requires a JSON schema object')
        try:
            schema_text = json.dumps(schema, ensure_ascii=False, indent=2, allow_nan=False) + '\n'
            schema_text.encode('utf-8')
            prompt.encode('utf-8')
        except (ValueError, TypeError, UnicodeError):
            raise NotesError('Codex authoring prompt or schema is not valid UTF-8 JSON input') from None
        if not self._login_checked:
            self.check_login()
        try:
            attempts = Path(output_dir).resolve() / '.attempts'
            if attempts.is_symlink():
                raise NotesError('Codex authoring .attempts directory must not be a symlink')
            attempts.mkdir(parents=True, exist_ok=True, mode=0o700)
            attempt = Path(tempfile.mkdtemp(prefix=stage + '-', dir=attempts))
            schema_path, result_path = attempt / 'schema.json', attempt / 'result.json'
            schema_path.write_text(schema_text, encoding='utf-8')
            (attempt / 'prompt.txt').write_text(prompt, encoding='utf-8')
            with tempfile.TemporaryDirectory(prefix='questtogether-codex-author-') as cwd:
                with (attempt / 'events.jsonl').open('wb') as events, (attempt / 'stderr.log').open('wb') as errors:
                    code, _, _ = self._run(
                        self._command(schema_path, result_path), cwd=cwd,
                        prompt=prompt, stdout=events, stderr=errors,
                    )
            if code != 0:
                raise NotesError('Codex authoring failed for ' + stage + ' (exit ' + str(code) + '). Review local attempt artifacts: ' + str(attempt))
            self._check_events(attempt / 'events.jsonl')
            try:
                result = _json(result_path.read_text(encoding='utf-8'))
            except (OSError, UnicodeError, ValueError):
                raise NotesError('Codex did not return a valid JSON result for ' + stage + '. Review local attempt artifacts: ' + str(attempt)) from None
            if not isinstance(result, dict):
                raise NotesError('Codex result must be a JSON object for ' + stage + '. Review local attempt artifacts: ' + str(attempt))
            return result
        except OSError:
            raise NotesError('Could not read or write Codex attempt artifacts. Check the draft directory and available disk space, then retry.') from None

    @staticmethod
    def _check_events(path):
        completed = False
        try:
            for line in path.read_text(encoding='utf-8').splitlines():
                if not line.strip():
                    continue
                event = _json(line)
                if not isinstance(event, dict):
                    raise ValueError('invalid event')
                kind = event.get('type')
                if kind in {'error', 'turn.failed'}:
                    raise ValueError('failed turn')
                if kind == 'turn.completed':
                    completed = True
                if kind in {'item.started', 'item.updated', 'item.completed'}:
                    item = event.get('item')
                    if not isinstance(item, dict) or item.get('type') not in {'agent_message', 'reasoning', 'todo_list'}:
                        raise ValueError('unexpected tool use')
            if not completed:
                raise ValueError('missing completed turn')
        except (OSError, UnicodeError, ValueError):
            raise NotesError('Codex did not complete a tool-free authoring turn. Review local attempt artifacts: ' + str(path.parent)) from None
