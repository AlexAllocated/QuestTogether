"""Build the in-game history from archived, localized, published notes."""
from datetime import date, datetime, timezone
import json
from pathlib import Path
from check_release_notes import NotesError, version_key
from changelogs import validate_entry
from localization import LOCALES, dumps, lua, read

LUA_FILE = 'ReleaseNotesHistory.lua'
DATES_FILE = 'changelogs/release_dates.json'
LEGACY_FILE = 'changelogs/legacy_notes.json'


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
