# QuestTogether changelog

## 5.10.0 — 2026-09-27

- Replace the chat welcome with an addon-owned welcome and patch notes window, with the scroll logo above the welcome heading. Show it once on first use and on major/minor upgrades, across characters and profiles; patch upgrades stay quiet. Reopen it with `/qt notes`, `/qt changelog`, `/qt patchnotes`, Patch Notes in the minimap menu, or the main Settings screen.
- Require current, regenerated in-game notes for every release. CI and the release script validate the version, generated data and changed content against the previous release; document the workflow in `RELEASING.md`.
- Fix quest Status links taking the full chat line as a fallback title, which duplicated closing brackets and announcement text after a quest was removed. Match the clicked quest link and recover titles from older malformed status lines.

- Add a draggable minimap button using the SVG scroll emblem. Left- or right-click for Settings, Compare Party Quests, Open Quest Journal, Patch Notes and the shared log-window destination action. Position and visibility are saved per profile. Use Hide Minimap Icon in its menu or Show minimap icon in Miscellaneous settings; the shortcut prints instructions for restoring it.
- Keep `/qt help` focused on normal commands; show debugging and developer commands with `/qt help debug`.
- Recover compare snapshots after map/combat restrictions, preserve sessions when the game UI hides, and replace obsolete peer replies during rapid refreshes. Synchronize the automatic-sharing setting, explain request cooldowns/rejections, and keep terminal feedback visible beside retry actions.

- `/qt compare debug` opens the full compare window with a realistic three-player party, 16 quests, overlapping progress and simulated actions. Filters and Refresh work without sending messages, sharing real quests or changing saved settings.
- Compare Party Quests in the minimap, player-name and quest-name menus opens Party Quest Compare, styled to match the WoW artwork in the debug window, with ownership and completion columns and Share buttons. All party quests appear by default; checking “Hide quests I don't have” limits the list to your quests. Also available with `/qt compare`.
- Request shareable quests from party members using the updated addon. Incoming requests ask by default, with an “Always allow party share requests” checkbox and a matching Miscellaneous setting. Requests expire and eligibility is checked again before sharing.

Add Open in Quest Journal to the quest-name menu after Share. It opens the selected quest's journal details, remains available while solo, and explains when a quest is not in your journal. Recheck the quest and restrictions on click without queueing delayed journal actions.

Validation: 595 addon tests pass in normal and reverse order on Lua 5.1 and 5.2, along with all six client API profiles and 20 release-tooling tests. Generated notes, Lua and shell syntax, exact libchev verification, and diff checks pass. Native sharing, recipient eligibility, final window rendering, and engine-level taint behavior require separate live-client validation.

## 5.9.2 — 2026-09-27

Left- or right-click a quest name in the QuestTogether log to open its menu, with Status first and Share second. Share uses the current quest-log entry without changing Blizzard's selected quest, and is unavailable when solo, restricted, or the quest cannot be shared. After a separator, the final option moves QuestTogether logs between the main and separate windows, matching QT's player-name menu.

Make quest names in status messages clickable, including fallback titles from other players' logs. Preserve existing quest links when formatting completed quest comparisons so status details do not become part of a second, broken link.

Validation: 521 tests pass in normal and reverse order on Lua 5.1 and 5.2. All six client API profiles, Lua and shell syntax checks, exact libchev verification, and diff checks pass. Live-client menu behavior, quest-share delivery, and engine-level taint validation remain separate.

## 5.9.1 — 2026-09-27

Keep shared objective wording from reopening an unrelated raw tooltip quest block. Later owned quest titles, party progress and genuinely titleless sources still work.

Preserve unknown task location flags without announcing false exits or re-entries. Explicit false and real quest removal remain authoritative; fresh acceptance resets retained observations, while duplicate acceptance preserves the current task lifetime.

Honor native waypoint rejection before tracking a pin. Disabled, restricted clicks are declined rather than queued without a wakeup; unrestricted clicks still work while disabled. Coordinate links report immediate failures.

Accept full Forever player names and quoted names in local bubble previews. Correct preview/debug instructions, native API test return values, forbidden-read assertions and restriction/deferral test timing. Make the CI syntax step propagate compiler failures.

Keep newly accepted quests pending until a real quest-log update supplies the matching row. Retry unreadable data without losing the acceptance, and cancel pending work when a quest is removed. Treat Classic's failed completion value (`-1`) as incomplete and preserve an explicit modern incomplete result.

Retain the last usable objective observation across missing rows and quest-log rescans so the next new milestone still announces. Preserve stage-change and replay suppression, and start fresh history when a quest is accepted again.

Invalidate cached nameplate relevance when quest state changes, including during combat. Stop tooltip objective matching at every new quest-title block, and reparent reused announcement bubbles to their current nameplate. Resume map-blocked work when the map closes while preserving combat, encounter and other restrictions.

Keep untyped tooltip quest blocks separate while retaining recognized party progress. Preserve incomplete-data signals from hidden tooltips and Questie so unreadable objectives cannot mark an entire mob type completed.

