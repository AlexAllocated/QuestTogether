# Releasing QuestTogether

`release_notes.json` is the canonical source for the in-game welcome, latest
patch notes, Discord release announcements, and repository changelogs. German (`deDE`), French (`frFR`),
European Spanish (`esES`), Latin American Spanish (`esMX`), Brazilian Portuguese (`ptBR`), Russian (`ruRU`), Italian (`itIT`),
Korean (`koKR`), Simplified Chinese (`zhCN`), and Traditional Chinese (`zhTW`) translations
live in `release_notes/<locale>.json`. `ReleaseNotes.lua` and
`LocalizedReleaseNotes.lua` are generated data; do not edit them by hand. Keep
notes concise and useful to players. Every release, including patch and
prerelease versions, needs updated content even when it does not open the notes
window automatically. Automatic opening is a runtime policy for major/minor
upgrades, not an exemption from writing patch notes.

The in-game viewer groups a minor release and its patches on one page, with
the minor release first. Patch notes must describe only that patch's changes:
do not repeat the minor release's feature guide, tips, or illustrations.
When correcting older notes, compare the published tags to identify the actual
patch changes, update every locale in `changelogs/history.json`, then regenerate
the in-game history and repository changelogs with `check_release_notes.py --write`.

## Prepare the notes

Run the automated authoring workflow locally with a saved ChatGPT login in the
Codex CLI. It uses `codex exec` with `gpt-6.1-sol` by default and verifies that
authentication is ChatGPT before starting; API-key authentication is rejected,
with no paid model API fallback. Normal subscription usage limits apply. Keep
the local machine running and connected while the authoring and review passes run.

```sh
python3 scripts/author_release_notes.py --include-working-tree --output-dir .local/release-notes-draft
```

Omit `--include-working-tree` for a clean, committed checkout. The default
baseline is the published tag matching the TOC version; use
`--baseline-ref <last-release-tag>` when the intended change range needs an
explicit baseline. `--model <model>` overrides the default model. To resume an
interrupted run, repeat the same command and output directory with `--resume`.
Use `--scope <text-file>` to constrain the release's player-facing topics when
needed. Resume requires the same model, scope, evidence and UI terminology, and
preserves manually edited drafts instead of overwriting them. Automated runs
send complete eligible diffs and changed source files; oversized evidence stops
with instructions to author in the active session rather than silently omitting code.
For note-only releases, evidence records changed languages, release entries and
file hashes without sending finished note prose to the writers. Supply the
editorial purpose with `--scope`.
Do not reuse a draft after changing its implementation evidence; export a new
context and author a fresh draft.

The command exports `context.json`, establishes a neutral `facts.json`, authors
`enUS.json` and all ten locale drafts independently, and runs separate review
passes. It saves authoring and review results under the output directory and
validates the complete draft. It does not replace canonical notes, commit, tag,
publish or post announcements. Eligible code evidence, facts and locale
terminology are sent to Codex for these model passes. Only eligible addon
sources and documentation enter the evidence; private files and credentials are
excluded. Login credentials stay in the local Codex configuration and must not
be copied to a remote runner. Including local edits in evidence does not include
them in a release: commit implementation changes before running the release script.

Manual authoring in an active Codex subscription session remains supported.
Prefer GPT-6.1 Sol for this work. Export its context into the same draft directory,
again omitting `--include-working-tree` for a clean, committed checkout:

```sh
python3 scripts/prepare_release_notes.py context --include-working-tree --output .local/release-notes-draft/context.json
```

For either route, establish a shared factual brief from the evidence before
writing publication prose. Check the facts against the code and
approved release scope, including prerequisites, defaults, limits, privacy and
who sees each change. Compose English and each destination language from these
facts. Do not pass finished English prose to language writers as a translation
template. Remove prior notes and changelog prose from their writing context;
use localized UI labels as terminology. Give each language its own editing pass
for natural phrasing and factual parity. Section topics stay aligned, but English
grammar, sentence order and bullet counts do not dictate the destination text.

Save the neutral factual brief as `facts.json` and the reviewed raw notes in a
local draft directory, for example `.local/release-notes-draft/`, as `enUS.json`,
`deDE.json`, `frFR.json`, `esES.json`,
`esMX.json`, `ptBR.json`, `ruRU.json`, `itIT.json`, `koKR.json`, `zhCN.json` and
`zhTW.json`. Every file is a complete notes object with `version`, `welcome` and
`sections`, using the schema described below. Keep the version equal to
`QuestTogether.toc`; the release script bumps all versions together. These draft
files do not contain the canonical `source_sha256` wrapper. `facts.json` uses
the same raw schema, with short factual fragments and aligned topics, tips and
illustrations rather than finished publication prose.

