#!/usr/bin/env python3
"""Build scalable rounded-panel corner artwork from addon-owned SVG sources."""
from pathlib import Path
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    with tempfile.TemporaryDirectory(prefix="qt-panel-corners-") as temp:
        for name in ("PanelCornerFill", "PanelCornerBorder"):
            png = Path(temp) / (name + ".png")
            target = ROOT / "Media" / (name + ".tga")
            subprocess.run(["rsvg-convert", "-o", str(png), str(target.with_suffix(".svg"))], check=True)
            subprocess.run(["magick", str(png), "-alpha", "on", "-depth", "8", "-type", "TrueColorAlpha", "-compress", "none", str(target)], check=True)
            data = target.read_bytes()
            width, height, depth, descriptor = struct.unpack_from("<HHBB", data, 12)
            if data[1:3] != b"\x00\x02" or (width, height, depth) != (64, 64, 32) or descriptor & 15 != 8:
                raise SystemExit("Expected uncompressed 64x64 RGBA texture")
            print(f"Built {target.name}")


if __name__ == "__main__":
    main()
