# QuestTogether

QuestTogether helps your group stay in sync while questing by sharing quest milestones in a clean, readable way.

It announces quest events, objective progress, world quest updates, and bonus objective updates to other QuestTogether users, then lets each player decide how they want to see those updates locally (chat bubbles, chat logs, or both).

## What QuestTogether Does

- Announces your quest activity to other QuestTogether users in your shared channel.
- Supports:
  - Quest accepted
  - Quest completed
  - Quest ready to turn in
  - Quest removed
  - Quest objective progress
  - World quest area enter/leave/progress/completed
  - Bonus objective area enter/leave/progress/completed
- Displays incoming updates with:
  - Chat bubbles over nearby players and a personal bubble anchor
  - Chat log output in your main chat or a dedicated QuestTogether chat tab
- Adds quest-objective enhancements on Blizzard nameplates:
  - Optional quest icon
  - Optional health bar tint for quest objectives
- Includes quick social actions in QuestTogether log entries:
  - Invite
  - Whisper
  - Add friend
  - Ignore/unignore
  - Compare Party Quests
- Compares your party's quests in one window, including ownership, completion, Share and Request Share actions. Incoming share requests ask for confirmation by default, with optional automatic approval.
- Adds quest-name menus for Status, Share, Open in Quest Journal and Compare Party Quests.
- Includes a draggable minimap menu and an in-game welcome and patch notes window.

## Why Use It

- Keeps party questing coordinated without voice chat.
- Makes nearby progress visible at a glance.
- Helps players quickly identify who is on what objective.
- Keeps your UI flexible with per-profile options and per-character profile defaults.

## Profiles and Settings

QuestTogether includes built-in profile management under:

`Options > AddOns > QuestTogether > Profiles`

You can:

- Switch profiles
- Create a new profile
- Copy another profile into your active profile
- Reset active profile to defaults
- Delete non-active profiles

Each character defaults to its own profile assignment, so your alts can have different setups automatically.

## Chat and Display Controls

In `Options > AddOns > QuestTogether`, you can configure:

- Exactly which announcement types you want to send/display
- Chat bubbles on/off
- Hide your own bubbles
- Bubble size and duration
- Chat log output on/off
- Chat log destination:
  - Main Chat Window
  - Separate QuestTogether chat window
- Progress visibility mode:
  - Party only
  - Party + nearby visible players
- Nameplate quest icon style and quest health color
- Separate emote toggles for your own and nearby players' quest completions and level-ups
- Minimap icon visibility and automatic approval of party share requests

## Slash Commands

- `/qt` or `/qt options` - Open QuestTogether options
- `/qt enable` - Enable addon runtime behavior
- `/qt disable` - Disable addon runtime behavior
- `/qt compare` - Open Party Quest Compare
- `/qt notes`, `/qt changelog`, or `/qt patchnotes` - Open the latest welcome and patch notes
- `/qt help` - Show normal commands
- `/qt help debug` - Show diagnostics, tests, previews and developer commands
- `/qt debug` - Open the debug log
- `/qt diagnostics [questID]` - Copy client, runtime, and recent-event diagnostics
- `/qt devlogall on|off|toggle` - Toggle developer all-announcements logging
- `/qt set <option> <value>` - Set boolean options
- `/qt get <option>` - Read option values
- `/qt scan` - Rescan your quest log now
- `/qt ping` - Request metadata pings from QuestTogether users
- `/qt bubbletest <text>` - Run a local bubble preview for your targeted player
- `/qt bubbletest "<player>" <text>` - With no target, preview a nearby visible player using their full name; for example, `/qt bubbletest "Anakin Othername" hello`
- `/qt test` - Run in-game addon tests

Bubble previews stay on your client. Player names can also be unquoted: `Name-Realm`, or `First Surname` on Forever. When you have a target, everything after `bubbletest` is preview text.

## Notes

- QuestTogether is designed to work without external library dependencies.
- The addon focuses on Blizzard UI compatibility and includes safeguards for common nameplate addon conflicts.
- If other players do not run QuestTogether, they will not receive addon message data.

## Tips

- If your chat logs feel noisy, disable specific announcement types first before turning off everything.
- If you prefer a cleaner main chat, use the separate QuestTogether chat destination.
- If you run multiple characters, create role-based profiles (solo, group, completionist, etc.) and assign per character.

## Support and Feedback

If you run into issues, include:

- Game version
- QuestTogether version
- Steps to reproduce
- Any relevant debug output (open `/qt debug`, choose **Select All**, then press Ctrl+C to copy)

That makes fixes much faster and more accurate.
