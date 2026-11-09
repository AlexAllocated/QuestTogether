# Major communication upgrade — release preparation

Target: 9.0.0. Implementation review and the final offline validation matrix have passed;
results are recorded in `PROTOCOL3_VALIDATION.md`. Live Retail and Forever
network validation remains pending; this draft is not a published release. The
original release plan requires that gate before publication. Any explicit
maintainer decision to release without it must be recorded separately, without
marking those tests passed.

## Player-facing facts

- QuestTogether now discovers players through channel membership and exchanges
  addon data through whispers and native party routes. It no longer sends addon
  messages into custom chat channels.
- Public updates can travel through other QuestTogether clients. Current and
  viewed zones receive priority; coverage grows progressively as clients discover
  one another. Disconnected groups of clients may remain undiscovered.
- Public relays preserve the original author, timestamps and expiry. Ordinary
  relayed data must be confirmed directly with its author before it is displayed
  or forwarded. Developer and VIP identities retain their signature checks.
- Party quest logs, objectives, focus, waypoints, private replies and developer
  diagnostics remain direct. Hidden coordinates are never part of the public
  relay network. Existing sharing and diagnostic choices remain in effect.
- Settings, saved profiles, VIP credentials and focus-following preferences are
  preserved.
- All communicating QuestTogether clients must upgrade together. There is no
  compatibility path for older protocols.
- Queue and traffic limits protect party activity. Slow or unavailable delivery
  remains possible; the network does not promise every worldwide event.
- The Party Objective Tracker uses the normal HUD layer so character and bag
  windows and item tooltips can cover it. Quest-tooltip docking is preserved.
  The maintainer confirmed this layering fix in the live client.

## Suggested English notice

**QuestTogether users must update together.** This major release replaces the
addon’s communication protocol. Older versions cannot exchange QT information
with this version.

QuestTogether uses a peer network to distribute public updates, with priority for
your current zone and the zone you are viewing. Discovery is progressive, so
players may appear as the network forms. Party information and private exchanges
continue to use direct routes, and your existing sharing preferences remain in
effect.

## Authoring and publication

Use the final code and measured validation results as the facts for every locale.
Write each language independently in the active subscription session. Do not
translate this draft line by line or claim the live checks passed before they
have been performed. Keep the released version unchanged until release is
authorized and validated.
