#!/usr/bin/env python3
"""Render the app icon from the same mark the app draws.

The icon is `DotMatrix.patterns[0]` — the 'u' — on `Palette.lcdGround`, drawn with
`DotMatrix.rect`'s geometry so it is the mark, not a picture of it: six columns
across the full width, each dot centred in its cell, lit dots larger than dim.

Output is an Icon Composer document, `Utt/Resources/AppIcon.icon`, not an
appiconset. macOS 26 composites a legacy `.icns` onto its own light plate and
shrinks it to fit — that plate is the grey border no amount of full-bleed artwork
removes. A `.icon` supplies the background itself, so the ground *is* the tile.

Run `just icon`.
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

# The grid's share of the canvas. The margin keeps the corner dots clear of the
# rounded mask the system applies to every icon.
GRID = 0.72

# The layer is drawn once, at the size Icon Composer documents use.
CANVAS = 1024

# 4x oversampled, then downsampled — the dots are small enough at 16pt that
# aliasing on their edges is the difference between a mark and a smudge.
SUPERSAMPLE = 4


def draw_mark() -> Image.Image:
    canvas = CANVAS * SUPERSAMPLE
    image = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    # DotMatrix.rect: step = size / 6, radius = step * (0.34 lit / 0.24 dim),
    # x = step * (0.5 + col) - radius.
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

    return image.resize((CANVAS, CANVAS), Image.LANCZOS)


def icon_document() -> dict:
    ground = ",".join(f"{channel / 255:.5f}" for channel in GROUND[:3]) + ",1.00000"
    return {
        "fill": {"solid": f"extended-srgb:{ground}"},
        "groups": [{"layers": [{"image-name": "mark.png", "name": "Mark"}]}],
        "supported-platforms": {"circles": ["watchOS"], "squares": ["iOS", "macOS"]},
    }


def main() -> None:
    root = pathlib.Path(__file__).resolve().parent.parent
    out = root / "Utt/Resources/AppIcon.icon"
    (out / "Assets").mkdir(parents=True, exist_ok=True)

    draw_mark().save(out / "Assets/mark.png")
    (out / "icon.json").write_text(json.dumps(icon_document(), indent=2) + "\n")

    print(f"→ {out.relative_to(root)}")


if __name__ == "__main__":
    main()
