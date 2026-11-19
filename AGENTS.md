# QuestTogether contributor instructions

## Release-note authoring

- Author English and every supported language with the local subscription
  workflow in `scripts/author_release_notes.py`, or directly in the active Codex
  subscription session. The automated workflow uses `codex exec` and defaults to
  `gpt-6.1-sol`. It must verify saved ChatGPT login authentication and fail instead
  of falling back to API-key authentication. Do not call a paid model API, use
  API credentials, or copy login credentials to a remote runner for release-note
  preparation.
- Read the release's actual code and commit evidence. Establish the approved
  player-facing facts, prerequisites, defaults and limits first. Write each
  language independently from those facts and the relevant localized UI labels;
  do not translate finished English prose line by line. Review each language for
  natural wording and factual parity. Section topics must align; sentence order
  and bullet counts may differ.
- Follow `RELEASING.md`: the local authoring command exports context, writes
  `facts.json`, authors all eleven locales independently and reviews them. Manual
  authoring can export context with `prepare_release_notes.py context`. Use
  `finalize` to validate the complete reviewed draft before replacing canonical
  notes. Render Lua and Markdown with `check_release_notes.py --write`; preserve
  the existing release checks.
- Preserve authored history, approved English corrections, localized revision
  records, dates and illustrations. Historical changes use that release's exact
  tags and approved scope. Never import later features or reset corrected notes
  to older tag wording.
- Local automated authoring sends eligible code evidence, facts and locale
  terminology to Codex and uses the saved ChatGPT subscription. Deterministic
  context export, finalization and validation are offline. Start an authorized
  deployment with `scripts/deploy.py`; it runs validation, packaging and
  publication locally in sequence through `scripts/release.py` in a detached
  user service and an isolated checkout, so work can continue in the source
  checkout. Use the deployment's local status/logs and explicit resume command;
  do not add GitHub Actions workflows or wait for remote validation. The local
  `scripts/validate_release.py` checks the exact release tag before publication.
  The local publisher uploads separate Forever and Retail/Classic files to
  CurseForge; the old single-file packaging webhook stays disabled. Only Forever
  declares the required QuestieDB download relation. Do not poll CurseForge
  review or validate its remote content. Publishing consumes
  reviewed canonical notes; authoring notes alone does not authorize a release.

Use the active session for UI catalog wording as well. The optional UI translation
API utility is separate paid tooling and is not part of the release-note workflow.
