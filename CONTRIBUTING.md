<!-- SPDX-License-Identifier: GPL-3.0-only -->
# Contributing to QuestTogether

Read [AGENTS.md](AGENTS.md) and the relevant development documentation before
changing the addon. Preserve unrelated work and the pinned vendor tree.

By intentionally submitting project-owned code, documentation, or assets for
inclusion after the license transition, you agree to license that contribution
under GPL-3.0-only. Contribute only material you have the right to submit under
those terms. You retain your copyright; no copyright assignment is required.
The full license and its scope are in [LICENSE](LICENSE) and
[LICENSING.md](LICENSING.md).

Put `SPDX-License-Identifier: GPL-3.0-only` in an appropriate comment in new
project-owned source files. Preserve existing author, copyright, license, and
provenance notices. Do not add that identifier to unchanged vendor files or to
screenshots containing third-party artwork. For modified files, keep their Git
history and document material changes; never represent imported work as original.

For an external component, record its origin, exact revision, license, and any
required notices before inclusion. Keep its license with distributed copies and
update the pinned manifest through the established dependency process. A project
license label is not permission to relicense third-party work.

Submit the preferred editable source for artwork and generated data, together
with its generation scripts, inputs, and instructions. Record asset provenance
and distinguish original project art from game screenshots. Do not commit private
signing keys, credentials, or private activation material.

Before proposing a release, run the repository checks and the packaging checks:

```sh
python3 scripts/package.py --write-source-companion
python3 scripts/package.py --check-source-companion
python3 scripts/test_package.py
```

Regeneration copies the legal notices as well as the companion TOC. Include those
generated files in the same change. [SOURCE.md](SOURCE.md) describes the exact
source reference required for a future release; passing local checks does not
publish or authorize one.
