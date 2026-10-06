# QuestTogether — Changelog

<!-- Generated from canonical release notes; do not edit by hand. -->

[Other languages](changelogs/README.md)

## 6.4.1

Thanks for using QuestTogether! This update adds more control over quest progress snapshots, player location displays, and window accessibility. Settings are easier to tune, and Discord is still the best place for feedback and support.

### Party Quest Log updates

- Player headers now show how fresh each quest snapshot is. Open a player header menu to refresh just that player without refreshing everyone.
- Filters now includes an optional auto-refresh setting. When enabled, the Party Quest Log refreshes about every 30 seconds while the real window is open.
- Refreshing keeps your search, expanded quests, horizontal position, and visible quest position when possible while new snapshot data arrives.
- Quest focus labels now distinguish waiting, expired, unsupported, unavailable, and unshared states, and the menu warns when following would create a loop.

### Accessibility and window layout

- Settings now includes Accessibility options for window scale from 80% to 150% and reduced motion for instant scrolling and objective expansion.
- Window scale enlarges text and controls together, but may be capped when needed to keep the full window on screen.
- The Party Quest Log and welcome window now save their size and screen-relative position per profile, and QuestTogether windows are refit after display size or UI scale changes.
- Use Reset window layout in Accessibility, or /qt resetlayout, to clear saved QuestTogether window layouts and recenter them.

### Player location controls

- World map and minimap display can now be toggled separately from location sharing, so you can hide local pins without changing what you share.
- The player location filter now offers all QuestTogether players, questing partners, or party only.
- Always show my party is on by default, so party members still appear when using the questing-partner filter if their location permissions allow it.

### Fixes and polish

- Experimental layer detection keeps the same settings and UI, with smoother request handling when local evidence changes or nearby candidates are cooling down.
- QuestTogether dialogs now handle Escape through their normal close actions, and the Party Quest Log can be assigned a key in the native Key Bindings menu with no default key set.
- Percent signs in translated release notes are handled as normal text.

## 6.4.0

Refined QT windows and quicker access to party quests.

### Party Quest Log

- Take a closer look at the Party Quest Log introduced in 6.3: compare up to five players in class-colored columns, see who has each quest, and spot missing quests or a party ready to turn in. Search and combine ownership, progress, and action filters; Share and Request Share are available where supported.
- Each player’s header shows their focused quest. Click a teammate’s name to follow their quest focus; following is opt-in and leaves your navigation alone when you lack their quest. Use Refresh for a fresh snapshot of remote progress. Screenshots show fictional preview data.
- Quests you own now have a small book button that opens their details in Blizzard’s Quest Log. Clicking the row still expands objectives.
- A crown marks the party leader and updates when leadership changes. Your own column stays first.

**Retail**

![Party Quest Log — Retail](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v6.4.0/Media/ReleaseNotes/PartyQuestLogRetail.png)

**Forever**

![Party Quest Log — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v6.4.0/Media/ReleaseNotes/PartyQuestLogForever.png)

### Expand everyone’s objectives

- Click a quest to expand each member’s objective counts, progress bars, and completed steps. Keep several quests expanded at once. This release makes these sections more compact, with matching class-colored headings and bodies; a typical five-player quest with two objectives each fits at the default window size. Longer quests may still need scrolling.

**Forever**

![Expand everyone’s objectives — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v6.4.0/Media/ReleaseNotes/PartyQuestObjectivesForever.png)

### Windows and minimap

- Left-click the minimap icon to open or close the Party Quest Log; right-click opens the menu. Settings is back in the menu, and the tooltip explains the shortcuts.
- Party-chat reminders, share and join requests, bubble settings, and the Discord link dialog now use QT’s scroll frame and light/dark themes, with more padding and room for slider values.
- Window dragging preserves the cursor offset, including in the compare preview. Menus and tooltips now consistently call Blizzard’s window the Quest Log.

### Preview commands

- Use /qt preview to list the window and announcement previews. The older preview commands still work; mock actions do not invite players, share quests, or send messages.
- The compare preview now shows a full five-player party, including a Hunter and Rogue, with varied objectives, focused quests, and a leader crown.

## 6.3.1

More comfortable spacing in the Party Quest Log.

### Objective panel spacing

- Expanded objective panels now have extra bottom padding so progress bars do not touch the border. Scrolling and expansion animations include the added space.
- Messages such as “No objective details available” are vertically centered beside the player’s name instead of crowding the top border.

## 6.3.0

A new Party Quest Log, shared destinations, and optional quest following make it easier to quest together.

### Party Quest Log

- Party Quest Compare is now Party Quest Log. Expand several quests at once to see each member's objectives and progress, with an overall party readiness summary.
- Search quests and combine ownership, progress, and sharing filters. Refresh updates remote snapshots; older clients can still compare quest lists but cannot provide objective details.
- Resize the parchment window and scroll smoothly. Class-colored columns, clickable padded player headers, and rounded objective panels make progress easier to read.

### Party focus and shared waypoints

- See each member's active quest beneath their name. Choose Follow quest focus from their header or QT menu to follow quests you own. Missing or cleared quests preserve your navigation; manual navigation, leaving the party, or reloading ends following.
- Other members' Blizzard waypoints appear as class-colored world-map and nearby minimap pins. Overlapping pins list every owner; Navigate here uses TomTom or native navigation. Receiving a pin never redirects you, and pins do not imply a shared phase.
- Share my focused quest, Share my waypoint, and Show party waypoints default on in Groups & Sharing, independently of public location sharing and partner status. Following is opt-in. These features require updated peers in parties of up to five, including dungeons; raids are excluded.

