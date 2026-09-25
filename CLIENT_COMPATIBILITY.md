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

The Classic references are mirrored Blizzard UI/API source. Source inspection and offline fixtures establish expected contracts, not engine-level taint safety, rendering or gameplay validation. The user requested source-backed implementation without waiting to level a Forever rogue. Live poison application, expiry, charge exhaustion and audio checks remain pending; no live test result is inferred from these fixtures. No SavedVariables were changed externally.

`QUEST_ACCEPTED` accepts either `(questID)` or Classic's `(questLogIndex, questID)` payload. A secret second value is rejected rather than interpreting the log index as a quest ID. Deferred acceptance, deduplication, snapshots and communication identity remain shared.

Quest enumeration retains legacy `GetQuestLogTitle` and modern `C_QuestLog.GetInfo` paths. Objective reads support the legacy by-ID function, structured `C_QuestLog.GetQuestObjectives`, and the older indexed leaderboard API. Foreign tables/values are access-gated before use. Existing snapshot completion status remains available when Classic lacks Retail's named completion APIs.

Classic `GetQuestLogPushable()` refers to the currently selected quest. QT reads it only when that selection already matches; it never changes the user's quest selection. Unavailable shareability is displayed as **Unknown**, not an incorrect **No**.

All current Classic nameplate XML uses the shared health container and base-unit access used by the addon; existing guarded legacy anchoring and tooltip/Questie fallbacks remain. Settings, the diagnostic console, surname-aware display and full communication identities keep their common implementation.

Run `lua scripts/test.lua` and its reverse order. Run `lua scripts/test.lua . normal <client>` for `retail`, `forever`, `era`, `tbc`, `mists`, `titan` to exercise actual production API wrappers against each expected contract. Repeat on Lua 5.1/5.2. These scripts are excluded from the TOC. Live `/qt test` includes both acceptance signatures and unknown shareability regressions without replacing client globals.
