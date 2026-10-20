# Runtime textures

Release ZIPs must include all addon-owned runtime textures:

- `Media/QuestTogetherIcon.tga` — scroll logo used by buttons, player plates, and tooltips.
- `Media/QuestTogetherTipIcon.tga` — QT scroll paired with a large gold bulb for tips. Build with `python3 scripts/build_minimap_icon.py --tip`; this also generates the matching PNG for web/Discord notes and the SVG preview from the original emblem.
- `Media/QuestTogetherPartnerIcon.tga` — static gold-glow scroll for LFQP announcements; build with `python3 scripts/build_minimap_icon.py --glow`.
- `Media/QuestTogetherDeveloperIcon.tga` — rear scroll and gold gear for verified developer chat prefixes. Build with `python3 scripts/build_minimap_icon.py --developer`; `--developer-glow` builds `QuestTogetherDeveloperPartnerIcon.tga` for LFQP. Both commands also produce PNG and SVG previews.
- `Media/ChatBubbleIcon.tga` — transparent speech bubble used by QT chat logs and overhead bubbles.
- `Media/MinimapPartnerRing.tga` — animated gold halo around the minimap button while LFQP.
- `Media/PanelCornerFill.tga` and `Media/PanelCornerBorder.tga` — 64×64 white corner artwork for scalable, class-tinted rounded panels. Build from the matching SVGs with `python3 scripts/build_panel_corners.py`.
- `Media/DeveloperGear.tga` — white, class-tinted gear for signature-verified developer map and minimap dots. Regenerate with `python3 scripts/build_party_icons.py`.
- `Media/VIPStar.tga` — class-tinted VIP marker, built with `python3 scripts/build_party_icons.py`.
- `Media/QuestTogetherVIPIcon.tga` — rear scroll and gold VIP star. Build with `python3 scripts/build_minimap_icon.py --vip`; `--vip-glow` builds the LFQP variant. Both produce PNG and SVG previews.
- `Media/Minimap{,VIP,Developer}Button.tga` — launcher-specific scroll, star, and gear icons with a metallic contour instead of a circular overlay. `python3 scripts/build_minimap_buttons.py` also builds matching `Highlight` and `Glow` textures. Chat and map artwork stay separate.
- `Media/PartyWaypoint.tga` — 32×32 class-tinted map pin with a dark outline. Regenerate with `rsvg-convert -o /tmp/qt-party-pin.png Media/PartyWaypoint.svg` then `magick /tmp/qt-party-pin.png -define tga:bits-per-sample=8 -compress none Media/PartyWaypoint.tga`.
- `Media/QuestCompareScroll.tga` — 1024×512 parchment scroll frame for Party Quest Log; regenerate from its SVG with `python3 scripts/build_compare_scroll.py`.

The icon `.tga` files are uncompressed 128×128 textures with 8-bit alpha. Regenerate
them with `python3 scripts/build_minimap_icon.py`,
`python3 scripts/build_chat_icon.py`, and
`python3 scripts/build_minimap_ring.py`, respectively. The SVG sources and build
scripts are development assets; screenshot files in this directory are not
runtime textures.

## Release-note screenshots

The `ReleaseNotes/PartyQuestLog*.png` files are unedited, user-supplied Party Quest Log preview screenshots.
Retail and Forever overview images retain their client-specific player names;
the expanded-objective image was captured in Forever. Web release notes label
these separately, and in-game notes select the overview using QT's regional-name
adapter. The objective screenshot is shown in-game only on Forever.

The matching uncompressed RGB TGA files preserve the original pixels at the
upper left of a 2048×1024 canvas. ReleaseNotesWindow crops the unused canvas with
texture coordinates and scales proportionally. To regenerate an asset:

```sh
magick Media/ReleaseNotes/PartyQuestLogRetail.png -background black -gravity northwest -extent 2048x1024 -alpha off -compress none Media/ReleaseNotes/PartyQuestLogRetail.tga
```

Ship all three TGA files with the addon; the PNG originals support web notes.

`PartyQuestFollowingForever.tga` uses a 2048×256 canvas for its 1198×199
screenshot. The smaller canvas removes unused transparent padding without
changing any screenshot pixels; its texture coordinates are defined alongside
the other illustrations in `ReleaseNotesWindow.lua`.

`ReleaseNotes/VIPCosmetics.png` is an 800×420 montage of fresh Forever captures:
the class-colored map star and individual VIP tooltip, the VIP minimap button,
and the VIP chat prefix. The map capture uses the owner's activated VIP identity
in a local presentation-only fixture, positioned away from the player's arrow
to illustrate another player's view. It does not modify peer records or send
invented player observations. The tooltip, symbols, and chat prefix use the
production renderers. The launcher is the live VIP button. Screenshots are
cropped and arranged without altering the rendered UI.

The same montage appears in the VIP window and 8.0.0 release notes. Its
uncompressed RGBA TGA occupies the upper-left 800×420 pixels of a 1024×512
transparent canvas:

```sh
magick Media/ReleaseNotes/VIPCosmetics.png -background none -gravity northwest -extent 1024x512 -type TrueColorAlpha -compress none Media/ReleaseNotes/VIPCosmetics.tga
```
