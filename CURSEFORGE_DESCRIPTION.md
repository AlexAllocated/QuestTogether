# QuestTogether

> *I wish I didn't have to say this, but QuestTogether is NOT “vibecoded.” I’m a career developer with over 20 years of experience. I’ve been building this addon for eight years alongside a steadily growing community of users.*

QuestTogether helps you quest with other players: compare quest logs, share eligible quests, follow party progress, and find people looking for company. Progress bubbles, an interactive chat log, map information, and party navigation work alongside WoW’s questing UI.

## Getting started

Install QuestTogether and have your questing partners install it too. Shared QT information and interactive comparisons require the other player to use QT. Required dependencies are included; TomTom is optional.

To set your preferences, type **`/qt`**. Review **What to Announce** and **Where to Announce** to choose which updates appear and how they are displayed. **Player Locations** controls public location sharing and which players you see on maps.

**Minimap controls**

- **Left-click the QT icon:** open **Party Quest Log**.
- **Right-click the QT icon:** open the main QT menu.

Settings names in this guide use the English labels; the addon follows your game language. Defaults below apply to new profiles. Existing characters keep their saved preferences.

## Party Quest Log

### Open a comparison

Left-click the minimap icon or type **`/qt pql`**. Read quests down the rows and players across the class-colored columns. The combined list includes quests you do not have.

Click **Refresh** to request current party information. The text beneath each player’s name shows the age or availability of their information; your own column follows your local quest log.

To compare with one reachable QT player outside your party, open their menu from a map dot or linked name in QT chat and choose **Compare Quests**.

