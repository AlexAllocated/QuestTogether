#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
# See LICENSING.md for scope and preserved third-party notices.
"""Offline detached deployment contracts; no real services or publication."""

import contextlib
import io
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True

import deploy


REPOSITORY = "offline-owner/QuestTogether"
GITHUB_SECRET = "offline-github-secret-DO-NOT-LOG"
DISCORD_SECRET = "offline-discord-secret-DO-NOT-LOG"
CURSEFORGE_SECRET = "offline-curseforge-secret-DO-NOT-LOG"
REAL_SUBPROCESS_RUN = subprocess.run
REAL_DEPLOY_RUN = deploy.run

FIXTURE_PUBLISHER = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
if "--check" in sys.argv:
    if (root / ".local/fail-preflight").exists():
        print("offline preflight refused", flush=True)
        sys.exit(7)
    print("offline preflight passed", flush=True)
    sys.exit(0)
output = root / ".local"
output.mkdir(exist_ok=True)
events = output / "fixture-events.json"
history = json.loads(events.read_text()) if events.exists() else []
history.append({"cwd": str(Path.cwd()), "arguments": sys.argv[1:],
                "commit": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
                "content": (root / "release-payload.txt").read_text()})
events.write_text(json.dumps(history))
print("Validating offline release locally...", flush=True)
print("fixture GitHub credential: " + os.environ.get("GH_TOKEN", ""), flush=True)
print("fixture Discord credential: " + os.environ.get("DISCORD_BOT_TOKEN", ""), flush=True)
print("fixture CurseForge credential: " + os.environ.get("CURSEFORGE_API_TOKEN", ""), flush=True)
if (output / "fail-worker").exists():
    print("offline worker failed before publication", flush=True)
    sys.exit(9)
