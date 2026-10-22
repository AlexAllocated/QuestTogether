"""Build the in-game history from archived, localized, published notes."""
from datetime import date, datetime, timezone
import io
import json
from pathlib import Path
import subprocess
from check_release_notes import NotesError, git, parse_notes, require_full_history, toc_version, version_key
from changelogs import validate_entry
from localization import LOCALES, dumps, lua, read

LUA_FILE = 'ReleaseNotesHistory.lua'
DATES_FILE = 'changelogs/release_dates.json'
LEGACY_FILE = 'changelogs/legacy_notes.json'


def require_complete_history(root, current_version, archived_versions):
    """Reject lost published entries, including releases skipped by a manual bump."""
    # Rendering exported sources remains possible without Git. Release preflight
    # and --release-history already require a checkout; validate every available
    # checkout here so ordinary generation cannot conceal a missing release.
    if git(root, 'rev-parse', '--is-inside-work-tree', allow_failure=True).returncode:
        return
    require_full_history(root)
    if git(root, 'rev-parse', '--verify', 'HEAD', allow_failure=True).returncode:
        return  # An initial repository has no published releases yet.
    current_key = version_key(current_version)
    candidates = []
    for tag in git(root, 'tag', '--merged', 'HEAD', '--list', 'v*').stdout.splitlines():
        version = tag[1:]
        try:
            key = version_key(version)
        except NotesError:
            continue
        if key < current_key and version not in archived_versions:
            candidates.append(version)
    if not candidates:
        return
    # One Git process handles all candidates, rather than two processes for each
    # historical tag. Old releases without structured notes need no backfill.
    queries = [f'refs/tags/v{version}:{path}' for version in candidates
               for path in ('QuestTogether.toc', 'release_notes.json')]
    result = subprocess.run(['git', '-C', str(root), 'cat-file', '--batch'],
                            input=('\n'.join(queries) + '\n').encode('utf-8'),
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise NotesError('could not inspect published release history: ' +
                         result.stderr.decode('utf-8', errors='replace').strip())
    stream = io.BytesIO(result.stdout)
    objects = []
    for query in queries:
        header = stream.readline().rstrip(b'\n')
        if header == (query + ' missing').encode('utf-8'):
            objects.append(None)
            continue
        fields = header.split()
        if len(fields) != 3 or fields[1] != b'blob' or not fields[2].isdigit():
            raise NotesError('invalid published release object: ' + query)
        data = stream.read(int(fields[2]))
        if stream.read(1) != b'\n':
            raise NotesError('incomplete published release object: ' + query)
        objects.append(data)
    missing = []
    for version, toc, raw_notes in zip(candidates, objects[::2], objects[1::2]):
        if toc is None or raw_notes is None:
            continue
        try:
            tagged_version = toc_version(toc.decode('utf-8'))
            notes = parse_notes(raw_notes.decode('utf-8'))
        except (UnicodeError, ValueError):
            continue  # Only valid, matching structured release tags qualify.
        if tagged_version == version == notes['version']:
            missing.append(version)
    if missing:
        missing.sort(key=version_key)
        raise NotesError('published releases missing from changelog history: ' + ', '.join(missing) +
                         '; restore their notes from the release tags before generating or releasing')


def outputs(root, current, generated, previous_version=None):
    root = Path(root)
    dates = read(root / DATES_FILE)
    if not isinstance(dates, dict):
        raise NotesError('release dates must be a version/date mapping')
    for version, value in dates.items():
        version_key(version)
        if not isinstance(value, str) or date.fromisoformat(value).isoformat() != value:
            raise NotesError('invalid release date: ' + version)
    # Record once during a version bump. Checks never infer dates from the clock.
    if previous_version and previous_version != current['version']:
        dates.setdefault(current['version'], datetime.now(timezone.utc).date().isoformat())
    history = json.loads(generated[root / 'changelogs/history.json'])['releases']
    legacy = read(root / LEGACY_FILE)
    if not isinstance(legacy, list):
        raise NotesError('legacy notes must be a list')
    entries = {}
    for entry in history + legacy:
        version = validate_entry(entry)
        if set(entry) != {'enUS', *LOCALES}:
            raise NotesError('release history requires all locales: ' + version)
        if version in entries:
            raise NotesError('duplicate release history: ' + version)
        if version_key(version) >= version_key(current['version']):
            raise NotesError('history must be older than current release: ' + version)
        entries[version] = entry
    require_complete_history(root, current['version'], entries)
    for version in [current['version'], *entries]:
        if version not in dates:
            raise NotesError('missing release date: ' + version)
    archived = [{'version': v, 'date': dates[v], 'locales': entries[v]}
                for v in sorted(entries, key=version_key, reverse=True) if entries[v]['enUS']['sections']]
    content = ('-- Generated from canonical changelog history; do not edit.\n'
               'local _, namespace = ...\n'
               'namespace.releaseNotesHistory = ' + lua(archived) + '\n'
               'namespace.releaseNotesDates = ' + lua(dates) + '\n')
    return {root / LUA_FILE: content, root / DATES_FILE: dumps(dates)}
