# QuestTogether architecture

This is the tracked contract for addon changes. Keep it alongside the code;
private `.local` notes are historical context, not the source of truth.

## Ownership

| Component | Owns | Does not own |
| --- | --- | --- |
| Core / EventHandlers | Native adapters, initialization, event routing, quest lifecycle orchestration | Feature timers, profile effects, live classification caches |
| Settings | Profile storage, migrations, value validation, atomic edits and effect dispatch | Widget construction, native navigation or frame mutation |
| RuntimeCoordinator | The enabled addon's periodic lifetime and feature tick order | Individual feature caches or wire codecs |
| Audio | Cue catalog, per-profile sound preferences, bounded suppression and QT-owned playback handles | Shared game sound settings, other addons' sounds or a delayed notification queue |
| DataBroker | Optional toolbar launcher registration, copied display fields and click routing | A bundled library, display-owned frames or another minimap button |
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
| DeveloperAnnouncements | Signed developer subscriptions, diagnostic consent, mirror audiences and paced private location publication | Normal announcement filters, private location storage or a separate transport |
| PartyQuestSync | Small-party lifetime, atomic quest-list snapshots, exact revisions, lifecycle replay and paced background interests | Window visibility, native sends or independent timers |
| PartyQuestProgress | Party-owned remote objective snapshots, ordered announcement deltas, per-peer detail requests and shared PQL/HUD subscriptions | Display filtering, independent polling, or assuming objective indices match across players |
| QuestProgressStyle | Shared rounded detail sections and objective progress bars for PQL and HUD | Quest state, requests, or window lifecycle |
| QuestFocusWindow / QuestFocusTooltip / QuestFocusEditMode | Party Objective Tracker HUD, native focus/tooltip observation, local detail reads, owned Edit Mode controls and revert baseline | Blizzard tracker rows, shared native layout registries or a separate objective cache |
| PartyFocusIndicators | Clickable class-colored party-focus dots and hover tips beside native quest buttons; bounded read-only block lookup and owned overlay geometry | Native tracker scripts, text, pools or layout; another focus store or network request |
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
| HUDEditDialog | Shared owned Edit Mode selection artwork and settings shell, native slider wiring, layout and theme | Feature selection, values or revert policy |
| WindowController / WindowLayout / WindowTheme | Window visibility and dismissal, geometry, chrome respectively | Quest-specific dialogs or protocol sessions |
| QuestDetails | Bounded copies of native quest-tooltip text and an owned reader session | Native tooltip mutation, quest selection, or peer requests |
| QuestDialogs | Focus/share-related presentation and callbacks | Window geometry rules |
| PlayerTooltipPresenter | Shared player tooltip content and measurement | Map projection or marker allocation |
| MapOverlayPool | Surface attachment, marker reuse, retirement and shared focus shading | Player/waypoint content, route or visibility policy |
| MapLocationPresentation | Projected world-map clustering/expansion and temporary player selection | Accepted observations, consent, location sampling or native map mutation |
| MapOverlayControls | Saved world-map overlay visibility, owned toggle and legend | Sharing, subscriptions, minimap visibility or accepted observations |
| LocationPins / PartyWaypointPins | Domain-specific pin placement, visuals and actions | A second tooltip renderer or marker pool lifecycle |

## Data and time contracts

- Quest-focus following retains its per-character target when the followed
  player selects a quest absent from the local log. It exposes a waiting status
  without opening a modal or changing current navigation. The shared controller
  rechecks ownership on its existing runtime cadence and on fresh peer focus,
  then applies the current shared quest without another Follow action. Reload
  recovery still requires fresh peer data; departure, ignore, raid conversion
  and disable clear intent, and explicit navigation keeps its existing
  confirmation policy. While waiting, native quest pickup/turn-in selection
  changes establish a new local baseline without cancelling follow intent; the
  same applies when the previous focus is no longer in the local quest log.
  A manual native focus change remains selected while the stop-follow dialog is
  pending. Follow application pauses until the choice is resolved: acceptance
  keeps the selection and stops following; cancellation resumes the latest
  eligible peer focus. Superseded choices cannot change a newer selection.
