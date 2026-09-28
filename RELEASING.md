# Releasing QuestTogether

`release_notes.json` is the canonical source for the in-game welcome and latest
patch notes. `ReleaseNotes.lua` is generated data; do not edit it by hand. Keep
notes concise and useful to players. Every release, including patch and
prerelease versions, needs updated content even when it does not open the notes
window automatically. Automatic opening is a runtime policy for major/minor
upgrades, not an exemption from writing patch notes.

## Prepare the notes

1. Update `CHANGELOG.md` and the welcome/sections in `release_notes.json` for the
   changes being released. Keep its version equal to `QuestTogether.toc` while
   developing; the release script updates both versions together.
2. Generate and check the Lua data:

   ```sh
   python3 scripts/check_release_notes.py --write
   python3 scripts/check_release_notes.py --check --release-history
   python3 scripts/test_release_notes.py
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

## Check and release

Use a full Git checkout with the published tags available. A shallow checkout
is rejected for release-history checks; fetch the missing history and tags
instead of disabling validation. CI uses `fetch-depth: 0`.

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
checks for an existing remote tag, updates the TOC and JSON version, regenerates
and rechecks `ReleaseNotes.lua`, then commits all three release files and pushes
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
