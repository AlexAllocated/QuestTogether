#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
# See LICENSING.md for scope and preserved third-party notices.
"""Validate an exact Git commit locally, selecting additional checks by changes.

No dependencies are installed and no remote services are contacted. A successful
run writes a receipt outside tracked sources for the local release command.
"""

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
from check_release_notes import version_key

sys.dont_write_bytecode = True

PYTHON_CHECKS = (
    ("check_release_notes.py", "--check", "--release-history"),
    ("localization.py",), ("test_localization.py",), ("changelogs.py",),
    ("test_changelogs.py",), ("test_release_history.py",),
    ("test_generate_release_notes.py",), ("test_generate_localized_notes.py",),
    ("test_release_note_facts.py",), ("test_prepare_release_notes.py",),
    ("test_author_release_notes.py",), ("test_codex_note_author.py",),
    ("test_note_data_evidence.py",), ("test_discord_changelog.py",),
    ("test_package.py",), ("check_architecture.py",),
    ("check_live_test_numeric.py",), ("test_live_test_numeric.py",),
    ("test_validate_release.py",), ("test_architecture.py",), ("test_release.py",), ("test_deploy.py",),
    ("test_curseforge_upload.py",),
)
LOCALES = ("enGB", "deDE", "frFR", "esES", "esMX", "ptBR", "ruRU", "itIT", "koKR", "zhCN", "zhTW")
CLIENTS = ("retail", "forever", "era", "tbc", "mists", "titan")
LUA_CHECKS = ("test.lua", "test_routine_selection.lua", "test_loader.lua", "regression_gamepad_adapter.lua",
              "regression_gamepad_launcher.lua", "regression_party_map_native.lua", "settings_smoke.lua")
from architecture_domains import PRESENTATION, SHARED_RUNTIME

FULL_SCOPE = {"stress": True, "tools": True, "base": None, "reason": "full validation requested"}


def changed_scope(paths):
    scope = {"stress": False, "tools": False}
    for name in paths:
        if name in SHARED_RUNTIME:
            scope.update(stress=True, tools=True)
            continue
        elif name in PRESENTATION or name.endswith(".md"):
            continue
        if name.startswith(("locales/", "release_notes/", "changelogs/")) and name.endswith((".json", ".md")):
            continue
        if name in {"release_notes.json", "release_notes_reuse.json"}:
            continue
        if name.startswith("Media/") and name.endswith((".svg", ".tga", ".png", ".ogg", ".json", ".txt")):
            continue
        if name in {"scripts/validate_release.py", "scripts/test_validate_release.py", "scripts/architecture_domains.py", "scripts/check_architecture.py"}:
            scope.update(stress=True, tools=True)
        elif name.startswith("scripts/") and name.endswith((".py", ".sh")):
            scope["tools"] = True
        elif name in {".pkgmeta", "LICENSE", "NOTICE"} or name.startswith("LICENSES/"):
            scope["tools"] = True
        else:
            # Core, communications, crypto, manifests, Lua fixtures and unknown
            # paths retain stress/order coverage. New files never silently opt out.
            scope.update(stress=True, tools=True)
    return scope


def select_scope(snapshot, tools, env, full=False):
    if full:
        return dict(FULL_SCOPE)
    def git(*args):
        return run([tools["git"], *args], cwd=snapshot, env=env, label="validation baseline", capture=True)
    try:
        head = git("rev-parse", "HEAD")
        tags = [tag for tag in git("tag", "--merged", "HEAD").splitlines()
                if re.fullmatch(r"v\d+\.\d+\.\d+(?:-(?:alpha|beta)\.\d+)?", tag)]
        base = next((tag for tag in sorted(tags, key=lambda tag: version_key(tag[1:]), reverse=True)
                     if git("rev-parse", tag + "^{commit}") != head), None)
        if base is None:
            return {**FULL_SCOPE, "reason": "no earlier reachable release tag"}
        paths = git("diff", "--name-only", "--no-renames", "-z", base, "HEAD").split("\0")
        changed = []
        for name in filter(None, paths):
            if name.endswith(".toc"):
                before, after = git("show", base + ":" + name), git("show", "HEAD:" + name)
                strip_version = lambda text: re.sub(r"^## Version:[^\n]*", "", text, flags=re.M)
                if strip_version(before) == strip_version(after):
                    continue
            changed.append(name)
        return {**changed_scope(changed), "base": base, "reason": str(len(changed)) + " changed paths"}
    except (ValidationError, ValueError):
        return {**FULL_SCOPE, "reason": "baseline could not be established"}


