# Protocol 3 offline benchmark observations

These are measurements from the uncommitted protocol 3 implementation on
2026-11-09. The final review candidate below includes scoped owner confirmations,
retained immutable source proofs, shared and mesh transport fairness, sustained
directory-probe pacing, independent rotation of interest scopes, and replay of
publications whose initial forwarding is still pending. Earlier runs, including
the pre-review baseline, document the implementation while it was changing.
They establish fixture behavior and resource bounds. They do not prove
live Forever/Retail delivery, cross-realm addressing, or coexistence with other
addons. Real clients remain the release gate.

## Crowded startup

The retained offline case is
`mesh two hundred simultaneous clients retain bounded progressive discovery` in
`scripts/regression_network_v2.lua`, using `scripts/network_fixture.lua` and actual
RuntimeCoordinator, geographic producers, mesh discovery, publication hashing,
transport, and receiver code. No hashes, neighbor confirmations, or public
observations are substituted.

- 200 independent clients start simultaneously, without a party.
- Four backing realms share overlapping, incomplete directories. Each client
  sees itself and eight addresses, using ring offsets -3, -2, -1, 1, 2, 3, 17,
  and 53. Directory entries confer no trust.
- All clients are in geographic map 12. Five move every five simulated seconds.
- Frame rate is 5 FPS, network latency 80 ms, channel join delay 300 ms, and
  directory roster load delay 500 ms. Random seed is 1537.
- Links are reachable and lossless. Native acceptance and asynchronous delivery
  remain separate. Directory channel payload sends are forbidden by assertions.
- Each client's mesh traffic must remain within 200 bytes/second plus a
  400-byte burst and one packet/second plus a two-packet burst, inside the shared
  transport budget. The test checks every simulated second.
- Each client is bounded to eight neighbors, 512 candidates, three pending
  handshakes, 32 forwarded interests, a 96-packet total queue, and 128 KiB of
  retained publications.

### Earlier working-tree runs

| Measurement | 60-second run | 180-second run |
| --- | ---: | ---: |
| Clients with a confirmed neighbor | 200 / 200 | 200 / 200 |
| Clients that received at least one visible remote location | 22 / 200 | 198 / 200 |
| Median time to first visible remote location, among successful clients | 28 s | 65 s |
| Slowest first visible remote location, among successful clients | 60 s | 168 s |
| Native accepted packets | 8,119 | 29,772 |
| Network delivered packets | 8,012 | 29,731 |
| Highest per-client native queue | 24 packets | 24 packets |
| Highest per-client retained publication bytes | 6,276 B | 13,302 B |
| Host CPU time for entire simulation | 29.00 s | 94.95 s |
| Host wall time for entire simulation | 29.16 s | 95.50 s |

Both runs passed all asserted resource budgets and made zero native CHANNEL
payload sends. Accepted versus delivered counts differ because the measurement
ends with packets still in flight; acceptance alone is not counted as delivery.

The longer run used the same case and setup, changing only its duration from 60
to 180 simulated seconds. The intervening implementation reduced interest fanout;
these runs are observations of the evolving working tree, not a controlled
before/after performance comparison. The 60-second case remains in the suite so
routine checks do not always pay the longer simulation cost.

The 60-second process peaked at 244,032 KiB RSS. The 180-second process peaked at 370,208 KiB RSS. These figures include 200 complete
private clients, the Lua test runner, and retained network traces. It is not the
memory footprint of one installed addon. Per-client publication retention and
native queue counts are measured separately above.

The first-visible percentiles exclude clients that had not received a location
by the end of that run. They describe the first remote location, not discovery of
every player. Crowded cold starts can take one to three minutes at these
conservative limits. No hard zone-wide response count or complete discovery is
promised.

Raw local run logs:

- `/tmp/qt-crowd-benchmark.log`
- `/tmp/qt-crowd-benchmark180.log`

### Earlier scoped-retention candidate: 180 seconds

The same setup was rerun after the scoped publication/confirmation fix and the
immutable outbox changes, against the then-current working tree based on commit
`bb0393d`. This run preceded the stable outer mesh-flow fix, shared byte-credit
fairness, and sustained 20–30 second probe cadence. The private runner extended the retained test to 180 seconds and added
measurement wrappers. Production code and fixture behavior were unchanged.

