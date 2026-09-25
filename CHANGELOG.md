# QuestTogether changelog

## Unreleased

Respect Forever's “My Last Name” setting when displaying your character's name. Keep other players' surnames visible, matching the native setting's scope. Use full names consistently for communications, group membership, nameplate matching, and social actions while preserving existing profile and personal bubble position keys.

Fix duplicate local quest announcements caused by receiving your own channel message under a different full-name format. Regression coverage exercises the local announcement followed by its channel and party echoes, including another character with the same first name.

## 5.7.6 — 2026-09-24

Use the same private libchev 1.1.2 debug console across all three addons, including category/search filters, copy controls, test results, diagnostic reports, timestamps when available, and a single final test summary. Fix stretched native frame artwork with explicit texture bounds.

QuestTogether supplies its own quest diagnostics and isolated tests while the shared library owns the console and generic debug behavior. Run `/qt test`, `/qt debug`, or `/qt diagnostics`.

Validation: 324 tests pass in both orders on Lua 5.1/5.2. The user confirmed the corrected frame appearance in-game. Other live restriction and gameplay validation remains separate.
