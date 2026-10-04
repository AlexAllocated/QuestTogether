# Runtime textures

Release ZIPs must include all addon-owned runtime textures:

- `Media/QuestTogetherIcon.tga` — scroll logo used by buttons, player plates, and tooltips.
- `Media/QuestTogetherPartnerIcon.tga` — static gold-glow scroll for LFQP announcements; build with `python3 scripts/build_minimap_icon.py --glow`.
- `Media/ChatBubbleIcon.tga` — transparent speech bubble used by QT chat logs and overhead bubbles.
- `Media/MinimapPartnerRing.tga` — animated gold halo around the minimap button while LFQP.

The `.tga` files are uncompressed 128×128 textures with 8-bit alpha. Regenerate
them with `python3 scripts/build_minimap_icon.py`,
`python3 scripts/build_chat_icon.py`, and
`python3 scripts/build_minimap_ring.py`, respectively. The SVG sources and build
scripts are development assets; screenshot files in this directory are not
runtime textures.