| Measurement | Result |
| --- | ---: |
| Clients with a confirmed neighbor | 200 / 200 |
| Clients that received at least one visible remote location | 198 / 200 |
| Median time to first visible location, among successful clients | 66 s |
| 90th / 95th percentile first visible location | 103 s / 116 s |
| Slowest first visible location, among successful clients | 169 s |
| Native accepted / network delivered packets | 29,465 / 29,422 |
| Native accepted payload bytes, across all clients | 4,461,549 B |
| Highest per-client native queue | 24 packets |
| Highest per-client queued bytes, sampled once per simulated second | 4,850 B |
| Highest per-client retained publication bytes | 16,373 B |
| Longest publication authentication interval | 73.8 s |
| Longest transfer assembly interval | 62.8 s |
| Longest native queue wait | 93.4 s |
| Largest measured per-client frame CPU | 11.601 ms |
| Host user / system CPU, entire simulation | 95.591 s / 0.182 s |
| Host wall time, entire simulation | 96.011 s |
| Host peak RSS, entire simulation | 385,684 KiB |

All per-client budget and capacity assertions passed, with zero native CHANNEL
payload sends. The two clients without a first visible location are excluded
from the reported percentiles. Connecting to the mesh is substantially quicker
than discovering all relevant public state; even this reachable, lossless cold
start does not guarantee every client sees a location within three minutes.

The authentication interval begins after a complete publication reaches a
receiver and includes its hash work, authentication queueing and direct origin
confirmation. Assembly and native queue waits are measured separately. A delayed
confirmation preserves the original source timestamp; it does not make an old
coordinate fresh. These maxima can describe different messages and should not
be added together as one delivery latency.

Per-client frame CPU combines that client's runtime callback and incoming message
handlers during one simulated frame. It excludes fixture timer dispatch and
setup. The peak can include Lua garbage collection shared by the 200-client host
process; it is not a prediction of one installed addon's frame cost. Likewise,
RSS includes all private clients, the test runner and retained network traces.

Raw local evidence is `/tmp/qt-final-benchmark180.log`; the private measurement
runner is `/tmp/qt-final-benchmark180.lua` with the instrumented test copy at
`/tmp/qt-final-benchmark-case.lua`. No measurement prints or wrappers were added
to production modules or the retained test.

### Pre-review baseline: 180 seconds

At the freeze before the additional code review, the same 200-client setup was
rerun with sustained 20–30 second probes after the first three staggered attempts,
rotating directory sampling, stable outer mesh-flow scheduling, and shared
byte-credit fairness. This baseline predates the admission, scope validation,
interest selection and pending-publication replay corrections described below.

| Measurement | Result |
| --- | ---: |
| Clients with a confirmed neighbor | 200 / 200 |
| Clients that received at least one visible remote location | 194 / 200 |
| Median time to first visible location, among successful clients | 64 s |
| 90th / 95th percentile first visible location | 111 s / 135 s |
| Slowest first visible location, among successful clients | 162 s |
| Native accepted / network delivered packets | 23,020 / 22,991 |
| Native accepted payload bytes, across all clients | 3,582,859 B |
| Highest per-client native queue | 24 packets |
| Highest per-client queued bytes, sampled once per simulated second | 4,844 B |
| Highest per-client retained publication bytes | 14,755 B |
| Longest publication authentication interval | 32.0 s |
| Longest transfer assembly interval | 63.8 s |
| Longest native queue wait | 39.8 s |
| Largest measured per-client frame CPU | 27.000 ms |
| Host user / system CPU, entire simulation | 81.306 s / 0.162 s |
| Host wall time, entire simulation | 81.672 s |
| Host peak RSS, entire simulation | 320,276 KiB |

All budget and capacity assertions passed, and no native CHANNEL payload was
sent. Six clients had no first visible remote location within 180 seconds;
they are excluded from the latency percentiles. The lower successful-client
count also means the maximum latency cannot be read as an improvement over the
previous run. The mesh remains progressive and best effort under these bounds.

