#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
# See LICENSING.md for scope and preserved third-party notices.
"""Local release contracts with real temporary Git and packages, no live services."""

import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True

import release

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = release.discord.DEFAULT_REPOSITORY
REAL_RUN = release.run


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="questtogether-release-")
        self.addCleanup(temporary.cleanup)
        self.parent = Path(temporary.name)
        self.root = self.parent / "source with spaces"
        self.root.mkdir()
        env = {key: value for key, value in os.environ.items()
               if not key.startswith("GIT_") and key not in
               {"GH_TOKEN", "GITHUB_TOKEN", "DISCORD_BOT_TOKEN", "GH_HOST"}}
        env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull,
                   GIT_ALLOW_PROTOCOL="file", GIT_TERMINAL_PROMPT="0",
                   GIT_AUTHOR_NAME="Offline release test", GIT_AUTHOR_EMAIL="test@example.invalid",
                   GIT_COMMITTER_NAME="Offline release test", GIT_COMMITTER_EMAIL="test@example.invalid",
                   GH_TOKEN="offline-github-token", DISCORD_BOT_TOKEN="offline-discord-token")
        environment = patch.dict(os.environ, env, clear=True)
        environment.start()
        self.addCleanup(environment.stop)
        for name in release.package.DOCUMENTS:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("Offline fixture: " + name + "\n")
        (self.root / "LICENSE").write_bytes((ROOT / "LICENSE").read_bytes())
        (self.root / "Libs/libchev/manifest.json").write_text(json.dumps(
            {"schema": 1, "revision": "a" * 40, "files": {}}))
        (self.root / ".gitignore").write_text(".local/\n")
        (self.root / "Core.lua").write_text("-- Offline fixture\n")
        for name in ("bump_version.sh", "check_release_notes.py"):
            shutil.copyfile(ROOT / "scripts" / name, self.root / "scripts" / name)
        self.write_notes("1.2.3", "Share eligible quests with your party.")
        self.git("init", "-q")
        self.git("checkout", "-qb", "main")
        self.git("add", ".")
        self.git("commit", "-qm", "Baseline")
        self.git("tag", "-a", "v1.2.3", "-m", "Baseline")
        self.git("remote", "add", "origin", "https://github.com/" + REPOSITORY + ".git")
        self.remote_branch = self.git("rev-parse", "HEAD")
        self.calls = []
        self.api_calls = []
        self.existing = None
        self.failure = None
        self.bad_receipt = False
        self.remote_sha = None
        self.private = False
        self.created = False
        self.draft_assets = []
        self.creation_payload = None
        self.stale_listing = False

    def git(self, *arguments):
        return REAL_RUN(self.root, ["git", "-c", "commit.gpgsign=false", "-c",
                        "core.hooksPath=" + os.devnull, *arguments], capture=True)

    def write_notes(self, version, item):
        notes = {"version": version, "welcome": "QuestTogether release notes.",
                 "sections": [{"title": "Party quests", "items": [item]}]}
        (self.root / "QuestTogether.toc").write_text(
            "## Version: " + version + "\n## X-License: GPL-3.0-only\nCore.lua\nReleaseNotes.lua\n")
        (self.root / "release_notes.json").write_text(json.dumps(notes))
        (self.root / "ReleaseNotes.lua").write_text(release.discord.render_lua(notes))
        return notes

    def prepare(self, tag="v1.2.4", *, localized=False):
        self.write_notes(tag[1:], "Compare eligible quests with a selected player.")
        if localized:
            with (self.root / "QuestTogether.toc").open("a") as handle:
                handle.write("LocalizedReleaseNotes.lua\n")
            (self.root / "LocalizedReleaseNotes.lua").write_text("-- Offline localized payload\n")
        self.git("add", ".")
        self.git("commit", "-qm", "Prepared release")
        self.git("tag", "-a", tag, "-m", "Prepared release")
        return self.git("rev-parse", "HEAD")

    def current_tag(self):
        return "v" + release.discord.toc_version((self.root / "QuestTogether.toc").read_text())

    def archive(self):
        tag = self.current_tag()
        return self.root / ".local/releases" / tag / ("QuestTogether-" + tag + ".zip")

    def receipt(self, sha=None):
        return {"schema": 1, "commit": sha or self.git("rev-parse", "HEAD"), "passed": True,
                "runner_sha256": release.validate_release.runner_sha256()}

    def fake_process(self, root, arguments, *, capture=False, env=None):
        arguments = list(map(str, arguments))
        self.calls.append(arguments)
        if "scripts/validate_release.py" in " ".join(arguments):
            if self.failure == "validate":
                raise release.ReleaseError("injected validation failure")
            path = Path(arguments[arguments.index("--receipt") + 1])
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(self.receipt("b" * 40 if self.bad_receipt else None)))
            return None
        if arguments[:2] == ["git", "push"]:
            if self.failure == "push":
                raise release.ReleaseError("injected push failure")
            self.assertIn("--atomic", arguments)
            self.assertIn("refs/tags/" + self.current_tag(), arguments)
            return None
        if arguments[:2] == ["git", "ls-remote"]:
            self.assertEqual(arguments[2:], ["--refs", "origin", "refs/heads/main"])
            return self.remote_branch + "\trefs/heads/main"
        if arguments[:2] == ["gh", "release"]:
            self.assertEqual(env["GH_TOKEN"], "offline-github-token")
            if self.failure == arguments[2]:
                raise release.ReleaseError("injected " + arguments[2] + " failure")
            self.assertNotIn("--clobber", arguments)
            if arguments[2] == "create":
                self.created = True
            elif arguments[2] == "download":
                name = arguments[arguments.index("--pattern") + 1]
                destination = Path(arguments[arguments.index("--dir") + 1]) / name
                destination.write_bytes((self.archive().parent / name).read_bytes())
            return None
        if len(arguments) > 1 and arguments[1] == "scripts/discord_changelog.py":
            self.assertIn("--post", arguments)
            self.assertIn("--all-locales", arguments)
            return None
        if arguments[:3] == ["gh", "auth", "token"]:
            raise release.ReleaseError("injected missing local authentication")
        if arguments[0] == "git":
            self.assertIn(arguments[1], {"remote", "rev-parse", "status", "branch", "archive",
                                         "check-ref-format", "cat-file"})
        else:
            self.assertEqual(arguments[:2], ["bash", "scripts/bump_version.sh"])
            self.assertTrue("--check" in arguments or "--local-only" in arguments)
        result = REAL_RUN(root, arguments, capture=True, env=env)
        return result if capture else None

    def request(self, path, method="GET", payload=None):
        self.api_calls.append(path)
        prefix = "/repos/" + REPOSITORY
        tag = self.current_tag()
        if method == "POST":
            self.assertEqual(path, prefix + "/releases")
            self.assertEqual(payload["tag_name"], tag)
            self.assertEqual(payload["target_commitish"], self.git("rev-parse", "HEAD"))
            self.assertTrue(payload["draft"])
            self.creation_payload = payload
            self.calls.append(["api", "create"])
            self.created = True
            return self.request(prefix + "/releases/123")
        self.assertEqual(method, "GET")
        if path == prefix:
            return {"full_name": REPOSITORY, "private": self.private}
        if path == prefix + "/git/ref/tags/" + tag:
            return {"ref": "refs/tags/" + tag,
                    "object": {"sha": self.remote_sha or self.git("rev-parse", "HEAD"), "type": "commit"}}
        if path.startswith(prefix + "/releases?per_page=100&page="):
            if self.stale_listing:
                return []
            return ([self.request(prefix + "/releases/123")]
                    if self.existing is not None or self.created else [])
        if path in (prefix + "/releases/tags/" + tag, prefix + "/releases/123"):
            if self.existing is None and not self.created:
                raise release.discord.APIHTTPError("GET", 404)
            if path.endswith("/tags/" + tag) and self.existing != "public":
                raise release.discord.APIHTTPError("GET", 404)
            archive = self.archive()
            draft = self.existing != "public"
            assets = self.draft_assets if draft else [
                {"name": archive.name, "state": "uploaded", "size": archive.stat().st_size,
                 "browser_download_url": "https://github.com/" + REPOSITORY
                 + "/releases/download/" + tag + "/" + archive.name}]
            return {"id": 123, "tag_name": tag, "draft": draft,
                    "published_at": "2026-11-17T00:00:00Z" if self.existing == "public" else None,
                    "html_url": "https://github.com/" + REPOSITORY + "/releases/tag/"
                                + ("untagged-private-draft" if draft else tag), "assets": assets}
        raise AssertionError("unexpected API request: " + path)

    def public_download(self, request, timeout=None):
        tag = self.current_tag()
        expected = "https://github.com/" + REPOSITORY + "/releases/download/" + tag + "/" + self.archive().name
        self.assertEqual(request.full_url, expected)
        self.assertFalse(request.has_header("Authorization"))
        result = io.BytesIO(self.archive().read_bytes())
        result.code = 200
        return result

    def invoke(self, *arguments):
        self.created = False
        output, errors = io.StringIO(), io.StringIO()
        with patch.object(release, "run", side_effect=self.fake_process), \
                patch.object(release.discord, "API", return_value=self), \
                patch.object(release.discord.urllib.request.OpenerDirector, "open", self.public_download), \
                contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            result = release.main(["--root", str(self.root), *arguments])
        return result, output.getvalue() + errors.getvalue()

    def stages(self):
        stages = []
        for command in self.calls:
            if "--local-only" in command:
                stages.append("bump")
            elif "scripts/validate_release.py" in " ".join(command):
                stages.append("validate")
            elif command[:2] == ["git", "archive"]:
                stages.append("package")
            elif command[:2] == ["git", "push"]:
                stages.append("push")
            elif command[:2] == ["gh", "release"]:
                stages.append(command[2])
            elif command == ["api", "create"]:
                stages.append("create")
            elif len(command) > 1 and command[1] == "scripts/discord_changelog.py":
                stages.append("announce")
        return stages

    def test_check_has_no_files_refs_credentials_or_network_side_effects(self):
        self.write_notes("1.2.3", "Compare eligible quests with a selected player.")
        os.utime(self.root / "Core.lua", (1, 1))  # Force stale stat metadata without changing content.
        before = {p.relative_to(self.root): p.read_bytes() for p in self.root.rglob("*") if p.is_file()}
        with patch.dict(os.environ, {"GH_TOKEN": "", "DISCORD_BOT_TOKEN": ""}):
            result, message = self.invoke("--bump", "patch", "--check")
        self.assertEqual(result, 0, message)
        after = {p.relative_to(self.root): p.read_bytes() for p in self.root.rglob("*") if p.is_file()}
        changed = [str(path) for path in before.keys() | after.keys() if before.get(path) != after.get(path)]
        self.assertEqual(changed, [])
        self.assertEqual(self.stages(), [])
        self.assertEqual(self.api_calls, [])

    def test_local_bump_validates_packages_pushes_publishes_then_announces(self):
        self.write_notes("1.2.3", "Compare eligible quests with a selected player.")
        result, message = self.invoke("--bump", "patch")
        self.assertEqual(result, 0, message)
        self.assertEqual(self.stages(), ["bump", "validate", "package", "push", "create", "upload", "edit", "announce"])
        self.assertEqual(self.git("status", "--porcelain"), "")
        self.assertEqual(self.git("cat-file", "-t", "v1.2.4"), "tag")
        manifest = release.package.verify_archive(self.archive().read_bytes())
        self.assertEqual(manifest["sourceCommit"], self.git("rev-parse", "HEAD"))
        self.assertTrue(self.creation_payload["draft"])
        self.assertTrue(any("--draft=false" in command for command in self.calls if command[:3] == ["gh", "release", "edit"]))
        self.assertFalse(any("actions/" in path or "curseforge" in path.casefold() for path in self.api_calls))

    def test_beta_and_stable_release_flags_follow_the_exact_tag(self):
        for tag, expected in (("v1.2.4", "false"), ("v1.2.4-beta.1", "true"), ("v1.2.4-alpha.1", "true")):
            with self.subTest(tag=tag):
                self.prepare(tag)
                self.calls.clear()
                result, message = self.invoke("--tag", tag)
                self.assertEqual(result, 0, message)
                edit = next(command for command in self.calls if command[:3] == ["gh", "release", "edit"])
                self.assertEqual(self.creation_payload["prerelease"], expected == "true")
                self.assertIn("--prerelease=" + expected, edit)

    def test_new_draft_uses_creation_identity_when_listing_is_stale(self):
        self.prepare()
        self.stale_listing = True
        result, message = self.invoke("--tag", "v1.2.4")
        self.assertEqual(result, 0, message)
        listings = [path for path in self.api_calls if "/releases?" in path]
        self.assertEqual(len(listings), 1, "creation must not wait for listing visibility")
        self.assertEqual(self.stages(), ["validate", "package", "push", "create", "upload", "edit", "announce"])

    def test_beta_bumps_keep_stable_baseline_and_increment_prerelease_sequence(self):
        for expected, item in (("v1.3.0-beta.1", "Compare eligible quests with a selected player."),
                               ("v1.3.0-beta.2", "Show quest objectives beside the party log.")):
            with self.subTest(tag=expected):
                self.write_notes(self.current_tag()[1:], item)
                result, message = self.invoke("--bump", "minor", "--channel", "beta")
                self.assertEqual(result, 0, message)
                self.assertEqual(self.current_tag(), expected)
                self.assertEqual(self.git("cat-file", "-t", expected), "tag")

    def test_explicit_note_reuse_is_forwarded_and_recorded_for_only_the_new_release(self):
        result, message = self.invoke("--bump", "patch", "--reuse-notes")
        self.assertEqual(result, 0, message)
        reuse = json.loads((self.root / "release_notes_reuse.json").read_text())
        self.assertEqual(reuse, {"schema": 1, "releases": {"1.2.4": "1.2.3"}})

    def test_failed_validation_or_wrong_receipt_stops_before_push(self):
        self.prepare()
        for failure, bad_receipt in (("validate", False), (None, True)):
            with self.subTest(failure=failure, bad_receipt=bad_receipt):
                self.failure, self.bad_receipt = failure, bad_receipt
                self.calls.clear()
                result, message = self.invoke("--tag", "v1.2.4")
                self.assertEqual(result, 1, message)
                self.assertEqual(self.stages(), ["validate"])
                self.assertEqual(self.api_calls, [])

    def test_failed_push_stops_before_github_and_discord(self):
        self.prepare()
        self.failure = "push"
        result, message = self.invoke("--tag", "v1.2.4")
        self.assertEqual(result, 1, message)
        self.assertEqual(self.stages(), ["validate", "package", "push"])
        self.assertEqual(self.api_calls, [])

    def test_explicit_source_branch_is_published_from_detached_checkout(self):
        sha = self.prepare()
        self.git("checkout", "-q", "--detach", sha)
        result, message = self.invoke("--tag", "v1.2.4", "--branch", "main")
        self.assertEqual(result, 0, message)
        push = next(command for command in self.calls if command[:2] == ["git", "push"])
        self.assertIn(sha + ":refs/heads/main", push)
        self.assertEqual(self.git("branch", "--show-current"), "")

    def test_draft_resume_uploads_before_publish_and_failed_upload_never_announces(self):
        self.prepare()
        self.existing, self.failure = "draft", "upload"
        result, message = self.invoke("--tag", "v1.2.4")
        self.assertEqual(result, 1, message)
        self.assertEqual(self.stages(), ["validate", "package", "push", "upload"])
        self.calls.clear()
        self.failure = None
        result, message = self.invoke("--tag", "v1.2.4")
        self.assertEqual(result, 0, message)
        self.assertEqual(self.stages(), ["package", "push", "upload", "edit", "announce"])
        self.assertIn("/repos/" + REPOSITORY + "/releases/123", self.api_calls)

    def test_draft_lookup_paginates_and_rejects_duplicates_or_incomplete_listings(self):
        class API:
            def __init__(self, pages):
                self.pages = pages
                self.calls = []

            def request(self, path):
                self.calls.append(path)
                if "/tags/" in path:
                    raise release.discord.APIHTTPError("GET", 404)
                return self.pages[min(int(path.rsplit("=", 1)[1]) - 1, len(self.pages) - 1)]

        other = [{"tag_name": "v0.0." + str(index)} for index in range(100)]
        draft = {"id": 123, "tag_name": "v1.2.4", "draft": True}
        api = API([other, [draft]])
        self.assertEqual(release.find_github_release(api, "/repos/test/repo", "v1.2.4"), draft)
        self.assertTrue(api.calls[-1].endswith("page=2"))
        for pages, message in (([[draft, draft]], "multiple"), ([other], "lookup limit"), ([[None]], "invalid")):
            with self.subTest(message=message), self.assertRaisesRegex(release.ReleaseError, message):
                release.find_github_release(API(pages), "/repos/test/repo", "v1.2.4")

    def test_draft_resume_keeps_matching_assets_and_uploads_only_missing_files(self):
        sha = self.prepare()
        output = self.archive().parent
        output.mkdir(parents=True)
        artifacts = release.build_artifacts(self.root, "v1.2.4", sha, output)
        self.existing = "draft"
        self.draft_assets = [{"name": artifacts[0].name, "state": "uploaded",
                              "digest": "sha256:" + hashlib.sha256(artifacts[0].read_bytes()).hexdigest()}]
        result, message = self.invoke("--tag", "v1.2.4")
        self.assertEqual(result, 0, message)
        upload = next(command for command in self.calls if command[:3] == ["gh", "release", "upload"])
        self.assertNotIn(str(artifacts[0]), upload)
        self.assertTrue(all(str(path) in upload for path in artifacts[1:]))

    def test_draft_asset_without_digest_is_verified_once_and_mismatch_stops_publication(self):
        sha = self.prepare()
        output = self.archive().parent
        output.mkdir(parents=True)
        artifacts = release.build_artifacts(self.root, "v1.2.4", sha, output)
        self.existing = "draft"
        self.draft_assets = [{"name": path.name, "state": "uploaded"} for path in artifacts]
        result, message = self.invoke("--tag", "v1.2.4")
        self.assertEqual(result, 0, message)
        self.assertEqual(self.stages().count("download"), len(artifacts))
        self.assertNotIn("upload", self.stages())
        self.draft_assets[0]["digest"] = "sha256:" + "f" * 64
        self.calls.clear()
        result, message = self.invoke("--tag", "v1.2.4")
        self.assertEqual(result, 1, message)
        self.assertIn("differs from the local release", message)
        self.assertFalse(any(stage in self.stages() for stage in ("upload", "edit", "announce")))

    def test_overlapping_publication_is_rejected_before_mutation_and_lock_is_released(self):
        self.write_notes("1.2.3", "Compare eligible quests with a selected player.")
        with release.publication_lock(self.root):
            result, message = self.invoke("--bump", "patch")
        self.assertEqual(result, 1, message)
        self.assertIn("already running", message)
        self.assertEqual(self.stages(), [])
        result, message = self.invoke("--bump", "patch")
        self.assertEqual(result, 0, message)

    def test_public_resume_preserves_release_and_delegates_missing_parts_to_discord(self):
        self.prepare(localized=True)
        self.existing = "public"
        result, message = self.invoke("--tag", "v1.2.4")
        self.assertEqual(result, 0, message)
        self.assertEqual(self.stages(), ["validate", "package", "push", "announce"])
        self.assertIn("already published", message)

    def test_receipt_reuse_requires_exact_commit_runner_hash_and_passed_shape(self):
        sha = self.prepare()
        receipt = self.root / ".local/releases/v1.2.4/validation.json"
        receipt.parent.mkdir(parents=True)
        for update in ({}, {"commit": "b" * 40}, {"runner_sha256": "b" * 64}, {"passed": False}, {"extra": True}):
            with self.subTest(update=update):
                receipt.write_text(json.dumps({**self.receipt(sha), **update}))
                self.calls.clear()
                result, message = self.invoke("--tag", "v1.2.4")
                self.assertEqual(result, 0, message)
                self.assertEqual("validate" in self.stages(), bool(update))

    def test_wrong_origin_or_dirty_or_nonexact_checkout_stops_before_publication(self):
        self.prepare()
        self.git("remote", "set-url", "origin", "https://github.com/example/unexpected.git")
        result, message = self.invoke("--tag", "v1.2.4")
        self.assertEqual(result, 1, message)
        self.assertIn("origin", message)
        self.git("remote", "set-url", "origin", "https://github.com/" + REPOSITORY)
        (self.root / "unexpected.txt").write_text("Unrelated work")
        result, message = self.invoke("--tag", "v1.2.4")
        self.assertEqual(result, 1, message)
        self.assertIn("clean checkout", message)
        self.git("add", "unexpected.txt")
        self.git("commit", "-qm", "Later commit")
        result, message = self.invoke("--tag", "v1.2.4")
        self.assertEqual(result, 1, message)
        self.assertIn("exact tag", message)
        self.assertEqual(self.stages(), [])
        self.assertEqual(self.api_calls, [])

    def test_credential_failure_occurs_before_local_bump(self):
        self.write_notes("1.2.3", "Compare eligible quests with a selected player.")
        head = self.git("rev-parse", "HEAD")
        for values in ({"DISCORD_BOT_TOKEN": ""}, {"GH_TOKEN": "", "GITHUB_TOKEN": ""}):
            with self.subTest(values=values), patch.dict(os.environ, values):
                self.calls.clear()
                result, message = self.invoke("--bump", "patch")
                self.assertEqual(result, 1, message)
                self.assertEqual(self.stages(), [])
                self.assertEqual(self.git("rev-parse", "HEAD"), head)
                self.assertEqual(self.git("tag", "--list"), "v1.2.3")

    def test_remote_tag_mismatch_or_private_repository_never_mutates_release(self):
        self.prepare()
        for remote_sha, private in (("b" * 40, False), (None, True)):
            with self.subTest(private=private):
                self.remote_sha, self.private = remote_sha, private
                self.calls.clear()
                result, message = self.invoke("--tag", "v1.2.4")
                self.assertEqual(result, 1, message)
                self.assertFalse(any(stage in self.stages() for stage in ("create", "upload", "edit", "announce")))

    def test_release_body_preserves_tip_text_and_exact_source_commit(self):
        notes = self.write_notes("1.2.4", "Compare eligible quests with a selected player.")
        notes["sections"][0]["tip"] = {"label": "Tip:", "text": "Try /qt tip."}
        (self.root / "release_notes.json").write_text(json.dumps(notes))
        (self.root / "ReleaseNotes.lua").write_text(release.discord.render_lua(notes))
        self.git("add", ".")
        self.git("commit", "-qm", "Notes with a tip")
        self.git("tag", "v1.2.4")
        sha = self.git("rev-parse", "HEAD")
        body = release.release_body(self.root, "v1.2.4", sha, REPOSITORY)
        self.assertIn("Try /qt tip.", body)
        self.assertIn("/tree/" + sha, body)
        self.assertIn("GPL-3.0-only", body)


class RemoteBranchPublicationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="questtogether-remote-release-")
        self.addCleanup(temporary.cleanup)
        self.parent = Path(temporary.name)
        self.root = self.parent / "release checkout"
        self.remote = self.parent / "origin.git"
        self.worker = self.parent / "continuing work"
        environment = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        environment.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull,
                           GIT_ALLOW_PROTOCOL="file", GIT_TERMINAL_PROMPT="0",
                           GIT_AUTHOR_NAME="Offline test", GIT_AUTHOR_EMAIL="test@example.invalid",
                           GIT_COMMITTER_NAME="Offline test", GIT_COMMITTER_EMAIL="test@example.invalid")
        patcher = patch.dict(os.environ, environment, clear=True)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.root.mkdir()
        self.git(self.root, "init", "-q", "-b", "main")
        self.commit(self.root, "baseline")
        self.baseline = self.git(self.root, "rev-parse", "HEAD")
        self.git(self.parent, "init", "-q", "--bare", str(self.remote))
        self.git(self.root, "remote", "add", "origin", str(self.remote))
        self.git(self.root, "push", "-q", "origin", "main")
        self.git(self.parent, "clone", "-q", "-b", "main", str(self.remote), str(self.worker))
        self.commit(self.root, "release")
        self.sha = self.git(self.root, "rev-parse", "HEAD")
        self.git(self.root, "tag", "-a", "v1.2.4", "-m", "Release")
        self.git(self.root, "checkout", "-q", "--detach", self.sha)
        self.calls = []

    def git(self, root, *args):
        return REAL_RUN(root, ["git", "-c", "commit.gpgsign=false", "-c",
                              "core.hooksPath=" + os.devnull, *args], capture=True)

    def commit(self, root, value):
        (root / "work.txt").write_text(value)
        self.git(root, "add", "work.txt")
        self.git(root, "commit", "-qm", value)
        return self.git(root, "rev-parse", "HEAD")

    def advance_remote(self, *, diverge=False):
        if not diverge:
            self.git(self.worker, "fetch", "-q", "--no-tags", str(self.root), self.sha)
            self.git(self.worker, "reset", "-q", "--hard", self.sha)
        sha = self.commit(self.worker, "continued work")
        self.git(self.worker, "push", "-q", "origin", "main")
        return sha

    def publish(self, before_push=None, branch="main"):
        def execute(root, arguments, *, capture=False, env=None):
            self.calls.append(list(arguments))
            if arguments[:2] == ["git", "push"] and before_push:
                before_push()
            result = REAL_RUN(root, arguments, capture=True, env=env)
            return result if capture else None

        with patch.object(release, "run", side_effect=execute), contextlib.redirect_stdout(io.StringIO()):
            release.push_release_refs(self.root, "v1.2.4", self.sha, branch, dict(os.environ))

    def remote_ref(self, ref):
        return self.git(self.remote, "rev-parse", "--verify", ref)

    def pushes(self):
        return [command for command in self.calls if command[:2] == ["git", "push"]]

    def assert_tag_absent(self):
        self.assertEqual(self.git(self.remote, "tag", "--list", "v1.2.4"), "")

    def test_ancestor_branch_and_tag_are_published_atomically_from_detached_checkout(self):
        self.publish()
        self.assertEqual(self.remote_ref("main"), self.sha)
        self.assertEqual(self.remote_ref("refs/tags/v1.2.4^{commit}"), self.sha)
        self.assertEqual(self.pushes(), [["git", "push", "--atomic", "origin",
                                         self.sha + ":refs/heads/main", "refs/tags/v1.2.4"]])
        self.assertEqual(self.git(self.root, "branch", "--show-current"), "")

    def test_newer_remote_commit_is_fetched_exactly_and_preserved_while_tag_is_published(self):
        newer = self.advance_remote()
        refs_before = self.git(self.root, "show-ref")
        fetch_head = self.root / ".git/FETCH_HEAD"
        fetch_head.write_text("preserve this fetch state\n")
        self.publish()
        self.assertEqual(self.remote_ref("main"), newer)
        self.assertEqual(self.remote_ref("refs/tags/v1.2.4^{commit}"), self.sha)
        self.assertEqual(self.git(self.root, "show-ref"), refs_before)
        self.assertEqual(fetch_head.read_text(), "preserve this fetch state\n")
        fetch = next(command for command in self.calls if command[:2] == ["git", "fetch"])
        self.assertEqual(fetch[-1], newer)
        self.assertIn("--no-write-fetch-head", fetch)
        self.assertEqual(self.pushes(), [["git", "push", "--atomic", "origin", "refs/tags/v1.2.4"]])

    def test_remote_at_release_commit_only_receives_tag(self):
        self.git(self.root, "push", "-q", "origin", self.sha + ":refs/heads/main")
        self.publish()
        self.assertEqual(self.pushes(), [["git", "push", "--atomic", "origin", "refs/tags/v1.2.4"]])

    def test_divergent_branch_stops_before_any_tag_push(self):
        divergent = self.advance_remote(diverge=True)
        with self.assertRaisesRegex(release.ReleaseError, "diverged.*Reconcile"):
            self.publish()
        self.assertEqual(self.remote_ref("main"), divergent)
        self.assertEqual(self.pushes(), [])
        self.assert_tag_absent()

    def test_unrelated_branch_stops_before_any_tag_push(self):
        self.git(self.worker, "checkout", "-q", "--orphan", "unrelated")
        unrelated = self.commit(self.worker, "unrelated history")
        self.git(self.worker, "push", "-q", "origin", "unrelated")
        with self.assertRaisesRegex(release.ReleaseError, "diverged"):
            self.publish(branch="unrelated")
        self.assertEqual(self.remote_ref("unrelated"), unrelated)
        self.assertEqual(self.pushes(), [])
        self.assert_tag_absent()

    def test_racing_descendant_retries_once_as_tag_only_and_preserves_new_work(self):
        advanced = []

        def race():
            if not advanced:
                advanced.append(self.advance_remote())

        self.publish(before_push=race)
        self.assertEqual(self.remote_ref("main"), advanced[0])
        self.assertEqual(self.remote_ref("refs/tags/v1.2.4^{commit}"), self.sha)
        self.assertEqual(len(self.pushes()), 2)
        self.assertEqual(self.pushes()[-1], ["git", "push", "--atomic", "origin", "refs/tags/v1.2.4"])

    def test_racing_divergence_rejects_atomic_push_without_partial_tag(self):
        advanced = []

        def race():
            advanced.append(self.advance_remote(diverge=True))

        with self.assertRaisesRegex(release.ReleaseError, "diverged"):
            self.publish(before_push=race)
        self.assertEqual(self.remote_ref("main"), advanced[0])
        self.assertEqual(len(self.pushes()), 1)
        self.assert_tag_absent()

    def test_conflicting_immutable_tag_rejects_branch_and_tag_together(self):
        self.git(self.worker, "tag", "v1.2.4")
        self.git(self.worker, "push", "-q", "origin", "refs/tags/v1.2.4")
        with self.assertRaises(release.ReleaseError):
            self.publish()
        self.assertEqual(self.remote_ref("main"), self.baseline)
        self.assertEqual(self.remote_ref("refs/tags/v1.2.4^{commit}"), self.baseline)
        self.assertEqual(len(self.pushes()), 1)

    def test_missing_branch_is_created_with_tag(self):
        self.publish(branch="new-release-branch")
        self.assertEqual(self.remote_ref("new-release-branch"), self.sha)
        self.assertEqual(self.remote_ref("refs/tags/v1.2.4^{commit}"), self.sha)
        self.assertEqual(self.remote_ref("main"), self.baseline)

    def test_detached_source_without_branch_only_publishes_tag(self):
        self.publish(branch="")
        self.assertEqual(self.remote_ref("main"), self.baseline)
        self.assertEqual(self.remote_ref("refs/tags/v1.2.4^{commit}"), self.sha)
        self.assertFalse(any(command[1] in {"ls-remote", "fetch"} for command in self.calls))


def load_tests(loader, tests, pattern):
    import test_deploy
    tests.addTests(loader.loadTestsFromModule(test_deploy))
    return tests


if __name__ == "__main__":
    unittest.main()