After the authoring and review passes succeed, finalize the complete set, then
render and check the derived files:

```sh
python3 scripts/prepare_release_notes.py finalize --draft-dir .local/release-notes-draft --context .local/release-notes-draft/context.json
python3 scripts/check_release_notes.py --write
python3 scripts/check_release_notes.py --check --release-history
python3 scripts/test_release_notes.py
python3 scripts/test_discord_changelog.py
```

Context export, finalization and deterministic checks are offline; authoring and
language review contact Codex. Finalization validates the factual brief and every
language before replacing canonical notes and computes the source digests locally.
It also rejects context whose commit or implementation evidence no longer matches
the checkout. Invalid,
incomplete or stale drafts leave the canonical notes untouched. The context file
is maintainer data and is excluded from addon packages. After changing English
wording, review every locale against
the updated facts and finalize the complete set again; old source digests are
not reusable. Automated checks validate structure, commands and consistency,
not fluency or complete semantic equivalence. Complete the usual Lua,
client-profile, library and live-client validation appropriate to the change,
and commit implementation changes and reviewed notes through the normal process.

Context export, note preparation, validation and publication run locally.
There are no GitHub Actions workflows to dispatch or wait for. Use the local
commands above for authoring or export the context for the active Codex session.
Release validation and publishing consume reviewed canonical notes without
generating new prose.
The old API-backed note-generation commands, including both forms of
`translate_locales.py --notes`, are retired; use the subscription authoring path.

## Correct published notes

Keep a verified backup before editing historical notes. Use each release's own
preceding tag and exact target tag for evidence, never later or uncommitted code.
The approved English scope comes from that tag or an already committed editorial
correction in `changelogs/history.json` or `changelogs/legacy_notes.json`. Releases
before structured notes use the committed legacy scope and actual code/commit
range. Preserve English wording, versions, release dates and illustrations when
the task is to correct localizations. Silent releases stay empty in every language.
Write each language directly in the active session from the historical facts,
and review every affected version and locale before replacing canonical history.

`changelogs/localized_revisions.json` preserves corrected published localizations
so the next version bump cannot restore old wording from Git tags. Its English
reference must exactly match the corresponding tag or its already committed
editorial correction in either historical archive. Uncommitted English history
edits do not authorize themselves. Keep the revision record and historical
archives consistent when correcting existing published notes; a draft for a new
release must not overwrite the previous release's correction. Explicit note reuse
also retains corrected localizations instead of requiring old tag wording.
Regenerate derived files with `python3 scripts/check_release_notes.py --write`
and validate with `--check --release-history`. Updating local sources does not
change tags, Discord posts or published downloads.

The JSON must contain `version`, a `welcome` string, and nonempty `sections` of
`title` and `items`. Unknown/duplicate fields, empty or placeholder text, invalid
versions, a version different from the TOC, and stale/missing generated Lua fail
validation. The generator emits only a literal Lua table with escaped primitive
strings. It does not execute JSON contents.
Sections may also contain one optional `tip` object with exactly `label` and
`text`. The label is the localized `Tip:` prefix (1–40 characters); the body is
plain text (1–800 characters). Both must be nonempty and trimmed, and the label
must be one line. Do not include the lightbulb, Markdown, or WoW formatting:
the viewers supply the presentation. For example:

```json
"tip": {
  "label": "Tip:",
  "text": "Type /qt tip or /qt hint to see another QuestTogether tip whenever you like."
}
```

