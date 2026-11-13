# Native gamepad navigation (beta)

QuestTogether uses Forever's native Gamepad UI navigation and the player's
existing controller mappings. Enable Gamepad UI in WoW, then leave **Enable native
gamepad navigation** checked in QT's General settings. Existing controller
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

This beta supports the audited native interfaces in Forever 1.60.1 builds
70888 and 70938. Other builds and clients without those interfaces keep their
existing mouse and keyboard windows. Hardware detection alone does not enable
navigation.
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
- Browsing quests in Blizzard's **Objective Tracker** also counts as hovering for
  **Party Objective Tracker**. It does not change quest focus or focus following.
  POT keeps its display-mode and tooltip preferences and remains a passive HUD.
- On the **world map**, point the native crosshair at a QT marker, then open the QT
  menu for its player or cluster actions using a binding that reaches QT. Native
  Select currently retains Blizzard's map action; an automatic Select handoff is
  undergoing a private feasibility test and is not enabled in production.
  Native zooming, panning and
  waypoints keep their normal behavior. Protected player targeting remains a
  mouse action.
- Requests arriving from other players do not capture controller focus. Open
  them deliberately through **Pending Requests**. Confirmation starts on Cancel
  or Decline. Back closes/cancels using the window's normal behavior; it does not
  save notes, accept requests or change reminder preferences.
- Settings categories remain under Blizzard's navigation. QT dropdown choices
  use compact owned menus. Standard Select/Back prompts use your native mappings.
- Text entry, moving/resizing HUD elements, and window corner resizing retain
  their existing controls. No on-screen keyboard is supplied.

## Safety and validation

This is a beta release for feedback on Forever's Gamepad UI integration. The
remaining live checks below are still pending. Private development probes are
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

On 2026-11-12, the tester confirmed that reloading after deleting the macro
recreated the quest-book launcher, bound it to LT + RT + D-pad Up, and opened
PQL. Basic production PQL controller navigation was also reported working well.
These reports do not individually establish every long-list navigation or
window-lifecycle case.

The tester also confirmed world-map crosshair hover and that QT's player tooltip
stays above an overlapping native quest tooltip. A separate private A-button
probe opened a player menu with D-pad navigation, Back and return to map movement;
that experiment is not part of the beta. Its revised startup handoff and cluster
menu path still need live validation.

The related world-map party marker presentation keeps verified VIP stars and
developer icons when grouped, and returns Blizzard's party markers when QT's
map overlays are turned off. This was confirmed on build 70888. Its required
native interfaces were source-compared and found unchanged in 70938, which is
also enabled; the 70938 party-marker behavior still needs live confirmation.
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
