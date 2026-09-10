#!/usr/bin/env python3
"""Render iPhone wallpapers from the same mark the app draws.

Four designs on one grid, the same one `DotMatrix.rect` computes: the dots sit
`step * (0.5 + col)` apart, lit ones at radius `step * 0.34` and dim ones at
`step * 0.24`. `make-app-icon.py` draws the mark that way; so does this.

A Lock Screen is mostly background. The clock owns the top third and the controls
own the bottom third, so the ground darkens towards both edges and everything
worth looking at lives in the band between them.

    field   a full-bleed dot field, one dot lit
    mark    `DotMatrix.patterns[0]` — the 'u' — the way the app icon sits
    meter   the equalizer bars in the readout colours
    bloom   one lit core on near-black, the recording overlay as a wall

Run `just wallpapers`.
"""

import argparse
import pathlib

from PIL import Image, ImageChops, ImageDraw, ImageFilter

# Straight from Utt/Design/Palette.swift.
GROUND = (48, 48, 39)  # lcdGround
DEEP = (24, 24, 20)  # lcdBackground
FOOT = (30, 30, 25)  # lcdGround dropped back towards lcdBackground
ACCENT = (212, 80, 30)
GREEN = (154, 209, 122)  # lcdGreen
YELLOW = (224, 160, 34)  # lcdYellow
RED = (255, 90, 46)  # lcdRed
DIM = (255, 255, 255)  # dim dots are the ground lifted, not a colour

# DotMatrix.patterns: the 'u', the centred square, and the 1-3-2-2-3-1 equalizer.
MARK = {7, 8, 13, 14, 21, 22, 27, 28}
CORE = {14, 15, 20, 21}
EQ = {19, 22, 25, 26, 27, 28, 30, 31, 32, 33, 34, 35}

# Native pixels: 17 Pro Max, 17 Pro, 15/16 Pro.
SIZES = [(1320, 2868), (1206, 2622), (1179, 2556)]

# Dots here are 20-60px across, so 2x is enough to keep their edges clean — the
# icon needs 4x only because it is read at 16pt.
SUPERSAMPLE = 2

# Dots across the full width of a field. Coarse enough to read as a matrix.
FIELD_COLUMNS = 30

OUT = pathlib.Path.home() / "Library/Mobile Documents/com~apple~CloudDocs/utt wallpapers"


def smootherstep(t: float) -> float:
    t = min(max(t, 0.0), 1.0)
    return t * t * t * (t * (t * 6 - 15) + 10)


def ramp(t: float, start: float, end: float) -> float:
    return smootherstep((t - start) / (end - start))


def band(t: float) -> float:
    """1 across the readable middle, falling to nothing under the clock."""
    return ramp(t, 0.10, 0.46) * (1 - 0.85 * ramp(t, 0.48, 1.05))


def blend(a: tuple, b: tuple, t: float) -> tuple:
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def draw_ground(width: int, height: int, top: tuple, mid: tuple, foot: tuple) -> Image.Image:
    """A one-pixel column stretched across, so the gradient costs nothing to draw."""
    column = Image.new("RGB", (1, height))
    pixels = column.load()
    for y in range(height):
        t = y / (height - 1)
        pixels[0, y] = (
            blend(top, mid, ramp(t, 0.0, 0.52)) if t < 0.52 else blend(mid, foot, ramp(t, 0.52, 1.0))
        )
    return column.resize((width, height), Image.BILINEAR)


def dot(layer: Image.Image, cx: float, cy: float, radius: float, colour: tuple) -> None:
    ImageDraw.Draw(layer).ellipse(
        [cx - radius, cy - radius, cx + radius, cy + radius], fill=colour
    )


def draw_field(
    dots: Image.Image, lit: Image.Image, width: int, height: int, gain: float, accent: tuple | None
) -> None:
    step = width / FIELD_COLUMNS
    for row in range(int(height / step) + 1):
        cy = step * (0.5 + row)
        alpha = round(255 * gain * (0.04 + 0.16 * band(cy / height)))
        for col in range(FIELD_COLUMNS):
            cx = step * (0.5 + col)
            if accent == (col, row):
                dot(dots, cx, cy, step * 0.34, ACCENT + (255,))
                dot(lit, cx, cy, step * 0.34, ACCENT)
            elif alpha > 0:
                dot(dots, cx, cy, step * 0.24, DIM + (alpha,))


