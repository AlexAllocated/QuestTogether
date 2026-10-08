# QuestTogether architecture

This is the tracked contract for addon changes. Keep it alongside the code;
private `.local` notes are historical context, not the source of truth.

## Ownership

| Component | Owns | Does not own |
| --- | --- | --- |
| Core / EventHandlers | Native adapters, initialization, event routing, quest lifecycle orchestration | Feature timers, profile effects, live classification caches |
| Settings | Profile storage, migrations, value validation, atomic edits and effect dispatch | Widget construction, native navigation or frame mutation |
| RuntimeCoordinator | The enabled addon's periodic lifetime and feature tick order | Individual feature caches or wire codecs |
| HotPathRuntime | Explicit timing, work classes, owner cancellation and restriction gates | Quest or presentation policy |
| QuestObservations | Quest-log acquisition, confirmed classifications, complete snapshot publication | Area entry/exit history or announcements |
| TaskArea | Reducing observations into world/bonus area state and announcement diffs | Native quest-log/classification reads |
| PeerState | Observation source, sample time, lifetime, field/epoch admission and commit | Domain payloads, private coordinates, presentation |
| PeerLifecycle | Reasons for departure, expiry and ignore retirement; invoking domain hooks | Editing another feature's internal tables |
| Transport | Bounded queue, pacing, backoff, native acceptance, delivery callbacks, world lifetime | Geographic routing or feature authorization decisions |
| BulkTransfer | Response delivery progression, retry budget, deadlines and cancellation | Payload formats, snapshot assembly, diagnostics consent |
| GeographicComms / NearbyStreams | Route subscriptions, geographic codecs and snapshot/movement publication | Generic transport queue or rewriting received feature caches |
| QuestCompare | Atomic party log assembly, local snapshots and negotiated revision reuse | Native UI mutation or independent transport pumps |
| PartyFocusController | Following and manual-choice state machine, missing-quest and confirmation policy | Party networking, persistence policy or preview fixtures |
| PartyNavigation / QuestComparePreview | Live/preview adapters, persistence and ownership of native focus | Copies of the following state machine or repair of another controller's fields |
| OwnedUI | Guarded owned-region access and a durable cleanup queue | Permission to modify Blizzard-owned frames |
| WindowController / WindowLayout / WindowTheme | Window visibility and dismissal, geometry, chrome respectively | Quest-specific dialogs or protocol sessions |
| QuestDialogs | Focus/share-related presentation and callbacks | Window geometry rules |
| PlayerTooltipPresenter | Shared player tooltip content and measurement | Map projection or marker allocation |
| MapOverlayPool | Surface attachment, marker reuse and retirement | Player/waypoint content, route or visibility policy |
| LocationPins / PartyWaypointPins | Domain-specific pin placement, visuals and actions | A second tooltip renderer or marker pool lifecycle |

## Data and time contracts

- A native API wrapper validates foreign values before copying primitive data
  into addon-owned state. Unknown is distinct from explicit `false`, empty and
  removed. A partial quest scan never publishes rows or classification changes.
- `RebuildQuestSnapshotStore` is acquisition. Area refreshes use it at their
  faster cadence; a caller already holding a completed acquisition passes that
  observation into the reducer. Ordinary classification readers do not query
  native APIs. Acceptance, removal and completion may explicitly capture fresh
  classification at their event boundary. Completion captures stay with that
  quest lifetime.
- Each peer field passes an explicit observation through admission and commit.
  Arrival time does not rejuvenate the source's sample time. Public metadata,
  location, nearby movement, party navigation and developer diagnostics keep
  their own TTL and consent rules. Hidden diagnostic coordinates never become
  public location state.
- Schedule work with a deliberate mode: `immediate`, `nextFrame`, `bounded` or
  `debounce`. A next-frame request cannot run inline or be made due by a flush.
  Bounded refreshes retain their original deadline under repeated events.
  Delayed callbacks validate owner, generation, identity and current consent.
  Nameplate identity generations are independent of presentation coalescing.
- A send returning `queued` is admission, not delivery. Only native acceptance
  advances packet progression. Queued work retains an owner/currentness check;
  cancellation, departure, opt-out and world replacement retire it. Nearby
  movement can drop obsolete samples but shares native throttle/backoff.
- PQL revisions certify an exact complete snapshot. They are negotiated;
  unchanged replies reuse only the matching validated baseline. Changed,
  missing, expired or incompatible baselines request full data. Manual Refresh
  is an explicit full refresh. Objective detail remains separately requested.
- Settings validate a whole edit before committing any key. `SetOptions` batches
  related changes and dispatches each affected service once. Profile activation
  uses the same effects, including themes, scale, privacy and navigation; it
  revokes old diagnostic request ownership even when both profiles allow it.

## UI and client boundaries

Never write QT state onto Blizzard frames, children, mixins or shared tables.
Use owned regions, GUID records and weak side tables. Guard foreign reads for
secrecy, accessibility and forbidden state; defer protected mutation until all
applicable restrictions clear. Treat a forbidden frame as quarantined.

Inherited hiding (including Alt+Z) suspends interaction without dismissing the
window's session. Explicit close retires it even if its parent is already hidden.
A region queued for cleanup carries ownership: reuse cancels old cleanup.
Cleanup can outlive addon disable; stale feature work cannot.

Use native settings controls through the shared constructors. Player-facing
text is localized at presentation; wire facts and diagnostic identifiers stay
stable. Vendored LibChev is immutable under its pinned manifest: fixes belong
upstream followed by a deliberate vendor update.

## Validation and delivery

`/qt test` loads private fixtures through the same TOC as the addon. Tests must
never patch Blizzard globals, shared native tables, secure-adjacent APIs or
live frames. UI fixtures model parent visibility, frame reuse and independently
forbidden/protected regions. `scripts/test.lua` alone owns offline engine stubs.

Run Lua 5.1 and 5.2 suites in both orders; settings construction, all locale and
client profiles, crypto, localization, release-note and packaging checks are CI
requirements. `scripts/check_architecture.py` protects key ownership boundaries;
behavioral tests cover cancellation, incomplete observations, replay, recovery
and protocol compatibility. Do not replace those with only source-pattern tests.

`scripts/package.py` derives installed Lua from the TOC and includes only the
explicit runtime asset/document rules. It checks pinned dependency hashes and
verifies every archived payload. Release builds use an immutable `--ref`;
working-tree builds are previews. See [RELEASING.md](RELEASING.md).

Offline success proves these contracts under fixtures. It does not establish
in-client rendering, taint safety, SavedVariables migration with real data,
network delivery or behavior with other addons. Keep those checks explicit.
