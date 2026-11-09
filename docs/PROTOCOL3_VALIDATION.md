# Protocol 3 validation record

Reviewed candidate: protocol 3, based on `bb0393d`, 2026-11-09, intended for
9.0.0. During validation the TOC remains 8.4.0; it does not identify the
published 8.4.0 package. Publication status is separate from these offline results.

## Complete Lua suites

The complete addon suite runs with normal and reversed registration order.
The `live` modes exercise the in-game test selection offline; they are not
live-client validation. Expensive network and stress cases remain in the full
normal/reverse suites.

| Interpreter | Normal | Reverse | Live selection | Reversed live selection |
| --- | --- | --- | --- | --- |
| Lua 5.1 | 1,532 / 0 (202.02 s) | 1,532 / 0 (201.93 s) | 1,428 / 0 (6.32 s) | 1,428 / 0 (6.42 s) |
| Lua 5.2 | 1,532 / 0 (124.08 s) | 1,532 / 0 (123.73 s) | 1,428 / 0 (5.62 s) | 1,428 / 0 (5.47 s) |

Cells show passed / failed and host elapsed time. Each live-selection run
passed 1,428 cases and skipped 104 offline-only cases. The live-selection runs are
still offline; actual in-game test responsiveness needs a separate live check.
The final commands and logs are in `/tmp/qt-protocol3-review/frozen-lua51/` and
`/tmp/qt-protocol3-review/frozen-lua52/`.

The first review matrix passed Lua 5.1 normal/reverse and Lua 5.2 reverse, but
Lua 5.2 normal exposed a VIP renewal failure. Investigation found a lost replay
interest while the publication was in flight and unfair selection between
simultaneous global/zone queries. Both were corrected without extending credential
expiry or weakening the delivery assertions. The original 400-second continuity
scenario also passed five fresh processes with seeds 1, 3, 5, 7 and 11.

## Independent client, identity and presentation checks

Every check in this table passed under both Lua 5.1 and Lua 5.2 (46 successful
command invocations). Client-profile checks use guarded native API fixtures;
they do not establish delivery or taint behavior inside the actual game.

| Gate | Result per interpreter |
| --- | --- |
| Ed25519 / SHA-512 OpenSSL interoperability | 11 cases passed |
| Settings smoke | Passed |
| Binding smoke | 6 actions passed |
| Client contracts: Retail, Forever, Era, TBC, Mists, Titan | 6 profiles passed |
| Native location contracts: Retail, Forever | 2 profiles passed |
| Presentation: enGB, deDE, frFR, esES, esMX, ptBR, ruRU, itIT, koKR, zhCN, zhTW | 121 assertions across 11 locales passed |
| VIP service, disposable test keys and local test environment | 7 tests passed |

Exact commands, timings and logs are recorded in
`/tmp/qt-protocol3-review/independent/lua51.json`, `lua52.json`, and
`crypto-recheck.json` in the same directory. The first crypto invocation lacked
OpenSSL in PATH; both reruns with the installed binary passed. Crypto and VIP checks used
disposable keys; no real identity credential or external service was changed.

## Static, localization and packaging gates

All 22 final static/Python commands passed, including release-history and generated
note checks, localization, changelog generation, release-authoring tests, Discord
changelog tests, package tests, architecture ownership, numeric fixture checks,
the exact pinned libchev vendor check, shell syntax and `git diff --check`.

- 954 source strings verified in all 10 translated UI catalogs.
- Architecture and live load order verified across 158 modules.
- Live numeric fixtures verified across 62 test modules; 4 numeric-check tests passed.
- All 164 Lua files found by the repository file inventory parsed with both
  Lua 5.1 and Lua 5.2 compilers.
- Vendored libchev 1.3.1 matches revision `24b06469b4246f8d413fabaa8313de7facadbac0`.
  No dependency was added or upgraded.

Final static results: `/tmp/qt-protocol3-review/static/results.json`; syntax
results: `/tmp/qt-protocol3-review/syntax.json`. The reviewed POT change removed
one obsolete localization audit entry for its former TOOLTIP strata. The final
localization check passed. Expected invalid-input errors printed by Python test
fixtures are distinct from their successful process exit status.

The reviewed working-tree package contains 831 verified files:

- Path: `.local/protocol3/QuestTogether-protocol3-reviewed.zip`
- SHA-256: `a6caa291f2b90a19f5864522edf17e1a1040f4eeb8c7d9b8dc31f855cf160dc7`
- Per-file hashes are included in `package-manifest.json`; `sourceCommit` is null
  for this working-tree preview. The displayed version remains 8.4.0.
- A release must be rebuilt from its exact committed tag with reviewed 9.0.0
  notes. This preview has not been uploaded to a release service.