- PQL and POT subscribe to party-owned quest data. Small parties bootstrap and
  conditionally refresh quest lists every 30 seconds without an open window.
  Background detail acquisition progressively warms every member's log; visible
  quests take priority, then unsampled quests (shared quests first). Background
  repair has a 120-second cadence; visible detail uses 30 seconds, with a five-second
  minimum between attempts. RuntimeCoordinator is the only periodic owner.
  Background summary/history/detail requests serialize per peer and party detail
  starts are paced to at most two per second. Explicit Refresh replaces a pending
  summary and can pass other pending reads, with repeated refreshes coalesced to
  at most one full request per peer every five seconds. Native accepted/already-on-
  quest share results use this same refresh path without inferring a quest ID.
  Accepted data stays visible while the header shows Loading for that refresh.
  A QCMP scheduling hint puts background requests and replies in the background
  traffic class; the coordinator applies it within protocol 3.
  Closing or changing views only detaches their callbacks. Pending requests and
  accepted data survive; departure, ignore, profile/world changes and disable
  retire the party lifetime. Up to four remote logs of 100 quests are warmed;
  objective storage is capped at 128 records per peer. Detached extra records
  expire after 120 idle seconds once any pending request has settled. Raids and
  comparisons outside the small party retain on-demand fetching.
  Refresh failures retain accepted data rather than reverting to Loading.
  Incoming announcements update cached rows before chat
  filters or delayed title rendering. Ordering is per sender/objective with quest
  lifecycle barriers. Events observed during a snapshot transfer are replayed over
  its baseline so a delayed reply cannot roll progress backward. Changed objective
  wording retires unverified sibling rows until a detail snapshot repairs them;
  indices are never matched across different players or languages.
  A complete summary fences overlapping detail replies while retaining accepted
  objective progress when summary fields are unchanged, and announcements
  received during summary assembly are replayed before installation is exposed.
  Shared detail rows fall back to certified quest status when there are no
  objective counters; an empty list never establishes readiness or completion.
  Their separate `questStatus` also drives each POT member header's status
  artwork. Known readiness survives pending objective-detail requests; pooled
  objective rows never inherit member icons. Native atlas selection/fallback
  is shared with PQL through `QuestProgressStyle`.
- The Party Objective Tracker has one profile-owned display mode: hidden, focused quest,
  hovered quest (default), or focus and hover. The combined mode follows local
  native quest focus (including party-follow changes), temporarily previewing a
  hovered Blizzard tracker quest through
  bounded read-only mouse/ancestor inspection. Hover never changes native focus;
  leaving falls back to focus or hides when neither exists. Local quest-log
  events refresh its own objectives without remote
  polling. Geometry is profile-owned under `windowLayouts.questFocus`. Its height is a
  maximum (600 by default): the managed placement frame retains that size while
  a top-anchored content panel shrinks to its rows outside Edit Mode. Overflow
  scrolls at the maximum; automatic shrink never writes saved geometry. Default
  placement samples Blizzard tracker and outer NineSlice geometry read-only and anchors QT to its
  inward-facing top corner without an additional gap. The profile option
  `questTrackerSnapToBlizzard` defaults on. While enabled, corner resizing is
  disabled; size sliders remain available. Dragging away disables snapping and
  restores corner resizing. Enabling snap replaces
  the manual position; disabling it allows dragging from the current location.
  Save/Revert include this option, and Reset restores docking. No anchors or state are written onto Blizzard frames. Opacity
  affects the backgrounds, with faint player sections retained at zero and text
  staying opaque with contrast suited to transparency. Player sections retain their
  class-colored fill at a constant 25% opacity, independently of the background
  slider. The optional solo-visibility rule uses actual group membership, defaults
  on, and never hides the Edit Mode preview. Its checkbox in Groups & Sharing
  and its Edit Mode checkbox read and write the same profile option. HUD Edit Mode
  shows an owned placement preview; selecting it opens the same themed settings
  shell as the personal bubble, with display mode/width/height/opacity controls and
  Save/Revert/Reset actions. Changes apply automatically. Save/revert
  baselines remain QT-owned, and temporary native Edit Mode hides preserve them.
  No rows, pools or settings are injected into Blizzard's objective tracker.
  Already-received progress uses the unblocked `quest_focus_presentation` work
  class: the renderer checks every owned region, uses the cached title and
  updates text/layout even during combat. Native reads, window creation,
  scrollbar controls and Edit Mode wait for their normal safe boundary. Local
  announcements enter that same progress reducer before local chat/bubbles;
  a later quest-log read repairs the rest of the local snapshot.
  When the native tooltip remains visible, snapped POT attaches to the tooltip owned by the
  exact hovered quest block. The profile-owned `questTrackerTooltipPlacement`
  offers Top (default), Bottom and Side in settings and Edit Mode. Top and Bottom
  align the right edges, using the opposite vertical edge if the chosen edge has
  insufficient room; Side retains the lateral layout. Screen bounds, visible content size, mixed scales
  and the source row constrain placement; narrow screens can use vertical
  placement or a bounded temporary scale reduction. Hover geometry is never
  saved; leaving restores the ordinary anchor and Edit Mode keeps its placement
  bounds. Native enter events only schedule a fresh, guarded read; the existing
  runtime observer handles leaving. `questTrackerHideBlizzardTooltip` defaults
  on and is shared by Groups & Sharing and Edit Mode. Existing explicit false
  choices remain unchanged; Reset to Default restores hiding. It may hide only the
  matching unprotected quest/campaign progress tooltip while POT is shown and
  restrictions permit. Failed suppression retains adjacency. Reward, item and
  unrelated tooltips remain untouched; QT never forces a reused tooltip to show.

