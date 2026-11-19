#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
# See LICENSING.md for scope and preserved third-party notices.
"""Validate and publish a release locally, in order. --check never publishes.

CurseForge is handed the pushed tag through its existing webhook. This command
does not poll CurseForge, download its files, or wait for GitHub Actions.
"""

import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True

import discord_changelog as discord
import package
import validate_release


class ReleaseError(ValueError):
    pass


@contextmanager
def publication_lock(root):
    directory = root / ".local/releases"
    directory.mkdir(parents=True, exist_ok=True)
    with (directory / ".publish.lock").open("a") as handle:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ReleaseError("another local release is already running in this checkout") from None
        try:
            yield
        finally:
            fcntl.flock(handle, fcntl.LOCK_UN)


def run(root, arguments, *, capture=False, env=None):
    result = subprocess.run(arguments, cwd=root, env=env, text=True,
                            stdout=subprocess.PIPE if capture else None,
                            stderr=subprocess.PIPE if capture else None)
    if result.returncode:
        # Captured auth/API output can contain sensitive data. Do not echo it.
        raise ReleaseError(Path(arguments[0]).name + " command failed (exit " + str(result.returncode) + ")")
    return result.stdout.strip() if capture else None


def git(root, *args):
    return run(root, ["git", *args], capture=True)


def release_tag(value):
    if not re.fullmatch(r"v\d+\.\d+\.\d+(?:-(?:alpha|beta)\.\d+)?", value):
        raise ReleaseError("expected a release tag such as v10.0.2 or v10.1.0-beta.1")
    return value


def exact_checkout(root, tag):
    sha = git(root, "rev-parse", "--verify", "refs/tags/" + release_tag(tag) + "^{commit}")
    if sha != git(root, "rev-parse", "HEAD") or git(root, "status", "--porcelain"):
        raise ReleaseError("release requires a clean checkout at the exact tag; commit implementation changes first")
    return sha


def check_origin(root, repository):
    url = git(root, "remote", "get-url", "origin")
    if url not in {"https://github.com/" + repository, "https://github.com/" + repository + ".git",
                   "git@github.com:" + repository, "git@github.com:" + repository + ".git",
                   "ssh://git@github.com/" + repository, "ssh://git@github.com/" + repository + ".git"}:
        raise ReleaseError("origin does not match the intended GitHub repository")


def local_credentials(root):
    if not os.environ.get("DISCORD_BOT_TOKEN"):
        raise ReleaseError("load DISCORD_BOT_TOKEN into the local environment before releasing")
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if not token:
        token = run(root, ["gh", "auth", "token", "--hostname", "github.com"], capture=True)
    if not token:
        raise ReleaseError("sign in with gh auth login before releasing")
    return {**os.environ, "GH_TOKEN": token}


def receipt_matches(path, sha):
    try:
        value = json.loads(path.read_text())
        return value == {"schema": 1, "commit": sha, "passed": True,
                         "runner_sha256": validate_release.runner_sha256()}
    except (OSError, ValueError):
        return False


def validate(root, tag, sha, output, args):
    receipt = output / "validation.json"
    if args.tag and receipt_matches(receipt, sha):
        print("Reusing successful local validation for this exact commit.", flush=True)
        return
    command = [args.python, str(root / "scripts/validate_release.py"), "--root", str(root),
               "--ref", tag, "--receipt", str(receipt), "--python", args.python]
    for name in ("lua51", "lua52"):
        value = getattr(args, name)
        if value:
            command += ["--" + name, value]
    run(root, command)
    if not receipt_matches(receipt, sha):
        raise ReleaseError("local validation did not certify the release commit")


def build_artifacts(root, tag, sha, output):
    archive = output / ("QuestTogether-" + tag + ".zip")
    version, _, _ = package.package(root, archive, sha)
    if "v" + version != tag:
        raise ReleaseError("package version differs from the release tag")
    source = output / ("QuestTogether-" + tag + "-source.tar.gz")
    run(root, ["git", "archive", "--format=tar.gz", "--prefix=QuestTogether-source/",
               "--output=" + str(source), sha])
    checksum = source.with_suffix(source.suffix + ".sha256")
    checksum.write_text(hashlib.sha256(source.read_bytes()).hexdigest() + "  " + source.name + "\n")
    return [archive, archive.with_suffix(".sha256"), source, checksum]