## Network contracts and performance

The retained regressions exercise actual coordinators, frame-rounded runtime
updates, asynchronous directory loading, independent backing realms and native
acceptance separately from remote receipt. They cover authenticated multi-hop
payloads, alternate paths, disconnected islands, malformed/forged data, scoped
confirmations, private-data exclusion, ordering, withdrawal, ignore and lifecycle
cancellation, loss/duplicates/reordering, stale callbacks, bounded queues and
completion callbacks.

The final 200-client, 180-second benchmark passed every asserted resource bound.
All 200 clients acquired a confirmed neighbor; 199 received a visible remote
location within that window. One had not, and is excluded from latency
percentiles. This is progressive coverage, not a universal discovery guarantee.
See [PROTOCOL3_BENCHMARKS.md](PROTOCOL3_BENCHMARKS.md) for hashing, traffic,
queueing, authentication, assembly, memory and per-frame CPU measurements and
their limitations.

Five full 30-quest party logs and a 31,200-byte diagnostic report complete while
movement continues at 5 and 60 FPS. The final mixed-load assertion checks the
original location sample is less than 10 seconds old, rather than treating a
late receipt as fresh data. Both interpreters passed the focused load tests.

Final review corrected and retained regressions for three scheduler hazards:
small mesh control packets consuming credit needed by larger mesh packets;
rotating mesh destinations repeatedly preceding replaced party state; and small
private packets starving larger private transfers at high frame rates. Both mesh
and shared schedulers now reserve the selected ready turn's byte credit. Private
work proceeds while the mesh sub-budget refills. Discovery tests also require
20–30-second probe spacing after the first three staggered probes and rotating
roster coverage beyond row 1,500.

The malformed-frame tests use generation 3 for invalid fields and explicitly
reject otherwise valid older-generation frames. Developer announcement duplicate
coverage waits for the exact authenticated announcement within its catalog
lifetime and checks both native paths and exactly one applied announcement.
It no longer assumes an unrelated mesh fragment proves delivery within 10 seconds.

## Findings corrected in the review

- Subscription admission now matches the publication scope to the actual lease.
  Neighbor slots are reserved during reciprocal admission; a full peer declines
  rather than acknowledging a connection it cannot retain.
- Directory-selection cleanup survives combat and graph reset, re-resolves
  display indices, and yields to intervening user selection.
- Unconfirmed discovery/authentication requests cannot occupy every mesh assembly
  slot. Other public assemblies require a confirmed edge or correlated reply.
  Multipart mesh responses retain their original request deadline.
- An unauthenticated forged relay cannot block the genuine owner's direct copy.
  Retired bundles release hash/authentication references and cancel their own hop
  work. Cancellation and reentrant producer/completion callbacks cannot recreate
  work in a retired lifetime or strand a completion callback.
- Retained developer advertisements lose replay eligibility when local developer
  authorization ends. Public request cancellation also retires its publication.
- Pending interests wait for publications to become replayable. Global and zone
  query branches rotate independently in bounded, expiring history; exhausted-hop
  queries do not consume a forwarding turn.
- POT stays on the ordinary HUD layer. The maintainer confirmed live that other
  windows and item tooltips now cover it correctly. This is a UI result, not a
  protocol-3 delivery test.

## Reproduction

For each available Lua 5.1/5.2 interpreter, run:

```sh
lua scripts/test.lua . normal
lua scripts/test.lua . reverse
lua scripts/test.lua . live
lua scripts/test.lua . live-reverse
python3 scripts/test_developer_crypto.py lua
lua scripts/settings_smoke.lua
python3 scripts/bindings_smoke.py lua
lua scripts/benchmark_mesh_hash.lua
```

The complete CI command list, including locale and client-profile loops, is in
`.github/workflows/test.yml`. Build this working tree without `--ref HEAD` until
it is committed; the packager otherwise intentionally builds the old commit.

## Remaining release gate

**No live Retail or Forever network result has been recorded for this candidate.**
Use [COMMUNICATION_LIVE_TESTS.md](COMMUNICATION_LIVE_TESTS.md) to record real remote
receipts, directory availability and selection behavior, a three-client
introduction/relay path, cross-backing-realm addressing, privacy cancellation,
party synchronization and coexistence with active addons on both clients.
Offline success cannot replace these checks. The original plan gates publication
on them; any explicit maintainer decision to release without them must be recorded
as a release-risk decision, not a passing test result.

On 2026-11-09 the maintainer explicitly authorized: "Publish 9.0.0 now; live
network tests remain pending." This resolves the publication gate for 9.0.0
without marking any live network scenario as tested or passed. POT layering is
the separately confirmed live UI result above.