- Native tracker party-focus markers use `GetPartyQuestFocusID` for up to four
  other members of the current small party, independent of following and POT
  visibility. `RuntimeCoordinator` samples those rows and refreshes geometry;
  the marker view reacquires visible native quest blocks through the read-only
  `GetExistingBlock` lookup. Each member gets a clickable class-colored dot to
  the left of Blizzard's quest-focus button, with a tooltip identifying whose
  focus it represents. Members sharing a quest form a spaced horizontal row;
  a lime-green outline identifies the followed member without changing class color.
  A white chain-link badge identifies a member following the local player, using
  the shared navigation query and its existing ordering, expiry and membership
  rules. Matching quest IDs alone never establish a follow relationship. Badges
  reserve their own horizontal space and share the dot's hover/click target.
  The owned frames are parented to UIParent and positioned
  with sanitized coordinates; they never alter native layout, pooling or
  gamepad navigation. Clicks request a follow confirmation; the user can save a
  per-profile preference to skip it. Delayed clicks and dialog choices recheck
  identity, membership and lifetime. Hidden, recycled, sliding
  or unreadable native rows and retired focus observations hide their markers.
  Focus dots, follow rings and badges track the native row's strata and frame
  level so ordinary windows can cover them. Their separate hover tooltips and
  focus confirmation dialogs remain on their appropriate overlay layers.
  POT renders above native quest-hover tooltips outside Edit Mode.

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
  icons and party groups from the shared party query. Clicking opens the smallest
  native map that geographically contains every member, including overlapping
  city/zone maps, without changing canvas magnification. At the
  deepest shared map, clicking expands up to 12 player
  dots with the existing player tooltip and actions. Large clusters page with the
  mouse wheel over the count marker.
  Individual player tooltips use the same white party outline, badge and total
  count around known roster members; solo players have no party decoration.
  Groups larger than five show the leader and the hovered player, once each,
  within that outline while retaining the group's total count.
  Summary-only and unknown party evidence remains labeled until a roster is known.
  Moving player markers keep updating beneath a stationary pointer while their
  tooltip remains open at its original position. A separate hover identity keeps
  pooled pins from changing the tooltip's subject; cluster summaries retain the
  acquired members and remove anyone no longer eligible for display. Moving the
  pointer away, closing/changing the map or losing visibility ends the hover.
  Secure minimap targeting still requires the actual marker under the pointer;
  a retained tooltip never preserves an old click target or cluster click hint.
  A navigation click automatically expands an identical cluster on the destination
  map. Its two-second intent is consumed once and is cancelled by membership,
  map, profile or enabled-lifetime changes; split clusters remain individual dots.
  Hovering a world-map player, cluster or shared waypoint shades the map while
  keeping the marker hosts and their children above the shade. The shared overlay
  owner fades unrelated markers separately; focused markers retain full opacity.
  Player focus includes visible party
  members. Hover shading never stacks with the expanded-cluster shade; leaving a
  marker restores the existing expansion emphasis, if any. Minimap hovers do not
  shade the world map.
  Expansion owns only a cluster identity, page and geometry signature; positions are
  display offsets connected to accepted coordinates, never new location observations.
  Hiding/changing the map, geometry or membership, disabling clustering, profile changes
  and Find on Map retire expansion. Minimap pins remain individual.
  The runtime coordinator follows world-map canvas geometry each frame. Same-map
  zoom and pan only reposition admitted player and waypoint markers; peer queries,
  clustering and communication retain their sampling cadence. Map-level changes
  rebuild the map overlays immediately, and unavailable geometry hides old markers
  until the new map is readable. Marker sizes and clipping remain in viewport pixels.
  Existing minimap player dots also follow the viewer's position and facing each
  frame, including peers without stream leases and authorized private dots. This
  pass rechecks visibility and freshness, reuses fixed world-coordinate conversions,
  and leaves membership, tooltips and network sampling on their normal cadence.
  The world-map QT button toggles all QT player and waypoint overlays together.
  Its per-profile preference defaults on and does not affect the minimap, sharing,
  filters or discovery. Hovering the button shows the map legend without changing
  map shading or marker emphasis.
  Location age never changes marker brightness. Normal source-freshness expiry
  still removes old observations; dimming reflects interaction state only.
  Find on Map and left-clicking a world-map dot share one 60-second green selection
  at the player's actual location, outside its cluster. A new selection replaces
  the previous one; right-click menus leave it unchanged. Left-click opens the
  deepest containing map, or the player menu when already there. Selection survives
  viewed-map changes but closing the map retires it. Find may temporarily reveal an
  otherwise filtered non-LFQP player and restore overlay visibility, but never changes
  saved player filters or sharing preferences, revives expired coordinates or reveals
  a hidden diagnostic location. Clicking a visible dot preserves its visibility rules,
  including developer-only diagnostic rows, through the existing visible-row query.
  Own-party markers remain native. Profile replacement, restriction, withdrawal,
  ignore and departure retire selection through normal presentation refresh.
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
  history fields distinguish active-log snapshots from completion evidence. Queries cover at
  most 32 IDs per request and 100 visible interests, with bounded native work;
  source sampling time limits history freshness to 60 seconds. Viewport changes
  limit pending requests but retain fresh accepted history for the comparison's
  bounded quest union, so sorting a completed quest offscreen cannot make it
  appear absent again. Ownership, expiry and snapshot invalidation still retire
  that evidence.
