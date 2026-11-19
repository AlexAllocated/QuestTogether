#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
# See LICENSING.md for scope and preserved third-party notices.
"""Prepare a release, then publish it in a detached local systemd user service.

The service owns an independent Git clone and finishes release.py through its
final Discord announcement. No GitHub Actions or CurseForge polling is used.
"""

import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True

DEFAULT_REPOSITORY = "AlexAllocated/QuestTogether"
ACTIVE_STATES = {"queued", "running"}
SERVICE_ENVIRONMENT = (
    "HOME", "PATH", "LANG", "LC_ALL", "XDG_RUNTIME_DIR", "XDG_CONFIG_HOME",
    "DBUS_SESSION_BUS_ADDRESS", "DISPLAY", "WAYLAND_DISPLAY", "SSH_AUTH_SOCK",
    "GH_CONFIG_DIR", "GH_TOKEN", "DISCORD_BOT_TOKEN", "DISCORD_CHANGELOG_CHANNEL_ID",
)


class DeployError(ValueError):
    pass


def now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def run(root, command, *, env=None):
    result = subprocess.run(command, cwd=root, env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        # Git, authentication tools and systemd can echo their environment or
        # remote input on failure. Keep it out of terminal output and metadata.
        raise DeployError(Path(command[0]).name + " failed (exit " + str(result.returncode) + ")")
    return result.stdout.strip()


def git(root, *arguments):
    return run(root, ["git", *arguments])


def executable(value, label):
    found = shutil.which(value) if value else None
    if not found:
        raise DeployError("missing " + label + "; supply an installed executable")
    # Do not resolve virtualenv interpreter symlinks.
    return str(Path(found).absolute())


def release_tag(value):
    if not re.fullmatch(r"v\d+\.\d+\.\d+(?:-(?:alpha|beta)\.\d+)?", value):
        raise DeployError("expected a release tag such as v10.0.2")
    return value


def repository_name(value):
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", value):
        raise DeployError("expected a GitHub repository owner/name")
    return value


def check_origin(root, repository):
    origin = git(root, "remote", "get-url", "origin")
    allowed = {prefix + repository + suffix for prefix in (
        "https://github.com/", "git@github.com:", "ssh://git@github.com/"
    ) for suffix in ("", ".git")}
    if origin not in allowed:
        raise DeployError("origin does not match the intended GitHub repository")
    return origin


def tag_identity(root, tag):
    ref = "refs/tags/" + release_tag(tag)
    commit = git(root, "rev-parse", "--verify", ref + "^{commit}")
    tag_object = git(root, "rev-parse", "--verify", ref)
    if not all(re.fullmatch(r"[0-9a-f]{40}", value) for value in (commit, tag_object)):
        raise DeployError("release tag did not resolve to a Git commit")
    return commit, tag_object


def atomic_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent,
                                     delete=False) as handle:
        pending = Path(handle.name)
        json.dump(value, handle, indent=2, sort_keys=True)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    try:
        pending.replace(path)
    finally:
        pending.unlink(missing_ok=True)


@contextmanager
def job_lock(path, *, blocking=False):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with path.open("a") as handle:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | (0 if blocking else fcntl.LOCK_NB))
        except BlockingIOError:
            raise DeployError("this deployment is already being prepared or running") from None
        try:
            yield
        finally:
            fcntl.flock(handle, fcntl.LOCK_UN)


def save_state(job, state, **changes):
    state.update(changes, updated=now())
    atomic_json(job / "state.json", state)


def load_state(job):
    try:
        state = json.loads((job / "state.json").read_text())
        valid = (state["schema"] == 1 and state["id"] == job.name
                 and re.fullmatch(r"[0-9a-f]{40}", state["commit"])
                 and re.fullmatch(r"[0-9a-f]{40}", state["tag_object"])
                 and state["branch"] and isinstance(state["attempt"], int))
        release_tag(state["tag"])
        repository_name(state["repository"])
        if not valid:
            raise ValueError()
        return state
    except (OSError, ValueError, TypeError, KeyError):
        raise DeployError("deployment metadata is missing or invalid") from None


def deployment_directory(root):
    return root / ".local/deployments"


