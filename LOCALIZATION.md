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
Unsupported/custom text and all objective progress retain the complete source
message; the receiver never invents quest-ID labels or objective identities. Successful
native lookups are cached for five minutes,
misses for five seconds, with 256 entries and at most ten native data-load requests
per 30 seconds. Each missing quest is requested at most once per 30 seconds. Loaded
results are used on subsequent presentation; old chat lines are not reprinted.

Progress preserves the sender's original objective wording and counts in every locale,
including when a local quest title is available. WoW's objective rows do not provide
a cross-stage stable target identity, so the receiver cannot safely translate an
objective description using its own quest log. Readable foreign-language text is
preferred over generic numbered objectives. Progress presentation performs no local
quest-data lookups; optional objective facts remain on the wire for compatibility.
Lifecycle titles still prefer available local data, including repairs of sent Quest-ID
placeholders. Monitored-quest scan announcements carry a bounded count fact;
older receivers retain the original readable text. Comparison
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
2. Author missing entries in `locales/<locale>.json` directly in the active
   Codex session, preserving reviewed translations. Use the setting or screen
   context and established WoW terminology; review each language for natural
   wording. This default workflow requires no model API credentials.
3. Review wording and button lengths. Run `python3 scripts/localization.py --write`
   to generate Lua and localized addon-list descriptions, then rerun without `--write`.
4. Run `python3 scripts/test_localization.py` and the addon suite. The offline runner
   supports `QT_TEST_LOCALE=deDE lua scripts/test.lua`; repeat for all supported locales.

The separate `python3 scripts/translate_locales.py --write` utility remains an
optional, explicitly selected UI-string API client. It uses `OPENAI_API_KEY` and
incurs API charges; it is not required for UI updates or release preparation.
Its `--notes` mode is retired. Do not run this paid utility as part of the default
Codex authoring workflow.

Formatting placeholders and command syntax must survive translation. The validator
checks source-key completeness, placeholder order, boundary whitespace, and generated
file consistency. A reviewed source audit catches new prose that lacks a lookup.
The source audit examines visible text inside WoW color/hyperlink markup while
excluding texture and atlas payloads. Add tests for newly encountered markup.

Behavioral fixtures use an explicit English registration policy by default. For
presentation coverage, register with `RegisterTest(name, callback, { locale =
"client" })`; isolation preserves the client locale for these cases. The CI locale
matrix runs actual tooltip, notice, menu, settings-status, comparison/consent and
notes renderers under each selected locale and prints the presentation-case count.
New presentation paths need a client-locale case, not just English assertions.

These checks do not establish translation quality or native UI fit; inspect settings,
comparison, sharing requests, map tooltips and notes in the relevant live client.

Use complete format strings for sentences so translations can place names and titles
naturally. Monitored counts use a label followed by the number, avoiding a plural
suffix that fails for singular counts or languages with several plural forms.

Quest title resolution includes current-session, matching-locale task trackers once
the initial scan completes. Saved tracker titles from another locale are not local
translations. Open comparisons invalidate cached misses on quest-data load results
and retry queued title loads under the existing ten-per-30-second limit, at most
twice per quest per comparison. Closing or replacing the comparison invalidates its
callbacks; these refreshes never request new remote snapshots or replay chat.

## Patch notes and Discord

The canonical English source remains `release_notes.json`. Each
`release_notes/<locale>.json` contains localized notes and `source_sha256`, a digest
of the English content excluding its version. `LocalizedReleaseNotes.lua` is generated
from these files and used in the in-game notes window. Section topics, illustration
identifiers, version and source digest must match before release. Languages may
split or combine bullets naturally; equal item counts are not a quality check.

For automated local authoring and review of release facts, English and all ten
other languages, run:

```sh
python3 scripts/author_release_notes.py --include-working-tree --output-dir .local/release-notes-draft
```

Omit `--include-working-tree` for a clean, committed checkout. The command uses
`codex exec` with saved ChatGPT login authentication and defaults to `gpt-6.1-sol`.
It rejects API-key authentication without falling back to a paid model API.
Subscription usage limits apply, and the local machine must stay running and
connected. Use `--baseline-ref` for an explicit release baseline, `--model` to
select another model, or repeat the same command with `--resume` to continue an
interrupted run. Code evidence, facts and localized terminology are sent to Codex
for authoring and review; deterministic export and validation are offline.

Manual authoring in an active Codex subscription session remains supported.
Prefer GPT-6.1 Sol for that work. Export the evidence with
`python3 scripts/prepare_release_notes.py context --include-working-tree --output .local/release-notes-draft/context.json`;
omit `--include-working-tree` when local edits do not belong in the evidence.

Establish the approved factual scope from the implementation first. Write a
neutral `facts.json` brief with prerequisites, defaults, limits and other approved
details, then compose English and every destination language independently from
those facts. Locale writers should receive facts, source evidence and relevant
localized UI labels, not finished English prose to translate line by line. Remove
previous notes and changelog prose from their writing context. Each language
needs its own editing pass for fluency, localized labels and factual parity;
these reviews are not native-speaker signoff.

The automated command saves `context.json`, the raw brief and notes as
`facts.json`, `enUS.json` and one `<locale>.json` per supported locale under
`.local/release-notes-draft/`, along with authoring and review results. For manual
authoring, save the same complete draft set. Each brief and notes file uses the
raw notes schema (`version`, `welcome`, `sections`), with matching topics, tips and
illustrations. Drafting leaves canonical files untouched. After successful
authoring and review, finalize the complete set with:

```sh
python3 scripts/prepare_release_notes.py finalize --draft-dir .local/release-notes-draft --context .local/release-notes-draft/context.json
python3 scripts/check_release_notes.py --write
python3 scripts/check_release_notes.py --check --release-history
```

Finalization validates the brief, all languages and implementation context before
replacing canonical JSON and computing source digests. Rendering generates the
Lua and Markdown. Neither step contacts a model service. The optional Prepare
release notes workflow exports an evidence artifact only; automated writing runs
locally with the saved ChatGPT login. Do not copy login credentials into CI.
Version bumps and publishing reuse the reviewed canonical files
without model calls. Any English wording change invalidates every old patch-note
source digest, so review all languages and finalize the complete set again.

Historical corrections use exact per-release tag ranges and approved English
scope, including committed editorial corrections and legacy notes from before
structured JSON. Preserve dates, illustrations and corrected localization records.
See `RELEASING.md` for backups, retained corrections and publication boundaries.

The Discord release workflow posts English plus the ten translations from the exact
published tag. `discord_channels.json` pins each channel's ID and translated name;
posting validates the bot, guild, all destinations and release artifacts first.
Per-channel markers make retries safe after partial delivery. Credentials are supplied
by the existing secret, never placed in translation files or release archives.

Channel provisioning is a separate maintainer action using
`scripts/setup_localized_discord.py`; normal release publishing never creates channels.