### Window and menu polish

- Patch notes now share the dark parchment theme, with optional Light mode. Drag or resize the window, browse cleaner history rows, and use arrows to move between releases or jump to either end. Join our Discord and Settings are in the footer.
- Player tooltips fit their content more closely. The minimap menu now separates questing tools from patch notes, log placement, and icon visibility. Settings and Send QT chat message are removed from that menu; settings remain available through /qt options.

## 6.2.3

Fewer repeated ready-to-turn-in announcements.

### Quest readiness fixes

- Quests already ready or complete when tracking starts are recorded quietly. Missing readiness data and later refreshes no longer replay already-observed ready-to-turn-in announcements.
- New completions still announce, and accepting a quest again resets its notification history. The sending player needs this update; older versions can still send bursts.

## 6.2.2

Readable quest progress in every language.

### Keep the objective details

- Quest, world quest, and bonus objective progress now keeps the sender's original wording and counts in chat and bubbles instead of replacing them with generic text such as "Objective 1: 5/5".
- Quest accepted and completed announcements still use translated labels and locally available quest titles.

## 6.2.1

Clearer control over party-chat announcements.

### Know when QT posts to party chat

- The setting under Where to Announce now clearly says that QT also posts to party chat when a member is not recognized as a QT user. It remains on by default.
- A new dialog with the QT logo appears after a short discovery delay. Choose Keep enabled or Turn off announcements before forwarding starts. Don't remind me again saves your acknowledgement for the current profile.
- The localized reminder names the affected members and can return when new unidentified members join. It disappears if they are recognized as QT users. Events held back while waiting are not replayed.

## 6.2.0

Smoother nearby dots, faster player details, and more reliable communication.

### Smoother minimap movement

- Nearby players can exchange positions through paced addon whispers. Smooth movement favors up to four closest eligible peers and respects sharing preferences, filters, ignores, and traffic limits.
- Both players need this update for nearby streams and direct hover replies. Older versions keep normal broadcasts; server delays and restrictions can still affect delivery.

### Faster discovery and party details

- Hovering a player name or dot can request fresh details directly. Requests are rate-limited, and unchanged party member lists no longer expire after two minutes.
- Recent locations, partner status, and known party details survive /reload for up to three minutes from their original samples. Entering a zone also requests a paced discovery refresh.
- Tooltips use known solo or grouped status while waiting for an exact party size. Party member rows now identify QT users with a small logo, keeping names aligned.

### Clearer localization and presentation

- Race names, ping details, quest data, and more interface text use local translations when available. Unavailable quest translations retain readable sender text; progress avoids borrowing unrelated local objective descriptions.
- Generic announcements now use the QT logo. Looking for Questing Partners is the first option in the minimap menu.

### Communication and reliability

- Comparisons, party rosters, join and share requests, and ping replies prefer direct whispers with compatible peers. Consolidated heartbeats and fewer unchanged location updates reduce redundant public traffic.
- Fixed repeated quest scans, excessive nameplate retries, dialogs that could not close during restrictions, and /qt set accepting non-toggle settings. Disabling location sharing no longer drops unrelated queued requests.

## 6.1.2

More responsive nearby player dots and clearer translated announcements.

### Minimap player dots

- Fixed missing QT player dots when the minimap does not provide a map ID. QT now uses your current map when needed.

### Faster local location updates

- Location updates now target once per second with fewer than 10 known QT users in your zone, 5–10 seconds with 10–19, and 15–20 seconds at 100. Intervals lengthen gradually between these levels; timings at 500 or more are unchanged.
- Fast updates send compact, freshly sampled locations while other player details keep their slower heartbeat. Existing traffic limits still apply, so congestion may delay delivery. Other players need this update to send faster positions.

### Clearer translated announcements

- Quest event labels such as Quest Accepted now use your language even when a local quest title or optional translation metadata is unavailable.
- When WoW cannot provide a local quest title, QT keeps the sender’s readable title. Progress messages still retain their original text when they cannot be safely reconstructed.

## 6.1.1

Cleaner context menus for players and quests.

### Context menu cleanup

- Player-name and quest-name menus no longer include the log-window shortcut. Move QuestTogether logs between the main chat window and a separate window using the minimap menu or settings.

## 6.1.0

Find parties on the map, see who is questing together, and request to join through any party member. Player tooltips now put party details front and center.

### See who is questing together

- Grouped players now have a small two-person badge on their map and minimap dots. Hover a party member to give their companions a white outline, dim unrelated dots, and show a crown on the leader. Gold Looking for Questing Partners glows remain visible.
- Player tooltips list party members with class-colored dots and names, with the crowned leader first. Parties of up to five list all members; larger groups show only the leader. These details also appear when hovering player names in the QuestTogether log.
- Your own party uses the game’s roster. Remote party details load from updated QuestTogether peers when needed, with cached results and paced requests to keep channel traffic small. Older clients retain their normal dots and basic party-size information; full remote party details require an updated peer.

### Join requests can reach the party leader

- You can request to join through a party member who cannot invite you. If their leader is running QuestTogether and available to invite, the request is redirected to the leader using the usual confirmation and automatic-approval settings.
- If the leader is not known to be using QuestTogether, the member can announce “[QT] PlayerName is requesting to join the party.” in party chat when party-chat announcements are enabled. Someone with invite permission must then invite you manually.
- The requester and forwarding member need this update for redirected requests. Existing full-party, restriction, ignore, expiry, and request-rate checks still apply.

### Cleaner player tooltips

