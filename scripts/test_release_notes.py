#!/usr/bin/env python3
"""Offline release-note contracts; all Git changes stay in temporary repositories."""

import copy
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parent
sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("release_notes_checker", SCRIPTS / "check_release_notes.py")
CHECKER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECKER)
REAL_GIT = shutil.which("git")


def sample_notes(version="1.2.3", item="Share eligible quests with your party."):
    return {"version": version, "welcome": "Welcome to QuestTogether. Open settings from the minimap.",
            "sections": [{"title": "Party quests", "items": [item]}]}


class NotesTests(unittest.TestCase):
    def test_optional_visual_example_roundtrip(self):
        notes = sample_notes()
        notes["sections"][0]["illustration"] = "quest-partners"
        parsed = CHECKER.parse_notes(json.dumps(notes))
        self.assertIn('illustration = "quest-partners"', CHECKER.render_lua(parsed))
        notes["sections"][0]["illustration"] = "unknown"
        with self.assertRaises(CHECKER.NotesError):
            CHECKER.parse_notes(json.dumps(notes))

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="questtogether-notes-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        self.env.update({"GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull,
                         "GIT_AUTHOR_NAME": "Offline notes test", "GIT_AUTHOR_EMAIL": "notes@example.invalid",
                         "GIT_COMMITTER_NAME": "Offline notes test", "GIT_COMMITTER_EMAIL": "notes@example.invalid"})
        self.root = self.new_repo("addon with spaces")

    def run_process(self, arguments, env=None, cwd=None):
        return subprocess.run(arguments, cwd=cwd or self.root, env=env or self.env,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding="utf-8")

    def git(self, *arguments, root=None):
        result = self.run_process([REAL_GIT, "-c", "commit.gpgsign=false", "-c", "core.hooksPath=" + os.devnull,
                                   *arguments], cwd=root)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def new_repo(self, name, legacy=False):
        root = self.directory / name
        (root / "scripts").mkdir(parents=True)
        for filename in ("check_release_notes.py", "bump_version.sh"):
            shutil.copyfile(SCRIPTS / filename, root / "scripts" / filename)
        (root / "QuestTogether.toc").write_text("## Version: 1.2.3\nCore.lua\nReleaseNotes.lua\n", encoding="utf-8")
        (root / "Core.lua").write_text("-- Published implementation\n", encoding="utf-8")
        if not legacy:
            notes = sample_notes()
            (root / "release_notes.json").write_text(json.dumps(notes), encoding="utf-8")
            (root / "ReleaseNotes.lua").write_text(CHECKER.render_lua(notes), encoding="utf-8")
        self.git("init", "-q", root=root)
        self.git("add", ".", root=root)
        self.git("commit", "-qm", "Fixture release", root=root)
        self.git("tag", "-a", "v1.2.3", "-m", "Fixture release", root=root)
        return root

    def write_notes(self, notes, generate=True):
        (self.root / "release_notes.json").write_text(json.dumps(notes, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        if generate:
            (self.root / "ReleaseNotes.lua").write_text(CHECKER.render_lua(notes), encoding="utf-8")

    def set_toc_version(self, version):
        (self.root / "QuestTogether.toc").write_text("## Version: " + version + "\nCore.lua\nReleaseNotes.lua\n", encoding="utf-8")

    def check(self, *arguments, success=True):
        result = self.run_process([sys.executable, str(self.root / "scripts/check_release_notes.py"), *arguments])
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result.stdout + result.stderr

    def commit_release(self, version, item):
        self.set_toc_version(version)
        self.write_notes(sample_notes(version, item))
        self.git("add", ".")
        self.git("commit", "-qm", "Fixture " + version)
        self.git("tag", "-a", "v" + version, "-m", "Fixture " + version)

    def guarded_git_env(self):
        # The copied release script may read this fixture repository, but any
        # attempted network, add/commit/push, or tag mutation fails and is logged.
        directory = self.directory / "guarded-bin"
        directory.mkdir(exist_ok=True)
        log = self.directory / "forbidden-git-calls.txt"
        wrapper = directory / "git"
        wrapper.write_text("#!" + sys.executable + "\n" +
                           "import os, sys\n" +
                           "args = sys.argv[1:]\n" +
                           "pos = 2 if args[:1] == ['-C'] else 0\n" +
                           "cmd = args[pos] if len(args) > pos else ''\n" +
                           "allowed = cmd in {'rev-parse','show','cat-file','log','merge-base','diff','status','ls-files'}\n" +
                           "allowed = allowed or (cmd == 'tag' and any(x in args[pos+1:] for x in ['--list','--merged']))\n" +
                           "if not allowed:\n" +
                           "    with open(" + repr(str(log)) + ", 'a') as f: f.write(repr(args)+'\\n')\n" +
                           "    sys.exit(90)\n" +
                           "os.execv(" + repr(REAL_GIT) + ", [" + repr(REAL_GIT) + "] + args)\n", encoding="utf-8")
        wrapper.chmod(0o755)
        env = dict(self.env)
        env["PATH"] = str(directory) + os.pathsep + env.get("PATH", "")
        return env, log

    def assert_bump_guard(self, arguments, success, contains):
        paths = ("QuestTogether.toc", "release_notes.json", "ReleaseNotes.lua")
        before = {name: (self.root / name).read_bytes() if (self.root / name).exists() else None for name in paths}
        head, tags = self.git("rev-parse", "HEAD"), self.git("tag", "--list")
        env, log = self.guarded_git_env()
        result = self.run_process(["bash", "scripts/bump_version.sh", *arguments], env=env)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        self.assertIn(contains, result.stdout + result.stderr)
        self.assertFalse(log.exists(), "bump preflight attempted a mutation or remote access")
        self.assertEqual(before, {name: (self.root / name).read_bytes() if (self.root / name).exists() else None for name in paths})
        self.assertEqual(self.git("rev-parse", "HEAD"), head)
        self.assertEqual(self.git("tag", "--list"), tags)

    def test_exact_generation_and_stale_detection(self):
        self.check("--check")
        path = self.root / "ReleaseNotes.lua"
        path.write_text(path.read_text() + "-- accidental edit\n")
        self.assertIn("missing or stale", self.check(success=False))
        self.check("--write")
        self.check()
        expected = path.read_bytes()
        self.check("--write")
        self.assertEqual(path.read_bytes(), expected)
        path.unlink()
        self.assertIn("missing or stale", self.check(success=False))

    def test_meaningful_schema_rejects_bad_data(self):
        mutations = [
            lambda n: n.update(welcome=" "), lambda n: n.update(welcome="TODO"),
            lambda n: n.update(welcome="x\x00y"), lambda n: n.update(welcome="bad\ud800text"),
            lambda n: n.update(sections=[]), lambda n: n.update(sections={}),
            lambda n: n.update(extra=True), lambda n: n.update(version=True),
            lambda n: n.update(version="01.2.3"), lambda n: n["sections"][0].update(items=[]),
            lambda n: n["sections"][0].update(items=[{}]), lambda n: n["sections"][0].update(title="line\nbreak"),
            lambda n: n["sections"].append(copy.deepcopy(n["sections"][0])),
        ]
        for mutate in mutations:
            with self.subTest(mutation=mutate):
                notes = sample_notes()
                mutate(notes)
                with self.assertRaises(CHECKER.NotesError):
                    CHECKER.parse_notes(json.dumps(notes))
        with self.assertRaises(CHECKER.NotesError):
            CHECKER.parse_notes('{"version":"1.2.3","version":"1.2.4"}')

    def test_toc_version_must_be_unique_and_match(self):
        self.set_toc_version("1.2.4")
        self.assertIn("does not match TOC", self.check(success=False))
        with (self.root / "QuestTogether.toc").open("a") as handle:
            handle.write("## Version: 1.2.3\n")
        self.assertIn("exactly one", self.check(success=False))

    def test_current_manifest_must_load_data_once_after_core(self):
        for entries in ("Core.lua\nWelcome.lua\n", "ReleaseNotes.lua\nCore.lua\n",
                        "Core.lua\nReleaseNotes.lua\nReleaseNotes.lua\n", "ReleaseNotes.lua\n"):
            with self.subTest(entries=entries):
                (self.root / "QuestTogether.toc").write_text("## Version: 1.2.3\n" + entries, encoding="utf-8")
                self.assertIn("must load", self.check(success=False))
        self.set_toc_version("1.2.3")
        self.check()

    def test_generator_escapes_utf8_and_code_as_literal_data(self):
        interpreters = sorted({path for name in ("lua5.1", "lua5.2", "lua") if (path := shutil.which(name))})
        if not interpreters:
            self.skipTest("Lua interpreter unavailable; CI installs Lua 5.1/5.2")
        text = 'Quest "Étoile" \\ path\n第二行\t"}; _G.injected = true; -- 123'
        notes = sample_notes(item=text)
        self.write_notes(notes, generate=False)
        self.check("--write")
        byte_string = '"' + "".join("\\%03d" % byte for byte in text.encode("utf-8")) + '"'
        script = "QuestTogether = {}\n" + (self.root / "ReleaseNotes.lua").read_text(encoding="utf-8")
        script += "assert(QuestTogether.releaseNotes.sections[1].items[1] == " + byte_string + ")\nassert(injected == nil)\n"
        for interpreter in interpreters:
            result = subprocess.run([interpreter, "-"], input=script, text=True, encoding="utf-8",
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=self.env, cwd=self.root)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_baseline_rejects_version_formatting_or_capitalization_only_changes(self):
        for mutate in (lambda n: None, lambda n: n.update(welcome=n["welcome"].upper()),
                       lambda n: n.update(welcome=n["welcome"].replace(" ", "  "))):
            with self.subTest(mutation=mutate):
                notes = sample_notes("1.2.4")
                mutate(notes)
                self.set_toc_version("1.2.4")
                self.write_notes(notes)
                self.assertIn("unchanged", self.check("--baseline-ref", "v1.2.3", success=False))
        old, new = sample_notes(), sample_notes("1.2.4")
        old["welcome"] += " Version 1.2.3."
        new["welcome"] += " Version 1.2.4."
        self.assertEqual(CHECKER.content_key(old), CHECKER.content_key(new))

    def test_updated_content_counts_even_if_authored_in_an_earlier_commit(self):
        self.write_notes(sample_notes(item="Keep party requests visible until they finish."))
        self.git("add", ".")
        self.git("commit", "-qm", "Author notes before bump")
        self.assertIn("differs from v1.2.3", self.check("--baseline-ref", "v1.2.3"))
        self.set_toc_version("1.2.4")
        self.check("--write", "--set-version", "1.2.4", "--baseline-ref", "v1.2.3")
        self.check("--check", "--release-history")
        self.assertEqual(json.loads((self.root / "release_notes.json").read_text())["version"], "1.2.4")

    def test_set_version_requires_write_and_does_not_overwrite_on_failure(self):
        before = (self.root / "release_notes.json").read_bytes()
        self.assertIn("requires --write", self.check("--set-version", "1.2.4", success=False))
        self.set_toc_version("1.2.4")
        self.assertIn("unchanged", self.check("--write", "--set-version", "1.2.4", "--baseline-ref", "v1.2.3", success=False))
        self.assertEqual((self.root / "release_notes.json").read_bytes(), before)

    def test_legacy_baseline_allows_first_adoption(self):
        self.root = self.new_repo("legacy", legacy=True)
        self.write_notes(sample_notes("1.2.4"))
        self.set_toc_version("1.2.4")
        self.assertIn("first adoption", self.check("--release-history"))

    def test_missing_previously_tracked_baseline_notes_fail_closed(self):
        self.set_toc_version("1.2.4")
        (self.root / "release_notes.json").unlink()
        self.git("add", "-A")
        self.git("commit", "-qm", "Fixture deleted notes")
        self.git("tag", "v1.2.4")
        self.set_toc_version("1.2.5")
        self.write_notes(sample_notes("1.2.5", "Recover party comparisons after combat."))
        self.assertIn("previously tracked", self.check("--release-history", success=False))

    def test_corrupt_or_version_mismatched_baseline_fails_closed(self):
        (self.root / "release_notes.json").write_text("{}", encoding="utf-8")
        self.set_toc_version("1.2.4")
        self.git("add", ".")
        self.git("commit", "-qm", "Fixture corrupt notes")
        self.git("tag", "v1.2.4")
        self.set_toc_version("1.2.5")
        self.write_notes(sample_notes("1.2.5"))
        self.assertIn("must contain exactly", self.check("--release-history", success=False))

    def test_baseline_notes_must_match_its_own_version(self):
        self.set_toc_version("1.2.4")
        self.git("add", ".")
        self.git("commit", "-qm", "Fixture version-only broken release")
        self.git("tag", "v1.2.4")
        self.set_toc_version("1.2.5")
        self.write_notes(sample_notes("1.2.5", "Updated notes for journal navigation."))
        self.assertIn("baseline notes do not match", self.check("--release-history", success=False))

    def test_history_uses_prior_prerelease_and_excludes_current_tag(self):
        self.commit_release("1.3.0-alpha.9", "New comparison controls appear in the minimap menu.")
        self.commit_release("1.3.0-beta.1", "Share requests explain their current cooldown.")
        self.commit_release("1.3.0", "Quest menus offer direct journal navigation.")
        self.assertIn("differs from v1.3.0-beta.1", self.check("--release-history"))

    def test_missing_or_nonancestor_baselines_fail_closed(self):
        self.assertIn("git rev-parse", self.check("--baseline-ref", "v9.9.9", success=False))
        self.assertIn("no reachable earlier", self.check("--release-history", success=False))
        initial = self.git("rev-parse", "HEAD")
        self.commit_release("1.2.4", "A separate future release for baseline checks.")
        self.git("checkout", "--detach", initial)
        self.assertIn("ancestor", self.check("--baseline-ref", "v1.2.4", success=False))

    def test_shallow_checkout_requires_full_history(self):
        shallow = self.directory / "shallow"
        self.git("clone", "--quiet", "--depth", "1", self.root.as_uri(), str(shallow))
        self.root = shallow
        self.assertIn("full checkout", self.check("--baseline-ref", "v1.2.3", success=False))

    def test_bump_refuses_unchanged_notes_before_any_mutation_or_network(self):
        self.assert_bump_guard(["patch"], success=False, contains="unchanged")

    def test_bump_refuses_stale_generated_notes_before_any_mutation_or_network(self):
        self.write_notes(sample_notes(item="New party comparison options."), generate=False)
        self.assert_bump_guard(["patch"], success=False, contains="missing or stale")

    def test_bump_refuses_missing_notes_before_any_mutation_or_network(self):
        (self.root / "release_notes.json").unlink()
        self.assert_bump_guard(["patch"], success=False, contains="release_notes.json")

    def test_bump_check_validates_stable_and_prerelease_without_side_effects(self):
        self.write_notes(sample_notes(item="Journal shortcuts and clearer party sharing feedback."))
        self.assert_bump_guard(["patch", "--check"], success=True, contains="New version: 1.2.4")
        self.assert_bump_guard(["minor", "beta", "--check"], success=True, contains="New version: 1.3.0-beta.1")

    def test_bump_requires_the_explicit_current_release_tag(self):
        self.write_notes(sample_notes(item="Current patch notes include journal fixes."))
        self.git("tag", "-d", "v1.2.3")
        self.assert_bump_guard(["patch", "--check"], success=False, contains="baseline v1.2.3 is missing")

    def local_release_remote(self, name):
        remote = self.directory / (name + " remote.git")
        self.git("init", "--bare", "-q", str(remote))
        self.git("remote", "add", "origin", str(remote))
        branch = self.git("symbolic-ref", "--short", "HEAD")
        self.git("push", "-q", "origin", branch, "--tags")
        return remote, branch

    def release_state(self, remote):
        # Compare the real index and all worktree bytes, not only the three
        # release files: rejection must preserve unrelated staging and edits.
        return {
            "files": {str(path.relative_to(self.root)): path.read_bytes()
                      for path in self.root.rglob("*")
                      if path.is_file() and ".git" not in path.relative_to(self.root).parts},
            "index": (self.root / ".git/index").read_bytes(),
            "head": self.git("rev-parse", "HEAD"),
            "refs": self.git("show-ref"),
            "remote_refs": self.git("show-ref", root=remote),
        }

    def test_full_release_publishes_committed_code_and_only_allowed_authored_files(self):
        for notes_committed in (False, True):
            with self.subTest(notes_committed=notes_committed):
                self.root = self.new_repo("publication " + str(notes_committed))
                remote, branch = self.local_release_remote("publication " + str(notes_committed))
                implementation = "-- Fixed implementation included in the release\n"
                (self.root / "Core.lua").write_text(implementation, encoding="utf-8")
                self.git("add", "Core.lua")
                self.git("commit", "-qm", "Fix implementation before release")
                self.write_notes(sample_notes(item="The committed implementation includes the quest fix."))
                # An intended TOC edit and a mix of staged/unstaged notes are
                # supported; the release must commit their current contents.
                with (self.root / "QuestTogether.toc").open("a") as handle:
                    handle.write("## Notes: Reviewed release metadata\n")
                self.git("add", "release_notes.json")
                if notes_committed:
                    self.git("add", "QuestTogether.toc", "ReleaseNotes.lua")
                    self.git("commit", "-qm", "Review release files before bump")
                before_head = self.git("rev-parse", "HEAD")
                result = self.run_process(["bash", "scripts/bump_version.sh", "patch"])
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                head = self.git("rev-parse", "HEAD")
                self.assertNotEqual(head, before_head)
                self.assertEqual(self.git("rev-parse", "HEAD^"), before_head)
                self.assertEqual(self.git("rev-parse", "refs/heads/" + branch, root=remote), head)
                self.assertEqual(self.git("rev-parse", "v1.2.4^{commit}", root=remote), head)
                self.assertEqual(self.git("cat-file", "-t", "v1.2.4", root=remote), "tag")
                self.assertEqual(self.git("show", "v1.2.4:Core.lua", root=remote), implementation.strip())
                published_notes = CHECKER.parse_notes(self.git("show", "v1.2.4:release_notes.json", root=remote))
                self.assertEqual(published_notes["version"], "1.2.4")
                self.assertEqual(self.git("show", "v1.2.4:ReleaseNotes.lua", root=remote),
                                 CHECKER.render_lua(published_notes).strip())
                published_toc = self.git("show", "v1.2.4:QuestTogether.toc", root=remote)
                self.assertEqual(CHECKER.toc_version(published_toc), "1.2.4")
                self.assertIn("## Notes: Reviewed release metadata", published_toc)
                changed = set(self.git("diff", "--name-only", "HEAD^", "HEAD").splitlines())
                self.assertEqual(changed, {"QuestTogether.toc", "release_notes.json", "ReleaseNotes.lua"})
                self.assertEqual(self.git("status", "--porcelain"), "")

    def test_dirty_source_release_fails_before_network_or_mutation_and_preserves_staging(self):
        for mode in ("staged", "unstaged", "staged_and_unstaged", "untracked", "renamed_to_release_file"):
            with self.subTest(mode=mode):
                self.root = self.new_repo("dirty " + mode)
                remote, _ = self.local_release_remote("dirty " + mode)
                if mode == "renamed_to_release_file":
                    # A rename into an allowed filename still removes a source
                    # file. The old path must not disappear from validation.
                    self.git("rm", "ReleaseNotes.lua")
                    self.git("mv", "Core.lua", "ReleaseNotes.lua")
                self.write_notes(sample_notes(item="The next release includes the quest fix."))
                self.git("add", "release_notes.json")
                if mode == "untracked":
                    # NUL-separated inspection must handle spaces/newlines.
                    (self.root / "new quest\nmodule.lua").write_text("-- Uncommitted new module\n", encoding="utf-8")
                elif mode != "renamed_to_release_file":
                    (self.root / "Core.lua").write_text("-- Uncommitted quest fix\n", encoding="utf-8")
                    if mode in ("staged", "staged_and_unstaged"):
                        self.git("add", "Core.lua")
                    if mode == "staged_and_unstaged":
                        with (self.root / "Core.lua").open("a") as handle:
                            handle.write("-- Additional unstaged edit must also survive\n")
                before = self.release_state(remote)
                env, forbidden = self.guarded_git_env()
                for arguments in (["patch", "--check"], ["patch"]):
                    result = self.run_process(["bash", "scripts/bump_version.sh", *arguments], env=env)
                    self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIn("non-release changes", result.stdout + result.stderr)
                    self.assertFalse(forbidden.exists(), "dirty release attempted remote access or Git mutation")
                    self.assertEqual(self.release_state(remote), before)


if __name__ == "__main__":
    unittest.main()
