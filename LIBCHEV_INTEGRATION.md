# Shared debug and runtime integration

QuestTogether embeds a private, pinned copy of [libchev](https://github.com/AlexAllocated/libchev). No separate addon installation is required. The embedded manifest records the exact source revision and file hashes. Another addon's library version cannot replace QT's implementation or share its stores.

libchev v1.1 owns the complete debug controller and console: bounded categorized logs, safe formatting, fuzzy/quoted search, filtering, batching, metrics, tail following, copy controls, report export, test presentation, and debug command behavior. QT's `Debug.lua` supplies private stores, persisted filter settings, cached quest diagnostics, test isolation, and restriction policy through thin adapters. Console windows and controls are created and guarded by the library. The old QT console, dropdown, scroll helpers, and generic formatting/filter/test-presentation implementations have been removed. Library 1.1.1 restores native WoW panel/button textures on the existing owned controls and emits a single test summary, including the offline harness output.

QT still owns quest snapshots, progress decisions, party/comms identity, nameplate state, restriction decisions, SavedVariables migration, and live-session test isolation. Deferred work, callback guards, assertions and weak-key helpers also come from libchev. Explicit clicks on old coordinate links can execute while QT is disabled if waypoint restrictions permit the action; background work stays paused.

## Commands

- `/qt test`: run isolated tests and open the current results in the common console. Old TEST history is replaced, search is cleared, and TEST is selected unless the user already has a visible ALL view.
- `/qt dump`, `/qt debug`, `/qtd`: open the common log view with category selection, fuzzy/quoted search, select/copy, clear, reload, tests, and diagnostics controls.
- `/qt dump clear`: clear logs and reset filters. `/qt dump CATEGORY` selects a category.
- `/qt diagnostics [questID]` or `/qt diag [questID]`: rebuild the cached domain report and show it with the newest events in the same console.

Programmatic `QuestTogether:RunTests(reverse, present)` is headless by default. The offline harness uses this same controller path with `present=false`; it does not rewrite test source or expose local isolation helpers globally. Interactive commands request presentation explicitly. A failed case restores QT's original controller and private state. No test patches Blizzard globals or constructs a live frame for a fixture.

The shared console checks restrictions and owned-region mutability before UI actions. A blocked open falls back to chat. Diagnostics read existing addon snapshots without live quest, tooltip, or nameplate scans. Logs never recursively dump foreign objects; callback error containment does not establish taint safety.

## Updating the embedded copy

Use the library's `scripts/vendor.py` with an immutable reviewed revision. Do not edit vendored files directly. Preserve its license and manifest in packages. From sibling `QuestTogether` and `LibChev` checkouts, verify with:

```sh
python3 ../LibChev/scripts/vendor.py . --check
```

Version `5.7.6-beta.3` pins libchev `1.1.1` at `2feea04bab60ba1c1b91bd01ab8a58ce02e091a9`.

Run normal and reverse suites under Lua 5.1 and 5.2, Lua parsing, TOC validation, and package checks after updating. Offline mocks remain excluded from the TOC.

## Validation boundary

The common-console migration adds consumer regressions for current test-result presentation, ALL-view preservation, debug command filters/clear, headless nonmutation, failed-case controller restoration, and fresh diagnostic command reports. The library also supplies pure controller self-checks.

All 324 cases pass in normal and reverse order under actual Lua 5.1.5 and Lua 5.2.4. All 23 Lua files parse under both versions; all 22 TOC entries are unique, present, and ordered correctly; the embedded revision/hash manifest verifies.

The user reported all 324 tests passing in Forever 1.60.1 build 70009 with QT `5.7.6-beta.2`. This confirms test execution in that session; it does not establish every UI/restriction path or validate subsequent library revisions. A source audit of all seven TOC-loaded test files found no NaN generation, division, exponentiation, or invalid math-domain fixtures. The only modulo checks use a fixed divisor of three.

Offline success does not prove live Retail/Forever rendering or taint safety. Before a stable release, run `/qt test` and `/qt diagnostics` in each available client. Exercise select/copy, category/search, scrolling away from and back to the tail, resize, clear, repeated test runs, and switching between report and log modes. Check opening and interacting across restrictions, then quests, progress bubbles, nameplates and coordinate links across combat, zoning, disable/re-enable and reload with the ordinary addon set.