Retry disabled nameplate cleanup only for the handles that could not be hidden; new icon, tint and bubble presentations cancel their previous cleanup. Invalidate party-dependent quest relevance on actual roster changes, require a readable live GUID for cached relevance, and prevent explicit unrelated quest titles from borrowing another quest's objective text.

Treat a missing progress-bar percentage as unknown even when its separate objective counter remains readable. Complete authoritative turn-ins that arrive before initial quest tracking becomes readable. Share the latest confirmed bonus-objective classification between snapshot and area readers, preserving unknown reads without overriding an explicit false or carrying classification into a new quest lifetime.

Resolve newly accepted tasks from current metadata before discarding hidden rows or announcing ordinary acceptance. Preserve confirmed world-quest classification through temporarily unavailable reads, and carry captured world, bonus or ordinary quest types into late completion announcements.

Rebuild quest text cleared inside instances when returning outdoors, using the existing restricted-work scheduler. Coalesce exit events and cancel obsolete recovery work when disabled.

Keep localized announcement and presence metadata within the wire limit without losing sender identity. Pace quest comparison responses, retry transport failures, and stop canceled or expired replies without reporting incomplete data as a finished comparison. Wait through known restrictions without consuming failed-read retries. Preserve Yes, No and Unknown shareability through comparison messages.

Include an optional map ID in announcements so nearby detection compares the same coordinate system across locales, retaining the zone-label fallback for older peers. Keep numeric location when a long zone label cannot fit. Make `/qt bubbletest` a local preview of the selected visible player, with no network impersonation or transport dependency.

Accept only approved celebration emotes from nearby players, with guarded mounted and faction-specific handling. Open HUD Edit Mode through Blizzard's eligible panel-opening path and report success only when its manager is visible.

Apply `/qt set enabled on|off` through the normal enable/disable lifecycle. Deleting another character's assigned profile now clears its assignment without immediately recreating the deleted profile; the character's default is resolved on its next login.

Correct the test harness to preserve live addon state and use private frame, API and timer fixtures. Load the same regression modules offline and in-game, including nameplate discovery tests. Add regressions for real quest-log event sequencing, inherited bubble visibility, first-time combat discovery, map recovery, legacy completion and localized or interrupted communications.

Avoid division by zero in the live invalid-level test, which Forever rejects before the addon handler runs. Keep NaN rejection coverage in the offline client contracts.

Preserve typed quest-title boundaries when the title text is unreadable, so a following objective cannot borrow an unrelated tracked quest's title. Keep independently readable positive evidence and prevent incomplete tooltip data from establishing completion.

Retry an unreadable initial quest scan on a later quest-log event through the existing restricted-work scheduler. Keep pending acceptances in control of their own tracking, preserve area-entry announcements as task metadata recovers, and cancel obsolete recovery work on disable.

Read the Chat restriction enum in diagnostics without adding it to general quest or UI restriction gates. Exercise the actual reader and report against supported, unavailable and inaccessible API results in offline client contracts.

Validation: 516 tests pass in normal and reverse order on Lua 5.1 and 5.2. All six client API profiles, Lua and shell syntax, exact library verification and diff checks pass. Repaired tests reject deliberately inserted forbidden reads and restriction bypasses. Offline tripwires detect accidental engine frame, timer, hook, restriction, tap, Questie, addon loader or native panel calls from live-test fixtures. Live-client rendering, two-client delivery and engine-level taint validation remain separate from these checks.

## 5.9.0 — 2026-09-26

Celebrate your own and nearby QuestTogether players' level-ups with synchronized emotes. Add separate, enabled-by-default level-up emote toggles beside the quest completion emote settings in Miscellaneous. Nearby reactions respect the existing player scope and proximity rules.

Remember confirmed quest-objective completion by creature type as well as individual spawn. Mobs that appear during combat stay unmarked when tooltip data is unavailable, even if an older spawn was cached as needed. Fresh unfinished objectives can restore highlighting; quest-state changes clear completion memory. Partial or inaccessible tooltip data is never treated as proof that everyone is done.

Clear quest nameplate icons and health tint immediately when a mob's tap is denied, including during combat. Listen for ownership changes and recheck taps on health and threat updates.

Detect newly encountered quest mobs during ordinary open-world combat using readable unit tooltip data. Refresh plates when they return from behind the camera, become your target, or are moused over. Retry delayed frames, GUIDs and tooltip quest lines with a bounded per-unit budget, cancel stale work when units are removed, and restore tint and icon together. Preserve map, instance, inaccessible-data and protected-frame guards; combat discovery does not invoke Questie or hidden tooltip UI.

Validation: 374 offline tests pass in normal and reverse order on Lua 5.1 and 5.2. Six client API profiles, Lua syntax checks, exact library verification and diff checks pass. Completion-cache regressions reproduced the bug before the fix. Live gameplay and engine-level taint validation remain separate.

## 5.8.6 — 2026-09-25

