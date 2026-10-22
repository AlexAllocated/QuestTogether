#!/usr/bin/env python3
"""Generate repository changelogs from the same canonical notes as Discord."""
import argparse
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
from check_release_notes import NotesError, git, markdown_tip, parse_notes, toc_version, unique_object, version_key
from localization import LOCALES, digest, dumps, read, release_note_outputs, validate_release_locale

HISTORY = 'changelogs/history.json'
LEGACY = 'changelogs/legacy_notes.json'
REVISIONS = 'changelogs/localized_revisions.json'
TITLES = {'enUS': 'Changelog', 'deDE': 'Änderungsprotokoll', 'frFR': 'Journal des modifications',
          'esES': 'Registro de cambios', 'esMX': 'Registro de cambios', 'ptBR': 'Registro de alterações',
          'ruRU': 'Журнал изменений', 'itIT': 'Registro delle modifiche', 'koKR': '변경 내역',
          'zhCN': '更新日志', 'zhTW': '更新日誌'}


def validate_entry(entry):
    if not isinstance(entry, dict) or 'enUS' not in entry or set(entry) - set(TITLES):
        raise NotesError('invalid changelog history languages')
    source = parse_notes(dumps(entry['enUS']))
    for locale, notes in entry.items():
        validate_release_locale(source, notes, 'changelog history ' + locale)
    return source['version']


def approved_english(root, version):
    """Use committed editorial history when it corrects an immutable tag's prose.

    Implementation evidence still comes from the release tag. Only already
    committed English corrections are authoritative; a dirty history entry or
    a draft for the current release must not authorize itself.
    """
    version_key(version)
    ref = 'refs/tags/v' + version
    if toc_version(git(root, 'show', ref + ':QuestTogether.toc').stdout) != version:
        raise NotesError('changelog tag version mismatch')
    approved = {}
    for path in (HISTORY, LEGACY):
        result = git(root, 'show', 'HEAD:' + path, allow_failure=True)
        if result.returncode:
            continue  # Repositories predating a structured archive.
        history = json.loads(result.stdout, object_pairs_hook=unique_object)
        if path == HISTORY:
            if not isinstance(history, dict) or set(history) != {'schema', 'releases'} or history['schema'] != 1:
                raise NotesError('invalid committed changelog history schema')
            history = history['releases']
        if not isinstance(history, list):
            raise NotesError('invalid committed changelog history schema')
        for entry in history:
            archived_version = validate_entry(entry)
            if archived_version in approved:
                raise NotesError('duplicate committed changelog version: ' + archived_version)
            approved[archived_version] = entry['enUS']
    if version in approved:
        return approved[version]
    published = parse_notes(git(root, 'show', ref + ':release_notes.json').stdout)
    if published['version'] != version:
        raise NotesError('changelog tag version mismatch')
    return published


def localized_revisions(root):
    path = Path(root) / REVISIONS
    if not path.exists():
        return {}
    data = read(path)
    if not isinstance(data, dict) or set(data) != {'schema', 'releases'} or data['schema'] != 1 or not isinstance(data['releases'], list):
        raise NotesError('invalid localized revision schema')
    revised = {}
    for entry in data['releases']:
        version = validate_entry(entry)
        if version in revised or set(entry) != {'enUS', *LOCALES}:
            raise NotesError('duplicate or incomplete localized revision: ' + version)
        source = approved_english(root, version)
        if entry['enUS'] != source:
            raise NotesError('localized revision changes published English notes or their committed editorial correction: ' + version)
        revised[version] = entry
    return revised


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
    # Editorial corrections must survive the next bump, which otherwise reads
    # the original translations back out of the immutable published tag.
    return localized_revisions(root).get(version, entry)


def render(locale, entries):
    lines = ['# QuestTogether — ' + TITLES[locale], '',
             '<!-- Generated from canonical release notes; do not edit by hand. -->', '']
    if locale == 'enUS':
        lines += ['[Other languages](changelogs/README.md)', '']
    for entry in entries:
        notes = entry.get(locale)
        if not notes or not notes['sections']:
            continue
        lines += ['## ' + notes['version'], '', notes['welcome'], '']
        for section in notes['sections']:
            lines += ['### ' + section['title'], '']
            lines += ['- ' + item for item in section['items']]
            lines += ['']
            if 'tip' in section:
                lines += [markdown_tip(section['tip'], notes['version']), '']
            for client, asset in illustration_images(section.get('illustration')):
                url = 'https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v' + notes['version'] + '/Media/ReleaseNotes/' + asset + '.png'
                lines += ['**' + client + '**', '', '![' + section['title'] + ' — ' + client + '](' + url + ')', '']
    if locale == 'enUS':
        lines += ['[Earlier handwritten changelog](changelogs/legacy-enUS.md)', '']
    return '\n'.join(lines)


def illustration_images(illustration):
    if illustration == 'vip-cosmetics':
        return [('Forever', 'VIPCosmetics')]
    if illustration == 'party-quest-log':
        return [('Retail', 'PartyQuestLogRetail'), ('Forever', 'PartyQuestLogForever')]
    if illustration == 'party-quest-objectives':
        return [('Forever', 'PartyQuestObjectivesForever')]
    if illustration == 'party-quest-overview':
        return [('Forever', 'PartyQuestOverviewForever')]
    if illustration == 'party-quest-following':
        return [('Forever', 'PartyQuestFollowingForever')]
    if illustration == 'party-quest-focus-warning':
        return [('Forever', 'PartyQuestFocusWarningForever')]
    if illustration == 'quest-tracker':
        return [('Forever', 'QuestTracker')]
    if illustration == 'quest-tracker-edit-mode':
        return [('Forever', 'QuestTrackerEditMode')]
    if illustration == 'quest-tracker-display':
        return [('Forever', 'QuestTrackerDisplay')]
    return []


def outputs(root, notes, localized_outputs=None, previous_version=None):
    root = Path(root)
    revisions = localized_revisions(root)
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
        if version in revisions and entry != revisions[version]:
            raise NotesError('archived localization differs from its editorial revision: ' + version)
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
    legacy_path = root / 'changelogs/legacy_notes.json'
    if legacy_path.exists():
        legacy = read(legacy_path)
        if not isinstance(legacy, list):
            raise NotesError('legacy notes must be a list')
        for entry in legacy:
            version = validate_entry(entry)
            if version in entries or version_key(version) >= version_key(notes['version']):
                raise NotesError('duplicate or newer legacy release: ' + version)
            if version in revisions and entry != revisions[version]:
                raise NotesError('legacy localization differs from its editorial revision: ' + version)
            entries[version] = entry
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
