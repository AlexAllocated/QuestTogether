# Native gamepad navigation

QuestTogether uses Forever's native Gamepad UI navigation and the player's
existing controller mappings. Enable Gamepad UI in WoW, then leave **Enable native
gamepad navigation** checked in QT's Controls & Launchers settings. Existing controller
keybindings stay unchanged.

With the default controller layout, QT adds a **PQL macro with a built-in
quest-book icon** to **LT + RT + D-pad Up on normal action page 1**, only if that
slot is empty. An occupied slot is left alone. Move or remove the button with
Blizzard's action-bar editor; the macro is also available in `/macro`.

Removing or moving only the button does not make QT put it back while the macro
still exists. If you delete the macro itself, QT can recreate and rebind it when
the default slot is empty. Existing actions and edited macros are preserved.
Other action pages and stance/vehicle bars remain unchanged. This is an ordinary
`/qt pql` macro, not a replacement for Blizzard's targeting shortcuts.

Assign **Open QuestTogether menu** in WoW Key Bindings to access contextual actions
and **Pending Requests**. It has no default binding. The world map's native
overrides can mask controller combinations, including modified face/D-pad keys;
an ordinary assigned controller binding is not guaranteed to reach QT there.

You can also assign **Follow target's quest focus** under QuestTogether in WoW
Key Bindings. Target a party member and press your assigned key to follow their
quest navigation. **Stop following quest focus** cancels it. Both bindings start
unassigned. For a macro, use `/qt focus` for your current target or
`/qt focus Full Name` for a specific party member; `/qt unfollow` stops following.
These commands follow quest focus, not the player's movement.

Controller navigation supports Forever 1.60.1 when the required native APIs and
secure wrappers are available. Build numbers are reported for diagnostics, not
used to enable or disable support. Other clients and clients without those
interfaces keep their existing mouse and keyboard windows. Hardware detection
alone does not enable navigation.
Native context menus failed live testing on build 70888, and no safe supported
repair was found in that build's public menu interfaces. While Gamepad UI is
active, QT therefore uses compact owned menus for actions and choices, including
menus opened with the mouse. They use flat native-style rows, checkmarks and
submenu arrows, size themselves to their contents, and page through overflow.
Native navigation still owns Select, Back and focus return; there is no separate
controller engine or raw controller binding layer. If native navigation is
disabled or unavailable, these menus remain usable with the mouse. After a native
safety failure, menu opening stops until reload; QT does not fall back to the
failed native menu path. In WoW's mouse/keyboard interface style, the existing
mouse menus are unchanged.

Owned dropdowns use Blizzard's artwork: HUD options use the standard Style 1
field, and Settings use Style 2. Artwork follows the client's loaded UI family,
including its dropdown backgrounds, arrows, checkboxes, radio marks and selection
highlights. Dropdown choices open below their field; setting help and tooltips
for clipped selected labels remain available. Existing checkboxes, sliders, PQL
controls, dialogs and native Select/Back prompts retain their original styling.

## Using the windows

- In **Party Quest Log**, move vertically between quests and horizontally between
  their controls. Select expands a quest; the QT menu binding opens its actions.
  Player headers offer the same player actions as the mouse. Navigation scrolls
  through the complete list, even when only some rows are visible.
- **View chain** opens inline quest-chain rows in the same list. Up/Down selects
  rows and Left/Right selects their controls. Select toggles a chain group, opens
  a step's actions, or expands objectives on an ordinary quest title. Back closes
  the action menu first, then the selected chain section and restores its origin;
  otherwise it closes Party Quest Log. The partial list viewport does not use
  native right-stick scrolling. Browsing leaves quest focus and waypoints alone.
  See [QUEST_CHAINS.md](QUEST_CHAINS.md) for provider setup and data limits. These
  new chain interactions still require live controller acceptance.
- Browsing quests in Blizzard's **Objective Tracker** also counts as hovering for
  **Party Objective Tracker**. It does not change quest focus or focus following.
  POT keeps its display-mode and tooltip preferences and remains a passive HUD.
- On the **world map**, point the native crosshair at a QT marker, then open the QT
  menu for its player or cluster actions using a binding that reaches QT. Native
  Select retains Blizzard's map action and does not open QT menus.
  Native zooming, panning and
  waypoints keep their normal behavior. Protected player targeting remains a
  mouse action.
- Requests arriving from other players do not capture controller focus. Open
  them deliberately through **Pending Requests**. Confirmation starts on Cancel
  or Decline. Back closes/cancels using the window's normal behavior; it does not
  save notes, accept requests or change reminder preferences.
- Settings categories remain under Blizzard's navigation. QT dropdown choices
  use compact owned menus. Standard Select/Back prompts use your native mappings.
- In **Patch Notes**, use the right stick to scroll the text and the D-pad to
  select buttons or browse History. Back closes the window. Notes opened
  automatically after an update take controller focus too.
