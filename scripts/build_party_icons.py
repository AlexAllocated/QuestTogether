#!/usr/bin/env python3
"""Render the party badge, leader crown, and hover ring textures; requires rsvg-convert and magick."""

from pathlib import Path
import struct
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
SIZE = 64



def render(name):
    output = ROOT / "Media" / (name + ".tga")
    with tempfile.TemporaryDirectory(prefix="questtogether-chat-icon-") as temp:
        png = Path(temp) / "icon.png"
        tga = Path(temp) / "icon.tga"
        subprocess.run([
            "rsvg-convert", "--width", str(SIZE * 4), "--height", str(SIZE * 4),
            "--output", str(png), str(ROOT / "Media" / (name + ".svg")),
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
            raise SystemExit("Expected an uncompressed 64x64 32-bit TGA with 8-bit alpha")
        output.write_bytes(data)
    print(f"Wrote {output.relative_to(ROOT)} ({SIZE}x{SIZE}, 32-bit RGBA)")


if __name__ == "__main__":
    for name in ("PartyBadge", "PartyLeader", "PartyHighlight"):
        render(name)