def release_body(root, tag, sha, repository):
    notes, actual = discord.load_notes(root, tag, exact=True)
    if actual != sha:
        raise ReleaseError("release commit changed while preparing notes")
    lines = [notes["welcome"], ""]
    for section in notes["sections"]:
        lines += ["## " + section["title"], ""]
        lines += ["- " + item for item in section["items"]]
        if section.get("tip"):
            lines += ["", discord.markdown_tip(section["tip"])]
        lines.append("")
    base = "https://github.com/" + repository
    lines += ["## Source and licensing", "",
              "[Exact corresponding source](" + base + "/tree/" + sha + ") (commit `" + sha + "`). "
              "The attached source archive includes editable assets and build scripts.", "",
              "Project-owned work is GPL-3.0-only; [licensing scope and preserved third-party terms]("
              + base + "/blob/" + sha + "/LICENSING.md) apply. Earlier MIT permissions remain unchanged.", ""]
    return "\n".join(lines)


def remote_branch_sha(root, branch, env):
    ref = "refs/heads/" + branch
    git(root, "check-ref-format", ref)
    value = run(root, ["git", "ls-remote", "--refs", "origin", ref], capture=True, env=env)
    if not value:
        return None
    fields = value.split()
    if len(fields) != 2 or fields[1] != ref or not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", fields[0]):
        raise ReleaseError("origin returned an unexpected branch reference")
    return fields[0]