- Collapsing columns changes only session presentation. All members still
  participate in readiness, missing-quest and sharing calculations. Keyboard
  navigation follows opening/list-click focus and uses a temporary owned input child;
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
- Personal bubbles use the profile's `ownChatBubbleMode` (`always`, `solo`, or
  `hidden`) beneath the master `showChatBubbles` switch. The old hide-own boolean
  migrates before defaults are applied, including inactive and copied profiles.
  One visibility query covers local announcements, QT chat, playback and
  capability reporting. Solo mode reads native party/raid membership rather than
  waiting for QT peer discovery; group changes retire a visible personal bubble
  without replaying it on leaving. Other players' bubbles, chat logs, publication
  and the Edit Mode placement preview keep their independent behavior.

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

The in-game release-note catalog groups releases by major/minor series. Each
page starts with the earliest available release in that series and appends its
patches in version order, retaining each release's date, translation fallback,
tips and illustrations. History navigation selects series rather than individual
patches. Successfully opening the combined page acknowledges the latest notes
version; automatic presentation remains gated on a new major/minor series.
Canonical notes, web changelogs and Discord posts remain individual releases.

## Audio

`Audio.lua` owns the only native QT audio adapters. Feature modules submit cue
keys at accepted transitions, never during repainting. Quiet defaults enable
requests/confirmations and successfully applied automatic focus changes. Party
waypoints, quest readiness/turn-ins/progress, QT chat and quest-share results are
individually available but off by default. A preview bypasses the event's enable
switch while respecting the addon lifetime, master switch, volumes and combat
mute preference.