[![Party Quest Log overview](https://media.forgecdn.net/attachments/2055/231/party-quest-log-overview-png.png)](https://media.forgecdn.net/attachments/2055/231/party-quest-log-overview-png.png)

### Read quest states

| State | Meaning |
| --- | --- |
| **Have** | The quest is active. |
| **Ready** | Its objectives are complete and it is ready to turn in. |
| **Completed** | The character’s completion history confirms completion. |
| **Missing** | The quest is absent and known to be unfinished or repeatable. |
| **Not in log** | The active log confirms absence, but completion history is unavailable. |
| **Loading** | QT is waiting for requested quest information. |
| **Unknown** | QT lacks enough current information to confirm the state. |

An unanswered request is not treated as a confirmed missing quest. Remote completion history is available when the other player’s QT client supports it.

### Compare objectives and filter quests

- Click the **+** beside a quest to expand its objectives. Compare each player’s counts and progress bars; several quests can remain expanded.
- Use **Search** for a quest name or ID. Received quest names in another language are searchable too.
- Open **Filters** and combine **Quest ownership**, **Party progress**, and **Available action**. For example, select **Quests I don't have** and **Can request share** to find quests to request.
- Use **Reset** or **Filters → Reset filters** to clear the filters and search. Filter selections are saved in your profile.

The book button beside a quest you own opens it in WoW’s quest log. Round focus buttons in player cells indicate quest focus and provide the focus actions described below.

[![Expanded quest objectives and sharing actions](https://media.forgecdn.net/attachments/2055/421/party-quest-log-dark-objectives-png.png)](https://media.forgecdn.net/attachments/2055/421/party-quest-log-dark-objectives-png.png)

### Refresh and arrange columns

- Open a player’s heading menu and choose **Refresh this player** to update that player alone.
- Enable **Filters → Auto-refresh while open** for periodic requests while the window is open. It starts off.
- Choose **Collapse player column** from a heading menu, then **Expand player column** to restore it. **Restore all player columns** restores every column.
- Move or resize the window as needed. Scroll vertically through quests and horizontally when the player columns exceed the available width.

### Use the keyboard

Opening Party Quest Log or clicking a quest gives the list keyboard focus. Press **Tab** to move between the list and Search.

- Use **Up/Down** to move between quests; **Home/End** and **Page Up/Page Down** move through longer lists.
- Press **Right** to expand objectives, **Left** to collapse them, or **Enter** to toggle them.
- Press **Space** or the **Menu** key to open the selected quest’s actions.
- Press **Escape** to close the window, or click outside it to return to normal controls.

[![Collapsed player columns and keyboard selection](https://media.forgecdn.net/attachments/2055/227/party-quest-log-compact-keyboard-png.png)](https://media.forgecdn.net/attachments/2055/227/party-quest-log-compact-keyboard-png.png)

## Sharing quests

### Share a quest you have

1. Find an eligible quest in Party Quest Log.
2. Click **Share**, or open its linked name in the QT log and choose **Share**.
3. Recipients respond to WoW’s normal quest-acceptance prompt.

### Request a quest you need

1. Find a shareable quest another party member has.
2. Click **Request Share**.
3. The owner receives a prompt identifying you and the quest, then chooses **Share** or **Decline**.

Requests require confirmation by default. To approve eligible requests automatically, enable **Groups & Sharing → Always allow party share requests**, or select that option in a share-request prompt. This does not automatically accept quests for recipients.

If sharing cannot proceed, QT provides an explanation. Hover a player’s heading in Party Quest Log to see their latest sharing result when WoW has reported one. Normal quest prerequisites and sharing rules still apply; sending a request or attempting a share does not guarantee acceptance.

[![Quest share-request confirmation](https://media.forgecdn.net/attachments/2055/239/quest-share-request-png.png)](https://media.forgecdn.net/attachments/2055/239/quest-share-request-png.png)

## Looking for Questing Partners

Enable **Looking for Questing Partners** in the minimap menu or **Groups & Sharing**. You can also **Shift-click the minimap icon** or type **`/qt lfg`** to toggle it. Your minimap icon glows while this status is enabled.

[![The QT minimap icon glowing with Looking for Questing Partners enabled](https://media.forgecdn.net/attachments/2055/499/minimap-looking-for-partners-png.png)](https://media.forgecdn.net/attachments/2055/499/minimap-looking-for-partners-png.png)

Other QT players see a gold glow on your public map dot and corresponding highlighted QT logos in chat, player nameplates, and party tooltips. When public location sharing is enabled, your tracked quest can also appear in your partner tooltip.

The status starts off and is saved per profile. Enabling it does not enable location sharing. **Groups & Sharing → Stop looking for partners when joining a group** can turn it off when you join or form a party or raid; this option starts off. You can turn partner status back on to recruit more players.

With location sharing enabled, turning partner status on also announces your search throughout your zone. **What to Announce → Announce Looking for Questing Partners** controls sending and displaying that announcement separately from the status and glowing icons. Other players’ announcement preferences still apply.

### Invite or request to join

1. Click a QT player’s name in the log or right-click their world-map dot to open the player menu.
2. Choose **Whisper** to talk, **Invite** to invite an available player, or **Request to Join** when the player is already grouped.
3. For join requests, an eligible recipient chooses **Send Invitation** or **Decline**. You still accept WoW’s normal invitation.

The same menu includes **Add Friend**, **Ignore** or **Unignore**, **Compare Quests**, and private-note actions. Party members can also offer quest-focus actions.

If the contacted player cannot invite, QT can forward the request to a QT-enabled party leader. If the leader does not use QT, the optional ordinary party-chat fallback can announce the request for a manual invitation.

Under **Groups & Sharing**, **Automatically invite friends who request to join** and **Automatically invite others while looking for partners** both start off. Automatic invitations require permission and room in the party. QT does not leave your current group or accept invitations for you.

[![QT player menu and party invitation actions](https://media.forgecdn.net/attachments/2055/233/player-map-actions-png.png)](https://media.forgecdn.net/attachments/2055/233/player-map-actions-png.png)

## Player locations

### Read map dots and tooltips

Class-colored dots represent other QT players on the world map and minimap. A gold glow marks someone looking for questing partners.

- Hover a dot to inspect available class, race, level, faction, partner status, party information, and QT version. Retail can also show War Mode. Keep the tooltip open while player details and the full small-party roster refresh. Larger groups show their size and leader.
- Hover a grouped player to highlight their party's visible dots. Party badges identify grouped players; a crown identifies the leader.
- Hover a world-map player, cluster, or shared waypoint to dim the surrounding map and keep the focused markers bright.
- On the **world map**, left-click a player dot to highlight it in green and open the most detailed map containing that player. If you are already at that map level, left-click opens their menu. The highlight lasts one minute, until the map closes, or until you select another player. Right-click opens the menu without changing the highlight. On the **minimap**, left-click a dot to target that player or right-click it to open their menu.

These details also appear when hovering linked player names in QT chat. Your party members appear using **Blizzard’s party markers**.

Use the **QT icon in the top-right corner of the map** to show or hide QT markers. A red X means they are hidden. Hover the icon to read the map legend; this does not dim the map.

[![World-map player dots and party tooltip](https://media.forgecdn.net/attachments/2055/234/player-map-party-roster-png.png)](https://media.forgecdn.net/attachments/2055/234/player-map-party-roster-png.png)

### Set sharing and display preferences

Open **Player Locations**:

- **Share my location on the map and minimap** controls whether other QT players receive your public location. It starts enabled; turning it off withdraws your public dot and coordinates.
- **Players shown on maps** offers **All QuestTogether players**, **Players looking for questing partners**, or **None**. It starts on **All QuestTogether players** and affects what you see, not who can see you. **None** hides QT’s player dots; Blizzard’s party markers remain.

**Developer → Share diagnostic data with the developer** is a separate preference and starts enabled. It permits QT diagnostics and in-game character/location data independently of public location sharing. This information is shared **only with the developer**. Turn it off separately if you do not want to share that information. Private player notes are never included.

WoW’s ignore list is respected for new QT logs, bubbles, player dots, icons, and player interactions. Previously printed chat history remains in the chat window.

[![Player location sharing and map filters](https://media.forgecdn.net/attachments/2055/219/location-settings-png.png)](https://media.forgecdn.net/attachments/2055/219/location-settings-png.png)

Locations are periodic reports. Distant dots update less frequently, and older information shows its age. A recent quest announcement does not guarantee equally recent coordinates. A dot also does not guarantee that the player is in your phase or layer.

### Experimental layer detection

**Experimental → Detect different layers** estimates whether nearby players are on a different layer using available observations. It requires location sharing and compatible QT clients. NPC-based inference is available in Forever’s open world.

A **likely different layer** indication is an estimate, not a confirmed phase ID. A player being out of sight alone does not prove a layer difference.

## Following a party member’s quest focus

Quest focus is the quest currently selected for navigation. This feature works in parties of up to five, including dungeon groups, and does not extend to raids.

Leave **Groups & Sharing → Share my focused quest** enabled if you want party members to see and follow your selection. It starts enabled and works independently of public location sharing.

To follow a party member:

1. In Party Quest Log, hover a player’s heading or open its menu to inspect their focused quest.
2. Choose **Follow quest focus** from that player’s menu. You can also use the active focus button for their selected quest in the comparison.
3. Use **Stop following** when you want to choose your own navigation again.

QT remembers whom you are following across reloads and resumes after fresh party information arrives. If that player selects a quest you do not have, following stops and your current navigation stays in place. Choosing a different quest through QT while following asks for confirmation. Your own column’s focus buttons let you select a quest directly.

[![Party Quest Log while following a teammate’s quest focus](https://media.forgecdn.net/attachments/2055/215/follow-party-quest-focus-png.png)](https://media.forgecdn.net/attachments/2055/215/follow-party-quest-focus-png.png)

## Shared party waypoints

A shared waypoint is a destination, separate from a player’s current location. QT shares each party member’s normal Blizzard map pin in parties of up to five, including dungeon groups. It does not share waypoints with raids.

### Share your destination

1. Enable **Groups & Sharing → Share my waypoint**. It starts enabled and works independently of public location sharing.
2. Open the world map and place a normal Blizzard map pin. In Forever’s native map, **Ctrl-click** a destination, or activate the map’s pin-placement button and click the destination. Use the native map-pin control on other supported clients.
3. QT shares that pin with your party automatically. Placing it elsewhere updates the shared destination; clearing it removes the shared pin. In Forever’s native map, Ctrl-click your existing pin to clear it.

### Navigate to a party waypoint

1. Leave **Groups & Sharing → Show party waypoints** enabled to see received destinations. It starts enabled.
2. Look for class-colored waypoint pins on the world map. Hover a pin for its owner, zone, and coordinates. Overlapping pins list their owners.
3. Click a pin and choose **Navigate here** under the desired owner’s name. QT uses TomTom when available, with supported Blizzard navigation as a fallback.

[![Shared party waypoints with owner information](https://media.forgecdn.net/attachments/2055/240/shared-party-waypoints-png.png)](https://media.forgecdn.net/attachments/2055/240/shared-party-waypoints-png.png)

Nearby destinations also appear on the minimap, with the same hover information and navigation menu.

[![Shared party waypoint on the minimap](https://media.forgecdn.net/attachments/2055/221/minimap-party-waypoints-png.png)](https://media.forgecdn.net/attachments/2055/221/minimap-party-waypoints-png.png)

Receiving a pin never redirects you automatically. Choosing **Navigate here** ends quest-focus following. Shared pins disappear when their owner leaves the party. Map-pin availability and navigation support depend on the client and map.

## Private player notes

1. Open a player menu from QT chat, a map dot, or their Party Quest Log heading.
2. Choose **Add private note** or **Edit private note**.
3. Enter your reminder and click **Save**. Your note appears in that player’s QT tooltip.
4. Reopen the editor to change it or use **Delete note** to remove it.

Notes are saved with your QT data and shared across your characters, independently of profiles. **They stay on your computer: they are never transmitted to other players or included in diagnostics.**

[![Private player-note editor](https://media.forgecdn.net/attachments/2055/235/private-player-note-png.png)](https://media.forgecdn.net/attachments/2055/235/private-player-note-png.png)

## Announcements and chat

### Choose which updates appear

Open **What to Announce**.

- Choose **Party Only** or **Party & Nearby Players**. The default is **Party & Nearby Players**.
- Set **Nearby Range**, from a smaller surrounding area up to **Entire Zone**. The default is **25% of zone**. Party updates can follow your group across zone boundaries.
- Enable the event types you want: quest acceptance, objective progress, readiness to turn in, completion, and removal. Supported clients also offer world-quest and bonus-objective area entry, area exit, progress, and completion settings.

QT also reports level-ups. Announcement scope, QT conversation scope, and map visibility are independent settings.

### Configure the log

1. Open **Where to Announce** and enable **Show Chat Logs**.
2. Choose **Main Chat Window**, the default, or **Separate Chat Window**. You can also switch between them from the minimap menu.
3. Use WoW’s chat-window controls to dock the separate QT window as a tab or leave it floating.
4. If desired, enable **Also Print To Main Chat If Docked As A Tab**. This does not mirror a floating window.

[![QuestTogether chat announcements](https://media.forgecdn.net/attachments/2055/217/live-quest-announcements-png.png)](https://media.forgecdn.net/attachments/2055/217/live-quest-announcements-png.png)

### Talk to QT players

Type **`/qt <message>`** to send a QuestTogether conversation message. Recognized slash commands still perform their normal actions.

Under **Where to Announce**, choose **Global** or **Zone Only** chat scope. Global is the default; Zone Only uses recent shared location information. Disable **Show QuestTogether Chat** to hide conversations without hiding quest announcements.

### Open a player’s chat menu

Click a linked player name in the QT log to open their player menu. From there, you can whisper, invite or request to join, compare quests, and manage friends, ignores, and private notes. The menu offers the actions available for that player.

[![Player menu opened from a linked name in the QT chat log](https://media.forgecdn.net/attachments/2055/211/chat-player-actions-png.png)](https://media.forgecdn.net/attachments/2055/211/chat-player-actions-png.png)

### Include party members without QT

**Where to Announce → Also send announcements to party chat if any party members are not running QuestTogether** sends your enabled event announcements to ordinary party chat. It starts enabled, and everyone in the party can see those messages. It does not post to raids.

A reminder lets you keep this fallback enabled or turn it off. **Don't remind me again** saves your reminder preference. The fallback can also announce join requests when your party leader is not known to use QT and you cannot invite.

## Progress bubbles

- Enable **Where to Announce → Show Chat Bubbles**. Nearby players’ updates appear above their available nameplates; your own updates use a personal on-screen anchor.
- Enable **Hide My Own Chat Bubbles** if you only want other players’ bubbles. Your progress continues to be shared.

To adjust your personal bubble:

1. Choose **Open HUD Edit Mode**, then select and move the QT bubble anchor.
2. In **QuestTogether Bubble**, adjust **Font Size** and **Display Duration**, then click **Save Changes**. **Revert Changes** restores your unsaved edits; **Reset To Default** restores the default configuration for the edit session.

[![Quest progress bubble above a nearby player](https://media.forgecdn.net/attachments/2055/293/quest-progress-bubbles-png.png)](https://media.forgecdn.net/attachments/2055/293/quest-progress-bubbles-png.png)

Bubbles start enabled, including your own. QT’s chat logs, bubbles, and celebration emotes can be disabled independently while you continue using maps and comparisons.

## Quest links and details

Hover a quest link in QT chat to see your status, shareability, quest ID, and available objectives from your local quest log.

Click the quest link to open its menu.

- Choose **Quest Details** for the information WoW makes available, including quests outside your log when supported.
- Choose **Open in Quest Log** for a quest you own, **Share** for an eligible quest, or **Party Quest Log** to open a comparison.

[![Quest menu opened from a quest link in the QT chat log](https://media.forgecdn.net/attachments/2055/213/chat-quest-actions-png.png)](https://media.forgecdn.net/attachments/2055/213/chat-quest-actions-png.png)

Quest Details shows the text available from your game client. Some quests or clients provide limited information.

[![Quest Details window](https://media.forgecdn.net/attachments/2055/237/quest-details-png.png)](https://media.forgecdn.net/attachments/2055/237/quest-details-png.png)

Coordinate links in QT updates can also create a TomTom waypoint, with supported Blizzard navigation as a fallback.

## Nameplates

### Quest Plates

1. Enable the appropriate nameplates in WoW, then open QT’s **Quest Plates** settings.
2. Enable **Quest Objective Icon** to mark relevant quest targets.
3. Choose **Left**, **Right**, **Top**, or **Prefix** icon placement.
4. Enable **Quest Objective Health Color** if you also want tinted objective health bars. Choose **Quest Health Color** or use **Reset** to restore the default.
5. Check the preview, which uses the current WoW nameplate style.

[![Quest-objective nameplate icons and health-bar color](https://media.forgecdn.net/attachments/2055/238/quest-plates-settings-png.png)](https://media.forgecdn.net/attachments/2055/238/quest-plates-settings-png.png)

### Player Plates

1. Enable friendly nameplates in WoW.
2. Open **Player Plates** and enable **QuestTogether Player Icon**.
3. Choose **Left**, **Right**, **Top**, or **Prefix** placement and check its preview.

Recognized friendly QT players receive the QT logo, including players who do not share their location. The logo indicates Looking for Questing Partners status when applicable. Ignored players’ QT icons are hidden.

[![QT player-nameplate logo with Looking for Questing Partners glow](https://media.forgecdn.net/attachments/2055/294/player-nameplate-logos-png.png)](https://media.forgecdn.net/attachments/2055/294/player-nameplate-logos-png.png)

Nameplate features depend on available game information and can be limited in instances or restricted situations. Nameplate replacements may affect their appearance or availability.

## Appearance and accessibility

### Choose a theme

Under **General → Theme**, choose **Dark** or **Light** parchment. Dark is the default.

[![Light theme](https://media.forgecdn.net/attachments/2055/230/party-quest-log-light-objectives-png.png)](https://media.forgecdn.net/attachments/2055/230/party-quest-log-light-objectives-png.png)

### Adjust scale and motion

- Under **Accessibility → Window scale**, resize text and controls together. The setting ranges from **80% to 150%** and starts at **100%**; QT caps the effective scale when needed to fit the display.
- Enable **Reduce motion** for immediate scrolling and objective expansion instead of animated transitions. It starts off.
- Use **Reset window layout** or **`/qt resetlayout`** to restore saved window placement.

QT saves window layouts and fits them after display-size or UI-scale changes. **Escape** closes QT windows unless a focused control handles it first, such as returning from Search to the Party Quest Log list.

[![QT accessibility settings](https://media.forgecdn.net/attachments/2055/209/accessibility-settings-png.png)](https://media.forgecdn.net/attachments/2055/209/accessibility-settings-png.png)

## Profiles

Each character starts with its own profile assignment. Open **Profiles** to manage settings:

- **Switch:** select a saved profile in **Current Profile**. Characters using the same profile share subsequent changes to its settings.
- **Copy:** choose a source under **Copy Into Current Profile**, then click **Copy**. This replaces the active profile’s settings without linking it to the source profile’s future changes.
- **Create:** enter a name under **Create And Switch To New Profile**, then click **Create**. QT copies your current settings and switches to the new profile.
- **Reset:** click **Reset Active Profile** to restore that profile’s defaults.
- **Delete:** select an inactive profile under **Delete Profile**, then click **Delete**. The active profile cannot be deleted.

Private player notes are separate from profile settings and remain shared across your characters.

[![Profile selection, copying, creation, reset, and deletion](https://media.forgecdn.net/attachments/2055/236/profiles-settings-png.png)](https://media.forgecdn.net/attachments/2055/236/profiles-settings-png.png)

## Minimap menu and keybindings

### Minimap icon

- **Left-click:** open Party Quest Log.
- **Right-click:** open the QT menu.
- **Shift-click:** toggle Looking for Questing Partners.
- **Drag:** move the icon around the minimap.

The menu opens **Party Quest Log**, WoW’s **Open Quest Log**, **Settings**, and **Patch Notes**. It also toggles partner status, switches the QT log between main and separate windows, and offers **Hide Minimap Icon**. Restore a hidden icon through **General → Show minimap icon**.

Hover the icon for your QT version, partner status, chat scope, nearby range, and location-sharing status.

[![QuestTogether minimap menu](https://media.forgecdn.net/attachments/2055/266/minimap-quick-menu-png.png)](https://media.forgecdn.net/attachments/2055/266/minimap-quick-menu-png.png)

### Assign keys

Open WoW’s **Key Bindings → QuestTogether** and assign any of these actions:

- **Toggle Party Quest Log**
- **Open QuestTogether menu**
- **Toggle Looking for Questing Partners**
- **Stop following quest focus**
- **Open QuestTogether chat**
- **Open QuestTogether settings**

These actions have no keys assigned by default. The menu binding works when the minimap icon is hidden.

## Interactive tips

Tips explain QT features and provide clickable actions for opening the relevant window, settings page, or controls.

Read the tip in the QT log on login or reload, or type **`/qt tip`** or **`/qt hint`** to show one whenever you want. Tips come from a shuffled pool.

Click a tip’s bracketed action, such as **[Party Quest Log]**, **[Player Locations]**, or **[Key Bindings]**, to open that feature directly. Available actions match the tip and your client’s capabilities.

Disable **General → Show tips on login** to stop automatic tips. The manual tip commands remain available.

## Celebration emotes

Under **Where to Announce → Celebration Emotes**, four independent options control your character’s emotes:

- **Emote On Quest Completion**
- **Emote On Nearby Player Quest Completion**
- **Emote On Level Up**
- **Emote On Nearby Player Level Up**

They start enabled. Disable the nearby reactions to keep only your own celebrations, or turn all four off. Nearby reactions respect your player-scope preference.

## Commands

- `/qt` or `/qt options` — Open settings.
- `/qt pql` — Open Party Quest Log (`/qt compare` also works).
- `/qt lfg` — Toggle Looking for Questing Partners. Add `on`, `off`, `toggle`, or `status` to set or check it explicitly.
- `/qt <message>` — Talk in QuestTogether chat; recognized commands still run normally.
- `/qt tip` or `/qt hint` — Show another tip.
- `/qt notes`, `/qt changelog`, or `/qt patchnotes` — Open patch notes and release history.
- `/qt resetlayout` — Reset saved window layouts.
- `/qt enable` or `/qt disable` — Enable or pause QT’s runtime features.
- `/qt scan` — Rescan your current quest log.
- `/qt get <option>` — Read a setting value.
- `/qt set <option> <value>` — Change an on/off setting using values such as `on` or `off`.
- `/qt discord` — Open the Discord invite.
- `/qt help` — Show normal command help.

**`/qt ad <channel>`** posts a ready-made English message about QT from a shuffled pool. Use a joined channel’s number or name, **`/qt ad say`**, or **`/qt ad yell`**. It sends only when you run the command; it does not advertise automatically.

## Updates and language

The welcome and patch-notes window opens on first use and after major or minor upgrades. Patch releases do not automatically reopen it. Open **Patch Notes** or type **`/qt notes`** at any time.

Use **History**, **Older**, **Newer**, **Oldest**, or **Latest** to browse releases. The window also provides Settings and Discord shortcuts. QT reminds you when another user reports a newer stable version; alpha and beta versions do not trigger that reminder.

Menus, settings, tips, and patch notes follow your WoW language. Localizations include English, German, French, Spanish, Brazilian Portuguese, Russian, Italian, Korean, and Chinese, including regional Spanish and Chinese variants. Quest titles use your client’s text when available. Objective announcements preserve the sender’s original wording and progress.

## Compatibility and troubleshooting

**Retail and WoW Forever receive regular in-game testing.** The package also targets Era/Hardcore/Season of Discovery, Anniversary/Burning Crusade, Mists Classic, and Titan Reforged. Those additional variants do not receive the same regular testing. Some features depend on what the game client supports.

QT works alongside your existing quest tracker. Both players need compatible QT clients for shared data and comparisons; optional ordinary party-chat announcements can reach party members without QT.

If a player’s dot or quest information is missing:

- Check **Player Locations → Players shown on maps** and whether the other player shares their location.
- Confirm the other player is online with QT enabled.
- Use **Refresh** or **Refresh this player** for a comparison. Location and quest data update independently.
- For missing nameplate features, check WoW’s friendly/enemy nameplate settings and any nameplate replacement addon.

For help or suggestions, [join the QuestTogether Discord](https://discord.gg/Uxyyvhfva9). Include your game client, QT version, what happened, and a screenshot when useful. The same invite is available through settings, patch notes, or **`/qt discord`**.
