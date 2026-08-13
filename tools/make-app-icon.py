#!/usr/bin/env python3
"""Render the app icon from the same mark the app draws.

The icon is `DotMatrix.patterns[0]` — the 'u' — on `Palette.lcdGround`, drawn with
`DotMatrix.rect`'s geometry so it is the mark, not a picture of it: six columns
across the full width, each dot centred in its cell, lit dots larger than dim.

Run `just icon`. Writes Utt/Resources/Assets.xcassets/AppIcon.appiconset/.
"""

import json
import pathlib

from PIL import Image, ImageDraw

# Palette.lcdGround (#303027) and Palette.accent, straight from Utt/Design/Palette.swift.
GROUND = (48, 48, 39, 255)
ACCENT = (212, 80, 30, 255)
DIM = (255, 255, 255, 38)

# DotMatrix.patterns[0], the 'u'.
LIT = {7, 8, 13, 14, 21, 22, 27, 28}

# The ground fills the canvas. macOS 26 masks every icon to its own rounded square
# and paints a plate behind it, so drawing our own inset square put a second, smaller
# tile inside the system's — the "border" in the Dock. The grid keeps its margin;
# the ground does not.
GRID = 0.78

# 4x oversampled, then downsampled — the dots are small enough at 16pt that
# aliasing on their edges is the difference between a mark and a smudge.
SUPERSAMPLE = 4

SIZES = [16, 32, 64, 128, 256, 512, 1024]
# (idiom size, scale, pixel size) — the set Xcode expects for macOS.
ENTRIES = [
    (16, 1), (16, 2), (32, 1), (32, 2),
    (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]


def draw_icon(pixels: int) -> Image.Image:
    canvas = pixels * SUPERSAMPLE
    image = Image.new("RGBA", (canvas, canvas), GROUND)
    draw = ImageDraw.Draw(image)

    # DotMatrix.rect: step = size / 6, radius = step * (0.34 lit / 0.24 dim),
    # x = step * (0.5 + col) - radius. The margin is what keeps the corner dots clear
    # of the system's rounded mask.
    grid = canvas * GRID
    origin = (canvas - grid) / 2
    step = grid / 6
    for index in range(36):
        lit = index in LIT
        radius = step * (0.34 if lit else 0.24)
        centre_x = origin + step * (0.5 + index % 6)
        centre_y = origin + step * (0.5 + index // 6)
        draw.ellipse(
            [centre_x - radius, centre_y - radius, centre_x + radius, centre_y + radius],
            fill=ACCENT if lit else DIM,
        )

    return image.resize((pixels, pixels), Image.LANCZOS)


def main() -> None:
    root = pathlib.Path(__file__).resolve().parent.parent
    out = root / "Utt/Resources/Assets.xcassets/AppIcon.appiconset"
    out.mkdir(parents=True, exist_ok=True)

    for pixels in SIZES:
        draw_icon(pixels).save(out / f"icon_{pixels}.png")

    images = [
        {
            "idiom": "mac",
            "size": f"{size}x{size}",
            "scale": f"{scale}x",
            "filename": f"icon_{size * scale}.png",
        }
        for size, scale in ENTRIES
    ]
    contents = {"images": images, "info": {"version": 1, "author": "xcode"}}
    (out / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")

    catalog = out.parent / "Contents.json"
    catalog.write_text(json.dumps({"info": {"version": 1, "author": "xcode"}}, indent=2) + "\n")

    print(f"→ {out.relative_to(root)}  ({len(SIZES)} pngs)")


if __name__ == "__main__":
    main()
