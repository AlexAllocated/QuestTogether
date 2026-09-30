# QuestTogether

**Quest progress, party quest comparisons, sharing shortcuts, and nearby players—all in one addon.**

QuestTogether helps you keep track of what your friends are doing while you quest. See objective progress above nearby players, find out who still needs a quest, share eligible quests with your party, and spot other QuestTogether users on your maps and friendly nameplates.

Use it with a regular questing group, a friend leveling an alt, or other QuestTogether players you meet along the way. Choose which updates matter to you and where they appear.

[Join the QuestTogether Discord for feedback and support](https://discord.gg/Uxyyvhfva9)

> **SCREENSHOT 01 — Questing together:** A party fighting quest mobs, with a progress bubble above a player, quest icons on relevant enemies, and the QuestTogether chat log visible.

## Follow quest progress as it happens

QuestTogether exchanges quest updates with other users of the addon and displays them on your own client. Keep track of the full questing cycle:

| Quest activity | Updates |
| --- | --- |
| Regular quests | Acceptance, objective progress, ready to turn in, completion, and removal |
| World quests | Entering or leaving an objective area, progress, and completion |
| Bonus objectives | Entering or leaving an objective area, progress, and completion |

Turn individual event types on or off under **What To Announce**. Those choices control the corresponding updates you send and display.

Choose **Party Only** or **Party & Nearby Players** to control whose progress you see. You can keep things focused on your group or enjoy updates from other QuestTogether players nearby.

## Put updates where you want them

Use chat bubbles, chat logs, or both.

**Chat bubbles** show updates above nearby players when their nameplates are available. Your own updates appear at a personal bubble anchor that you can position through **HUD Edit Mode**. The QuestTogether Bubble settings let you adjust bubble size and display duration.

You can hide your own bubbles while continuing to send your progress to other players.

**Chat logs** can go to the main chat window or a separate QuestTogether window. Keep that window docked as a tab or float it beside your other UI. If it is docked, an optional setting also prints updates to main chat; floating windows keep their output separate.

Switch the log destination from settings or directly from QuestTogether's player, quest, and minimap menus.

> **SCREENSHOT 02 — Chat your way:** QuestTogether updates in a dedicated chat window, showing player names, clickable quest names, objective progress, and completion messages.

> **SCREENSHOT 03 — Personal bubble customization:** HUD Edit Mode with the QuestTogether Bubble anchor selected and its size/duration controls visible.

## Compare your party's quests

Open **Party Quest Compare** with `/qt compare`, or choose **Compare Party Quests** from the minimap or quest-name menu.

The movable comparison window uses familiar WoW styling, with each quest on one row and each group member in a column. Text and color show whether a player has the quest, is ready to turn it in, or is missing it. **Loading** and **Unknown** distinguish an unanswered request from a confirmed missing quest.

- See the combined quest lists by default, including quests you do not have.
- Check **Hide quests I don't have** to focus on your own quests. The choice is saved in your profile.
- Use **Refresh** to request updated quest lists from other players. Your own list updates as your quest log changes.
- Scroll through longer quest lists and across wider groups; scrollbars appear only when needed.
- Hover quest rows for the full title, quest ID, and the selected owner for a share request when applicable.

You can also compare with one person. Choose **Compare Quests** from a player's name or map-dot menu to open a comparison between just you and that player. This includes reachable QuestTogether users outside your party, making it easier to decide whether you should quest together.

> **SCREENSHOT 04 — Party Quest Compare:** A realistic three-player comparison with Have, Ready, and Missing states, plus Share and Request Share buttons. Leave “Hide quests I don't have” unchecked.

## Share quests with fewer steps

The comparison window puts sharing actions beside the quests that need them:

- **Share** appears beside an eligible quest you own when another member is known to be missing it.
- **Request Share** lets you ask an eligible party member for a shareable quest you do not have. Both players need a version that supports share requests.
- You can also share an eligible quest directly from its name menu in a QuestTogether chat entry.

Incoming requests **ask for confirmation by default**. The owner sees who is asking and which quest they want, then chooses **Share** or **Decline**.

For regular questing partners, check **Always allow party share requests** before confirming. You can change that preference at any time under **Miscellaneous** in settings. This automatically approves eligible requests from any current party member; the recipient still handles WoW's normal quest-acceptance prompt.

Sharing is per quest and requires a party together. WoW's normal shareability and recipient eligibility rules still apply. A share attempt does not guarantee that another player can receive or accept the quest, and unavailable actions explain why they cannot be used.

> **SCREENSHOT 05 — Sharing consent:** An incoming share request showing the requester, quest title, Share/Decline buttons, and “Always allow party share requests” checkbox.

## Find QuestTogether players on your maps

Other QuestTogether users appear as small **class-colored dots** on the world map and minimap when location sharing and viewing are enabled.

Hover a dot to see the player's **name, faction, race, class, and level**, when available. Click it to open the same player menu used in QuestTogether chat logs.

The **Player Locations** settings have two independent controls, each applying to both the world map and minimap:

- **Share my location** — let other QuestTogether users see your dot.
- **Show other players** — display players who share their location.

Both start enabled for new profiles. Turning sharing off also removes location details from your quest announcements and ping replies. Existing sharing opt-outs are preserved when upgrading.

Enable **Only show players looking for questing partners** to filter both maps to LFG players. This filter starts off.

On Retail, tooltips also show War Mode when available. Forever omits realm and War Mode labels. Dots remain visible across phases to help you find people to group with.

Locations update periodically. Brief gaps retain the last reported dot for up to two minutes; older reports show their age in the tooltip. Turning location sharing off removes the dot when the withdrawal arrives, with expiry as a fallback. Both players need a version that supports location sharing. A dot represents a recently reported location; it does not guarantee that the player is in your phase or layer.

> **SCREENSHOT 06 — Players on the map:** World-map and minimap views with several class-colored dots. Hover one dot to show the player-details tooltip.

## Find a questing partner

Turn on **Looking for Questing Partners** to let other QuestTogether players know you want company. Your status appears in your player-name menu and on your map-dot tooltips. A soft gold glow makes your dots stand out on both maps, and your QT nameplate logo gains a soft gold glow. Others can use the existing Whisper, Invite, or Compare Quests actions to get in touch.

Toggle it in the **minimap menu**, **Settings → Miscellaneous**, or with **`/qt lfg`**. Use `/qt lfg on`, `/qt lfg off`, or `/qt lfg status` for an explicit action. The status starts off and is saved per profile. It does not enable location sharing, send automatic invitations, or post recruitment messages in public chat.

Status expires when updates stop, and ignored players stay hidden. Disabling QuestTogether pauses your advertisement. Both players need a version that supports partner status.

> **SCREENSHOT — Questing partners:** Glowing map dots and a glowing QT player logo, alongside the LFG map filter and minimap menu shortcut.

## Ask to join a questing party

When a QT player's recent metadata says they are already grouped, their player
menu offers **Request to Join** instead of Invite. The recipient sees who is
asking and chooses **Send Invitation** or **Decline**. They must be able to invite
and have room in an ordinary party. The requester still accepts WoW's normal
invitation. QT never leaves your current group for you.

The prompt and **Miscellaneous** settings offer two independent, initially-off
preferences: automatically invite friends who request to join, and automatically
invite others while Looking for Questing Partners is on. Friends means your
character friends list. Requests expire and are rate-limited; ignored players
cannot request entry. Both players need a version supporting join requests.

## Spot quest objectives on nameplates

**Quest Plates** adds an optional quest icon to relevant Blizzard nameplates and an optional health-bar tint for quest objectives.

Choose **Left**, **Right**, **Top**, or **Prefix** placement. Prefix places the icon before the unit's name; Left is the default. Choose your preferred quest health color, reset it to the default, or turn the tint off while keeping icons.

The settings preview shows your choices using the current WoW nameplate style. Decorations follow available quest-objective information, including unfinished party objectives exposed by the game, and update as that information changes.

> **SCREENSHOT 07 — Quest Plates:** A quest mob with its icon and health tint, alongside the Quest Plates settings preview and position choices.

## Recognize nearby QuestTogether users

**Player Plates** displays the QuestTogether scroll logo beside friendly players who are using the addon.

Enable friendly nameplates in WoW, then choose **Left**, **Right**, **Top**, or **Prefix** placement in QuestTogether's Player Plates settings. Player icons start enabled with Left placement, include a gap between the logo and the bar or name text, and have their own preview and visibility toggle.

Player icons leave health-bar colors alone. Identification works from any supported QuestTogether message, even when location sharing is off. Recognized players remain known for the current UI session in a bounded cache; missed heartbeats do not remove their icons. Explicit departures and ignored players are cleared.

Quest and player decorations follow the addon's open-world nameplate policy. Instances, unavailable nameplates, and game restrictions can limit their display.

> **SCREENSHOT 08 — Player Plates:** A friendly QuestTogether player with the scroll logo beside their nameplate, plus the Player Plates settings preview.

## Act directly from chat

Left- or right-click linked names in QuestTogether's log to open their menus.

**Player-name menus** provide Invite, Whisper, Add Friend, Ignore/Unignore, and Compare Quests, plus the shortcut to move QuestTogether logs between main and separate chat windows.

**Quest-name menus** provide:

- **Status** — print the quest's local status and shareability when available.
- **Share** — share an eligible quest you currently own with your party.
- **Open in Quest Journal** — open that quest's journal entry when it is in your log.
- **Compare Party Quests** — open the whole-party comparison.
- The same shortcut to move QuestTogether's logs.

Coordinate links, when included in an update or ping reply, can create a **TomTom waypoint** if TomTom is installed, with a **Blizzard waypoint** fallback where supported.

> **SCREENSHOT 09 — Clickable chat:** Player-name and quest-name menus, with a quest status line and coordinate link visible nearby.

## Celebrate together

QuestTogether can play celebration emotes when you complete quests or gain a level, and respond to nearby QuestTogether players' celebrations.

There are four separate toggles under **Miscellaneous**: your quest completions, nearby players' quest completions, your level-ups, and nearby players' level-ups. Nearby reactions respect your player-scope setting. World quest and bonus-objective completions participate in quest-completion celebrations.

## Know when an update is available

When another player reports a newer stable QuestTogether release, you get a reminder in your chosen QuestTogether chat window. It appears once when first detected and once after each reload until you install that release or a newer one. The reminder carries across characters; alpha and beta builds do not trigger it.

## Keep familiar controls close by

The draggable **QuestTogether minimap button** opens a menu with:

- Looking for Questing Partners
- Settings
- Compare Party Quests
- Open Quest Journal
- Patch Notes
- Move QuestTogether Logs to Separate Window, or back to Main Window
- Hide Minimap Icon

You can drag the button around the minimap or hide it. Hiding it prints a reminder that it can be restored through **Miscellaneous → Show minimap icon** in `/qt options`.

> **SCREENSHOT 10 — Minimap menu:** The scroll-logo minimap button with its context menu open.

## Make each character feel right

QuestTogether's settings are organized into **What To Announce**, **Where To Announce**, **Quest Plates**, **Player Plates**, **Player Locations**, **Miscellaneous**, and **Profiles**.

Each character starts with its own profile assignment. Switch profiles, create a new one, copy settings from another profile, reset the active profile, or delete a profile that is not active. Use different setups for different characters, or assign a shared profile where you want the same preferences.

The main settings page includes a quick status overview and shortcuts to common settings, HUD Edit Mode, rescanning the quest log, help, patch notes, and Discord support.

WoW's ignore list is respected across new quest logs, bubbles, player dots, and player icons. Ignoring someone also clears their active visuals and cancels pending comparisons and share requests involving them. Previously printed chat history remains in your chat window.

> **SCREENSHOT 11 — Settings and profiles:** The main QuestTogether settings page and Profiles controls, showing a few example character or playstyle profiles.

## See what's new in-game

A welcome and patch notes window introduces QuestTogether and highlights the latest changes. It opens on first use and after a **major or minor version upgrade**. Patch releases do not automatically reopen it.

Revisit the notes from the minimap menu, main settings page, or `/qt notes`, `/qt changelog`, and `/qt patchnotes`. The window includes shortcuts to settings and our Discord for feedback and support tickets.

> **SCREENSHOT 12 — Welcome and patch notes:** The latest notes window with the QuestTogether logo, release highlights, Settings button, and Discord button.

## Getting started

1. Install QuestTogether and have your questing partners install it too.
2. Click the minimap scroll icon or type `/qt` to open settings.
3. Choose the announcements and display options you want. Review **Player Locations** if you want to change the default sharing and viewing settings.
4. Enable the appropriate WoW nameplates for quest and player icons. Use HUD Edit Mode if you want to reposition your personal bubble.
5. Start questing. Open `/qt compare` whenever you want to check everyone's quest lists.

QuestTogether exchanges its updates through addon communication. Other players need QuestTogether to receive those updates, and comparison data depends on a responding peer. The **Party Only** progress filter controls displayed announcements; location sharing and viewing have their own independent settings.

The addon bundles its required library, so no separate library download is needed. TomTom is optional. The package includes client adapters for Retail, Forever, Era/Hardcore/Season of Discovery, Anniversary/Burning Crusade, Mists Classic, and Titan Reforged; individual features depend on the APIs available in your client. Nameplate enhancements are built around Blizzard nameplates, so replacement nameplate addons may affect their appearance or availability.

## Useful commands

| Command | Action |
| --- | --- |
| `/qt` or `/qt options` | Open settings |
| `/qt compare` | Open Party Quest Compare |
| `/qt lfg [on|off|toggle|status]` | Set or check Looking for Questing Partners; no argument toggles |
| `/qt notes`, `/qt changelog`, or `/qt patchnotes` | Open welcome and latest patch notes |
| `/qt enable` / `/qt disable` | Enable or disable addon runtime behavior |
| `/qt scan` | Rescan your quest log |
| `/qt get <option>` | Read an option value |
| `/qt set <option> <value>` | Change a boolean option using on/off or true/false |
| `/qt help` | Show normal command help |
| `/qt help debug` | Show diagnostics, tests, and preview commands |

For troubleshooting, QuestTogether includes a searchable, filterable debug window (`/qt debug` or `/qtd`), copyable diagnostics (`/qt diagnostics [questID]`), and an in-game test suite (`/qt test`). `/qt ping` requests metadata from other reachable QuestTogether clients. Local bubble previews and `/qt compare debug` let you preview UI with test data; comparison previews do not share quests.

## Feedback and support

**[Join the QuestTogether Discord](https://discord.gg/Uxyyvhfva9)** to suggest features, share feedback, or open a support ticket. You can also find a copyable invite through **Discord — Feedback & Support** in the welcome window and main settings page.

When reporting a problem, include your game client, QuestTogether version, what happened, and how to reproduce it. Screenshots and copied diagnostics are helpful. To copy debug output, open `/qt debug`, choose **Select All**, and press **Ctrl+C**.

## Play in your language

QuestTogether supports all nine WoW languages across eleven in-game text locales:
English, German, French, European and Latin American Spanish, Brazilian Portuguese,
Russian, Italian, Korean, and Simplified and Traditional Chinese. Menus,
settings, and patch notes follow your WoW client language. Events from updated QT
players can be displayed in your language too, using local quest titles when WoW
has them and the other player's actual progress. Some objectives use a translated
objective number instead of their original description. Older addon versions and
unavailable quest data retain safe fallbacks; public party chat uses the sender's
language. Discord has a separate changelog channel for each supported language.