def draw_board(
    dots: Image.Image,
    lit: Image.Image,
    pattern: set,
    colour,
    step: float,
    origin: tuple,
) -> None:
    """One 6x6 board — DotMatrix.rect's geometry, offset to where it sits."""
    for index in range(36):
        on = index in pattern
        radius = step * (0.34 if on else 0.24)
        cx = origin[0] + step * (0.5 + index % 6)
        cy = origin[1] + step * (0.5 + index // 6)
        if on:
            tint = colour(index) if callable(colour) else colour
            dot(dots, cx, cy, radius, tint + (255,))
            dot(lit, cx, cy, radius, tint)
        else:
            dot(dots, cx, cy, radius, DIM + (34,))


def add_bloom(base: Image.Image, lit: Image.Image, radius: float, strength: float) -> Image.Image:
    """Two blurs added on top, the way RecordingOverlay stacks wide over tight.

    Blurred at a quarter scale: the result is low-frequency by definition, and a
    200px-radius Gaussian over 15 megapixels is not.
    """
    if strength <= 0:
        return base
    small = (lit.width // 4, lit.height // 4)
    seed = lit.resize(small, Image.BILINEAR)
    glow = ImageChops.add(
        seed.filter(ImageFilter.GaussianBlur(radius / 4)).point(lambda v: int(v * strength * 0.75)),
        seed.filter(ImageFilter.GaussianBlur(radius / 14)).point(lambda v: int(v * strength * 0.5)),
    )
    return ImageChops.add(base, glow.resize(lit.size, Image.BICUBIC))


def eq_colour(index: int) -> tuple:
    """A bar runs hot at its tip. The lower rows are cooled back towards the
    ground, or six full-strength lcdGreen dots own the whole screen."""
    return {3: RED, 4: blend(YELLOW, GROUND, 0.28)}.get(index // 6, blend(GREEN, GROUND, 0.5))


DESIGNS = {
    # (top, mid, foot), field gain, field accent cell, board, bloom strength
    "field": dict(ground=(DEEP, GROUND, FOOT), gain=1.0, accent=(11, 27), board=None, bloom=0.55),
    # A board carries its own dim grid, so a field behind one reads as two grids
    # at odds — the mark sits on the bare ground the way the app icon does.
    "mark": dict(
        ground=(DEEP, GROUND, FOOT),
        gain=0.0,
        accent=None,
        board=(MARK, ACCENT, 0.52, 0.44),
        bloom=0.5,
    ),
    "meter": dict(
        ground=(DEEP, GROUND, FOOT),
        gain=0.0,
        accent=None,
        board=(EQ, eq_colour, 0.56, 0.46),
        bloom=0.3,
    ),
    "bloom": dict(
        ground=(DEEP, DEEP, DEEP),
        gain=0.0,
        accent=None,
        board=(CORE, ACCENT, 0.40, 0.44),
        bloom=3.0,
    ),
}


def render(name: str, size: tuple) -> Image.Image:
    width, height = (side * SUPERSAMPLE for side in size)
    spec = DESIGNS[name]

    base = draw_ground(width, height, *spec["ground"])
    dots = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    lit = Image.new("RGB", (width, height), (0, 0, 0))

    if spec["gain"] or spec["accent"]:
        draw_field(dots, lit, width, height, spec["gain"], spec["accent"])

    radius = width / FIELD_COLUMNS
    if spec["board"]:
        pattern, colour, fraction, centre = spec["board"]
        step = width * fraction / 6
        origin = ((width - width * fraction) / 2, height * centre - step * 3)
        draw_board(dots, lit, pattern, colour, step, origin)
        radius = step

    base = Image.alpha_composite(base.convert("RGBA"), dots).convert("RGB")
    return add_bloom(base, lit, radius * 1.1, spec["bloom"]).resize(size, Image.LANCZOS)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=pathlib.Path, default=OUT)
    out = parser.parse_args().out
    out.mkdir(parents=True, exist_ok=True)

    for name in DESIGNS:
        for size in SIZES:
            path = out / f"utt-{name}-{size[0]}x{size[1]}.png"
            render(name, size).save(path)
            print(f"→ {path.name}")
    print(f"   in {out}")


if __name__ == "__main__":
    main()