def find_job(root, identifier):
    base = deployment_directory(root)
    if identifier == "latest":
        try:
            identifier = json.loads((base / "latest.json").read_text())["id"]
        except (OSError, ValueError, TypeError, KeyError):
            raise DeployError("no deployment has been prepared in this checkout") from None
    if not isinstance(identifier, str) or not re.fullmatch(r"v[0-9A-Za-z.-]+-[0-9a-f]{12}", identifier):
        raise DeployError("invalid deployment ID")
    job = base / identifier
    load_state(job)
    return job


def credentials(root):
    if not os.environ.get("DISCORD_BOT_TOKEN"):
        raise DeployError("load DISCORD_BOT_TOKEN into the local environment before deploying")
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if not token:
        token = run(root, ["gh", "auth", "token", "--hostname", "github.com"])
    if not token:
        raise DeployError("sign in with gh auth login before deploying")
    env = {name: os.environ[name] for name in SERVICE_ENVIRONMENT if name in os.environ}
    env.update(GH_TOKEN=token, PYTHONDONTWRITEBYTECODE="1", GIT_TERMINAL_PROMPT="0")
    return env


def check_service_manager(root):
    executable("systemd-run", "systemd-run")
    executable("systemctl", "systemctl")
    run(root, ["systemctl", "--user", "show", "--property=Version", "--value"])


def preflight(root, args):
    command = [args.python or sys.executable, str(root / "scripts/release.py"),
               "--root", str(root), "--repository", args.repository or DEFAULT_REPOSITORY, "--check"]
    if args.bump:
        command += ["--bump", args.bump, "--channel", args.channel]
        if args.reuse_notes:
            command.append("--reuse-notes")
    else:
        command += ["--tag", args.tag]
    # Preflight has no network access. Preserve its actionable validation output.
    result = subprocess.run(command, cwd=root)
    if result.returncode:
        raise DeployError("release preflight failed; fix its reported issue before deploying")


def verify_snapshot(job, state):
    snapshot = job / "checkout"
    if tag_identity(snapshot, state["tag"]) != (state["commit"], state["tag_object"]):
        raise DeployError("deployment tag changed from the prepared release")
    if git(snapshot, "rev-parse", "HEAD") != state["commit"] or git(snapshot, "status", "--porcelain"):
        raise DeployError("deployment checkout must remain clean at its prepared commit")
    if git(snapshot, "branch", "--show-current") != state["branch"]:
        raise DeployError("deployment branch changed from the original release branch")
    if check_origin(snapshot, state["repository"]) != state["origin"]:
        raise DeployError("deployment origin changed")
    if (snapshot / ".git/objects/info/alternates").exists():
        raise DeployError("deployment must have independent Git object storage")


def import_receipt(job, state, source, *, required=False):
    if source is None:
        return False
    snapshot = job / "checkout"
    try:
        receipt = json.loads(Path(source).read_text())
        digest = hashlib.sha256((snapshot / "scripts/validate_release.py").read_bytes()).hexdigest()
        valid = receipt == {"schema": 1, "commit": state["commit"], "passed": True,
                            "runner_sha256": digest}
    except (OSError, ValueError):
        valid = False
    if not valid:
        if required:
            raise DeployError("validation receipt does not certify this exact commit and validator")
        return False
    atomic_json(snapshot / ".local/releases" / state["tag"] / "validation.json", receipt)
    return True


