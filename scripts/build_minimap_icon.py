#!/usr/bin/env python3
"""Render the existing logo's scroll emblem as a transparent WoW texture.

Run: python3 scripts/build_minimap_icon.py
Requires rsvg-convert (librsvg) and magick (ImageMagick 7).
The original logo.svg and logo.png are never modified.
"""

from pathlib import Path
import copy
import argparse
import struct
import subprocess
import tempfile
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "Media" / "QuestTogetherIcon.tga"
SVG_NS = "http://www.w3.org/2000/svg"
SIZE = 128


def tip_icon(scrolls):
    """Pair the original rear scroll with a large gold tip bulb."""
    def element(parent, name, **attributes):
        return ET.SubElement(parent, f"{{{SVG_NS}}}{name}", attributes)

    icon = ET.Element(f"{{{SVG_NS}}}svg", {
        "width": str(SIZE), "height": str(SIZE), "viewBox": "0 0 128 128",
    })
    emblem = element(icon, "g", transform="translate(-83.4286 -57.8286) scale(.2285714)")
    rear_scroll = copy.deepcopy(scrolls)
    for shape in list(rear_scroll):
        if shape.get("id") not in ("rear-scroll", "rear-roll"):
            rear_scroll.remove(shape)
    emblem.append(rear_scroll)
    badge = element(icon, "g")

    def path(shape, fill, stroke="#222B30", width="7", **attributes):
        return element(badge, "path", d=shape, fill=fill, stroke=stroke,
                       **{"stroke-width": width, "stroke-linejoin": "round", "stroke-linecap": "round"},
                       **attributes)

    bulb = "M77 28 C59 28 45 42 45 60 C45 73 51 80 58 89 L61 97 H93 L96 89 C103 80 109 73 109 60 C109 42 95 28 77 28 Z"
    path(bulb, "#D9A62A")
    path("M61 97 H93 V108 Q93 115 86 115 H68 Q61 115 61 108 Z", "#F5F2E9")
    path("M69 96 V78 L62 67 M85 96 V78 L92 67 M62 67 L77 76 L92 67", "none", width="5")
    path("M67 122 H87", "none", width="6")
    return icon


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    variant = parser.add_mutually_exclusive_group()
    variant.add_argument("--glow", action="store_true", help="Render the LFQP announcement variant")
    variant.add_argument("--tip", action="store_true", help="Render the scroll and gold tip bulb (TGA, PNG and SVG)")
    args = parser.parse_args()
    name = "QuestTogetherTipIcon.tga" if args.tip else "QuestTogetherPartnerIcon.tga" if args.glow else OUTPUT.name
    output = ROOT / "Media" / name
    source = ET.parse(ROOT / "logo.svg")
    scrolls = source.find(f".//{{{SVG_NS}}}g[@id='quest-scrolls']")
    if scrolls is None:
        raise SystemExit("logo.svg is missing the quest-scrolls emblem")

    ET.register_namespace("", SVG_NS)
    # Include the original paths and their 32-unit strokes, with even padding.
    icon = ET.Element(f"{{{SVG_NS}}}svg", {
        "width": str(SIZE),
        "height": str(SIZE),
        "viewBox": "315 203 660 660" if args.glow else "365 253 560 560",
    })
    emblem = copy.deepcopy(scrolls)
    if args.glow:
        # A full pixel of solid gold must survive the log's 14px inline size.
        # Draw an explicit vector contour instead of relying on morphology,
        # whose rasterized outline was too thin at this scale.
        defs = ET.SubElement(icon, f"{{{SVG_NS}}}defs")
        glow = ET.SubElement(defs, f"{{{SVG_NS}}}filter", {
            "id": "partner-glow", "x": "-30%", "y": "-30%", "width": "160%", "height": "160%",
            "color-interpolation-filters": "sRGB",
        })
        ET.SubElement(glow, f"{{{SVG_NS}}}feGaussianBlur", {"stdDeviation": "12"})
        contour = copy.deepcopy(scrolls)
        for element in contour.iter():
            element.attrib.pop("id", None)
            element.set("stroke", "#FFE438")
            element.set("stroke-width", "132")
            if element.get("fill") != "none":
                element.set("fill", "#FFE438")
        halo = copy.deepcopy(contour)
        halo.set("filter", "url(#partner-glow)")
        icon.append(halo)
        icon.append(contour)
    icon.append(emblem)
    if args.tip:
        icon = tip_icon(scrolls)
    output.parent.mkdir(parents=True, exist_ok=True)
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
        output.write_bytes(data)
        if args.tip:
            ET.ElementTree(icon).write(output.with_suffix(".svg"), encoding="utf-8", xml_declaration=True)
            subprocess.run([
                "magick", str(tga), "-strip", "-define", "png:exclude-chunks=date,time",
                str(output.with_suffix(".png")),
            ], check=True)
    print(f"Wrote {output.relative_to(ROOT)} ({SIZE}x{SIZE}, 32-bit RGBA)")


if __name__ == "__main__":
    main()
