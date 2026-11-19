#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
# See LICENSING.md for scope and preserved third-party notices.
"""Offline contracts for the local validation gate and isolated Lua workers."""

import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True

import validate_release as validation

SHA = "a" * 40


class PlanTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "sample.lua").write_text("return true\n")
        self.tools = {name: "/tools/" + name for name in ("git", "bash", "openssl", "python", "lua5.1", "lua5.2")}

    def test_all_ci_modes_clients_locales_and_publication_contracts_are_retained(self):
        with patch.object(validation, "run") as run, patch.object(validation, "regression_matrix") as matrix:
            validation.validate(self.root, self.tools, {"PATH": "/tools"})
        matrix.assert_called_once_with(self.root, self.tools, {"PATH": "/tools"})
        calls = run.call_args_list
        commands = [call.args[0] for call in calls]
        for script in ("test_release.py", "test_validate_release.py", "test_package.py", "test_discord_changelog.py",
                       "check_release_notes.py", "test_release_history.py", "test_author_release_notes.py"):
            self.assertTrue(any("scripts/" + script in command for command in commands), script)
        for version in ("5.1", "5.2"):
            lua = self.tools["lua" + version]
            for script in validation.LUA_CHECKS:
                if script != "test.lua":
                    self.assertIn([lua, "scripts/" + script], commands)
            locale_calls = [call for call in calls if call.args[0] == [lua, "scripts/test.lua", ".", "locale"]]
            self.assertEqual({call.kwargs["env"]["QT_TEST_LOCALE"] for call in locale_calls}, set(validation.LOCALES))
            for client in validation.CLIENTS:
                self.assertIn([lua, "scripts/test.lua", ".", "normal", client], commands)
            for client in ("retail", "forever"):
                self.assertIn([lua, "scripts/location_client_profiles.lua", ".", client], commands)
            vip = [call for call in calls if "services/vip" in call.args[0] and call.kwargs["env"]["QT_TEST_LUA"] == lua]
            self.assertEqual(len(vip), 1)
            syntax = [call for call in calls if call.args[0] == [lua, "-"]]
            self.assertEqual(len(syntax), 1)
            self.assertIn("loadfile", syntax[0].kwargs["input"])
            self.assertNotIn("dofile", syntax[0].kwargs["input"])
        self.assertIn([self.tools["python"], "scripts/package.py", "--ref", "HEAD", "--output", "dist/QuestTogether.zip"], commands)
        self.assertFalse(any(word in {"pip", "apt-get", "curl", "gh", "push"} for command in commands for word in command))

    def test_first_failure_stops_the_plan(self):
        with patch.object(validation, "run", side_effect=validation.ValidationError("failed")) as run:
            with self.assertRaises(validation.ValidationError):
                validation.validate(self.root, self.tools, {})
        self.assertEqual(run.call_count, 1)

    def test_preflight_checks_both_interpreters_and_missing_dependencies_fail_clearly(self):
        def ready(command, **kwargs):
            if "io.write(_VERSION)" in command:
                return "Lua " + command[0][-3:]
            if command[0] == self.tools["python"]:
                raise validation.ValidationError("missing dependencies")
            return "OpenSSL"
        with patch.object(validation, "run", side_effect=ready):
            with self.assertRaisesRegex(validation.ValidationError, "requirements.txt.*--python"):
                validation.preflight(self.root, self.tools, {})
        with patch.object(validation, "run", return_value="Lua 5.4"):
            with self.assertRaisesRegex(validation.ValidationError, "Lua 5.1 executable reports Lua 5.4"):
                validation.preflight(self.root, self.tools, {})

    def test_run_propagates_failed_exit_without_starting_more_commands(self):
        with patch.object(validation.subprocess, "run", return_value=subprocess.CompletedProcess([], 9)) as execute:
            with self.assertRaisesRegex(validation.ValidationError, "fixture failed.*9"):
                validation.run(["/fake/lua"], cwd=self.root, env={}, label="fixture", capture=True)
        self.assertEqual(execute.call_count, 1)
        self.assertNotIn("shell", execute.call_args.kwargs)

    def test_matrix_runs_all_complete_orders_with_native_bits_and_readable_logs(self):
        def execute(command, **kwargs):
            kwargs["stdout"].write("complete fixture suite\n")
            return subprocess.CompletedProcess(command, 0)
        output = io.StringIO()
        with patch.object(validation.subprocess, "run", side_effect=execute) as run, \
                contextlib.redirect_stdout(output):
            validation.regression_matrix(self.root, self.tools, {"PATH": "/tools"})
        expected = {(self.tools["lua" + version], mode) for version in ("5.1", "5.2")
                    for mode in ("normal", "reverse", "live", "live-reverse")}
        self.assertEqual({(call.args[0][0], call.args[0][-1]) for call in run.call_args_list}, expected)
        self.assertEqual(run.call_count, 8)
        for call in run.call_args_list:
            self.assertEqual(call.args[0][1:3], ["scripts/test.lua", "."])
            self.assertEqual(call.kwargs["cwd"], self.root)
            self.assertEqual(call.kwargs["env"]["QT_TEST_REQUIRE_NATIVE_BIT"], "1")
            self.assertEqual(call.kwargs["env"]["QT_TEST_TIMINGS"], "1")
        self.assertEqual(output.getvalue().count("complete fixture suite\n"), 8)

    def test_failed_matrix_prints_failure_and_prevents_success(self):
        def execute(command, **kwargs):
            kwargs["stdout"].write("fixture assertion failed\n")
            return subprocess.CompletedProcess(command, 9)
        output = io.StringIO()
        with patch.object(validation.subprocess, "run", side_effect=execute), \
                patch.object(validation.os, "cpu_count", return_value=1), \
                contextlib.redirect_stdout(output), \
                self.assertRaisesRegex(validation.ValidationError, "failed.*9"):
            validation.regression_matrix(self.root, self.tools, {})
        self.assertIn("fixture assertion failed", output.getvalue())

    def test_missing_native_bit_support_fails_preflight(self):
        def execute(command, **kwargs):
            if "require('bit')" in command[-1]:
                raise validation.ValidationError("missing bit")
            return "Lua 5.1"
        with patch.object(validation, "run", side_effect=execute), \
                self.assertRaisesRegex(validation.ValidationError, "LuaBitOp"):
            validation.preflight(self.root, self.tools, {})


class OrchestrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.parent = Path(self.temp.name)
        self.root = self.parent / "source"
        self.root.mkdir()
        self.receipt = self.parent / "success.json"
        self.calls = []
        self.guard = patch.object(validation.subprocess, "run", side_effect=AssertionError("tests must not execute commands"))
        self.guard.start()
        self.addCleanup(self.guard.stop)

    def fake_run(self, command, **kwargs):
        self.calls.append((command, dict(kwargs)))
        if "rev-parse" in command:
            return "false" if "--is-shallow-repository" in command else SHA
        if "clone" in command:
            Path(command[-1]).mkdir()
        return ""

    def invoke(self, *, validate=None, preflight=None, extra=()):
        with patch.object(validation, "run", side_effect=self.fake_run), \
                patch.object(validation, "executable", side_effect=lambda value, label: "/tools/" + Path(value).name), \
                patch.object(validation, "preflight", side_effect=preflight), \
                patch.object(validation, "validate", side_effect=validate) as checked, \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            result = validation.main(["--root", str(self.root), "--receipt", str(self.receipt), *extra])
        return result, checked

    def test_exact_detached_local_snapshot_success_receipt_and_cleanup(self):
        captured = []
        def check(snapshot, tools, env):
            captured.append(snapshot)
            self.assertNotEqual(snapshot, self.root)
            self.assertTrue(snapshot.is_dir())
            aliases = Path(env["PATH"].split(os.pathsep)[0])
            self.assertEqual((aliases / "lua5.1").readlink(), Path("/tools/custom-lua51"))
            self.assertEqual((aliases / "lua5.2").readlink(), Path("/tools/custom-lua52"))
        result, checked = self.invoke(validate=check, extra=("--ref", "v1.2.3", "--lua51", "/fake/custom-lua51", "--lua52", "/fake/custom-lua52"))
        self.assertEqual(result, 0)
        self.assertEqual(checked.call_count, 1)
        self.assertFalse(captured[0].exists())
        self.assertEqual(json.loads(self.receipt.read_text()), {
            "schema": 1, "commit": SHA, "runner_sha256": hashlib.sha256(Path(validation.__file__).read_bytes()).hexdigest(), "passed": True})
        commands = [command for command, _ in self.calls]
        self.assertTrue(any(command[-1] == "v1.2.3^{commit}" and "--end-of-options" in command for command in commands))
        self.assertTrue(any("clone" in command and "--shared" in command and str(self.root) in command for command in commands))
        self.assertTrue(any(command[-2:] == ["--detach", SHA] for command in commands))
        self.assertFalse(any("worktree" in command for command in commands))

    def test_failed_validation_removes_stale_receipt_and_cleans_snapshot(self):
        self.receipt.write_text('{"passed":true}')
        snapshots = []
        def fail(snapshot, tools, env):
            snapshots.append(snapshot)
            raise validation.ValidationError("fixture failed")
        result, _ = self.invoke(validate=fail)
        self.assertEqual(result, 1)
        self.assertFalse(self.receipt.exists())
        self.assertFalse(snapshots[0].exists())

    def test_missing_dependencies_prevent_validation_and_receipt(self):
        result, checked = self.invoke(preflight=validation.ValidationError("missing dependency"))
        self.assertEqual(result, 1)
        checked.assert_not_called()
        self.assertFalse(self.receipt.exists())

    def test_unignored_receipt_inside_source_is_rejected_without_deleting_it(self):
        self.receipt = self.root / "important.json"
        self.receipt.write_text("preserve")
        original = self.fake_run
        def unignored(command, **kwargs):
            if "check-ignore" in command:
                raise validation.ValidationError("not ignored")
            return original(command, **kwargs)
        self.fake_run = unignored
        result, checked = self.invoke()
        self.assertEqual(result, 1)
        self.assertEqual(self.receipt.read_text(), "preserve")
        checked.assert_not_called()
        self.assertFalse(any("clone" in command for command, _ in self.calls))

    def test_tracked_receipt_is_rejected_even_when_ignore_patterns_match(self):
        self.receipt = self.root / "tracked.json"
        self.receipt.write_text("preserve")
        original = self.fake_run
        def tracked(command, **kwargs):
            if "ls-files" in command:
                return "tracked.json"
            return original(command, **kwargs)
        self.fake_run = tracked
        result, checked = self.invoke()
        self.assertEqual(result, 1)
        self.assertEqual(self.receipt.read_text(), "preserve")
        checked.assert_not_called()

    def test_ignored_untracked_receipt_is_allowed(self):
        self.receipt = self.root / ".local/releases/v1.2.3/validation.json"
        result, checked = self.invoke()
        self.assertEqual(result, 0)
        self.assertTrue(json.loads(self.receipt.read_text())["passed"])
        self.assertEqual(checked.call_count, 1)
        commands = [command for command, _ in self.calls]
        self.assertTrue(any("ls-files" in command for command in commands))
        self.assertTrue(any("check-ignore" in command for command in commands))

    def test_changed_runner_cannot_certify_new_code_with_old_results(self):
        with patch.object(validation, "runner_sha256", side_effect=["a" * 64, "b" * 64]):
            result, _ = self.invoke()
        self.assertEqual(result, 1)
        self.assertFalse(self.receipt.exists())

    def test_missing_tool_has_actionable_error(self):
        with patch.object(validation.shutil, "which", return_value=None):
            with self.assertRaisesRegex(validation.ValidationError, "missing Lua 5.2.*executable path"):
                validation.executable("lua5.2", "Lua 5.2")

    def test_virtualenv_executable_path_is_preserved(self):
        python = self.parent / "venv-python"
        python.symlink_to(sys.executable)
        with patch.object(validation.shutil, "which", return_value=str(python)):
            self.assertEqual(validation.executable(str(python), "Python"), str(python))

    def test_ambient_git_and_locale_settings_do_not_override_the_plan(self):
        def check(snapshot, tools, env):
            self.assertNotIn("GIT_DIR", env)
            self.assertNotIn("QT_TEST_LOCALE", env)
            self.assertNotIn("QT_TEST_LUA", env)
        with patch.dict(os.environ, {"GIT_DIR": "/unrelated", "QT_TEST_LOCALE": "deDE", "QT_TEST_LUA": "/unrelated/lua"}):
            result, _ = self.invoke(validate=check)
        self.assertEqual(result, 0)

    def test_publication_credentials_never_reach_snapshot_commands(self):
        names = ("DISCORD_BOT_TOKEN", "GH_TOKEN", "GITHUB_TOKEN")
        def check(snapshot, tools, env):
            for name in names:
                self.assertNotIn(name, env)
        with patch.dict(os.environ, {name: "private-fixture" for name in names}):
            result, _ = self.invoke(validate=check)
        self.assertEqual(result, 0)
        for command, kwargs in self.calls:
            for name in names:
                self.assertNotIn(name, kwargs["env"])


if __name__ == "__main__":
    unittest.main()