def prepare_snapshot(job, state, receipt=None):
    """Finish never-launched preparation without exposing a partial checkout."""
    if state["attempt"] != 0 or state.get("unit"):
        raise DeployError("only a never-launched deployment may prepare its snapshot")
    source = Path(state["source_root"])
    check = argparse.Namespace(python=state["python"], repository=state["repository"],
                               bump=None, tag=state["tag"])
    receipt_source = receipt or source / ".local/releases" / state["tag"] / "validation.json"
    if (job / "checkout").exists():
        # Preserve a previously completed snapshot, including any ignored
        # receipts. Never reset a dirty or changed checkout to make it pass.
        verify_snapshot(job, state)
        preflight(job / "checkout", check)
        import_receipt(job, state, receipt_source, required=receipt is not None)
    else:
        if tag_identity(source, state["tag"]) != (state["commit"], state["tag_object"]):
            raise DeployError("source tag changed; cannot reconstruct the prepared deployment")
        if check_origin(source, state["repository"]) != state["origin"]:
            raise DeployError("source origin changed; cannot reconstruct the prepared deployment")
        if git(source, "rev-parse", "--is-shallow-repository") != "false":
            raise DeployError("snapshot reconstruction requires full local release history")
        with tempfile.TemporaryDirectory(prefix=".preparing-", dir=job) as directory:
            pending = Path(directory)
            snapshot = pending / "checkout"
            # No alternates or hardlinks: development, GC or deletion of the
            # original checkout cannot change an accepted deployment.
            git(source, "-c", "core.hooksPath=" + os.devnull, "clone", "--no-hardlinks",
                "--no-checkout", "--quiet", "--", str(source), str(snapshot))
            git(snapshot, "config", "core.hooksPath", os.devnull)
            git(snapshot, "remote", "set-url", "origin", state["origin"])
            git(snapshot, "checkout", "--quiet", "-B", state["branch"], state["commit"])
            verify_snapshot(pending, state)
            preflight(snapshot, check)
            import_receipt(pending, state, receipt_source, required=receipt is not None)
            # Clone or preflight failures remove only this temporary staging
            # directory; --resume can retry the identical release safely.
            snapshot.replace(job / "checkout")
    if not (job / "worker.py").exists():
        with tempfile.NamedTemporaryFile(dir=job, delete=False) as handle:
            pending_worker = Path(handle.name)
            handle.write(Path(__file__).read_bytes())
            handle.flush()
            os.fsync(handle.fileno())
        try:
            pending_worker.replace(job / "worker.py")
        finally:
            pending_worker.unlink(missing_ok=True)


def service_state(job, state):
    if not state.get("unit"):
        return {}
    result = subprocess.run(["systemctl", "--user", "show", state["unit"],
                             "--property=LoadState,ActiveState,SubState,ExecMainStatus,Result"],
                            cwd=job, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    observed = dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line)
    if result.returncode and observed.get("LoadState") != "not-found":
        raise DeployError("cannot inspect the local deployment service")
    return observed


def build_service_command(job, state, env):
    command = ["systemd-run", "--user", "--quiet", "--collect", "--service-type=exec",
               "--unit=" + state["unit"], "--working-directory=" + str(job),
               "--property=KillMode=control-group", "--property=TimeoutStopSec=20",
               "--property=StandardOutput=null", "--property=StandardError=null",
               "--expand-environment=no"]
    # NAME without '=value' copies the value from systemd-run's own environment.
    # Credentials never enter argv, job metadata, scripts or log files.
    for name in sorted(env):
        command += ["--setenv=" + name]
    return command + [state["python"], str(job / "worker.py"), "--worker", str(job)]


def launch_service(job, state, env):
    attempt = state["attempt"] + 1
    unit = "questtogether-deploy-" + state["id"] + "-" + str(attempt) + ".service"
    save_state(job, state, status="queued", attempt=attempt, unit=unit,
               exit_code=None, error=None, started=None, finished=None)
    try:
        run(job, build_service_command(job, state, env), env=env)
    except (DeployError, OSError):
        save_state(job, state, status="failed", exit_code=None, finished=now(),
                   error="systemd did not confirm service startup; inspect --status before resuming")
        raise


def print_job(job, state):
    print("Deployment " + state["id"] + ": " + state["status"] + ".")
    print("Status: python3 scripts/deploy.py --root " + shlex.quote(state["source_root"]) + " --status " + state["id"])
    print("Log: " + str(job / "deploy.log"))


