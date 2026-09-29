# Releasing QuestTogether

`release_notes.json` is the canonical source for the in-game welcome, latest
patch notes, and Discord release announcements. German (`deDE`), French (`frFR`),
Spanish (`esES`), Brazilian Portuguese (`ptBR`), and Russian (`ruRU`) translations
live in `release_notes/<locale>.json`. `ReleaseNotes.lua` and
`LocalizedReleaseNotes.lua` are generated data; do not edit them by hand. Keep
notes concise and useful to players. Every release, including patch and
prerelease versions, needs updated content even when it does not open the notes
window automatically. Automatic opening is a runtime policy for major/minor
upgrades, not an exemption from writing patch notes.

## Prepare the notes

Use **Actions → Prepare Release Notes → Run workflow** on `main`. It compares
the current code with the published tag matching the TOC version, generates
player-facing notes with the same OpenAI workflow used by Bumblebee, and opens
a review PR containing the English notes, all five translations, and both generated
Lua files. It also uploads those files and English Markdown notes as an artifact.
Review and merge that PR before the version bump. It does not tag, release, or
announce anything.
If repository policy blocks Actions from opening PRs, the generated artifact
remains available; use its files through the normal review process.

For local preparation, with `OPENAI_API_KEY` already in the environment:

```sh
python3 scripts/generate_release_notes.py --write
python3 scripts/translate_locales.py --notes --write
python3 scripts/check_release_notes.py --check
```

