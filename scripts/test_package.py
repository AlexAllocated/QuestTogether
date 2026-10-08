#!/usr/bin/env python3
"""Release payload integrity without live services or changing the checkout."""
import io
from pathlib import Path
import tempfile
import unittest
import zipfile
import package
import check_architecture

ROOT = Path(__file__).resolve().parents[1]

class PackagingTests(unittest.TestCase):
    def test_live_manifest_and_repeatable_archives(self):
        with tempfile.TemporaryDirectory() as directory:
            first, second = (Path(directory) / name for name in ("first.zip", "second.zip"))
            package.package(ROOT, first)
            package.package(ROOT, second)
            self.assertEqual(first.read_bytes(), second.read_bytes())
            manifest = package.verify_archive(first.read_bytes())
            self.assertTrue(set(package.toc_entries((ROOT / "QuestTogether.toc").read_text())) <= set(manifest["files"]))
            self.assertIn("Libs/libchev/LICENSE", manifest["files"])
            self.assertIn("Media/QuestTogetherIcon.tga", manifest["files"])
            self.assertNotIn("scripts/test.lua", manifest["files"])
            self.assertFalse(any(p.startswith(".local/") or p.endswith("image.png") for p in manifest["files"]))

    def test_ref_is_independent_of_working_tree(self):
        # Real immutable history: local refactors must not leak into a tag build.
        version, files = package.payloads(ROOT, "HEAD")
        self.assertEqual(version, package.version_from_toc(files["QuestTogether.toc"].decode()))
        self.assertIsNotNone(__import__("json").loads(files[package.MANIFEST])["sourceCommit"])

    def test_rejects_damaged_and_incomplete_payloads(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "test.zip"
            package.package(ROOT, archive)
            original = archive.read_bytes()
            with zipfile.ZipFile(io.BytesIO(original)) as source:
                entries = {name: source.read(name) for name in source.namelist()}
            for mutation in ("corrupt", "missing", "extra", "path_alias"):
                changed = dict(entries)
                if mutation == "corrupt": changed["QuestTogether/Core.lua"] += b"--bad"
                elif mutation == "missing": del changed["QuestTogether/Core.lua"]
                elif mutation == "extra": changed["QuestTogether/private-key"] = b"unexpected"
                else: changed["QuestTogether/../escape"] = b"unexpected"
                data = io.BytesIO()
                with zipfile.ZipFile(data, "w") as target:
                    for name, value in changed.items(): target.writestr(name, value)
                with self.assertRaises(package.PackageError, msg=mutation): package.verify_archive(data.getvalue())

    def test_architecture_guard_catches_native_send_ownership_regressions(self):
        for call in ("pcall(a.API.SendAddonMessage, prefix, wire)",
                     "self.API.SendAddonMessage(prefix, wire)",
                     "local send = other.API.SendAddonMessage"):
            source = (ROOT / "NearbyStreams.lua").read_text() + "\n" + call
            with self.assertRaisesRegex(ValueError, "native addon sends belong to Transport"):
                check_architecture.check(ROOT, {"NearbyStreams.lua": source})

    def test_manifest_rejects_duplicates_offline_tools_and_traversal(self):
        for text in ("Core.lua\ncore.lua", "scripts/test.lua", "../Core.lua", "/Core.lua"):
            with self.assertRaises(package.PackageError): package.toc_entries(text)

if __name__ == "__main__": unittest.main()
