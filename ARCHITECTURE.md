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
| CommunicationCoordinator | Typed submissions, request correlation, audiences, policy checks, source revisions, cancellation and session fences | Feature consent decisions, native sends, arbitrary serialization |
| CommsProtocol | Operation catalog, bounded schemas, route declarations, envelope and length-prefixed codecs | Feature scheduling loops or domain caches |
| Transport | Single native adapter, bounded queue, fairness, pacing, native outcomes and exactly-once tickets | Geographic policy, remote delivery guarantees or feature authorization |
| CommsTransfer | Shared fragmentation, atomic assembly, bounded repair, retained response replay and aggregate payload budget | Domain snapshot installation or diagnostic consent |
| GeographicComms / NearbyStreams | Current/viewed interests, subscriptions, discovery policy and owned state/movement producers | Another native queue or rewriting received feature caches |
| QuestCompareCommunication / PingCommunication | Domain request premises and response construction | Wire encoding, fragment pumps or independent timers |
| DeveloperAnnouncements | Signed developer subscriptions, diagnostic consent, mirror audiences and bounded feed work | Normal announcement filters, private location access or a separate transport |
| QuestCompare | Atomic party log assembly, local snapshots and negotiated revision reuse | Native UI mutation or independent transport pumps |
| PartyFocusController | Following and manual-choice state machine, missing-quest and confirmation policy | Party networking, persistence policy or preview fixtures |
| PartyNavigation / QuestComparePreview | Live/preview adapters, persistence and ownership of native focus | Copies of the following state machine or repair of another controller's fields |
| Keybindings | Fixed player actions delegated to existing feature operations | Key assignment, binding overrides, native input state |
| OwnedUI | Guarded owned-region access and a durable cleanup queue | Permission to modify Blizzard-owned frames |
| WindowController / WindowLayout / WindowTheme | Window visibility and dismissal, geometry, chrome respectively | Quest-specific dialogs or protocol sessions |
| QuestDetails | Bounded copies of native quest-tooltip text and an owned reader session | Native tooltip mutation, quest selection, or peer requests |
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
  quest lifetime. A complete scan retains departed classification briefly in a
  bounded, completion-only store; it cannot repopulate active state or survive
  reacquisition. Unknown fields may use that evidence, explicit false cannot.
- Each peer field passes an explicit observation through admission and commit.
  Arrival time does not rejuvenate the source's sample time. Public metadata,
  location, nearby movement, party navigation and developer diagnostics keep
  their own TTL and consent rules. Hidden diagnostic coordinates never become
  public location state. Every location-bearing observation preserves its source
  sample time. Missing coordinates are unknown, not a withdrawal. Pongs carry an
  explicit sharing flag; coordinates alone do not establish consent.
- Schedule work with a deliberate mode: `immediate`, `nextFrame`, `bounded` or
  `debounce`. A next-frame request cannot run inline or be made due by a flush.
  Bounded refreshes retain their original deadline under repeated events.
  Delayed callbacks validate owner, generation, identity and current consent.
  Nameplate identity generations are independent of presentation coalescing.
  Support-window maintenance explicitly uses the UI lifetime, which survives
  feature disable and wakes only while work is pending. It retains the same
  restriction and owner checks as enabled-runtime work.
- A send returning `queued` is admission, not delivery. Only native acceptance
  advances packet progression. Queued work retains an owner/currentness check;
  cancellation, departure, opt-out and world replacement retire it. Nearby
  movement can drop obsolete samples but shares native throttle/backoff.
  Action requests also recheck their premise at delivery: a join request still
  needs a solo requester, and a share request needs confirmed quest absence.
- PQL revisions certify an exact complete snapshot. They are negotiated;
  unchanged replies reuse only the matching validated baseline. Changed,
  missing, expired or incompatible baselines request full data. Manual Refresh
  is an explicit full refresh. Objective detail remains separately requested;
  any detail response that changes ownership or summary fields invalidates the
  certified revision before updating the member's displayed entry. Publish and
  retire member entries, revisions and sample times together through the shared
  snapshot helpers; installed entry maps are not mutated in place.
- Settings validate a whole edit before committing any key. `SetOptions` batches
  related changes and dispatches each affected service once. Profile activation
  uses the same effects, including themes, scale, privacy and navigation; it
  revokes old diagnostic request ownership even when both profiles allow it.

## Communication generation 2

The only gameplay prefix is `QuestTogether2`. Existing global and regional chat
channel names remain unchanged. Generation 1 traffic is ignored, with no legacy
decoder, companion packet, capability negotiation or fallback transmission.
Communicating peers must upgrade together. Ed25519 developer requests bind the
native sender, request identity, issue time, target and purpose to `QTDEV2`.
Signatures authenticate requests; they do not encrypt replies.

