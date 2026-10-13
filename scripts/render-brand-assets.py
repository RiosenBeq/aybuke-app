#!/usr/bin/env python3
"""Render Glowlit's app icons and brand board in the "Blush" palette.

    python3 scripts/render-brand-assets.py

Writes:
  ios/App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon{,-Dark,-Tinted}.png
  docs/assets/brand/app-icon-1024.png
  docs/assets/brand/brand-board.png

The icon is "Glow Print" (docs/assets/brand/app-icon.svg): a sharp-cornered
white print, tilted on a blush tile, showing a white sparkle glowing pink on
ink, with a small heart on the print's chin. Shapes are drawn at 4x and
downsampled for clean anti-aliasing. Requires Pillow; the brand board uses macOS's New York Italic.
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
    """ "Glow Print": a sharp-cornered white print, tilted like a photo on a
    mood board, showing a sparkle glowing pink on ink. Sharp print = the
    app's photo cards; sparkle = "make it glow"; blush tile = the palette."""
    s = SIZE * SCALE
    tile, glow_a, glow_b, frame, photo, halo, star, small = {
        "default": (BLUSH, WHITE, PETAL, WHITE, INK, BLUSH, WHITE, BLUSH),
        "dark": (INK, BLUSH, CHARCOAL, BLUSH, INK, BLUSH, WHITE, BLUSH),
        "tinted": ((0, 0, 0), (70, 70, 70), (30, 30, 30), WHITE, (0, 0, 0), (120, 120, 120), WHITE, (200, 200, 200)),
    }[variant]
    glow_alpha = {"default": (0.6, 0.75), "dark": (0.18, 0.55), "tinted": (0.25, 0.3)}[variant]

    image = Image.new("RGBA", (s, s), tile + (255,))
    image.alpha_composite(radial(s, (0.22 * s, 0.16 * s), 0.62 * s, glow_a, glow_alpha[0]))
    image.alpha_composite(radial(s, (0.86 * s, 0.9 * s), 0.55 * s, glow_b, glow_alpha[1]))

    # The print, drawn upright on its own layer, then tilted.
    print_w, print_h = 0.54 * s, 0.64 * s
    border, chin = 0.045 * s, 0.13 * s
    layer = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    x0, y0 = (s - print_w) / 2 - 0.02 * s, (s - print_h) / 2 + 0.01 * s
    layer_draw = ImageDraw.Draw(layer)
    layer_draw.rectangle((x0, y0, x0 + print_w, y0 + print_h), fill=frame + (255,))
    px0, py0 = x0 + border, y0 + border
    px1, py1 = x0 + print_w - border, y0 + print_h - chin
    layer_draw.rectangle((px0, py0, px1, py1), fill=photo + (255,))
    # Pink glow inside the photo, clipped to it.
    glow = radial(s, ((px0 + px1) / 2, (py0 + py1) / 2), 0.21 * s, halo, 0.9 if variant != "tinted" else 0.7)
    clip = Image.new("L", (s, s), 0)
    ImageDraw.Draw(clip).rectangle((px0, py0, px1, py1), fill=255)
    glow.putalpha(Image.composite(glow.getchannel("A"), Image.new("L", (s, s), 0), clip))
    layer.alpha_composite(glow)
    layer_draw = ImageDraw.Draw(layer)
    cx, cy = (px0 + px1) / 2, (py0 + py1) / 2
    sparkle(layer_draw, (cx, cy), 0.13 * s, star + (255,))
    sparkle(layer_draw, (cx + 0.105 * s, cy - 0.1 * s), 0.035 * s, small + (255,))
    # A small heart on the print's chin, like a note written on a photo.
    heart_c = ((px0 + px1) / 2, y0 + print_h - chin / 2)
    hr = 0.024 * s
    hx, hy = heart_c
    heart_color = {"default": BLUSH, "dark": INK, "tinted": (110, 110, 110)}[variant] + (255,)
    hy -= hr * 0.55
    for side in (-1, 1):
        cx_heart = hx + side * hr
        layer_draw.ellipse((cx_heart - hr, hy - hr * 1.2, cx_heart + hr, hy + hr * 0.8), fill=heart_color)
    layer_draw.polygon([(hx - hr * 1.93, hy + hr * 0.05), (hx + hr * 1.93, hy + hr * 0.05), (hx, hy + hr * 2.05)], fill=heart_color)

    shadow = layer.getchannel("A").filter(ImageFilter.GaussianBlur(0.035 * s))
    shadow_layer = Image.new("RGBA", (s, s), INK + (0,))
    shadow_layer.putalpha(shadow.point(lambda value: int(value * (0.28 if variant == "default" else 0.5))))
    tilt = -7
    shadow_layer = shadow_layer.rotate(tilt, resample=Image.BICUBIC, center=(s / 2, s / 2), translate=(0, 0.025 * s))
    image.alpha_composite(shadow_layer)
    image.alpha_composite(layer.rotate(tilt, resample=Image.BICUBIC, center=(s / 2, s / 2)))

    # Sparkles on the tile, as in the app's hero card.
    draw = ImageDraw.Draw(image)
    corner = WHITE if variant != "dark" else BLUSH
    sparkle(draw, (0.845 * s, 0.155 * s), 0.065 * s, corner)
    sparkle(draw, (0.91 * s, 0.255 * s), 0.028 * s, corner)

    out = image.resize((SIZE, SIZE), Image.LANCZOS)
    return out.convert("RGB")


def font(cut: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONTS / f"Poppins-{cut}.ttf"), size)


def serif(size: int) -> ImageFont.FreeTypeFont:
    if SERIF_ITALIC.exists():
        return ImageFont.truetype(str(SERIF_ITALIC), size)
    return font("SemiBold", size)


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
    draw.text((x, 150), "Glowlit", font=font("ExtraBold", 150), fill=INK)
    make = font("Bold", 64)
    draw.text((x + 4, 335), "Make it ", font=make, fill=INK)
    offset = draw.textlength("Make it ", font=make)
    draw.text((x + 4 + offset, 322), "glow.", font=serif(76), fill=INK)
    draw.text((x + 6, 440), "AI photo editor & generator — made for girls who glow.", font=font("SemiBold", 30), fill=(92, 84, 87))

    swatches = [("Blush", BLUSH, "#F7C1D9"), ("Petal", PETAL, "#F8E0EA"), ("Ink", INK, "#121212"),
                ("Charcoal", CHARCOAL, "#24272A"), ("Paper", PAPER, "#F8F8F6"), ("White", WHITE, "#FFFFFF")]
    sx, sy, sw = 140, 640, 205
    label_font = font("SemiBold", 26)
    hex_font = font("SemiBold", 22)
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
