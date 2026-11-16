<!-- SPDX-License-Identifier: GPL-3.0-only -->
# Source and editable assets

The source repository is https://github.com/AlexAllocated/QuestTogether.
Lua is distributed as editable source. Deterministic installation archives also
include the original SVG inputs, asset-generation Python scripts,
`Media/README.md`, audio synthesis recipe and metadata, and complete license and
attribution notices. No private signing or issuer key is needed to modify or
install the addon. Development tools referenced below are external dependencies,
not bundled components.

## Identify the exact source

The license-transition commit is
`0390b81dfecf1469aba9b05d6a9cdb3107aa61c6`, and the first stable release under
GPL-3.0-only is 10.0.0 (`v10.0.0`). The transition commit identifies the licensing
change; obtain the complete source for a release from that release's exact source
commit, recorded in its package manifest or release description as described
below. Earlier MIT grants remain in force; see [LICENSING.md](LICENSING.md).

For an archive built with `scripts/package.py --ref <tag-or-commit>`, read
`QuestTogether/package-manifest.json`. `sourceCommit` is the full Git commit;
`sourceRepository` identifies the repository, and `sourceUrl` points to that
exact commit. The manifest hashes all installed files. Schema 3 also records
`license: GPL-3.0-only`; exceptions are in LICENSING.md and NOTICE.
An archive built without `--ref` is an unpublished working-tree preview:
`sourceCommit` and `sourceUrl` are null, so it does not claim an exact published
source identity.

The source tree and archive URLs for a recorded commit are:

```text
https://github.com/AlexAllocated/QuestTogether/tree/<sourceCommit>
https://github.com/AlexAllocated/QuestTogether/archive/<sourceCommit>.tar.gz
```

Check out that exact commit to obtain all development tools, localization
catalogs, tests, generated-data inputs, and asset sources together:

```sh
git clone https://github.com/AlexAllocated/QuestTogether.git
cd QuestTogether
git checkout --detach <sourceCommit>
python3 scripts/package.py --ref <sourceCommit> --output dist/QuestTogether.zip
```

The repository-based source packager includes tracked sources and applies the
folder move in `.pkgmeta`; it does not create the deterministic packager's
manifest. Its release page must therefore identify the immutable release tag
and full source commit, and link the source tree and archive for that commit.
A version label alone is insufficient, and a local uncommitted source tree
cannot provide that published mapping.

## Preferred editable asset sources

| Output | Editable inputs and generator |
| --- | --- |
| Scroll logo and badge textures | `logo.svg`, marker SVGs under `Media/`, `scripts/build_minimap_icon.py` |
| Chat bubble | `Media/ChatBubbleIcon.svg`, `scripts/build_chat_icon.py` |
| Party markers, follower chevrons and quest-chain icon | Matching `Media/*.svg`, `scripts/build_party_icons.py` |
| Panel corners | `Media/PanelCornerFill.svg`, `Media/PanelCornerBorder.svg`, `scripts/build_panel_corners.py` |
| Party Quest Log scroll | `Media/QuestCompareScroll.svg`, `scripts/build_compare_scroll.py` |
| Focus and minimap rings | `scripts/build_focus_ring.py`, `scripts/build_minimap_ring.py` |
| Minimap button variants | Base logo textures and `scripts/build_minimap_buttons.py` |
| Party waypoint | `Media/PartyWaypoint.svg`; conversion commands in `Media/README.md` |
| Audio gain variants | `scripts/build_audio.py`, `Media/Audio/manifest.json` |
| Screenshot textures | Original `Media/ReleaseNotes/*.png`; conversion commands in `Media/README.md` |

Use Python 3 for the scripts. Vector/raster builders document their required
`rsvg-convert` (librsvg) and ImageMagick 7 tools; audio generation requires
`ffmpeg` with `libvorbis`. Run audio validation with
`python3 scripts/build_audio.py --verify-only`. See each script's help and
`Media/README.md` for commands and variants. The scripts and inputs are the
editable source; byte-identical regenerated media is not promised across tool
versions. Screenshot conversions preserve third-party artwork and do not acquire
the original-art license merely by being generated.

## Release source and licensing requirements

1. Record the full license-transition commit and the release's actual source
   commit. Verify that the release descends from that transition; do not relabel
   historical MIT tags.
2. Keep source, editable asset inputs, generation scripts, license texts, and
   notices available at the release commit. Regenerate the checked-in Tests
   companion after changing legal files or its canonical TOC.
3. Build and verify from the exact release ref. Publish that source reference
   alongside the installation archive, including for source-packager uploads.
4. Set the project's applicable release license metadata to GPL-3.0-only, while
   keeping the bundled-license and screenshot exceptions visible. Record the
   first affected tag and transition hash in the release description.

These requirements apply from 10.0.0 onward. Earlier releases retain their
existing license terms. Adding license files or building a local ZIP does not
publish a release or establish its exact published source identity.