class ValidationError(ValueError):
    pass


def runner_sha256():
    return hashlib.sha256(Path(__file__).read_bytes()).hexdigest()


def executable(value, label):
    found = shutil.which(value) if value else None
    if not found:
        raise ValidationError("missing " + label + "; install it locally or supply its executable path")
    # Resolving a virtualenv's Python symlink would select the base interpreter
    # and lose the dependencies installed in that virtualenv.
    return str(Path(found).absolute())


def run(command, *, cwd, env, label, capture=False, input=None):
    started = time.monotonic()
    if not capture:
        print("Checking " + label + "...", flush=True)
    result = subprocess.run(command, cwd=cwd, env=env, text=True, input=input,
                            stdout=subprocess.PIPE if capture else None,
                            stderr=subprocess.PIPE if capture else None)
    if result.returncode:
        raise ValidationError(label + " failed (exit " + str(result.returncode) + ", "
                              + format(time.monotonic() - started, ".1f") + "s)")
    if not capture:
        print("Passed " + label + " in " + format(time.monotonic() - started, ".1f") + "s.", flush=True)
    return result.stdout.rstrip("\r\n") if capture else None


def check_receipt_path(root, receipt, git, env):
    if receipt == root:
        raise ValidationError("--receipt must be a file outside tracked sources")
    if root not in receipt.parents:
        return
    relative = str(receipt.relative_to(root))
    tracked = run([git, "ls-files", "--", relative], cwd=root, env=env,
                  label="receipt tracking check", capture=True)
    if tracked:
        raise ValidationError("--receipt must not overwrite a tracked source file")
    try:
        run([git, "check-ignore", "--quiet", "--no-index", "--", relative], cwd=root, env=env,
            label="receipt ignore check", capture=True)
    except ValidationError:
        raise ValidationError("--receipt inside the checkout must be Git-ignored and untracked") from None


def preflight(snapshot, tools, env):
    for version in ("5.1",):
        actual = run([tools["lua" + version], "-e", "io.write(_VERSION)"], cwd=snapshot, env=env,
                     label="Lua " + version + " interpreter", capture=True)
        if actual != "Lua " + version:
            raise ValidationError("Lua " + version + " executable reports " + actual)
        try:
            run([tools["lua" + version], "-e",
                 "local b=bit32 or bit or require('bit'); assert(b.bxor(1,3)%4294967296==2)"],
                cwd=snapshot, env=env, label="native Lua " + version + " bit operations", capture=True)
        except ValidationError:
            raise ValidationError("Lua " + version + " needs native bit operations; install LuaBitOp for "
                                  "Lua 5.1 and configure LUA_CPATH before deployment") from None
    run([tools["openssl"], "version"], cwd=snapshot, env=env, label="OpenSSL", capture=True)
    # The full VIP suite below determines compatibility. Dependencies must
    # already be available in the chosen interpreter; never install them here.
    code = "import cryptography, discord; from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey"
    try:
        run([tools["python"], "-c", code], cwd=snapshot, env=env,
            label="installed VIP dependencies", capture=True)
    except ValidationError:
        raise ValidationError("selected Python needs the dependencies from services/vip/requirements.txt; "
                              "prepare that environment locally and pass --python") from None


def run_jobs(snapshot, jobs):
    """Independent read-only checks share one bounded pool and separate logs."""
    def check(job):
        label, command, env, source = job
        started = time.monotonic()
        with tempfile.TemporaryFile(mode="w+", encoding="utf-8") as log:
            result = subprocess.run(command, cwd=snapshot, env=env, input=source,
                                    text=True, stdout=log, stderr=subprocess.STDOUT)
            log.seek(0)
            return label, result.returncode, time.monotonic() - started, log.read()
    print("Checking " + str(len(jobs)) + " independent jobs with at most four local workers...", flush=True)
    with ThreadPoolExecutor(max_workers=min(4, os.cpu_count() or 1)) as pool:
        pending = [pool.submit(check, job) for job in jobs]
        for future in as_completed(pending):
            label, code, elapsed, output = future.result()
            print(output, end="" if output.endswith("\n") else "\n", flush=True)
            if code:
                for other in pending:
                    other.cancel()
                raise ValidationError(label + " failed (exit " + str(code) + ")")
            print("Passed " + label + " in " + format(elapsed, ".1f") + "s.", flush=True)


