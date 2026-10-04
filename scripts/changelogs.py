#!/usr/bin/env python3
"""Generate repository changelogs from the same canonical notes as Discord."""
import argparse
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
from check_release_notes import NotesError, git, parse_notes, unique_object, version_key
from localization import LOCALES, digest, dumps, read, release_note_outputs

HISTORY = 'changelogs/history.json'
TITLES = {'enUS': 'Changelog', 'deDE': 'Änderungsprotokoll', 'frFR': 'Journal des modifications',
          'esES': 'Registro de cambios', 'esMX': 'Registro de cambios', 'ptBR': 'Registro de alterações',
          'ruRU': 'Журнал изменений', 'itIT': 'Registro delle modifiche', 'koKR': '변경 내역',
          'zhCN': '更新日志', 'zhTW': '更新日誌'}


def validate_entry(entry):
    if not isinstance(entry, dict) or 'enUS' not in entry or set(entry) - set(TITLES):
        raise NotesError('invalid changelog history languages')
    source = parse_notes(dumps(entry['enUS']))
    for locale, notes in entry.items():
        parse_notes(dumps(notes))
        if notes['version'] != source['version'] or len(notes['sections']) != len(source['sections']):
            raise NotesError('changelog history version/section mismatch: ' + locale)
        for a, b in zip(source['sections'], notes['sections']):
            if len(a['items']) != len(b['items']) or a.get('illustration') != b.get('illustration'):
                raise NotesError('changelog history item/illustration mismatch: ' + locale)
    return source['version']


def tagged_entry(root, version):
    """Read a published baseline before a version bump; never archive a draft."""
    version_key(version)
    ref = 'refs/tags/v' + version
    if git(root, 'merge-base', '--is-ancestor', ref, 'HEAD', allow_failure=True).returncode:
        raise NotesError('changelog baseline must be a reachable release tag: ' + ref)
    source = parse_notes(git(root, 'show', ref + ':release_notes.json').stdout)
    if source['version'] != version:
        raise NotesError('changelog tag version mismatch')
    entry = {'enUS': source}
    for locale in LOCALES:
        result = git(root, 'show', ref + ':release_notes/' + locale + '.json', allow_failure=True)
        if result.returncode:
            continue  # Before this locale was supported, no translation existed.
        wrapper = json.loads(result.stdout, object_pairs_hook=unique_object)
        if set(wrapper) != {'source_sha256', 'notes'} or wrapper['source_sha256'] != digest(source):
            raise NotesError('stale archived translation: ' + version + ' ' + locale)
        entry[locale] = wrapper['notes']
    validate_entry(entry)
    return entry


def render(locale, entries):
    lines = ['# QuestTogether — ' + TITLES[locale], '',
             '<!-- Generated from canonical release notes; do not edit by hand. -->', '']
    if locale == 'enUS':
        lines += ['[Other languages](changelogs/README.md)', '']
    for entry in entries:
        notes = entry.get(locale)
        if not notes:
            continue
        lines += ['## ' + notes['version'], '', notes['welcome'], '']
        for section in notes['sections']:
            lines += ['### ' + section['title'], '']
            lines += ['- ' + item for item in section['items']]
            lines += ['']
    if locale == 'enUS':
        lines += ['[Earlier handwritten changelog](changelogs/legacy-enUS.md)', '']
    return '\n'.join(lines)


def outputs(root, notes, localized_outputs=None, previous_version=None):
    root = Path(root)
    history = read(root / HISTORY)
    if not isinstance(history, dict) or set(history) != {'schema', 'releases'} or history['schema'] != 1 or not isinstance(history['releases'], list):
        raise NotesError('invalid changelog history schema')
    archived = {}
    for entry in history['releases']:
        version = validate_entry(entry)
        if version in archived:
            raise NotesError('duplicate changelog history version: ' + version)
        if version_key(version) > version_key(notes['version']):
            raise NotesError('changelog history is newer than current release')
        archived[version] = entry
    if previous_version and previous_version != notes['version']:
        published = tagged_entry(root, previous_version)
        if previous_version in archived and archived[previous_version] != published:
            raise NotesError('archived changelog differs from published tag')
        archived[previous_version] = published
    current = {'enUS': notes}
    # Caller supplies fully validated, version-adjusted translations during bump.
    if localized_outputs is None:
        localized_outputs = release_note_outputs(root, notes)
    for locale in LOCALES:
        path = root / 'release_notes' / (locale + '.json')
        if path in localized_outputs:
            current[locale] = json.loads(localized_outputs[path])['notes']
    validate_entry(current)
    entries = dict(archived)
    entries[notes['version']] = current
    ordered = [entries[v] for v in sorted(entries, key=version_key, reverse=True)]
    result = {root / ('CHANGELOG.md' if locale == 'enUS' else 'changelogs/' + locale + '.md'): render(locale, ordered)
              for locale in TITLES}
    result[root / HISTORY] = dumps({'schema': 1, 'releases': [archived[v] for v in sorted(archived, key=version_key, reverse=True)]})
    return result


def check(root):
    root = Path(root)
    notes = parse_notes((root / 'release_notes.json').read_text(encoding='utf-8'))
    for path, expected in outputs(root, notes).items():
        if not path.is_file() or path.read_bytes() != expected.encode('utf-8'):
            raise NotesError(str(path.relative_to(root)) + ' is missing or stale; regenerate release notes')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    try:
        check(args.root.resolve())
        print('All 11 changelogs match canonical release notes.')
    except (OSError, ValueError) as error:
        parser.exit(1, str(error) + '\n')