- Party information now sits immediately below the level, race, and class line, with compact member rows and space between sections. Alliance and Horde badges are twice as large.
- The addon version appears last in the shorter vX.Y.Z format. When a location’s age is shown, Last update sits directly above the version.
- Tracked quest counts have been removed from player and minimap-button tooltips. The active quest title for players looking for questing partners is still shown.

## 6.0.2

Browse QuestTogether’s past updates in your language, with better quest-name recovery for completion announcements.

### Browse past patch notes

- The welcome window now has Older and Newer buttons, a Latest shortcut, and a History picker showing release versions and dates. Opening patch notes starts at the latest release.
- The history includes every previous published release, including the early betas. All historical notes are translated into every supported WoW locale and included in the matching repository changelogs.
- Navigation buttons disable when there is nowhere to go. Browsing older notes does not change which upgrade you have acknowledged; automatic popups still appear only for major and minor upgrades. Open the window anytime with /qt notes.

### Quest completion titles

- When a quest leaves your log before QuestTogether has a usable title, completion announcements now try the game’s available quest-title lookup before falling back to a quest ID. A recovered title is preserved regardless of turn-in and removal event order.
- Announcements still use the sender’s text when your client cannot resolve a local title. If neither client has a name available, the quest ID remains the fallback. The improved sender-side recovery applies when the sender updates.

## 6.0.1

Celebrations now stay with players you can actually see nearby.

### Nearby celebration fixes

- Reactions to another player finishing a quest or leveling up now require a matching, visible player unit. Map coordinates or a name alone no longer trigger an emote, including when devlogall is enabled.
- Incoming emotes must match QuestTogether's own celebration list. Unlisted emotes, including mountspecial and faction cheers, are ignored without choosing a substitute.
- Your own quest-completion and level-up celebrations keep their existing behavior and settings.

## 6.0.0

QuestTogether 6.0 prepares for Forever launch with a communication system designed to reduce background traffic as the community grows.

### Local activity, worldwide discovery

- Quest announcements and frequent player updates now use zone channels. Party announcements still reach your group across zone boundaries.
- Player dots remain available across the world, with slower background updates. Opening another zone on the world map temporarily subscribes to its updates.
- QT text chat stays on the global QuestTogether channel. Your Global or Zone Only chat setting still controls which messages you see.

### Less background traffic

- Presence, version, quest counts, partner status and location are bundled into compact updates. Crowded zones update less often to reduce traffic.
- Announcements are paced and take priority over background updates. Ping replies are spread out to avoid a reply burst. WoW can still delay channel delivery; this update does not guarantee instant messages.
- Player tooltips show the age of older locations. Diagnostics now report message counts, throttling and sender-reported announcement delays.

### A major update during beta

- We are making this larger communication change now in anticipation of Forever launch. Beta is the best time to make these foundational decisions, before more players depend on the old behavior.
- Version 6.0 leaves QuestTogetherAnnounce1 and no longer sends or receives on that legacy channel. It uses QuestTogether for global chat and discovery, plus zone channels for local activity.
- QuestTogether keeps its channels after your other chat channels, with the main chat channel before its zone channels. Your location-sharing, ignore-list and announcement preferences are preserved.

### Compatibility with older versions

- Please update together. Older versions cannot read the new bundled player updates or listen to the new zone channels, so mixed-version players may miss map dots, partner status and nearby quest announcements.
- Players using only the legacy channel are no longer discoverable through that channel in 6.0. Some exchanges with newer 5.x versions can still work through the shared global channel or a group, but this is partial compatibility, not the full experience.
- Manual /qt ping still uses the global channel. It can hear compatible older clients there, but it is a best-effort discovery tool, not a complete count of everyone using QuestTogether.

## 5.17.2

QT chat is easier to distinguish from quest announcements.

### White QT chat text

- Messages from players in QT chat now use white text in the chat log and overhead bubbles.
- Player names keep their class colors, and quest announcements keep their yellow text.

## 5.17.1

See more about your questing companions and check quest status directly from chat tooltips.

### More useful player tooltips

- Player-name and map-dot tooltips now show how many quests QuestTogether is monitoring, plus Solo or Party of N. Your own tooltip uses your current local state.
- The minimap tooltip now counts quests monitored by QuestTogether, matching the startup announcement instead of counting only quests watched in WoW’s tracker.
- Remote quest counts and party sizes require an updated peer. They refresh about every 80 seconds through existing heartbeat messages, with no extra messages; missing or stale reports show as unknown. Older versions continue receiving compatible version announcements.

### Quest status on hover

- Hover a quest name in QT logs to see your quest status, shareability, quest ID, and locally tracked objective progress in a tooltip beside the cursor.
- The Status menu item has been removed. Clicking a quest name still opens Share, Open in Quest Journal, Compare Party Quests, and the log-window destination action.
- The new tooltip labels are translated into every supported locale. Quest details reflect your own progress, not the sender’s quest stage.

## 5.17.0

Say hello in QT chat, find questing partners across your zone, and discover clearer player details and settings.

### Chat with other QuestTogether players

- Type /qt <text>, or choose Send QT chat message from the minimap menu. Conversations appear in QT logs and nearby overhead bubbles with a speech-bubble icon; existing slash commands still work.
- Choose Global chat (the default), Zone Only, or hide QT chat entirely. Zone Only requires a recent shared location from the sender; Global does not.
- The new QuestTogether channel works alongside QuestTogetherAnnounce1 during the transition. QT places both after your other channels when supported, with QuestTogether first; typed chat uses only the new channel.

### Find questing partners