The measurement definitions and host-process caveats above also apply here.
In particular, the 27 ms frame maximum includes any shared Lua garbage collection
charged during that client's callback in a process containing 200 clients and
all network traces. It is not an observed in-game frame hitch or a one-client
performance estimate. Production changes to several pacing and fairness paths
prevent attributing differences between runs to any single change.

Raw pre-review evidence: `/tmp/qt-frozen-benchmark180.log`. The private runner and test
copy remain `/tmp/qt-final-benchmark180.lua` and
`/tmp/qt-final-benchmark-case.lua`; both were regenerated from the frozen source
before this run. No instrumentation was added to repository production files.

### Final review candidate: 180 seconds

The same lossless 200-client scenario was rerun on Lua 5.2 after the review fixes.
Neighbor admission now reserves bounded capacity before acknowledging a new
connection, and publication routes must match the actual interest scope.
Interest forwarding rotates branches independently for each destination and
scope, so simultaneous global and zone renewals cannot repeatedly exclude the
same neighbor. This selection history is capped and expires; fanout, probe
cadence and traffic budgets were not increased.

A new interest also remains eligible for replay while the current owned
publication is being verified or forwarded. Previously, finding no completed
publication could discard that interest's replay job before the publication
became available. These changes were accompanied by focused regressions and VIP
renewal checks; the crowded benchmark below measures public discovery rather
than VIP renewal continuity.

| Measurement | Result |
| --- | ---: |
| Clients with a confirmed neighbor | 200 / 200 |
| Clients that received at least one visible remote location | 199 / 200 |
| Median time to first visible location, among successful clients | 68 s |
| 90th / 95th percentile first visible location | 87 s / 92 s |
| Slowest first visible location, among successful clients | 122 s |
| Native accepted / network delivered packets | 26,155 / 26,119 |
| Native accepted encoded payload bytes, across all clients | 4,207,357 B |
| Network delivered encoded payload bytes, across all clients | 4,201,710 B |
| Highest per-client native queue | 22 packets |
| Highest per-client queued bytes, sampled once per simulated second | 4,585 B |
| Highest per-client retained publication bytes | 16,364 B |
| Longest publication authentication interval | 63.4 s |
| Longest transfer assembly interval | 76.6 s |
| Longest native queue wait | 54.6 s |
| Largest measured per-client frame CPU | 12.744 ms |
| Directed neighbor edges at the final sample | 1,326 |
| Directed neighbor edges with a reciprocal counterpart | 1,170 |
| Host CPU and wall time, entire simulation | Not measured |
| Host peak RSS, entire simulation | Not measured |

All asserted traffic, queue and publication-retention bounds passed, with zero
native CHANNEL payload sends. One client had no visible remote location by the
end of the run and is excluded from the latency percentiles. Those percentiles
measure each client's first accepted remote location, not complete discovery or
freshness of every player's position.

The graph snapshot contains 156 directed edges without a reciprocal counterpart.
Admission and renewal are asynchronous; this snapshot does not establish that
every edge is usable in both directions. It also does not establish connectivity
between clients whose native whispers cannot reach each other.

The authentication, assembly, queue and CPU definitions above still apply.
Their maxima may concern different messages and must not be added together.
The per-client frame CPU measurement includes host Lua garbage collection; it
is not an in-game frame-time measurement. Total host CPU, wall time and peak RSS
were not collected for this final run and must not be inferred from the earlier
baseline. Changes to several routing and recovery paths, along with iteration
and scheduling variation, prevent treating these runs as a controlled
performance comparison. Discovery remains progressive, with no complete-delivery
guarantee; live Forever and Retail validation remains necessary.

Raw final-review evidence: `/tmp/qt-post-fairness-benchmark180.log`, with parsed
measurements in `/tmp/qt-post-review-final-benchmark.json`. The private runner is
`/tmp/qt-post-review-benchmark180.lua` and its instrumented case is
`/tmp/qt-post-review-benchmark-case.lua`. These measurement wrappers were not
added to production modules or the retained regression test.