def validation_jobs(snapshot, tools, env, scope):
    python, lua = tools["python"], tools["lua5.1"]
    lua_env = {key: value for key, value in env.items() if key not in ("QT_TEST_BATCH_INDEX", "QT_TEST_BATCH_COUNT")}
    lua_env["QT_TEST_LUA"] = lua
    jobs = []
    def add(label, command, environment=lua_env, source=None):
        jobs.append((label, command, environment, source))
    modes = ("normal", "reverse", "live", "live-reverse") if scope["stress"] else ("live",)
    if not scope["stress"]:
        for index in range(1, 4):
            add("Lua 5.1 routine batch " + str(index) + "/3", [lua, "scripts/test.lua", ".", "routine"],
                dict(lua_env, QT_TEST_REQUIRE_NATIVE_BIT="1", QT_TEST_TIMINGS="1",
                     QT_TEST_BATCH_INDEX=str(index), QT_TEST_BATCH_COUNT="3"))
    # Full order checks and the simulated-live run remain whole processes.
    for mode in modes:
        add("Lua 5.1 " + mode, [lua, "scripts/test.lua", ".", mode],
            dict(lua_env, QT_TEST_REQUIRE_NATIVE_BIT="1", QT_TEST_TIMINGS="1"))
    for arguments in PYTHON_CHECKS:
        if arguments[0].startswith("test_") and not scope["tools"]:
            continue
        add(arguments[0], [python, "scripts/" + arguments[0], *arguments[1:]])
    if scope["tools"]:
        add("release-note Lua 5.1 contracts", [python, "scripts/test_release_notes.py"])
    for script in LUA_CHECKS:
        if script != "test.lua":
            add(script + " (Lua 5.1)", [lua, "scripts/" + script])
    # Crypto interoperability and binding behavior are runtime checks, not
    # release-tool unit tests; retain them on every release.
    for script in ("test_developer_crypto.py", "bindings_smoke.py"):
        add(script + " (Lua 5.1)", [python, "scripts/" + script, lua])
    add("VIP service and Lua 5.1 interoperability",
        [python, "-m", "unittest", "discover", "-s", "services/vip", "-p", "test_*.py"])
    for locale in LOCALES:
        add("Lua 5.1 locale " + locale, [lua, "scripts/test.lua", ".", "locale"],
            dict(lua_env, QT_TEST_LOCALE=locale))
    for client in CLIENTS:
        add("Lua 5.1 client " + client, [lua, "scripts/test.lua", ".", "normal", client])
    for client in ("retail", "forever"):
        add("Lua 5.1 locations " + client, [lua, "scripts/location_client_profiles.lua", ".", client])
    paths = sorted(str(path.relative_to(snapshot)) for path in snapshot.rglob("*.lua")
                   if ".git" not in path.relative_to(snapshot).parts)
    syntax = "\n".join('assert(loadfile("' + "".join("\\%03d" % byte for byte in path.encode("utf-8")) + '"))'
                       for path in paths)
    add("all Lua 5.1 syntax", [lua, "-"], source=syntax)
    add("release shell syntax", [tools["bash"], "-n", "scripts/bump_version.sh"])
    add("Git whitespace", [tools["git"], "diff", "--check"])
    return jobs