The in-game viewer shows this as a separate sample with the QT lightbulb icon,
a gold label, and cream body text, matching chat tips. Repository changelogs and
GitHub release Markdown use the same icon at 20 pixels in a blockquote. Its PNG
URL is pinned to the notes' release tag. Discord attaches the PNG once per
message and displays it beside the localized tip label in a separate embed,
with the exact body beneath it; it does not require a custom Discord emoji.
The asset's first release is declared in `TIP_ICON_FIRST_VERSION`; older notes
retain their original Unicode presentation so archived examples never reference
an asset missing from their tag. Discord keeps every tip whole when splitting
messages and includes author labels in its text budget.
Omit `tip` entirely when none is needed; an empty or null tip is invalid.
Sections may include `illustration`: `quest-partners`, `party-quest-log`, or
`party-quest-objectives`. Party Quest Log screenshots are checked-in assets:
web changelogs and Discord label the Retail/Forever captures and link to the
release tag, while the in-game viewer selects the client's overview. The
expanded-objective capture is Forever-only in-game. Include the matching
`Media/ReleaseNotes/*.tga` files in the ZIP; see `Media/README.md` for conversion.
The checker also requires the TOC to load `ReleaseNotes.lua` exactly once after
`Core.lua`, so generated notes cannot silently be omitted from the addon.
When the TOC enables `LocalizedReleaseNotes.lua`, it must load exactly once after
the English notes, and **all ten translations are mandatory for every release**.
Each translated JSON contains exactly `source_sha256` and `notes`. Its `notes`
has the same schema and version as the English source, with the same section
topics and order, matching optional illustrations and tip presence. Languages
may split or combine bullets naturally; item counts need not match. Tip
labels and bodies must be translated, preserving their commands and arguments.
The same structure and command checks apply to archived release tips. The source digest is
SHA-256 over UTF-8 English JSON without `version`, serialized with sorted keys,
unescaped Unicode, and separators `(',', ':')`. Any English content change makes
old translations stale. Missing/stale translations, mismatched structure, or stale
generated localized Lua block release preparation. Version-only bumps preserve
the reviewed translations and their digest without model calls.
Structural validation cannot establish translation quality. Separate language
review checks fluency and factual parity; automated review is not native-speaker
signoff. UI catalog validation is a separate `python3 scripts/localization.py`
check and does not replace patch-note translation validation.

## Check and release

Use a full Git checkout with the published tags available. A shallow checkout
is rejected for release-history checks; fetch the missing history and tags
instead of disabling validation.

Commit all implementation, test, documentation and tooling changes first.
Both preflight and publication reject staged, unstaged or unignored untracked
changes outside this explicit allowlist:

- `QuestTogether.toc`
- `QuestTogether_Tests.toc` and generated `QuestTogether_Tests/QuestTogether_Tests.toc`
- `CHANGELOG.md`, `changelogs/history.json`, and `changelogs/<locale>.md` for the ten supported non-English locales
- `release_notes.json`
- `release_notes/context.json` and `changelogs/localized_revisions.json` when present
- `release_notes_reuse.json` when it exists or `--reuse-notes` is specified
- `ReleaseNotes.lua`
- `LocalizedReleaseNotes.lua`
- `ReleaseNotesHistory.lua` and `changelogs/release_dates.json` when the TOC enables history
- `release_notes/deDE.json`, `release_notes/frFR.json`, `release_notes/esES.json`, `release_notes/esMX.json`,
  `release_notes/ptBR.json`, `release_notes/ruRU.json`, `release_notes/itIT.json`,
  `release_notes/koKR.json`, `release_notes/zhCN.json`, and `release_notes/zhTW.json`

The localized files are allowed only when the TOC enables localized notes.
These files may contain reviewed release preparation edits, staged or
unstaged; the release commit includes their current contents. Keep the TOC and
notes at the current published version until the script bumps them together.
Ignored local files are not release inputs. Rejection happens before remote
access or writes and preserves the worktree, index, commits and tags; the script
does not automatically stage or commit unrelated work.

First run a local preflight, for example:

```sh
python3 scripts/deploy.py --bump minor --check
python3 scripts/deploy.py --bump patch --channel beta --check
```

`--check` validates the current authored/generated notes against the exact
`v<current TOC version>` release tag and displays the planned version. It does
not write files, contact remotes, commit, or tag. Missing/unreachable baseline
tags fail; a version-only, capitalization-only, or whitespace-only notes edit
does not count as new content. Reviewers still judge whether the notes actually
describe the release.

If the release owner explicitly requests identical notes, use the narrow
exception `python3 scripts/deploy.py --bump patch --reuse-notes --check`. Without
`--check`, the ordinary authorized publication workflow records the planned
version and its exact published baseline in `release_notes_reuse.json`:

```json
{"schema": 1, "releases": {"1.2.4": "1.2.3"}}
```

Reuse requires identical English and all enabled translated content, including
tips and illustrations, excluding only the version. The baseline must be the
reachable published `v<current TOC version>` tag. Check-only never writes this
acknowledgement. The tracked record lets local validation and Discord validate
that one release normally; it does not waive freshness for subsequent releases. New prose still
uses the normal workflow. This tooling metadata is not included in addon ZIPs.

After the release has been explicitly authorized, omit `--check`:

```sh
python3 scripts/deploy.py --bump minor
```