Developer announcement subscriptions use the separate `QTDEVFEED2` signature
domain, binding sender, request identity, issue time, action, session and target.
Local developer identity plus a private signer starts the subscription;
`devlogall` remains only a presentation filter. All clients publish a compact
global `HELLO` after channel readiness on startup/re-entry. A developer publishes
`DEVANN` globally, renews every 90 seconds, and coalesces arrivals into reoffers
no more often than ten seconds. Reoffers reuse the signed record and envelope;
verified request identities suppress repeated crypto work. Authentication owns
subscription replay admission, allowing a previously capacity-rejected offer or
an offer after a local profile/session reset to be retried. A lease ends 240
seconds after its signed issue time, never 240 seconds after delayed receipt.

Only clients allowing developer diagnostics add whisper audiences to ANN/LVL.
They reuse the original sanitized payload and envelope, including public location
sharing restrictions. Public/group and private copies deduplicate as one event.
Consent, ignore, profile replacement, departure and session shutdown fence queued
copies and delayed authentication. Signature verification rechecks peer departure
ordering before installing a lease. This does not provide historical replay or
messages from clients on unreachable channels or older unsupported versions.

Mirrors use the existing background class and budgets, at most four outstanding
copies and four subscribed developer recipients per client. Receiver processing
allows 32 mirrored datagrams/second, burst 16 and at most eight per frame before
the ordinary ingress limits. At most eight incoming mirror assemblies (4 KiB
each) leave capacity for normal traffic. These are QT processing policies, not
claims about server limits or guaranteed delivery. Extra copies can expire or
drop under load; bounded counters report queue outcomes and receiver drops.

Features submit owned records through `Publish`, `Emit`, `Request` and `Respond`.
The catalog supplies semantics, priority, lifetime, size bounds and legal routes.
Producers attach an owner and currentness predicate; they never encode a payload
only to decode it again for scheduling or privacy. A logical submission preserves
one envelope identity across audience fan-out. Native sender identity is
authoritative; conflicting payload identities are rejected.

`RuntimeCoordinator` alone advances periodic network work. Authentication,
request deadlines, transfer progression and transport drain advance each frame;
feature sampling uses deliberate cadences. Geographic interest policy retains at
most the current and viewed zone subscriptions, with four-second view dwell.
Both zones trigger coalesced discovery; each responder can advance at most one
publication per zone cooldown. Public whole-world baselines use 150–210-second
jitter and a maximum 600-second source lifetime. Regional cadence varies with
density and renews stationary locations. Nearby streams keep four leases, with
replaceable per-recipient samples that expire after two seconds. UI settings and
presentation consumers do not drive network progression.

Inbound processing has a separate per-frame ceiling: 96 datagrams/24 KiB total,
with public traffic limited to 64 datagrams/16 KiB. The reserve admits actual
party traffic and peers with live targeted requests. Cheap admission checks run
before decoding; the runtime alone resets the allowance. There is no unbounded
receive queue or accumulated idle credit. Excess packets are counted and dropped;
ordinary state renewal and bounded request/transfer recovery remain responsible
for repair. Generated timestamp IDs use fixed-point decimal formatting because
Forever's integer format conversions are 32-bit.

The shared scheduler uses QT policy limits, not claims about Blizzard limits:

| Limit | Value |
| --- | --- |
| Byte rate / burst | 800 bytes/s / 1,600 bytes, charging prefix and estimated overhead |
| Packet rate / burst | 4 packets/s / 4 packets |
| Queue / control reserve | 96 datagrams / 16 slots |
| Weighted class rotation | control 1, events 1, active state 3, bulk 2, background 1 |
| Native attempts per frame | 2 |
| Outgoing / incoming transfers | 16 / 64, with reserved incoming party/targeted capacity |
| Aggregate retained payload / object | 512 KiB / 128 KiB |
| Fragments per object / datagram | 1,024 / 255 bytes |

Buckets start empty on world entry. Class rotation also rotates destinations and
transfers and borrows unused capacity. `AddonMessageThrottle` pauses the prefix
for one second and reduces its packet rate to one/second. Thirty seconds of
successful active traffic recovers 0.5/second, capped at four; idle time earns no
rate recovery. `ChannelThrottle` is an ambiguous native outcome and is not
resubmitted automatically. Native acceptance never claims remote delivery.
Tickets settle exactly once, including replacement, cancellation and expiry.

State samples replace older queued samples for the same topic/audience. Events
retain immutable identities and finite duplicate suppression. Requests preserve
identity across bounded retries; accepted actions cannot prompt or act twice.
A transiently busy receiver must not tombstone an unaccepted request. Immutable
cached responses can replay after loss without rereading a changed domain
snapshot. PQL installs complete snapshots atomically and reuses only an exact
revision; objective detail is a separate request.

Large transfers share one fragment format, validate correlation before allocating
response buffers, and interleave across recipients. Completion/END starts missing
fragment repair, with at most two rounds. Thirty seconds without progress and a
missing END permits a bounded status query. Queueing alone is not packet loss.
The original request bounds transfer lifetime to at most 600 seconds. Retirement
releases buffers on completion, cancellation or expiry. Oversize and capacity
failures are explicit; requested fields are not stripped to fit.