def is_ancestor(root, ancestor, descendant):
    result = subprocess.run(["git", "merge-base", "--is-ancestor", ancestor, descendant],
                            cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode not in (0, 1):
        raise ReleaseError("could not compare the release commit with the remote branch")
    return result.returncode == 0


def release_branch_update(root, branch, remote_sha, sha, env):
    if remote_sha is None:
        return True
    try:
        git(root, "cat-file", "-e", remote_sha + "^{commit}")
    except ReleaseError:
        # Fetch the exact observation, not a branch name that can move between
        # ls-remote and fetch. Leave local branches, tags and FETCH_HEAD alone.
        try:
            run(root, ["git", "fetch", "--no-tags", "--no-prune", "--no-prune-tags",
                       "--no-write-fetch-head", "--recurse-submodules=no", "origin", remote_sha], env=env)
        except ReleaseError as error:
            raise ReleaseError("could not fetch the observed origin/" + branch
                               + " commit; resume the release to recheck the remote branch") from error
    if git(root, "rev-parse", "--verify", remote_sha + "^{commit}") != remote_sha:
        raise ReleaseError("remote branch does not identify a commit")
    if is_ancestor(root, sha, remote_sha):
        return False
    if is_ancestor(root, remote_sha, sha):
        return True
    raise ReleaseError("origin/" + branch + " has diverged from the validated release commit; "
                       "publication stopped. Reconcile the branch and prepare a new release "
                       "that includes its changes before publishing")


def push_release_refs(root, tag, sha, branch, env):
    remote_sha = remote_branch_sha(root, branch, env) if branch else None
    for attempt in range(2):
        update_branch = bool(branch) and release_branch_update(root, branch, remote_sha, sha, env)
        refs = ([sha + ":refs/heads/" + branch] if update_branch else []) + ["refs/tags/" + tag]
        if branch and not update_branch:
            print("origin/" + branch + " already contains the release; preserving its current tip.", flush=True)
        try:
            # A normal atomic push never rewinds a concurrent branch update,
            # and a rejected branch cannot leave the tag partially published.
            run(root, ["git", "push", "--atomic", "origin", *refs], env=env)
            return
        except ReleaseError:
            if not update_branch or attempt:
                raise
            latest = remote_branch_sha(root, branch, env)
            if latest == remote_sha:
                raise
            if latest is None:
                raise ReleaseError("origin/" + branch + " was removed during publication; "
                                   "check the intended source branch before resuming") from None
            remote_sha = latest
            print("Remote branch changed during publication; checking it once more.", flush=True)


def find_github_release(api, prefix, tag):
    # The tag endpoint exposes published releases only. Authenticated listings
    # include drafts; keep their numeric identity for subsequent reads.
    try:
        return api.request(prefix + "/releases/tags/" + tag)
    except discord.APIHTTPError as error:
        if error.status != 404:
            raise
    matches = []
    for page in range(1, 21):
        entries = api.request(prefix + "/releases?per_page=100&page=" + str(page))
        if not isinstance(entries, list) or any(not isinstance(entry, dict) for entry in entries):
            raise ReleaseError("GitHub returned an invalid release listing")
        matches.extend(entry for entry in entries if entry.get("tag_name") == tag)
        if len(matches) > 1:
            raise ReleaseError("multiple GitHub releases use this tag; resolve the duplicate drafts before resuming")
        if len(entries) < 100:
            return matches[0] if matches else None
    raise ReleaseError("GitHub release listing exceeds the lookup limit; no release was created")


def publish_github(root, repository, tag, sha, artifacts, body, env):
    api = discord.API(discord.GITHUB_API, env["GH_TOKEN"])
    prefix = "/repos/" + repository
    repo = api.request(prefix)
    if repo.get("full_name", "").casefold() != repository.casefold() or repo.get("private") is not False:
        raise ReleaseError("release publication requires the intended public repository")
    if discord.remote_tag_sha(api, prefix, tag) != sha:
        raise ReleaseError("remote release tag differs from the locally validated commit")
    existing = find_github_release(api, prefix, tag)
    prerelease = "-" in tag
    if existing is not None and existing.get("tag_name") != tag:
        raise ReleaseError("GitHub returned a different release tag")
    if existing and not existing.get("draft"):
        # Public releases are immutable here. Existing Discord markers make a
        # resumed announcement safe without editing the published release.
        notes, _ = discord.load_notes(root, tag, exact=True)
        release = discord.verify_release(api, repository, tag, sha)
        discord.verify_archive(release, repository, tag, notes,
                               localized_lua=(root / discord.LOCALIZED_LUA).read_bytes())
        print("GitHub release is already published; resuming its announcement.", flush=True)
        return
    if existing is None:
        # Use the creation response's identity. Immediately listing again can
        # return the pre-creation view and strand an otherwise valid draft.
        existing = api.request(prefix + "/releases", method="POST", payload={
            "tag_name": tag, "target_commitish": sha,
            "name": "QuestTogether " + tag[1:], "body": body.read_text(),
            "draft": True, "prerelease": prerelease,
        })
    release_id = existing.get("id") if existing else None
    if type(release_id) is not int or release_id <= 0:
        raise ReleaseError("GitHub draft release identity is unavailable; resume to check it again")
    release_path = prefix + "/releases/" + str(release_id)
    # An interrupted upload resumes missing files. Never overwrite an asset,
    # including if a different publisher has already made the release public.
    existing = api.request(release_path)
    if existing.get("tag_name") != tag or existing.get("draft") is not True:
        raise ReleaseError("draft release changed before its upload; resume to recheck the published release")
    assets = existing.get("assets", [])
    missing = []
    for path in artifacts:
        matches = [asset for asset in assets if asset.get("name") == path.name]
        if not matches:
            missing.append(path)
            continue
        if len(matches) != 1 or matches[0].get("state") != "uploaded":
            raise ReleaseError("draft contains an ambiguous or unfinished upload: " + path.name)
        expected = hashlib.sha256(path.read_bytes()).hexdigest()
        digest = matches[0].get("digest")
        if digest is None:
            # Older GitHub assets may lack digest metadata. This is a one-time
            # read of an existing GitHub draft asset, never a CurseForge check.
            with tempfile.TemporaryDirectory(prefix="qt-release-asset-") as directory:
                run(root, ["gh", "release", "download", tag, "--repo", repository,
                           "--pattern", path.name, "--dir", directory], env=env)
                digest = "sha256:" + hashlib.sha256((Path(directory) / path.name).read_bytes()).hexdigest()
        if digest != "sha256:" + expected:
            raise ReleaseError("existing draft asset differs from the local release: " + path.name)
    if missing:
        run(root, ["gh", "release", "upload", tag, "--repo", repository, *map(str, missing)], env=env)
    current = api.request(release_path)
    if current.get("tag_name") != tag or current.get("draft") is not True:
        raise ReleaseError("draft release changed before publication; resume to recheck it")
    run(root, ["gh", "release", "edit", tag, "--repo", repository, "--draft=false",
               "--prerelease=" + str(prerelease).lower(), "--notes-file", str(body)], env=env)


def publish(root, repository, args, bump):
    env = local_credentials(root)
    with publication_lock(root):
        if bump:
            run(root, bump + ["--local-only"])
        tag = args.tag or release_tag("v" + discord.toc_version((root / discord.TOC_FILE).read_text()))
        sha = exact_checkout(root, tag)
        output = root / ".local/releases" / tag
        output.mkdir(parents=True, exist_ok=True)
        print("Validating " + tag + " locally...", flush=True)
        validate(root, tag, sha, output, args)
        artifacts = build_artifacts(root, tag, sha, output)
        body = output / "github-notes.md"
        body.write_text(release_body(root, tag, sha, repository), encoding="utf-8")
        if exact_checkout(root, tag) != sha:
            raise ReleaseError("checkout changed during validation")
        branch = args.branch or git(root, "branch", "--show-current")
        print("Pushing the validated release tag; handing off to CurseForge.", flush=True)
        push_release_refs(root, tag, sha, branch, env)
        publish_github(root, repository, tag, sha, artifacts, body, env)
        print("Posting the release notes to Discord locally...", flush=True)
        run(root, [args.python, "scripts/discord_changelog.py", "--root", str(root), "--post",
                   "--tag", tag, "--repository", repository, "--all-locales"], env=env)
        print("Published " + tag + " on GitHub and announced it on Discord. "
              "The tag was handed to CurseForge; its processing is not monitored.")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    choice = parser.add_mutually_exclusive_group(required=True)
    choice.add_argument("--bump", choices=("major", "minor", "patch"))
    choice.add_argument("--tag", type=release_tag, help="resume an already prepared local release")
    parser.add_argument("--channel", choices=("stable", "beta", "alpha"), default="stable")
    parser.add_argument("--reuse-notes", action="store_true")
    parser.add_argument("--check", action="store_true", help="local preflight only; no writes or network")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--repository", default=discord.DEFAULT_REPOSITORY)
    parser.add_argument("--branch", help="source branch to publish from an isolated detached checkout")
    parser.add_argument("--lua51")
    parser.add_argument("--lua52")
    parser.add_argument("--python", default=sys.executable)
    args = parser.parse_args(argv)
    try:
        root = args.root.resolve()
        repository = discord.repository_name(args.repository)
        if args.branch:
            git(root, "check-ref-format", "refs/heads/" + args.branch)
        if args.tag and (args.reuse_notes or args.channel != "stable"):
            raise ReleaseError("--channel and --reuse-notes apply only to --bump")
        check_origin(root, repository)
        bump = ["bash", "scripts/bump_version.sh", args.bump, args.channel] if args.bump else None
        if args.reuse_notes:
            bump += ["--reuse-notes"]
        if bump:
            run(root, bump + ["--check"])
        else:
            exact_checkout(root, args.tag)
            discord.load_notes(root, args.tag, exact=True)
        if args.check:
            print("Preflight passed. Release steps: prepare locally; validate; package; push tag; "
                  "publish GitHub; announce on Discord. CurseForge handles the tag independently.")
            return 0
        publish(root, repository, args, bump)
        return 0
    except (ReleaseError, discord.ChangelogError, discord.NotesError, package.PackageError, OSError, ValueError) as error:
        print("Local release stopped: " + str(error), file=sys.stderr)
        print("If a release tag was prepared, fix the reported issue and resume with --tag <that-tag>.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