def validate(snapshot, tools, env, scope=None):
    scope = dict(FULL_SCOPE) if scope is None else scope
    print("Validation baseline: " + (scope["base"] or "none") + "; " + scope["reason"] + ".", flush=True)
    print("Network stress and reverse order: " + ("included" if scope["stress"] else "unchanged; deferred")
          + ". Release-tool unit tests: " + ("included" if scope["tools"] else "unchanged; deferred") + ".", flush=True)
    run_jobs(snapshot, validation_jobs(snapshot, tools, env, scope))
    # Always verify the actual archive, manifest, licenses and pinned library,
    # independently of whether packager unit tests were selected.
    run([tools["python"], "scripts/package.py", "--ref", "HEAD", "--output", "dist/QuestTogether.zip"],
        cwd=snapshot, env=env, label="exact-commit package and pinned library")
    for flavor in ("forever", "retail-classic"):
        run([tools["python"], "scripts/package.py", "--ref", "HEAD", "--flavor", flavor,
             "--output", "dist/QuestTogether-" + flavor + ".zip"],
            cwd=snapshot, env=env, label="CurseForge " + flavor + " package")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--ref", default="HEAD")
    parser.add_argument("--receipt", type=Path, required=True, help="success receipt outside tracked sources (ignored paths allowed)")
    parser.add_argument("--lua51", default=os.environ.get("LUA51", "lua5.1"))
    parser.add_argument("--lua52", help=argparse.SUPPRESS)  # Accept old launchers; no longer required.
    parser.add_argument("--full", action="store_true", help="include all stress, reverse-order and tooling tests")
    parser.add_argument("--python", default=sys.executable)
    args = parser.parse_args(argv)
    try:
        validation_digest = runner_sha256()
        root, receipt = args.root.resolve(), args.receipt.resolve()
        env = {key: value for key, value in os.environ.items()
               if not key.startswith("GIT_") and key not in (
                   "QT_TEST_LOCALE", "QT_TEST_LUA", "QT_TEST_TIMINGS", "QT_TEST_REQUIRE_NATIVE_BIT",
                   "QT_TEST_BATCH_INDEX", "QT_TEST_BATCH_COUNT",
                   "DISCORD_BOT_TOKEN", "GH_TOKEN", "GITHUB_TOKEN", "CURSEFORGE_API_TOKEN")}
        env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull, PYTHONDONTWRITEBYTECODE="1")
        git_tool = executable("git", "Git")
        check_receipt_path(root, receipt, git_tool, env)
        # A failed rerun must never leave a previous success at the requested path.
        receipt.unlink(missing_ok=True)
        tools = {name: executable(value, label) for name, value, label in (
            ("bash", "bash", "Bash"), ("openssl", "openssl", "OpenSSL"),
            ("python", args.python, "Python"), ("lua5.1", args.lua51, "Lua 5.1"))}
        tools["git"] = git_tool
        commit = run([tools["git"], "rev-parse", "--verify", "--end-of-options", args.ref + "^{commit}"],
                     cwd=root, env=env, label="release commit", capture=True)
        if not re.fullmatch(r"[0-9a-f]{40}", commit):
            raise ValidationError("release ref did not resolve to a commit")
        shallow = run([tools["git"], "rev-parse", "--is-shallow-repository"], cwd=root, env=env,
                      label="full release history", capture=True)
        if shallow != "false":
            raise ValidationError("release validation requires a full local Git checkout and tags")
        with tempfile.TemporaryDirectory(prefix="questtogether-validation-") as directory:
            temporary = Path(directory)
            snapshot = temporary / "source"
            run([tools["git"], "-c", "core.hooksPath=" + os.devnull, "clone", "--shared", "--no-checkout", "--quiet",
                 "--", str(root), str(snapshot)], cwd=root, env=env, label="isolated local commit snapshot")
            run([tools["git"], "-c", "core.hooksPath=" + os.devnull, "checkout", "--quiet", "--detach", commit],
                cwd=snapshot, env=env, label="exact commit checkout")
            # Some existing tests discover executable names with shutil.which.
            # Make explicit interpreter overrides available to those tests too.
            aliases = temporary / "bin"
            aliases.mkdir()
            for name, target in (("lua5.1", tools["lua5.1"]),):
                (aliases / name).symlink_to(target)
            python_alias = aliases / "python3"
            python_alias.write_text("#!" + tools["bash"] + "\nexec " + shlex.quote(tools["python"]) + ' "$@"\n')
            python_alias.chmod(0o700)
            env["PATH"] = str(aliases) + os.pathsep + env.get("PATH", "")
            preflight(snapshot, tools, env)
            validate(snapshot, tools, env, select_scope(snapshot, tools, env, args.full))
        if runner_sha256() != validation_digest:
            raise ValidationError("validation runner changed during the checks; run validation again")
        receipt.parent.mkdir(parents=True, exist_ok=True)
        payload = {"schema": 1, "commit": commit, "runner_sha256": validation_digest, "passed": True}
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=receipt.parent, delete=False) as handle:
            pending = Path(handle.name)
            json.dump(payload, handle, sort_keys=True)
            handle.write("\n")
        try:
            pending.replace(receipt)
        finally:
            pending.unlink(missing_ok=True)
        print("Local release validation passed for " + commit + ".", flush=True)
        return 0
    except (ValidationError, OSError, ValueError) as error:
        print("Release validation error: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