def start(args):
    root = args.root.resolve()
    repository = repository_name(args.repository or DEFAULT_REPOSITORY)
    origin = check_origin(root, repository)
    if args.check:
        preflight(root, args)
        return 0
    if git(root, "rev-parse", "--is-shallow-repository") != "false":
        raise DeployError("deployment requires a full local checkout and release tags")
    branch = git(root, "branch", "--show-current")
    if not branch:
        raise DeployError("start deployment from the intended release branch")
    git(root, "check-ref-format", "--branch", branch)
    env = credentials(root)
    check_service_manager(root)
    interpreters = {
        "python": executable(args.python or sys.executable, "Python"),
        "lua51": executable(args.lua51 or os.environ.get("LUA51", "lua5.1"), "Lua 5.1"),
        "lua52": args.lua52,  # Retained only for explicitly resuming older release tooling.
    }
    base = deployment_directory(root)
    with job_lock(base / ".prepare.lock"):
        # Also excludes a foreground release.py publisher in this checkout.
        with job_lock(root / ".local/releases/.publish.lock"):
            if args.bump:
                preflight(root, args)
                command = ["bash", "scripts/bump_version.sh", args.bump, args.channel, "--local-only"]
                if args.reuse_notes:
                    command.append("--reuse-notes")
                result = subprocess.run(command, cwd=root)
                if result.returncode:
                    raise DeployError("local release preparation failed; inspect existing tags before retrying")
                toc = (root / "QuestTogether.toc").read_text()
                versions = re.findall(r"^## Version:\s*(\S+)\s*$", toc, re.MULTILINE)
                if len(versions) != 1:
                    raise DeployError("prepared TOC has no unambiguous version")
                tag = release_tag("v" + versions[0])
            else:
                tag = args.tag
            commit, tag_object = tag_identity(root, tag)
            identifier = tag + "-" + commit[:12]
            job = base / identifier
            if job.exists():
                raise DeployError("deployment already exists; inspect --status " + identifier
                                  + " or resume it with --resume " + identifier)
            job.mkdir(mode=0o700)
            state = dict(schema=1, id=identifier, tag=tag, commit=commit, tag_object=tag_object,
                         branch=branch, repository=repository, origin=origin,
                         source_root=str(root), status="prepared", attempt=0, unit=None,
                         created=now(), exit_code=None, error=None, **interpreters)
            save_state(job, state)
            atomic_json(base / "latest.json", {"id": identifier})
            with job_lock(job / ".lock"):
                try:
                    prepare_snapshot(job, state, args.receipt)
                    launch_service(job, state, env)
                except (DeployError, OSError):
                    if state["status"] == "prepared":
                        save_state(job, state, status="failed", finished=now(), exit_code=None,
                                   error="deployment snapshot preparation failed")
                    raise
    print_job(job, state)
    print("The local service now owns validation, publication and the final Discord announcement. "
          "You can continue development; keep this machine running.")
    return 0


def resume(args):
    root = args.root.resolve()
    job = find_job(root, args.resume)
    with job_lock(job / ".lock"):
        state = load_state(job)
        if state["status"] == "succeeded":
            print_job(job, state)
            return 0
        check_service_manager(root)
        observed = service_state(job, state)
        if observed.get("ActiveState") in {"active", "activating", "deactivating", "reloading"}:
            raise DeployError("the deployment service is still active; inspect --status")
        for name in ("python", "lua51"):
            value = getattr(args, name)
            if value:
                state[name] = executable(value, name)
        if state.get("lua52") and args.lua52:
            state["lua52"] = executable(args.lua52, "legacy Lua 5.2")
        env = credentials(root)
        if state["attempt"] == 0 and not state.get("unit"):
            prepare_snapshot(job, state, args.receipt)
        else:
            verify_snapshot(job, state)
            if args.receipt:
                import_receipt(job, state, args.receipt, required=True)
        launch_service(job, state, env)
    print_job(job, state)
    print("Resumed the same prepared release without changing its version or tag.")
    return 0


def status(args):
    job = find_job(args.root.resolve(), args.status)
    state = load_state(job)
    if state["status"] in ACTIVE_STATES:
        try:
            with job_lock(job / ".lock"):
                state = load_state(job)
                observed = service_state(job, state)
                if state["status"] in ACTIVE_STATES and observed.get("ActiveState") not in {
                    "active", "activating", "deactivating", "reloading"
                }:
                    save_state(job, state, status="interrupted", finished=now(),
                               exit_code=None, error="service stopped before recording completion; resume this job")
        except DeployError:
            # The worker owns its lock while running. Manager unavailability
            # must likewise never be mistaken for proof of completion.
            pass
    print(json.dumps(state, indent=2, sort_keys=True))
    print("Log: " + str(job / "deploy.log"))
    if state["status"] in {"failed", "interrupted"}:
        print("After fixing the reported issue, resume with --resume " + state["id"] + ".")
    return 0


