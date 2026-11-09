# Protocol 3 mesh: live-client release gate

This checklist tracks live validation for the major communication upgrade.
Unchecked scenarios remain unverified. Offline Lua tests establish protocol and
state-machine behavior; they do not establish Blizzard directory availability and whisper delivery, native
throttling, cross-addon behavior, or live UI performance.

Keep the development TOC and notes version unchanged until the authorized release
step. Record the exact candidate commit/package hash, game client build, locale,
realm, installed addons, date, tester, and result for every run. Test Retail and
Forever separately wherever this release is offered. Do not mark an unavailable
client or scenario as passed.

## Setup and evidence

- [ ] Install the same candidate on three clients, A, B and C. Keep a fourth client
  on the last published version to verify the intentional protocol break.
- [ ] Use ordinary player profiles on A and B. Start with public location sharing
  enabled and the map filter set to all QuestTogether players. Check LFQP-only
  filtering separately; it must not be mistaken for missing communication.
- [ ] Record Lua errors and addon communication diagnostics before and after each
  scenario. Save relevant timestamps and screenshots. Redact player names and
  diagnostic contents before sharing evidence beyond the test participants.
- [ ] Run `/qt test`. Confirm progress advances while movement and ordinary addon
  activity continue, and the run ends with a complete summary without a script
  timeout. The report counts expensive offline-only cases separately; the full
  offline suite still runs those stress and matrix checks.
- [ ] Run first with the minimum required addons, then with the normal addon set,
  including other active communication addons and Questie where supported. Keep
  native chat, party invitations, quest sharing, map controls, and ordinary addon
  menus working. Do not replace native APIs or add test hooks on live clients.

## Compatibility, discovery and relaying

- [ ] Record actual remote receipts, not merely accepted send counts. Inspect
  directory availability separately from payload delivery. Confirm no outgoing
  addon packet uses CHANNEL, and old prefixes cause no reply or state change.
- [ ] Put A and C in independent backing realms with overlapping membership
  through B. Confirm A learns C's address through B, then receives C's immutable
  public data via B after direct native-origin authentication. Record the actual
  origin, hop and receipt evidence locally; redact names from shared reports.
- [ ] Repeat in Retail and Forever. Directory visibility, cross-backing-realm
  whisper addressing and actual addon receipt must each be verified.
- [ ] Remove a bridge while an alternate path exists; confirm recovery. Repeat
  without an alternate path and confirm honest isolation and bounded retries.
- [ ] Open the channel UI while a roster scan is pending. Confirm QT preserves
  the user's selection, does not continually select directories, and resumes
  later. Test delayed roster loading and absent directory services.
- [ ] Move A and B between zones and view another zone for four seconds. Confirm
  current/viewed interests replace obsolete ones, old directory memberships leave,
  and background discovery remains slower. Rapid map changes must not cause a
  join or query storm.
- [ ] Inspect the native send counters while other communication addons are
  active. Record mesh bytes/packets, hash slices, authentication latency, queue
  age, expiry and drops. Mesh and private traffic must share the transport cap.
- [ ] Move nearby, stop, and change zones. Confirm prompt direct nearby updates
  and finite stream leases. New discoveries must not refresh old coordinates.
- [ ] Sign out the publication's origin before a new recipient can authenticate
  an ordinary relayed record. Confirm it remains unavailable until verified or
  expired. Previously verified exact records retain their original expiry.

## Party activity and large replies

- [ ] Join A and B into a party. Open and refresh the Party Quest Log, expand
  objectives, change quest focus, follow the other player's focus, and stop
  following. Each action should reach the intended current party.
- [ ] Repeat with a large, varied quest log and several expanded objectives.
  During the transfer, produce ordinary quest updates and move nearby. Confirm
  other activity keeps making progress and the completed log is coherent rather
  than a mixture of two snapshots. Record transfer duration and queue diagnostics.
- [ ] Change a quest or complete an objective while a log refresh is pending, then
  refresh again. Confirm the newer result wins. A repeated unchanged response
  must not certify an empty or obsolete local baseline.
- [ ] Hover a newly discovered player to request details. Confirm identity, party,
  and questing-partner information fills in without inventing coordinates or
  changing that player's location-sharing permission.
- [ ] Leave or change parties during a pending transfer, focus update, join
  request, or quest-share request. Old work must not reach the new party or reopen
  a retired request. Party members should use WoW's native map/minimap dots without
  duplicate QuestTogether dots.

## Freshness, privacy, and lifecycle

- [ ] Turn B's public location sharing off while B has queued traffic. A's public
  dot should withdraw once the withdrawal arrives. No queued old coordinates may
  bring it back. Other public features must continue working as configured.
- [ ] Toggle sharing off/on/off and repeat during a large transfer. Confirm the
  final setting wins. A later-received older sample must not replace a newer
  position or withdrawal, and arrival time must not renew the sample's age.
- [ ] Ignore B on A, then remove the ignore. Confirm ignored messages do not update
  dots or metadata; fresh permitted traffic can restore them after unignoring.
  Request the Party Quest Log again and verify its contents rather than just its
  reported revision.
- [ ] Log B out normally. Observe whether A receives the best-effort departure
  and removes B promptly. Repeat a loading-screen transition and a reload; after
  returning, B should publish fresh presence and become available for normal
  interaction without waiting for old cooldowns.
- [ ] Test a disconnect without a final message. A must eventually remove the old
  public dot at its source-based expiry (normally up to 600 seconds), even if
  unrelated quest activity was received earlier. A failed final send is not itself
  a defect; failure to expire is.
- [ ] Disable and re-enable QuestTogether, and switch profiles with traffic queued.
  Retired requests, transfers, and locations must not leak into the replacement
  runtime. The current profile's sharing and display choices must be respected.

