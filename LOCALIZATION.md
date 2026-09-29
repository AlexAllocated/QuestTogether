# Localization

QuestTogether selects the WoW client language automatically. Initial translations:
German (deDE), French (frFR), Spanish (esES and esMX), Brazilian Portuguese (ptBR),
and Russian (ruRU). English is the fallback for unsupported locales and absent keys.
These are initial translations; native-speaker feedback is welcome in Discord.

## Text ownership

`Localization.lua` supplies the private translator before Core loads. The generated
`Locales.lua` contains the five dictionaries from `locales/*.json`. Source English
strings are keys; change a source string to invalidate its old translations.
Wrap user-facing static text in `L("...")`. Keep command words, saved-setting keys,
API identifiers, model status values, and communication fields unchanged. Translate
canonical status values at presentation, never before comparisons or transmission.
`locales/dynamic.json` lists such presentation keys and shared LibChev UI strings.

Incoming announcements, quest titles/objective text, and player-supplied names stay
in the sender's language. Local event labels use the local language. Diagnostics,
raw debug records and test failure details retain their original wording so reports
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

The Discord release workflow posts English plus the five translations from the exact
published tag. `discord_channels.json` pins each channel's ID and translated name;
posting validates the bot, guild, all destinations and release artifacts first.
Per-channel markers make retries safe after partial delivery. Credentials are supplied
by the existing secret, never placed in translation files or release archives.

Channel provisioning is a separate maintainer action using
`scripts/setup_localized_discord.py`; normal release publishing never creates channels.
