#!/usr/bin/env python3
"""Build the addon-owned parchment frame with rsvg-convert and ImageMagick."""
from pathlib import Path
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def main():
    with tempfile.TemporaryDirectory(prefix="qt-compare-scroll-") as temp:
        png = Path(temp) / "scroll.png"
        target = ROOT / "Media" / "QuestCompareScroll.tga"
        subprocess.run(["rsvg-convert", "-o", str(png), str(ROOT / "Media" / "QuestCompareScroll.svg")], check=True)
        subprocess.run(["magick", str(png), "-alpha", "on", "-depth", "8", "-type", "TrueColorAlpha", "-compress", "none", str(target)], check=True)
        data = target.read_bytes()
        width, height, depth, descriptor = struct.unpack_from("<HHBB", data, 12)
        if data[1:3] != b"\x00\x02" or (width, height, depth) != (1024, 512, 32) or descriptor & 15 != 8:
            raise SystemExit("Expected uncompressed 1024x512 RGBA texture")
        print(f"Built {target.name}: {width}x{height}")

if __name__ == "__main__":
    main()
