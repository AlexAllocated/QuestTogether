# CurseForge description and gallery workflow

Refresh QuestTogether's project description and screenshots from the current addon, using real in-game rendering and repeatable local scenes. Keep the editable copy in `CURSEFORGE_DESCRIPTION.md` and capture evidence under `.local/curseforge-refresh/`. Uploading an image, saving a description, and verifying the public page are separate completion steps.

**Current published baseline:** use `.local/curseforge-refresh/manual-2026-10-14/manifest.json` and `.local/curseforge-refresh/latest-run.json`. The latest LFQP minimap revision has 26 gallery images, 23 inline images, and eight featured images. The preceding theme-placement revision had 25 gallery images and 22 inline images. Its preceding verified state had 24 gallery images and 21 inline images. The top-level `.local/curseforge-refresh/manifest.json` describes the earlier publication and is preserved as historical evidence; do not use its URLs or gallery counts as the current baseline.

## Prepare and preserve

- [ ] Record the QT version and commit, client build, locale, character, resolution, UI scale, theme, and enabled addons in a dated run manifest.
- [ ] Copy the existing author-page description to `backups/description-before.md` and record gallery order, captions, image IDs, and public URLs in `backups/gallery-before.json`. Preserve original image files when available before removing or replacing media.
- [ ] Record any settings that capture work will change, including QT enablement, theme, window layouts, camera position, and temporary addon enablement. Do not overwrite a previous run's backups.
- [ ] Check that the installed QT directory points to the intended checkout. The current Forever installation uses `_classic_beta_/Interface/AddOns/QuestTogether` under the Steam Wine prefix, and its symlink resolves to `/home/alx/code/QuestTogether`.

For this workstation, verify the installation with:

```sh
readlink -f '/home/alx/.local/share/Steam/steamapps/compatdata/2527490029/pfx/drive_c/Program Files (x86)/World of Warcraft/_classic_beta_/Interface/AddOns/QuestTogether'
```

Keep these local directories separate:

| Path | Contents |
| --- | --- |
| `backups/` | Original description, gallery records, and restoration information |
| `raw/` | Unedited window captures, never overwritten by cropped exports |
| `final/` | Reviewed crops or compressed derivatives for upload |
| `manifest.json` | Capture provenance, checksums, captions, destinations, and verification status |
| `QuestTogetherCapture/` | Optional local scene addon; never part of a release package |

## Verify the description

Review every claim against the current code and supported client behavior before updating `CURSEFORGE_DESCRIPTION.md`. Keep defaults separate from optional settings and distinguish local UI demonstrations from live communication evidence.

Write for someone encountering QT for the first time. Explain what they can do, how to do it, and what to expect. Omit development history and incidental implementation choices even when phrased in the present tense: for example, describe how to open a player menu without explaining that Target is its first item. Present integrated features such as clickable tip actions together, rather than as additions. Keep limitations that affect a player's choices or expectations.

Use numbered lists only for procedures whose actions follow one another. Use bullets for independent controls, options, or commands, and prose for setup context and explanations. Do not present a collection of hints as a getting-started sequence.

| Claim | Starting points |
| --- | --- |
| Party Quest Log, compact columns, keyboard controls, and quest states | `QuestCompareWindow.lua`, `QuestCompareInteraction.lua`, `QuestCompletion.lua` |
| Sharing and explanations of results | `QuestCompare.lua`, `QuestSharingResults.lua` |
| Map visibility, partner status, and hovered party information | `PlayerLocations.lua`, `PlayerDetails.lua`, `PartyVisuals.lua`, `Options.lua` |
| Party quest focus and waypoints | `PartyFocusController.lua`, `PartyNavigation.lua`, `PartyWaypointPins.lua` |
| Private notes, clickable tips, and keybindings | `PlayerNotes.lua`, `Hints.lua`, `Bindings.xml` |
| Settings, supported clients, localization, and release changes | `Settings.lua`, TOC files, `locales/`, `release_notes.json` |