- Text entry, moving/resizing HUD elements, and window corner resizing retain
  their existing controls. No on-screen keyboard is supplied.

QT-managed windows and their open menus close automatically when combat begins.
On clients with addon restriction notifications, teardown runs synchronously
inside the combat **Activating** event, before native focus changes become
restricted. Popups detach before their parent windows. Other clients use the
normal combat-start event. Dialogs cancel through their existing dismissal
paths; a combat interruption does not apply a preset or complete first-run setup.
Ordinary dismissed dialogs do not reopen automatically after combat.

If a client already enforces restrictions before QT receives the event, native
cleanup remains queued until it is allowed. X, Escape and Back also remain
dismissal-only during ordinary combat when the native cleanup APIs are available;
quest actions and navigation remain suspended. `gamepad.dismissalRestricted`
reports the current cleanup restriction. Since the diagnostic report window
cannot open during combat, QT retains the latest combat close attempt in
`gamepad.lastCombatClose.*`. After reproducing a stuck close, leave combat and
run `/qt diagnostics` without reloading. Opening the report does not overwrite
the saved restrictions and outcome. Only one local scalar snapshot is retained;
it contains no player or quest data and is cleared by reload. PQL automatic
closure was confirmed in-game on Forever build 70959. The shared lifetime also
covers the debug log/report window with QT disabled, independently of native
controller availability; those additional paths have offline coverage.

The managed-window audit covers PQL and its previews, quest details, focus
confirmations, share/join prompts, player notes, recent companions, VIP/Discord
dialogs, patch notes, presets, HUD edit dialogs and QT-owned action menus.
Debug log and diagnostic-report modes share the same registered console window.
Blizzard's Settings host remains owned by Blizzard.

## Safety and validation

Controller support is included in the stable release. The remaining live checks
below are still pending. Private development probes are
not included in the release, and automatic A-button menus on map markers are
not enabled. Native map Select keeps its existing behavior.

The private owned-panel fixture passed basic selection, default Cancel, nested
Back and focus return, main-window UI/world focus switching, UI hide/restore,
single activation per held Select/Back, and deferred closure after combat on
70888. The original native-menu path failed on that build and was not retained;
this does not establish that native menus cannot be supported by a future build.
On build 70938, the tester confirmed restored production PQL navigation and the
revised POT Display dropdown and QT quick menu, including Select/Back. Remaining
visual checks include Settings' distinct dropdown style, alternate client-family
artwork, hover/pressed/disabled states, help and clipped-label tooltips, nested
menus and overflow paging. The basic visual confirmation does not establish all
of those cases.

The relevant native interfaces were source-compared for build 70938 and remain
unchanged from 70888. Basic PQL and owned-menu acceptance on 70938 is recorded
above; the earlier fixture lifecycle results remain evidence for 70888 only.

