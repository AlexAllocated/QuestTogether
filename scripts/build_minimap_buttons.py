#!/usr/bin/env python3
"""Give launcher logos a dark/gold rim following their outer silhouette.

Uses the existing logo textures without changing chat or map artwork.
Requires ImageMagick 7. Outputs uncompressed 128x128 RGBA TGA files.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MEDIA = ROOT / "Media"


def magick(*args):
    subprocess.run(["magick", *map(str, args)], check=True)


def build(source, name):
    with tempfile.TemporaryDirectory(prefix="qt-minimap-button-") as directory:
        temp = Path(directory)
        art, alpha = temp / "art.png", temp / "alpha.png"
        # Four-times sampling keeps the narrow bevel smooth at minimap size.
        magick(source, "-resize", "400x400", "-gravity", "center",
               "-background", "none", "-extent", "512x512", art)
        magick(art, "-alpha", "extract", alpha)

        def mask(radius):
            path = temp / f"mask-{radius}.png"
            magick(alpha, "-morphology", "Dilate", f"Disk:{radius}", path)
            return path

        def layer(color, coverage, destination):
            magick("-size", "512x512", color, coverage,
                   "-alpha", "off", "-compose", "CopyOpacity", "-composite", destination)

        outer, rim, inner = temp / "outer.png", temp / "rim.png", temp / "inner.png"
        layer("xc:#151713", mask(36), outer)
        layer("gradient:#f0d49a-#70502c", mask(28), rim)
        layer("xc:#332a1d", mask(10), inner)
        button = temp / "button.png"
        magick(outer, rim, "-compose", "Over", "-composite", inner, "-composite",
               art, "-composite", button)
        # Mouseover and LFQP retain the same silhouette instead of adding circles.
        highlight = temp / "highlight.png"
        layer("xc:#fff0bd", mask(28), highlight)
        magick(highlight, "-channel", "A", "-evaluate", "multiply", "0.35",
               "+channel", highlight)
        halo = temp / "halo.png"
        magick(mask(40), mask(20), "-compose", "MinusSrc", "-composite",
               "-blur", "0x10", temp / "halo-mask.png")
        layer("xc:#ffe438", temp / "halo-mask.png", halo)
        for suffix, image in (("", button), ("Highlight", highlight), ("Glow", halo)):
            output = MEDIA / (name + suffix)
            magick(image, "-filter", "Lanczos", "-resize", "128x128",
                   "-depth", "8", "-type", "TrueColorAlpha", "-compress", "none",
                   output.with_suffix(".tga"))
            if not suffix:
                magick(output.with_suffix(".tga"), "-strip", output.with_suffix(".png"))
            print(f"Wrote {output.relative_to(ROOT)}")


if __name__ == "__main__":
    build(MEDIA / "QuestTogetherIcon.tga", "MinimapButton")
    build(MEDIA / "QuestTogetherVIPIcon.tga", "MinimapVIPButton")
    build(MEDIA / "QuestTogetherDeveloperIcon.tga", "MinimapDeveloperButton")
