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
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        (self.root / "sample.lua").write_text("return true\n")
        self.tools = {name: "/tools/" + name for name in ("git", "bash", "openssl", "python", "lua5.1")}

    def test_full_plan_retains_all_checks_on_lua51(self):
        jobs = validation.validation_jobs(self.root, self.tools, {}, validation.FULL_SCOPE)
        commands = [job[1] for job in jobs]
        lua = self.tools["lua5.1"]
        for mode in ("normal", "reverse", "live", "live-reverse"):
            self.assertIn([lua, "scripts/test.lua", ".", mode], commands)
        for arguments in validation.PYTHON_CHECKS:
            self.assertIn([self.tools["python"], "scripts/" + arguments[0], *arguments[1:]], commands)
        for client in validation.CLIENTS:
            self.assertIn([lua, "scripts/test.lua", ".", "normal", client], commands)
        self.assertEqual({job[2]["QT_TEST_LOCALE"] for job in jobs if "QT_TEST_LOCALE" in job[2]}, set(validation.LOCALES))
        self.assertFalse(any("lua5.2" in part for command in commands for part in command))
        self.assertEqual(len([j for j in jobs if j[1] == [lua, "-"]]), 1)

    def test_routine_keeps_runtime_security_clients_and_actual_package(self):
        scope = {"stress": False, "tools": False, "base": "v1.0.0", "reason": "UI only"}
        with patch.object(validation, "run_jobs") as execute, patch.object(validation, "run") as run:
            validation.validate(self.root, self.tools, {}, scope)
        commands = [job[1] for job in execute.call_args.args[1]]
        self.assertIn([self.tools["lua5.1"], "scripts/test.lua", ".", "routine"], commands)
        self.assertIn([self.tools["lua5.1"], "scripts/test.lua", ".", "live"], commands)
        for script in ("test_developer_crypto.py", "bindings_smoke.py", "check_release_notes.py", "localization.py", "changelogs.py"):
            self.assertTrue(any("scripts/" + script in command for command in commands))
        self.assertFalse(any("scripts/test_package.py" in command for command in commands))
        self.assertTrue(any("services/vip" in command for command in commands))
        self.assertIn("scripts/package.py", run.call_args.args[0])
        self.assertIn("--ref", run.call_args.args[0])

    def test_failed_job_prevents_package_and_preserves_error_log(self):
        def fail(command, **kwargs):
            kwargs["stdout"].write("fixture assertion failed\n")
            return subprocess.CompletedProcess(command, 9)
        output = io.StringIO()
        with patch.object(validation.subprocess, "run", side_effect=fail) as execute, \
                contextlib.redirect_stdout(output), self.assertRaisesRegex(validation.ValidationError, "failed.*9"):
            validation.run_jobs(self.root, [("fixture", ["lua"], {}, None)])
        self.assertEqual(execute.call_count, 1)
        self.assertIn("fixture assertion failed", output.getvalue())
        with patch.object(validation, "run_jobs", side_effect=validation.ValidationError("failed")), \
                patch.object(validation, "run") as package, self.assertRaises(validation.ValidationError):
            validation.validate(self.root, self.tools, {})
        package.assert_not_called()

    def test_jobs_preserve_commands_environments_and_separate_output(self):
        def execute(command, **kwargs):
            kwargs["stdout"].write(command[0] + " passed\n")
            self.assertEqual(kwargs["env"]["JOB"], command[0])
            self.assertEqual(kwargs["input"], command[0])
            return subprocess.CompletedProcess(command, 0)
        output = io.StringIO()
        jobs = [(str(i), [str(i)], {"JOB": str(i)}, str(i)) for i in range(8)]
        with patch.object(validation.subprocess, "run", side_effect=execute) as run, contextlib.redirect_stdout(output):
            validation.run_jobs(self.root, jobs)
        self.assertEqual(run.call_count, 8)
        for i in range(8): self.assertEqual(output.getvalue().count(str(i) + " passed\n"), 1)

    def test_native_bits_and_python_dependencies_are_required(self):
        def ready(command, **kwargs):
            if "io.write(_VERSION)" in command: return "Lua 5.1"
            if command[0] == self.tools["python"]: raise validation.ValidationError("missing dependency")
            return ""
        with patch.object(validation, "run", side_effect=ready), self.assertRaisesRegex(validation.ValidationError, "requirements.txt"):
            validation.preflight(self.root, self.tools, {})
        def missing_bit(command, **kwargs):
            if "require('bit')" in command[-1]: raise validation.ValidationError("missing bit")
            return "Lua 5.1"
        with patch.object(validation, "run", side_effect=missing_bit), self.assertRaisesRegex(validation.ValidationError, "LuaBitOp"):
            validation.preflight(self.root, self.tools, {})