Six original QT recordings provide a shared sound palette. Custom-file playback
has no portable per-call gain, so the asset builder renders 1–100% linear gain
variants. Runtime combines master and event percentages, selects the nearest
positive variant, and makes no native call for zero. Playback uses WoW's SFX
channel and remains subject to its mute/volume controls. QT never changes audio
CVars; native button sounds and existing emote audio remain owned by WoW.

Only one QT handle is retained. Per-cue cooldowns and the configurable minimum
interval suppress bursts; attention prompts can interrupt a lower-priority cue.
There is no notification backlog. Prompt identities suppress redraws, accepted
waypoint geometry suppresses heartbeats, and objective cues require fresh party
events. Older useful quest observations still update the domain cache silently.
Disable, profile changes and world departure retire audio state and stop only
QT's handle. RuntimeCoordinator handles ongoing mute/lifetime checks.

Live tests detach audio state and use owned playback recorders. Production
adapters also refuse native play/stop calls while tests run. Package verification
includes every gain variant and its audio provenance notice/manifest. Offline
checks establish dispatch and isolation; actual listening in supported clients
is still required to assess audibility and sound quality.

## Communication generation 3

VIP cosmetics use a separate pinned issuer key in `VIPPublicKey.lua`.
`VIPIdentity.lua` owns account-wide activation storage, incremental certificate
and sender/session-bound proof verification, bounded identity caches, publication
and withdrawal. `VIPWindow.lua` owns the contact/activation UI. Neither module
grants developer authority or changes diagnostic/location consent.
`RuntimeCoordinator` advances VIP work through the communication coordinator;
public `VIP` events use scoped mesh interests, the catalog, transport and
fragment assembly. Presentation queries `IsVerifiedVIP`, with developer artwork
taking precedence. Private activation seeds live in the separate
`QuestTogetherVIP` SavedVariables root and are excluded from profile exports and
diagnostic snapshots.

`services/vip` is a separate Discord worker, not an addon runtime dependency.
It stores permanent Discord-ID grants and per-installation credentials in a
private SQLite ledger. Only the configured numeric owner may grant or issue for
another user; all command replies are ephemeral. The dedicated issuer key and
ledger must be preserved when moving hosts. See `services/vip/README.md`.

The only gameplay prefix is `QuestTogether3`, with generation 3 framing. Old
prefixes and framing are rejected without responses. Both Retail and Forever use
the same primary mesh design; communicating clients must upgrade together.
Existing signed credentials keep their dedicated signature domains and formats.
Signatures authenticate identities and requests; they do not encrypt replies.

`MeshNetwork` owns candidate addresses, correlated native-whisper handshakes,
neighbors, directory scans and scoped interest paths. These are routing records,
not accepted player observations. `MeshPublications` owns canonical SHA-512 public
bundles, retained owner copies, verification caches and quarantined relays.
Only its verified entry into `CommunicationCoordinator` can apply a relayed
record to the existing domain stores. A copied confirmation from another peer
is never authority for the claimed origin.

Generation-3 `QuestTogether3` and `QuestTogether3Z<zone>` channels are membership
directories only. Display-list indices and native channel IDs remain distinct.
Directory selection is guarded, restored and deferred while unsafe. Missing,
suspended or incomplete directories are degraded discovery, not a reason to send
channel payloads. `Transport` does not admit the CHANNEL distribution. Bootstrap
also uses party/guild contacts and up to 64 public peers saved for 24 hours per
character/client/region. Private diagnostics never supply saved seeds.
If combat interrupts selection restoration, one bounded cleanup record retains
channel names across graph resets. A native event retries it when safe, resolves
current display indices, and yields to a user's intervening selection.