A subsequent narrow correction prevents an exhausted-hop query from consuming
a branch-selection turn. That alternating terminal/forwardable-query pattern
was checked on Lua 5.1 and 5.2 in the scoped fairness regression; this benchmark
was not rerun for that correction.

## Mixed party and diagnostic traffic

The existing network suite also runs five clients with full 30-quest logs,
continuous movement, a 31,200-byte diagnostic report, and actual frame-rounded
runtime/transport progression at 5 and 60 FPS. It asserts complete atomic quest
logs, exactly one complete report and Pong, fresh movement, and aggregate packet
and byte conservation.

This mixed-load case uses a cooperative verification seam for the diagnostic
signature so it measures scheduling instead of re-testing signature math. Mesh
canonical hashing remains the real implementation. Separate real-key tests cover
identity authorization.

Initial mixed-load runs observed movement data that was roughly 79 to 89 seconds
old while unrelated bulk work progressed. One blocking path was removed: full
metadata and replaceable location publications now use
separate pending slots and keys for both public and group routes. Public creation
or replacement waits at least five seconds, including after failed admission;
party movement retains its one-second cadence. Older baseline completion cannot
replace the scheduler's newer accepted coordinates. The focused coexistence test now passes at both frame rates, alongside the
revoked-coordinate and navigation-duplication cases (3 / 3 in
`/tmp/qt-mesh-mixed-tests4.log`). An earlier independently instrumented local run observed
report completion at 162 simulated seconds at 5 FPS and 189 seconds at 60 FPS;
the latest movement was 0.2 and 0.7 seconds old, respectively. The temporary
instrumentation was never added to the repository. These are observed outcomes
of that earlier working tree; concurrent identity and scheduler changes prevent
attributing the improvement to one isolated edit. The other selected Comms,
geographic, and announcement suites passed 180 / 180 in
`/tmp/qt-owned-migration5.log`.

The final mixed-load gate now checks the accepted location's original sample
age, rather than only the time since receipt. A late old publication cannot pass
by arriving recently. It retains the ten-second source-freshness limit, complete
five-player quest logs, exactly-once diagnostic completion, and conserved shared
budgets. This test plus transport checks passed 30 / 30 on both Lua 5.1 and 5.2
in `/tmp/qt-final-fair-source51.log` and `/tmp/qt-final-fair-source52.log`.

The final scheduler gives the public sub-budget a stable turn within the shared
scheduler while rotating public destinations inside that turn. Otherwise, a new
public destination can reset outer flow ordering ahead of replaceable party
movement. A deterministic regression fails the previous ordering and passes the
fix. Another regression verifies that large private packets can accumulate byte
credit while smaller traffic remains busy, at 1, 5, and 60 FPS.

## Canonical hashing CPU

Run `lua scripts/benchmark_mesh_hash.lua` from the repository root. This uses
five repetitions per size, the bundled SHA-512 implementation, and the same
16-step cooperative slices as the publication worker. Hash outputs are checked
for their expected 64-byte length; separate OpenSSL interoperability tests check
cryptographic correctness.

| Input | Lua 5.2 mean CPU | Lua 5.2 largest slice | Lua 5.1 mean CPU | Lua 5.1 largest slice |
| --- | ---: | ---: | ---: | ---: |
| 256 bytes | 1.29 ms | 0.111 ms | 10.63 ms | 0.765 ms |
| 1,024 bytes | 3.80 ms | 0.155 ms | 33.28 ms | 0.934 ms |
| 8,192 bytes | 27.99 ms | 0.165 ms | 229.97 ms | 0.998 ms |

The local Lua 5.2 interpreter has native `bit32`; the local Lua 5.1 interpreter
has neither `bit` nor `bit32`, so it exercises the much slower arithmetic
fallback. These are host CPU measurements, not claims about the game's CPU or
frame rate. Production checks elapsed CPU between slices, with a one-millisecond
hash-work target per runtime update and a separate hard step limit. A slice can
overshoot that target on a slower machine. The bounded diagnostic counters expose
hash CPU, largest slice, hash queue age, confirmation latency, transfer assembly,
and transport queue time separately.
