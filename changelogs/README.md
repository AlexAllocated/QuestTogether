# QuestTogether changelogs

These files contain the same welcome text, section headings, and release items
as their corresponding Discord changelog channels and in-game patch notes.
They are generated from canonical release notes, not independently summarized.

| Locale | Changelog | Canonical history starts |
| --- | --- | --- |
| English (`enUS`, also `enGB`) | [English](../CHANGELOG.md) | 5.10.0 |
| German (`deDE`) | [Deutsch](deDE.md) | 5.14.0 |
| French (`frFR`) | [Français](frFR.md) | 5.14.0 |
| European Spanish (`esES`) | [Español](esES.md) | 5.14.0 |
| Latin American Spanish (`esMX`) | [Español latinoamericano](esMX.md) | 5.16.0 |
| Brazilian Portuguese (`ptBR`) | [Português brasileiro](ptBR.md) | 5.14.0 |
| Russian (`ruRU`) | [Русский](ruRU.md) | 5.14.0 |
| Italian (`itIT`) | [Italiano](itIT.md) | 5.16.0 |
| Korean (`koKR`) | [한국어](koKR.md) | 5.16.0 |
| Simplified Chinese (`zhCN`) | [简体中文](zhCN.md) | 5.16.0 |
| Traditional Chinese (`zhTW`) | [繁體中文](zhTW.md) | 5.16.0 |

Only releases with an existing published translation appear in each localized
history. Earlier handwritten English entries remain available in the
[original changelog](legacy-enUS.md). Older Discord messages are not reposted.

For maintainers: edit `release_notes.json` and its translations, then run
`python3 scripts/check_release_notes.py --write`. Do not hand-edit generated
Markdown or the published-note archive. See [the release workflow](../RELEASING.md).