- Turning on Looking for Questing Partners announces your search throughout your zone with a gold-glow QT icon and a smiley. Zone-wide delivery requires location sharing and respects announcement preferences; turning it off stays silent.
- Control these messages in What to Announce. A 30-second cooldown limits repeated announcements while your status and glow still update immediately. You can also choose to stop looking automatically when joining a group; this starts off.
- Shift-click the minimap button to toggle your partner search. A brighter, pulsing gold ring highlights your active search without clipping the logo.

### Choose your range and see more player details

- Nearby Range now runs from 5% to Entire Zone, with a default of 25%. It scales distance across your current zone; party members and directly visible players retain their existing behavior.
- Hover names in QT logs for the same improved tooltip as map dots: a class-colored name, level, race, class, faction emblem, partner status, tracked quest when available, and QT version. Name tooltips now appear beside your cursor.
- Your own name tooltip now shows your current super-tracked quest while looking for partners. Updated clients advertise versions about every 40 seconds using existing heartbeat messages; older clients keep their previous schedule.

### Clearer controls and announcements

- The minimap tooltip now shows your QT version, partner status, chat scope, watched quest count, nearby range, and location-sharing status.
- Settings controls now have translated explanations on hover, including dropdowns, sliders, profile actions, and color controls.
- When your client cannot resolve a localized quest title, announcements preserve the sender’s original text in both logs and bubbles instead of showing a generic quest number. Localized rendering resumes for later announcements once the title is available.

## 5.16.7

Read the same QuestTogether release notes in-game, on Discord, and in your preferred language in the changelog files.

### Consistent, multilingual changelogs

- The English changelog now shares the same release summaries and bullet points as the welcome window and Discord announcements.
- Changelog files are available for all supported locales, with existing translated release history and a preserved copy of the older handwritten English notes.
- Release checks keep the changelog files synchronized with the canonical notes and translations.

## 5.16.6

See at a glance when you are looking for questing partners.

### A glowing minimap reminder

- Your QuestTogether minimap button now pulses with the same gold logo glow as player nameplates while Looking for Questing Partners is on.
- The glow follows your partner status and stops when QT is disabled or the minimap button is hidden. Your button and logo keep their existing size.

## 5.16.5

A shorter prefix keeps party announcements compact.

### Compact party announcements

- Quest progress posted to party members without QuestTogether now starts with [QT] instead of [QuestTogether].
- Announcements still respect the chat message limit and preserve complete characters in every language.

## 5.16.4

Keep your bubble settings when leaving Edit Mode and find nearby questing companions on crowded maps.

### Bubble settings stay saved

- Closing HUD Edit Mode now preserves your QT bubble font size, display duration, and position instead of reverting them.
- The QT bubble panel now has its own Save Changes button and saved-state message. Settings apply automatically; Save Changes sets the point that Revert Changes returns to.
- After saving and making further adjustments, Revert Changes restores your last saved QT settings.

### Nearby players get priority

- When more than 128 eligible dots compete for space on the map or minimap, the closest players get priority based on distance from your character.
- When the 512-location cache fills, closer players are retained ahead of more distant arrivals. Map panning and zooming do not change proximity priority.
- These changes keep the existing dot and cache limits without sending additional communication messages.

## 5.16.3

Find the settings you need more easily and see your QuestTogether preferences at a glance.

### Settings organized around how you play

- Groups & Sharing replaces Miscellaneous, bringing partner availability, join requests, and quest-sharing approvals together.
- Celebration emotes now live under Where to Announce. Minimap visibility is under General on the main page, with debug tools and quest-log rescanning together under Troubleshooting.
- Compare Party Quests and Find Questing Partners are now the first Quick Actions. Your existing preferences are preserved.

### A more useful Quick Status

- See your partner status, location sharing and display preferences, request approvals, announcement output, and quest and player nameplate settings in linked sections.
- Check your active profile, installed version, and any detected newer version. When QT is disabled, the summary clearly identifies the settings as saved preferences.
- Click a section heading to open its settings. The summary grows to fit its text and stays current while the page is open.

## 5.16.2

Recognize QuestTogether players from their tooltips and spot questing partners more easily.

### QuestTogether player tooltips

- Hover a QT player’s character, nameplate, or unit frame to see “This player is using QuestTogether.” Players looking for questing partners also show that status and a glowing QT logo.
- The QT section matches the tooltip’s width and scale, sits clear of its health bar, and moves above the tooltip when space below is limited.

### A more visible partner glow

- The gold nameplate glow now reaches twice as far around the logo while keeping the logo itself the same size.
- Icons and glows reflect real QT users and their current partner-seeking status.

## 5.16.1

Find questing partners more easily and see which quest they are focusing on.

### A brighter partner glow

- Players looking for questing partners now have a brighter gold glow around their QT nameplate logo, with a gentle breathing pulse. The logo itself stays steady.

### See their current quest

- Hover the map or minimap dot of a player looking for questing partners to see their super-tracked quest—the single quest selected for navigation. Both players need this update.
- Quest information refreshes about every 20 seconds. It is shared only while Looking for Questing Partners and location sharing are enabled.
- Quest names use your client language when available, with the sender’s title or quest ID as a fallback. Older QT versions keep their existing dots and partner indicators.

## 5.16.0

QuestTogether now supports every WoW language and can display other players’ quest updates in your client’s language.

### Play in more languages

- Menus, settings, and patch notes now support all WoW language locales: English, German, French, European Spanish, Latin American Spanish, Brazilian Portuguese, Russian, Italian, Korean, Simplified Chinese, and Traditional Chinese.
- Latin American Spanish now has its own text instead of sharing European Spanish.

### Localized quest progress