The default requires committed changes and a clean working tree. To deliberately
include local addon edits, use `--include-working-tree`. Omit `--write` to preview
generated notes without changing the addon. `--markdown-out <path>` writes the
same text for a GitHub release body. Generation uses `gpt-5.5` by default, matching
Bumblebee; `CHANGELOG_OPENAI_MODEL` or `--model` overrides it. Only release
evidence from approved addon/documentation paths is sent; credentials are never
written into generated content or the addon. An API failure, refusal, invalid
content or repeated previous notes fails instead of replacing files with a
placeholder. This uses the documented [Responses structured-output format](https://developers.openai.com/api/docs/guides/structured-outputs).
Generating notes from local edits does not include those edits in a release:
commit the implementation changes before running the release script.
English generation deliberately leaves existing translations untouched. Translate
again after the final English edit, then review every language before releasing.
The preparation workflow performs these steps in order and refuses to push its
branch if any translation or generated file fails validation. An English draft
artifact may still be available after a translation failure; it is not release-ready.

Authored notes remain supported:

1. Update `CHANGELOG.md` and review or edit the welcome/sections in
   `release_notes.json` for the changes being released. Keep its version equal to
   `QuestTogether.toc` while developing; the release script updates all versions
   together. AI generation drafts the prose; reviewing its accuracy is still
   part of releasing.
2. Translate the final English notes, then generate and check the Lua data:

   ```sh
   python3 scripts/translate_locales.py --notes --write
   python3 scripts/check_release_notes.py --write
   python3 scripts/check_release_notes.py --check --release-history
   python3 scripts/test_release_notes.py
   python3 scripts/test_generate_release_notes.py
   python3 scripts/test_discord_changelog.py
   ```

3. Review the generated content and complete the usual Lua, client-profile,
   library, and live-client validation appropriate to the change. Commit the
   feature changes and authored notes through the normal review process.

The JSON must contain `version`, a `welcome` string, and nonempty `sections` of
`title` and `items`. Unknown/duplicate fields, empty or placeholder text, invalid
versions, a version different from the TOC, and stale/missing generated Lua fail
validation. The generator emits only a literal Lua table with escaped primitive
strings. It does not execute JSON contents.
The checker also requires the TOC to load `ReleaseNotes.lua` exactly once after
`Core.lua`, so generated notes cannot silently be omitted from the addon.
When the TOC enables `LocalizedReleaseNotes.lua`, it must load exactly once after
the English notes, and **all five translations are mandatory for every release**.
Each translated JSON contains exactly `source_sha256` and `notes`. Its `notes`
has the same schema and version as the English source, with the same number of
sections and items and matching optional illustrations. The source digest is
SHA-256 over UTF-8 English JSON without `version`, serialized with sorted keys,
unescaped Unicode, and separators `(',', ':')`. Any English content change makes
old translations stale. Missing/stale translations, mismatched structure, or stale
generated localized Lua block release preparation. Version-only bumps preserve
the reviewed translations and their digest without contacting the translation API.
Structural validation cannot establish translation quality; human review is still
required. UI catalog validation is a separate `python3 scripts/localization.py`
check and does not replace patch-note translation validation.

## Check and release

Use a full Git checkout with the published tags available. A shallow checkout
is rejected for release-history checks; fetch the missing history and tags
instead of disabling validation. CI uses `fetch-depth: 0`.

Commit all implementation, test, documentation and workflow changes first.
Both preflight and publication reject staged, unstaged or unignored untracked
changes outside this explicit allowlist:

- `QuestTogether.toc`
- `release_notes.json`
- `ReleaseNotes.lua`
- `LocalizedReleaseNotes.lua`
- `release_notes/deDE.json`, `release_notes/frFR.json`, `release_notes/esES.json`,
  `release_notes/ptBR.json`, and `release_notes/ruRU.json`

The localized files are allowed only when the TOC enables localized notes.
These files may contain reviewed release preparation edits, staged or
unstaged; the release commit includes their current contents. Keep the TOC and
notes at the current published version until the script bumps them together.
Ignored local files are not release inputs. Rejection happens before remote
access or writes and preserves the worktree, index, commits and tags; the script
does not automatically stage or commit unrelated work.

First run a local preflight, for example:

```sh
bash scripts/bump_version.sh minor --check
bash scripts/bump_version.sh patch beta --check
```

`--check` validates the current authored/generated notes against the exact
`v<current TOC version>` release tag and displays the planned version. It does
not write files, contact remotes, commit, or tag. Missing/unreachable baseline
tags fail; a version-only, capitalization-only, or whitespace-only notes edit
does not count as new content. Reviewers still judge whether the notes actually
describe the release.

After the release has been explicitly authorized, omit `--check`:

```sh
bash scripts/bump_version.sh minor
```

The release path repeats the same checks **before** remote access or mutation,
checks for an existing remote tag, updates the TOC and every notes version,
regenerates and rechecks both Lua files, then commits the release files and pushes
the commit and annotated tag. The script performs publication; do not run it
merely to generate notes or preview a version. Existing alpha/beta sequencing
continues to use stable version tags as its base.

## Baseline enforcement

CI runs `--check --release-history`, comparing notes to the highest earlier
version tag reachable from `HEAD` (including alpha/beta versions). The current
version's tag is excluded so tag-push builds compare against the prior release,
not themselves. The release script uses the explicit current-version tag before
it bumps the version, so content authored in earlier feature commits still
counts. Neither path relies on a shallow checkout's incidental tag list.

For an explicit review, use
`python3 scripts/check_release_notes.py --check --baseline-ref v5.9.2`.
The baseline must be an ancestor of `HEAD`, and its notes must match its own TOC.
A legacy release that never tracked `release_notes.json` permits first adoption.
A missing file after notes were previously tracked, corrupt notes, or unavailable
baseline history fails instead of silently skipping the comparison.

The first release with in-game notes is 5.10.0, using the legacy 5.9.2 release
as its adoption baseline. Subsequent releases must change the authored content
as well as the version.

## Discord announcements

**Discord Changelog** runs when a GitHub release is published. It checks out the
exact tag and uses that tag's canonical notes, verifies the generated Lua and
release history, and waits for the versioned release ZIP and successful Tests
workflow for the same commit. It checks the ZIP's embedded notes before posting
them to QuestTogether's `#changelog` as the existing **Bumblebee** bot. It does
not regenerate or summarize notes at announcement time. The welcome window and
Discord therefore share the same welcome and bullet points, including patch and
prerelease notes; automatic window opening still follows the major/minor policy.

The bot must belong to the QuestTogether server and have View Channels, Send
Messages, Embed Links and Read Message History in `#changelog`. The script
verifies its identity, guild, channel and effective permissions before posting.
GitHub Actions configuration:

- `DISCORD_BOT_TOKEN` secret: the existing Bumblebee bot credential.
- `OPENAI_API_KEY` secret: used only by release-note preparation, not posting.
- `DISCORD_CHANGELOG_CHANNEL_ID` variable: `1553981217039187978`.

Expected guild is `1553951084941156502`; expected bot is `890285739940671548`.
Secrets are stored in GitHub Actions, not in the addon or workflow YAML. These
were provisioned from Bumblebee's existing configuration; rotating that shared
bot credential also requires updating QuestTogether's Actions secret.

Preview the current notes locally without network access:

```sh
python3 scripts/discord_changelog.py --dry-run
```

For a read-only connection check with the bot token and channel variable in the
environment, run `python3 scripts/discord_changelog.py --check-access`. To retry
an actual published announcement, manually run **Discord Changelog**, select its
tag, and disable the default dry-run option. Long notes are split at bullet
boundaries without dropping text. Bot-authored part markers skip already posted
parts, including after a partial failure, and a stable nonce protects short
transport retries. Mentions are disabled. Conflicting notes, a wrong destination,
missing permissions or an exhausted history scan fail instead of blindly posting.
The implementation follows [Discord's message limits and nonce contract](https://docs.discord.com/developers/resources/message).

Publishing a release with a workflow's default `GITHUB_TOKEN` does not trigger
another release-event workflow ([GitHub's event rules](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow)). If packaging is later moved into Actions, invoke
the changelog workflow explicitly from that pipeline or use the normal authorized
release publisher. The current maintainer-driven release publication emits the
release event. Do not send announcements for uncommitted work or a tag whose
download/validation is not ready.
