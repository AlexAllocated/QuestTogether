# Communication upgrade: live-client release gate

This checklist tracks live validation for the major communication upgrade.
Unchecked scenarios remain unverified. Offline Lua tests establish protocol and
state-machine behavior; they do not establish Blizzard channel delivery, native
throttling, cross-addon behavior, or live UI performance.

Keep the development TOC and notes version unchanged until the authorized release
step. Record the exact candidate commit/package hash, game client build, locale,
realm, installed addons, date, tester, and result for every run. Test Retail and
Forever separately wherever this release is offered. Do not mark an unavailable
client or scenario as passed.

## Setup and evidence

- [ ] Install the same candidate on two clients, A and B. Keep a third client, C,
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

## Compatibility and discovery

- [ ] A and B discover each other and exchange quest progress. C does not exchange
  QuestTogether data with them in either direction. Old traffic causes no reply
  loop or Lua error; ordinary WoW chat and party functions still work with C.
- [ ] Put A and B in different zones. On A, hold B's zone open on the world map
  for at least four seconds. Confirm A can discover B through that area's channel
  and also continues receiving updates for A's own zone.
- [ ] Pan rapidly between zones, view a continent, close the map, and reopen it.
  Confirm the addon retains at most the current zone plus one settled viewed zone,
  leaves obsolete zone subscriptions, and does not repeatedly issue discovery
  queries for the same zone. The normal dwell and cooldowns are intentional.
- [ ] View a third, unrelated zone and allow normal background traffic to run.
  Confirm more distant public dots still refresh without a manual request.
  The ordinary global publication interval is randomized between 150 and 210
  seconds after an accepted send; congestion can delay it. Record actual times,
  not a promised deadline.
- [ ] Bring A and B within minimap range and move, stop, and change zones. Confirm
  nearby updates remain smooth enough to use, cease when no longer relevant,
  and fall back to ordinary snapshots when a short stream expires. No old
  interpolated position should persist after a newer withdrawal.

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
