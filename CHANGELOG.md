# QuestTogether — Changelog

<!-- Generated from canonical release notes; do not edit by hand. -->

[Other languages](changelogs/README.md)

## 6.0.0

Celebrations now stay with players you can actually see nearby.

### Nearby celebration fixes

- Reactions to another player finishing a quest or leveling up now require a matching, visible player unit. Map coordinates or a name alone no longer trigger an emote, including when devlogall is enabled.
- Incoming emotes must match QuestTogether's own celebration list. Unlisted emotes, including mountspecial and faction cheers, are ignored without choosing a substitute.
- Your own quest-completion and level-up celebrations keep their existing behavior and settings.

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

[Earlier handwritten changelog](changelogs/legacy-enUS.md)