On 2026-11-19, the build-number allowlist was removed after comparing Blizzard's
[70938 to 70959 UI source](https://github.com/Gethe/wow-ui-source/compare/bebcb6bf309cf41b41bd74f8ca651e6a105b2676...3d8abb1da73acd38e412e24fb3f99454a6392346).
The 17 changed files do not change QT's native navigation wrappers, gamepad
action storage and binding helpers, or the group-map provider and secure
unit-position delegate. The bag window changes affect its own navigation only.
The previous build gate prevented new-character launcher installation and
controller navigation entirely. Compatibility checks cover arbitrary version and build strings, including missing
build metadata, while still rejecting missing or insecure native wrappers. Client
version, build and interface numbers are diagnostic information only. Macro placement, controller
input and party-map behavior on this build still require live confirmation.

On 2026-11-12, the tester confirmed that reloading after deleting the macro
recreated the quest-book launcher, bound it to LT + RT + D-pad Up, and opened
PQL. Basic production PQL controller navigation was also reported working well.
These reports do not individually establish every long-list navigation or
window-lifecycle case.

The tester also confirmed world-map crosshair hover and that QT's player tooltip
stays above an overlapping native quest tooltip. A separate private A-button
probe opened a player menu with D-pad navigation, Back and return to map movement;
that experiment is not part of the release. Its revised startup handoff and cluster
menu path still need live validation.

The related world-map party marker presentation keeps verified VIP stars and
developer icons when grouped, and returns Blizzard's party markers when QT's
map overlays are turned off. This was confirmed on build 70888. Its required
native interfaces were source-compared and found unchanged in 70938 and 70959,
which are also enabled; their party-marker behavior still needs live confirmation.
The minimap remains unchanged.

POT controller browsing, settings and other windows still require live acceptance. Remaining
checks include PQL virtual-list boundaries, preservation after removing only the
launcher button, the menu binding while the map owns focus, return from foreign
windows, controller reconnects, interface-mode changes, search/chat entry,
covering windows and combat transitions. Offline doubles do not establish taint
safety or physical controller behavior.

If an unexpected native failure occurs, QT stops controller integration for the
session and records a bounded diagnostic. Save `/qt diagnostics`, then reload to
clear native state before further testing. QT never reloads the game itself.

## Welcome and configuration

New installations open the welcome chooser instead of patch notes. Select one
of the four cards, then **Start questing**. Full Adventure is initially selected;
Back or Escape on first setup uses Full Adventure. On a manually reopened
chooser, Back cancels. Keyboard Up/Down selects a card and Enter applies.
Right/Left expands or collapses its settings; Page Up/Down scrolls the list.
First setup remembers the choice for future characters; on a reopened chooser,
Space toggles that checkbox. Controller Select chooses a card; navigate to
Start questing to apply it. Each card also has a separate Show settings button.
Expanding a card does not select or apply it. Use the mouse wheel or controller
right stick to read all its settings; the Apply button stays available below
the list. Existing installations are not reset.

Open **WoW Options > AddOns > QuestTogether > Presets** to revisit the chooser.
Each card describes a common use case. Expanded details show every option the
preset applies, grouped by feature with its exact enabled/disabled state or
selected value. These details use the preset values directly. Each choice
changes only the listed feature options, not layouts, bindings,
notes or the addon's enabled state. Individual edits produce **Custom**. The
future-character checkbox sets the account default; copied and existing
profiles keep their settings.

- **Full Adventure:** the usual QT defaults, with automatic leader-follow off.
- **Quiet Questing:** maps, plates, PQL and tracker remain. Automatic messages,
  bubbles, sounds, emotes, startup tips and update interruptions are off.
- **Quest Log Only:** PQL on demand with minimap and controller shortcuts.
  Map overlays/buttons, plate additions, identifiers, tracker/focus indicators,
  automatic output and incoming QT share-request prompts are off.
- **Little Sidekick:** no automatic QT windows, launchers or visual additions. Reports
  stay within the current party, diagnostic sharing and public discovery are
  off, and automatic leader-follow is on. **Thanks and celebration emotes stay
  on** and can be changed individually. Deliberate shortcuts and WoW Options
  still work. Blizzard's own UI and native quest-sharing dialogs are unchanged.

QT's main page contains presets, startup tips and update notices. **Controls &
Launchers** contains controller navigation, shortcut installation and minimap access. **Data Broker** has its own page for compatible toolbar
launchers and their click actions. **Party Tracker & Focus** contains leader-follow and
tracker indicators; **Groups & Sharing** contains incoming share requests and the
sharing audience. **Maps & Minimap** contains map overlays, buttons and waypoints.
**Appearance & Accessibility** contains theme, scale and motion settings.
**Emotes** contains automatic thanks and celebrations; sound cues stay in Audio.
New profiles enable every sound cue; saved opt-outs are preserved. **Where to
Announce → My chat bubble** supports always, solo, party (including raids), and
hidden. This controls only the local personal bubble, not outgoing progress.
Controller navigation and shortcut installation are independent. Disabling the
shortcut removes only an unchanged action whose placement QT recorded; custom
macros/bindings are retained. Turning it on can restore that same removed action
if its slot remains empty. Existing unbound macros are not automatically remapped.
If another toolbar has already registered the Data Broker launcher, use the
explicit **Reload UI** button to remove it for the next session.

Automatic leader-follow uses the actual small-party leader and fresh QT focus
information. When both characters have the selected quest, local focus follows
without confirmation. While it is usable, other focus and waypoint actions
cannot replace it. Native WoW selection can briefly change before QT restores
it through the normal API. If the leader disconnects, has no usable QT focus,
or chooses a quest you lack, manual local focus works until following resumes.
Solo, self-leadership and raids retain ordinary local behavior. Stop following
and `/qt unfollow` explain which setting to turn off; neither disables it.
Turning the setting off leaves the current quest selected.

### Welcome and leader-follow live acceptance

Offline fixtures cannot establish live rendering, native input ownership or
actual delivery between clients. Before release, check:

1. A fresh test account sees welcome once; an existing account keeps its settings.
   Try mouse, keyboard and controller, including Back and a combat transition.
2. Choose Little Sidekick before startup completes. Check for no QT launcher, automatic
   chat/window/map/plate/tracker output while another grouped client receives
   quest, focus, history, waypoint and location updates. Emotes should remain.
3. Follow a leader with QT and a shared quest. Change leadership and quest focus;
   accept another quest and attempt a manual focus/waypoint switch. No stop-follow
   warning should appear while automatic following can operate.
4. Disconnect the leader or choose a quest the follower lacks. Try a local focus,
   then restore a usable leader quest and confirm automatic resumption.
5. Recover settings through WoW Options. Change presets and individual options,
   disable leader-follow, and test launcher preservation and the toolbar reload
   notice. Reopen or copy a profile and confirm unrelated customization survives.