Preserve the meaningful limits: other players need compatible QT versions; remote data can be stale; your own party uses Blizzard's map markers; full hovered rosters cover small parties; quest sharing follows WoW eligibility rules; notes stay local. Do not advertise synthetic scenes as proof of successful live requests or imply that every client exposes the same quest, nameplate, and navigation APIs.

## Capture in game

Use the browser automation tool for Chrome and the CurseForge author interface. Native desktop control is unavailable in that tool in this setup; the user approved Niri, xdotool, and ImageMagick for the game capture work.

1. Discover the current game window with `niri msg --json windows`; match the WoW application and title. Discover its X11 window separately with `xdotool search --name 'World of Warcraft'`. Window IDs change across launches; never reuse an old numeric ID blindly.
2. Focus the verified Niri window, then send keyboard input with an explicit `--window "$qt_capture_xid"` on each xdotool input invocation. `wtype` did not deliver working input to this WoW session; `xdotool` did. If xdotool is absent from PATH, use the available Nix package, for example `nix shell nixpkgs#xdotool -c xdotool ...`. Wait for each native input process to finish before calling browser tools; overlapping them can change focus mid-command.
3. Run `/qt disable` before isolated scenes. Keep QuestTogether loaded so its presentation code is available. Load the optional local `QuestTogetherCapture` addon for the current character, then reload as needed.
4. Run `/qtcapture status`. Confirm `liveQT=false`, synthetic players, `nativeQuestData=false`, `networkAdapters=none`, and `savedVariables=none` before using its scenes.
5. Capture scenes with `/qtcapture overview`, `objectives`, `collapsed`, `following`, `share`, `note`, or `focuswarning`. Use `light` and `dark` to change the capture owner's theme; `hide` closes its current scene. Check the addon's current help before assuming an older command remains available.
6. Arrange and inspect the actual UI: all labels readable, icons present, no clipped buttons, useful quest variety, and no error windows. Keep the surrounding game visible enough to establish context. Move the pointer away unless a tooltip or active control is the subject.
7. Save each raw window capture with a unique absolute filename:

```sh
niri msg action screenshot-window --id "$qt_capture_window_id" --path "$qt_capture_raw_path"
```

Set both variables from the current inventory and an absolute path inside `raw/`. Screenshot creation is asynchronous: wait until the new file exists and decodes before opening or cropping it. Review every capture before continuing; an input command succeeding does not prove the intended window changed.

Do not send Escape automatically before commands: it can open the Game Menu. If the notes editor or Party Quest Log keyboard mode currently consumes input, send one Escape to release that focus, inspect the result, then issue the command.

The capture addon uses synthetic player/quest data with QT's actual renderers. Do not contact real users, send invitations or quest-share requests, or enable diagnostics to stage a screenshot. Features outside its scene list need an existing authorized live example or a separately isolated presentation scene. Ordinary QT must be re-enabled explicitly for normal play or intentional live captures.

### Native chat and input checks

- Inspect the current edit focus before sending a slash command. Return may submit an already-open chat edit box instead of opening an empty one; Ctrl+A may act on another focused control. Do not assume the helper's Return/Ctrl+A/type/Return sequence starts from the right state.
- An open note editor, Party Quest Log keyboard mode, chat input, or the Game Menu can change where keys go. Release the observed focus once and inspect again. Repeated Escape presses can open another menu rather than clear the original state.
- The dated run's `game-input.py` contains hardcoded Niri and X11 IDs. Those are recorded session values, not durable configuration. Rediscover both IDs before resuming after a restart, character transition, or lost context; do not replay the script unchanged on that assumption alone.
- Verify the current character's enabled addons and intended layout after switching characters. Readout and layout screenshots are evidence of the selection process, not feature-gallery images.
- For player/quest menu screenshots, use actual linked text in WoW's native QT chat window and open its normal QT menu. Keep the originating chat line visible beside the menu. Do not click an action that sends, invites, shares, or ignores someone merely to obtain the menu screenshot.
- The older `CaptureExtras.lua` log scene uses a private `ScrollingMessageFrame` with no hyperlink click handler. It demonstrates production text formatting, but cannot establish that a real chat link opens a menu. A map-dot player menu also does not substitute for the chat-link screenshot.
- If local demonstration messages are needed, use a separately reviewed local-only native-chat insertion path; do not send fictional lines to Say, Yell, party, channels, or addon peers. Record and restore any native-chat changes separately from private capture frames.

