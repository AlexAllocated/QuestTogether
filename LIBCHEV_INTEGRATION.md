# Shared runtime integration

QuestTogether embeds a private, pinned copy of [libchev](https://github.com/AlexAllocated/libchev). No separate addon installation is required. The embedded copy's manifest records the exact source revision and file hashes. Another addon's library version cannot replace QT's implementation or share its runtime stores.

The shared library supplies bounded categorized logs, primitive sanitization, diagnostic headers and the copy window, guarded callback execution, weak-key side tables, generation-aware deferred work, assertions, and the test runner. QT continues to own quest snapshots, progress decisions, party/comms identity, nameplate state, restriction policy, SavedVariables, and live-session test isolation.

The deferred-work adapter still checks the current QT store and enabled lifetime. Explicit clicks on old coordinate links can execute while QT is disabled, provided waypoint restrictions permit the action. This exception does not enable background work or bypass restrictions.

## Commands

- `/qt test`: run QT's regressions and the library's safe private-value self-checks. It never loads offline engine mocks.
- `/qt diagnostics`: show the common copy window with client/addon/library versions, QT's cached state, and the newest events that fit its report budget.
- `/qt dump`: retain QT's full searchable debug history, categories, and existing test/debug controls.

Diagnostics use existing addon snapshots. They do not trigger live quest, tooltip or nameplate scans. Logging never recursively dumps foreign objects, and error containment does not establish taint safety.

## Updating the embedded copy

Use the library's `scripts/vendor.py` with an immutable reviewed revision. Do not edit vendored files directly. Preserve the library license and manifest in release packages. Run the vendoring script's check mode, QT's normal and reverse suites, Lua parsing, and TOC validation after updating.

This integration pins libchev v1.0.0 at `09ac76eb6fe8e9589b809188652950c3cd9e444c`. From the QT checkout, verify the embedded files with:

```sh
python3 ../LibChev/scripts/vendor.py . --check
```

## Validation boundary

The integration adds regressions for disabled waypoint clicks, restriction enforcement, stale timers, unavailable timer adapters, and retaining the newest diagnostic history within the common copy window's bound. The 300 existing tests remain, with 10 shared self-checks and 5 integration regressions added.

All 315 tests passed in normal and reverse order under Lua 5.1.5 and Lua 5.2.4. The embedded manifest, Lua syntax, and TOC load order were checked separately. The consumer version is `5.7.6-beta.1` while live validation remains outstanding.

Offline success does not prove live Retail/Forever rendering or taint safety. Before a stable release, run `/qt test` and `/qt diagnostics` in each available client; inspect quests, progress bubbles, nameplates and coordinate links across combat, zoning, disable/re-enable and reload. Include the ordinary addon set to check coexistence. The earlier Retail confirmation for release 5.7.5 does not validate this extraction.