- Supported quest events from updated QT players can appear in your client language in QT chat logs and bubbles, using local quest titles when available and the sender’s actual progress numbers.
- When a translated objective description cannot be chosen safely, QT uses a localized objective number with counts, percentages, completion, or progress status instead.
- Older QT versions and public party chat retain the sender’s wording. When WoW cannot supply a local quest title, QT keeps the source title or shows the quest ID. Same-language events keep their detailed native wording.

### Quest title polish

- Quest comparison now prefers your local quest title when available.
- Localized quest titles with non-ASCII punctuation stay clickable more reliably.

## 5.15.0

Ask to join a questing party directly from a QuestTogether player menu.

### Join a questing party

- Grouped QT players now show Request to Join instead of Invite when recent party information is available. Both players need this update; the requester must be solo.
- The recipient can send a normal WoW invitation or decline. They must have invitation permission and room in an ordinary party. You still accept the normal invitation to join.

### Optional automatic invitations

- Two new options automatically approve requests from character friends, or from other players while you are Looking for Questing Partners. Both start off and appear in the prompt and Miscellaneous settings. Battle.net account friends are not included.
- Requests expire and respect ignores, party changes, and game restrictions. QT never leaves your current group or accepts invitations for you.

## 5.14.1

Party announcements now show the full QuestTogether name.

### Party chat

- Expanded the party-chat announcement prefix from [QT] to [QuestTogether], making it easier for other players to find the addon.

## 5.14.0

QuestTogether now speaks five more languages and helps you keep party members without QT informed.

### Play in your language

- The interface is now available in German, French, Spanish, Brazilian Portuguese, and Russian. QuestTogether follows your game language, with English as the fallback.
- Settings, menus, tooltips, quest comparisons, and patch notes are translated. Quest names and progress text received from other players stay in their original language.
- Find translated release announcements in the five language-specific changelog channels on our Discord.

### Keep your whole party informed

- A new Where to Announce option sends your enabled event announcements to party chat when someone in your party has not been recognized as a QT user. It starts enabled and can be turned off in settings.
- This also works in matched instance parties. Solo play and raids are excluded, and other players’ announcements are never relayed.

## 5.13.1

This maintenance update improves quest-plate recovery, clears stale bubbles and player logos, and keeps settings and the debug window behaving consistently.

### Quest plates and player indicators

- Quest icons and health tints recover correctly after restricted views close. Delayed quest scans retain their settling time, and temporarily missing tooltip data keeps its retry budget.
- Announcement bubbles are cleaned up when a player plate disappears or is reused during combat. Protected or forbidden frames wait for safe cleanup.
- Map locations and player presence recover after disabling QuestTogether, changing zones, and enabling it again. Departed players no longer regain a QT logo from late location or partner-status withdrawals.

### Settings and window fixes

- The Looking for Questing Partners checkbox stays synchronized when status changes through commands, menus, or profile settings.
- The debug window safely finishes interrupted drag and resize gestures when restrictions lift, even after it has been hidden.

### Reliability improvements

- Strengthened tests detect forbidden frame access even when an error is caught internally.
- Release checks now refuse to publish while implementation changes remain uncommitted, helping ensure fixes actually reach the download.

## 5.13.0

Find questing partners at a glance with highlighted map dots and player logos, simpler location settings, and reminders when another player has a newer stable QuestTogether release.

### Spot questing partners

- Players looking for questing partners have a soft gold glow around their class-colored map and minimap dots.
- Their QuestTogether nameplate logo gets a soft gold glow. Highlights disappear when the status is turned off or expires.
- Player Locations settings includes Only show players looking for questing partners. It starts off and filters both maps when enabled.
- The in-game What's New window shows regular and glowing logos and map dots side by side. Gold glow means looking for questing partners.

### Simpler location settings

- Share my location and Show other players each apply to both the world map and minimap.
- Both options start enabled for new profiles. Existing location-sharing opt-outs are preserved when upgrading.

### New-version reminders

- QuestTogether notices when another player reports a newer stable addon version and prints an update reminder in your chosen QuestTogether chat window.
- The reminder is saved across characters and appears once each reload until you install the detected release or a newer one. Alpha and beta versions do not trigger reminders.
- Version announcements are small and infrequent. QuestTogether also recognizes version information in existing ping replies.

## 5.12.0

Find people to quest with using the new Looking for Questing Partners status. This update also improves minimap tooltip visibility and separates Retail War Mode and realm behavior from Forever.

### Looking for Questing Partners

- Let other QuestTogether users know you want company. Your status appears in your player menu and on map-dot tooltips; it does not enable location sharing or send invitations.
- Toggle the status from the minimap menu, Settings > Miscellaneous, or /qt lfg. Use /qt lfg on, off, or status to set or check it. It starts off and is saved per profile.
- Partner status expires when updates stop. Ignored players are excluded, and disabling QuestTogether pauses your advertisement.

### Retail and Forever

- Forever no longer shows War Mode in player-dot tooltips, quest location details, or ping output. Forever pings also omit realm labels while preserving complete player names.
- Nearby quest updates on Forever no longer require Retail War Mode information. Map dots remain visible across phases so you can find people to group with.
- Retail uses the active War Mode state when available. Unknown or unsupported War Mode is no longer reported as Off.

### More stable player dots

- Briefly missing coordinates no longer remove your dot immediately. Last reported positions remain for up to two minutes, and older reports show their age in the tooltip. Sharing opt-outs still withdraw immediately when communication is available.
- Movement broadcasts are limited to once every ten seconds, reducing location traffic. Stationary heartbeats remain every twenty seconds so older clients stay compatible.
- The location cache now retains up to 512 players. Each map still draws at most 128 visible dots, and players outside the displayed map no longer use up that drawing limit.

