#!/usr/bin/env python3
"""Render the existing logo's scroll emblem as a transparent WoW texture.

Run: python3 scripts/build_minimap_icon.py
Requires rsvg-convert (librsvg) and magick (ImageMagick 7).
The original logo.svg and logo.png are never modified.
"""

from pathlib import Path
import copy
import struct
import subprocess
import tempfile
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "Media" / "QuestTogetherIcon.tga"
SVG_NS = "http://www.w3.org/2000/svg"
SIZE = 128


def main():
    source = ET.parse(ROOT / "logo.svg")
    scrolls = source.find(f".//{{{SVG_NS}}}g[@id='quest-scrolls']")
    if scrolls is None:
        raise SystemExit("logo.svg is missing the quest-scrolls emblem")

    ET.register_namespace("", SVG_NS)
    # Include the original paths and their 32-unit strokes, with even padding.
    icon = ET.Element(f"{{{SVG_NS}}}svg", {
        "width": str(SIZE),
        "height": str(SIZE),
        "viewBox": "365 253 560 560",
    })
    icon.append(copy.deepcopy(scrolls))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="questtogether-icon-") as temp:
        svg = Path(temp) / "icon.svg"
        png = Path(temp) / "icon.png"
        tga = Path(temp) / "icon.tga"
        ET.ElementTree(icon).write(svg, encoding="utf-8", xml_declaration=True)
        subprocess.run([
            "rsvg-convert", "--width", str(SIZE * 4), "--height", str(SIZE * 4),
            "--output", str(png), str(svg),
        ], check=True)
        subprocess.run([
            "magick", str(png), "-filter", "Lanczos", "-resize", f"{SIZE}x{SIZE}",
            "-alpha", "on", "-depth", "8", "-type", "TrueColorAlpha",
            "-compress", "none", str(tga),
        ], check=True)
        data = tga.read_bytes()
        width, height, depth, descriptor = struct.unpack_from("<HHBB", data, 12)
        if (
            data[1:3] != b"\x00\x02"
            or (width, height, depth) != (SIZE, SIZE, 32)
            or (descriptor & 15) != 8
        ):
            raise SystemExit("Expected an uncompressed 128x128 32-bit TGA with 8-bit alpha")
        OUTPUT.write_bytes(data)
    print(f"Wrote {OUTPUT.relative_to(ROOT)} ({SIZE}x{SIZE}, 32-bit RGBA)")


if __name__ == "__main__":
    main()
