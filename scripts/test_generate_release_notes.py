#!/usr/bin/env python3
"""Offline generator contracts: temporary Git repositories and fake HTTP only."""

import copy
import io
import json
import os
from pathlib import Path
import sys
import unittest
from unittest import mock
import urllib.error

sys.dont_write_bytecode = True
import generate_release_notes as GENERATOR
import test_release_notes as FIXTURES


def draft(item="Find nearby players with class-colored location dots."):
    return {"welcome": "Welcome to QuestTogether. Explore the new map settings.",
            "sections": [{"title": "Player locations", "items": [item]}]}


def response(value=None, **changes):
    value = draft() if value is None else value
    result = {"status": "completed", "output": [{"type": "message", "role": "assistant",
              "status": "completed", "content": [{"type": "output_text", "text": json.dumps(value)}]}]}
    result.update(changes)
    return result


def opener_for(value):
    return lambda *_args, **_kwargs: io.BytesIO(json.dumps(value).encode("utf-8"))


class GeneratorTests(unittest.TestCase):
    # Reuse the existing isolated Git setup, without inheriting its test cases.
    run_process = FIXTURES.NotesTests.run_process
    git = FIXTURES.NotesTests.git
    new_repo = FIXTURES.NotesTests.new_repo

    def setUp(self):
        FIXTURES.NotesTests.setUp(self)
        self.network = mock.patch.object(GENERATOR.urllib.request, "urlopen",
                                         side_effect=AssertionError("offline tests must never use the network"))
        self.network.start()
        self.addCleanup(self.network.stop)

    def commit_feature(self, filename="Core.lua", text="-- Render new location dots.\n", message="Add location dots"):
        (self.root / filename).write_text(text, encoding="utf-8")
        self.git("add", filename)
        self.git("commit", "-qm", message)

    def saved_notes(self):
        return {name: (self.root / name).read_bytes() for name in ("release_notes.json", "ReleaseNotes.lua")}

    def test_real_evidence_uses_only_changes_since_resolved_baseline(self):
        self.commit_feature(text="-- Older baseline feature.\n", message="Excluded older commit")
        self.git("tag", "-f", "v1.2.3")
        self.commit_feature(text="-- New location dots.\n", message="Add map sharing preferences")
        version, previous, evidence = GENERATOR.collect_evidence(self.root)
        self.assertEqual(version, "1.2.3")
        self.assertEqual(previous, FIXTURES.sample_notes())
        self.assertIn("Add map sharing preferences", evidence)
        self.assertNotIn("Excluded older commit", evidence)
        self.assertIn("+-- New location dots.", evidence)
        self.assertIn("PREVIOUS NOTES (do not repeat unchanged features)", evidence)
        self.assertIn(FIXTURES.sample_notes()["sections"][0]["items"][0], evidence)
        self.assertNotIn("BEGIN UNTRUSTED SOURCE ReleaseNotes.lua", evidence)

    def test_dirty_worktree_requires_explicit_opt_in_and_collects_staged_unstaged_untracked(self):
        self.commit_feature()
        (self.root / "Core.lua").write_text("-- Staged feature.\n", encoding="utf-8")
        self.git("add", "Core.lua")
        (self.root / "Core.lua").write_text("-- Staged feature.\n-- Unstaged fix.\n", encoding="utf-8")
        (self.root / "NewLocationPins.lua").write_text("-- Brand-new untracked feature.\n", encoding="utf-8")
        with self.assertRaisesRegex(GENERATOR.NotesError, "dirty"):
            GENERATOR.collect_evidence(self.root)
        _, _, evidence = GENERATOR.collect_evidence(self.root, include_working_tree=True)
        for expected in ("Staged feature", "Unstaged fix", "Brand-new untracked feature"):
            self.assertIn(expected, evidence)

    def test_local_secrets_ignored_files_generated_notes_and_symlinks_are_excluded(self):
        self.commit_feature()
        (self.root / ".gitignore").write_text("Ignored.lua\n.local/\n", encoding="utf-8")
        for name in (".env", ".env.lua", "Secrets.lua", "Credentials.lua", "PrivateKey.lua",
                     "Config.lua", "Ignored.lua", "release_notes.json", "LocalizedReleaseNotes.lua", "Locales.lua"):
            (self.root / name).write_text("excluded-content-" + name, encoding="utf-8")
        (self.root / ".local").mkdir()
        (self.root / ".local/Debug.lua").write_text("excluded-local-content", encoding="utf-8")
        (self.root / "Linked.lua").symlink_to(self.root / "Secrets.lua")
        (self.root / "NewFeature.lua").write_text("eligible-new-feature", encoding="utf-8")
        _, _, evidence = GENERATOR.collect_evidence(self.root, include_working_tree=True)
        self.assertIn("eligible-new-feature", evidence)
        self.assertNotIn("excluded-content", evidence)
        self.assertNotIn("excluded-local-content", evidence)
        self.assertNotIn("Linked.lua", evidence)

    def test_translated_notes_are_never_source_evidence_or_silently_overwritten(self):
        self.commit_feature()
        path = self.root / "LocalizedReleaseNotes.lua"
        path.write_text("-- Earlier translated feature must not become new evidence.\n", encoding="utf-8")
        self.git("add", path.name)
        self.git("commit", "-qm", "Fixture translated data")
        _, _, evidence = GENERATOR.collect_evidence(self.root)
        self.assertNotIn("Earlier translated feature", evidence)
        before = path.read_bytes()
        GENERATOR.generate(self.root, write=True, generator=lambda *args: draft())
        self.assertEqual(path.read_bytes(), before, "English drafting must require a separate translation step")

    def test_deleted_and_replaced_historical_symlinks_are_not_evidence(self):
        (self.root / "Linked.lua").symlink_to("/private/excluded-historical-secret")
        self.git("add", "Linked.lua")
        self.git("commit", "-qm", "Fixture link")
        self.git("tag", "-f", "v1.2.3")
        (self.root / "Linked.lua").unlink()
        (self.root / "Linked.lua").write_text("replaced-link-content", encoding="utf-8")
        self.git("add", "Linked.lua")
        self.git("commit", "-qm", "Replace link")
        self.commit_feature()
        _, _, evidence = GENERATOR.collect_evidence(self.root)
        self.assertNotIn("excluded-historical-secret", evidence)
        self.assertNotIn("replaced-link-content", evidence)
        (self.root / "Linked.lua").unlink()
        _, _, evidence = GENERATOR.collect_evidence(self.root, include_working_tree=True)
        self.assertNotIn("excluded-historical-secret", evidence)

    def test_no_changes_missing_nonancestor_and_shallow_baselines_fail_before_generator(self):
        with self.assertRaisesRegex(GENERATOR.NotesError, "no player-facing"):
            GENERATOR.collect_evidence(self.root)
        with self.assertRaises(GENERATOR.NotesError):
            GENERATOR.collect_evidence(self.root, "missing-baseline")
        old = self.git("rev-parse", "HEAD")
        self.commit_feature()
        later = self.git("rev-parse", "HEAD")
        self.git("checkout", "--detach", old)
        with self.assertRaisesRegex(GENERATOR.NotesError, "ancestor"):
            GENERATOR.collect_evidence(self.root, later)
        self.git("checkout", "--detach", later)
        shallow = self.directory / "shallow"
        self.git("clone", "--quiet", "--depth", "1", self.root.as_uri(), str(shallow))
        with self.assertRaisesRegex(GENERATOR.NotesError, "full checkout"):
            GENERATOR.collect_evidence(shallow)

    def test_request_is_structured_private_and_preserves_default_or_explicit_model(self):
        for model in (GENERATOR.MODEL, "explicit-model"):
            with self.subTest(model=model):
                seen = []
                def opener(request, timeout):
                    seen.append((request, timeout))
                    return opener_for(response())()
                actual = GENERATOR.request_notes("untrusted source evidence", "offline-fake-key", model, opener)
                self.assertEqual(actual, draft())
                request, timeout = seen[0]
                self.assertEqual(request.full_url, "https://api.openai.com/v1/responses")
                self.assertEqual(request.method, "POST")
                self.assertEqual(timeout, 180)
                self.assertEqual(request.get_header("Authorization"), "Bearer offline-fake-key")
                payload = json.loads(request.data)
                self.assertEqual(payload["model"], model)
                self.assertFalse(payload["store"])
                self.assertEqual(payload["input"][1], {"role": "user", "content": "untrusted source evidence"})
                self.assertIn("untrusted evidence", payload["input"][0]["content"])
                self.assertEqual(payload["text"]["format"]["schema"], GENERATOR.SCHEMA)
                self.assertTrue(payload["text"]["format"]["strict"])
                self.assertEqual(payload["text"]["format"]["type"], "json_schema")
        self.assertEqual(GENERATOR.MODEL, "gpt-5.5")

    def test_missing_credentials_never_call_opener(self):
        opener = mock.Mock(side_effect=AssertionError("missing key must not open HTTP"))
        with self.assertRaisesRegex(GENERATOR.NotesError, "OPENAI_API_KEY"):
            GENERATOR.request_notes("evidence", None, opener=opener)
        opener.assert_not_called()

    def test_status_refusal_and_malformed_envelopes_never_overwrite_notes(self):
        self.commit_feature()
        before = self.saved_notes()
        refusal = {"type": "refusal", "refusal": "No notes"}
        mixed = response()
        mixed["output"][0]["content"].append(refusal)
        bad_draft = response()
        bad_draft["output"][0]["content"][0]["text"] = "{not-json"
        duplicate = response()
        duplicate["output"][0]["content"][0]["text"] = '{"welcome":"first","welcome":"second","sections":[]}'
        cases = [None, [], 1, response(status="incomplete"), response(status="failed"),
                 response(output=None), response(output={}), response(output=[None]),
                 response(output=[{"type": "message", "content": None}]),
                 response(output=[{"type": "message", "content": [None]}]),
                 response(output=[{"type": "message", "status": "incomplete", "content": []}]),
                 response(output=[{"type": "message", "content": [refusal]}]),
                 response(output=[{"type": "message", "content": [{"type": "output_text", "text": 7}]}]),
                 response(output=[]), mixed, bad_draft, duplicate, response({"extra": True}),
                 response({"welcome": "Useful welcome", "sections": []})]
        for result in cases:
            with self.subTest(result=result):
                def generate(evidence, key, model):
                    return GENERATOR.request_notes(evidence, key, model, opener_for(result))
                with self.assertRaises(GENERATOR.NotesError):
                    GENERATOR.generate(self.root, write=True, api_key="offline-fake-key", generator=generate)
                self.assertEqual(self.saved_notes(), before)

    def test_http_timeout_transport_and_invalid_json_do_not_echo_secrets(self):
        self.commit_feature()
        before = self.saved_notes()
        cases = [urllib.error.HTTPError("https://example.invalid", 401, "offline-secret", {}, io.BytesIO(b"offline-secret")),
                 urllib.error.URLError("offline-secret"), TimeoutError("offline-secret"),
                 ConnectionResetError("offline-secret")]
        for error in cases:
            with self.subTest(error=type(error)):
                def generate(evidence, key, model):
                    return GENERATOR.request_notes(evidence, key, model, opener=mock.Mock(side_effect=error))
                with self.assertRaises(GENERATOR.NotesError) as raised:
                    GENERATOR.generate(self.root, write=True, api_key="offline-secret", generator=generate)
                self.assertNotIn("offline-secret", str(raised.exception))
                self.assertEqual(self.saved_notes(), before)
        with self.assertRaises(GENERATOR.NotesError):
            GENERATOR.generate(self.root, write=True, generator=lambda *args: GENERATOR.request_notes(
                "source", "offline-secret", opener=lambda *a, **kw: io.BytesIO(b"not-json")))
        self.assertEqual(self.saved_notes(), before)

    def test_old_notes_and_old_bullets_mixed_with_new_ones_are_rejected_without_overwrite(self):
        self.commit_feature()
        before = self.saved_notes()
        old = FIXTURES.sample_notes()
        old.pop("version")
        mixed = draft()
        mixed["sections"][0]["items"].append(old["sections"][0]["items"][0].upper())
        for generated in (old, mixed):
            with self.subTest(generated=generated):
                with self.assertRaisesRegex(GENERATOR.NotesError, "repeat"):
                    GENERATOR.generate(self.root, write=True, generator=lambda *args: generated)
                self.assertEqual(self.saved_notes(), before)

    def test_dry_run_and_write_keep_toc_version_and_exact_json_lua_markdown_items(self):
        self.commit_feature()
        before, head = self.saved_notes(), self.git("rev-parse", "HEAD")
        generated = draft('Meet "Étoile" near the map marker.')
        notes = GENERATOR.generate(self.root, generator=lambda *args: copy.deepcopy(generated))
        self.assertEqual(self.saved_notes(), before)
        notes = GENERATOR.generate(self.root, write=True, generator=lambda *args: copy.deepcopy(generated))
        self.assertEqual(notes, {"version": "1.2.3", **generated})
        self.assertEqual((self.root / "release_notes.json").read_text(), json.dumps(notes, ensure_ascii=False, indent=2) + "\n")
        self.assertEqual((self.root / "ReleaseNotes.lua").read_text(), GENERATOR.render_lua(notes))
        self.assertEqual(GENERATOR.toc_version((self.root / "QuestTogether.toc").read_text()), "1.2.3")
        self.assertEqual(self.git("rev-parse", "HEAD"), head)
        rendered = GENERATOR.markdown(notes)
        self.assertIn(notes["welcome"], rendered)
        for section in notes["sections"]:
            self.assertIn("## " + section["title"], rendered)
            for item in section["items"]:
                self.assertIn("- " + item + "\n", rendered)

    def test_cli_writes_all_three_views_and_preserves_markdown_on_failure(self):
        self.commit_feature()
        markdown = self.directory / "notes.md"
        args = ["--root", str(self.root), "--write", "--markdown-out", str(markdown), "--model", "chosen-model"]
        with mock.patch.object(GENERATOR, "request_notes", return_value=draft()) as request, \
                mock.patch.dict(os.environ, {"OPENAI_API_KEY": "offline-fake-key"}), \
                mock.patch("sys.stdout", new_callable=io.StringIO):
            self.assertEqual(GENERATOR.main(args), 0)
            self.assertEqual(request.call_args.args[1:], ("offline-fake-key", "chosen-model"))
        notes = json.loads((self.root / "release_notes.json").read_text())
        self.assertEqual(markdown.read_text(), GENERATOR.markdown(notes))
        before, prior_markdown = self.saved_notes(), markdown.read_bytes()
        with mock.patch.object(GENERATOR, "request_notes", side_effect=GENERATOR.NotesError("refused")), \
                mock.patch("sys.stderr", new_callable=io.StringIO):
            self.assertEqual(GENERATOR.main(args + ["--include-working-tree"]), 1)
        self.assertEqual(self.saved_notes(), before)
        self.assertEqual(markdown.read_bytes(), prior_markdown)


if __name__ == "__main__":
    unittest.main()
