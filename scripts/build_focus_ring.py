#!/usr/bin/env python3
"""Build the class-tinted focus ring with a genuinely transparent center."""

from pathlib import Path
import math
import struct


SIZE = 64
# Displayed at 12px: a substantial 2.5px stroke around a 7px opening.
OUTER_RADIUS = SIZE / 2
INNER_RADIUS = SIZE * 7 / 24
OUTPUT = Path(__file__).resolve().parents[1] / "Media" / "FocusRing.tga"


def main():
    pixels = bytearray()
    for y in range(SIZE):
        for x in range(SIZE):
            radius = math.hypot(x + 0.5 - SIZE / 2, y + 0.5 - SIZE / 2)
            outer = max(0, min(1, OUTER_RADIUS + 0.5 - radius))
            inner = max(0, min(1, radius - INNER_RADIUS + 0.5))
            pixels.extend((255, 255, 255, round(255 * outer * inner)))
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
    OUTPUT.write_bytes(header + pixels)
    print(f"Wrote {OUTPUT.name} ({SIZE}x{SIZE}, 32-bit RGBA)")


if __name__ == "__main__":
    main()
