#!/usr/bin/env python3
"""Build the README screenshot gallery from simulator captures.

The Screenshots workflow (.github/workflows/screenshots.yml) publishes
full-resolution PNGs to the `screenshots` branch. To refresh the gallery:

    mkdir -p /tmp/glowlit-shots
    git fetch origin screenshots
    git archive origin/screenshots | tar -x -C /tmp/glowlit-shots
    python3 scripts/screenshot-gallery.py /tmp/glowlit-shots

This writes one downscaled JPEG per screen plus overview.jpg to
docs/assets/screenshots/. Requires Pillow (`pip install pillow`).
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONTS = ROOT / "ios" / "App" / "Resources" / "Fonts"
OUTPUT = ROOT / "docs" / "assets" / "screenshots"

# Scenes in the order the workflow captures them, with their gallery captions.
SCENES = [
    ("onboarding", "Onboarding"),
    ("home", "Explore"),
    ("create", "Create from text"),
    ("results", "Results"),
    ("edit", "Edit hub"),
    ("editor", "Magic Edit"),
    ("result", "Before / after"),
    ("library", "My Works"),
    ("paywall", "Paywall"),
    ("consent", "AI consent"),
    ("settings", "Settings"),
    ("share", "Share"),
    ("legal", "Privacy Policy"),
]

# "Blush" tokens (ios/App/DesignSystem/Palette.swift).
BACKGROUND = (248, 224, 234)
TEXT_PRIMARY = (18, 18, 18)
TEXT_SECONDARY = (92, 84, 87)
STROKE = (226, 196, 208)
BEZEL = (18, 18, 18)
GLOW = (255, 255, 255)
GRADIENT = ((18, 18, 18), (36, 39, 42))

SCREEN_WIDTH = 600  # per-screen JPEGs shown in the README
TILE_WIDTH = 300  # screen width inside overview.jpg
PER_ROW = 6
MARGIN = 90
GAP = 44


def load_font(cut: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONTS / f"Poppins-{cut}.ttf"), size)


def rounded_mask(size: tuple[int, int], radius: int, scale: int = 4) -> Image.Image:
    """Anti-aliased rounded-rectangle mask."""
    width, height = size
    large = Image.new("L", (width * scale, height * scale), 0)
    ImageDraw.Draw(large).rounded_rectangle(
        (0, 0, width * scale - 1, height * scale - 1), radius * scale, fill=255
    )
    return large.resize(size, Image.LANCZOS)


def horizontal_gradient(size: tuple[int, int], start: tuple, end: tuple) -> Image.Image:
    width, height = size
    row = Image.new("RGB", (width, 1))
    for x in range(width):
        t = x / max(width - 1, 1)
        row.putpixel((x, 0), tuple(round(a + (b - a) * t) for a, b in zip(start, end)))
    return row.resize(size)


def scaled(screen: Image.Image, width: int) -> Image.Image:
    return screen.resize((width, round(screen.height * width / screen.width)), Image.LANCZOS)


def device_tile(screen: Image.Image) -> Image.Image:
    """The screen with rounded display corners inside a thin bezel."""
    display = scaled(screen, TILE_WIDTH)
    radius = round(TILE_WIDTH * 0.14)
    bezel = 6
    outer = (display.width + 2 * bezel, display.height + 2 * bezel)
    tile = Image.new("RGBA", outer, (0, 0, 0, 0))
    tile.paste(STROKE + (255,), (0, 0, *outer), rounded_mask(outer, radius + bezel))
    inner = (outer[0] - 4, outer[1] - 4)
    tile.paste(BEZEL + (255,), (2, 2, 2 + inner[0], 2 + inner[1]), rounded_mask(inner, radius + bezel - 2))
    tile.paste(display, (bezel, bezel), rounded_mask(display.size, radius))
    return tile


def centered_text(canvas: Image.Image, y: int, text: str, font: ImageFont.FreeTypeFont,
                  fill: tuple | None = None, center_x: float | None = None) -> None:
    """Draws `text` centred on `center_x`; a gradient fill when `fill` is None."""
    left, _, right, bottom = font.getbbox(text)
    x = round((canvas.width / 2 if center_x is None else center_x) - (left + right) / 2)
    if fill is not None:
        ImageDraw.Draw(canvas).text((x, y), text, font=font, fill=fill)
        return
    mask = Image.new("L", (right, bottom), 0)
    ImageDraw.Draw(mask).text((0, 0), text, font=font, fill=255)
    canvas.paste(horizontal_gradient(mask.size, *GRADIENT), (x, y), mask)


def overview(screens: list[tuple[Image.Image, str]]) -> Image.Image:
    tiles = [(device_tile(screen), caption) for screen, caption in screens]
    tile_width, tile_height = tiles[0][0].size
    rows = [tiles[i:i + PER_ROW] for i in range(0, len(tiles), PER_ROW)]

    title, tagline, subtitle = load_font("ExtraBold", 104), load_font("Bold", 46), load_font("SemiBold", 30)
    caption_font = load_font("SemiBold", 28)
    header_height, caption_height, row_gap = 330, 64, 40

    width = 2 * MARGIN + PER_ROW * tile_width + (PER_ROW - 1) * GAP
    height = header_height + len(rows) * (tile_height + caption_height) + (len(rows) - 1) * row_gap + MARGIN
    canvas = Image.new("RGB", (width, height), BACKGROUND)

    # Soft white glow behind the header.
    glow = Image.new("L", (width, height), 0)
    ImageDraw.Draw(glow).ellipse((width * 0.22, -height * 0.32, width * 0.78, height * 0.2), fill=170)
    canvas.paste(GLOW, (0, 0, width, height), glow.filter(ImageFilter.GaussianBlur(width * 0.07)))

    centered_text(canvas, 64, "Glowlit", title, TEXT_PRIMARY)
    centered_text(canvas, 188, "Make it glow", tagline)
    centered_text(canvas, 256, "AI photo editor made for girls who glow  ·  iOS Simulator, demo mode", subtitle, TEXT_SECONDARY)

    y = header_height
    for row in rows:
        x = (width - (len(row) * tile_width + (len(row) - 1) * GAP)) // 2
        for tile, caption in row:
            canvas.paste(tile, (x, y), tile)
            centered_text(canvas, y + tile_height + 16, caption, caption_font, TEXT_PRIMARY, x + tile_width / 2)
            x += tile_width + GAP
        y += tile_height + caption_height + row_gap
    return canvas


def save_jpeg(image: Image.Image, path: Path, quality: int) -> None:
    image.save(path, "JPEG", quality=quality, optimize=True, progressive=True, subsampling=0)


def main() -> int:
    parser = argparse.ArgumentParser(description="Build the README screenshot gallery.")
    parser.add_argument("source", type=Path, help="directory containing <scene>.png captures")
    args = parser.parse_args()

    missing = [name for name, _ in SCENES if not (args.source / f"{name}.png").is_file()]
    if missing:
        print(f"Missing captures in {args.source}: {', '.join(missing)}", file=sys.stderr)
        return 1

    OUTPUT.mkdir(parents=True, exist_ok=True)
    screens = []
    for name, caption in SCENES:
        with Image.open(args.source / f"{name}.png") as image:
            screen = image.convert("RGB")
        save_jpeg(scaled(screen, SCREEN_WIDTH), OUTPUT / f"{name}.jpg", quality=85)
        screens.append((screen, caption))
    save_jpeg(overview(screens), OUTPUT / "overview.jpg", quality=90)
    print(f"Wrote {len(screens) + 1} images to {OUTPUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
