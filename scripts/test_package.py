#!/usr/bin/env python3
"""Release payload integrity without live services or changing the checkout."""
import io
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
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
            self.assertIn("Media/QuestTogetherTipIcon.tga", manifest["files"])
            self.assertIn("Media/QuestTogetherTipIcon.png", manifest["files"])
            self.assertIn("Media/QuestTogetherDeveloperIcon.tga", manifest["files"])
            self.assertIn("Media/QuestTogetherDeveloperPartnerIcon.tga", manifest["files"])
            self.assertNotIn("scripts/test.lua", manifest["files"])
            self.assertNotIn("scripts/offline_numeric_tests.lua", manifest["files"])
            self.assertFalse(any(p.startswith(".local/") or p.endswith("image.png") for p in manifest["files"]))

    def test_ref_is_independent_of_working_tree(self):
        # A clean checkout cannot expose accidentally reading working-tree files
        # in a ref build. Give the commit, index, and worktree distinct content.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            published = {name: b"fixture document\n" for name in package.DOCUMENTS}
            published.update({
                "QuestTogether.toc": b"## Version: 1.0.0\nCore.lua\nLibs/libchev/libchev.lua\n",
                "Core.lua": b"-- published code\n",
                "Libs/libchev/libchev.lua": b"-- pinned dependency\n",
                "Media/Published.tga": b"published asset",
            })
            published["Libs/libchev/manifest.json"] = json.dumps({
                "schema": 1, "revision": "a" * 40,
                "files": {"libchev.lua": hashlib.sha256(published["Libs/libchev/libchev.lua"]).hexdigest()},
            }).encode()
            for name, data in published.items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
            environment = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
            environment.update({"GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull})
            with patch.dict(os.environ, environment, clear=True):
                def git(*args):
                    return subprocess.check_output([
                        "git", "-c", "user.name=Offline package test", "-c", "user.email=test@example.invalid",
                        "-c", "commit.gpgsign=false", "-c", "core.hooksPath=" + os.devnull, *args,
                    ], cwd=root, stderr=subprocess.DEVNULL).decode().strip()
                git("init", "-q")
                git("add", ".")
                git("commit", "-qm", "Published fixture")
                commit = git("rev-parse", "HEAD")
                (root / "Core.lua").write_text("-- staged code\n")
                git("add", "Core.lua")
                (root / "Core.lua").write_text("-- unstaged code\n")
                (root / "QuestTogether.toc").write_text("## Version: 9.0.0\nUntracked.lua\n")
                (root / "Media/Published.tga").unlink()
                (root / "Media/Untracked.tga").write_bytes(b"untracked asset")
                version, files = package.payloads(root, "HEAD")
            self.assertEqual(version, "1.0.0")
            self.assertEqual({name: data for name, data in files.items() if name != package.MANIFEST}, published)
            manifest = json.loads(files[package.MANIFEST])
            self.assertEqual(manifest["sourceCommit"], commit)
            self.assertEqual(manifest["files"], {name: hashlib.sha256(data).hexdigest() for name, data in published.items()})

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

    def test_architecture_guard_catches_retired_network_ownership(self):
        for call, expected in (
            ("function QT:Request(op, record) end", "typed submissions"),
            ("self:SerializeWireMessage(record)", "retired communication paths"),
            ("function QT:EncodeCommRecord(op, record) end", "wire schemas"),
        ):
            source = (ROOT / "NearbyStreams.lua").read_text() + "\n" + call
            with self.assertRaisesRegex(ValueError, expected):
                check_architecture.check(ROOT, {"NearbyStreams.lua": source})
        source = (ROOT / "CommsTransfer.lua").read_text() + "\nself.API.Delay(1, pump)"
        with self.assertRaisesRegex(ValueError, "network progression"):
            check_architecture.check(ROOT, {"CommsTransfer.lua": source})

    def test_manifest_rejects_duplicates_offline_tools_and_traversal(self):
        for text in ("Core.lua\ncore.lua", "scripts/test.lua", "scripts/offline_numeric_tests.lua", "../Core.lua", "/Core.lua"):
            with self.assertRaises(package.PackageError): package.toc_entries(text)

if __name__ == "__main__": unittest.main()
