# QuestTogether client compatibility

One source tree supports these current client families. Interface metadata permits loading; API capabilities still decide which adapter can run. PTR/beta builds in the same family use those adapters when their contracts match. This does not claim support for arbitrary historical/private-server clients.

| Client family | Source snapshot | Interface targets |
| --- | --- | --- |
| Retail | Installed 12.1.0.69933 UI export | 120100 (existing older Retail targets retained) |
| Forever | Installed 1.60.1.69977 UI export; 1.60.1.70009 spell data | 16001 |
| Era / Hardcore / Season of Discovery | [1.15.9.69722](https://github.com/Gethe/wow-ui-source/tree/33e177d9bf38d76d5c6c6e05d5da78db1899659a) | 11509 |
| Anniversary / Burning Crusade | [2.5.6.69795](https://github.com/Gethe/wow-ui-source/tree/1463c686270b6c64e2c5c228f447c4597c0f8ba6) | 20506 |
| Mists Classic | [5.5.4.69934](https://github.com/Gethe/wow-ui-source/tree/cde55d0033e89b246381385b2f063cd6c6047ef8) | 50504 |
| Titan Reforged (China) | [3.80.2.69874](https://github.com/Gethe/wow-ui-source/tree/84ef503f0d2617494db84cc9c7e7b530e976f6e7) | 38001, 38002 |

The Classic references are mirrored Blizzard UI/API source. Source inspection and offline fixtures establish expected contracts, not engine-level taint safety, rendering or gameplay validation. Live nameplate transitions and two-client quest synchronization require separate checks. No live test result is inferred from these fixtures.

The minimap launcher uses an addon-owned button and tooltip, with a transparent 128×128 TGA generated from the scroll group in `logo.svg` by `scripts/build_minimap_icon.py`. Its guarded Minimap parent supplies position and scale; no scripts or addon fields are installed on Blizzard frames. Drag state is stored separately so an inaccessible parent can cancel the drag without touching quarantined children. Position and visibility are profile settings. Settings > Groups & Sharing > Show minimap icon controls visibility. The minimap menu can hide it and prints a local chat message explaining how to restore it through `/qt options`; a restricted or rejected click cannot report a successful hide. An independent event frame restores deferred layout/visibility after restrictions, including while announcements are disabled. Left-click toggles the Party Quest Log (including closing its preview); right-click opens the menu, including Settings. Shift-click still toggles looking for questing partners. The localized tooltip lists these actions. Menu actions recheck restrictions on click, including the shared chat-window destination action.

The launcher's generic journal action uses the non-toggle `OpenQuestLog()` entry point present in both installed Retail and Forever UI exports (`Blizzard_WorldMap.lua`), then verifies that the map and quest log are visible. It does not select a quest or require a populated details frame. Live tests substitute addon-owned wrappers; native opener contracts are covered only by offline client profiles. Before release, check the icon/menu, drag persistence, profile visibility, minimap scaling, both journal states and restriction recovery in Retail and Forever, with blocked-action/taint reporting enabled.

Player Plates uses an independent enabled-by-default `nameplatePlayerIconEnabled` option and `nameplatePlayerIconStyle` (Left by default, plus Right, Top and Prefix). Friendly visible player units must match an authenticated QT sender recognized during this UI session, with a readable name/GUID. Native friendly-player visibility is read from `nameplateShowFriendlyPlayers` on current Retail and Forever, falling back to `nameplateShowFriends` only when the modern key is absent. Explicit modern Off overrides legacy On; unreadable values fail closed. Ignored players and self are excluded. The player logo reuses the addon-owned quest-icon pool with separate artwork/style state, adds four pixels of horizontal spacing beside bars/text, and never creates a health tint. Recycled creature/player plates switch artwork; removed plates and departed or evicted peers use owned cleanup handles, including when native lookup is already empty. Protected/forbidden layouts defer to the existing cleanup/recovery path. Instance and restriction policy remains the same as quest plates; no nameplate CVars are changed.

The versioned `QTPR` presence message has no coordinates or claimed sender identity. The existing update frame uses one presence slot every 20 seconds, alternating unchanged QTPR and QTVR packets for discovery and compatibility; each format repeats every 40 seconds. All twelve supported incoming message types can identify their authenticated transport sender after validation: ANN, LVL, PING, PONG, QCMP, QCQE, QCDN, QSHR, QTPR, LOC, QTLF and QTVR. Comparison/share recipients and payload names never identify somebody else. Valid requests/replies can identify a sender even when their action is addressed to another player or the local request has ended. Rejected routes, malformed payloads, ignored senders and obsolete ordered LOC/QTLF updates do not establish recognition. Positive location publications and QTLF On identify an active addon. LOC mask-0 withdrawals and QTLF Off preserve existing recognition but cannot establish or restore it; an explicit QTPR departure removes recognition. This remains true when departure and withdrawal packets arrive in either order across routes. The bounded registry retains up to 512 players until the UI session or comms state resets, evicting the least recently heard sender when full. Missing heartbeats alone do not erase identification. Locations and looking-for-partners status still expire independently. Location sharing may be off without suppressing player identification. Disable/logout sends best-effort departure; local disable resets the registry. No additional traffic is generated by recognition. `UNIT_NAME_UPDATE` and queued health refreshes recover missing identity without scanning player quest tooltips. Unit existence, player and friendship API flags are checked for accessibility before branching.

**Looking for Questing Partners** is an optional profile setting (`lookingForQuestPartners`, default false). `/qt lfg [on|off|toggle|status]`, the minimap checkbox, and Groups & Sharing settings share that setting. Coordinate-free `QTLF|1,<session>,<sequence>,<0-or-1>` updates use authenticated existing announcement routes. Session/sequence ordering rejects delayed route copies; up to four prior sessions per peer remain retired. Older peers still receive unchanged `QTPR` presence and ignore the new command. On heartbeats every 20 seconds; Off is silent by default except explicit setting changes and bounded withdrawal retries while the last successful On can remain visible (65 seconds). Only explicit partner updates renew status: ordinary announcements, pings, and presence do not. At most 256 status records are retained. Off/departure records retain ordering until expiry, so delayed On copies cannot undo a withdrawal. Ignore pruning and comms reset clear records. Every legacy QTPR transition is applied without content deduplication; ordered QTLF remains safe to deduplicate. Ordered partner status is independent of legacy presence, so a delayed old QTPR departure cannot clear a newer QTLF On after rejoining. Disabling/logging out sends a best-effort ordered Off before legacy departure and stops updates. A saved On preference resumes after re-enabling or reloading. No automatic invites, public recruitment messages, or location-consent changes occur.

LFG map/minimap tooltips can also show the sender's single super-tracked quest. The read-only adapter uses `C_SuperTrack.IsSuperTrackingQuest()` and `GetSuperTrackedQuestID()` behind restriction/access guards; waypoints, missing APIs, inaccessible values and invalid IDs publish no quest. Optional `QTLQ|1,<session>,<sequence>,<questID-or-0>,<escaped-title>` packets accompany the existing 20-second partner heartbeat only with LFG and location sharing enabled. A prior publication gets bounded clear retries for 65 seconds. Only that quest ID and a bounded fallback title are transmitted, never objectives or other quest-log contents. Viewers prefer a localized title through the existing bounded title cache, then the sender’s title, then the quest ID. Fallback text is escaped for display; oversized titles are omitted without splitting UTF-8 or percent escapes. Scalar super-track reads remain available while the map is open; native title lookups retain the existing map-sensitive restriction guard. Legacy LOC/QTLF formats stay unchanged. The receiver retains at most 256 quest records for 65 seconds and displays only a record matching the current LFG session and sequence, tolerating either packet order without resurrecting old quests. Quest packets alone never establish presence or renew LFG. Reset and ignores clear this state. Offline tests cover both UI surfaces and native adapter contracts; actual super-tracking and two-client delivery still require in-game validation on Retail and Forever.

The minimap tooltip is parented independently of the minimap to guarded UIParent and uses its own TOOLTIP strata and frame level. The button supplies only the anchor. An owned update callback checks visibility while shown and retries quarantined hides; no Blizzard frame state or scripts are changed. Native draw order still needs an in-game check with the user's action-bar UI.


Direct player-logo refreshes also enforce the shared `nameplate_refresh` work policy. Map-sensitive and noncombat restrictions queue generation-checked refreshes; map-close wakeups still recheck encounter restrictions, and removed tokens cannot revive stale icons. Ordinary open-world combat continues to allow unprotected icons. Cleanup uses the existing owned-handle guards.

Left-positioned player logos use the guarded `AurasFrame.BuffListFrame` anchor when it contains visible buffs. Both installed Retail and Forever exports grow this list leftward from the classification marker. Empty lists remain shown with nonzero width, so occupancy uses bounded, accessible child visibility instead of container width or aura contents. The stable list anchors the logo, with compact padding that follows aura scale; pooled aura children are never retained. Missing, hidden or inaccessible layouts retain the normal bar anchor. `UNIT_AURA` coalesces existing player-logo refreshes through the next-frame, restriction-aware scheduler, after Blizzard's layout. NPC aura events do not schedule quest scans. No foreign fields, layouts or scripts are modified.

Before release, enable friendly nameplates on two updated clients and check all four player-icon positions, the Player Plates preview/toggle, location sharing off, ignore/unignore, disable/re-enable, explicit departures and recognition after a long quiet period. Add/remove one and two visible buffs and change aura scale to check outward spacing and return to the normal anchor. Test plate recycling between players and creatures, delayed names, combat and instance transitions with blocked-action/taint reporting enabled. Live rendering and engine permissions remain unverified.

Player Locations has two independent profile options: **Share my location** (`sharePlayerLocation`) and **Show other players** (`showPlayerLocations`). Each controls both world map and minimap and defaults to true. **Only show players looking for questing partners** (`onlyShowQuestPartners`) defaults to false and filters both surfaces using fresh explicit QTLF status. Existing profiles migrate before defaults: either old sharing switch Off keeps combined sharing Off; either old viewing switch On keeps combined viewing On. Explicit new values win. Old per-surface keys are removed. Incoming legacy LOC masks still restrict where a peer can be displayed; the combined local sharing option publishes mask 3 or 0.

The versioned `LOC` packet uses the authenticated transport sender and bounded primitive metadata. Positions are sampled at most every five seconds, moving positions broadcast at most every ten seconds, stationary positions heartbeat every 20 seconds, and peers expire after 120 seconds. At most 512 peer records are retained. Sharing changes publish immediately. Transient unavailable/restricted position reads pause publication without withdrawing or renewing the last reported point. Disabling sharing removes coordinates, map ID and zone from quest announcements and ping replies. Withdrawal is best-effort when communication itself is restricted; remote expiry bounds stale dots.

LFG dots use four pooled translucent gold circles that fade outward around the unchanged class-colored center, filling a 16-pixel footprint instead of the normal 12-pixel black border. Projection clips the complete halo; pooled dots revert on status expiry or reuse. Player logos use eight pooled, additive copies of the transparent logo behind the original artwork, offset by four pixels to create a gold contour glow around the unchanged logo. The brighter glow uses pooled native alpha animations with a 2.4-second breathing cycle; the logo itself remains steady. Unsupported animation APIs keep a bright static glow, and status removal stops the pulse. Only addon-owned regions change, under existing visibility/restriction guards. Accepted partner updates and pruning schedule guarded nameplate refreshes when the displayed status changes or an owned glow needs recovery; map refreshes use the current partner state. The LFG-only filter applies to maps, not ordinary QT player logos.

`QTVR|1,<installed-version>` advertises only the sender's installed addon version over existing routes. The existing update frame sends an initial version advertisement and then reuses every other 20-second presence slot, so versions repeat about every 40 seconds without extra heartbeat messages. Older QTPR parsers reject extra fields, so both wire formats remain intact. The separate 300-second version fallback is normally suppressed by successful heartbeat versions; failed attempts remain paced at 20 seconds. No request/reply exchange or forwarding occurs, and legacy QTPR remains unchanged. Valid version packets also identify the authenticated QT sender. Existing validated PONG packets can supply versions even without an active local ping. Self, ignored, disabled, malformed and unrelated-route traffic is excluded by the common receive boundary. Numeric major/minor/patch and supported alpha/beta ordering are compared rather than strings; only stable peer releases create update notices. These are peer reports, not online release-catalog verification. Account-wide `availableAddonVersion` and `addonUpdateAvailable` retain the highest newer stable report. Login reconciles installed metadata and emits one chat reminder per UI session, even with runtime announcements disabled; installing that release or newer clears the record. Profiles and comms resets cannot repeat a notice within the session. Unknown local metadata preserves the remembered version until it can be compared.

Location overlays, pooled dots and tooltips are addon-owned; no state, scripts or providers are added to Blizzard frames or shared map registries. Native geometry reads are guarded for restrictions, forbidden frames and inaccessible values. World-map placement follows the current canvas rect, zoom, pan and scale. Cross-map projection checks the actual returned map ID and rejects distinct floors belonging to the same map group. Minimap placement uses `C_Minimap.GetUiMapID` when present, falling back to the player's current `C_Map.GetBestMapForUnit("player")` map when the UI-map getter is absent or returns nil. An explicitly invalid or inaccessible minimap map ID does not trigger fallback. Offline geometry profiles exercise the nullable native return, explicit hybrid-map precedence, and unavailable/restricted fallback data. Placement also reads `GetViewRadius`, map/world conversions and player facing; the rotation CVar is combined with `IsRotateMinimapIgnored` for HybridMinimap. Unsupported geometry, unknown masks or unavailable conversions hide markers. No mutation or CVar write is used to force a projection. Empty surfaces avoid native geometry work. These APIs and map-group/rotation behavior were checked against the installed Retail and Forever UI exports; they do not establish native rendering on either client. Dots identify recent reported positions, not matching phase, layer or instance membership.

While the addon remains enabled, withdrawals retry on all current routes every five seconds until the last successfully published position reaches its 120-second lifetime. Any-route success does not prematurely suppress retries for another failed route. Retries contain no old coordinates and stop at expiry even when every send fails. Disable/logout still makes only a best-effort immediate withdrawal before stopping runtime work. Native geometry fixtures count forbidden read attempts before raising errors and assert zero outside production's `pcall` boundary.

Whisper validates the menu owner's accessible chat edit box before passing a preferred chat frame to Blizzard. Map/minimap dots instead pass no preference, allowing native selection of the active/default chat window. Native failure returns false; a successful void-returning invocation returns true. Offline contracts cover real chat owners, dot-menu callbacks, forbidden/inaccessible owners, classic and instant-messenger modes, and modern/legacy entry points. Primary-source Retail/Forever chat functions were also exercised separately offline.

WoW ignore checks apply at transport and presentation boundaries, including developer all-announcements logging. `IGNORELIST_UPDATE` clears ignored peer locations and active bubbles and cancels their pending comparisons/share requests. Unavailable bubble or pin handles are quarantined for owned cleanup; new playback cancels stale cleanup. Existing historical chat lines are not removed. Pin hover/click revalidates visibility, ignore state, map context and restrictions before showing player details or opening the common QT menu.

Before release, use two updated clients to check map zoom/pan, minimap scale/rotation, different floors, stale expiry, Share my location, Show other players, the partner-only filter, profile changes and disable/re-enable. Check ignored players through both QT and the native ignore UI, existing visible bubbles, player tooltips/menus, and two-player comparison outside a party. Check restrictions and recovery with blocked-action/taint reporting enabled. These live checks remain outstanding.

`QUEST_ACCEPTED` accepts either `(questID)` or Classic's `(questLogIndex, questID)` payload. A secret second value is rejected rather than interpreting the log index as a quest ID. Acceptance waits for an actual `QUEST_LOG_UPDATE` and a readable row whose quest ID matches. Missing or recycled rows stay pending until a later update; removal, turn-in and runtime reset cancel obsolete work. Deferred acceptance, deduplication, snapshots and communication identity remain shared.

Quest enumeration retains legacy `GetQuestLogTitle` and modern `C_QuestLog.GetInfo` paths. Legacy completion `1` means complete; `nil` and `-1` do not. An explicit modern `false` takes precedence, while a missing modern completion field may use legacy data. Objective reads support the legacy by-ID function, structured `C_QuestLog.GetQuestObjectives`, and the older indexed leaderboard API. Foreign tables/values are access-gated before use. Existing snapshot completion status remains available when Classic lacks Retail's named completion APIs.

Ready-to-turn-in tracking preserves unknown readiness separately from a readable false.
Initial scans silently baseline quests that are already ready or have completed objectives,
even if the readiness API has not caught up yet. An unknown-to-ready observation is also
silent. A confirmed unfinished-to-ready transition announces once per tracked quest
lifetime; rescans and temporary false/unknown reads cannot replay that milestone.
Live false still updates status displays. Removal/reacceptance and addon re-enabling
start fresh tracker lifetimes. No polling, extra communication, or native mutations are
added. If every available API reports an unfinished quest during loading, that cannot
be distinguished from genuine unfinished state until more data arrives.

An initial scan with an unreadable row or count remains pending until a later quest-log event supplies usable data. Recovery uses the existing scheduler and respects runtime and map restrictions; it does not poll unreadable data and is canceled on disable. Pending acceptances retain ownership of their tracking and readiness checks while recovery initializes other quests. Area-entry announcements remain eligible when task metadata becomes readable during the recovery scan, including after another acceptance has already refreshed area state.

Classic `GetQuestLogPushable()` refers to the currently selected quest. QT reads it only when that selection already matches; it never changes the user's quest selection. Unavailable shareability is displayed as **Unknown**, not an incorrect **No**.

Quest-name clicks open a menu with Share, Open in Quest Log, and Party Quest Log. Log-window destination changes are available in the minimap menu and settings, not the player-name or quest-name menus. Sharing requires the modern quest-by-ID lookup and shareability APIs, a current matching quest-log row, a group, and unrestricted runtime state. Legacy-only sharing remains unavailable rather than changing the selected quest. Each click rechecks eligibility and the current log index; restricted actions are not queued. Native invocation confirms an attempt, not another player's acceptance. Status and comparison messages retain clickable quest names. Status fallback titles are extracted from the matching quest ID in the clicked chat message, excluding speaker/coordinate links and announcement wording. Older nested status links can recover their inner quest title; unrelated or incomplete links fall back to the known title or quest ID. Live tests use private menu/output fixtures; the offline runner now models the native pure Lua hyperlink formatter so rendered brackets are exercised too.

Party Quest Log in the minimap and quest-name menus opens the addon-owned window (also `/qt compare`). Its parchment scroll artwork is an addon-owned texture, and it does not inherit Blizzard window scripts or modify the vendored library. The window initially shows eleven row heights, with a reusable frame pool that grows with the viewport to accommodate partially revealed rows with class-colored headings, column accents, and readiness summaries. Search matches quest IDs and both localized and received quest names; ownership, progress and action filters combine without extra communication. Filter choices persist per profile; the former hide-other-quests preference maps to “Quests I have.” Search persists through Refresh within a session. Reset clears all filters. Missing requires a complete snapshot; incomplete, failed and timed-out reads remain unknown. Refresh cancels the previous comparison generation, and roster changes discard departed players. Scrollbars appear only for actual overflow; filtering and roster changes clamp offsets.

Location rendering examines up to 512 candidates per surface and renders at most 128 visible dots, rather than letting off-map names consume the rendering quota. Hover and click validation use the same 512-candidate bound. Tooltips show update age for points at least 30 seconds old. Retained points are last reports, never extrapolated or retransmitted stale coordinates. The longer receiver lifetime tolerates missed heartbeats; the unchanged 20-second heartbeat remains compatible with older receivers' 45-second expiry. More than 512 active records or 128 visible dots per surface can still exceed the bounded UI/cache capacity. Native geometry failures still hide a surface rather than anchor dots using unverified map/viewport data.

**Retail versus Forever:** regional full identities are retained for communication, ignore checks, comparisons, player menus, dots and plates. Existing Forever First-Surname profile storage keys are preserved, but missing-name fallbacks never invent a realm. Forever does not read or display realms or War Mode, even for legacy peers' dummy fields. Other clients require a readable `C_PvP.IsWarModeFeatureEnabled()` result before sampling/displaying War Mode; the native Active value is used rather than Desired. Unknown metadata stays unknown. Coordinate-based announcement proximity checks War Mode only when supported and otherwise retains map/distance checks; unreadable capability cannot establish proximity. Map dots are never filtered by phase or War Mode. Geometric floor checks remain necessary for accurate map projection.

The installed Forever API exports contain no verified four-way Normal/PvP/RolePlay/Hardcore getter/enum. `UnitGetAvailableRoles` means tank/healer/damage; `C_GameRules.IsHardcoreActive` is only a boolean. No role label is inferred from either API or a realm name. Supporting those tooltip labels needs a verified native contract. A compatibility review receipt and source evidence are recorded under `.local/reviews/client-paradigm-2026-09-28/` and `.local/reviews/forever-paradigm-2026-09-28/`; tests remain private/addon-owned and native contract mocks remain offline.


The player-name menu's **Compare Quests** instead opens a two-player session containing only the local player and the selected target. Map dots use this same menu. Current group members use the group route; other targets use the existing QT channel. Refresh and roster changes preserve the selected target, and ignored targets are rejected. Share and Request Share remain available only when the target is currently in your party. Local snapshots opened from a world-map dot can remain deferred until the map closes; the window explains this instead of displaying a false empty snapshot. A nonparty comparison requires a reachable QT peer on that channel; this does not add a cross-realm whisper transport.

`/qt preview compare` (also `/qt compare debug`) opens a five-player preview even while solo or the addon is disabled, when UI restrictions permit. It uses your current quest log plus four simulated teammates and extra missing quests. Its focus controls deliberately affect real navigation; sharing and request actions remain simulated. The filter menu can simulate incomplete snapshots, and Refresh reads your log again and resets the simulated party. A fully fictional fallback is used only when native adapters or the local snapshot are unavailable. See the native preview boundary below. Actual rendering still requires live-client validation.

The comparison's local snapshot uses the existing map-sensitive deferred work class and checks session identity before reading. Hiding UIParent preserves the window's session; an explicit close cancels it. Updated responders replace obsolete queued replies for the same authenticated requester while preserving other requesters, pacing and queue bounds. A per-owner request cooldown only schedules a UI refresh, never a later request or native share. Valid new requests rejected by admission limits receive an unavailable response; request replays remain suppressed. Terminal feedback stays visible while retry is enabled, and the automatic-sharing checkbox refreshes from the active profile.

`/qt help` lists normal commands. `/qt help debug` lists diagnostics, tests, previews and developer commands; displaying help performs no debug actions.

Welcome and latest patch notes use an addon-owned window with the same texture-only WoW artwork as the debug and comparison windows. The scroll logo appears above the welcome heading. Opening Settings from the window closes it; an unavailable or failed settings action leaves the notes visible. It replaces the login chat welcome. Account-wide `releaseNotesSeenVersion` records only a successfully visible presentation: first use and higher major/minor series open automatically, while patches, prerelease promotions within a series, repeated logins and downgrades do not. Presentation waits through runtime restrictions and hidden UI using an independent owned listener, including while announcements are disabled. A failed render does not trigger a repeated render loop or acknowledge the version. `/qt notes`, `/qt changelog`, `/qt patchnotes`, the minimap menu and the main Settings screen open it manually. Private controller/UI fixtures cover gating, actual visibility, recovery and scrolling without modifying client globals. Native rendering and restriction/taint behavior still require checks in Retail and Forever.

**Discord — Feedback & Support** appears in both the welcome window and main Settings page. It opens an addon-owned copy-link window with the permanent invite https://discord.gg/Uxyyvhfva9. Successful opening closes the welcome window; Settings remains underneath the raised copy window. Restricted clicks do not queue an external action. This only displays a copyable link; it does not launch a browser or send Discord messages.

`release_notes.json` is the canonical versioned content; `ReleaseNotes.lua` contains generated primitive data. CI checks exact generated bytes, TOC version agreement and content changes against reachable release history. The release script checks the current release baseline before mutation or remote access and updates the TOC and notes together. `RELEASING.md` documents generation and the read-only `--check` preflight. Every release needs updated notes, including patches that do not automatically open the window; content accuracy still requires review.

Party share requests use a separate versioned, group-only message with transport-authenticated sender, explicit target, quest ID, correlated request ID and bounded lifetime. A new optional `share1` capability on comparison completion preserves older comparisons while disabling Request Share for older senders. Requests ask by default. Confirming with “Always allow party share requests” saves the profile setting; Groups & Sharing can toggle it later. Both automatic and manual approval recheck current party membership, quest ownership, shareability and restrictions. A failed automatic invocation falls back to confirmation, never to a retry loop. Native invocation reports only “Share attempted”; it cannot establish delivery or acceptance.

The installed Retail and Forever UI exports call `QuestLogPushQuest(questLogIndex)` from `QuestUtil.ShareQuest`. [Azeroth Pilot Reloaded's event handler](https://github.com/Azeroth-Pilot-Reloaded/azeroth-pilot-reloaded/blob/cc2b743f004ff79e1f8660de177f90264558043f/APR-Core/core/Event.lua) also attempts automatic sharing from its quest event flow. That is evidence for automatic sharing in addon code, not a proof of engine permission on every build. Validate the opted-in automatic path separately in Retail and Forever, along with native recipient prompts and blocked-action/taint reporting. The default manual confirmation remains available.

Comparison messages retain all three shareability states. Updated receivers accept the existing class-bearing and older classless layouts; known values still use `1`/`0`, and unavailable values use an empty field. Older receivers still interpret unavailable values as No, so both clients need the update for Unknown to display correctly. Combat, map and encounter restrictions defer comparison snapshots without spending unreadable-data retries; queued replies still expire and cancel on disable or requester departure.

Announcement v3 appends an optional map ID after the existing fourteen fields. Updated peers compare valid map IDs before coordinates, regardless of localized zone labels. If either peer lacks a valid ID, the existing zone-label fallback remains. Old receivers continue reading their original fields. Oversized zone labels can be dropped while numeric location remains available. `/qt bubbletest` previews only on the local client; it never sends another player's identity over the network, and receiver authentication is unchanged.

Remote completion and level-up emote tokens are normalized and checked against a private snapshot of the shipped local celebration list. Remote emotes also require a current target/mouseover/focus/nameplate unit whose identity still matches the sender. The native adapter requires accessible UnitExists, UnitIsPlayer and UnitIsVisible results, and rejects a phase mismatch when UnitPhaseReason or legacy UnitInPhase is available. A map coordinate or sender name alone cannot trigger an emote, including with devlogall; restricted or unreadable cases are skipped without retry. Self celebrations retain their existing independent path. Tokens outside that list, including mountspecial and the faction cheers, are ignored without a replacement emote. Unsupported tokens cannot invoke arbitrary local emotes, while authentication, proximity, player scope and reaction options remain required.

All current Classic nameplate XML uses the shared health container and base-unit access used by the addon; existing guarded legacy anchoring and tooltip/Questie fallbacks remain. Settings, the diagnostic console, surname-aware display and full communication identities keep their common implementation.

Open-world combat nameplate discovery uses only readable `C_TooltipInfo.GetUnit` data and guarded, addon-owned decorations. The installed Forever export documents this as a data API taking a unit token, and its nameplate driver registers `NAME_PLATE_UNIT_BEHIND_CAMERA_CHANGED`. Combat alone no longer suspends all discovery and presentation work. World-map visibility, encounter/challenge/PvP/map restrictions, instance policy, inaccessible data and protected frames retain their guards. Questie and hidden-tooltip fallbacks stay outside restricted runtime states. Offline lifecycle regressions cover first-seen combat mobs, camera visibility, late data, tap loss and recycled plates; live rendering and engine-level taint validation remain separate.

Quest-state events clear addon-owned nameplate caches immediately and schedule a guarded refresh; that refresh also discards tooltip results cached before quest data settled. Map-blocked work uses an addon-owned, unparented frame to detect map closure and rechecks all restrictions before running. Recycled announcement bubbles are reparented only after checking the bubble and current host for protection, forbidden access and mutability. These paths do not attach addon state to Blizzard frames or register callbacks on Blizzard's map frame.

If an in-instance refresh clears quest text, world/zone events after returning outdoors schedule a coalesced quest-state rebuild. Recovery waits through combat, encounter and map restrictions and is canceled with its disabled runtime lifetime. Ordinary outdoor zone events keep their existing presentation-only refresh.

Untyped tooltip text terminates the current quest block at unknown labels while preserving recognized player rows from the copied party roster. Unreadable structured, hidden-tooltip or Questie rows retain an incomplete-data signal through source traversal and cannot establish NPC-wide completion. Positive objective evidence remains usable. The fallback sources retain their existing runtime restrictions.

A readable typed quest-title row retains its block boundary even when its title text is inaccessible. Following objectives cannot match another owned quest solely through shared wording. The boundary and incomplete-data flag contain only addon-owned values; independently readable structured, Questie, hidden-tooltip and later quest-block evidence remain usable under their existing guards.

Unavailable leading rows now preserve that boundary through extraction even when no readable row preceded them, including an entirely inaccessible structured row. Regressions exercise actual presentation and GUID/NPC cache results, with positive controls for later readable owned blocks, genuine titleless sources and ordinary readable unit headers. Untyped readable text still cannot reliably distinguish an unknown quest title from a unit header; this repair does not impose a blanket unknown-header rejection.

Expired explicit player departures clean up stored peer visuals even before periodic pruning. Protected or forbidden icons remain quarantined until safe cleanup. Location permission withdrawals retry each disabled surface independently for the remaining lifetime of its last published point; ongoing publication on another surface cannot extend that retry window. Settings rechecks restrictions before changing the native chat destination and never queues that selection for later.

Native map adapters check both secrecy and accessibility before reading map/position return values and only return copied scalar data. The nonsecret inaccessible-table case is an offline defensive contract, not a confirmed observed native return on either client. Native map and release-notes label regression counters record forbidden attempts before throwing so production error handling cannot hide them.

Actual roster changes invalidate party-dependent positive and negative quest-plate caches. Cached quest relevance requires a readable live GUID, while existing token-tooltip discovery and bounded retries remain available without one. Explicit unrelated quest-title blocks cannot reuse a tracked quest's generic objective text. Deferred disable cleanup retains only blocked addon-owned visual handles; presenting a reused handle cancels its old cleanup without relaxing forbidden, protected or inaccessible-frame guards.

Bonus-objective and world-quest classifications each use one addon-owned record of the latest readable boolean across snapshot and area reads. Missing metadata preserves that record; explicit false updates it, complete removal prunes it, and reset or fresh acceptance starts a new lifetime. New task acceptance resolves current metadata before handling hidden rows or choosing an announcement type, and retries unknown classification on later quest-log events. Ordinary quests do not require optional task APIs. Completion dispatch retains the captured world, bonus or ordinary type after live metadata disappears, including either removal/turn-in order. Progress-bar percentage and objective count are independent API observations: an unavailable percentage does not become zero from the count. Authoritative turn-ins can complete even when acceptance never received a readable row, with duplicate suppression preserved.

HUD Edit Mode uses the native eligibility check and public `ShowUIPanel` path documented by the installed Retail and Forever UI exports. It refuses active restrictions and inaccessible or forbidden managers, then verifies actual panel visibility before reporting success. Live tests substitute only addon-owned wrappers and private manager fixtures; native loader and panel API contracts are exercised separately in the offline profiles.

Diagnostics query the Chat restriction enum through the existing access-guarded reader. Chat is not added to the general quest/UI runtime restriction set. Offline contracts exercise the actual diagnostic report and reader with inactive, activating, active, unavailable, failing and inaccessible results, including absent APIs or enums; live tests do not replace restriction globals.

Run `lua scripts/location_client_profiles.lua . retail` and `. forever` on Lua 5.1/5.2 for offline-only native geometry contract probes. This script is excluded from the addon TOC and never runs in-game. It checks the shared Retail/Forever API shape, scale/zoom/pan, world axes, rotation overrides, floors and inaccessible values; client names label the same expected contracts, not emulated game engines. CI runs both profiles.

Run `lua scripts/test.lua` and `lua scripts/test.lua . reverse`. Run `lua scripts/test.lua . normal <client>` for `retail`, `forever`, `era`, `tbc`, `mists`, `titan` to exercise actual production API wrappers against each expected contract. Repeat on Lua 5.1/5.2. The offline runner loads Lua files from the addon TOC so it exercises the same regression modules as live `/qt test`, including nameplate discovery. Only the offline runner and client-profile fixtures are excluded from the TOC. Live tests use private addon API, frame and clock fixtures, preserve the live database and runtime references, and do not replace client globals. Offline-only tripwires fail the suite if a live-test fixture reaches engine frame creation, timers, hooks, restriction/tap reads, Questie, addon loading or native panel opening, including when production code catches the resulting error.

Before release, verify in the client that newly accepted quests become tracked after a readable quest-log update, progress announcements resume after temporarily unavailable data, and objective completion updates existing plates during ordinary combat. Check that tap loss clears both icon and tint, recycled nameplates retain visible bubbles, and closing the map resumes work without bypassing an active encounter restriction. Check a tooltip containing both a completed known quest and an unrelated unfinished quest, plus a party member who still needs progress. Check localized announcements and a large quest comparison between two updated clients, including a request received during combat and Unknown shareability. Verify `/qt set enabled off|on` stops and resumes the addon, and deleting an alt's profile stays deleted until that alt next initializes its default. Run `/qt test` in Retail and Forever with existing plates and bubbles visible and confirm their state is preserved; check for blocked actions and taint during these transitions.

For the latest fixes, also check plates when a relevant party member leaves, disable/re-enable while a visual is restricted, and `/qt bubbletest` on a visible player with no channel connection. Check new bonus-objective tracking, world/bonus area transitions and late completion text. After a quest update inside an instance, return outdoors and confirm icons/tint recover. Verify HUD Edit Mode opens its visible manager when eligible and declines while restricted. Check approved nearby celebrations and cross-locale proximity between updated clients. When initial quest data or a tooltip title is temporarily unreadable, verify tracking recovers on a later quest-log update and unrelated objectives do not create plates. The current offline suite has 746 tests. The user confirmed the earlier player-logo rendering and buff spacing in Forever; the user also confirmed both gold glows; consolidated settings, update notices, and the new visual examples still need live-client checks. Broader live-client validation remains separate.

Raw quest blocks cannot reopen solely through shared objective text after a boundary. A later raw title must match an owned quest title; this lookup uses owned snapshots/tracker data and does not add live tooltip reads. Task-area location flags preserve unknown separately from false, including modern/legacy adapter merging. A known positive area remains stable while required location data is unavailable; explicit false, complete removal, and fresh acceptance/reset still end that observation. Duplicate acceptance preserves an already tracked lifetime.

Both Retail and Forever UI-source exports declare a boolean `wasSet` result for `C_Map.SetUserWaypoint`. A rejected or unavailable result does not supertrack an older pin. Disabled clicks are allowed immediately only when unrestricted; restricted disabled clicks return failure without parked work. Enabled clicks can accept a deferred attempt and recheck restrictions when registered release events arrive. Live tests use private API/event/clock fixtures; real native adapters and secret-value sentinels are exercised only by offline profiles.

Before release, also check shared objective wording across unrelated tooltip blocks, temporary location-data outages without actual movement, disabled waypoint clicks during and after combat, and a native waypoint rejection with an existing pin. With no target, preview Forever players using `First Surname` or a quoted full name, and confirm only the intended local bubble appears. Run `/qt test` in both clients and check these transitions for blocked actions and taint; offline success does not establish native rendering or taint behavior.

Release-note sections can request the validated `quest-partners` illustration. The window shows addon-owned regular/glowing logo and map-dot examples within its scroll content, using the same artwork and visual parameters as the live indicators. They do not create player records, frames on real plates, map positions, or communications. No all-friendly or all-dot preview overrides ship.

The 5.13.1 repair pass separates bubble teardown from starting new playback:
accessible, unprotected addon-owned bubbles can stop on combat removal or base
reuse; protected/forbidden bubbles retain a pending owned cleanup handle and
retry after restriction events. The private debug console similarly remembers
interrupted gesture cancellation without bypassing its consumer policy, using
an independent owned wake frame so hidden windows can recover. Offline tests
exercise real addon policy/event paths and persistent attempted-access counters;
these remain separate from native taint and live rendering validation.

Party-chat fallback uses C_ChatInfo.SendChatMessage when available, with the
legacy SendChatMessage adapter for older clients. Only current non-raid party
units are checked; unreadable membership/identity fails closed. QT recognition
uses existing session discovery, so newly joined QT users can briefly count as
unrecognized. Messages go to the entire party, including QT users. Chat-specific
restrictions suppress public messages without queuing or affecting addon transport.
Offline adapter checks cover both API paths; actual party/instance-party delivery
and client chat restrictions still require live validation. Native send usage:
https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_ChatFrameBase/Shared/SlashCommands.lua

Localization uses addon-owned dictionaries and immutable command/protocol identifiers.
The eleven native text locales are enUS, deDE, frFR, esES, esMX, ptBR, ruRU, itIT,
koKR, zhCN and zhTW: nine languages with separate Spanish and Chinese variants.
European and Latin American Spanish use independent catalogs and event locale IDs;
enGB remains a compatibility alias for enUS. Client locale is read once; unknown locales fall back to English.
Optional ANN facts allow receiver-local event rendering while preserving the original
text for older peers and unsupported payloads. Native `C_QuestLog.GetTitleForQuestID`
and `RequestLoadQuestByID` are feature-detected and restriction-gated; title loading
is bounded. Missing, restricted, failed, or placeholder title lookups retain the
sender's readable quest title with a receiver-local event label when an exact known
source prefix can be identified. This also handles missing optional ANN facts for
quest lifecycle events. Unknown/custom text and progress without a local title retain
the complete source message; no quest-ID labels are generated. Progress
uses sender counters, never the receiver's objective counters or potentially different
quest stage. Structured `numRequired` supplements legacy objective reads only when
text, type and any existing current count agree. Same-language text and public party
chat retain their original wording. See `LOCALIZATION.md` for cache and fallback rules. The test harness temporarily uses English for
legacy exact-string assertions and restores the original addon state; dedicated
locale tests render comparison and release-note controls and exercise status/share
logic in every language using private frames. Offline success does not establish
native font coverage, label wrapping or live-client rendering. Check those in each
client locale before declaring layout validation complete.


## Party join requests (5.15.0)

The native boundary uses `C_PartyInfo.CanInvite`, `GetNumGroupMembers`, and
`C_PartyInfo.InviteUnit`, with guarded primitive copies and no writes to Blizzard
frames, shared popup tables, or secure delegates. Group/raid/instance state must
be readable; invitations are limited to ordinary parties with room and permission.
Missing APIs fail closed. `InviteUnit` has no success return: a nonthrowing call
means attempted, not delivered or accepted. QT does not call `ConfirmInviteUnit`,
`RequestInviteFromUnit`, group-leave APIs, or automatically accept invitations.
Source: [generated PartyInfo API documentation](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/PartyInfoDocumentation.lua).
Automatic calls are attempted once only when opted in and unrestricted; a failed
invocation falls back to a manual prompt. This does not prove native delivery or
hardware-click behavior on any specific live Retail/Forever build.

Friends means the character friends list, queried through
`C_FriendList.GetFriendInfo`, with exact normalized identity comparison. It is
not faction friendliness, first-name matching, a sender claim, or Battle.net
account friendship. Forever full regional names remain intact. A missing or
unreadable friend lookup requires manual consent.
Source: [generated FriendList API documentation](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/FriendListDocumentation.lua).

`QJST` version 1 advertises an ephemeral session/sequence, grouped state and
invite availability on the existing authenticated announcement routes. Unchanged
metadata sends once per 60 seconds; changes and failures are paced at 5 seconds.
A 125-second expiry and 512-peer cap apply. It carries no position or friend list,
and preserves legacy presence packets. Unknown native state is not advertised.
`QJON` version 1 carries request ID, target and status; the transport sender is
always authoritative. Only matching outgoing sender/ID/target replies are accepted.
Requests expire after 60 seconds, at most one outgoing request waits, incoming
traffic is capped at 10 requests per minute, each sender has a 15-second cooldown,
and replay history is bounded to 128 entries retained for 120 seconds. Outstanding
invites reserve available slots for 60 seconds or until that player joins.

Changing the host roster invalidates old consent. Ignores, peer departures,
disable/reset and expiration clear pending state. Restricted incoming requests
are never parked for automatic execution later. Tests use private peers/frames;
native mocks are confined to the offline client profiles. Live rendering, actual
invitation delivery/acceptance, cross-faction eligibility, automatic invocation
and blocked-action/taint behavior still require in-game validation on both clients.


### Player tooltip badges

A QT-owned section attaches to the standard player tooltip for character models, nameplates and unit frames. It reads `GameTooltip:GetUnit()` and validated public unit identity through addon wrappers on the existing 0.2-second updater. It never adds fields, hooks or lines to Blizzard's tooltip. The UIParent-owned section matches the tooltip's effective width/scale, clears its visible health bar, and moves above when there is insufficient space below. Only known QT players and the local player qualify. Ignored players, NPCs, unknown identities and restricted/forbidden hosts hide the section. The section identifies the player as a QT user; only fresh LFG On adds the partner-seeking line and glow. Off or unknown status adds no extra text. Disable/reset hides the owned UI. No temporary player-identity or LFG overrides ship.

QT bubble Edit Mode changes persist immediately in the active QT profile. Its addon-owned Save Changes button establishes a new Revert baseline and reports saved state without marking Blizzard layout tables dirty. Native Save also establishes that baseline; closing Edit Mode retains changes. Revert restores size, duration, and anchor only for the originating profile. Verify Save → edit → Revert and close/reload persistence in both clients; private fixture tests do not prove native UI rendering or taint behavior.

Location rendering retains the 128-pin cap per surface and the 512-peer model bound. Crowded surfaces rank by squared world-coordinate distance to the local player before projecting eligible pins; map pan/zoom do not define proximity. Unknown or other-continent distances rank last with stable name ordering. Cache overflow discards the farthest entry, then the oldest on distance ties; the newcomer participates and can itself be discarded. Missing local geometry falls back to age-based cache eviction. These operations add no network messages. Native distance reads remain restriction/access guarded.

## QT chat and channel-name transition

Version 6.0 ends the two-channel migration: `QuestTogetherAnnounce1` is left on enable and is neither joined, sent to, nor accepted as an incoming route. `QuestTogether` remains the global human chat and discovery channel; zone subscriptions are described below. Older clients may understand individual packets on shared routes but are no longer a full compatibility target. No received message is relayed.

Plain `CHAT_MSG_CHANNEL` messages are accepted only by exact channel metadata on either QT channel, respect ignore/disabled/chat restriction and output settings, and never establish QT presence. Display strips user-supplied UI markup. `/qt <message>` sends otherwise-unrecognized text once to the freshly resolved canonical channel ID, without local echo or deferred retries. Native channel delivery and moderation rules still apply; older QT clients do not display this new chat feature.

Channel reordering uses `GetChannelList` and the public `C_ChatInfo.SwapChatChannelsByChannelIndex` used in Blizzard's ChatConfig UI. It preserves non-QT relative order, then places QT channels last, with the canonical human chat channel before regional subscriptions. Coalesced channel events and restriction recovery trigger bounded passes. No ChatTypeInfo or native frame fields are changed. Missing reorder APIs leave the original order intact. Chat-name hover uses the public `ChatFrame.OnHyperlinkEnter/Leave` events and the same addon-owned tooltip renderer as dots, anchored beside the cursor at UIParent scale. Native GameTooltip and chat-frame scripts remain untouched.

Offline coverage includes distinct channel IDs, partial join failures, duplicate delivery, channel reordering/recovery, current-ID slash sends, shared tooltip content/cleanup, and initialized-live-addon fixture isolation. Live Retail/Forever checks still need channel order across login/zone changes, real mixed-version delivery, tooltip positioning at UI scales, circular launcher glow, and blocked-action/taint behavior.

The nearby announcement range is persisted per profile as a 5–100 percentage, default 25. At 5 it exactly preserves the previous 5-coordinate-point radius. Higher settings convert x/y deltas using physical map width/height in yards, with the radius set to the selected percentage of the map diagonal; 100 includes all valid points on the same map. This measures a radius, not percentage of zone area. Map/legacy-label identity and Retail War Mode checks remain in place. `GetMapWorldSize` is read behind the existing restricted/access-guarded map adapters; clients lacking it derive dimensions from 0/0 and 0.5/0.5 world positions, following HereBeDragons’ Classic fallback. Missing geometry retains only the old nearby range. No packet or heartbeat changes are needed.

QT chat scope is independently persisted as Global (default) or Zone Only. Global never queries location data. Zone Only checks the local best map against an existing shared peer location within the location model’s lifetime (120 seconds for unwrapped old LOC packets, at most 600 seconds from sampling for new snapshots), with withdrawals and unknown locations excluded. It is a receive-side filter for both logs and bubbles, rather than a separate channel or a sender delivery boundary. Sender self-echo remains allowed. UI tooltips explain the need for recent shared locations.

The shared map-dot/chat-speaker tooltip now uses a wrapping class-colored title, larger body text, faction accents, a divider, padded sections, gold partner/quest highlights, and muted location age. All regions and styling remain QT-owned; refreshing between partner/non-partner and hover sources reuses the same regions.

LFQP off-to-on changes publish one `ANN` event of type `LOOKING_FOR_QUEST_PARTNERS`, with the QT logo and receiver-localized text. Repeated On selections, status heartbeats, reloads, profile loading, and disabling LFQP do not publish this event. It uses existing route deduplication and does not post to native party chat. Same-zone location matching bypasses the nearby radius and map dimensions for this event only; Retail War Mode compatibility, ignore lists, Party Only, and output preferences still apply. Location sharing disabled continues to redact the zone and coordinates, so remote zone-wide discovery then cannot be established from the announcement. Publication is skipped while disabled, logging out, or restricted; it is never queued for later. Older clients can render the existing ANN wire format but retain their own distance rules.

The `announceQuestPartners` profile option defaults on and controls both publication and display of LFQP announcements without disabling QTLF status metadata or indicators. The `stopLookingForPartnersOnJoin` option defaults off; when enabled, `GROUP_JOINED` clears LFQP through the normal setting/withdrawal path. Ordinary roster refreshes do not clear an explicitly resumed search. Both controls participate in settings refresh and profile persistence.

Dot and chat-name tooltips share a class-colored name header and divider, a localized level/race/class summary with a class-colored class name, and a small translucent native faction emblem. Unknown factions hide the reused emblem. These are addon-owned regions; no native unit tooltip or frame is modified.

QT chat is available through `/qt <message>`; its former minimap composer shortcut has been removed. The receiver-localized LFQP announcement ends with `:)`; status labels remain unchanged.

LFQP announcement icons use the local static gold-glow `QuestTogetherPartnerIcon.tga` in chat and overhead bubbles. The wire packet retains the standard scroll path so older peers never reference an asset absent from their installation. The glow is rendered from the original SVG emblem by `scripts/build_minimap_icon.py --glow`; inline chat textures cannot run the animated nameplate glow.

The LFQP announcement cooldown is 30 seconds and paces failed attempts too, without delaying status updates or scheduling a later announcement. Minimap Shift-click uses the existing partner toggle behind a read-only key-state adapter. Its owned tooltip refreshes status while hovered; per-player version caches use validated transport identities and are cleared with presence removal. Settings hover explanations use a reusable QT-owned tooltip and private control hooks. Own-name hover reads the current local super-tracked quest without depending on an incoming self packet or location-sharing consent.

Quest-name hover now uses the QT-owned cursor tooltip, with your local quest status, shareability, quest ID, and available local objective text. It replaces the Status menu action; quest sharing, journal, and compare actions retain their click-time guards. Player and quest hovers share the owned rendering/lifecycle path, hide on leave, restriction, disable, and hidden chat frames, and escape foreign display markup. No native tooltip lines or chat scripts are replaced.

Player-name/map-dot tooltips and the minimap count use QT's monitored tracker, matching the full-scan announcement rather than WoW's watched quest count. Counts stay unknown until the first readable QT scan. Player tooltips also show Solo or Party of N, using guarded native group metadata for self. Version heartbeats alternate legacy QTVR v1 with QTVR v2 carrying installed version, monitored count, and group size (empty fields mean unknown). In 6.0 these individual metadata updates are captured into compact regional/global snapshots; the newest extended stats are preserved when an internal producer emits a short version-only form. Unwrapped old stats expire after 180 seconds, and snapshot stats after at most 600 seconds from sampling and are removed with ignored/departed/evicted identities; missing reports never imply zero quests or Solo. Peer stats do not control sharing or invite authorization.

## Transport latency and capacity diagnostics

The Forever trace from October 4, 2026 contains replies to a ping generated at
3745.484 arriving at 3955.440: about 210 seconds round trip. That is not a
measurement of one-way quest-announcement latency or proof of channel overload.
Requests now remain eligible for five minutes (eight retained requests, up to
4096 distinct responders each). Reset/reload discards them. Replies use only the
validated incoming group/channel route. Manual `/qt ping` requests remain global, plus the group route when grouped; replies are jittered over 1–20 seconds and queued with bounded lifetime. No automatic ping request retries were added.

Announcement wire v3 has an optional seventeenth field containing the sender's
server epoch time when QT creates the event. Existing v1-v3 decoders ignore this
extra field. The 255-byte budget is unchanged; timing may be omitted if space is
needed. Incoming messages without a valid timestamp have unknown age, not zero.
`/qt dump comms` logs `reportedAgeSeconds`; `/qt diag` includes sample count,
mean/max age, and local per-command transport counters. Ages are second-resolution,
sender-reported estimates, affected by clock differences; they do not control
display, emotes, identity, or permissions. Future timestamps and ages over one day
are treated as unknown. Existing installations must update to send timestamps.

Traffic counters count every attempted successful/failed API send route, received
packet and duplicate, including payload bytes and throttle results. Successful
sends mean API acceptance, not verified delivery; byte counts exclude transport
overhead. Counters reset with the addon runtime and use fixed command buckets.
These measurements do not send additional packets.

Pre-6.0 capacity baseline: with both migration channels, a solo stationary client normally
broadcasts about 14 background channel packets per minute (location, alternating
presence/version, and party metadata). Moving with LFQP and a tracked quest is
about 32/minute, before quest events, comparisons, requests, startup bursts or
failures. At 1000 clients this is roughly 233-533 broadcast packets/second, each
potentially delivered to every listener. These are source-derived estimates,
not a measured server limit. The former independent send timers shared one native
prefix budget without a common scheduler; the observed startup trace contains
native throttle failures. A longer ping window does not solve that scaling risk.
The 6.0 implementation below replaces those independent publications.

## Geographic transport in 6.0

- **Global:** `QuestTogether` retains plain text QT chat, legacy comparison/join transactions for older peers, and `QTB1` presence snapshots every 150–210 seconds. Worldwide dots remain available within the existing bounded cache (512 locations, 128 drawn pins). Their last-update age uses sample time, including estimated transit delay, rather than disguising delayed coordinates as newly sampled.
- **Regional:** `QuestTogetherZ<zoneMapID>` carries announcements and snapshots. Subscribe to the current zone plus, after four seconds of stable map selection, one viewed zone. Leaving/closing the view releases the old subscription; never more than two zone subscriptions. Zone/floor ancestors use copied `C_Map.GetMapInfo` fields, with cycle/depth bounds; continents/world maps never create subscriptions. No role, realm suffix, War Mode or phase identifier partitions these channels. Existing Retail display filtering still applies.
- **Cadence:** current-zone and group locations update every 1 second below 10 known same-zone peers, 5–10 seconds at 10–19 peers, and 15–20 seconds at 100 peers. Intermediate populations interpolate to the existing 45–50 seconds at 500 peers, 70–75 at 1,000, and 90–95 at 1,400+. The fastest interval has no jitter. Each scheduled publication samples fresh coordinates; unchanged positions skip fast per-route publications while full metadata still renews discovery and freshness. Fast updates use compact location-only envelopes while full metadata retains the previous 20–95-second density-based heartbeat. Status changes still expedite a full snapshot. Queue pacing can add delivery delay, and duplicate pending location updates coalesce rather than accumulating. Global snapshots continue independently. A newly viewed zone receives the next scheduled publication; opening a map never solicits a broadcast response storm. Failed joins fall back to global announcement delivery, without claiming zone subscription success.
- **Snapshots:** state producers stage only their newest LOC/QTPR/QTVR/QTLF/QTLQ/QJST data. Each length-prefixed packet stays within 255 bytes; long optional labels/titles are omitted. QTPG party visuals and QTCI capabilities travel in isolated fragments for older decoders. A bounded parser allows only recognized state commands and rejects truncated framing, nesting and implausible time fields. Snapshot sessions and per-command sequences tolerate fragment/route reordering and reject retired sessions. Data expires at most 600 seconds after sampling; unreadable locations are omitted after 35 seconds rather than renewed indefinitely. The server timestamp is an estimate; when unavailable, transit age is unknown and receiver time is used.
- **Scheduler:** one two-packet/second token budget with a four-packet burst, one token reserved for immediate transactions. Up to 96 queued packets; announcements/PONGs expire after 30 seconds, snapshots after 15. Events precede snapshots, snapshots coalesce per route/part, and native throttle results pause all attempts for two seconds. Comparison requests also queue, validate that their request is still pending before sending, and acknowledge queue acceptance. Other transaction calls retain actual-send return semantics; state staging and event queue acceptance acknowledge only local storage. Local token pacing does not spend comparison-response failure retries. A failed route backs off independently; native throttle results still pause all routes. Complete replacement snapshots remove obsolete trailing fragments. No invite, quest-sharing or other protected action is deferred by this scheduler.
- **Lifecycle/privacy:** the transition to location withdrawal cancels packed snapshots and queued announcements, replaces the stored position with a clear, and schedules global/local publication. Repeated location clears use the normal global cadence. LFQP and tracked-quest withdrawals repeat throughout the 600-second snapshot lifetime. Status changes accelerate publication with a ten-second global floor. Normal disable/world departure attempts a compact clear immediately and discards pending publications. Reset invalidates ping callbacks and leaves owned regional channels. Reload reconciliation removes orphaned numeric QT zone subscriptions; already-joined channels still receive filters, and chat-window cleanup runs when channel bindings change rather than on every send. Group roster changes and regional departures discard queued work for the old audience. Ignore checks apply before snapshot decoding/display. Clears are best effort; lost clears expire naturally, and are never proof of remote removal.
- **Deduplication:** party/zone/global overlap still produces duplicate delivery without the legacy channel. A 4096-entry ring gives bounded storage and constant-time replacement; new announcements carry a bounded event ID in optional field 18 and deduplicate for five minutes (subject to ring capacity), so separately generated identical actions remain distinct. Snapshot sequencing additionally rejects obsolete state after the short payload duplicate window. Capability/order records are bounded to 2048 peers; expiry maintenance runs at most once per second, with immediate admission-cap enforcement. Existing model cache bounds remain in place.

The packet-rate savings depend on snapshot size, player activity and adoption. This is an audience and traffic reduction, not proof of a native server capacity limit. Local simulations cover subscriptions, two-peer transport, throttling, queue expiry, ordering, consent changes and dense-zone backoff. Live Retail/Forever validation is still required for channel joining/order, real latency, two-client delivery, and taint/blocked-action behavior. Owner `devlogall` can only show received events; regional subscriptions no longer provide a worldwide firehose of quest activity.

### Join requests through a party member

A fresh grouped `QJST` record permits a manual join request even when the member
cannot invite. If that member is in a normal party with room, QT resolves the
current `party1`–`party4` leader through an access-checked native wrapper and
requires fresh, invite-capable QT join metadata for that roster member. Raid,
instance-group, full, unknown, ignored, and restricted states cannot relay.

The member replies with `QJON|1,<id>,<requester>,redirect,<leader>`; names are
escaped exactly as in ordinary requests. Only the contacted member can redirect
an active outgoing request with its exact ID, once and before any pending
confirmation. The requester sends an ordinary authenticated request to the
leader itself. No payload can impersonate the original requester. The original
outgoing expiry is retained, and responses from the original member no longer
complete the redirected request. Normal replay, cooldown, queue and invite-slot
bounds still apply; there is no new heartbeat or automatic retry loop.

The leader applies its own friendship/LFQP consent preferences and rechecks
invite permissions, party capacity, roster, profile, expiry, and ignores at
confirmation. The requester and contacted member need this forwarding support;
the leader only needs the existing join-request protocol. Older members return
the existing unavailable response. Direct invites and requests remain unchanged.
A rare older requester using stale invite-capable metadata cannot interpret a
redirect and will expire normally. Live three-client Retail/Forever delivery and
native invitation behavior still require client validation.

When the current leader is not known to use QT, `announceToNonQTParty` also
allows the contacted member to send a single plain `[QT] <requester> is requesting
to join the party.` message to PARTY chat. This uses the same request replay, per-sender
cooldown and ten-per-minute global budget. No announcement goes to raids,
instance groups, full/unknown parties, ignored players, or restricted chat, and
no delayed retry is queued. A known QT leader with stale join metadata is not
treated as a non-QT leader. The requester receives `announced` feedback only
after the party-chat adapter reports a successful invocation; the leader must
invite manually. Native invocation is not proof of server delivery.


## Party map visuals (6.1)

- Grouped map/minimap dots show a two-person badge. Hovering a party member gives
  matching visible dots a white outline, dims unrelated dots, and crowns that
  party's leader. The gold LFQP glow remains independent. Leaving, closing the
  surface, recycling a pin, disabling QT, or entering restrictions clears the
  hover state without mutating protected UI.
- Both map-dot and chat-name tooltips put the crowned leader first, with class-colored
  dots and full names. Groups of two through five list all members (including
  non-QT members); larger groups show only the leader. Ignored names are omitted.
  Native roster data is authoritative for the viewer's own group.
- `QTPG` advertises size, leader name/class and a deterministic roster revision in
  the existing paced presence snapshots. It is isolated in its own QTB1 packet:
  older 6.x parsers reject unknown inner commands, so combining it with LOC would
  prevent those clients from reading locations. Initially solo clients need no
  extra packet; QTVR already carries solo status. Group changes stage a fresh
  revision/withdrawal, with the existing global ten-second burst floor.
- Hovering a remote small party requests its roster with targeted `QPGR` whispers when supported (global channel for older peers);
  `QPGM` replies carry one member each, at most five. They use the existing bounded
  send queue and token budget, not immediate five-packet bursts. No periodic full
  roster broadcast or query storm is added. Requests are correlated with the exact
  sender, request ID and revision; only a complete, unique, hash-matching roster
  containing its sender and leader is displayed. Partial/stale results stay unknown.
- Header records follow snapshot sampling/expiry (up to 600 seconds); complete
  roster caches last 120 seconds. Request attempts are limited to once per party
  per 60 seconds, with at most 16 outstanding; responders allow one request per
  sender per 20 seconds and one total response per five seconds. Peer, roster,
  retry and responder caches are bounded. Native group changes, ignore/departure,
  disable/reset and metadata replacement invalidate dependent state.
- Older clients can still supply the basic grouped badge through their existing
  party-size metadata. Remote identity, crowns, highlights and complete member
  lists require a peer with the new party metadata; no group identity is guessed
  from equal party sizes. Only visible shared QT dots are highlighted; the feature
  does not invent locations for non-QT or non-sharing members.
- Native leader detection copies a unit token behind restriction/secret guards
  and supports solo leader, party and raid token layouts. All rendering uses
  addon-owned regions. Offline adapter, transport and private-frame tests do not
  establish live rendering, server delivery or taint safety on Retail/Forever.

## Nearby whisper positions and tooltip identity (6.2.0)

- Updated peers advertise `QTCI|1,streamSupport,raceID,directSupport` in the existing paced
  metadata snapshots. This small optional packet is isolated from established
  presence, LOC and party packets, so older receivers can keep reading those.
  There are no speculative whisper probes to older clients. A missing native
  race ID is encoded as zero; native race/class labels fall back to sender text.
- A peer must already have a fresh, consented location inside the current
  minimap projection, advertise stream support, and be among the four closest
  eligible peers. Both sharing and viewing must be enabled. The existing LFQP
  filter, ignore list, map-floor compatibility, hidden minimap and runtime
  restrictions apply. Server phase is deliberately not inferred from coordinates.
- `QTSR` requests/renews a 12-second lease; `QTSP` carries its receiver-issued
  token, sequence, timestamp, map ID and normalized position; `QTSX` cancels it.
  Only WHISPER accepts these commands. Sender identity comes from the transport,
  and requests cannot name a different reply recipient. Other commands remain
  rejected on WHISPER, while the separate targeted-control allowlist below is accepted. Position packets cannot refresh a public LOC record or
  revive its sharing consent. Stale requests, mismatched tokens, reordered samples,
  withdrawals and disabled/departed peers lose their streams.
- Each client sends at most five nearby whisper packets per second TOTAL,
  including lease controls, across at most four nearest subscribers. Fair
  scheduling shares this budget; a lone moving peer usually receives roughly
  four to five samples per second, while crowded situations get fewer. Stationary
  positions use a two-second heartbeat. No movement backlog accumulates.
  Pending announcement/response traffic takes priority, native throttle pauses
  are shared, and failed whispers back off before another attempt. These limits
  are additional to the existing two-packet/second geographic send budget;
  WHISPER is not assumed to bypass native/server throttling.
- Only existing QT-owned minimap pins animate (up to 30 frames per second),
  interpolating received samples over 0.2–1 seconds without extrapolation.
  Map changes and large jumps snap. After three seconds without fresh position
  data, the normal zone/global location remains the fallback. This animation
  does not rebuild world-map UI or tooltip content on every animation frame.
- Tooltip race names resolve through `C_CreatureInfo.GetRaceInfo(raceID)` and
  classes through the local class-name table. Custom/unavailable races and
  peers without a race ID retain their readable original names. No machine
  translation, extra per-tooltip query, or additional identity heartbeat is used.
- Private two-client transports, bounded-rate/lifecycle tests, private frame
  animation tests and offline native adapter profiles validate the model only.
  Real WHISPER delivery, movement quality, server throttling and taint still need
  testing with two updated clients in both Retail and Forever.

## Generic announcement decoration (6.2.0)

- Generic announcements, info/warning headers and bubble fallbacks use the QT
  logo. The old generic exclamation-mark texture received from older peers is
  recognized at display time and replaced too. Quest-specific textures/atlases,
  the chat-bubble icon and LFQP's glowing logo keep their existing meanings;
  the quest-mob nameplate icon is unchanged.

### Communication audit (2026-10-05, 6.2.0)

Targeted party-join controls use one route: a supported whisper, otherwise the current group when the target is in it, or the global QT channel. Announcement publication constructs one event for local display, native party chat and wire encoding. Receive dispatch rejects oversized and NUL-containing wire packets before parsing. Nearby position streams yield to ready comparison-response jobs as well as queued announcements, but continue while a comparison is waiting for an unavailable local quest snapshot.

In an isolated ten-minute workload with unchanged positions and fewer than ten peers, solo traffic fell from 638 packets to 68, and grouped traffic from 1,201 to 192. Moving workloads retained identical packet counts and payload bytes; higher-density idle savings vary with heartbeat cadence. These measurements exclude optional nearby whisper traffic and native/server latency. The local audit manifest, pre-change source copies, workload script and measurements are under `.local/audits/comms-2026-10-05/`.

### Targeted control transport (architecture audit, 6.2.0)

One-recipient traffic uses addon `WHISPER` when the target advertises direct-control support. A single route-selection helper covers quest comparisons (`QCMP`, `QCQE`, `QCDN`), party-roster lookups (`QPGR`, `QPGM`), join controls (`QJON`), party share controls (`QSHR`), and ping replies (`PONG`). Old or unknown peers retain their established group/global route; comparison requests no longer broadcast to both an unrelated channel and the target's group.

Direct support adds one flag to the existing isolated QTCI presence fragment, without an extra heartbeat. Its bounded 512-peer cache expires from the snapshot's sample time and is reset with comms. Stream/location preferences do not disable direct controls. Old three-field QTCI metadata remains readable. A valid incoming direct request establishes its reply path without requiring reciprocal discovery first.

Manual PING remains global plus group. Its optional trailing `direct1` flag lets updated receivers whisper their replies immediately after the requester's reload. Released parsers ignore the extra field and continue their original replies. PONG still requires an outstanding request and authoritative sender identity; an unrelated client does not receive whispered reports.

The whisper control allowlist does not admit ANN, LVL, plain QT chat, presence snapshots, or public LOC messages. Existing sender/target/request correlation, ignore handling, bounded queues, timeouts, share consent and current-group membership checks remain enforced. Group-dependent queued direct requests and comparison responses stop on departure. Nearby streams retain their own strict three-command lease protocol. Both paths still honor native throttling; whispers do not imply unlimited bandwidth or delivery acknowledgement. Failed sends remain failed and expire/retry under their existing bounded policy rather than blindly duplicating an accepted whisper onto a broadcast channel.

Offline three-client tests exercise Retail cross-realm name strings and Forever full names, zero bystander delivery of comparisons/rosters, immediate post-reload private ping replies, old-peer broadcast compatibility, capability expiry, throttling, cancellation, ignored peers, departed groups, and manual share/invite consent. Live addon whisper delivery must still be checked on both clients, including cross-realm/instance and faction restrictions where applicable.

### Heartbeat ownership and consolidation (6.2.0)

In geographic mode, the twenty-second presence producer refreshes extended QTVR version/tooltip metadata and party visuals together. It no longer alternates bare presence, basic version, and extended version stages or runs a separate version heartbeat. The old alternating behavior is retained only for the non-geographic path. Party-visual refresh does not depend on version parsing succeeding. Actual transmission remains owned by the density-paced local/group and slower global snapshot scheduler; a producer call is not an extra network message.

A fresh valid version record already identifies the sender as a QT user, so full snapshots omit a redundant positive QTPR record when that record is included. Explicit departures are retained, and bare presence remains available when version data is absent, invalid or stale. Party-visual solo withdrawals stop after the last grouped publication's possible lifetime (600 seconds for snapshots, 180 for the legacy path); the staged clear then ages out normally. LFQP and location withdrawals retain their existing independent consent/freshness rules.

The update loop has one public-position publisher in geographic mode. It avoids the separate five-second sample before geographic publication, and shares a fresh same-tick addon-owned sample with nearby position streams when both need it. The sample is never cached across ticks, and stream consent/restriction gates still run before use. Without a due geographic publication, a stream samples its own fresh position. Legacy location publication remains supported.

Nearby lease renewals and stationary stream keepalives remain separate from public presence: they authorize short-lived peer streams and prevent smooth-position samples from expiring. Public heartbeat consolidation must not extend those leases or keep stale movement alive. QTLF and its optional tracked-quest QTLQ also remain paired because receiver sequencing requires them to match.

The repeatable ten-minute public-traffic workload under `.local/audits/heartbeat-2026-10-05/` shows 68→68 packets and 8,602→8,161 payload bytes for idle sparse-zone solo presence; at 1,000 observed peers, public position reads drop from 129→13. These measurements exclude active nearby whispers and native/server latency. Publication cadence, geographic/group audiences and explicit privacy withdrawals remain intact.

### Reload location cache and zone discovery (6.2.0)

On logout/reload, QT saves at most 512 validated public locations in an addon-owned SavedVariables cache scoped to the current character. A saved point expires three minutes after its original sample, or sooner if its original live lifetime ends. Restoration translates wall-clock ages back to the current session clock; repeated reloads never renew the timestamp. Old, malformed, future-dated, wrong-character, ignored, and withdrawn positions are discarded. The cache is consumed once on initialization, respects the existing location display/filter options, and does not restore streaming leases or pretend that cached metadata is a new live message. Fresh LFQP status is also retained with its own original expiry, capped at three minutes from its sample. Party status and known small-party rosters retain the original party-revision confirmation expiry as described below. Other metadata continues to refresh through presence traffic or a requested hover reply.

The one-time `QTDQ|1,<zone>` query is queued 2–5 seconds after discovering the current zone, once its channel is joined. It uses only that regional channel, never the global channel, group channel, whispers, or a zone merely viewed on the map. Zone changes can query again, with a 60-second per-client request floor. A request from another newcomer coalesces any pending local query. Receivers advance their existing regional metadata snapshot by a random 2–20 seconds, without postponing an already-due snapshot or advancing global publication. Each client considers at most one request per minute; with more than 32 known same-zone peers it responds with probability 32 / peer count. This limits expected acceleration in known crowded zones, not a hard server-wide count: population estimates and simultaneous cold starts can differ. Normal heartbeats continue filling in all remaining peers.

Queries use the existing bounded queue, token budget, expiry and restriction checks. Queries queued for a departed current zone are discarded even if that channel remains subscribed for the world map. Older QT versions ignore the new query and still supply their regular snapshots. Offline checks cover two-peer dispatch, throttling-compatible queue ownership, routing, coalescing, dense-zone sampling, cache expiry/clock reset, live replacement, ignore/consent handling and capacity. Actual SavedVariables persistence and accelerated discovery still require live reload and two-updated-client checks.


### Hover details and review repairs (6.2.0)

Entering a QT player-name or map/minimap-dot tooltip can request fresh details through addon whispers. This is an entry action, not another periodic heartbeat: repainting an open tooltip does not send more requests. A known QT identity or a still-valid restored position is sufficient to query; no prior party leader or revision is required. Requests never use a public channel fallback. Older versions ignore these optional commands and continue their existing presence broadcasts.

`QTHQ` requests correlate to `QTHD` responses by transport sender and a session-specific request ID. One client can attempt a request every two seconds, with at most eight outstanding requests and a 15-second response lifetime. Complete recent metadata or a successful reply is reused for 30 seconds; unanswered/unsupported peers have a 120-second retry floor. Responders allow one reply per sender per 30 seconds and one reply total every five seconds. Both directions use the existing bounded geographic send queue and token budget; they do not get a separate high-frequency channel or bypass congestion backoff.

Replies contain freshly read party identity, version, join availability, LFQP status, tracked quest where sharing permits, and non-location character identity. Existing `QTB1` per-command sequence ordering prevents older public snapshots from replacing newer requested details. `QTHI` supplies class, level, faction and optional source-language race/class labels without publishing coordinates. The receiver uses local class/race lookups where available. A response is bounded to eight 175-byte fragments, validates its metadata-only command allowlist after complete assembly, and tolerates fragments arriving out of order. No partial reply is displayed. After current small-party identity arrives, the existing correlated roster exchange can fetch member names directly. All messages remain within the native 255-byte payload limit.

Ignore, disable, restrictions, expiry, changed response rosters and withdrawn location consent invalidate queued hover work where relevant. Tracked quest details follow the same sharing consent as normal presence; basic character and party identity do not depend on publishing a location. Neither a restored point nor a request attempt establishes fresh live presence. Responses update owned data; normal tooltip repaint refreshes only the tooltip currently being hovered and never reopens a dismissed one.

The review repairs also separate safe owned window dismissal from protected actions/layout, coalesce blocked objective rescans, respect exhausted nonquest tooltip scan retries, classify queued location-bearing packets by content, preserve nonboolean options when `/qt set` is misused, translate the compare column heading, and resolve available local class/race/zone labels in ping output. Shared window dismissal is supplied by private libchev 1.2.4 through the normal immutable vendor workflow.

Offline validation covers complete two-peer dispatch, Forever names, lost/reordered/duplicate/expired/mismatched replies, privacy and ignore changes, long UTF-8 payloads, original snapshot ordering, queue budgets, and tooltip entry/repaint/leave behavior. Actual delivery timing, SavedVariables persistence, rendering and taint behavior still require live-client checks.


The location reload cache also retains solo/group size, known leader/class/revision and a validated roster for parties of up to five. Party metadata expires at its original deadline and no later than three minutes after its sample. A validated member list remains reusable while fresh party metadata confirms its exact revision; it no longer expires independently after two minutes. Saved rosters use the matching revision confirmation's original sample and expiry, including transit age, with the same three-minute reload cap. QTVR-only size information is retained when a full party identity was unavailable. Restored party information is explicitly marked cached and requires a still-valid cached position until live presence arrives. Cached status never establishes live QT membership, starts roster traffic, or authorizes invites/shares. Fresh live information replaces it. Larger groups retain the known leader only. Repeated reloads, malformed revisions/rosters, expiry, ignores and explicit departures are regression-tested.

The minimap menu contains Looking for Questing Partners, a divider, Party Quest Log, Open Quest Log, a divider, Patch Notes, the main/separate log-window toggle, and Hide Minimap Icon, in that order. Settings remain available through `/qt options` and the welcome window. Callbacks read current settings and recheck restrictions.

Party tooltip summaries also use fresh existing QJST solo/grouped metadata when an exact size is unavailable. A newer contradictory summary hides the older count and roster; delayed older summaries cannot replace newer sampled party identity. Grouped-only reports show no invented count or members. These fallbacks work with published peers that do not support hover requests.

### Party-chat acknowledgement (6.2.1)

The default-on party-chat option now explains that enabled announcements are also sent when a party member is not recognized as a QT user. A ten-second discovery grace period precedes an addon-owned reminder naming those members. Keep enabled (or the close button) acknowledges the current unidentified members; Turn off announcements disables the setting. The optional Don't remind me again checkbox is saved per profile only by a valid acknowledgement. New unidentified members can trigger another reminder; members who leave or become recognized are removed. No extra presence probes are sent.

Event forwarding and non-QT-leader join-request chat wait for acknowledgement, unless that profile has already suppressed reminders. Waiting events are not queued or replayed. The reminder shares the forwarding path's current native party checks, excludes raids, defers discovery/presentation under restrictions, and rechecks membership/profile at click time. An existing acknowledgement still permits otherwise-allowed announcements during combat. Safe close hides the owned window during restrictions without saving an acknowledgement; it resumes afterward. Disable/reset clears transient state.

`/qt preview partychat` shows the same dialog with localized sample names and is listed only in `/qt help debug`. Its separate preview frame and request cannot alter real acknowledgement, settings, membership, or outgoing chat. Preview closes on addon reset. Both live-safe state regressions and private-frame callback tests cover it; actual client layout still needs visual validation.

### Expandable comparison objectives

Comparison completion (`QCDN` v1) has an optional seventh `obj1` field. Only peers advertising it receive an objective request: an optional fifth quest-ID field on `QCMP` v1 scopes the response to a single quest. These on-demand requests and replies use addon whispers, with the existing comparison queue, send budget, expiry, and transport-sender correlation. They add no heartbeat or global objective broadcast. The full-list comparison remains compatible with older clients.

The scoped reply contains zero or one `QCQE` quest entry, an optional ninth field advertising its objective count, up to 20 `QCOB` packets, and the normal `QCDN` completion marker (counting quests, not objective packets). `QCOB` v1 carries request ID, quest ID, objective index, escaped source text, objective type, optional completion boolean, and optional numeric current/required values. The 255-byte limit retains complete UTF-8 text. Replies can arrive in any order; missing expected objective packets leave the details loading until timeout, never complete. No-objective/unreadable client results remain explicitly unavailable. The public channel fallback used by old full-list comparisons is not used for these detail requests.

The compare window can keep multiple quests expanded independently. Objective requests run sequentially per peer so their response queues cannot supersede another open quest. A bottom-right resize grip adjusts the viewport within screen-aware bounds (minimum width based on displayed party columns, with a 780-pixel floor and a 500-pixel minimum height; three players require 962 pixels and five require 1222, keeping the compact share actions visible). Resizing reuses cached display rows and does not read quests or send messages. Class-colored column headings and subtle column tints identify players without replacing readiness colors. Each quest summarizes ready, missing and unknown members; incomplete snapshots never establish group readiness. Expanded objectives sit in an inset bordered panel beneath a highlighted parent quest and show bounded progress bars where counters exist. Pixel scrolling keeps headers fixed; wheel easing only shifts existing row content and repaints on row crossings, without rebuilding snapshots or generating traffic. Expansion and collapse reveal the details over 180 ms without scaling text; rapid reversal starts from the current height. The row pool grows to twice the visible row count plus two, accommodating simultaneous partially clipped sections, and reuses existing frames when shrinking. Filtering, refresh and close stop the owned animations. Details are grouped by player: objective index alone is not assumed to establish equivalent objectives across locales or client data. Source wording remains visible, including text-only legacy counters; structured counters and progress percentages are used where safely readable. Remote details are snapshots refreshed by Refresh or reopening the row; local details follow the existing coalesced quest-log refresh. Collapsing one quest cancels only its detail requests; closing, ignoring, disabling, or rebuilding the comparison cancels the associated pending detail requests. Read-only quest access stays in the existing map/restriction-sensitive work class; no Blizzard UI, selection, or super-tracking state is mutated.

`/qt preview compare` copies your real objectives and simulates corresponding teammate progress, with fictional objective details for the extra mock quests. It sends no comparison requests. Offline regressions cover two-addon whisper exchanges, reordered/incomplete/late packets, old peers, counters and text fallback, restriction guards, cancellation, localization, and bounded row reuse. In-game rendering and actual two-client delivery remain separate validation steps.

Dark parchment is the default. The off-by-default Light mode profile setting on the main settings page restores light parchment. The shared palette in `WindowTheme.lua` styles Party Quest Log (including its isolated preview), the welcome/patch-notes window, quest-share and party-join requests, the party-chat reminder, bubble settings, and the Discord copy-link dialog. Small dialogs use fixed-size scroll rolls, a QT logo header, and wrapped content that can grow for translations. Libchev debug and diagnostic windows retain their own styling. It switches parchment and text colors, with matching borders, class accents and progress colors in the quest log, without modifying Blizzard UI or changing quest/expansion state. Theme refreshes use the existing restriction-aware scheduler.

Both scroll windows use the MEDIUM frame stratum with native top-level focus, allowing ordinary quest panels to come forward. Welcome-window theme changes recolor existing labels and illustrations without reopening the window, changing the history page or scroll offset, or acknowledging a new version.

The welcome window uses fixed-height scroll rolls with separate end caps, an addon-owned header drag region, and a bottom-right resize grip. Resizing reflows the current notes or release-history list without changing the selected release or acknowledging a version. History entries use plain themed rows instead of stretched native button artwork. Header/footer placement and dragging still require a live-client visual check.


### Party focus and shared waypoints (local development)

`QTNAV` v1 combines active quest ID/title, native user waypoint, and the selected follow target in one bounded snapshot. It uses only the current PARTY or INSTANCE_CHAT route for groups of two through five, including dungeon parties, and never global/geographic channels or whispers. Changes coalesce over 250 ms, with a single jittered 28–32-second refresh and 90-second peer expiry. Join/reload snapshots request a rate-limited response; session/revision checks reject stale packets. Group departure, ignore, addon disable, or raid conversion removes state and pins. Older clients can keep using other QT features but have no focus/waypoint state.

The three Groups & Sharing options default on, independently of public location/LFQP settings. Disabling either sharing option publishes its unavailable sentinel; clearing a native pin or quest publishes a distinct empty state. Following is explicit, cycle-checked, and saved per character across reloads. Only the follow target is saved; fresh validated party data is required before resuming. Temporary peer expiry or unavailable focus preserves the follow intent while waiting. Missing quests stop following and open a themed notice with an Open Party Quest Log action; cleared focus preserves the follow and personal navigation. Party departure, disband, raid conversion, ignore, and addon disable clear the saved intent. PQL uses ordinary Blizzard mini quest POI atlases in each owned quest/player cell; local buttons focus a quest and teammates’ active quest buttons start following. Inactive teammate buttons are read-only and gray. All buttons retain full opacity. While following, every button is gray except the followed member’s active quest; choosing your own focus or another member’s active quest asks for confirmation before ending or switching the follow. Without a follow, your buttons and teammates’ active quests retain their colors. Header menus retain focus details and following controls. Cancel leaves the follow intact, and a follow-identity token rejects confirmations from a superseded follow. Use `/qt preview unfollow` or the isolated compare preview to exercise the warning. Native quest-tracker changes also restore the last followed focus and ask before applying the new quest or clearing focus; Cancel keeps following. This uses guarded public APIs after the tracking event, without modifying Blizzard callbacks, so the native selection may briefly change before restoration. Other native navigation (waypoints, etc.) stops following directly. A failed restoration stops following without repeated writes; a failed confirmed quest setter preserves the follow. QT setter echoes do not prompt. Restricted changes retain the latest received intent, then recheck current membership, ownership, and follow state before applying. Failed setters are reported without repeated retries.

Waypoints use a separate four-pin pool on each map surface, reusing the guarded map/floor projection and minimap rotation geometry. They do not consume player-dot caps or inherit LFQP filters. The local native pin is not duplicated. Overlap tooltips/menus include every nearby pin owner; Navigate here explicitly invokes the existing TomTom/native path. Pins can cross phase layers but never promise phase compatibility. Unavailable geometry hides the pins.

The Party Quest Log shows focus under each member's header, with a header menu and Following/Stop controls. Its private debug preview simulates a shared quest (Aria) and a missing quest (Borin), without native navigation or outgoing communication. Offline contracts cover the native adapters for client profiles; actual two-client navigation, tooltip placement, and rendering on Retail and Forever still require in-game validation.


### Local previews

Run `/qt preview share`, `/qt preview join`, `/qt preview partychat`,
`/qt preview bubble`, or `/qt preview discord` to inspect the matching QT dialog.
These commands are listed in `/qt help debug`. Request previews use separate
frames and never invite, share, acknowledge real requests, or save preferences.
The bubble preview uses the same native slider widgets with inert callbacks and
disabled save/reset buttons; it neither enters Blizzard Edit Mode nor changes
its live session. Clients without the native slider template report that this
preview is unavailable. Discord previews only display the copyable invite link.
Run `/qt preview` (or `/qt preview help`) to list every preview. The same list
appears in `/qt help debug`. `/qt preview compare` opens the Party Quest Log with simulated teammates and real local navigation; `/qt preview notes` (also `welcome`) opens the welcome/notes
window. `/qt preview announcement <text>` renders a local announcement on your
current target, or use `/qt preview announcement "<player>" <text>` without a
target. Message case and quoted/Forever names are preserved. Invalid preview
commands print help and never become QT chat. `/qt partychatpreview`,
`/qt compare debug`, and `/qt bubbletest ...` remain compatibility aliases;
`/qt notes` remains the normal patch-notes command.
Theme changes refresh open dialogs without resetting checked preferences.
All preview creation obeys UI restrictions; test fixtures stay addon-owned.

Small dialogs reserve body margins outside the scroll rolls and keep actions
above the bottom roll. Bubble slider values have their own bounded column;
layout runs after native slider setup, which otherwise restores fixed widths.
All QT scroll windows share cursor-delta dragging based on effective scale and
rendered position. The driver runs only during a drag and stops on hide,
restrictions, or a scale change. Check repeated grabs after resizing, with a
non-default UI scale, and with bubble settings attached to Edit Mode. Offline
fixtures cover pickup geometry and cleanup; actual cursor tracking and visual
spacing still need confirmation in the client.


### Window accessibility and snapshot freshness (local changes after 6.4.1)

Party Quest Log now labels remote snapshots with their age. Its player header menu can refresh one player, and Filters offers an opt-in 30-second refresh while the real window is visible. Closing it cancels requests; the preview remains isolated. Refresh keeps search, expanded quests, horizontal position, and the visible quest anchor while replacement data arrives. Hover rows for complete quest/objective text.

Settings > Accessibility provides 80–150% window scaling and reduced-motion scrolling/expansion. Scaling enlarges text and controls together; fitting the full window on a small display takes priority over the requested percentage. The Party Quest Log and welcome window save size and screen-relative position per profile. Restoring, reopening, changing display size, or changing UI scale clamps/fits registered QT windows to the current screen. Reset window layout (or `/qt resetlayout`) clears saved layouts and recenters windows. No layout state is stored on Blizzard frames. `Bindings.xml` exposes Toggle Party Quest Log in native Key Bindings with no default key. QT dialogs handle Escape through their existing dismissal actions; the libchev debug window is unchanged.

Player Locations uses one display toggle for both the world map and minimap, independent of location sharing. The split display preferences from 6.4.2 migrate with display enabled if either surface was enabled; sharing is unchanged. Its single filter menu offers all QT players, questing partners, or party only. Always show my party defaults on and exempts party members from the questing-partner filter, subject to their existing location-sharing permissions. Local display changes do not cancel outgoing nearby streams.

The experimental layer UI is unchanged. Local evidence changes retire old request nonces without imposing the unsupported-peer backoff, and outgoing candidate checks skip cooling-down peers instead of being limited to the nearest four. The global pacing limit remains in force.

Private regressions exercise display changes, malformed layout data, restricted deferral, snapshot refresh lifetime, reduced motion, and filtering. Actual Retail/Forever rendering, Escape ordering against native windows, native keybindings, and the ultrawide/Moonlight display transition still require live-client verification.

Party comparison snapshots use the guarded `C_QuestLog.IsComplete` adapter as the authority for completion, matching `QuestMixin:IsComplete` and the native objective tracker's POI style in the installed Retail and Forever exports. Quest-log row completion is retained only when that query is unavailable. The same completion bit drives the local Ready label, party summary, POI icon, and outgoing comparison entry; no extra message or receiver-side guess is introduced. Older senders retain their reported snapshot until they update. Private tests cover disagreeing flags, false as an authoritative result, inaccessible/failed reads, wire round trips and icon selection.

The comparison preview reads an owned copy of the current local quest log and objective details, then creates four simulated teammates and two private synthetic quests the player does not own. Synthetic IDs never reach the native setter or party transport. Focus actions in this mode deliberately change the real Blizzard super-tracked quest and use the production follow/confirmation state machine with private membership, no-op transport, and no saved follow writes. An owned event listener observes native tracking changes even when the addon runtime is disabled; its short update loop runs only while the preview is open. The actual party follow is suspended while the preview is open and resumes afterward; its target is retained but not advertised as active during preview. Closing or refreshing discards simulated following and invalidates pending confirmation callbacks. Share, request-share and journal actions remain simulations. A fully fictional fallback remains available when native adapters or a reliable local snapshot are unavailable. The preview labels its real navigation effects. Missing quests now show Not shareable or Shareability unknown when no sharing action is available; these do not claim knowledge of another player's prerequisites.
