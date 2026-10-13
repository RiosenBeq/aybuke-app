#!/usr/bin/env python3
"""Generate App Store screenshots and social images from simulator captures.

    python3 scripts/marketing-images.py <captures-dir>

<captures-dir> holds full-resolution simulator PNGs named after the app's
screenshot scenes (home.png, result.png, share.png, …; see
ios/App/App/ScreenshotScenes.swift and .github/workflows/screenshots.yml).

Writes:
  docs/marketing/app-store/{en,tr}/NN-<scene>.jpg   1290×2796 (6.9-inch iPhone)
  docs/marketing/social/post-launch.png              1080×1350 feed post
  docs/marketing/social/story-launch.png             1080×1920 Story
  web/assets/og-image.png                            1200×630 link preview
  web/assets/screens/<scene>.jpg                     screens for the landing page

Headlines come from docs/marketing/screenshot-captions.json. Requires Pillow.
Uses the app's bundled display font (Poppins) and macOS's New York Italic for
the accent word, if available.
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONTS = ROOT / "ios" / "App" / "Resources" / "Fonts"
CAPTIONS = ROOT / "docs" / "marketing" / "screenshot-captions.json"
OUT_STORE = ROOT / "docs" / "marketing" / "app-store"
OUT_SOCIAL = ROOT / "docs" / "marketing" / "social"
OUT_WEB = ROOT / "web" / "assets"
ICON = ROOT / "docs" / "assets" / "brand" / "app-icon-1024.png"
SERIF_ITALIC = Path("/System/Library/Fonts/NewYorkItalic.ttf")

BLUSH = (247, 193, 217)
PETAL = (248, 224, 234)
INK = (18, 18, 18)
INK_SOFT = (74, 67, 70)
WHITE = (255, 255, 255)


def display_font(size: int, heavy: bool = True) -> ImageFont.FreeTypeFont:
    candidates = (
        ["Poppins-ExtraBold.ttf", "Poppins-Bold.ttf"]
        if heavy else ["Poppins-SemiBold.ttf", "Poppins-Medium.ttf"]
    )
    for name in candidates:
        path = FONTS / name
        if path.exists():
            return ImageFont.truetype(str(path), size)
    return ImageFont.load_default()


def accent_font(size: int) -> ImageFont.FreeTypeFont:
    if SERIF_ITALIC.exists():
        return ImageFont.truetype(str(SERIF_ITALIC), size)
    return display_font(size)


def glow(size: tuple[int, int], center: tuple[float, float], radius: float, color: tuple, alpha: float) -> Image.Image:
    layer = Image.new("RGBA", size, color + (0,))
    mask = Image.new("L", size, 0)
    cx, cy = center
    ImageDraw.Draw(mask).ellipse((cx - radius, cy - radius, cx + radius, cy + radius), fill=int(255 * alpha))
    layer.putalpha(mask.filter(ImageFilter.GaussianBlur(radius * 0.5)))
    return layer


def background(size: tuple[int, int], variant: int) -> Image.Image:
    w, h = size
    base = Image.new("RGBA", size, (PETAL if variant % 2 == 0 else BLUSH) + (255,))
    base.alpha_composite(glow(size, (w * 0.15, h * 0.08), w * 0.75, WHITE, 0.75))
    base.alpha_composite(glow(size, (w * 0.95, h * 0.85), w * 0.7, BLUSH if variant % 2 == 0 else PETAL, 0.8))
    return base


def sparkle(draw: ImageDraw.ImageDraw, center: tuple[float, float], radius: float, fill: tuple) -> None:
    cx, cy = center
    points = []
    for index in range(16):
        angle = index * math.pi / 8 - math.pi / 2
        r = radius if index % 4 == 0 else radius * (0.26 if index % 2 == 0 else 0.35)
        points.append((cx + r * math.cos(angle), cy + r * math.sin(angle)))
    draw.polygon(points, fill=fill)


def wrap(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.FreeTypeFont, width: int) -> list[str]:
    lines: list[str] = []
    line = ""
    for word in text.split():
        candidate = f"{line} {word}".strip()
        if draw.textlength(candidate, font=font) <= width or not line:
            line = candidate
        else:
            lines.append(line)
            line = word
    if line:
        lines.append(line)
    return lines


def centered_lines(draw, lines, font, y, width, fill, spacing):
    for line in lines:
        draw.text(((width - draw.textlength(line, font=font)) / 2, y), line, font=font, fill=fill)
        y += font.size + spacing
    return y


def phone(screen: Image.Image, height: int) -> Image.Image:
    """Screenshot inside a slim ink bezel with rounded corners and a shadow."""
    scale = height / screen.height
    sw, sh = round(screen.width * scale), height
    screen = screen.convert("RGB").resize((sw, sh), Image.LANCZOS)
    bezel = round(sw * 0.024)
    w, h = sw + bezel * 2, sh + bezel * 2
    pad = 90
    canvas = Image.new("RGBA", (w + pad * 2, h + pad * 2), (0, 0, 0, 0))
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((pad, pad + 30, pad + w, pad + h + 30), radius=round(w * 0.135), fill=INK + (70,))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(40)))
    ImageDraw.Draw(canvas).rounded_rectangle((pad, pad, pad + w, pad + h), radius=round(w * 0.135), fill=INK + (255,))
    mask = Image.new("L", (sw * 2, sh * 2), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw * 2 - 1, sh * 2 - 1), radius=round(sw * 0.115) * 2, fill=255)
    canvas.paste(screen, (pad + bezel, pad + bezel), mask.resize((sw, sh), Image.LANCZOS))
    return canvas


def store_screenshot(capture: Path, title: str, subtitle: str, index: int) -> Image.Image:
    size = (1290, 2796)
    image = background(size, index)
    draw = ImageDraw.Draw(image)
    title_font = display_font(108)
    subtitle_font = display_font(48, heavy=False)
    y = centered_lines(draw, wrap(draw, title, title_font, 1120), title_font, 200, size[0], INK, 18)
    centered_lines(draw, wrap(draw, subtitle, subtitle_font, 1060), subtitle_font, y + 26, size[0], INK_SOFT, 12)
    sparkle(draw, (1150, 104), 44, WHITE)
    sparkle(draw, (1222, 168), 18, INK)
    sparkle(draw, (120, 130), 24, WHITE)
    device = phone(Image.open(capture), 1930)
    image.alpha_composite(device, ((size[0] - device.width) // 2, size[1] - device.height + 150))
    return image.convert("RGB")


def headline(draw, x, y, plain: str, accent: str, size: int, fill=INK):
    """'Make it ' in the display font followed by an italic serif accent."""
    font = display_font(size)
    serif = accent_font(round(size * 1.12))
    draw.text((x, y), plain, font=font, fill=fill)
    draw.text((x + draw.textlength(plain, font=font), y - round(size * 0.12)), accent, font=serif, fill=fill)


def social_post(captures: Path) -> Image.Image:
    size = (1080, 1350)
    image = background(size, 0)
    draw = ImageDraw.Draw(image)
    plain, accent = "Make it ", "glow."
    font = display_font(112)
    width = draw.textlength(plain, font=font) + draw.textlength(accent, font=accent_font(125))
    headline(draw, (size[0] - width) / 2, 110, plain, accent, 112)
    sub = display_font(40, heavy=False)
    centered_lines(draw, ["AI glow-ups for girls who glow"], sub, 270, size[0], INK_SOFT, 0)
    device = phone(Image.open(captures / "home.png"), 880)
    image.alpha_composite(device, ((size[0] - device.width) // 2, 330))
    pill = "Coming soon to the App Store"
    pill_font = display_font(34, heavy=False)
    pw = draw.textlength(pill, font=pill_font) + 70
    draw.rounded_rectangle(((size[0] - pw) / 2, 1240, (size[0] + pw) / 2, 1310), radius=35, fill=INK)
    draw.text(((size[0] - pw) / 2 + 35, 1255), pill, font=pill_font, fill=BLUSH)
    sparkle(draw, (930, 90), 40, WHITE)
    sparkle(draw, (985, 160), 18, INK)
    return image.convert("RGB")


def social_story(captures: Path) -> Image.Image:
    size = (1080, 1920)
    image = background(size, 1)
    draw = ImageDraw.Draw(image)
    plain, accent = "Say it. ", "See it."
    font = display_font(104)
    width = draw.textlength(plain, font=font) + draw.textlength(accent, font=accent_font(116))
    headline(draw, (size[0] - width) / 2, 290, plain, accent, 104)
    sub = display_font(42, heavy=False)
    centered_lines(draw, ["“Give me pink hair.” Done."], sub, 440, size[0], INK_SOFT, 0)
    device = phone(Image.open(captures / "result.png"), 1150)
    image.alpha_composite(device, ((size[0] - device.width) // 2, 520))
    cta_font = display_font(40, heavy=False)
    cta = "Glowlit · AI photo editor"
    cw = draw.textlength(cta, font=cta_font) + 80
    draw.rounded_rectangle(((size[0] - cw) / 2, 1690, (size[0] + cw) / 2, 1770), radius=40, fill=INK)
    draw.text(((size[0] - cw) / 2 + 40, 1707), cta, font=cta_font, fill=BLUSH)
    sparkle(draw, (900, 250), 44, WHITE)
    sparkle(draw, (170, 1600), 30, WHITE)
    return image.convert("RGB")


def og_image(captures: Path) -> Image.Image:
    size = (1200, 630)
    image = background(size, 0)
    draw = ImageDraw.Draw(image)
    icon = Image.open(ICON).convert("RGB").resize((150, 150), Image.LANCZOS)
    mask = Image.new("L", (600, 600), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, 599, 599), radius=135, fill=255)
    image.paste(icon, (80, 90), mask.resize((150, 150), Image.LANCZOS))
    draw.text((80, 270), "Glowlit", font=display_font(110), fill=INK)
    headline(draw, 84, 410, "Make it ", "glow.", 64)
    draw.text((84, 510), "AI glow-ups, trends & dreamy art", font=display_font(34, heavy=False), fill=INK_SOFT)
    device = phone(Image.open(captures / "home.png"), 560)
    image.alpha_composite(device, (size[0] - device.width - 30, 40))
    sparkle(draw, (700, 110), 34, WHITE)
    return image.convert("RGB")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    captures = Path(sys.argv[1])
    captions = json.loads(CAPTIONS.read_text(encoding="utf-8"))
    for lang, items in captions.items():
        folder = OUT_STORE / lang
        folder.mkdir(parents=True, exist_ok=True)
        for index, item in enumerate(items, start=1):
            capture = captures / f"{item['scene']}.png"
            if not capture.exists():
                print(f"skip {lang}/{item['scene']}: {capture} missing")
                continue
            store_screenshot(capture, item["title"], item["subtitle"], index).save(
                folder / f"{index:02d}-{item['scene']}.jpg", quality=92, subsampling=0
            )
    OUT_SOCIAL.mkdir(parents=True, exist_ok=True)
    OUT_WEB.mkdir(parents=True, exist_ok=True)
    screens = OUT_WEB / "screens"
    screens.mkdir(parents=True, exist_ok=True)
    for scene in ("home", "result", "share", "create", "library", "consent"):
        capture = captures / f"{scene}.png"
        if capture.exists():
            shot = Image.open(capture).convert("RGB")
            shot.resize((540, round(shot.height * 540 / shot.width)), Image.LANCZOS).save(screens / f"{scene}.jpg", quality=86)
    social_post(captures).save(OUT_SOCIAL / "post-launch.png")
    social_story(captures).save(OUT_SOCIAL / "story-launch.png")
    og_image(captures).save(OUT_WEB / "og-image.png")
    print("Wrote App Store screenshots, social images and the link-preview image.")


if __name__ == "__main__":
    main()