def notify(state):
    program = shutil.which("notify-send")
    if not program:
        return
    try:
        subprocess.run([program, "QuestTogether deployment " + state["status"],
                        state["tag"] + ": " + ("GitHub published and Discord announced."
                        if state["status"] == "succeeded" else "Check the deployment log and resume after fixing the issue.")],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        pass


def worker(job):
    job = Path(job).resolve()
    with job_lock(job / ".lock", blocking=True):
        state = load_state(job)
        if state["status"] == "succeeded":
            return 0
        if state["status"] != "queued":
            raise DeployError("worker may only start a queued deployment; use --resume")
        child = None
        exit_code = 1
        error = "deployment worker failed; inspect deploy.log"
        handlers = {}

        def stopped(signum, frame):
            raise InterruptedError("deployment service was stopped")

        try:
            for signum in (signal.SIGTERM, signal.SIGINT):
                handlers[signum] = signal.signal(signum, stopped)
            save_state(job, state, status="running", started=now(), pid=os.getpid())
            verify_snapshot(job, state)
            snapshot = job / "checkout"
            command = [state["python"], "-u", str(snapshot / "scripts/release.py"),
                       "--root", str(snapshot), "--tag", state["tag"],
                       "--repository", state["repository"], "--python", state["python"],
                       "--lua51", state["lua51"]]
            if state.get("lua52"):
                command += ["--lua52", state["lua52"]]
            # Older prepared tags lack this option. The checked-out branch is
            # still original, so their existing publisher derives it correctly.
            if '"--branch"' in (snapshot / "scripts/release.py").read_text():
                command += ["--branch", state["branch"]]
            secrets = [os.environ[name] for name in ("GH_TOKEN", "GITHUB_TOKEN", "DISCORD_BOT_TOKEN")
                       if os.environ.get(name)]
            with (job / "deploy.log").open("a", encoding="utf-8", buffering=1) as log:
                os.chmod(job / "deploy.log", 0o600)
                log.write("\n" + now() + " Starting " + state["tag"] + " attempt " + str(state["attempt"]) + ".\n")
                child = subprocess.Popen(command, cwd=snapshot, stdout=subprocess.PIPE,
                                         stderr=subprocess.STDOUT, text=True, errors="replace", bufsize=1)
                for line in child.stdout:
                    for secret in secrets:
                        line = line.replace(secret, "[REDACTED]")
                    log.write(line)
                exit_code = child.wait()
                if exit_code:
                    error = "local publisher failed (exit " + str(exit_code) + "); inspect deploy.log"
                else:
                    error = None
        except InterruptedError:
            exit_code, error = 143, "deployment service was stopped; resume this job"
        except DeployError as failure:
            error = str(failure)
        except (OSError, ValueError):
            # Do not serialize arbitrary exception strings (which may include
            # credential-bearing command/environment data).
            pass
        finally:
            if child is not None and child.poll() is None:
                try:
                    child.terminate()
                except ProcessLookupError:
                    pass
                try:
                    child.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()
            if child is not None and child.stdout is not None:
                child.stdout.close()
            for signum, handler in handlers.items():
                signal.signal(signum, handler)
            save_state(job, state, status="succeeded" if exit_code == 0 else "failed",
                       exit_code=exit_code, error=error, finished=now(), pid=None)
            if error:
                with (job / "deploy.log").open("a", encoding="utf-8") as log:
                    log.write(now() + " " + error + ".\n")
                os.chmod(job / "deploy.log", 0o600)
            notify(state)
        return exit_code if exit_code >= 0 else 128 - exit_code


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    choice = parser.add_mutually_exclusive_group(required=True)
    choice.add_argument("--bump", choices=("major", "minor", "patch"))
    choice.add_argument("--tag", help="adopt an existing tag without bumping")
    choice.add_argument("--status", nargs="?", const="latest", metavar="JOB")
    choice.add_argument("--resume", nargs="?", const="latest", metavar="JOB")
    choice.add_argument("--worker", type=Path, help=argparse.SUPPRESS)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--repository")
    parser.add_argument("--channel", choices=("stable", "alpha", "beta"), default="stable")
    parser.add_argument("--reuse-notes", action="store_true")
    parser.add_argument("--check", action="store_true", help="preflight only; no writes or service")
    parser.add_argument("--receipt", type=Path, help="reuse only a matching successful validation receipt")
    parser.add_argument("--python")
    parser.add_argument("--lua51")
    parser.add_argument("--lua52", help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    try:
        if not args.bump and (args.reuse_notes or args.channel != "stable"):
            raise DeployError("--channel and --reuse-notes apply only to --bump")
        if args.check and not (args.bump or args.tag):
            raise DeployError("--check requires --bump or --tag")
        if args.receipt and not (args.tag or args.resume):
            raise DeployError("--receipt requires --tag or --resume")
        if args.tag:
            args.tag = release_tag(args.tag)
        if args.worker:
            return worker(args.worker)
        if args.status:
            return status(args)
        if args.resume:
            return resume(args)
        return start(args)
    except (DeployError, OSError, ValueError) as error:
        print("Deployment stopped: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