### Reliable player logos

- Fix missing logos on friendly player nameplates in current Forever and Retail clients by reading the current friendly-player visibility setting.
- Left-positioned logos move outward to make room for visible buffs, then return to their usual position when the buffs disappear.
- All supported QuestTogether messages now identify their sender. A bounded cache remembers players for the current UI session, so missed heartbeats no longer remove their logos. Explicit departures and ignored players are still cleared; no extra messages are sent.

### Minimap polish

- The QuestTogether minimap tooltip now uses an independent tooltip layer so it can appear over action bar UI. It hides when the button becomes unavailable or restrictions begin.

## 5.11.0

QuestTogether now adds player locations, player plate logos, focused quest comparisons, and easier Discord feedback and support. Settings let you choose what you share and what you see while quest progress stays coordinated with other QuestTogether users.

### Find QuestTogether players nearby

- Show the scroll logo beside friendly QuestTogether players when WoW's friendly nameplates are on. Player Plates are enabled by default, with a padded Left position; choose Left, Right, Top, or Prefix without changing health-bar colors.
- Class-colored player dots can appear on the world map and minimap for players sharing their location. Hover a dot for name, faction, race, class, and level; click it for the QuestTogether player menu.
- Player Locations has separate sharing and viewing switches for the world map and minimap, and all four start enabled. Presence for player plate logos can continue even when both location sharing switches are off.
- Locations refresh periodically and disappear when they expire. Both players need the updated addon; a dot does not guarantee that you share the same phase or layer.

### Compare one player or the whole party

- The player menu Compare Quests action now compares only you and the selected player, including reachable nonparty QuestTogether peers. Whole-party comparison stays available from the minimap menu, quest-name menus, and /qt compare.
- Quest sharing and share requests remain party-only. Targeted comparisons explain when a party is needed for sharing and when the selected player needs QuestTogether to respond.
- If a share request is already waiting on another player, the comparison now shows who it is waiting for after you switch targets.

### Feedback and support

- The welcome window and main settings page now include Discord — Feedback & Support. It opens a copyable invite when available, or prints the invite in chat if the link window cannot open.

### Fixes and polish

- Ignored players are now filtered more completely. New logs, bubbles, dots, comparisons, and share work are suppressed, while existing bubbles and locations are cleared when the ignore list changes.
- Fixed false quest plates caused by unavailable tooltip boundaries matching another quest's objective text.
- Turning off map or minimap sharing now retries the update after temporary communication failures. Turning off both sharing options also removes location details from other addon updates.
- Player logos clear correctly when a player's presence expires just before they leave. Whisper from map dots opens your chat window, and changing the log destination from Settings is unavailable during restrictions.

## 5.10.0

QuestTogether shares quest progress with your party and nearby players. Use the minimap button for settings, party quest comparisons, your quest journal, and these latest notes.

### Compare and share party quests

- Open Compare Party Quests from the minimap or quest and player menus, or type /qt compare. See who has each quest and how far everyone has progressed.
- All party quests appear by default. Check Hide quests I don't have to focus on quests in your own journal.
- Request shareable quests from party members using the updated addon. Requests ask permission by default; automatic sharing is an optional setting.
- Comparisons recover after map or combat restrictions. Refreshes replace older replies, and request cooldowns and failures explain when you can try again.

### Shortcuts and quest menus

- Drag the scroll-shaped minimap button to reposition it. Its menu opens settings, comparisons, the quest journal, patch notes, and the log-window destination control. Hide it from the menu and restore it in Miscellaneous settings.
- Quest-name menus offer Status, Share, Open in Quest Journal, and Compare Party Quests. Sharing and journal actions recheck the current quest and restrictions when clicked.
- Quest status links keep their titles intact after a quest leaves your log. The automatic-sharing checkbox now follows saved settings and profile changes.

### Help and latest notes

- Read the welcome and latest patch notes in their own window instead of repeated chat messages. Choose Patch Notes from the minimap menu or main Settings page, or use /qt notes, /qt changelog, or /qt patchnotes.
- The notes window opens automatically for major and minor upgrades. Patch updates still include fresh notes without opening the window automatically.
- Use /qt help for normal commands and /qt help debug for previews, diagnostics, and developer commands.

## 5.9.2

Left- or right-click a quest name in the QuestTogether log to open its menu, with Status first and Share second. Share uses the current quest-log entry without changing Blizzard's selected quest, and is unavailable when solo, restricted, or the quest cannot be shared. After a separator, the final option moves QuestTogether logs between the main and separate windows, matching QT's player-name menu.

### Changes in this release

- Make quest names in status messages clickable, including fallback titles from other players' logs. Preserve existing quest links when formatting completed quest comparisons so status details do not become part of a second, broken link.
- Validation: 521 tests pass in normal and reverse order on Lua 5.1 and 5.2. All six client API profiles, Lua and shell syntax checks, exact libchev verification, and diff checks pass. Live-client menu behavior, quest-share delivery, and engine-level taint validation remain separate.

## 5.9.1

Fixes quest tracking, quest plate visibility, task-area announcements, communication reliability, and user actions identified in the comprehensive audit.

### Changes in this release

