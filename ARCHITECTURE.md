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
| QuestCompletion | Bounded character-history queries for visible comparisons, evidence age and completed/absent classification | Account-wide completion or full history broadcasts |
| QuestSharingResults | Exact native share-result matching and recent per-player explanations | Guessing which quest a native result belongs to |
| QuestCompareInteraction | Column presentation and keyboard selection geometry | Removing members from comparison calculations or global key bindings |
| PartyFocusController | Following and manual-choice state machine, missing-quest and confirmation policy | Party networking, persistence policy or preview fixtures |
| PartyNavigation / QuestComparePreview | Live/preview adapters, persistence and ownership of native focus | Copies of the following state machine or repair of another controller's fields |
| Hints | Local tip catalog, capability eligibility, account-wide no-repeat pool, startup display and whitelisted navigation links | Network announcements or implicit setting changes |
| PlayerNotes | Private full-name annotations and their owned editor | Peer state, profile copies, diagnostics or network payloads |
| RecentCompanions | Bounded private history from actual group membership and its owned list | Nearby discovery, online status, profile copies or network payloads |
| ObjectiveAnnouncements | Bounded local objective burst aggregation before publication | Remote-event rewriting, native quest reads or a separate timer |
| PlayerDetails | Active hover interests, metadata refresh and roster fetch coordination | Tooltip drawing or an independent timer |
| PartyVisuals | Shared party identity, validated rosters, partial membership evidence and freshness-aware member lookup | Tooltip-specific membership inference or manufacturing peer presence |
| Keybindings | Fixed player actions delegated to existing feature operations | Key assignment, binding overrides, native input state |
| OwnedUI | Guarded owned-region access and a durable cleanup queue | Permission to modify Blizzard-owned frames |
| WindowController / WindowLayout / WindowTheme | Window visibility and dismissal, geometry, chrome respectively | Quest-specific dialogs or protocol sessions |
| QuestDetails | Bounded copies of native quest-tooltip text and an owned reader session | Native tooltip mutation, quest selection, or peer requests |
| QuestDialogs | Focus/share-related presentation and callbacks | Window geometry rules |
| PlayerTooltipPresenter | Shared player tooltip content and measurement | Map projection or marker allocation |
| MapOverlayPool | Surface attachment, marker reuse and retirement | Player/waypoint content, route or visibility policy |
| MapLocationPresentation | Projected world-map clustering/expansion and temporary player selection | Accepted observations, consent, location sampling or native map mutation |
| MapOverlayControls | Saved world-map overlay visibility, owned toggle and hover highlight | Sharing, subscriptions, minimap visibility or accepted observations |
| LocationPins / PartyWaypointPins | Domain-specific pin placement, visuals and actions | A second tooltip renderer or marker pool lifecycle |

## Data and time contracts

- Recent companions are recorded only from the sanitized current group roster,
  including non-QT members. The private `db.global.recentCompanions` store is
  scoped by client, region, naming model and realm; it retains at most 100 entries
  for 90 days. Leaving a group stamps the previous roster before replacement.
  Departure stamps require the exact roster observed in this enabled world
  lifetime; re-entry reads the native roster again, never renewing a stale one.
  Profiles do not copy the history, and neither network nor diagnostic payloads
  include it. Removing an entry suppresses re-recording until that member leaves
  the current group. The list does not imply that someone is currently online.
- Local objective increments have one fixed half-second deadline per quest
  lifetime and objective identity. The newest captured event replaces the older
  pending one before all outputs (wire, local chat, bubbles and non-QT party chat).
  Finished objectives and quest milestones flush in order; removal, stage changes,
  profile changes, world departure and disable retire obsolete work. The shared
  owner-bound scheduler handles the deadline; unknown objective facts publish
  immediately rather than guessing how to combine them. Sender wording stays intact.
- World-map clusters are formed after projection within 24 UI pixels, with stable
  player membership. Clustering is enabled by default and can be disabled in Player
  Locations without affecting sharing or discovery. Hovering a cluster shows up to six
  cached player rows through the shared tooltip renderer, including individual status
  icons but no inferred party grouping or leaders. Clicking opens the smallest
  native map that geographically contains every member, including overlapping
  city/zone maps, without changing canvas magnification. At the
  deepest shared map, clicking expands up to 12 player
  dots with the existing player tooltip and actions. Large clusters page with the
  mouse wheel over the count marker.
  A navigation click automatically expands an identical cluster on the destination
  map. Its two-second intent is consumed once and is cancelled by membership,
  map, profile or enabled-lifetime changes; split clusters remain individual dots.
  While expanded, a noninteractive owned layer shades the visible map and ordinary
  markers by 22%. The cluster center, member dots and connectors render above it.
  Party-hover dimming remains independent; the minimap is unchanged.
  Expansion owns only a cluster identity, page and geometry signature; positions are
  display offsets connected to accepted coordinates, never new location observations.
  Hiding/changing the map, geometry or membership, disabling clustering, profile changes
  and Find on Map retire expansion. Minimap pins remain individual.
  The world-map QT button toggles all QT player and waypoint overlays together.
  Its per-profile preference defaults on and does not affect the minimap, sharing,
  filters or discovery. Hovering the button shades the native map beneath all QT
  overlays; leaving restores normal layering, including any expanded cluster.
  Location age never changes marker brightness. Normal source-freshness expiry
  still removes old observations; dimming reflects interaction state only.
  Find on Map uses the guarded native opener and a 20-second green selection at the
  player's actual location, outside its cluster. Explicit selection may temporarily
  reveal an otherwise filtered non-LFQP player and restores world-map overlay
  visibility, but never changes saved player filters or sharing preferences,
  revives expired coordinates or reveals a hidden diagnostic location. Own-party
  markers remain native. Closing/changing the map, profile replacement, restriction,
  withdrawal, ignore and departure retire selection through normal presentation refresh.
