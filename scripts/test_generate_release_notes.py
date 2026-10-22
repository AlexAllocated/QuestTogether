#!/usr/bin/env python3
"""Offline evidence, draft validation, and retired API-entrypoint contracts."""

import copy
import io
import json
import os
from pathlib import Path
import sys
import unittest
from unittest import mock
import urllib.request

sys.dont_write_bytecode = True
import generate_release_notes as GENERATOR
import test_release_notes as FIXTURES


def draft(item="Find nearby players with class-colored location dots."):
    return {"welcome": "Welcome to QuestTogether. Explore the new map settings.",
            "sections": [{"title": "Player locations", "items": [item]}]}


class GeneratorTests(unittest.TestCase):
    # Reuse the existing isolated Git setup, without inheriting its test cases.
    run_process = FIXTURES.NotesTests.run_process
    git = FIXTURES.NotesTests.git
    new_repo = FIXTURES.NotesTests.new_repo

    def setUp(self):
        FIXTURES.NotesTests.setUp(self)
        self.network = mock.patch.object(urllib.request, "urlopen",
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
                     "Config.lua", "Ignored.lua", "release_notes.json", "LocalizedReleaseNotes.lua", "ReleaseNotesHistory.lua", "Locales.lua"):
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

    def test_historical_evidence_can_begin_before_structured_notes_without_relaxing_draft_checks(self):
        self.git('rm', 'release_notes.json')
        self.git('commit', '-qm', 'Fixture before structured release notes')
        self.git('tag', '-f', 'v1.2.3')
        (self.root / 'release_notes.json').write_text(json.dumps(FIXTURES.sample_notes('1.3.0')))
        (self.root / 'QuestTogether.toc').write_text('## Version: 1.3.0\nCore.lua\nReleaseNotes.lua\n')
        (self.root / 'Core.lua').write_text('-- First release with structured notes.\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'Add actual new feature')
        self.git('tag', 'v1.3.0')
        with self.assertRaises(GENERATOR.NotesError):
            GENERATOR.collect_evidence(self.root, 'v1.2.3', target_ref='v1.3.0')
        version, previous, evidence = GENERATOR.collect_evidence(
            self.root, 'v1.2.3', target_ref='v1.3.0', allow_legacy_baseline=True)
        self.assertEqual(version, '1.3.0')
        self.assertIsNone(previous)
        self.assertIn('Structured release notes were not recorded', evidence)
        self.assertIn('+-- First release with structured notes.', evidence)
        self.assertIn('Add actual new feature', evidence)
        with self.assertRaisesRegex(GENERATOR.NotesError, 'historical target'):
            GENERATOR.collect_evidence(self.root, 'v1.2.3', allow_legacy_baseline=True)


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
        from generate_localized_notes import load_context
        self.assertIn('Add location dots', load_context(self.root, notes))
        self.assertEqual(GENERATOR.toc_version((self.root / "QuestTogether.toc").read_text()), "1.2.3")
        self.assertEqual(self.git("rev-parse", "HEAD"), head)
        rendered = GENERATOR.markdown(notes)
        self.assertIn(notes["welcome"], rendered)
        for section in notes["sections"]:
            self.assertIn("## " + section["title"], rendered)
            for item in section["items"]:
                self.assertIn("- " + item + "\n", rendered)


    def test_retired_request_rejects_keys_and_openers_without_network(self):
        opener = mock.Mock(side_effect=AssertionError("retired requests must never open HTTP"))
        for key in (None, "offline-secret"):
            with self.subTest(key_present=bool(key)):
                with self.assertRaisesRegex(GENERATOR.NotesError, "active Codex subscription session") as raised:
                    GENERATOR.request_notes("evidence", key, "chosen-model", opener=opener)
                self.assertIn("prepare_release_notes.py context", str(raised.exception))
                self.assertIn("prepare_release_notes.py finalize", str(raised.exception))
                self.assertNotIn("offline-secret", str(raised.exception))
        opener.assert_not_called()

    def test_retired_generation_stops_before_evidence_and_preserves_files(self):
        before = self.saved_notes()
        with mock.patch.object(GENERATOR, "collect_evidence", side_effect=AssertionError("must fail before collecting evidence")):
            with self.assertRaisesRegex(GENERATOR.NotesError, "Paid release-note API generation is retired"):
                GENERATOR.generate(self.root, write=True, api_key="offline-secret")
        self.assertEqual(self.saved_notes(), before)
        self.assertFalse((self.root / "release_notes/context.json").exists())

    def test_injected_offline_draft_keeps_optional_tip_in_markdown(self):
        self.commit_feature()
        source = draft()
        source["sections"][0]["tip"] = {"label": "Tip:", "text": "Use /qt tip or /qt hint."}
        notes = GENERATOR.generate(self.root, generator=lambda *args: copy.deepcopy(source))
        self.assertIn("> 💡 Tip: Use /qt tip or /qt hint.", GENERATOR.markdown(notes))

    def test_retired_cli_ignores_credentials_and_preserves_all_outputs(self):
        markdown = self.directory / "notes.md"
        markdown.write_text("Existing reviewed notes")
        before, prior_markdown = self.saved_notes(), markdown.read_bytes()
        args = ["--root", str(self.root), "--write", "--include-working-tree",
                "--markdown-out", str(markdown), "--model", "chosen-model"]
        environment_get = os.environ.get
        def reject_credentials(name, *args):
            if name in {"OPENAI_API_KEY", "CHANGELOG_OPENAI_MODEL"}:
                raise AssertionError("retired CLI must not read model credentials or settings")
            return environment_get(name, *args)
        with mock.patch.dict(os.environ, {"OPENAI_API_KEY": "offline-secret", "CHANGELOG_OPENAI_MODEL": "paid-model"}), \
                mock.patch.object(os.environ, "get", side_effect=reject_credentials), \
                mock.patch.object(GENERATOR, "generate", side_effect=AssertionError("retired CLI must not start generation")), \
                mock.patch("sys.stderr", new_callable=io.StringIO) as error:
            self.assertEqual(GENERATOR.main(args), 1)
        self.assertIn("active Codex subscription session", error.getvalue())
        self.assertNotIn("offline-secret", error.getvalue())
        self.assertEqual(self.saved_notes(), before)
        self.assertEqual(markdown.read_bytes(), prior_markdown)
        self.assertFalse((self.root / "release_notes/context.json").exists())


if __name__ == "__main__":
    unittest.main()
