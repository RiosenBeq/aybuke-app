#!/usr/bin/env python3
"""Render Glowlit's app icons and brand board.

    python3 scripts/render-brand-assets.py

Writes:
  ios/App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon{,-Dark,-Tinted}.png
  ios/App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-Mac-{16…1024}.png (Mac Catalyst)
  ios/App/Resources/Assets.xcassets/BrandIcon.imageset/BrandIcon.png (in-app use: invite card)
  web/assets/icon.png
  docs/assets/brand/app-icon-1024.png
  docs/assets/brand/brand-board.png

The icon is "Glow Print" in its colorful "Aura" edition: a sharp-cornered white
print, tilted on an aura tile (mint, lilac, pink, peach and a butter glow),
showing a white sparkle glowing pink on plum, with a pink heart on the print's
chin. Shapes are drawn at 4x and downsampled for clean anti-aliasing.
Requires Pillow; the brand board uses macOS's New York Italic.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONTS = ROOT / "ios" / "App" / "Resources" / "Fonts"
ICONSET = ROOT / "ios" / "App" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
BRAND = ROOT / "docs" / "assets" / "brand"
BRAND_ICON = ROOT / "ios" / "App" / "Resources" / "Assets.xcassets" / "BrandIcon.imageset"
WEB_ICON = ROOT / "web" / "assets" / "icon.png"
SERIF_ITALIC = Path("/System/Library/Fonts/NewYorkItalic.ttf")

BLUSH = (247, 193, 217)
PETAL = (248, 224, 234)
INK = (18, 18, 18)
CHARCOAL = (36, 39, 42)
PAPER = (248, 248, 246)
WHITE = (255, 255, 255)

# Aura accents: the colorful side of the brand (icon, share cards, template art).
AURA_PINK = (255, 92, 161)
AURA_LILAC = (167, 139, 250)
AURA_PEACH = (255, 170, 120)
AURA_BUTTER = (255, 222, 110)
AURA_MINT = (120, 225, 205)
PLUM = (60, 24, 90)
PLUM_DEEP = (20, 10, 30)

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


def lerp(a: tuple, b: tuple, t: float) -> tuple:
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient(width: int, height: int, stops: list[tuple[float, tuple]], diagonal: bool) -> Image.Image:
    """Smooth gradient through colour stops: diagonal (top-left to bottom-right) or vertical."""
    small = 256
    image = Image.new("RGB", (small, small))
    pixels = image.load()
    for y in range(small):
        for x in range(small):
            t = (x + y) / (2 * (small - 1)) if diagonal else y / (small - 1)
            for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
                if p0 <= t <= p1:
                    pixels[x, y] = lerp(c0, c1, (t - p0) / (p1 - p0))
                    break
    return image.resize((int(width), int(height)), Image.BICUBIC).convert("RGBA")


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
    mood board, showing a sparkle glowing pink on plum. Sharp print = the
    app's photo cards; sparkle = "make it glow"; aura tile = the colors of a glow-up."""
    s = SIZE * SCALE
    frame, halo, star, small = {
        "default": (WHITE, AURA_PINK, WHITE, AURA_BUTTER),
        "dark": ((250, 240, 246), AURA_PINK, WHITE, AURA_BUTTER),
        "tinted": (WHITE, (120, 120, 120), WHITE, (200, 200, 200)),
    }[variant]

    if variant == "default":
        image = gradient(s, s, [(0, AURA_MINT), (0.4, AURA_LILAC), (0.75, AURA_PINK), (1, AURA_PEACH)], diagonal=True)
        image.alpha_composite(radial(s, (0.15 * s, 0.1 * s), 0.55 * s, WHITE, 0.55))
        image.alpha_composite(radial(s, (0.95 * s, 0.95 * s), 0.45 * s, AURA_BUTTER, 0.55))
    elif variant == "dark":
        image = Image.new("RGBA", (s, s), INK + (255,))
        image.alpha_composite(radial(s, (0.12 * s, 0.1 * s), 0.6 * s, AURA_LILAC, 0.35))
        image.alpha_composite(radial(s, (0.92 * s, 0.92 * s), 0.55 * s, AURA_PINK, 0.45))
    else:
        image = Image.new("RGBA", (s, s), (0, 0, 0, 255))
        image.alpha_composite(radial(s, (0.22 * s, 0.16 * s), 0.62 * s, (70, 70, 70), 0.25))

    # The print, drawn upright on its own layer, then tilted.
    print_w, print_h = 0.54 * s, 0.64 * s
    border, chin = 0.045 * s, 0.13 * s
    layer = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    x0, y0 = (s - print_w) / 2 - 0.02 * s, (s - print_h) / 2 + 0.01 * s
    layer_draw = ImageDraw.Draw(layer)
    layer_draw.rectangle((x0, y0, x0 + print_w, y0 + print_h), fill=frame + (255,))
    px0, py0 = x0 + border, y0 + border
    px1, py1 = x0 + print_w - border, y0 + print_h - chin
    if variant == "tinted":
        layer_draw.rectangle((px0, py0, px1, py1), fill=(0, 0, 0, 255))
    else:
        layer.paste(gradient(px1 - px0, py1 - py0, [(0, PLUM), (1, PLUM_DEEP)], diagonal=False), (int(px0), int(py0)))
    # Glows inside the photo, clipped to it: pink around the sparkle, lilac and butter at the edges.
    clip = Image.new("L", (s, s), 0)
    ImageDraw.Draw(clip).rectangle((px0, py0, px1, py1), fill=255)
    cx, cy = (px0 + px1) / 2, (py0 + py1) / 2
    glows = [(halo, 0.21, 0.95 if variant != "tinted" else 0.7, 0, 0)]
    if variant != "tinted":
        glows += [(AURA_LILAC, 0.14, 0.55, -0.06, 0.07), (AURA_BUTTER, 0.1, 0.45, 0.07, 0.09)]
    for color, radius, alpha, dx, dy in glows:
        glow = radial(s, (cx + dx * s, cy + dy * s), radius * s, color, alpha)
        glow.putalpha(Image.composite(glow.getchannel("A"), Image.new("L", (s, s), 0), clip))
        layer.alpha_composite(glow)
    layer_draw = ImageDraw.Draw(layer)
    sparkle(layer_draw, (cx, cy), 0.13 * s, star + (255,))
    sparkle(layer_draw, (cx + 0.105 * s, cy - 0.1 * s), 0.035 * s, small + (255,))
    # A small heart on the print's chin, like a note written on a photo.
    heart_c = ((px0 + px1) / 2, y0 + print_h - chin / 2)
    hr = 0.024 * s
    hx, hy = heart_c
    heart_color = {"default": AURA_PINK, "dark": AURA_PINK, "tinted": (110, 110, 110)}[variant] + (255,)
    hy -= hr * 0.55
    for side in (-1, 1):
        cx_heart = hx + side * hr
        layer_draw.ellipse((cx_heart - hr, hy - hr * 1.2, cx_heart + hr, hy + hr * 0.8), fill=heart_color)
    layer_draw.polygon([(hx - hr * 1.93, hy + hr * 0.05), (hx + hr * 1.93, hy + hr * 0.05), (hx, hy + hr * 2.05)], fill=heart_color)

    shadow = layer.getchannel("A").filter(ImageFilter.GaussianBlur(0.035 * s))
    shadow_layer = Image.new("RGBA", (s, s), (PLUM_DEEP if variant == "default" else INK) + (0,))
    shadow_layer.putalpha(shadow.point(lambda value: int(value * (0.3 if variant == "default" else 0.5))))
    tilt = -7
    shadow_layer = shadow_layer.rotate(tilt, resample=Image.BICUBIC, center=(s / 2, s / 2), translate=(0, 0.025 * s))
    image.alpha_composite(shadow_layer)
    image.alpha_composite(layer.rotate(tilt, resample=Image.BICUBIC, center=(s / 2, s / 2)))

    # Sparkles on the tile, as in the app's hero card.
    draw = ImageDraw.Draw(image)
    corner = WHITE
    sparkle(draw, (0.845 * s, 0.155 * s), 0.065 * s, corner)
    sparkle(draw, (0.91 * s, 0.255 * s), 0.028 * s, corner)

    out = image.resize((SIZE, SIZE), Image.LANCZOS)
    return out.convert("RGB")