Pongs have **no arrival-time cutoff**. They must match one of the eight most recent
locally owned ping identities in the current session, match a target when one was
specified, and pass sender deduplication. This finite bookkeeping is independent
of reply age. Old source locations cannot be made fresh by a late pong. Detailed
diagnostic reports retain their separate request/transfer expiry, signature and
consent checks. Publicly shared diagnostic positions update ordinary peer state;
hidden diagnostic positions remain in their separate authorized store.

Privacy withdrawal cancels queued coordinate publications and their parent
transfers before sending a clear. Ignore, group changes, profile replacement,
world departure and disable fence both pending work and stale callbacks. Departure
cancels old queues, then attempts a small BYE through the same native adapter with
available budget. It never flushes old work or earns more budget after retirement;
expiry remains the fallback. Re-entry starts empty and republishes fresh state.

Diagnostics are bounded counters/gauges for queue age and charged bytes, native
outcomes, replacement/expiry, request timing, authentication queue/work time and
transfer progress. They distinguish native acceptance, authentication and remote
response assembly. Reading diagnostics must not start network activity.

The private multi-peer network harness runs actual coordinators with independent
clocks/state, frame-rounded timers, asynchronous channel joins and delivery
separate from native acceptance. It exercises loss, reorder, duplicates, throttle,
ambiguous outcomes, low FPS, mixed workloads and lifecycle changes. Run the
[live communication release gate](docs/COMMUNICATION_LIVE_TESTS.md) before publishing
the major upgrade; offline results alone do not validate real delivery or coexistence.

## UI and client boundaries

Never write QT state onto Blizzard frames, children, mixins or shared tables.
Use owned regions, GUID records and weak side tables. Guard foreign reads for
secrecy, accessibility and forbidden state; defer protected mutation until all
applicable restrictions clear. Treat a forbidden frame as quarantined.

Inherited hiding (including Alt+Z) suspends interaction without dismissing the
window's session. Explicit close retires it even if its parent is already hidden.
A dismissed presentation is hidden before its callback may display a successor
on the same frame. Temporary native Edit Mode hiding preserves its Revert
baseline until the editing session actually ends.
Window geometry belongs to the profile that last restored it. Replacing that
profile restores its saved geometry or the window defaults, while display
changes fit the current layout without erasing the user's saved dimensions.
A region queued for cleanup carries ownership: reuse cancels old cleanup.
Cleanup can outlive addon disable; stale feature work cannot.

Bindings declare an explicit localized category instead of a legacy header row.
Existing action IDs remain stable so saved assignments survive. Keybindings
dispatch through existing feature operations; they never assign keys or duplicate
action logic. The quick-menu binding uses the ordinary native menu and remains
available when the minimap icon is hidden.

Use native settings controls through the shared constructors. Player-facing
text is localized at presentation; wire facts and diagnostic identifiers stay
stable. Vendored LibChev is immutable under its pinned manifest: fixes belong
upstream followed by a deliberate vendor update.

Use Blizzard templates for ordinary buttons, checkboxes, swatches, searches
and scrollbars. Preserve inherited search and control behavior on owned instances.
OwnedUI translates native scrollbar percentages to the window's pixel offsets;
features retain their layout, filtering and scroll model. Programmatic refreshes
must not feed back into input callbacks, and hidden/restricted windows retire
held scrolling. Debug controls follow the same policy in upstream LibChev.

## Validation and delivery

`/qt test` loads private fixtures through the same TOC as the addon. Tests must
never patch Blizzard globals, shared native tables, secure-adjacent APIs or
live frames. UI fixtures model parent visibility, frame reuse and independently
forbidden/protected regions. `scripts/test.lua` alone owns offline engine stubs.
Presented runs schedule one complete isolated case per frame through LibChev;
fixtures and announcement suppression are restored before each frame returns.
Explicitly marked `offline` stress, soak and expensive matrix cases remain in
the full headless suite and are counted as skipped in live reports. Never yield
inside a fixture or silently time out a case. CI exercises the real staggered
controller in both orders with live-state updates between callbacks.
Fixtures detach unknown runtime tables to `nil`, so component constructors own
their shape; they must not turn initialized stores into empty placeholder tables.
Offline runs seed populated phase/target stores to exercise tests after gameplay.
WoW can reject division by zero: live numeric fixtures use supported nonfinite
constants, while mandatory real NaN assertions remain outside the TOC.

Run Lua 5.1 and 5.2 suites in both orders; settings construction, all locale and
client profiles, crypto, localization, release-note and packaging checks are CI
requirements. `scripts/check_architecture.py` protects key ownership boundaries;
behavioral tests cover cancellation, incomplete observations, replay, recovery
and the protocol upgrade boundary. Do not replace those with only source-pattern tests.

`scripts/package.py` derives installed Lua from the TOC and includes only the
explicit runtime asset/document rules. It checks pinned dependency hashes and
verifies every archived payload. Release builds use an immutable `--ref`;
working-tree builds are previews. See [RELEASING.md](RELEASING.md).

Offline success proves these contracts under fixtures. It does not establish
in-client rendering, taint safety, SavedVariables migration with real data,
network delivery or behavior with other addons. Keep those checks explicit.
