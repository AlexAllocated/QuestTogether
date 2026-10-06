# Runtime textures

Release ZIPs must include all addon-owned runtime textures:

- `Media/QuestTogetherIcon.tga` — scroll logo used by buttons, player plates, and tooltips.
- `Media/QuestTogetherPartnerIcon.tga` — static gold-glow scroll for LFQP announcements; build with `python3 scripts/build_minimap_icon.py --glow`.
- `Media/ChatBubbleIcon.tga` — transparent speech bubble used by QT chat logs and overhead bubbles.
- `Media/MinimapPartnerRing.tga` — animated gold halo around the minimap button while LFQP.
- `Media/PanelCornerFill.tga` and `Media/PanelCornerBorder.tga` — 64×64 white corner artwork for scalable, class-tinted rounded panels. Build from the matching SVGs with `python3 scripts/build_panel_corners.py`.
- `Media/PartyWaypoint.tga` — 32×32 class-tinted map pin with a dark outline. Regenerate with `rsvg-convert -o /tmp/qt-party-pin.png Media/PartyWaypoint.svg` then `magick /tmp/qt-party-pin.png -define tga:bits-per-sample=8 -compress none Media/PartyWaypoint.tga`.
- `Media/QuestCompareScroll.tga` — 1024×512 parchment scroll frame for Party Quest Log; regenerate from its SVG with `python3 scripts/build_compare_scroll.py`.

The icon `.tga` files are uncompressed 128×128 textures with 8-bit alpha. Regenerate
them with `python3 scripts/build_minimap_icon.py`,
`python3 scripts/build_chat_icon.py`, and
`python3 scripts/build_minimap_ring.py`, respectively. The SVG sources and build
scripts are development assets; screenshot files in this directory are not
runtime textures.