MAC_ICON_SIZES = (16, 32, 64, 128, 256, 512, 1024)


def mac_icon(art: Image.Image) -> Image.Image:
    """The icon on Apple's macOS grid for the Mac Catalyst build: a rounded
    tile with a soft shadow on a transparent canvas, as Xcode would generate
    it. iOS masks the square icon itself; macOS shows the file as drawn, and
    the Mac App Store needs every size up to 1024 in the app's .icns."""
    inset, radius = 96, 186
    s = SIZE * SCALE
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (inset * SCALE, inset * SCALE, s - inset * SCALE, s - inset * SCALE), radius=radius * SCALE, fill=255
    )
    mask = mask.resize((SIZE, SIZE), Image.LANCZOS)
    tile = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    tile.paste(art.convert("RGBA").resize((SIZE - 2 * inset, SIZE - 2 * inset), Image.LANCZOS), (inset, inset))
    tile.putalpha(mask)
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    out.paste((0, 0, 0, 255), (0, 20), mask.filter(ImageFilter.GaussianBlur(10)).point(lambda value: int(value * 0.32)))
    out.alpha_composite(tile)
    return out


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
                ("Aura Pink", AURA_PINK, "#FF5CA1"), ("Lilac", AURA_LILAC, "#A78BFA"), ("Peach", AURA_PEACH, "#FFAA78"),
                ("Butter", AURA_BUTTER, "#FFDE6E"), ("Mint", AURA_MINT, "#78E1CD")]
    sx, sy, sw = 140, 640, 150
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
    mac = mac_icon(default)
    for size in MAC_ICON_SIZES:
        mac.resize((size, size), Image.LANCZOS).save(ICONSET / f"AppIcon-Mac-{size}.png")
    default.save(BRAND / "app-icon-1024.png")
    default.resize((512, 512), Image.LANCZOS).save(BRAND_ICON / "BrandIcon.png")
    default.resize((256, 256), Image.LANCZOS).save(WEB_ICON)
    brand_board(default).save(BRAND / "brand-board.png")
    print("Rendered app icons and brand board.")


if __name__ == "__main__":
    main()