- Prevent unrelated tooltip quest blocks from borrowing shared objective text. Preserve valid party progress and recover plates after map, instance, roster, and quest changes.
- Keep newly accepted quests and initial scans pending until readable data arrives. Preserve objective milestones, task classification, and unknown location state without false exits or duplicate entries.
- Improve localized announcements and quest comparisons, including payload limits, pacing, retries, cancellation, and shareability reporting.
- Honor native waypoint failures without tracking an old pin. Decline restricted clicks while disabled instead of losing queued work.
- Make bubble tests local previews and accept full Forever names or quoted names, while preserving exact player identity.
- Correct enable/disable and profile handling, HUD Edit Mode opening, approved celebration emotes, and diagnostics.
- Strengthen live-safe test isolation and regression coverage, correct faulty test assumptions, and make CI propagate Lua syntax failures.
- Validation: 516 tests pass in normal and reverse order on Lua 5.1 and 5.2. All six client API profiles, syntax checks, exact libchev verification, and diff checks pass. Live-client rendering, two-client delivery, and engine-level taint validation remain separate.

## 5.9.0

Celebrate your own and nearby QuestTogether players' level-ups with synchronized emotes. Add separate, enabled-by-default level-up emote toggles beside the quest completion emote settings in Miscellaneous. Nearby reactions respect the existing player scope and proximity rules.

### Changes in this release

- Remember confirmed quest-objective completion by creature type as well as individual spawn. Mobs that appear during combat stay unmarked when tooltip data is unavailable, even if an older spawn was cached as needed. Fresh unfinished objectives can restore highlighting; quest-state changes clear completion memory. Partial or inaccessible tooltip data is never treated as proof that everyone is done.
- Clear quest nameplate icons and health tint immediately when a mob's tap is denied, including during combat. Listen for ownership changes and recheck taps on health and threat updates.
- Detect newly encountered quest mobs during ordinary open-world combat using readable unit tooltip data. Refresh plates when they return from behind the camera, become your target, or are moused over. Retry delayed frames, GUIDs and tooltip quest lines with a bounded per-unit budget, cancel stale work when units are removed, and restore tint and icon together. Preserve map, instance, inaccessible-data and protected-frame guards; combat discovery does not invoke Questie or hidden tooltip UI.
- Validation: 374 offline tests pass in normal and reverse order on Lua 5.1 and 5.2. Six client API profiles, Lua syntax checks, exact library verification and diff checks pass. Completion-cache regressions reproduced the bug before the fix. Live gameplay and engine-level taint validation remain separate.

## 5.8.6

Harden character names, class names, quest titles and custom class colors against inaccessible or malformed API values. Validate optional TomTom and Questie integration data before using it, and stop reading Questie tooltip lines at inaccessible data. Normalize bubble visibility and edit-mode state to booleans before passing them to UI controls.

### Changes in this release

- Consolidate the loading-screen event handler, remove unused private arguments and an unused restriction-enum branch, and clarify callback and return-value handling. Keep modern/legacy client fallbacks and the exact private library revision intact.
- Validation: 336 tests pass in normal and reverse order on Lua 5.1 and 5.2, with expanded adapter checks across six client profiles. New regressions fail against the previous implementation. Lua parsing, exact library verification and diff checks pass. Reviewed the remaining Ketho WoW API/LuaLS diagnostics, including a separate pass without offline client mocks; retained findings have specific compatibility, guard, callback, library or fixture reasons. Live Retail and Forever gameplay validation remains separate.

## 5.8.5

Fix task/world-quest map discovery on modern clients by reading questID from C_TaskQuest.GetQuestsOnMap, while retaining the legacy API and questId field for older clients. Prefer C_ChatInfo.PerformEmote so completion emotes work when deprecated globals are disabled; safely handle missing or failing emote APIs.

### Changes in this release

- Remove an unused party-roster fingerprint calculation and unused local variables. Extend offline client checks to cover modern and legacy task/emote APIs, API precedence, inaccessible quest data, and missing/failing APIs. Validation: 334 tests pass in normal and reverse order on Lua 5.1 and 5.2, plus the expanded API checks on six client profiles, Lua parsing and exact library verification. Gameplay validation in Retail and Forever remains separate from offline checks.

## 5.8.4

Repository housekeeping: keep local development notes outside the tracked source and release packages. Gameplay behavior is unchanged.

### Changes in this release

- Repository housekeeping: keep local development notes outside the tracked source and release packages. Gameplay behavior is unchanged.

## 5.8.3

Announce the installed version, supported clients and settings command once per login or UI reload. Include addon-specific CurseForge and GitHub feedback links; clicking a link opens a native-style copy window. Share message behavior and safe copy UI through private libchev 1.2.0. If link registration or the copy window is unavailable, show the full URL in chat. An unavailable welcome helper cannot interrupt normal addon startup.

### Changes in this release

- Validation: 334 tests pass in both orders on Lua 5.1 and 5.2, with client API checks, Lua parsing and exact library vendor verification. NoPoizen smoke simulations exercise both feedback links on all seven client/ruleset profiles. Live rendering remains a separate check.

## 5.8.2

Isolate test fixture GUID lookups from nearby players. Fix two false failures in /qt test when a real unit occupies the nameplate token used by the tooltip and cached-icon checks. Gameplay nameplate behavior is unchanged.

### Changes in this release

- The offline environment now includes that token collision and reproduces both failures without the fixture fix. All 333 tests pass in both orders on Lua 5.1 and 5.2 after the fix; six client API profiles also pass. In-game confirmation remains separate.

## 5.8.1

Show Blizzard's quest marker beside QuestTogether in the AddOns list instead of the default question mark.

### Changes in this release

- Show Blizzard's quest marker beside QuestTogether in the AddOns list instead of the default question mark.

## 5.8.0

Support current Classic clients with correct quest-acceptance payloads, guarded objective API fallbacks, honest unknown shareability, flavor metadata and six-client API regression checks. Preserve Retail/Forever behavior and shared debug utilities.

### Changes in this release