class SelectionTests(unittest.TestCase):
    def test_presentation_and_auth_changes_are_distinct(self):
        for path in ("QuestCompareWindow.lua", "PresetWindow.lua", "locales/frFR.json", "Media/QuestChain.svg", "release_notes.json"):
            self.assertEqual(validation.changed_scope([path]), {"stress": False, "tools": False})
        for path in ("Core.lua", "Settings.lua", "Transport.lua", "VIPIdentity.lua", "Libs/Ed25519/Ed25519.lua", "scripts/network_fixture.lua", "scripts/test.lua", "unknown.dat"):
            self.assertEqual(validation.changed_scope([path]), {"stress": True, "tools": True})
        self.assertEqual(validation.changed_scope(["scripts/release.py"]), {"stress": False, "tools": True})
        self.assertEqual(validation.changed_scope(["scripts/validate_release.py"]), {"stress": True, "tools": True})

    def test_real_git_baseline_skips_current_tag_and_checks_manifest_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                return subprocess.check_output(["git", "-c", "user.name=Offline", "-c", "user.email=test@example.invalid", "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", *args], cwd=root, text=True).strip()
            git("init", "-q")
            (root / "QuestTogether.toc").write_text("## Version: 1.0.0\nCore.lua\n")
            git("add", "."); git("commit", "-qm", "baseline"); git("tag", "v1.0.0")
            (root / "QuestTogether.toc").write_text("## Version: 1.1.0\nCore.lua\n")
            (root / "PresetWindow.lua").write_text("-- fixture\n")
            git("add", "."); git("commit", "-qm", "presentation"); git("tag", "v1.1.0")
            tools = {"git": "git"}
            scope = validation.select_scope(root, tools, os.environ)
            self.assertEqual(scope["base"], "v1.0.0")
            self.assertFalse(scope["stress"]); self.assertFalse(scope["tools"])
            (root / "QuestTogether.toc").write_text("## Version: 1.1.1\nCore.lua\nNewCore.lua\n")
            git("add", "."); git("commit", "-qm", "manifest change")
            self.assertTrue(validation.select_scope(root, tools, os.environ)["stress"])
            self.assertEqual(validation.select_scope(root, tools, os.environ, True), validation.FULL_SCOPE)

    def test_missing_history_and_baseline_fail_closed(self):
        with patch.object(validation, "run", return_value=""):
            self.assertTrue(validation.select_scope(Path("/source"), {"git": "git"}, {})["stress"])
        with patch.object(validation, "run", side_effect=validation.ValidationError("read failure")):
            self.assertTrue(validation.select_scope(Path("/source"), {"git": "git"}, {})["tools"])


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
                patch.object(validation, "select_scope", return_value=validation.FULL_SCOPE), \
                patch.object(validation, "validate", side_effect=validate) as checked, \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            result = validation.main(["--root", str(self.root), "--receipt", str(self.receipt), *extra])
        return result, checked

    def test_exact_detached_local_snapshot_success_receipt_and_cleanup(self):
        captured = []
        def check(snapshot, tools, env, scope):
            captured.append(snapshot)
            self.assertNotEqual(snapshot, self.root)
            self.assertTrue(snapshot.is_dir())
            aliases = Path(env["PATH"].split(os.pathsep)[0])
            self.assertEqual((aliases / "lua5.1").readlink(), Path("/tools/custom-lua51"))
            self.assertFalse((aliases / "lua5.2").exists())
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
        def fail(snapshot, tools, env, scope):
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
        def check(snapshot, tools, env, scope):
            self.assertNotIn("GIT_DIR", env)
            self.assertNotIn("QT_TEST_LOCALE", env)
            self.assertNotIn("QT_TEST_LUA", env)
        with patch.dict(os.environ, {"GIT_DIR": "/unrelated", "QT_TEST_LOCALE": "deDE", "QT_TEST_LUA": "/unrelated/lua"}):
            result, _ = self.invoke(validate=check)
        self.assertEqual(result, 0)

    def test_publication_credentials_never_reach_snapshot_commands(self):
        names = ("DISCORD_BOT_TOKEN", "GH_TOKEN", "GITHUB_TOKEN")
        def check(snapshot, tools, env, scope):
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
