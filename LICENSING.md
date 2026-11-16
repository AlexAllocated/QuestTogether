<!-- SPDX-License-Identifier: GPL-3.0-only -->
# QuestTogether licensing

Project-owned code, documentation, and original assets in this revision and
subsequent revisions are licensed under the GNU General Public License, version
3 only (`GPL-3.0-only`). The complete, unmodified license is in [LICENSE](LICENSE).
This includes the optional QuestTogether Tests companion and development tools.
Copyright remains with the respective contributors; existing notices and Git
history identify their contributions. No copyright assignment is required.

This is a prospective license transition. Earlier copies offered under MIT
retain their MIT permissions; this change does not withdraw those permissions
or make earlier releases GPL-only. [LICENSES/MIT.txt](LICENSES/MIT.txt) preserves
the MIT permission and warranty terms. Preserve any copyright notices supplied
with the earlier copy. New project-owned contributions from this transition
forward use GPL-3.0-only; they are not also offered under MIT by this notice.

The license transition is commit
`0390b81dfecf1469aba9b05d6a9cdb3107aa61c6`, which first added this file and changed
the main TOC's `X-License` to `GPL-3.0-only`. The first stable release under these
terms is 10.0.0 (`v10.0.0`). Earlier releases, including 9.3.3, retain their
existing MIT terms. Verify the transition in a complete checkout with:

```sh
git log --reverse --diff-filter=A --format='%H %ad %s' --date=iso-strict -- LICENSING.md
git show <transition-commit> -- QuestTogether.toc LICENSING.md
```

A working-tree preview does not establish an exact published source identity.
The transition commit identifies the licensing change, not the complete source
of every subsequent release. Existing release tags are not relabeled. Release
metadata must identify the actual tag and full source commit as described in
[SOURCE.md](SOURCE.md).

## Scope and exceptions

- `Libs/libchev/` remains MIT-licensed under its own unchanged license and pinned
  manifest. The copy of its self-tests in a deterministic Tests package remains
  covered by that MIT notice.
- `Libs/Ed25519/` retains its existing TweetNaCl public-domain provenance and
  original-author attribution. The GPL statement covers QuestTogether-owned
  adaptations, not an exclusive claim to the upstream public-domain material.
- Blizzard game artwork, fonts, sounds, UI resources, names, and other third-party
  material displayed by the game are not relicensed by this project. Screenshots
  and their conversions, including `Media/ReleaseNotes/`, contain game/runtime
  artwork and are excluded from the blanket GPL asset grant. This project claims
  no ownership of that material and grants no rights on Blizzard's behalf.
- Original QuestTogether SVG artwork, its generated textures, and procedurally
  synthesized audio are included in the project-owned grant, to the extent the
  project holds rights. [Media/README.md](Media/README.md) and
  [Media/Audio/NOTICE.txt](Media/Audio/NOTICE.txt) describe their editable sources
  and recorded provenance. Generated previews do not expand ownership claims.
- QuestieDB is an optional external dependency, not a bundled database or part
  of this license grant. Its code, data, and notices remain with that project.

[NOTICE](NOTICE) identifies bundled components and exclusions.
[CONTRIBUTING.md](CONTRIBUTING.md) explains contribution licensing and
[SOURCE.md](SOURCE.md) explains source and asset availability. These notices
describe scope; they do not modify the terms of the GPL or third-party licenses.