- Validation: 333 tests pass in both orders on Lua 5.1 and 5.2, with six client profiles, Lua parsing and exact private-library vendor checks. NoPoizen client smoke checks and package verification also pass. Live validation of the new adapters remains pending.
- See CLIENT_COMPATIBILITY.md for source evidence, scope and validation limits.

## 5.7.7

Keep overlapping debug consoles and their controls in one native stacking group through private libchev 1.1.3. Category menus stay with their owning console.

### Changes in this release

- Default quest objective icons to the left of the nameplate. Existing saved icon positions remain unchanged.
- Respect Forever's “My Last Name” setting when displaying your character's name. Keep other players' surnames visible, matching the native setting's scope. Use full names consistently for communications, group membership, nameplate matching, and social actions while preserving existing profile and personal bubble position keys.
- Fix duplicate local quest announcements caused by receiving your own channel message under a different full-name format. Regression coverage exercises the local announcement followed by its channel and party echoes, including another character with the same first name.
- Validation: 331 tests pass in both orders under Lua 5.1/5.2. Live confirmation of the new icon default and multi-window interaction remains separate.

## 5.7.6

Use the same private libchev 1.1.2 debug console across all three addons, including category/search filters, copy controls, test results, diagnostic reports, timestamps when available, and a single final test summary. Fix stretched native frame artwork with explicit texture bounds.

### Changes in this release

- QuestTogether supplies its own quest diagnostics and isolated tests while the shared library owns the console and generic debug behavior. Run /qt test, /qt debug, or /qt diagnostics.
- Validation: 324 tests pass in both orders on Lua 5.1/5.2. The user confirmed the corrected frame appearance in-game. Other live restriction and gameplay validation remains separate.

## 5.7.6-beta.3

QuestTogether 5.7.6-beta.3 updates the embedded shared debug console to libchev 1.1.1.

### Changes in this release

- Restores the native WoW-style window appearance across the addons' shared console.
- Removes the duplicate test-summary line while retaining the final summary in bounded history.
- Keeps the common search, category, copy, scrolling, test, and diagnostic behavior and existing restriction guards.
- The user reported all 324 QT tests passing in Forever 1.60.1 build 70009 on beta.2. QT's seven live-loaded test files were also audited for invalid arithmetic; no NaN-generation or division-by-zero fixtures were found. That earlier live test result does not validate this new appearance change.
- After /reload, open /qtd, run /qt test, and check the window appearance and single summary. Live rendering and restriction/taint behavior for this revision still need client verification.
- Validation: all 324 cases pass forward/reverse on actual Lua 5.1.5 and 5.2.4, each CLI run emits one summary, and the extracted 26-file installable ZIP passes on both versions. All 23 Lua files parse; all 22 TOC entries and the vendor manifest verify. Formatting and diff checks pass. Library pin: 2feea04bab60ba1c1b91bd01ab8a58ce02e091a9. No QT GitHub CI is configured; upstream library CI passed.

## 5.7.6-beta.2

QuestTogether 5.7.6-beta.2 replaces its separate debug window with the shared libchev v1.1 console used across the addons. The embedded library is included; no separate installation is required.

### Changes in this release

- Shared category filtering, fuzzy/quoted search, copy/select, clear, reload, tests, diagnostics, and scroll-following behavior.
- /qt test opens the current results; repeated runs replace old TEST history and clear stale search filters.
- /qt diagnostics [questID] and /qt diag [questID] rebuild the current cached report in the same console, retaining recent events within the shared export budget.
- Shared restriction and owned-frame guards replace QT's old console callbacks and dropdown implementation.
- Quest state, announcements, nameplates, comms, and QT-specific test isolation remain owned by QuestTogether.
- This is a beta release. Live Retail/Forever rendering and taint behavior still need verification. After /reload, run /qt test and /qt diagnostics, then exercise category/search, copy, clear, resize, scrolling, repeated test runs, and switching between reports and logs. Include combat/restriction transitions and your usual addon set.
- Validation: 324/324 tests pass in both orders under Lua 5.1.5 and 5.2.4. All 23 Lua files parse, all 22 TOC entries validate, and the pinned library manifest verifies. The installable ZIP was extracted and passed all 324 cases using the separate offline harness. Library pin: 1f2cd0eaabb692fd0befd51dbdadeb7e07beb3c6.

## 5.7.6-beta.1

QuestTogether 5.7.6-beta.1 embeds libchev v1.0.0 to share logging, diagnostics, callback guards, deferred-work mechanics, and test execution with the other Together addons. The library is included; no separate addon installation is needed.

### Changes in this release

- Diagnostic reports include common client/addon/library information and retain the newest events when the copy window fills.
- Quest, party, nameplate, and restriction behavior remains owned by QuestTogether, with isolated per-addon runtime stores.
- Coordinate links remain usable while QT is disabled when restrictions allow them; queued background work stays paused and stale timers are discarded.
- /qt test now includes 315 cases: the existing 300, ten shared library checks, and five integration regressions.
- Validation: all 315 tests pass in both orders under Lua 5.1.5 and 5.2.4; Lua syntax, TOC load order, and the embedded revision/hash manifest pass. Embedded libchev source: 09ac76eb6fe8e9589b809188652950c3cd9e444c.
- This is a beta release. Live Retail/Forever UI rendering and taint behavior after this extraction still need verification. After reloading, run /qt test and /qt diagnostics, then exercise quests, progress bubbles, nameplates, and coordinate links across combat, zoning, disable/re-enable, and reload with your usual addons. The earlier Retail 300-test confirmation applied to v5.7.5.

[Earlier handwritten changelog](changelogs/legacy-enUS.md)
