#!/usr/bin/env python3
"""Render Glowlit's app icons and brand board in the "Blush" palette.

    python3 scripts/render-brand-assets.py

Writes:
  ios/App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon{,-Dark,-Tinted}.png
  docs/assets/brand/app-icon-1024.png
  docs/assets/brand/brand-board.png

The icon follows docs/assets/brand/app-icon.svg ("Sunrise Split": a disc that
is half ink (before) and half white (after), split by the compare handle, on a
blush tile, plus a sparkle). Shapes are drawn at 4x and downsampled for clean
anti-aliasing. Requires Pillow; the brand board uses macOS's New York Italic.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONTS = ROOT / "ios" / "App" / "Resources" / "Fonts"
ICONSET = ROOT / "ios" / "App" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
BRAND = ROOT / "docs" / "assets" / "brand"
SERIF_ITALIC = Path("/System/Library/Fonts/NewYorkItalic.ttf")

BLUSH = (247, 193, 217)
PETAL = (248, 224, 234)
INK = (18, 18, 18)
CHARCOAL = (36, 39, 42)
PAPER = (248, 248, 246)
WHITE = (255, 255, 255)

SCALE = 4
SIZE = 1024


def radial(size: int, center: tuple[float, float], radius: float, color: tuple, alpha: float) -> Image.Image:
    """Soft radial glow layer (RGBA)."""
    layer = Image.new("RGBA", (size, size), color + (0,))
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    cx, cy = center
    draw.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), fill=int(255 * alpha))
    mask = mask.filter(ImageFilter.GaussianBlur(radius * 0.45))
    layer.putalpha(mask)
    return layer


def sparkle(draw: ImageDraw.ImageDraw, center: tuple[float, float], radius: float, fill: tuple) -> None:
    """Four-point star with slightly concave sides."""
    cx, cy = center
    inner = radius * 0.26
    points = []
    for index in range(16):
        angle = index * 3.14159265 / 8 - 3.14159265 / 2
        if index % 4 == 0:
            r = radius
        elif index % 2 == 0:
            r = inner
        else:
            r = inner * 1.35
        from math import cos, sin
        points.append((cx + r * cos(angle), cy + r * sin(angle)))
    draw.polygon(points, fill=fill)


def icon(variant: str = "default") -> Image.Image:
    s = SIZE * SCALE
    tile, glow_a, glow_b = {
        "default": (BLUSH, WHITE, PETAL),
        "dark": (INK, BLUSH, CHARCOAL),
        "tinted": ((0, 0, 0), (60, 60, 60), (30, 30, 30)),
    }[variant]
    before, after, handle, chevron, star = {
        "default": (INK, WHITE, INK, BLUSH, WHITE),
        "dark": ((46, 49, 52), BLUSH, BLUSH, INK, BLUSH),
        "tinted": ((90, 90, 90), WHITE, WHITE, (0, 0, 0), WHITE),
    }[variant]

    image = Image.new("RGBA", (s, s), tile + (255,))
    glow_alpha = {"default": (0.55, 0.7), "dark": (0.16, 0.6), "tinted": (0.25, 0.3)}[variant]
    image.alpha_composite(radial(s, (0.24 * s, 0.18 * s), 0.62 * s, glow_a, glow_alpha[0]))
    image.alpha_composite(radial(s, (0.86 * s, 0.9 * s), 0.55 * s, glow_b, glow_alpha[1]))
    draw = ImageDraw.Draw(image)

    c = s / 2
    r = 0.293 * s  # 300 px at 1024
    disc = Image.new("L", (s, s), 0)
    ImageDraw.Draw(disc).ellipse((c - r, c - r, c + r, c + r), fill=255)
    halves = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    halves_draw = ImageDraw.Draw(halves)
    halves_draw.rectangle((0, 0, c, s), fill=before + (255,))
    halves_draw.rectangle((c, 0, s, s), fill=after + (255,))
    image.paste(halves, (0, 0), disc)

    bar = 0.0254 * s
    draw.rounded_rectangle((c - bar / 2, 0.146 * s, c + bar / 2, 0.854 * s), radius=bar / 2, fill=handle)
    knob = 0.068 * s
    draw.ellipse((c - knob, c - knob, c + knob, c + knob), fill=handle)
    width = int(0.0137 * s)
    for direction in (-1, 1):
        x0 = c + direction * 0.0234 * s
        x1 = c + direction * 0.0449 * s
        draw.line([(x0, c - 0.0234 * s), (x1, c), (x0, c + 0.0234 * s)], fill=chevron, width=width, joint="curve")
        for point in [(x0, c - 0.0234 * s), (x1, c), (x0, c + 0.0234 * s)]:
            draw.ellipse((point[0] - width / 2, point[1] - width / 2, point[0] + width / 2, point[1] + width / 2), fill=chevron)

    sparkle(draw, (0.775 * s, 0.215 * s), 0.085 * s, star)
    sparkle(draw, (0.86 * s, 0.33 * s), 0.038 * s, star)

    out = image.resize((SIZE, SIZE), Image.LANCZOS)
    return out.convert("RGB")


def font(cut: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONTS / f"BricolageGrotesque-{cut}.ttf"), size)


def serif(size: int) -> ImageFont.FreeTypeFont:
    if SERIF_ITALIC.exists():
        return ImageFont.truetype(str(SERIF_ITALIC), size)
    return font("TextSemiBold", size)


def brand_board(app_icon: Image.Image) -> Image.Image:
    w, h = 1600, 900
    board = Image.new("RGBA", (w, h), PETAL + (255,))
    board.alpha_composite(radial(w if w > h else h, (260, 200), 520, WHITE, 0.6).crop((0, 0, w, h)))
    board.alpha_composite(radial(w if w > h else h, (1450, 820), 520, BLUSH, 0.8).crop((0, 0, w, h)))
    draw = ImageDraw.Draw(board)

    # Icon with an iOS-like squircle mask and a soft shadow.
    side = 360
    ix, iy = 140, 170
    mask = Image.new("L", (side * 4, side * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, side * 4 - 1, side * 4 - 1), radius=int(side * 4 * 0.225), fill=255)
    mask = mask.resize((side, side), Image.LANCZOS)
    shadow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((ix, iy + 24, ix + side, iy + side + 24), radius=int(side * 0.225), fill=INK + (60,))
    board.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(28)))
    board.paste(app_icon.resize((side, side), Image.LANCZOS), (ix, iy), mask)

    x = 600
    draw.text((x, 150), "Glowlit", font=font("DisplayExtraBold", 150), fill=INK)
    make = font("DisplayBold", 64)
    draw.text((x + 4, 335), "Make it ", font=make, fill=INK)
    offset = draw.textlength("Make it ", font=make)
    draw.text((x + 4 + offset, 322), "glow.", font=serif(76), fill=INK)
    draw.text((x + 6, 440), "AI photo editor & generator — made for girls who glow.", font=font("TextSemiBold", 30), fill=(92, 84, 87))

    swatches = [("Blush", BLUSH, "#F7C1D9"), ("Petal", PETAL, "#F8E0EA"), ("Ink", INK, "#121212"),
                ("Charcoal", CHARCOAL, "#24272A"), ("Paper", PAPER, "#F8F8F6"), ("White", WHITE, "#FFFFFF")]
    sx, sy, sw = 140, 640, 205
    label_font = font("TextSemiBold", 26)
    hex_font = font("TextSemiBold", 22)
    for index, (name, color, hex_value) in enumerate(swatches):
        left = sx + index * (sw + 18)
        draw.rounded_rectangle((left, sy, left + sw, sy + 120), radius=26, fill=color, outline=(226, 196, 208), width=2)
        draw.text((left + 4, sy + 136), name, font=label_font, fill=INK)
        draw.text((left + 4, sy + 170), hex_value, font=hex_font, fill=(110, 100, 104))

    sparkle(draw, (1480, 120), 46, WHITE)
    sparkle(draw, (1530, 205), 22, INK)
    return board.convert("RGB")


def main() -> None:
    default = icon("default")
    default.save(ICONSET / "AppIcon.png")
    icon("dark").save(ICONSET / "AppIcon-Dark.png")
    icon("tinted").convert("L").save(ICONSET / "AppIcon-Tinted.png")
    default.save(BRAND / "app-icon-1024.png")
    brand_board(default).save(BRAND / "brand-board.png")
    print("Rendered app icons and brand board.")


if __name__ == "__main__":
    main()