print("Pushing the validated release tag; handing off to CurseForge.", flush=True)
print("Posting the release notes to Discord locally...", flush=True)
print("Published offline release on GitHub and announced it on Discord.", flush=True)
'''


class DeployTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="questtogether-deploy-")
        self.addCleanup(temporary.cleanup)
        self.parent = Path(temporary.name)
        self.root = self.parent / "source with spaces"
        self.root.mkdir()
        environment = {key: value for key, value in os.environ.items()
                       if not key.startswith("GIT_") and key not in
                       {"GH_TOKEN", "GITHUB_TOKEN", "DISCORD_BOT_TOKEN", "GH_HOST"}}
        environment.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull,
                           GIT_ALLOW_PROTOCOL="file", GIT_TERMINAL_PROMPT="0",
                           GIT_AUTHOR_NAME="Offline deployment test", GIT_AUTHOR_EMAIL="test@example.invalid",
                           GIT_COMMITTER_NAME="Offline deployment test", GIT_COMMITTER_EMAIL="test@example.invalid",
                           GH_TOKEN=GITHUB_SECRET, DISCORD_BOT_TOKEN=DISCORD_SECRET,
                           CURSEFORGE_API_TOKEN=CURSEFORGE_SECRET)
        patched = patch.dict(os.environ, environment, clear=True)
        patched.start()
        self.addCleanup(patched.stop)
        (self.root / "scripts").mkdir()
        (self.root / "scripts/release.py").write_text(FIXTURE_PUBLISHER)
        (self.root / "scripts/validate_release.py").write_text("# Offline validator fingerprint fixture\n")
        (self.root / ".gitignore").write_text(".local/\n")
        (self.root / "release-payload.txt").write_text("exact tagged payload\n")
        (self.root / "QuestTogether.toc").write_text("## Version: 1.2.3\n")
        self.git("init", "-q")
        self.git("checkout", "-qb", "main")
        self.git("add", ".")
        self.git("commit", "-qm", "Offline release fixture")
        self.git("tag", "-a", "v1.2.3", "-m", "Offline release fixture")
        self.git("remote", "add", "origin", "https://github.com/" + REPOSITORY + ".git")
        self.sha = self.git("rev-parse", "HEAD")
        self.calls = []
        self.service_active = True

    def git(self, *arguments, root=None):
        result = REAL_SUBPROCESS_RUN(
            ["git", "-c", "commit.gpgsign=false", "-c", "core.hooksPath=" + os.devnull, *arguments],
            cwd=root or self.root, text=True, capture_output=True, check=True)
        return result.stdout.strip()

    def fake_run(self, root, command, *, env=None):
        self.calls.append((list(command), env))
        if command[0] == "systemd-run":
            self.service_active = True
            return ""
        if command[0] == "systemctl":
            if "--property=Version" in command:
                return "offline-systemd"
            return "LoadState=loaded\nActiveState=" + ("active" if self.service_active else "inactive") + "\n"
        self.assertEqual(command[0], "git", "offline tests must not contact another service")
        self.assertNotIn("push", command)
        self.assertNotIn("fetch", command)
        if "clone" in command:
            self.assertEqual(Path(command[-2]), self.root)
        return REAL_DEPLOY_RUN(root, command, env=env)

    def fake_subprocess(self, command, **options):
        if command[0] == "systemctl":
            self.calls.append((list(command), options.get("env")))
            return subprocess.CompletedProcess(command, 0, stdout="LoadState=loaded\nActiveState="
                + ("active" if self.service_active else "inactive") + "\n", stderr="")
        if command[0] == "git":
            self.assertNotIn("push", command)
            self.assertNotIn("fetch", command)
        else:
            self.assertEqual(Path(command[1]).name, "release.py")
            self.assertTrue(Path(command[1]).is_relative_to(self.parent))
            self.assertIn("--check", command)
            # The fixture's preflight output is irrelevant to assertions; keep
            # it off the test runner's terminal without running a real service.
            options.update(stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return REAL_SUBPROCESS_RUN(command, **options)

    def invoke(self, *arguments):
        output, errors = io.StringIO(), io.StringIO()
        def executable(value, label):
            self.assertNotEqual(label, "Lua 5.2", "new deployments must not require Lua 5.2")
            return str(Path(sys.executable).absolute()) if label == "Python" else "/offline/" + Path(value).name
        with patch.object(deploy, "run", side_effect=self.fake_run), \
                patch.object(deploy.subprocess, "run", side_effect=self.fake_subprocess), \
                patch.object(deploy, "executable", side_effect=executable), \
                contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            result = deploy.main(["--root", str(self.root), "--repository", REPOSITORY, *arguments])
        return result, output.getvalue() + errors.getvalue()

    def job(self):
        return deploy.find_job(self.root, "latest")

    def state(self):
        return deploy.load_state(self.job())

    def launches(self):
        return [(command, env) for command, env in self.calls if command[0] == "systemd-run"]

    def start(self):
        result, message = self.invoke("--tag", "v1.2.3")
        self.assertEqual(result, 0, message)
        return self.job()

    def finish_worker(self):
        with patch.object(deploy, "notify"), patch.object(deploy, "run", side_effect=self.fake_run), \
                patch.object(deploy.subprocess, "run", side_effect=self.fake_subprocess):
            result = deploy.worker(self.job())
        self.service_active = False
        return result

    def test_check_has_no_files_refs_service_or_credential_side_effects(self):
        before = {p.relative_to(self.root): p.read_bytes() for p in self.root.rglob("*") if p.is_file()}
        with patch.dict(os.environ, {"GH_TOKEN": "", "DISCORD_BOT_TOKEN": ""}), \
                patch.object(deploy, "check_service_manager", side_effect=AssertionError("check cannot start systemd")), \
                patch.object(deploy, "credentials", side_effect=AssertionError("check cannot load credentials")):
            result, message = self.invoke("--bump", "patch", "--check")
        self.assertEqual(result, 0, message)
        after = {p.relative_to(self.root): p.read_bytes() for p in self.root.rglob("*") if p.is_file()}
        self.assertEqual(before, after)
        self.assertEqual(self.launches(), [])

    def test_failed_preflight_never_bumps_starts_or_publishes(self):
        local = self.root / ".local"
        local.mkdir()
        (local / "fail-preflight").touch()
        result, message = self.invoke("--bump", "patch")
        self.assertEqual(result, 1, message)
        self.assertIn("preflight failed", message)
        self.assertEqual(self.git("rev-parse", "HEAD"), self.sha)
        self.assertEqual(self.git("tag", "--list"), "v1.2.3")
        self.assertFalse((local / "fixture-events.json").exists())
        self.assertEqual(self.launches(), [])

    def test_missing_credentials_or_service_manager_fail_before_preparation(self):
        with patch.dict(os.environ, {"DISCORD_BOT_TOKEN": ""}):
            result, message = self.invoke("--bump", "patch")
        self.assertEqual(result, 1, message)
        self.assertFalse(deploy.deployment_directory(self.root).exists())
        with patch.object(deploy, "check_service_manager", side_effect=deploy.DeployError("manager unavailable")):
            result, message = self.invoke("--bump", "patch")
        self.assertEqual(result, 1, message)
        self.assertIn("manager unavailable", message)
        self.assertFalse(deploy.deployment_directory(self.root).exists())
        self.assertEqual(self.git("rev-parse", "HEAD"), self.sha)
        self.assertEqual(self.launches(), [])

    def test_kickoff_owns_exact_independent_snapshot_then_allows_source_changes(self):
        job = self.start()
        state = self.state()
        snapshot = job / "checkout"
        self.assertEqual(state["status"], "queued")
        self.assertEqual(state["commit"], self.sha)
        self.assertEqual(state["attempt"], 1)
        self.assertIsNone(state["lua52"])
        self.assertEqual(self.git("rev-parse", "HEAD", root=snapshot), self.sha)
        self.assertEqual(self.git("remote", "get-url", "origin", root=snapshot),
                         "https://github.com/" + REPOSITORY + ".git")
        self.assertFalse((snapshot / ".git/objects/info/alternates").exists())
        object_path = Path(".git/objects") / self.sha[:2] / self.sha[2:]
        self.assertNotEqual((self.root / object_path).stat().st_ino, (snapshot / object_path).stat().st_ino)
        self.assertEqual((job / "worker.py").read_bytes(), Path(deploy.__file__).read_bytes())
        standalone = REAL_SUBPROCESS_RUN([sys.executable, "-I", str(job / "worker.py"), "--help"],
                                         cwd=job, text=True, capture_output=True)
        self.assertEqual(standalone.returncode, 0, standalone.stderr)
        self.assertFalse((snapshot / ".local/fixture-events.json").exists())
        (self.root / "release-payload.txt").write_text("later development must not ship\n")
        self.git("add", "release-payload.txt")
        self.git("commit", "-qm", "Continue developing after kickoff")
        later_commit = self.git("rev-parse", "HEAD")
        self.assertNotEqual(later_commit, self.sha)
        self.assertEqual(self.finish_worker(), 0)
        self.assertEqual(self.state()["status"], "succeeded")
        events = json.loads((snapshot / ".local/fixture-events.json").read_text())
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["cwd"], str(snapshot))
        self.assertEqual(events[0]["commit"], self.sha)
        self.assertEqual(events[0]["content"], "exact tagged payload\n")
        self.assertIn("v1.2.3", events[0]["arguments"])
        self.assertNotIn("--lua52", events[0]["arguments"])
        self.assertEqual(self.git("rev-parse", "HEAD"), later_commit)
        self.assertEqual(self.git("status", "--porcelain"), "")

    def test_duplicate_start_and_active_resume_cannot_launch_a_second_publisher(self):
        self.start()
        result, message = self.invoke("--tag", "v1.2.3")
        self.assertEqual(result, 1, message)
        self.assertIn("already exists", message)
        result, message = self.invoke("--resume")
        self.assertEqual(result, 1, message)
        self.assertIn("still active", message)
        self.assertEqual(len(self.launches()), 1)
        self.assertEqual(self.state()["attempt"], 1)
        self.assertEqual(self.state()["status"], "queued")

    def test_worker_lock_and_completed_state_prevent_duplicate_execution(self):
        job = self.start()
        with deploy.job_lock(job / ".lock"):
            result, message = self.invoke("--resume")
        self.assertEqual(result, 1, message)
        self.assertIn("already being prepared or running", message)
        self.assertEqual(len(self.launches()), 1)
        self.assertEqual(self.finish_worker(), 0)
        log = (job / "deploy.log").read_bytes()
        self.assertEqual(self.finish_worker(), 0)
        self.assertEqual((job / "deploy.log").read_bytes(), log)
        events = json.loads((job / "checkout/.local/fixture-events.json").read_text())
        self.assertEqual(len(events), 1)

    def test_snapshot_preflight_failure_creates_no_publisher_or_service(self):
        with patch.object(deploy, "preflight", side_effect=deploy.DeployError("offline preflight rejected snapshot")):
            result, message = self.invoke("--tag", "v1.2.3")
        self.assertEqual(result, 1, message)
        self.assertIn("preflight rejected", message)
        self.assertEqual(self.state()["status"], "failed")
        self.assertEqual(self.state()["attempt"], 0)
        self.assertFalse((self.job() / "checkout/.local/fixture-events.json").exists())
        self.assertEqual(self.launches(), [])
        with patch.object(deploy, "preflight", wraps=deploy.preflight) as checked:
            result, message = self.invoke("--resume")
        self.assertEqual(result, 0, message)
        self.assertEqual(checked.call_count, 1)
        self.assertEqual(self.state()["commit"], self.sha)
        self.assertEqual(self.state()["attempt"], 1)
        self.assertEqual(self.git("tag", "--list"), "v1.2.3")
        self.assertEqual(self.finish_worker(), 0)

    def fail_clone(self):
        original = self.fake_run
        def fail(root, command, *, env=None):
            if "clone" in command:
                raise deploy.DeployError("git failed (exit 1)")
            return original(root, command, env=env)
        with patch.object(self, "fake_run", side_effect=fail):
            result, message = self.invoke("--tag", "v1.2.3")
        self.assertEqual(result, 1, message)
        self.assertEqual(self.state()["status"], "failed")
        self.assertEqual(self.state()["attempt"], 0)
        self.assertFalse((self.job() / "checkout").exists())
        self.assertFalse((self.job() / "worker.py").exists())
        self.assertEqual(self.launches(), [])

    def test_clone_preparation_failure_can_resume_without_another_bump_or_tag(self):
        self.fail_clone()
        job = self.job()
        result, message = self.invoke("--resume")
        self.assertEqual(result, 0, message)
        self.assertEqual(self.job(), job)
        self.assertEqual(self.state()["commit"], self.sha)
        self.assertEqual(self.state()["attempt"], 1)
        self.assertEqual(self.git("rev-parse", "HEAD"), self.sha)
        self.assertEqual(self.git("tag", "--list"), "v1.2.3")
        self.assertTrue((job / "worker.py").is_file())
        self.assertEqual(self.finish_worker(), 0)

    def test_preparation_resume_refuses_a_moved_source_tag(self):
        self.fail_clone()
        (self.root / "release-payload.txt").write_text("replacement must not ship\n")
        self.git("add", "release-payload.txt")
        self.git("commit", "-qm", "Later replacement")
        self.git("tag", "-f", "-a", "v1.2.3", "-m", "Moved source tag")
        result, message = self.invoke("--resume")
        self.assertEqual(result, 1, message)
        self.assertEqual(self.state()["commit"], self.sha)
        self.assertEqual(self.state()["attempt"], 0)
        self.assertEqual(self.launches(), [])

    def test_preparation_resume_does_not_replace_a_modified_existing_snapshot(self):
        with patch.object(deploy, "launch_service", side_effect=deploy.DeployError("offline interruption before launch")):
            result, message = self.invoke("--tag", "v1.2.3")
        self.assertEqual(result, 1, message)
        payload = self.job() / "checkout/release-payload.txt"
        payload.write_text("preserve this unexpected local change\n")
        result, message = self.invoke("--resume")
        self.assertEqual(result, 1, message)
        self.assertEqual(payload.read_text(), "preserve this unexpected local change\n")
        self.assertEqual(self.state()["attempt"], 0)
        self.assertEqual(self.launches(), [])

    def test_service_start_failure_is_recorded_and_resumable(self):
        original = self.fake_run
        def fail_start(root, command, *, env=None):
            if command[0] == "systemd-run":
                raise deploy.DeployError("systemd-run failed (exit 1)")
            return original(root, command, env=env)
        with patch.object(self, "fake_run", side_effect=fail_start):
            result, message = self.invoke("--tag", "v1.2.3")
        self.assertEqual(result, 1, message)
        self.assertEqual(self.state()["status"], "failed")
        self.assertEqual(self.state()["attempt"], 1)
        self.assertFalse((self.job() / "checkout/.local/fixture-events.json").exists())
        self.service_active = False
        result, message = self.invoke("--resume")
        self.assertEqual(result, 0, message)
        self.assertEqual(self.state()["attempt"], 2)
        self.assertEqual(self.finish_worker(), 0)

    def test_worker_failure_resumes_same_checkout_tag_and_log_without_bumping(self):
        job = self.start()
        marker = job / "checkout/.local/fail-worker"
        marker.parent.mkdir(exist_ok=True)
        marker.touch()
        self.assertEqual(self.finish_worker(), 9)
        failed = self.state()
        self.assertEqual(failed["status"], "failed")
        self.assertEqual(failed["exit_code"], 9)
        self.assertIn("exit 9", failed["error"])
        log = job / "deploy.log"
        first_log = log.read_text()
        marker.unlink()
        result, message = self.invoke("--resume")
        self.assertEqual(result, 0, message)
        self.assertEqual(self.job(), job)
        self.assertEqual(self.state()["attempt"], 2)
        self.assertNotEqual(self.state()["unit"], failed["unit"])
        self.assertEqual(self.finish_worker(), 0)
        self.assertEqual(self.state()["commit"], self.sha)
        self.assertEqual(self.state()["status"], "succeeded")
        self.assertTrue(log.read_text().startswith(first_log))
        self.assertEqual(self.git("tag", "--list"), "v1.2.3")
        events = json.loads((job / "checkout/.local/fixture-events.json").read_text())
        self.assertEqual([event["commit"] for event in events], [self.sha, self.sha])
        launch_count = len(self.launches())
        with patch.dict(os.environ, {"GH_TOKEN": "", "DISCORD_BOT_TOKEN": ""}):
            result, message = self.invoke("--resume")
        self.assertEqual(result, 0, message)
        self.assertEqual(len(self.launches()), launch_count)

    def test_credential_values_stay_out_of_arguments_state_worker_and_logs(self):
        job = self.start()
        command, environment = self.launches()[0]
        self.assertIn("--setenv=GH_TOKEN", command)
        self.assertIn("--setenv=DISCORD_BOT_TOKEN", command)
        self.assertIn("--setenv=CURSEFORGE_API_TOKEN", command)
        self.assertEqual(environment["GH_TOKEN"], GITHUB_SECRET)
        self.assertEqual(environment["DISCORD_BOT_TOKEN"], DISCORD_SECRET)
        self.assertEqual(environment["CURSEFORGE_API_TOKEN"], CURSEFORGE_SECRET)
        self.assertNotIn("--scope", command)
        self.assertNotIn("--wait", command)
        self.assertEqual(self.finish_worker(), 0)
        result, message = self.invoke("--status")
        self.assertEqual(result, 0, message)
        text = "\n".join(command) + message
        for relative in ("state.json", "deploy.log", "worker.py"):
            text += (job / relative).read_text()
        for secret in (GITHUB_SECRET, DISCORD_SECRET, CURSEFORGE_SECRET):
            self.assertNotIn(secret, text)
        self.assertIn("[REDACTED]", (job / "deploy.log").read_text())
        self.assertEqual((job / "deploy.log").stat().st_mode & 0o777, 0o600)

    def test_failed_commands_never_repeat_captured_credential_output(self):
        response = subprocess.CompletedProcess(["systemd-run"], 5, stdout=GITHUB_SECRET, stderr=DISCORD_SECRET)
        with patch.object(deploy.subprocess, "run", return_value=response):
            with self.assertRaises(deploy.DeployError) as raised:
                deploy.run(self.root, ["systemd-run", "--user"])
        self.assertIn("exit 5", str(raised.exception))
        self.assertNotIn(GITHUB_SECRET, str(raised.exception))
        self.assertNotIn(DISCORD_SECRET, str(raised.exception))

    def test_status_detects_stopped_service_without_network_or_credentials(self):
        self.start()
        self.service_active = False
        self.calls.clear()
        with patch.dict(os.environ, {"GH_TOKEN": "", "DISCORD_BOT_TOKEN": ""}), \
                patch.object(deploy, "credentials", side_effect=AssertionError("status cannot load credentials")):
            result, message = self.invoke("--status")
        self.assertEqual(result, 0, message)
        self.assertEqual(self.state()["status"], "interrupted")
        self.assertIn("--resume", message)
        self.assertTrue(all(command[0] == "systemctl" for command, _ in self.calls))

    def test_dirty_snapshot_blocks_worker_and_resume_before_publication(self):
        job = self.start()
        (job / "checkout/release-payload.txt").write_text("unexpected change\n")
        self.assertEqual(self.finish_worker(), 1)
        self.assertEqual(self.state()["status"], "failed")
        self.assertFalse((job / "checkout/.local/fixture-events.json").exists())
        result, message = self.invoke("--resume")
        self.assertEqual(result, 1, message)
        self.assertIn("must remain clean", message)
        self.assertEqual(len(self.launches()), 1)

    def test_matching_receipt_imports_and_wrong_receipt_prevents_launch(self):
        receipt = self.parent / "validation.json"
        receipt.write_text(json.dumps({"schema": 1, "commit": self.sha, "passed": True,
            "runner_sha256": hashlib.sha256((self.root / "scripts/validate_release.py").read_bytes()).hexdigest()}))
        result, message = self.invoke("--tag", "v1.2.3", "--receipt", str(receipt))
        self.assertEqual(result, 0, message)
        imported = self.job() / "checkout/.local/releases/v1.2.3/validation.json"
        self.assertEqual(json.loads(imported.read_text()), json.loads(receipt.read_text()))
        self.service_active = False
        receipt.write_text(json.dumps({"schema": 1, "commit": "f" * 40, "passed": True,
                                      "runner_sha256": "invalid"}))
        result, message = self.invoke("--resume", "--receipt", str(receipt))
        self.assertEqual(result, 1, message)
        self.assertIn("does not certify", message)
        self.assertEqual(len(self.launches()), 1)


if __name__ == "__main__":
    unittest.main()
