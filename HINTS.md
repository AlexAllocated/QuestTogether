# Player tips

`Hints.lua` contains 225 localized tips. Stable IDs preserve the account-wide
unseen pool across wording changes, language changes and new releases. New tips
join that pool without resetting previously seen tips. Startup tips can be
turned off; `/qt tip` and `/qt hint` remain available for local, manual draws.

Every feature-facing tip should explain a useful action, distinction or limit.
Link to its settings page or an existing window where possible. Links open a
fixed, guarded destination; they never apply a preset, change an option or run
arbitrary commands. Follow the current settings category names when moving a
feature. Keep client-specific guidance capability-gated without loading a
provider, requesting data or reading gameplay state just to select a tip.

## Coverage audit

This map covers the current player-facing surfaces, including optional and
client-specific functionality. Numbers identify stable `hintNNN` entries.

| Area | Tips |
| --- | --- |
| Settings, help, minimap launcher and bindings | 001–013 |
| PQL objectives, search, filters, refresh, columns and keyboard | 014–035, 186, 221–222 |
| Share, Request Share, approvals, eligibility and party-wide offers | 036–042, 176–178 |
| Looking for Questing Partners and join requests | 043–056 |
| Maps, privacy, party markers, timestamps, clustering and VIPs | 057–075, 175, 214–215, 220 |
| Announcement events, scopes, nearby range and chat destinations | 076–098 |
| Bubbles, celebration emotes and buff thanks | 099–102, 156–160, 207–208 |
| Quest/player nameplates, names-only preview and tooltip filters | 103–112, 216–217 |
| Scale, themes, reduced motion, layouts and profiles | 113–124, 169, 173–174 |
| Release notes, updates, support and diagnostics | 125–133, 218–219 |
| Quest details, journal, manual focus and following | 134–147, 194–195 |
| Party waypoints, coordinates and navigation | 148–155, 189 |
| Retail activities, Forever layers and War Mode | 161–166 |
| Presets and their intended uses | 168–174 |
| Provider setup, chains, spoilers, prerequisites, giver navigation, preview | 179–191 |
| Party tracker, HUD editing and automatic leader-follow | 192–198, 223 |
| Native Forever controller navigation and launcher customization | 199–204 |
| Audio cues, defaults, individual controls and troubleshooting | 205–206, 224 |
| Optional Data Broker toolbar integration | 209–211 |
| Recent companions and private player notes | 212–213 |
| Manual tips and startup preference | 167, 225 |

The audit added 58 tips and corrected existing home-page, manual-follow and
waypoint guidance. Quest-chain tips distinguish Forever's optional QuestieDB
from Retail's native coverage. Controller tips describe current production
behavior, including the unassigned QT menu binding; they do not describe old
experimental input probes. Sharing tips distinguish unknown eligibility from
a confirmed blocker and never promise that WoW will accept a share.

All source strings are authored in the active session across the eleven
supported languages, using the repository's localized UI terminology. Run the
localization checker, hint regressions and client-profile checks after changes.
The hint regressions cover stable unique IDs, new tips entering the existing
unseen pool, capability gating and the fixed navigation whitelist.
