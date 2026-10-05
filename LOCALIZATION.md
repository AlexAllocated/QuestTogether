# Localization

QuestTogether follows WoW's **nine languages, represented by eleven in-game text
locales**. Each Spanish locale and each Chinese writing variant has its own catalog.

| Language / variant | In-game locale |
| --- | --- |
| English | enUS |
| German | deDE |
| French | frFR |
| Spanish — Europe | esES |
| Spanish — Latin America | esMX |
| Portuguese — Brazil | ptBR |
| Russian | ruRU |
| Italian | itIT |
| Korean | koKR |
| Chinese — Simplified | zhCN |
| Chinese — Traditional | zhTW |

The English source plus ten non-English catalogs cover that set. WoW's European
English client uses the same in-game text locale as US English; `enGB` is retained
as a compatibility alias for `enUS`. `esMX` is not an alias for `esES`.
Unknown locales and absent keys fall back to English. Initial translations welcome
native-speaker feedback in Discord. We do not add languages unsupported by WoW.

## Text ownership

`Localization.lua` supplies the private translator before Core loads. The generated
`Locales.lua` contains the ten dictionaries from `locales/*.json`. Source English
strings are keys; change a source string to invalidate its old translations.
Wrap user-facing static text in `L("...")`. Keep command words, saved-setting keys,
API identifiers, model status values, and communication fields unchanged. Translate
canonical status values at presentation, never before comparisons or transmission.
`locales/dynamic.json` lists such presentation keys and shared LibChev UI strings.

New peers append optional facts to the existing version-3 ANN payload. Each packet
still contains the sender's original text; old receivers ignore the extension, and
new receivers preserve unrecognized text when facts are missing, invalid, unsupported,
or omitted to fit the 255-byte wire limit. Known quest lifecycle labels can still be
localized from their event type and an exact supported-language prefix. No per-language
packets are broadcast.

For different-language senders, `EventLocalization.lua` renders supported event labels
locally and resolves quest titles through addon snapshots or guarded native quest-data
APIs. If a title is unavailable, quest lifecycle events translate the label while
retaining the sender's readable title, extracted only from an exact known prefix.
Unsupported/custom text and progress without a local title retain the complete source
message; the receiver never invents quest-ID labels or objective identities. Successful
native lookups are cached for five minutes,
misses for five seconds, with 256 entries and at most ten native data-load requests
per 30 seconds. Each missing quest is requested at most once per 30 seconds. Loaded
results are used on subsequent presentation; old chat lines are not reprinted.

Progress uses transmitted objective index, count/total, percentage, or completion
state. WoW's objective rows do not provide a cross-stage stable target identity, so
translated progress says, for example, “Objective 2: 3/8” instead of borrowing the
receiver's current objective description or counters. Legacy text-only APIs can send
completion state; without trustworthy structured facts the original text is retained.
Same-language announcements retain their detailed native objective wording. Comparison
rows prefer the receiver's local quest title when available. Player names are unchanged.
Public party chat stays in the sender's language because everyone receives one string.

Native APIs are read through addon-owned wrappers, never replaced in live tests.
No foreign UI objects or quest selection are mutated. Restricted native reads wait
until a later presentation call; cached local titles can still be displayed.

Diagnostics, raw debug records and test failure details retain their original wording so reports
remain useful across locales; shared debug window controls and headings are translated.

## Updating interface text

1. Add `L()` calls and update the reviewed `locales/source_audit.json` exemptions only
   for native identifiers, canonical values, diagnostics, or sample proper names.
2. Set `OPENAI_API_KEY` in the environment and run
   `python3 scripts/translate_locales.py --write` to draft missing translations.
   Existing translated entries are preserved; remove an entry to request a new draft.
3. Review wording and button lengths. Run `python3 scripts/localization.py --write`
   to generate Lua and localized addon-list descriptions, then rerun without `--write`.
4. Run `python3 scripts/test_localization.py` and the addon suite. The offline runner
   supports `QT_TEST_LOCALE=deDE lua scripts/test.lua`; repeat for all supported locales.

Formatting placeholders and command syntax must survive translation. The validator
checks source-key completeness, placeholder order, boundary whitespace, and generated
file consistency. A reviewed source audit catches new prose that lacks a lookup.
These checks do not establish translation quality or native UI fit; inspect settings,
comparison, sharing requests, map tooltips and notes in the relevant live client.

## Patch notes and Discord

The canonical English source remains `release_notes.json`. Each
`release_notes/<locale>.json` contains translated notes and `source_sha256`, a digest
of the English content excluding its version. `LocalizedReleaseNotes.lua` is generated
from these files and used in the in-game notes window. The note sections, item counts,
illustration identifiers, version and source digest must match before release.

After drafting English notes, run `python3 scripts/translate_locales.py --notes --write`,
review every language, then `python3 scripts/check_release_notes.py --check`. The
Prepare release notes workflow performs these steps before opening its review PR.
Version bumps reuse validated translations and update all versions without API calls.
Any English wording change invalidates every old patch-note translation.

The Discord release workflow posts English plus the ten translations from the exact
published tag. `discord_channels.json` pins each channel's ID and translated name;
posting validates the bot, guild, all destinations and release artifacts first.
Per-channel markers make retries safe after partial delivery. Credentials are supplied
by the existing secret, never placed in translation files or release archives.

Channel provisioning is a separate maintainer action using
`scripts/setup_localized_discord.py`; normal release publishing never creates channels.