A node keeps at most 512 candidates, 8 confirmed neighbors and 3 simultaneous
handshakes. Introductions carry at most 8 addresses, without establishing presence,
location, credentials or party membership. New probes run every 20–30 seconds after
three staggered initial probes; unanswered candidates wait 5–30 minutes. Directory
scans refresh every 5 minutes, processing 32 rows per paced tick and 1,500 per cycle.
Cycles share the row allowance across active directories and rotate both the
first directory and each directory's starting roster row. A large global roster
cannot permanently exclude zone rosters or members beyond its first 1,500 rows.
Geographically useful contacts coexist with randomly selected connecting contacts.
An eligible connection rotates at most once per 120 seconds.
Admission reserves slots for reciprocal handshakes before acknowledging them;
busy peers decline without offering unusable introductions. Reservations expire
and do not establish a confirmed edge or accepted player data.

Native whispers can be accepted locally and later produce a player-not-found
system notice. A bounded, transport-lifetime ledger correlates the localized
notice with actual QT whisper attempts for 30 seconds. Ordinary whisper intent
keeps ambiguous notices visible. Correlated failures retire only routing state,
cancel that target's queued whispers, and hold further sends for 60 seconds;
discovery retains its existing candidate backoff. An eligible native-origin
packet clears the send hold before replies, without renewing domain data.
Chat filters suppress only correlated notices; failures remain counted in QT's
diagnostics. Missing hooks, unreadable values, and uncertain matches fail open.

Interests have 120-second leases renewed every 40 seconds with new immutable query
identities. Each query forwards once, to at most 3 neighbors with an 8-hop limit;
duplicate arrivals may provide alternate paths. Public payloads follow subscribed
reverse paths. The origin, session, publication identity, source timestamps,
expiry, scope and payload remain unchanged across all hops. Ordinary unknown
bundles stay quarantined until their author directly confirms the exact digest
from its own retained public outbox, or they expire. Confirmations are batched;
exact verified copies and direct owner payloads avoid redundant authentication.
Existing pinned-key DEVANN, authorized broadcast PING and VIP proofs use their
signed identity fields for ordering and expiry instead of unsigned outer fields.
Broadcast PING verification and forwarding do not require diagnostics consent.
The reply handler consumes the verifier's sanitized request, and creates a private
Pong only with current consent and the diagnostic generation captured at admission.
Opt-out preserves pending public signature checks while cancelling private work;
turning consent back on cannot revive those retired replies. Session shutdown
still cancels all verification and relay work.
Private replies, hidden locations, developer mirrors, party snapshots, focus and
waypoints never relay. There is no discovery or delivery guarantee across islands.
Renewed interests rotate destinations independently per requester and scope, with
at most 64 selection histories expiring after 120 seconds. An interest received
while an owner publication is hashing or sending waits for that exact publication
to become ready; cancellation and expiry still prevent replay.

Developer announcement subscriptions use the separate `QTDEVFEED2` signature
domain, binding sender, request identity, issue time, action, session and target.
Local developer identity plus a private signer starts the subscription;
`devlogall` remains only a presentation filter. All clients publish a compact
public `HELLO` on startup/re-entry. A developer publishes
`DEVANN` globally, renews every 90 seconds, and coalesces arrivals into reoffers
no more often than ten seconds. Reoffers reuse the signed record and envelope;
verified request identities suppress repeated crypto work. Authentication owns
subscription replay admission, allowing a previously capacity-rejected offer or
an offer after a local profile/session reset to be retried. A lease ends 240
seconds after its signed issue time, never 240 seconds after delayed receipt.

Only clients allowing developer diagnostics add whisper audiences to ANN/LVL.
They reuse the original sanitized payload and envelope, including public location
sharing restrictions. Public/group and private copies deduplicate as one event.
The same verified subscription receives separate `DLOC` snapshots, initially
after a short jitter and then every 30–45 seconds, including while stationary.
These private state records can only use a live consent-bound whisper route;
they cannot be embedded in public state or ordinary announcements. The developer
retains issued offers for their lease so renewal does not reject in-flight data.
DeveloperDiagnostics applies normal peer session, sequence and source-time fences.
Publicly shared coordinates refresh ordinary location state; hidden coordinates
remain only in its separate 512-player private store and expire after 120 seconds
from sampling. Unavailable or newly public samples clear the prior private dot.
No manual ping or `devlogall` display setting is needed for this feed.
Consent, ignore, profile replacement, departure and session shutdown fence queued
copies and delayed authentication. Signature verification rechecks peer departure
ordering before installing a lease. This does not provide historical replay or
messages from clients in disconnected networks or older unsupported versions.