The launcher prepares the release locally, starts a detached systemd user
service, and returns a job ID and paths to its local status and log. Once it
reports that the job has started, you can keep working in the source checkout
or close the terminal. This requires a working systemd user manager. Keep the
machine running and connected and the user session active; the service does not
survive a reboot and does not retry failures automatically.

The deployment performs these steps in order:

1. Prepare the version commit and annotated tag locally, updating the TOCs,
   canonical note versions and generated release files together.
2. Copy the exact tagged commit into a separate checkout and run the local
   publisher there. Validate the tag and record successful validation for
   that commit. Later edits in the source checkout are not release inputs.
3. Build and verify the deterministic installation ZIP, SHA-256 sidecar and
   corresponding source archive locally.
4. Push the release commit and tag. Update the original release branch only
   when it can advance to that commit. If the remote branch already contains
   the release plus newer work, leave it ahead; divergent history stops the
   deployment. The tag triggers the existing CurseForge webhook; no polling,
   download inspection or extra CurseForge validation follows.
5. Upload the prepared archives to a draft GitHub release, then publish it.
6. Post the canonical notes to Discord from the same detached local job.

Each step must succeed before the next starts. The publisher does not wait for
GitHub Actions. A successful kickoff means the job started; only a completed
job means GitHub publication and Discord announcements succeeded.
The job also attempts a desktop notification on success or failure; the saved
status and log remain available if desktop notifications are unavailable.
It performs publication; do not run it merely to generate notes or preview a
version. Existing alpha/beta sequencing continues to use stable version tags as
its base. The lower-level `bump_version.sh --local-only` helper prepares a local
commit and tag. `deploy.py` is the usual entrypoint; `release.py` remains the
foreground worker for the complete release sequence.

Before publication, authenticate `gh` locally or provide `GH_TOKEN`, and make
`DISCORD_BOT_TOKEN` available in the local environment. The publisher cannot read
back the old GitHub Actions secret. Keep credentials out of command arguments,
tracked files and logs.

Inspect the latest local deployment at any time, or pass the printed job ID:

```sh
python3 scripts/deploy.py --status
python3 scripts/deploy.py --status <job-id>
```

Job files live under `.local/deployments/<job-id>/`, including `state.json`,
`deploy.log`, and the isolated `checkout/`. Keep that directory while the job
is running or may need to be resumed. Status inspection reads only local state
and the local service; it does not poll GitHub Actions or CurseForge. To watch
the saved log, use `tail -f .local/deployments/<job-id>/deploy.log`.

If a step fails, fix its cause and resume the same job with publication
credentials available in the environment:

```sh
python3 scripts/deploy.py --resume
python3 scripts/deploy.py --resume <job-id>
```

Resume uses the saved release checkout and does not create another version bump
or include later source changes. An already active job cannot be started twice.
To adopt a local tag that was prepared before starting a deployment:

```sh
python3 scripts/deploy.py --tag vX.Y.Z
```

The launcher can import an existing success receipt from
`.local/releases/<tag>/validation.json`. Use `--receipt <path>` with `--tag` or
`--resume` when the receipt was saved elsewhere; an explicitly supplied receipt
must match or the deployment stops.

Successful local validation is reused only when both the release commit and
validator fingerprint match. Already published Discord parts are skipped. An
interrupted local job is resumed explicitly; no remote workflow continues it.

### Local validation environment

The validator needs Git, Bash, OpenSSL, Lua 5.1, Lua 5.2 and Python with
`services/vip/requirements.txt` installed. Set `LUA51` and `LUA52`, or pass
`--lua51` and `--lua52`, if the interpreters are not named `lua5.1` and `lua5.2`.
Use `--python` for a prepared Python environment; `deploy.py` passes these options
through the publisher to the validator. Dependencies must already be installed: validation
does not install packages or contact the network.

To validate an existing tag without publishing:

```sh
python3 scripts/validate_release.py --ref vX.Y.Z --receipt /tmp/questtogether-validation.json
```

The validator creates a temporary local clone at the exact ref, runs the Python,
Lua, locale, client-profile, package and pinned-library checks sequentially, and
removes the temporary clone when finished. It streams logs to the terminal and
writes the success receipt outside tracked sources only after all checks pass.
Failure removes a stale receipt at that path. This automated suite supplements
the live-client checks appropriate to the change; it does not run a WoW client.

## Baseline enforcement

Local release validation runs `--check --release-history`, comparing notes to the
highest earlier version tag reachable from `HEAD` (including alpha/beta versions). The current
version's tag is excluded so release builds compare against the prior release,
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

