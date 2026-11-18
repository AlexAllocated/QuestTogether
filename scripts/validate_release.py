#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
# See LICENSING.md for scope and preserved third-party notices.
"""Run all release checks locally against an isolated, exact Git commit.

No dependencies are installed and no remote services are contacted. A successful
run writes a receipt outside tracked sources for the local release command.
"""

import argparse
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
    ("test_validate_release.py",), ("test_release.py",),
)
LOCALES = ("enGB", "deDE", "frFR", "esES", "esMX", "ptBR", "ruRU", "itIT", "koKR", "zhCN", "zhTW")
CLIENTS = ("retail", "forever", "era", "tbc", "mists", "titan")
LUA_CHECKS = ("test.lua", "test_loader.lua", "regression_gamepad_adapter.lua",
              "regression_gamepad_launcher.lua", "regression_party_map_native.lua", "settings_smoke.lua")


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
    if not capture:
        print("Checking " + label + "...", flush=True)
    result = subprocess.run(command, cwd=cwd, env=env, text=True, input=input,
                            stdout=subprocess.PIPE if capture else None,
                            stderr=subprocess.PIPE if capture else None)
    if result.returncode:
        raise ValidationError(label + " failed (exit " + str(result.returncode) + ")")
    return result.stdout.strip() if capture else None


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
    for version in ("5.1", "5.2"):
        actual = run([tools["lua" + version], "-e", "io.write(_VERSION)"], cwd=snapshot, env=env,
                     label="Lua " + version + " interpreter", capture=True)
        if actual != "Lua " + version:
            raise ValidationError("Lua " + version + " executable reports " + actual)
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


def validate(snapshot, tools, env):
    python = tools["python"]
    for arguments in PYTHON_CHECKS:
        run([python, "scripts/" + arguments[0], *arguments[1:]], cwd=snapshot, env=env, label=arguments[0])
    for version in ("5.1", "5.2"):
        lua = tools["lua" + version]
        lua_env = dict(env, QT_TEST_LUA=lua)
        run([python, "scripts/test_release_notes.py"], cwd=snapshot, env=lua_env,
            label="release-note Lua " + version + " contracts")
        for script in LUA_CHECKS:
            run([lua, "scripts/" + script], cwd=snapshot, env=lua_env, label=script + " (Lua " + version + ")")
        for script in ("test_developer_crypto.py", "bindings_smoke.py"):
            run([python, "scripts/" + script, lua], cwd=snapshot, env=lua_env, label=script + " (Lua " + version + ")")
        run([python, "-m", "unittest", "discover", "-s", "services/vip", "-p", "test_*.py"],
            cwd=snapshot, env=lua_env, label="VIP service and Lua " + version + " interoperability")
        for mode in ("reverse", "live", "live-reverse"):
            run([lua, "scripts/test.lua", ".", mode], cwd=snapshot, env=lua_env, label="Lua " + version + " " + mode)
        for locale in LOCALES:
            run([lua, "scripts/test.lua", ".", "locale"], cwd=snapshot,
                env=dict(lua_env, QT_TEST_LOCALE=locale), label="Lua " + version + " locale " + locale)
        for client in CLIENTS:
            run([lua, "scripts/test.lua", ".", "normal", client], cwd=snapshot,
                env=lua_env, label="Lua " + version + " client " + client)
        for client in ("retail", "forever"):
            run([lua, "scripts/location_client_profiles.lua", ".", client], cwd=snapshot,
                env=lua_env, label="Lua " + version + " locations " + client)
        # loadfile compiles each file without executing it, as luac -p does.
        # Decimal byte escapes work in both Lua versions and for every filename.
        paths = sorted(str(path.relative_to(snapshot)) for path in snapshot.rglob("*.lua")
                       if ".git" not in path.relative_to(snapshot).parts)
        syntax = "\n".join('assert(loadfile("' + "".join("\\%03d" % byte for byte in path.encode("utf-8")) + '"))'
                           for path in paths)
        run([lua, "-"], cwd=snapshot, env=lua_env, input=syntax, label="all Lua " + version + " syntax")
    run([tools["bash"], "-n", "scripts/bump_version.sh"], cwd=snapshot, env=env, label="release shell syntax")
    run([tools["git"], "diff", "--check"], cwd=snapshot, env=env, label="Git whitespace")
    # package.py validates every vendored library hash against its pinned
    # manifest and verifies the resulting complete installation archive.
    run([python, "scripts/package.py", "--ref", "HEAD", "--output", "dist/QuestTogether.zip"],
        cwd=snapshot, env=env, label="exact-commit package and pinned library")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--ref", default="HEAD")
    parser.add_argument("--receipt", type=Path, required=True, help="success receipt outside tracked sources (ignored paths allowed)")
    parser.add_argument("--lua51", default=os.environ.get("LUA51", "lua5.1"))
    parser.add_argument("--lua52", default=os.environ.get("LUA52", "lua5.2"))
    parser.add_argument("--python", default=sys.executable)
    args = parser.parse_args(argv)
    try:
        validation_digest = runner_sha256()
        root, receipt = args.root.resolve(), args.receipt.resolve()
        env = {key: value for key, value in os.environ.items()
               if not key.startswith("GIT_") and key not in (
                   "QT_TEST_LOCALE", "QT_TEST_LUA", "DISCORD_BOT_TOKEN", "GH_TOKEN", "GITHUB_TOKEN")}
        env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull, PYTHONDONTWRITEBYTECODE="1")
        git_tool = executable("git", "Git")
        check_receipt_path(root, receipt, git_tool, env)
        # A failed rerun must never leave a previous success at the requested path.
        receipt.unlink(missing_ok=True)
        tools = {name: executable(value, label) for name, value, label in (
            ("bash", "bash", "Bash"), ("openssl", "openssl", "OpenSSL"),
            ("python", args.python, "Python"), ("lua5.1", args.lua51, "Lua 5.1"), ("lua5.2", args.lua52, "Lua 5.2"))}
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
            for name, target in (("lua5.1", tools["lua5.1"]), ("lua5.2", tools["lua5.2"])):
                (aliases / name).symlink_to(target)
            python_alias = aliases / "python3"
            python_alias.write_text("#!" + tools["bash"] + "\nexec " + shlex.quote(tools["python"]) + ' "$@"\n')
            python_alias.chmod(0o700)
            env["PATH"] = str(aliases) + os.pathsep + env.get("PATH", "")
            preflight(snapshot, tools, env)
            validate(snapshot, tools, env)
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
