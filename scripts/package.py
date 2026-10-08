#!/usr/bin/env python3
"""Build and verify a deterministic installation from the live TOC and asset rules."""
from __future__ import annotations
import argparse
import fnmatch
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import zipfile

ADDON = "QuestTogether"
MANIFEST = "package-manifest.json"
MAX_BYTES = 64 * 1024 * 1024
ASSETS = ("Media/**/*.tga", "Media/*.tga", "Media/ReleaseNotes/*.png", "changelogs/*.md")
DOCUMENTS = ("Bindings.xml", "Libs/Ed25519/README.md", "Libs/libchev/manifest.json",
             "Libs/libchev/LICENSE", "CHANGELOG.md", "CURSEFORGE_DESCRIPTION.md",
             "CLIENT_COMPATIBILITY.md", "logo.png")

class PackageError(ValueError):
    pass


def safe_path(name):
    path = PurePosixPath(name)
    if not name or "\\" in name or path.is_absolute() or any(p in ("", ".", "..") for p in name.split("/")):
        raise PackageError("unsafe package path: " + name)
    return name


def toc_entries(text):
    entries = [safe_path(line.strip().replace("\\", "/")) for line in text.splitlines()
               if line.strip() and not line.lstrip().startswith("#")]
    if len({p.casefold() for p in entries}) != len(entries):
        raise PackageError("duplicate live manifest entry")
    if any(not p.endswith(".lua") or (p.startswith("scripts/") and not
            (p.startswith("scripts/regression_") or p == "scripts/ui_fixture.lua")) for p in entries):
        raise PackageError("TOC contains an unsupported or offline-only file")
    return entries


def version_from_toc(text):
    versions = re.findall(r"^## Version: ([^\r\n]+)$", text, re.M)
    if len(versions) != 1 or not re.fullmatch(r"\d+\.\d+\.\d+(?:-(?:alpha|beta)\.\d+)?", versions[0]):
        raise PackageError("TOC must have one valid version")
    return versions[0]


def digest(data):
    return hashlib.sha256(data).hexdigest()


def payloads(root, ref=None):
    root = Path(root).resolve()
    commit = None
    if ref:
        commit = subprocess.check_output(["git", "rev-parse", "--verify", ref + "^{commit}"], cwd=root, text=True).strip()
        names = subprocess.check_output(["git", "ls-tree", "-r", "--name-only", commit], cwd=root, text=True).splitlines()
        def read(name):
            mode = subprocess.check_output(["git", "ls-tree", commit, "--", name], cwd=root, text=True).split(" ", 1)[0]
            if mode != "100644":
                raise PackageError("package input must be a regular data file: " + name)
            return subprocess.check_output(["git", "show", commit + ":" + name], cwd=root)
    else:
        names = [str(p.relative_to(root)) for pattern in ASSETS for p in root.glob(pattern)]
        def read(name):
            path = root / name
            if path.is_symlink() or not path.is_file() or root not in path.resolve().parents:
                raise PackageError("missing or linked package input: " + name)
            return path.read_bytes()
    toc = read(ADDON + ".toc")
    text = toc.decode("utf-8")
    version = version_from_toc(text)
    selected = set(toc_entries(text)) | set(DOCUMENTS) | {ADDON + ".toc"}
    selected.update(safe_path(name) for name in names if any(fnmatch.fnmatchcase(name, pattern) for pattern in ASSETS))
    data = {name: read(name) for name in sorted(selected)}
    dependency = json.loads(data["Libs/libchev/manifest.json"])
    if dependency.get("schema") != 1 or not re.fullmatch(r"[a-f0-9]{40}", dependency.get("revision", "")):
        raise PackageError("invalid pinned library manifest")
    for name, expected in dependency["files"].items():
        key = "Libs/libchev/" + safe_path(name)
        if key not in data or digest(data[key]) != expected:
            raise PackageError("vendored library differs from its pinned manifest: " + key)
    package_manifest = {"schema": 1, "addon": ADDON, "version": version, "sourceCommit": commit,
                        "files": {name: digest(value) for name, value in data.items()}}
    data[MANIFEST] = (json.dumps(package_manifest, sort_keys=True, indent=2) + "\n").encode()
    return version, data


def verify_archive(data, expected=None):
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            entries = archive.infolist()
            if len(entries) > 1000 or sum(p.file_size for p in entries) > MAX_BYTES:
                raise PackageError("archive exceeds package limits")
            names = set()
            for entry in entries:
                safe_path(entry.filename)
                if not entry.filename.startswith(ADDON + "/") or entry.filename.casefold() in names:
                    raise PackageError("archive has an unexpected root or duplicate path")
                if entry.flag_bits & 1 or (entry.external_attr >> 16) & 0o170000 == 0o120000:
                    raise PackageError("archive contains encrypted or linked entries")
                names.add(entry.filename.casefold())
            manifest = json.loads(archive.read(ADDON + "/" + MANIFEST))
            if manifest.get("schema") != 1 or manifest.get("addon") != ADDON or not isinstance(manifest.get("files"), dict):
                raise PackageError("invalid package manifest")
            hashes = manifest["files"]
            for name in hashes: safe_path(name)
            if set(archive.namelist()) != {ADDON + "/" + p for p in hashes} | {ADDON + "/" + MANIFEST}:
                raise PackageError("archive contents differ from package manifest")
            contents = {p: archive.read(ADDON + "/" + p) for p in hashes}
            if any(digest(contents[p]) != h for p, h in hashes.items()):
                raise PackageError("package content hash mismatch")
            toc = contents[ADDON + ".toc"].decode("utf-8")
            if version_from_toc(toc) != manifest.get("version") or not set(toc_entries(toc)) <= set(contents):
                raise PackageError("package version or live load manifest mismatch")
            if not set(DOCUMENTS) <= set(contents):
                raise PackageError("package is missing mandatory assets or licenses")
            dependency = json.loads(contents["Libs/libchev/manifest.json"])
            if any(digest(contents["Libs/libchev/" + safe_path(p)]) != h for p, h in dependency["files"].items()):
                raise PackageError("package vendored library does not match its pin")
            if expected is not None:
                actual = dict(contents, **{MANIFEST: archive.read(ADDON + "/" + MANIFEST)})
                if actual != expected: raise PackageError("archive differs from source payloads")
            return manifest
    except (zipfile.BadZipFile, KeyError, TypeError, UnicodeError, json.JSONDecodeError, RuntimeError) as error:
        raise PackageError("invalid installation archive: " + str(error)) from error


def package(root, output, ref=None):
    version, contents = payloads(root, ref)
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, data in sorted(contents.items()):
            entry = zipfile.ZipInfo(ADDON + "/" + name, (1980, 1, 1, 0, 0, 0))
            entry.compress_type, entry.create_system = zipfile.ZIP_DEFLATED, 3
            entry.external_attr = 0o100644 << 16
            archive.writestr(entry, data, compresslevel=9)
    data = stream.getvalue()
    verify_archive(data, contents)
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(data)
    output.with_suffix(".sha256").write_text(digest(data) + "  " + output.name + "\n")
    return version, len(contents), digest(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--ref", help="Build exactly this git tag/commit, ignoring working-tree files")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    version, count, sha = package(args.root, args.output, args.ref)
    print(f"{ADDON} {version}: {count} verified files; SHA256 {sha}")

if __name__ == "__main__":
    main()