## Prepare upload images

- [ ] Retain raw captures and create separate derivatives in `final/`. Crop to the feature while preserving readable context; do not paint in UI states that the addon did not render.
- [ ] Inspect the crop at normal viewing size and as a small gallery thumbnail. Give each screenshot one clear purpose instead of publishing many nearly identical views.
- [ ] Prefer PNG for crisp text where it fits the current upload limit. If necessary, create a JPEG derivative with ImageMagick and inspect text clarity. Read the uploader's current size/type limits; an earlier upload limit was 2 MB, which should not be treated as permanent.
- [ ] Use stable descriptive names such as `party-quest-log-objectives.png`, `party-quest-log-compact.png`, or `private-player-notes.png`. Captions explain the feature; they do not expose internal scene commands or test identities as real players.
- [ ] Record image dimensions, file size, and SHA-256 for both raw and final files. Keep the crop rectangle and any resizing/quality parameters reproducible.

One manifest entry per image should include these fields:

```json
{
  "key": "PARTY_QUEST_LOG",
  "scene": "objectives",
  "data": "synthetic",
  "raw": "raw/party-quest-log-objectives.png",
  "final": "final/party-quest-log-objectives.png",
  "raw_sha256": "fill after capture",
  "final_sha256": "fill after export",
  "crop": null,
  "caption": "Compare each player's quest objectives and progress.",
  "public_url": null,
  "gallery_id": null,
  "uploaded": false,
  "public_verified": false
}
```

## Update CurseForge and verify

1. Open QuestTogether in CurseForge Authors, project `296929`, using the signed-in Chrome session. Use the normal interface through any Cloudflare challenge; do not substitute unverified automated HTTP requests.
2. Use **Media → Add media** to upload reviewed final images. The chooser accepts multiple local image paths at once. If browser automation cannot transfer the files, check **Allow access to file URLs** for its Chrome extension; enabling it resolved this session's upload failure. After a Chrome restart, rediscover the browser and tab because their automation IDs can change.
3. Selecting files uploads them and creates media entries immediately. Record the media IDs and public image URLs before retrying an uncertain upload, to avoid duplicates. Edit captions/metadata and click **Apply**; this saves the metadata but leaves the modal open. After confirming the save, **Cancel** closes the modal without undoing those saved entries. Verify each image renders before replacing older gallery entries.
4. Replace each `{{SCREENSHOT_...}}` token in the description with its verified public URL. Search for remaining placeholders, validate links, and review the full copy before saving.
5. Open the description editor in **Markdown** mode, insert the prepared copy, inspect its preview, and save. Keep the repository copy synchronized with the published text.
6. Reopen the public project page and gallery. Check screenshot order, image loading, captions, headings, lists, links, and mobile-width readability. If moderation or caching delays visibility, record it as pending rather than claiming the public update is complete.
7. Save the final public URLs and verification time in the run manifest. Compare the published page with the local description and intended gallery before reporting completion.

## Restore the playing environment

- [ ] Run `/qtcapture stop`, disable the temporary capture addon for the character, and reload. Remove only temporary links/files created for this run; preserve its source and capture evidence locally.
- [ ] Run `/qt enable` and confirm normal QT operation is restored. Verify the original profile, theme, layouts, UI scale, and other changed settings against the preparation record.
- [ ] Confirm no capture windows or synthetic players remain and no capture addon files entered the release package or tracked production addon files.
- [ ] Report the published description/gallery URLs, any pending public verification, and restoration status. Screenshot preparation alone is not a completed upload.

## Earlier completed refresh: 2026-10-14