## Congestion and recovery

- [ ] With a verified VIP visible as a star, take the observing client through a
  loading screen and return before the proof expires. The star should remain
  available without waiting for a fresh VIP broadcast. Repeat with a real VIP
  departure, cosmetic withdrawal and expired proof; those must still remove it.
- [ ] Observe multiple VIPs through several renewal cycles, including alongside
  ordinary location and quest updates. Capture `comms.vip` queue/capacity and
  authentication counters if a star becomes a normal dot. Do not extend proof
  expiry or treat unrelated public traffic as authentication.
- [ ] On a developer observer, confirm a transient unavailable diagnostic
  position does not remove an otherwise valid public dot. Location opt-out must
  still withdraw public coordinates, and unavailable samples cannot renew them.

- [ ] Exercise a busy area and concurrent ordinary addon traffic. Confirm queued
  work progresses without flooding retries, Lua errors, or sustained UI stalls.
  If native throttling occurs, capture it and verify paced recovery after the
  contention subsides. Do not deliberately spam public channels to manufacture it.
- [ ] Use the offline network suite for deterministic loss, duplication,
  reordering, native rejection, and retry-budget coverage. In a controlled live
  test where delayed or incomplete replies occur naturally, confirm missing
  pieces recover without repeating the underlying action or rebuilding a
  different snapshot. Record a live case as unexercised if no such condition
  occurred; do not claim the offline simulation proves live recovery.
- [ ] If a native submission is reported as ambiguous during a fragmented
  message, the unsent remainder should still progress without replaying that
  fragment. Completion must remain ambiguous even if the receiver assembles it.
- [ ] After quieting the workload, verify expired/superseded work is cleared and
  new control actions are not stuck behind obsolete bulk transfers. There is no
  hard delivery deadline for every participant in a crowded global channel.

## Authorized diagnostics only

Run these checks only with participating testers who have agreed to diagnostic
sharing and with the maintainer's existing signed-request tooling. Use an ordinary
observer as well as the authorized maintainer so private/public state can be
distinguished. Do not publish private keys or diagnostic report contents.

- [ ] An authorized request produces a small initial reply before a large report.
  Ordinary quest/party traffic keeps progressing during the report transfer.
  Only the intended maintainer receives the diagnostic response.
- [ ] With public sharing on, an accepted diagnostic location refresh updates the
  normal public snapshot using its original sample time and normal ordering rules.
  With public sharing off, any permitted diagnostic coordinates remain private
  and short-lived; they do not enter the public location cache or get rebroadcast.
- [ ] With diagnostics enabled and public location sharing disabled, sign in
  before and after the developer. Without `/qt ping` or `devlogall`, confirm the
  developer sees the private dot, movement refreshes it, and stationary players
  remain visible beyond two minutes. An ordinary observer must not see the dot.
  Turning public sharing back on must remove the hidden-location styling.
- [ ] Turn diagnostic sharing off while verification, a delayed reply, or report
  delivery is pending. No further diagnostic data from that work should be sent.
  Ordinary public behavior continues according to its separate settings.
- [ ] Where a reply is naturally late or an approved test setup can delay it,
  verify a still-correlated late pong is handled once. Fresh permitted data may
  refresh a normal snapshot; expired samples, prior withdrawals, ignored players,
  cancelled requests, and retired world generations must still be respected.
  A late report must not reopen an expired diagnostic window. Do not disable
  privacy or authenticity checks to make this scenario easier to exercise.

## Sign-off

Attach results to the candidate commit. Include failed and unexercised scenarios,
actual latency observations, native throttle evidence if available, and any client
that was not tested. Complete required live scenarios or explicitly resolve their
release risk before publication. A green offline suite or an unchecked checklist
is not live-client sign-off.

## Evidence recorded during implementation

- 2026-11-09, protocol-3 candidate: the maintainer confirmed that character/item
  UI covers POT correctly after the layering correction ("Covered correctly").
  This establishes the reported UI fix only. No protocol-3 multi-client Retail
  or Forever delivery result has been recorded; those release gates remain open.
- 2026-10-11: the user reported Forever startup failing on a millisecond session
  timestamp passed to `%d`. After the fixed-point formatter change, the user
  confirmed another `/reload` succeeds. This verifies the reported startup path
  only; client build and full addon inventory were not recorded for that check.
- All multi-client delivery and coexistence scenarios above remain pending. A
  successful reload does not substitute for those release gates.
- 2026-10-11: the user's Forever 1.60.1 build 70338 (interface 16001, enUS)
  reported `script ran too long` in the synchronous LibChev test runner. The
  replacement schedules whole isolated cases between frames and excludes
  explicitly marked heavy stress/matrix cases from live runs. The user's next
  report completed all 1,276 selected tests (1,266 passed, 10 failed). Eight
  failures came from populated phase state being replaced with an invalid empty
  table in test isolation; two came from live fixtures constructing NaN by
  division by zero. The corrected fixtures detach structured stores completely
  and keep NaN construction in the offline harness.
- 2026-10-11: the user reran `/qt test` on Forever 1.60.1 build 70338
  (interface 16001, enUS), with QuestTogether 6.5.11 and LibChev 1.3.0. The
  report finished with `status=complete`: 1,277 passed, 0 failed, 57 offline-only
  checks skipped. This confirms the corrected in-game suite completes without
  the reported failures. Responsiveness and multi-client communication were not
  measured by this report and remain separate checks.
- 2026-10-11: after the successful in-game suite, the maintainer explicitly
  authorized publication as a major release. Publish 7.0.0 with the protocol
  incompatibility and pre-WoW Forever timing prominently documented. This
  authorization permits release with the multi-client scenarios still pending;
  it does not mark them tested or passed.