- Developer map identity comes only from the existing signature-verified announcement
  lease, checked against the peer session, departure and expiry. Authenticating that
  public identity is independent of diagnostic consent; private requests and mirrored
  announcements remain consent-gated. Verified developers use a class-tinted gear with
  normal player interactions. Only the local developer can query fresh diagnostic
  location privacy for the shared tooltip; received presentation flags cannot grant
  a badge or reveal diagnostic-only status to ordinary clients.
- Private player notes live in `db.global.playerNotes`, separated by client
  project, region and naming model, then canonical full player identity. They
  survive profile/character changes. Neither diagnostic exports nor any
  communication record may include notes or unsaved editor drafts. Presentation
  escapes markup; the editor keeps the complete bounded note.
- A completed active-log snapshot proves absence from that log, not completion
  history. Comparisons show `Absent` as "Not in log" until character-specific
  history establishes `Completed` or `Missing`. Repeatable quests never become
  permanently satisfied from a past completion. Active `Have`/`Ready` entries
  take precedence, and `Completed` does not mean ready for turn-in. Optional
  history fields preserve compatibility with older v2 peers. Queries cover at
  most 32 IDs per request and 100 visible interests, with bounded native work;
  source sampling time limits history freshness to 60 seconds.
- Collapsing columns changes only session presentation. All members still
  participate in readiness, missing-quest and sharing calculations. Keyboard
  navigation is explicitly activated and uses a temporary owned input child;
  edit focus, menus, outside clicks, restrictions and hiding retire that child.
- Native quest-sharing messages have recipient identities but no quest IDs.
  Their recent localized explanations are labeled as the player's latest share
  result. They never change a particular QT request to accepted. QT's own
  request responses may include an optional, validated failure reason code.
- Active player hovers immediately display cached metadata and register an
  interest. `RuntimeCoordinator` renews or retries deduplicated metadata and
  full small-party roster requests; rendering does not pump requests. Hidden,
  replaced, ignored or departed hover targets retire the interest. Full rosters
  cover parties of up to five; raids retain the existing size-only summary.
  Transfer-aware request deadlines are authoritative for fragmented rosters.
  Interrupted hover metadata can retry after a short cancellation cooldown.
  Partial metadata with no accepted progress or correlated responder liveness
  for 90 seconds is retired before requesting a fresh snapshot; healthy
  transfers retain the original request and its absolute deadline.
- Player hovers, cluster grouping and party highlighting resolve membership
  through `GetPlayerPartyVisualInfo`. Direct observations retain their sender
  and sampling lifetime; a bounded membership index lets every confirmed
  member reuse the same validated roster. Partial known members remain
  distinct from a complete roster and do not suppress a needed roster fetch.
  Newer conflicting membership, departures, ignores and expiry retire the
  corresponding evidence; reading a roster never renews its source or creates
  QT presence for its members. A newer validated roster also disproves older
  overlapping membership reported by another party. Reload persistence uses
  the same resolved evidence, including solo and grouped-with-unknown-size facts.

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
  Overlapping party facts retain raw source timestamps through projections and
  reload caching. Within one sender/session, source revisions resolve equal
  timestamps; receipt fractions and unrelated senders' counters cannot.
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

Tips are local chat-log output. `OnLogin` schedules one through the shared UI work
lifetime after chat destinations are initialized; zoning and enabling do not draw
another. The profile's `showStartupTips` preference defaults on and is checked
before scheduling and again before printing; manual `/qt tip` and `/qt hint`
remain available when it is off. All draws share `db.global.hintPool`.
Stable IDs survive wording, language and profile changes. Only successfully printed
tips consume a draw; unsupported client features are excluded. Display adds the
QT tip logo with its gold bulb, gold localized label, and cream tip text centrally,
leaving catalog text reusable.
Release-note tip examples carry a localized label and body in canonical notes;
the viewer calls the same hint formatter inside a separate chat-style card.
Web notes render that example as an illustrated blockquote; Discord uses the same
icon beside the localized tip label in a separate embed.

## Communication generation 2

The only gameplay prefix is `QuestTogether2`. Existing global and regional chat
channel names remain unchanged. Generation 1 traffic is ignored, with no legacy
decoder, companion packet or fallback transmission. Optional feature capabilities
may extend generation 2, with conservative behavior when a peer lacks support.
Peers on different protocol generations must upgrade together. Ed25519 developer requests bind the
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

EventLocalization owns the shared local quest-title cache and native load budget.
Core reads local quest titles, links and structured tooltip headers without
opening or selecting native UI. Foreign-language announcements may wait at most
two seconds for an already-requested title, with at most 32 pending messages;
runtime owners cancel them on reset or world exit. Completion rechecks current
display eligibility and prints once, preserving the sender's title if no local
title becomes available. Subsequent events for the same player and quest retain
arrival order and the original deadline; unrelated announcements remain independent.
Title resolution notifies current views even when another surface filled the
cache first. Each view owns its deferred refresh and session checks. Quest Details
uses the same resolver for its heading and retains pending native tooltip IDs
even before text arrives. Received quest titles are normalized only for display;
certified snapshots and revision inputs remain unchanged.

The settings home page keeps General controls with a compact status readout and
shortcuts for the Party Quest Log, patch notes, and support. Category navigation
stays in the native settings sidebar. The Theme dropdown presents the existing
`lightMode` profile preference.

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