Mirrors use the existing background class and budgets, at most four outstanding
copies and four subscribed developer recipients per client, shared by announcement
mirrors and location snapshots. Receiver processing allows 32 developer datagrams/second, burst 16 and at most eight per frame before
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
Both zones advertise mesh interests and supply directory membership. Public
state coalesces into windows of at least 5 seconds; events become eligible
immediately and can expire under congestion. Slower global baselines preserve
progressive background coverage and original per-field source freshness.
Nearby streams keep four leases, with
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
transfers and borrows unused capacity. A selected ready turn earns byte credit
before smaller packets can spend it. Mesh traffic has its own class/destination
rotation and appears as one stable flow to the shared scheduler. Waiting for the
mesh sub-budget does not block private traffic. `AddonMessageThrottle` pauses the prefix
for one second and reduces its packet rate to one/second. Thirty seconds of
successful active traffic recovers 0.5/second, capped at four; idle time earns no
rate recovery. `ChannelThrottle` is an ambiguous native outcome and is not
resubmitted automatically. Native acceptance never claims remote delivery.
Tickets settle exactly once, including replacement, cancellation and expiry.
Hard native send failures are logged in QT diagnostics without invoking WoW's
global error handler or installed bug catchers. Repeated failures are limited to one report per fixed
route/result bucket per minute; every attempt remains counted. Normal throttle
backoff and ambiguous results are not reported as definite send failures. A
rejected request ends its loading state without waiting for a remote timeout.
Directory refusal notices update bounded discovery diagnostics. They never
produce channel-send retries or global error popups. Mesh traffic, including
fragment control and origin confirmations, has a sub-budget of 1 packet/s and
200 bytes/s within the shared budget (burst 2 packets/400 bytes). At most 24 queued
mesh packets and 8 outgoing mesh transfers (at most 6 for replaceable state) leave capacity for actual party and
private work. Public bundles are at most 8 KiB; retained mesh payloads reserve up
to 128 KiB inside the existing 512 KiB aggregate transfer/cache ceiling. Routing
history is bounded and expires. Diagnostics report counts, ages, hash time,
authentication latency, queue bytes and outcomes without names or payload text.
Mesh assembly requires a confirmed edge or a correlated response where applicable.
Unknown peers may occupy at most four discovery/authentication request assemblies,
leaving the other mesh slots available. Fragment arrival never extends a mesh
request's original deadline. Publication retirement cancels its hop work, removes
authentication/hash references and settles its completion exactly once.

State samples replace older queued samples for the same topic/audience. Events
retain immutable identities and finite duplicate suppression. Requests preserve
identity across bounded retries; accepted actions cannot prompt or act twice.
A transiently busy receiver must not tombstone an unaccepted request. Immutable
cached responses can replay after loss without rereading a changed domain
snapshot. PQL installs complete snapshots atomically and reuses only an exact
revision; objective detail is a separate request.
Party log, objective-detail and completion-history exchanges use the current
PARTY, RAID or INSTANCE_CHAT distribution for group members. The logical recipient
is separate from the native route; request correlation and roster lifetimes fence
group fan-out, response replay and repair. Comparisons outside the group retain
whispers within generation 3.

Large transfers share one fragment format, validate correlation before allocating
response buffers, and interleave across recipients. Completion/END starts missing
fragment repair, with at most two rounds. Thirty seconds without progress and a
missing END permits a bounded status query. Queueing alone is not packet loss.
The original request bounds transfer lifetime to at most 600 seconds. Retirement
releases buffers on completion, cancellation or expiry. Oversize and capacity
failures are explicit; requested fields are not stripped to fit.
Abandoning a partial quest response sends a recipient-validated cancellation to
release its sender's queued work. Cancelled-response tombstones repeat that signal
when a later END arrives. Under capacity pressure, fully sent, idle QCRS recovery
copies may be reclaimed after a five-second grace; active sends/repairs and
diagnostic transfers are not evicted. Lost acknowledgements or abandoned hovers
must not reserve every outgoing slot for the full response lifetime.

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
Quest traffic retains fixed operation/route/native-result counters, and the
comparison owner exposes bounded request and response-job counts and ages without
player identities or quest content.