Discord publication is the final local release step, after the exact tagged
commit passes local validation and its versioned ZIP is published on GitHub.
There is no Actions test dependency or separate remote announcement workflow. The
publisher verifies the public release tag and ZIP, including the archive's
embedded notes, before posting to QuestTogether's `#changelog` and localized
channels as the existing **Bumblebee** bot.

The exact tag supplies canonical notes, generated Lua, release history and
screenshots. The publisher does not regenerate or summarize notes at announcement
time. The welcome window and Discord therefore share the same welcome and bullet
points, including patch and prerelease notes; automatic window opening still
follows the major/minor policy. A missing or invalid download fails visibly.

The bot must belong to the QuestTogether server and have View Channels, Send
Messages, Embed Links and Read Message History in `#changelog`. The script
verifies its identity, guild, channel and effective permissions before posting.
Local publication credentials and destinations:

- `DISCORD_BOT_TOKEN`: the existing Bumblebee bot credential in the local environment.
- `discord_channels.json`: checked-in English and localized destination IDs.
- `DISCORD_CHANGELOG_CHANNEL_ID`: optional English-channel override; expected ID
  `1553981217039187978`.

Expected guild is `1553951084941156502`; expected bot is `890285739940671548`.
Keep the bot credential outside the repository and terminal output. It is shared
with Bumblebee's existing configuration, so credential rotation must also update
the local publisher's environment. No model API secret is used for release notes.

Preview the current notes locally without network access:

```sh
python3 scripts/discord_changelog.py --dry-run --all-locales
```