- Published the full feature rewrite and short summary at https://www.curseforge.com/wow/addons/questtogether. Editable source: `CURSEFORGE_DESCRIPTION.md`.
- Nine fresh in-game screenshots are featured; twelve older gallery images remain available but unfeatured. Ten linked images appear within the description, including the existing player-nameplate example.
- Capture source: QT 7.2.1, commit `a1c6955f928fec63baf31f5cc8d1a1e004c00320`, WoW Forever. Scenes use a private owner and fictional data. This verifies presentation, not multiplayer delivery.
- Browser verification confirmed the published text, all ten loaded inline images, gallery captions, and full-size image links. At 390px phone width, command tables were too wide; a command list solved it. The short quest-state table fits.
- All raw files, final crops, checksums, exact image URLs, and proof screenshots are in `.local/curseforge-refresh/manifest.json` and adjacent files. Preserve this run before starting another.
- `/qtcapture stop` was run; the temporary installed addon symlink was removed; the UI was reloaded; normal QT was re-enabled. The local check printed `QT restored=true; capture=nil`, and ordinary incoming updates resumed.
- Direct gallery star controls immediately toggle featured status. Existing media were retained to avoid irreversible deletion. Caption **Apply** saves without closing its editor; wait for the saved state before closing it.
- Keep browser batches under the tool timeout (or set an explicit longer timeout). A timeout can reset handles; rediscover browser IDs and use a fresh tab in the same selected browser if the old tab reports an unattached debugger. Do not blindly replay toggles: inspect the persisted star state first.

## Completed manual baseline: 2026-10-14

This is a second run, separate from the completed refresh above. Its working directory is `.local/curseforge-refresh/manual-2026-10-14/`. The user requested one short introductory paragraph followed by a practical manual, with **all screenshots captured afresh**.

- `CURSEFORGE_DESCRIPTION.md` contains the complete manual with **21 linked inline screenshots and no remaining image placeholders**. Features are described as current behavior rather than a sequence of additions. Interactive tips include direct actions to the relevant windows, settings, and controls.
- **24 fresh images are uploaded, all gallery captions are applied, and eight images are featured. All 21 images from the previous gallery were removed.** `gallery-final-prepublish.json` verifies the 24 fresh URLs and absence of old URLs. `gallery-final.json` records all final titles; the public verification records confirm the complete gallery and featured selection.
- `manifest.json` maps the 21 inline images and three gallery extras to source captures, crops, hashes, dimensions, captions, URLs, and verification gates. `upload-plan.json` holds the same 24 destinations and gallery labels. Extras show the Party Quest Log player-column menu, shared-waypoint navigation menu, and minimap status tooltip.
- The original description, gallery snapshots, previous manifest, and a local SavedVariables backup remain in `backups/`. SavedVariables are private restoration material and must not be uploaded.
- Approved records come from `qa-candidates-pql-chat.json` and `navigation-crop-candidates.json`; rejected candidates remain documented. All final file hashes, dimensions, and sizes were checked. The four settings images use `1150x900+1215+290` crops from raw05–08, verified by exact decoded-pixel comparison.
- Navigation retakes raw60–64 show the pointer on the actual hovered or clicked pin. The world-map waypoint tooltip, waypoint navigation menu, minimap waypoint, map player menu, and party-roster tooltip each have their own image. Do not substitute earlier held candidates.
- Player and quest menus were opened from actual linked text in WoW's native QT chat window. The private formatting-only capture frame does not demonstrate hyperlink behavior. Chat-menu images retain the originating line and visible pointer.
- Bubbles and player logos use raw77, with isolated local QT presentation attached to an actual visible player's native nameplate. No request, invitation, progress announcement, or live player-store change was sent to create those scenes. Captions describe the rendered feature without claiming multiplayer delivery or showing nonexistent bubble controls.
- Capture scene extensions remain local in `CaptureManual.lua`, `CaptureNavigation.lua`, and `CaptureDispatch.lua`. Forever's map-pin instructions were verified in the exported `Blizzard_SharedMapDataProviders/WaypointLocationDataProvider.lua`; other clients retain client-neutral instructions.
- **The playing environment has been returned to normal:** the publishing agent ran `/qtcapture stop`, `/qt enable`, disabled the temporary capture addon, and reloaded. Normal profiles are enabled. The installed `QuestTogetherCapture` symlink was removed, and filesystem inspection confirms that path is absent. Local source, raw captures, and restoration backups remain preserved. The game readout in `raw/81-restored-runtime.png` and `restored-runtime-proof.png` confirms `QT restored=true; capture=nil; devlogall=true`. Modern and extra action bars remain off as requested. An exact comparison with the original camera position is not recorded and was not required for completion.
- **The manual is published and publicly verified.** `public-verification.json` records the rendered description, all 21 loaded inline images with matching full-size links, and eight featured images. `public-gallery-verification.json` confirms all 24 gallery images load and use only this run's URLs; their captions match the manifest.
- Desktop and phone-width views were inspected. `public-desktop.png`, `public-waypoints-desktop.png`, and `public-mobile.png` preserve the visual checks. At a 390px phone viewport, the document is 375px wide and the description 335px wide, with no image overflow. The browser viewport was restored afterward.
- The manifest records all final evidence paths and hashes, public URLs, timestamps, and completed gates. This task updated the listing and documentation only; it did not create a commit or addon release.

