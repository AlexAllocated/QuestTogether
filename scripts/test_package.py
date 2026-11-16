#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
# See LICENSING.md for scope and preserved third-party notices.
"""Release payload integrity without live services or changing the checkout."""
import io
import hashlib
import json
import os
from pathlib import Path
import posixpath
import re
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile
import package
import check_architecture

ROOT = Path(__file__).resolve().parents[1]

class PackagingTests(unittest.TestCase):
    def test_source_package_moves_thin_companion_and_resolves_shared_tests(self):
        # Simulate CurseForge's documented ignore-before-directory-move order
        # against real source bytes, without invoking an upload or a model.
        metadata = (ROOT / ".pkgmeta").read_text()
        self.assertRegex(metadata, r"(?m)^package-as: QuestTogether$")
        source, destination = re.search(r"(?m)^  (QuestTogether/\S+): (\S+)$", metadata).groups()
        ignored = re.findall(r"(?m)^  - (\S+)$", metadata)
        self.assertIn("QuestTogether_Tests.toc", ignored)
        names = set(subprocess.check_output(["git", "ls-files"], cwd=ROOT, text=True).splitlines())
        read = lambda name: (ROOT / name).read_bytes()
        names.update(package.source_companion_files(read("QuestTogether_Tests.toc").decode(), read))
        # New required source files must be tested before they have been staged.
        names.update(package.DOCUMENTS)
        names.update(package.toc_entries(read("QuestTogether.toc").decode()))
        names.update(package.toc_entries(read("QuestTogether_Tests.toc").decode()))
        installed = {}
        for name in names:
            if name in ignored or any(part.startswith(".") for part in name.split("/")):
                continue
            path = "QuestTogether/" + name
            if path.startswith(source + "/"):
                path = destination + path[len(source):]
            installed[path] = (ROOT / name).read_bytes()
        self.assertEqual(destination, "QuestTogether_Tests")
        self.assertEqual({name for name in installed if name.startswith(destination + "/")},
                         {destination + "/QuestTogether_Tests.toc", destination + "/Bindings.xml"}
                         | {destination + "/" + name for name in package.LEGAL_DOCUMENTS})
        for name in package.LEGAL_DOCUMENTS:
            self.assertEqual(installed[destination + "/" + name], read(name))
            self.assertEqual(installed["QuestTogether/" + name], read(name))
        for name in package.EDITABLE_ASSETS:
            self.assertEqual(installed["QuestTogether/" + name], read(name))
        self.assertNotIn("QuestTogether/QuestTogether_Tests.toc", installed)
        self.assertNotIn(source + "/QuestTogether_Tests.toc", installed)
        self.assertEqual(installed[destination + "/Bindings.xml"], package.TEST_BINDINGS)
        canonical = (ROOT / "QuestTogether_Tests.toc").read_text()
        generated = installed[destination + "/QuestTogether_Tests.toc"].decode()
        package.check_source_companion(lambda name: (ROOT / name).read_bytes(), canonical)
        self.assertEqual(package.version_from_toc(generated), package.version_from_toc(canonical))
        references = [line.strip().replace("\\", "/") for line in generated.splitlines()
                      if line.strip() and not line.lstrip().startswith("#")]
        entries = package.validate_test_manifest(canonical, (ROOT / "QuestTogether.toc").read_text())
        self.assertEqual(references, ["../QuestTogether/" + name for name in entries])
        main_entries = set(package.toc_entries((ROOT / "QuestTogether.toc").read_text()))
        for reference, name in zip(references, entries):
            resolved = posixpath.normpath(destination + "/" + reference)
            self.assertEqual(resolved, "QuestTogether/" + name)
            self.assertEqual(installed[resolved], (ROOT / name).read_bytes())
            self.assertNotIn(name, main_entries)
        vendor = json.loads(installed["QuestTogether/Libs/libchev/manifest.json"])
        for name, expected in vendor["files"].items():
            self.assertEqual(package.digest(installed["QuestTogether/Libs/libchev/" + name]), expected)

    def test_source_companion_rejects_stale_version_and_new_modules(self):
        canonical = (ROOT / "QuestTogether_Tests.toc").read_text()
        saved = {name: (ROOT / name).read_bytes() for name in package.LEGAL_DOCUMENTS}
        saved.update(package.source_companion_files(canonical, saved.__getitem__))
        for changed in (canonical.replace("## Version: " + package.version_from_toc(canonical), "## Version: 99.0.0"),
                        canonical.replace("scripts/test_complete.lua", "scripts/regression_new.lua\nscripts/test_complete.lua")):
            with self.assertRaisesRegex(package.PackageError, "stale source companion"):
                package.check_source_companion(saved.__getitem__, changed)

    def test_source_companion_rejects_stale_legal_notices(self):
        canonical = (ROOT / "QuestTogether_Tests.toc").read_text()
        original = {name: (ROOT / name).read_bytes() for name in package.LEGAL_DOCUMENTS}
        original.update(package.source_companion_files(canonical, original.__getitem__))
        for name in package.LEGAL_DOCUMENTS:
            changed = dict(original)
            changed[name] += b"\nUpdated notice\n"
            with self.subTest(name=name), self.assertRaisesRegex(package.PackageError, "stale source companion"):
                package.check_source_companion(changed.__getitem__, canonical)

    @staticmethod
    def archive_with_manifest(files, schema=3, metadata=None):
        """Rehash intentional mutations so verification exercises content rules."""
        manifest_path = package.ADDON + "/" + package.MANIFEST
        manifest = json.loads(files[manifest_path])
        manifest["schema"] = schema
        manifest["files"] = {name: package.digest(value) for name, value in files.items()
                             if name != manifest_path}
        manifest.update(metadata or {})
        data = io.BytesIO()
        with zipfile.ZipFile(data, "w") as archive:
            for name, value in files.items():
                archive.writestr(name, json.dumps(manifest).encode() if name == manifest_path else value)
        return data.getvalue()

    def test_legal_and_editable_source_files_are_mandatory_even_after_rehash(self):
        _, original = package.payloads(ROOT)
        required = [addon + "/" + name for addon in (package.ADDON, package.TEST_ADDON)
                    for name in package.LEGAL_DOCUMENTS]
        required += [package.ADDON + "/" + name for name in (
            "logo.svg", "Media/QuestCompareScroll.svg", "scripts/build_audio.py", "Media/README.md")]
        for name in required:
            changed = dict(original)
            del changed[name]
            with self.subTest(name=name), self.assertRaises(package.PackageError):
                package.verify_archive(self.archive_with_manifest(changed))

    def test_license_text_and_companion_notices_cannot_be_replaced(self):
        _, original = package.payloads(ROOT)
        for mutation in ("truncated_gpl", "stale_notice", "wrong_main_spdx", "wrong_test_spdx"):
            changed = dict(original)
            if mutation == "truncated_gpl":
                for addon in (package.ADDON, package.TEST_ADDON):
                    changed[addon + "/LICENSE"] = b"GNU GENERAL PUBLIC LICENSE\nVersion 3\n"
            elif mutation == "stale_notice":
                changed[package.TEST_ADDON + "/NOTICE"] = b"outdated attribution\n"
            else:
                addon = package.ADDON if mutation == "wrong_main_spdx" else package.TEST_ADDON
                name = addon + "/" + addon + ".toc"
                changed[name] = changed[name].replace(b"GPL-3.0-only", b"GPL-3.0-or-later")
            with self.subTest(mutation=mutation), self.assertRaises(package.PackageError):
                package.verify_archive(self.archive_with_manifest(changed))

    def test_source_and_license_metadata_are_validated(self):
        _, files = package.payloads(ROOT)
        for metadata in ({"license": "MIT"}, {"sourceCommit": "HEAD"},
                         {"sourceRepository": "https://example.invalid/other"},
                         {"sourceUrl": package.SOURCE_REPOSITORY + "/tree/main"},
                         {"sourceCommit": "a" * 40, "sourceUrl": None}):
            with self.subTest(metadata=metadata), self.assertRaises(package.PackageError):
                package.verify_archive(self.archive_with_manifest(files, metadata=metadata))

    def test_unpacked_size_limit_remains_enforced(self):
        _, files = package.payloads(ROOT)
        data = self.archive_with_manifest(files)
        with patch.object(package, "MAX_BYTES", 1), self.assertRaisesRegex(package.PackageError, "archive exceeds package limits"):
            package.verify_archive(data)

    def test_historical_schema_two_keeps_its_original_document_requirements(self):
        _, files = package.payloads(ROOT)
        for name in package.LEGAL_DOCUMENTS:
            files.pop(package.TEST_ADDON + "/" + name)
            if name not in package.LEGACY_DOCUMENTS:
                files.pop(package.ADDON + "/" + name)
        for name in package.EDITABLE_ASSETS:
            files.pop(package.ADDON + "/" + name)
        for addon in (package.ADDON, package.TEST_ADDON):
            name = addon + "/" + addon + ".toc"
            files[name] = files[name].replace(b"GPL-3.0-only", b"MIT License")
        manifest_path = package.ADDON + "/" + package.MANIFEST
        historical = json.loads(files[manifest_path])
        for field in ("license", "sourceRepository", "sourceUrl"):
            del historical[field]
        files[manifest_path] = json.dumps(historical).encode()
        manifest = package.verify_archive(self.archive_with_manifest(files, schema=2))
        self.assertEqual(manifest["schema"], 2)

    def test_live_manifest_and_repeatable_archives(self):
        with tempfile.TemporaryDirectory() as directory:
            first, second = (Path(directory) / name for name in ("first.zip", "second.zip"))
            package.package(ROOT, first)
            package.package(ROOT, second)
            self.assertEqual(first.read_bytes(), second.read_bytes())
            manifest = package.verify_archive(first.read_bytes())
            self.assertTrue({"QuestTogether/" + p for p in package.toc_entries((ROOT / "QuestTogether.toc").read_text())} <= set(manifest["files"]))
            self.assertIn("QuestTogether/Libs/libchev/LICENSE", manifest["files"])
            for name in package.LEGAL_DOCUMENTS:
                for addon in (package.ADDON, package.TEST_ADDON):
                    self.assertEqual(manifest["files"][addon + "/" + name],
                                     package.digest((ROOT / name).read_bytes()))
            for name in package.EDITABLE_ASSETS:
                self.assertIn("QuestTogether/" + name, manifest["files"])
            self.assertIn("QuestTogether/Media/QuestTogetherIcon.tga", manifest["files"])
            self.assertIn("QuestTogether/Media/QuestTogetherTipIcon.tga", manifest["files"])
            self.assertIn("QuestTogether/Media/QuestTogetherTipIcon.png", manifest["files"])
            self.assertIn("QuestTogether/Media/QuestTogetherDeveloperIcon.tga", manifest["files"])
            self.assertIn("QuestTogether/Media/QuestTogetherDeveloperPartnerIcon.tga", manifest["files"])
            audio = json.loads((ROOT / "Media/Audio/manifest.json").read_text())
            self.assertIn("QuestTogether/Media/Audio/NOTICE.txt", manifest["files"])
            self.assertIn("QuestTogether/Media/Audio/manifest.json", manifest["files"])
            for cue in ("scroll", "spellbook", "selection", "chime", "progress", "completion"):
                for gain in range(1, 101):
                    self.assertIn(f"QuestTogether/Media/Audio/{cue}/{gain:03}.ogg", manifest["files"])
                for variant in audio["cues"][cue]["variants"]:
                    self.assertEqual(manifest["files"]["QuestTogether/Media/Audio/" + variant["file"]], variant["sha256"])
            self.assertNotIn("QuestTogether/scripts/test.lua", manifest["files"])
            self.assertNotIn("QuestTogether/scripts/offline_numeric_tests.lua", manifest["files"])
            self.assertFalse(any(p.startswith(".local/") or p.endswith("image.png") for p in manifest["files"]))
            self.assertEqual(manifest["schema"], 3)
            self.assertEqual(manifest["license"], "GPL-3.0-only")
            self.assertEqual(manifest["sourceRepository"], package.SOURCE_REPOSITORY)
            self.assertIsNone(manifest["sourceCommit"])
            self.assertIsNone(manifest["sourceUrl"])
            self.assertIn("QuestTogether_Tests/QuestTogether_Tests.toc", manifest["files"])
            self.assertIn("QuestTogether_Tests/Tests.lua", manifest["files"])
            self.assertNotIn("QuestTogether/Tests.lua", manifest["files"])
            # WoW discovers root Bindings.xml independently of TOC entries.
            # The companion must never register the main addon's bindings again.
            self.assertIn("QuestTogether/Bindings.xml", manifest["files"])
            self.assertEqual(manifest["files"]["QuestTogether_Tests/Bindings.xml"], package.digest(package.TEST_BINDINGS))
            companion = (ROOT / "QuestTogether_Tests.toc").read_text()
            entries = package.validate_test_manifest(companion, (ROOT / "QuestTogether.toc").read_text())
            self.assertTrue({"QuestTogether_Tests/" + p for p in entries} <= set(manifest["files"]))

    def test_companion_rejects_wrong_version_eager_loading_and_missing_files(self):
        main = (ROOT / "QuestTogether.toc").read_text()
        companion = (ROOT / "QuestTogether_Tests.toc").read_text()
        for changed in (companion.replace("## LoadOnDemand: 1", "## LoadOnDemand: 0"),
                        companion.replace("## RequiredDeps: QuestTogether", "## RequiredDeps:"),
                        companion.replace("## X-QT-TestModules:", "## Wrong-Count:"),
                        companion.replace("scripts/test_complete.lua", "Core.lua"),
                        companion.replace("## Version: " + package.version_from_toc(main), "## Version: 0.0.0")):
            with self.assertRaises(package.PackageError): package.validate_test_manifest(changed, main)
        with self.assertRaises(package.PackageError):
            package.validate_test_completion("Tests.lua", b"-- incomplete module\n")
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "addon.zip"
            package.package(ROOT, path)
            with zipfile.ZipFile(path) as archive:
                payloads = {name: archive.read(name) for name in archive.namelist()}
            del payloads["QuestTogether_Tests/Tests.lua"]
            buffer = io.BytesIO()
            with zipfile.ZipFile(buffer, "w") as archive:
                for name, value in payloads.items(): archive.writestr(name, value)
            with self.assertRaises(package.PackageError): package.verify_archive(buffer.getvalue())

    def test_ref_is_independent_of_working_tree(self):
        # A clean checkout cannot expose accidentally reading working-tree files
        # in a ref build. Give the commit, index, and worktree distinct content.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            published = {name: b"fixture document\n" for name in package.DOCUMENTS}
            published["LICENSE"] = (ROOT / "LICENSE").read_bytes()
            published.update({
                "QuestTogether.toc": b"## Version: 1.0.0\n## X-License: GPL-3.0-only\nCore.lua\nLibs/libchev/libchev.lua\n",
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
            self.assertEqual({name: data for name, data in files.items() if name != "QuestTogether/" + package.MANIFEST}, {"QuestTogether/" + name: data for name, data in published.items()})
            manifest = json.loads(files["QuestTogether/" + package.MANIFEST])
            self.assertEqual(manifest["sourceCommit"], commit)
            self.assertEqual(manifest["sourceUrl"], package.SOURCE_REPOSITORY + "/tree/" + commit)
            self.assertEqual(manifest["license"], "GPL-3.0-only")
            self.assertEqual(manifest["files"], {"QuestTogether/" + name: hashlib.sha256(data).hexdigest() for name, data in published.items()})

    def test_rejects_damaged_and_incomplete_payloads(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "test.zip"
            package.package(ROOT, archive)
            original = archive.read_bytes()
            with zipfile.ZipFile(io.BytesIO(original)) as source:
                entries = {name: source.read(name) for name in source.namelist()}
            for mutation in ("corrupt", "missing", "extra", "path_alias", "main_root", "test_root", "parent_collision", "test_bindings"):
                changed = dict(entries)
                if mutation == "corrupt": changed["QuestTogether/Core.lua"] += b"--bad"
                elif mutation == "missing": del changed["QuestTogether/Core.lua"]
                elif mutation == "extra": changed["QuestTogether/private-key"] = b"unexpected"
                elif mutation == "path_alias": changed["QuestTogether/../escape"] = b"unexpected"
                elif mutation == "test_bindings":
                    name = "QuestTogether_Tests/Bindings.xml"
                    changed[name] = b'<Bindings><Binding name="QUESTTOGETHER_SETTINGS">print("bad")</Binding></Bindings>'
                    manifest = json.loads(changed["QuestTogether/" + package.MANIFEST])
                    manifest["files"][name] = package.digest(changed[name])
                    changed["QuestTogether/" + package.MANIFEST] = json.dumps(manifest).encode()
                else:
                    collision = {"main_root": "QuestTogether", "test_root": "QuestTogether_Tests",
                                 "parent_collision": "QuestTogether/Media"}[mutation]
                    changed[collision] = b"regular file colliding with directory"
                    manifest = json.loads(changed["QuestTogether/" + package.MANIFEST])
                    manifest["files"][collision] = package.digest(changed[collision])
                    changed["QuestTogether/" + package.MANIFEST] = json.dumps(manifest).encode()
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
