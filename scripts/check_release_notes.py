#!/usr/bin/env python3
"""Validate canonical notes and generate their Lua data without evaluating code."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


VERSION = re.compile(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-(alpha|beta)\.(0|[1-9][0-9]*))?\Z")
VERSION_MENTION = re.compile(r"(?<![\w.])v?[0-9]+\.[0-9]+\.[0-9]+(?:-(?:alpha|beta)\.[0-9]+)?(?!\w|\.[0-9])", re.IGNORECASE)
NOTES_FILE = "release_notes.json"
REUSE_FILE = "release_notes_reuse.json"
LUA_FILE = "ReleaseNotes.lua"
LOCALIZED_LUA_FILE = "LocalizedReleaseNotes.lua"
TOC_FILE = "QuestTogether.toc"
# Releases before this asset existed retain their original rendering and URLs.
TIP_ICON_FIRST_VERSION = "7.1.1"
TIP_ICON_PATH = "Media/QuestTogetherTipIcon.png"
sys.dont_write_bytecode = True


class NotesError(ValueError):
    pass


def version_key(value):
    match = VERSION.fullmatch(value) if isinstance(value, str) else None
    if not match:
        raise NotesError("version must be X.Y.Z, X.Y.Z-alpha.N, or X.Y.Z-beta.N")
    major, minor, patch, channel, sequence = match.groups()
    return (int(major), int(minor), int(patch), {"alpha": 0, "beta": 1, None: 2}[channel], int(sequence or 0))


def toc_version(text):
    versions = re.findall(r"^## Version:[ \t]*(.*?)[ \t]*$", text, re.MULTILINE)
    if len(versions) != 1:
        raise NotesError("QuestTogether.toc must contain exactly one ## Version field")
    version_key(versions[0])
    return versions[0]


def check_manifest(text):
    entries = [line.strip().replace("\\", "/") for line in text.splitlines()
               if line.strip() and not line.lstrip().startswith("#")]
    if entries.count(LUA_FILE) != 1 or entries.count("Core.lua") != 1:
        raise NotesError("QuestTogether.toc must load Core.lua and ReleaseNotes.lua exactly once")
    if entries.index(LUA_FILE) < entries.index("Core.lua"):
        raise NotesError("QuestTogether.toc must load ReleaseNotes.lua after Core.lua")
    if LOCALIZED_LUA_FILE in entries:
        if entries.count(LOCALIZED_LUA_FILE) != 1 or entries.index(LOCALIZED_LUA_FILE) < entries.index(LUA_FILE):
            raise NotesError("QuestTogether.toc must load LocalizedReleaseNotes.lua exactly once after ReleaseNotes.lua")
    if "ReleaseNotesHistory.lua" in entries:
        if (entries.count("ReleaseNotesHistory.lua") != 1 or LOCALIZED_LUA_FILE not in entries
                or entries.index("ReleaseNotesHistory.lua") < entries.index(LOCALIZED_LUA_FILE)
                or ("Welcome.lua" in entries and entries.index("ReleaseNotesHistory.lua") > entries.index("Welcome.lua"))):
            raise NotesError("QuestTogether.toc must load ReleaseNotesHistory.lua once after localized notes and before Welcome.lua")
    return LOCALIZED_LUA_FILE in entries


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise NotesError("duplicate JSON key: " + key)
        result[key] = value
    return result


def meaningful_text(value, label, limit, single_line=False, minimum=3):
    if not isinstance(value, str) or len(value.strip()) < minimum:
        raise NotesError(label + " must contain meaningful text")
    if value != value.strip() or len(value) > limit:
        raise NotesError(label + " must be trimmed and at most " + str(limit) + " characters")
    try:
        value.encode("utf-8")
    except UnicodeError as error:
        raise NotesError(label + " must contain valid Unicode") from error
    if any((ord(char) < 32 and char not in "\n\t") or ord(char) == 127 for char in value):
        raise NotesError(label + " contains unsupported control characters")
    if single_line and ("\n" in value or "\t" in value):
        raise NotesError(label + " must be a single line")
    if value.casefold().rstrip(".!:") in {"todo", "tbd", "placeholder", "coming soon", "release notes", "none", "n/a"}:
        raise NotesError(label + " must not be a placeholder")
    return value


def parse_tip(value, label):
    if not isinstance(value, dict) or set(value) != {"label", "text"}:
        raise NotesError(label + " must contain exactly label and text")
    meaningful_text(value["label"], label + ".label", 40, single_line=True, minimum=1)
    meaningful_text(value["text"], label + ".text", 800, minimum=1)
    # Tips are content, not preformatted chat/Markdown. Renderers add the bulb
    # and blockquote; WoW markup would leak into web and Discord output.
    for key, text in value.items():
        if re.search(r"\|(?:c[0-9a-fA-F]{8}|r\b|[HTA][^|]*\|[hta])|`|\*\*|__|~~|!?\[[^\]]*\]\([^)]*\)", text):
            raise NotesError(label + "." + key + " must contain plain text")
    return value


def format_tip(tip):
    """One plain sample line shared by every external release-note renderer."""
    return "💡 " + tip["label"] + " " + tip["text"]


def tip_icon_path(version):
    return TIP_ICON_PATH if version and version_key(version) >= version_key(TIP_ICON_FIRST_VERSION) else None


def markdown_tip(tip, version=None):
    icon = tip_icon_path(version)
    if icon:
        url = "https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v" + version + "/" + icon
        text = '<img src="' + url + '" width="20" height="20" alt=""> ' + tip["label"] + " " + tip["text"]
    else:
        text = format_tip(tip)
    return "\n".join("> " + line for line in text.split("\n"))


def parse_notes(text, label=NOTES_FILE):
    try:
        notes = json.loads(text, object_pairs_hook=unique_object)
    except (ValueError, TypeError) as error:
        raise NotesError(label + ": " + str(error)) from error
    if not isinstance(notes, dict) or set(notes) != {"version", "welcome", "sections"}:
        raise NotesError(label + " must contain exactly version, welcome, and sections")
    version_key(notes["version"])
    # Explicitly empty content is a silent release, not placeholder prose.
    if notes["welcome"] == "" and notes["sections"] == []:
        return notes
    meaningful_text(notes["welcome"], label + ".welcome", 1200)
    sections = notes["sections"]
    if not isinstance(sections, list) or not 1 <= len(sections) <= 12:
        raise NotesError(label + ".sections must contain 1 to 12 sections")
    titles = set()
    for index, section in enumerate(sections, 1):
        prefix = label + ".sections[" + str(index) + "]"
        if not isinstance(section, dict) or not {"title", "items"} <= set(section) or set(section) - {"title", "items", "illustration", "tip"}:
            raise NotesError(prefix + " must contain title and items, with optional illustration and tip")
        if "illustration" in section and section["illustration"] not in ("quest-partners", "party-quest-log", "party-quest-objectives", "party-quest-overview", "party-quest-following", "party-quest-focus-warning"):
            raise NotesError(prefix + ".illustration is unsupported")
        title = meaningful_text(section["title"], prefix + ".title", 80, single_line=True)
        if title.casefold() in titles:
            raise NotesError(prefix + ".title duplicates another section")
        titles.add(title.casefold())
        items = section["items"]
        if not isinstance(items, list) or not 1 <= len(items) <= 16:
            raise NotesError(prefix + ".items must contain 1 to 16 items")
        for item_index, item in enumerate(items, 1):
            meaningful_text(item, prefix + ".items[" + str(item_index) + "]", 800)
        if "tip" in section:
            parse_tip(section["tip"], prefix + ".tip")
    return notes


def lua_string(value):
    replacements = {"\\": "\\\\", '"': '\\"', "\n": "\\n", "\r": "\\r", "\t": "\\t"}
    return '"' + "".join(replacements.get(char, "\\%03d" % ord(char) if ord(char) < 32 or ord(char) == 127 else char)
                           for char in value) + '"'


def render_lua(notes):
    lines = [
        "-- Generated from release_notes.json by scripts/check_release_notes.py --write.",
        "-- Edit the JSON source, then regenerate this file.",
        "local QuestTogether = _G.QuestTogether",
        "",
        "QuestTogether.releaseNotes = {",
        "\tversion = " + lua_string(notes["version"]) + ",",
        "\twelcome = " + lua_string(notes["welcome"]) + ",",
        "\tsections = {",
    ]
    for section in notes["sections"]:
        lines += ["\t\t{", "\t\t\ttitle = " + lua_string(section["title"]) + ",", "\t\t\titems = {"]
        lines += ["\t\t\t\t" + lua_string(item) + "," for item in section["items"]]
        lines += ["\t\t\t},"]
        if "illustration" in section:
            lines += ["\t\t\tillustration = " + lua_string(section["illustration"]) + ","]
        if "tip" in section:
            lines += ["\t\t\ttip = {", "\t\t\t\tlabel = " + lua_string(section["tip"]["label"]) + ",",
                      "\t\t\t\ttext = " + lua_string(section["tip"]["text"]) + ",", "\t\t\t},"]
        lines += ["\t\t},"]
    lines += ["\t},", "}", ""]
    return "\n".join(lines)


def content_key(notes):
    # Reformatting JSON/whitespace or changing the version label is not fresh notes.
    def normalize(value):
        if isinstance(value, str):
            return " ".join(VERSION_MENTION.sub("<version>", value).split()).casefold()
        if isinstance(value, list):
            return [normalize(item) for item in value]
        return {key: normalize(item) for key, item in value.items()}
    return normalize({"welcome": notes["welcome"], "sections": notes["sections"]})


def git(root, *arguments, allow_failure=False):
    result = subprocess.run(["git", "-C", str(root), *arguments], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, encoding="utf-8")
    if result.returncode and not allow_failure:
        raise NotesError("git " + " ".join(arguments) + ": " + result.stderr.strip())
    return result


def require_full_history(root):
    if git(root, "rev-parse", "--is-shallow-repository").stdout.strip() != "false":
        raise NotesError("release-note history checks require a full checkout; fetch full history and tags")


def previous_release(root, current_version):
    require_full_history(root)
    tags = git(root, "tag", "--merged", "HEAD", "--list", "v*").stdout.splitlines()
    candidates = []
    for tag in tags:
        try:
            key = version_key(tag[1:])
        except NotesError:
            continue
        if key < version_key(current_version):
            candidates.append((key, tag))
    if not candidates:
        raise NotesError("no reachable earlier release tag; fetch release tags or provide --baseline-ref explicitly")
    return max(candidates)[1]


def note_content(notes):
    # Reuse means identical authored content, not merely equivalent wording.
    return {"welcome": notes["welcome"], "sections": notes["sections"]}


def read_note_reuse(root):
    path = Path(root) / REUSE_FILE
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_object)
    except (ValueError, TypeError) as error:
        raise NotesError(REUSE_FILE + ": " + str(error)) from error
    if (not isinstance(data, dict) or set(data) != {"schema", "releases"}
            or type(data["schema"]) is not int or data["schema"] != 1
            or not isinstance(data["releases"], dict)):
        raise NotesError(REUSE_FILE + " must contain schema 1 and a releases mapping")
    for target, baseline in data["releases"].items():
        if version_key(target) <= version_key(baseline):
            raise NotesError(REUSE_FILE + " target must be newer than its baseline")
    return data["releases"]


def check_reused_translations(root, commit):
    # A repeated release keeps every enabled translation, not only English.
    manifest = (Path(root) / TOC_FILE).read_text(encoding="utf-8")
    if not check_manifest(manifest):
        return
    from localization import LOCALES
    for locale in LOCALES:
        relative = "release_notes/" + locale + ".json"
        published = json.loads(git(root, "show", commit + ":" + relative).stdout, object_pairs_hook=unique_object)
        current = json.loads((Path(root) / relative).read_text(encoding="utf-8"), object_pairs_hook=unique_object)
        for wrapper in (published, current):
            if not isinstance(wrapper, dict) or set(wrapper) != {"source_sha256", "notes"}:
                raise NotesError("invalid reused translation: " + locale)
            parse_notes(json.dumps(wrapper["notes"], ensure_ascii=False), relative)
        if (current["source_sha256"] != published["source_sha256"]
                or note_content(current["notes"]) != note_content(published["notes"])):
            raise NotesError("reused translation differs from published notes: " + locale)


def check_baseline(root, notes, reference, reuse_for=None):
    acknowledged = read_note_reuse(root)
    require_full_history(root)
    commit = git(root, "rev-parse", "--verify", "--end-of-options", reference + "^{commit}").stdout.strip()
    if git(root, "merge-base", "--is-ancestor", commit, "HEAD", allow_failure=True).returncode:
        raise NotesError("release-note baseline must be an ancestor of HEAD: " + reference)
    baseline_version = toc_version(git(root, "show", commit + ":" + TOC_FILE).stdout)
    if version_key(baseline_version) > version_key(notes["version"]):
        raise NotesError("release-note baseline is newer than the current version")
    present = git(root, "cat-file", "-e", commit + ":" + NOTES_FILE, allow_failure=True)
    if present.returncode:
        if reuse_for:
            raise NotesError("cannot reuse a baseline without published release notes")
        history = git(root, "log", "-1", "--format=%H", commit, "--", NOTES_FILE).stdout.strip()
        if history:
            raise NotesError("baseline previously tracked release notes but is missing them: " + reference)
        return "legacy baseline " + reference + " predates release notes (first adoption)"
    baseline = parse_notes(git(root, "show", commit + ":" + NOTES_FILE).stdout, reference + ":" + NOTES_FILE)
    if baseline["version"] != baseline_version:
        raise NotesError("baseline notes do not match its TOC version: " + reference)
    # An explicit request is a planned release; saved acknowledgements apply
    # only to their exact released version. Fresh drafts do not need a waiver.
    unchanged = content_key(notes) == content_key(baseline)
    target = reuse_for or (notes["version"] if unchanged and notes["version"] in acknowledged else None)
    if target:
        if version_key(target) <= version_key(baseline_version) or notes["version"] not in (baseline_version, target):
            raise NotesError("note reuse target must be newer than the selected baseline")
        recorded_baseline = acknowledged.get(target)
        if recorded_baseline is not None and recorded_baseline != baseline_version:
            raise NotesError("note reuse acknowledgement does not match the selected baseline")
        if not reuse_for and recorded_baseline != baseline_version:
            raise NotesError("note reuse requires an explicit acknowledgement")
        tag = "refs/tags/v" + baseline_version
        tagged_commit = git(root, "rev-parse", "--verify", "--end-of-options", tag + "^{commit}").stdout.strip()
        if commit != tagged_commit:
            raise NotesError("note reuse baseline must be the published version tag: " + tag)
        if note_content(notes) != note_content(baseline):
            raise NotesError("note reuse requires exactly unchanged published content")
        check_reused_translations(root, commit)
        return "release notes explicitly reused from " + tag + " for " + target
    if notes["welcome"] == "" and notes["sections"] == []:
        return "silent release; no new release notes"
    if unchanged:
        raise NotesError("release notes are unchanged from " + reference + "; update their content for every release")
    return "release-note content differs from " + reference


def atomic_write(path, text):
    data = text.encode("utf-8")
    if path.exists() and path.read_bytes() == data:
        return
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as handle:
            temporary = Path(handle.name)
            handle.write(data)
        temporary.chmod(0o644)
        os.replace(temporary, path)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="validate exact generated output (default)")
    mode.add_argument("--write", action="store_true", help="regenerate English and enabled localized release-note data")
    parser.add_argument("--set-version", help="with --write, update canonical version after the TOC bump")
    parser.add_argument("--reuse-notes-for", metavar="VERSION", help="explicitly reuse identical published notes for this one target version")
    baseline = parser.add_mutually_exclusive_group()
    baseline.add_argument("--baseline-ref", help="require content changes from this explicit Git release baseline")
    baseline.add_argument("--release-history", action="store_true", help="compare the previous reachable release tag; requires full history")
    args = parser.parse_args(argv)
    try:
        if args.set_version and not args.write:
            raise NotesError("--set-version requires --write")
        if args.reuse_notes_for:
            version_key(args.reuse_notes_for)
            if not args.baseline_ref or (args.write and args.set_version != args.reuse_notes_for):
                raise NotesError("--reuse-notes-for requires --baseline-ref and, when writing, the same --set-version")
        root = args.root.resolve()
        acknowledged = read_note_reuse(root)
        notes = parse_notes((root / NOTES_FILE).read_text(encoding="utf-8"))
        previous_version = notes["version"]
        if args.set_version:
            version_key(args.set_version)
            notes["version"] = args.set_version
        manifest = (root / TOC_FILE).read_text(encoding="utf-8")
        version = toc_version(manifest)
        localized = check_manifest(manifest)
        if notes["version"] != version:
            raise NotesError("release_notes.json version " + notes["version"] + " does not match TOC version " + version)
        reference = previous_release(root, version) if args.release_history else args.baseline_ref
        baseline_result = check_baseline(root, notes, reference, reuse_for=args.reuse_notes_for) if reference else None
        outputs = {root / LUA_FILE: render_lua(notes)}
        if localized:
            # Validate all translations before changing any version or generated
            # file. Version-only bumps reuse reviewed text without an API call.
            from localization import release_note_outputs
            localized_outputs = release_note_outputs(
                root, notes, previous_version=previous_version if args.set_version else None)
            outputs.update(localized_outputs)
        if (root / "scripts/changelogs.py").is_file():
            from changelogs import outputs as changelog_outputs
            outputs.update(changelog_outputs(root, notes, outputs,
                           previous_version=previous_version if args.set_version else None))
        if any(line.strip() == "ReleaseNotesHistory.lua" for line in manifest.splitlines()):
            from release_history import outputs as history_outputs
            outputs.update(history_outputs(root, notes, outputs,
                           previous_version=previous_version if args.set_version else None))
        if args.set_version:
            outputs[root / NOTES_FILE] = json.dumps(notes, ensure_ascii=False, indent=2) + "\n"
        if args.reuse_notes_for and args.write:
            baseline_version = toc_version(git(root, "show", args.baseline_ref + ":" + TOC_FILE).stdout)
            acknowledged[args.reuse_notes_for] = baseline_version
            outputs[root / REUSE_FILE] = json.dumps({"schema": 1, "releases": acknowledged}, indent=2, sort_keys=True) + "\n"
        if args.write:
            for path, generated in outputs.items():
                atomic_write(path, generated)
        else:
            for path, generated in outputs.items():
                if not path.is_file() or path.read_bytes() != generated.encode("utf-8"):
                    raise NotesError(str(path.relative_to(root)) +
                                     " is missing or stale; run python3 scripts/check_release_notes.py --write")
        print("Release notes " + version + (" generated." if args.write else " verified."))
        if baseline_result:
            print(baseline_result)
        return 0
    except (OSError, UnicodeError, ValueError, ImportError) as error:
        print("Release notes error: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