## Latest completed theme-placement revision: 2026-10-14

- The objectives instructions use the fresh dark-theme capture `raw/86-dark-objectives-expanded.png`, cropped to `1584x908+928+264` as `final/party-quest-log-dark-objectives.png`. The crop matches the source pixels exactly. The initial raw85 capture did not expand the intended quest and is excluded.
- The existing raw29 light-theme image remains unchanged and appears only beneath **Appearance and accessibility → Choose a theme**, beside the **General → Theme** instruction. It has the separate `SCREENSHOT_LIGHT_THEME` manifest slot. The accessibility-settings image remains beside the scale and motion controls.
- The new dark upload uses attachment `2055/421`. Its title is **Expanded quest objectives** and caption is **Expand a quest to compare each party member’s objective progress.** The light image uses title **Light theme** and caption **Choose Light under General → Theme to use light parchment in QuestTogether windows.** The dark example is featured and the light example is unfeatured, retaining eight featured images.
- This revision has **25 gallery images and 22 inline images**, all publicly loaded and verified. `theme-review/` preserves the preceding copy and manifest. Its `public-verification.json` records all inline images and the eight featured URLs; `public-themes-final.png` shows the complete light image beneath **Appearance and accessibility → Choose a theme** and its **General → Theme** instruction. `gallery-verification.json` confirms all 25 gallery images and their captions. Gallery titles were saved through the author interface.
- Phone-width checks in `theme-review/mobile-verification.json` and `public-mobile.png` confirm a 390px viewport, 375px document, and no overflowing images. The browser viewport was reset after inspection.
- Capture cleanup, temporary-addon removal, and reload are complete after the dark recapture. `raw/90-theme-restoration-readout.png` and `theme-review/restored-runtime-final.png` show `QT restored=true; capture=nil`; filesystem inspection confirms the installed capture-addon path is absent. Requested action-bar preferences remain in place. No addon release or commit is part of this revision.

## LFQP minimap capture and diagnostics wording: 2026-10-14

- `lfqp-review/` preserves the prior description, manifest, upload plan, and public verification. Fresh raw93 uses the production minimap glow renderer on the actual icon, invoked through an isolated presentation-only receiver. No partner preference or network publication was changed. The final crop is `310x334+3130+0`; no compositing, recoloring, or resizing was used.
- Attachment `2055/499` appears directly below the LFQP enabling instructions. Gallery title: **Looking for Questing Partners**. It is unfeatured; the eight featured screenshots remain unchanged.
- The diagnostics paragraph explicitly states that this information is shared **only with the developer**, retaining the separate opt-out and private-notes exclusion.
- After capture, the normal minimap renderer restored the icon, the temporary receiver was cleared, and raw94 verifies `LFQP=false; capture=nil`. No settings or addon files required restoration. To repeat, use a minimal explicit owner with the real minimap button and production glow method; never toggle `/qt lfg` to stage a local-only photo. Keep the pointer away because the real tooltip reflects the unchanged actual status.