For a read-only connection check with the bot token in the environment, run
`python3 scripts/discord_changelog.py --check-access --all-locales`. Long notes are split at bullet
boundaries without dropping text. Bot-authored part markers skip already posted
parts, including after a partial failure, and a stable nonce protects short
transport retries. Mentions are disabled. Conflicting notes, a wrong destination,
missing permissions or an exhausted history scan fail instead of blindly posting.
The implementation follows [Discord's message limits and nonce contract](https://docs.discord.com/developers/resources/message).

Do not send announcements for uncommitted work or a tag whose download or local
validation is not ready. The tag push invokes CurseForge's existing packaging
webhook; release publication does not poll CurseForge or inspect its output.

## Synchronized repository changelogs

Do not hand-edit `CHANGELOG.md` or `changelogs/<locale>.md`. They are generated
by `python3 scripts/check_release_notes.py --write` from the exact welcome,
section titles, items, and optional tips used by Discord. Update the canonical JSON and all
translations first. The check mode, release preflight, local validation, and Discord posting
reject missing or stale Markdown. Commit these generated files alongside the
reviewed canonical notes. Local context export prepares authoring evidence only.

`changelogs/history.json` preserves the canonical notes from published tags.
The version-bump step archives the previous version from its reachable Git tag,
never from the edited draft, and then generates the new entry plus history.
Version bumps commit the archive and all eleven Markdown files together.
The original handwritten changelog is retained in `changelogs/legacy-enUS.md`.
Localized history includes the approved legacy entries as well as structured
published notes. It does not invent a release or its factual scope. Rendering
changelogs never reposts older Discord announcements; replacing those posts is a
separate, explicitly authorized maintenance operation.
No network or translation API is needed to regenerate existing changelogs.

Include `CHANGELOG.md` and `changelogs/*.md` in release downloads when packaging
documentation. The JSON archive is release tooling data, not an addon runtime
file. Existing published ZIPs and Discord messages remain unchanged.

## Browsable release history

The welcome window opens at the latest release. Older/Newer buttons page through
notes; History lists all bundled releases with publication dates in UTC. Browsing
history never changes upgrade acknowledgement or the major/minor popup policy.

`ReleaseNotesHistory.lua` is generated from `changelogs/history.json` and
`changelogs/legacy_notes.json`. The latter preserves releases predating structured
notes, including the 5.7.6 betas. All historical entries require every supported
locale. These same entries generate the English and localized Markdown changelogs.
Do not edit generated Lua or Markdown directly. Existing Discord posts are not
reposted when historical translations are backfilled.

`changelogs/release_dates.json` records dates from published GitHub releases. A
version bump records the new version's UTC date once and archives the published
previous notes. If publication moves to another day, update that date before
publishing and regenerate with `python3 scripts/check_release_notes.py --write`.
Local validation rejects missing dates, incomplete historical translations, duplicate versions,
and stale generated history. Include `ReleaseNotesHistory.lua` and the dates file
in release commits alongside the existing notes and changelogs.

## Reproducible installation packages

Build a reviewed commit or tag with the checked-in packager:

```sh
python3 scripts/package.py --ref HEAD --output dist/QuestTogether.zip
python3 scripts/test_package.py
```

Use the release tag instead of `HEAD` when packaging a published version. The
source is read directly from Git, so local edits and unrelated screenshots
cannot enter that archive. Omitting `--ref` builds a working-tree preview.
The TOC determines Lua load contents; explicit asset rules include game textures,
release screenshots, localized changelogs, editable SVG inputs, asset-generation
scripts, and complete project and vendor notices. The packager verifies the
pinned library manifest and writes a SHA-256 sidecar. See `SOURCE.md` for the
editable source inventory and tool dependencies, and `LICENSING.md` for the
prospective GPL-3.0-only scope and preserved third-party and historical MIT rights.

The archive installs two sibling folders: `QuestTogether` and the optional
`QuestTogether_Tests` companion. The latter is load-on-demand: normal gameplay
does not compile or register test fixtures. `/qt test` loads it before starting
the staggered test runner. Both TOCs must have matching version/interface metadata;
the bump script updates both version fields. Keep both folders when installing
the release if in-game tests are wanted; QT gameplay does not depend on the companion.

CurseForge's repository webhook packages source directly. `.pkgmeta` moves the
checked-in `QuestTogether_Tests/` directory beside the main addon and excludes the
canonical root companion TOC. Its generated TOC uses sibling-relative paths to
the original QA files in `QuestTogether`, which remain unloaded during normal
play. The pinned vendor tree stays intact; no test sources are duplicated.
After editing the canonical `QuestTogether_Tests.toc` or any packaged legal
notice, regenerate the source companion with
`python3 scripts/package.py --write-source-companion`. This also copies the
complete GPL, historical MIT terms, licensing scope, source guidance, and vendor
notices into the companion. Both installed addon folders retain those notices.
`--check-source-companion`, ordinary package builds and release preflight reject
stale manifests or legal copies. The bump script regenerates the source companion after updating
the two canonical versions. Package tests simulate the source folder move and
resolve every companion entry against the actual packaged files.

For a development checkout, keep the main addon linked to the repository. Create
`QuestTogether_Tests` as a separate directory with these links into the checkout:

- `QuestTogether_Tests.toc` -> the same-named root TOC
- `Tests.lua` -> the root test-registration file
- `scripts` -> the repository's scripts directory
- `Libs/libchev/SelfTests.lua` -> the pinned library's self-test file

Create an empty `Bindings.xml` containing `<Bindings></Bindings>` in the companion
directory as well. The package includes this empty container so native binding
discovery always finds a file but registers no commands.

Do **not** link the companion directory to the entire repository: WoW discovers
root `Bindings.xml` independently of the TOC and would register the main addon's
bindings a second time. These narrow links still pick up source and new regression
modules automatically. Adding the new addon folder may require restarting the game
so it is discovered. Offline tests read both canonical
manifests; `lua scripts/test_loader.lua` separately verifies cold startup and the
on-demand loading/failure path. Package schema 3 records installation-relative
paths for both folders, GPL-3.0-only metadata, the source repository, and the exact
commit URL. The verifier retains the original document requirements for historical
schema 1 and 2 archives; those releases are not retroactively relabeled.

Every archive contains `package-manifest.json` with its source commit and hashes
of all installed files. The packager validates the ZIP against those inputs,
and the Discord release verifier validates the whole installation manifest
when present. Historical archives without this manifest retain their existing
notes/version validation so old releases can still be reposted.

An unpublished working-tree preview has null `sourceCommit` and `sourceUrl`;
it cannot stand in for an exact release source reference. Before a separately
authorized GPL release, verify the actual release commit descends from the
license-transition commit identified in `LICENSING.md`. Record the full transition
hash, first affected tag, and full release source commit in the release description.
Keep all editable sources and generation tools available at that commit. Verify
the release's applicable host license metadata says GPL-3.0-only and retains the
bundled-license and screenshot exceptions. Source-packager releases do not create
the deterministic manifest, so their release page must explicitly link the exact
source commit and archive as described in `SOURCE.md`. These checks apply to the
GPL-3.0-only releases beginning with 10.0.0, not to historical MIT versions.

The local release process runs the package tests and builds the exact tested
commit with this packager before publication. It uploads that verified ZIP to
the GitHub release; do not maintain a release-specific file-copy script.
