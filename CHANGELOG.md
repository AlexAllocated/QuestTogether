# QuestTogether changelog

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
