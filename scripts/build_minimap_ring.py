#!/usr/bin/env python3
"""Build the transparent circular LFQP halo without third-party dependencies."""

from pathlib import Path
import math
import struct


SIZE = 128
OUTPUT = Path(__file__).resolve().parents[1] / "Media" / "MinimapPartnerRing.tga"


def main():
    # Bright gold core with a soft outer halo; the middle remains transparent.
    pixels = bytearray()
    for y in range(SIZE):
        for x in range(SIZE):
            distance = abs(math.hypot(x + 0.5 - SIZE / 2, y + 0.5 - SIZE / 2) - 45)
            core = max(0, min(1, 5 - distance))
            halo = 0.6 * math.exp(-0.5 * (distance / 7) ** 2)
            alpha = max(core, halo) if distance < 18 else 0
            pixels.extend((round(30 + 90 * core), round(165 + 60 * core), 255, round(alpha * 255)))
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
    OUTPUT.write_bytes(header + pixels)
    print(f"Wrote {OUTPUT.name} ({SIZE}x{SIZE}, 32-bit RGBA)")


if __name__ == "__main__":
    main()