Harden character names, class names, quest titles and custom class colors against inaccessible or malformed API values. Validate optional TomTom and Questie integration data before using it, and stop reading Questie tooltip lines at inaccessible data. Normalize bubble visibility and edit-mode state to booleans before passing them to UI controls.

Consolidate the loading-screen event handler, remove unused private arguments and an unused restriction-enum branch, and clarify callback and return-value handling. Keep modern/legacy client fallbacks and the exact private library revision intact.

Validation: 336 tests pass in normal and reverse order on Lua 5.1 and 5.2, with expanded adapter checks across six client profiles. New regressions fail against the previous implementation. Lua parsing, exact library verification and diff checks pass. Reviewed the remaining Ketho WoW API/LuaLS diagnostics, including a separate pass without offline client mocks; retained findings have specific compatibility, guard, callback, library or fixture reasons. Live Retail and Forever gameplay validation remains separate.

## 5.8.5 — 2026-09-25

Fix task/world-quest map discovery on modern clients by reading `questID` from `C_TaskQuest.GetQuestsOnMap`, while retaining the legacy API and `questId` field for older clients. Prefer `C_ChatInfo.PerformEmote` so completion emotes work when deprecated globals are disabled; safely handle missing or failing emote APIs.

Remove an unused party-roster fingerprint calculation and unused local variables. Extend offline client checks to cover modern and legacy task/emote APIs, API precedence, inaccessible quest data, and missing/failing APIs. Validation: 334 tests pass in normal and reverse order on Lua 5.1 and 5.2, plus the expanded API checks on six client profiles, Lua parsing and exact library verification. Gameplay validation in Retail and Forever remains separate from offline checks.

## 5.8.4 — 2026-09-25

Repository housekeeping: keep local development notes outside the tracked source and release packages. Gameplay behavior is unchanged.

## 5.8.3 — 2026-09-24

Announce the installed version, supported clients and settings command once per login or UI reload. Include addon-specific CurseForge and GitHub feedback links; clicking a link opens a native-style copy window. Share message behavior and safe copy UI through private libchev 1.2.0. If link registration or the copy window is unavailable, show the full URL in chat. An unavailable welcome helper cannot interrupt normal addon startup.

Validation: 334 tests pass in both orders on Lua 5.1 and 5.2, with client API checks, Lua parsing and exact library vendor verification. NoPoizen smoke simulations exercise both feedback links on all seven client/ruleset profiles. Live rendering remains a separate check.

## 5.8.2 — 2026-09-24

Isolate test fixture GUID lookups from nearby players. Fix two false failures in `/qt test` when a real unit occupies the nameplate token used by the tooltip and cached-icon checks. Gameplay nameplate behavior is unchanged.

The offline environment now includes that token collision and reproduces both failures without the fixture fix. All 333 tests pass in both orders on Lua 5.1 and 5.2 after the fix; six client API profiles also pass. In-game confirmation remains separate.

## 5.8.1 — 2026-09-24

Show Blizzard's quest marker beside QuestTogether in the AddOns list instead of the default question mark.

## 5.8.0 — 2026-09-24

Support current Classic clients with correct quest-acceptance payloads, guarded objective API fallbacks, honest unknown shareability, flavor metadata and six-client API regression checks. Preserve Retail/Forever behavior and shared debug utilities.

Validation: 333 tests pass in both orders on Lua 5.1 and 5.2, with six client profiles, Lua parsing and exact private-library vendor checks. NoPoizen client smoke checks and package verification also pass. Live validation of the new adapters remains pending.

See [CLIENT_COMPATIBILITY.md](CLIENT_COMPATIBILITY.md) for source evidence, scope and validation limits.

## 5.7.7 — 2026-09-24

Keep overlapping debug consoles and their controls in one native stacking group through private libchev 1.1.3. Category menus stay with their owning console.

Default quest objective icons to the left of the nameplate. Existing saved icon positions remain unchanged.

Respect Forever's “My Last Name” setting when displaying your character's name. Keep other players' surnames visible, matching the native setting's scope. Use full names consistently for communications, group membership, nameplate matching, and social actions while preserving existing profile and personal bubble position keys.

Fix duplicate local quest announcements caused by receiving your own channel message under a different full-name format. Regression coverage exercises the local announcement followed by its channel and party echoes, including another character with the same first name.

Validation: 331 tests pass in both orders under Lua 5.1/5.2. Live confirmation of the new icon default and multi-window interaction remains separate.

## 5.7.6 — 2026-09-24

Use the same private libchev 1.1.2 debug console across all three addons, including category/search filters, copy controls, test results, diagnostic reports, timestamps when available, and a single final test summary. Fix stretched native frame artwork with explicit texture bounds.

QuestTogether supplies its own quest diagnostics and isolated tests while the shared library owns the console and generic debug behavior. Run `/qt test`, `/qt debug`, or `/qt diagnostics`.

Validation: 324 tests pass in both orders on Lua 5.1/5.2. The user confirmed the corrected frame appearance in-game. Other live restriction and gameplay validation remains separate.