The private multi-peer network harness runs actual coordinators with independent
clocks/state, frame-rounded timers, asynchronous channel joins and delivery
separate from native acceptance. It exercises loss, reorder, duplicates, throttle,
ambiguous outcomes, low FPS, mixed workloads and lifecycle changes. Run the
[live communication release gate](docs/COMMUNICATION_LIVE_TESTS.md) before publishing
the major upgrade; offline results alone do not validate real delivery or coexistence.

## UI and client boundaries

`DataBroker.lua` registers a `QuestTogether` launcher only when another addon has
already supplied LibDataBroker through LibStub. Neither library is bundled or
declared as a required/optional TOC dependency. Login and late addon loads retry
discovery; the existing launcher recovery events retry after restrictions.
Registration is idempotent, and QT never replaces another object's name. Library
creation and proxy updates are isolated because they synchronously notify other
addons. Only QT's created object receives primitive display fields and callbacks;
the addon/profile/peer tables never become broker attributes.

Left/right actions are profile settings: Party Quest Log, menu, LFQP toggle,
settings or none, with log/menu defaults. They reuse existing feature commands
and validate restrictions when clicked. The broker remains usable with the
minimap hidden and retains menu/settings access while QT is disabled. Identity
artwork, enabled state and LFQP text refresh from existing feature transitions.
The display owns tooltip lifecycle; QT only adds lines through its public tooltip
API after forbidden/protected/restriction checks. No fields, scripts, positioning
or visibility changes are written to a display-owned frame. Live tests detach
broker state and block the real registry adapter; fixtures own their registries.

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

Keep a test when the failure it catches justifies its fixture and maintenance
cost; uniqueness alone is not enough. Prefer the real producer/receiver or
UI-event fixture over another test of mocked method delegation. Do not add
standalone cases for every constant, cosmetic choice, fictional preview detail,
getter or forwarded argument. Shared validators need representative valid and
invalid behavior at their owner, not a fresh exhaustive matrix in every caller.
Keep layered coverage only where the integration adds a meaningful failure mode;
retain authorization, data-loss, source-order, lifecycle and restricted-access
boundaries even when their outcomes look similar. A table-driven case is useful
only if each input actually changes the exercised path. Test names must be unique; the offline harness checks
the complete registered suite before selecting any subset.

Negative cases need valid positive controls. Begin malformed protocol cases with
valid current-generation records, establish active state before testing expiry,
and reorder at least two distinct items. Count forbidden calls outside protected
callbacks: an error-only stub can be swallowed by production `pcall`. Use the
controlled clock for timers rather than running delay callbacks inline. Expected
wire sizes, contents and outcomes must not simply reuse the implementation being
tested to compute their answers.

`lua scripts/test.lua . locale` runs every case tagged `locale = "client"` in
the selected `QT_TEST_LOCALE`. CI uses that subset for each additional locale;
the full default and reverse runs already cover the fixtures that force English.
Python-only validators run once in CI. Generated release-note Lua, bindings and
crypto checks still run under both interpreters because they execute Lua code.
Avoid fixed test/catalog counts and exact UI geometry assertions unless those
numbers are the product contract and the fixture actually models that behavior.

`scripts/package.py` derives installed Lua from the TOC and includes only the
explicit runtime asset/document rules. It checks pinned dependency hashes and
verifies every archived payload. Release builds use an immutable `--ref`;
working-tree builds are previews. See [RELEASING.md](RELEASING.md).

Offline success proves these contracts under fixtures. It does not establish
in-client rendering, taint safety, SavedVariables migration with real data,
network delivery or behavior with other addons. Keep those checks explicit.
