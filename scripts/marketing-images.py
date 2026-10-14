#!/usr/bin/env python3
"""Generate App Store screenshots and social images from simulator captures.

    python3 scripts/marketing-images.py <captures-dir>
    python3 scripts/marketing-images.py <captures-dir> --out <dir> --lang en,ru --only iphone --stand-ins

<captures-dir> holds full-resolution simulator PNGs named after the scenes in
docs/marketing/screenshot-captions.json, captured with -GLScreenshotScene
(ios/App/App/ScreenshotScenes.swift):

  result.png        result                     before/after slider
  makeup.png        editor -GLEditorTool makeup (-GLMakeupPreset <id>)
  home.png          home
  effects.png       effects
  textStickers.png  textStickers
  create.png        create
  share-cover.png   share -GLShareFormat cover (shareCover.png works too)
  collage.png       collage
  consent.png       consent
  paywall.png       paywall
  cutout.png        cutout                     (Mac set)
  hideFaces.png     hideFaces                  (Mac set)

Captures of the app in a given language go in <captures-dir>/<lang>/, iPad
captures in <captures-dir>/ipad/<lang>/ (or ipad/), and Mac window captures
(`screencapture -x -o -l <window id>` of the Mac Catalyst app launched with
-GLWindowSize 1600x1000, so every shot has the same size) in
<captures-dir>/mac/<lang>/ (or mac/). Plain files are the fallback for every
language.

Writes:
  docs/marketing/app-store/<lang>/NN-<scene>.jpg       1290×2796 (6.9-inch iPhone)
  docs/marketing/app-store/<lang>/ipad/NN-<scene>.jpg  2064×2752 (13-inch iPad)
  docs/marketing/app-store/<lang>/mac/NN-<scene>.jpg   2880×1800 (Mac, 16:10)
  docs/marketing/social/post-launch.png                1080×1350 feed post
  docs/marketing/social/story-launch.png               1080×1920 Story
  web/assets/og-image.png                              1200×630 link preview
  web/assets/screens/<scene>.jpg                       screens for the landing page

Options:
  --out DIR       write the same tree under DIR (app-store/, social/, web/) instead
  --lang en,tr    only these languages (default: every language in the captions)
  --only SETS     comma-separated: iphone, ipad, mac, social (default: all)
  --stand-ins     frame the iPhone capture where an iPad or Mac capture is missing,
                  to judge the layout before those captures exist (never upload these)

Captions: per language a list of {scene, title, subtitle}, optionally with a
"chip" (a short callout) and, for the before/after slide, "before" and
"after"; "mac" holds the Mac lists. *Asterisks* mark the accent word, a
no-break space (\\u00a0) keeps words together, and "\\n" marks where a title
breaks when it needs two lines.

The look: Aura gradients that flow from one image into the next, a headline in
Poppins ExtraBold with the accent word in New York Italic (Japanese, Korean and
Chinese have no italics, so their accent keeps the heavy face) filled with a
pink-to-violet gradient, a short subtitle, the capture in a drawn device frame,
and sparkles and die-cut stickers drawn in code (never emoji). Russian uses
SF Pro, as Poppins has no Cyrillic; Japanese, Korean and Chinese use Hiragino
Sans, Apple SD Gothic Neo and Hiragino Sans GB. Requires Pillow and macOS's
system fonts.
"""

from __future__ import annotations

import argparse
import json
import math
import random
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONTS = ROOT / "ios" / "App" / "Resources" / "Fonts"
CAPTIONS = ROOT / "docs" / "marketing" / "screenshot-captions.json"
ICON = ROOT / "docs" / "assets" / "brand" / "app-icon-1024.png"
SYSTEM = Path("/System/Library/Fonts")

# The name the app shows; captions spell it out, the social images use this.
APP_NAME = "Aybuke"
IPHONE, IPAD, MAC = (1290, 2796), (2064, 2752), (2880, 1800)
TITLE_LIMIT, SUBTITLE_LIMIT = 28, 60

# The Blush UI palette and the Aura accents (docs/02-brand-identity.md).
INK = (18, 18, 18)
INK_SOFT = (82, 72, 77)
BLUSH = (247, 193, 217)
WHITE = (255, 255, 255)
PINK = (255, 92, 161)
LILAC = (167, 139, 250)
PEACH = (255, 170, 120)
BUTTER = (255, 222, 110)
MINT = (120, 225, 205)
PLUM = (58, 24, 56)
# The accent word: Aura pink to lilac, deepened to read as large text on the aura.
ACCENT = ((222, 44, 134), (124, 77, 237))


# MARK: - Colour and pixels

def mix(a, b, t: float) -> tuple:
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def color_at(stops, t: float) -> tuple:
    for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
        if t <= p1:
            u = 0 if p1 == p0 else (t - p0) / (p1 - p0)
            return tuple(round(c0[i] + (c1[i] - c0[i]) * max(0.0, u)) for i in range(len(c0)))
    return tuple(stops[-1][1])


def gradient(size, stops, angle: float = 90) -> Image.Image:
    """A linear gradient; 90° runs top to bottom, 0° left to right. Angled ones
    are drawn small and scaled up: a gradient has no detail to lose."""
    w, h = round(size[0]), round(size[1])
    strip = Image.new("RGBA", (1, 256))
    px = strip.load()
    for i in range(256):
        c = color_at(stops, i / 255)
        px[0, i] = c if len(c) == 4 else c + (255,)
    if angle % 360 == 90:
        return strip.resize((w, h), Image.BILINEAR)
    if angle % 360 == 0:
        return strip.transpose(Image.ROTATE_90).resize((w, h), Image.BILINEAR)
    q = max(1, min(w, h) // 96)
    sw, sh = max(2, w // q), max(2, h // q)
    side = math.ceil(math.hypot(sw, sh)) + 2
    square = strip.resize((side, side), Image.BILINEAR).rotate(90 - angle, resample=Image.BICUBIC)
    left, top = (side - sw) // 2, (side - sh) // 2
    return square.crop((left, top, left + sw, top + sh)).resize((w, h), Image.BILINEAR)


def solid(mask: Image.Image, color) -> Image.Image:
    layer = Image.new("RGBA", mask.size, tuple(color[:3]) + (0,))
    layer.putalpha(mask if len(color) == 3 else mask.point(lambda v: v * color[3] // 255))
    return layer


def textured(mask: Image.Image, image: Image.Image) -> Image.Image:
    layer = image.convert("RGBA")
    layer.putalpha(ImageChops.multiply(layer.getchannel("A"), mask))
    return layer


def fade(mask: Image.Image, opacity: float) -> Image.Image:
    return mask.point(lambda v: round(v * opacity))


def dither(image: Image.Image, amount: float = 2.2) -> Image.Image:
    """A little film grain, so smooth gradients don't band in JPEG."""
    noise = Image.effect_noise(image.size, amount).convert("L")
    return ImageChops.add(image.convert("RGB"), Image.merge("RGB", (noise, noise, noise)), 1.0, -128)


def place(canvas: Image.Image, layer: Image.Image, x: float, y: float) -> None:
    """alpha_composite at any position, clipping what falls off the canvas."""
    x, y = round(x), round(y)
    left, top = max(0, -x), max(0, -y)
    right, bottom = min(layer.width, canvas.width - x), min(layer.height, canvas.height - y)
    if right <= left or bottom <= top:
        return
    if (left, top, right, bottom) != (0, 0, layer.width, layer.height):
        layer = layer.crop((left, top, right, bottom))
    canvas.alpha_composite(layer, (x + left, y + top))


def place_centered(canvas, layer, cx, cy) -> None:
    place(canvas, layer, cx - layer.width / 2, cy - layer.height / 2)


# MARK: - Masks and shadows

SS = 4  # supersampling for drawn shapes


def mask(size, paint, ss: int = SS) -> Image.Image:
    """An anti-aliased mask: paint(draw, k) draws white at k× scale."""
    w, h = round(size[0]), round(size[1])
    big = Image.new("L", (w * ss, h * ss), 0)
    paint(ImageDraw.Draw(big), ss)
    return big.reduce(ss)


def rounded(size, radius: float, ss: int = 3) -> Image.Image:
    w, h = round(size[0]), round(size[1])
    r = min(radius, w / 2, h / 2)
    return mask((w, h), lambda d, k: d.rounded_rectangle((0, 0, w * k - 1, h * k - 1), radius=r * k, fill=255), ss)


def outline(size, radius: float, width: float) -> Image.Image:
    """The edge of a rounded rectangle, width pixels thick."""
    w, h = round(size[0]), round(size[1])
    r = min(radius, w / 2, h / 2)
    return mask((w, h), lambda d, k: d.rounded_rectangle((0, 0, w * k - 1, h * k - 1), radius=r * k, outline=255,
                                                         width=max(1, round(width * k))), 3)


def grow(m: Image.Image, px: float) -> Image.Image:
    """Dilate a (supersampled) mask by about px, with rounded corners."""
    if px <= 0:
        return m
    blurred = m.filter(ImageFilter.GaussianBlur(px / 1.7))
    return blurred.point(lambda v: 255 if v > 11 else 0)


def shrink(m: Image.Image, px: float) -> Image.Image:
    blurred = m.filter(ImageFilter.GaussianBlur(px / 1.7))
    return blurred.point(lambda v: 255 if v > 244 else 0)


def soften(m: Image.Image, px: float) -> Image.Image:
    """Round every corner of a (supersampled) mask by about px."""
    blurred = m.filter(ImageFilter.GaussianBlur(px))
    return blurred.point(lambda v: 255 if v >= 128 else 0)


def shadow(alpha: Image.Image, blur: float, opacity: float, color=PLUM) -> Image.Image:
    """A soft shadow the size of alpha (which needs room around the shape)."""
    w, h = alpha.size
    f = max(1, int(blur // 5))
    small = alpha.resize((max(1, w // f), max(1, h // f)), Image.BILINEAR).filter(ImageFilter.GaussianBlur(blur / f))
    return solid(fade(small.resize((w, h), Image.BICUBIC), opacity), color)


def with_shadows(art: Image.Image, shadows) -> Image.Image:
    """art on a padded canvas above its shadows: (blur, opacity, dy) each."""
    pad = round(max(b * 2.2 + abs(dy) for b, _, dy in shadows))
    out = Image.new("RGBA", (art.width + pad * 2, art.height + pad * 2), (0, 0, 0, 0))
    alpha = Image.new("L", out.size, 0)
    alpha.paste(art.getchannel("A"), (pad, pad))
    for blur, opacity, dy in shadows:
        place(out, shadow(alpha, blur, opacity), 0, dy)
    out.alpha_composite(art, (pad, pad))
    return out


def quad(p0, c, p1, steps: int = 18):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * c[0] + t * t * p1[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * c[1] + t * t * p1[1])
            for t in (i / steps for i in range(steps + 1))]


def sparkle_points(cx, cy, r, inner: float = 0.28, tall: float = 1.0):
    """The app's four-point sparkle (SparkleShape): concave sides, needle points."""
    k, v = inner * r, r * tall
    return (quad((cx, cy - v), (cx + k, cy - k * tall), (cx + r, cy))
            + quad((cx + r, cy), (cx + k, cy + k * tall), (cx, cy + v))
            + quad((cx, cy + v), (cx - k, cy + k * tall), (cx - r, cy))
            + quad((cx - r, cy), (cx - k, cy - k * tall), (cx, cy - v)))


def heart_parts(cx, cy, width):
    """A round sticker heart: a square on its point with two circles for lobes.
    Returns (lobes as circle boxes, the square as a polygon), centred on (cx, cy)."""
    a = width / 1.707
    d = a / math.sqrt(2)
    oy = cy - (d - 0.854 * a) / 2  # centre the bounding box vertically
    square = [(cx, oy - d), (cx + d, oy), (cx, oy + d), (cx - d, oy)]
    lobes = [(cx - d / 2 - a / 2, oy - d / 2 - a / 2, cx - d / 2 + a / 2, oy - d / 2 + a / 2),
             (cx + d / 2 - a / 2, oy - d / 2 - a / 2, cx + d / 2 + a / 2, oy - d / 2 + a / 2)]
    return lobes, square


def paint_heart(d, cx, cy, width, fill=255):
    lobes, square = heart_parts(cx, cy, width)
    d.polygon(square, fill=fill)
    for box in lobes:
        d.ellipse(box, fill=fill)


# MARK: - Fonts

@dataclass(frozen=True)
class Face:
    path: Path
    index: int = 0
    axes: tuple = ()     # variation values in the font's axis order
    bold: float = 0.0    # synthetic emboldening in em, for faces without a heavy cut

    def at(self, size: float) -> ImageFont.FreeTypeFont:
        return load_font(str(self.path), self.index, self.axes, max(1, round(size)))

    def stroke(self, size: float) -> int:
        return round(self.bold * size)


@lru_cache(maxsize=1024)
def load_font(path: str, index: int, axes: tuple, size: int) -> ImageFont.FreeTypeFont:
    font = ImageFont.truetype(path, size, index=index)
    if axes:
        font.set_variation_by_axes(list(axes))
    return font


@dataclass(frozen=True)
class Script:
    heavy: Face
    medium: Face
    semibold: Face
    accent: Face | None        # None: the accent keeps the heavy face, coloured
    accent_scale: float = 1.0
    leading: float = 1.04      # headline baseline-to-baseline, in em
    tracking: float = 0.0      # headline letter spacing, in em
    cjk: bool = False          # break between characters, not only at spaces

    def faces(self):
        return [self.heavy, self.medium, self.semibold] + ([self.accent] if self.accent else [])


NEW_YORK_ITALIC = Face(SYSTEM / "NewYorkItalic.ttf", axes=(256, 640, 0))   # opsz, wght, GRAD
SF_PRO = SYSTEM / "SFNS.ttf"                                               # wdth, opsz, GRAD, wght
LATIN = Script(Face(FONTS / "Poppins-ExtraBold.ttf"), Face(FONTS / "Poppins-Medium.ttf"),
               Face(FONTS / "Poppins-SemiBold.ttf"), NEW_YORK_ITALIC, accent_scale=1.1, leading=1.04)
CYRILLIC = Script(Face(SF_PRO, axes=(100, 96, 400, 820)), Face(SF_PRO, axes=(100, 28, 400, 510)),
                  Face(SF_PRO, axes=(100, 28, 400, 640)), NEW_YORK_ITALIC, accent_scale=1.08,
                  leading=1.05, tracking=-0.012)
JAPANESE = Script(Face(SYSTEM / "ヒラギノ角ゴシック W8.ttc"), Face(SYSTEM / "ヒラギノ角ゴシック W5.ttc"),
                  Face(SYSTEM / "ヒラギノ角ゴシック W6.ttc"), None, leading=1.2, cjk=True)
KOREAN = Script(Face(SYSTEM / "AppleSDGothicNeo.ttc", 16), Face(SYSTEM / "AppleSDGothicNeo.ttc", 2),
                Face(SYSTEM / "AppleSDGothicNeo.ttc", 4), None, leading=1.16)
# Hiragino Sans GB stops at W6, so Chinese headlines get a touch of synthetic bold.
CHINESE = Script(Face(SYSTEM / "Hiragino Sans GB.ttc", 2, bold=0.016), Face(SYSTEM / "Hiragino Sans GB.ttc", 0, bold=0.012),
                 Face(SYSTEM / "Hiragino Sans GB.ttc", 2), None, leading=1.2, cjk=True)
SCRIPTS = {"ru": CYRILLIC, "ja": JAPANESE, "ko": KOREAN, "zh": CHINESE}


@lru_cache(maxsize=None)
def script_for(lang: str) -> Script:
    script = SCRIPTS.get(lang) or SCRIPTS.get(lang.split("-")[0]) or LATIN
    missing = [str(face.path) for face in script.faces() if not face.path.exists()]
    if missing:
        print(f"warning: {lang}: missing {', '.join(missing)}; using Poppins")
        return LATIN if all(face.path.exists() for face in LATIN.faces()) else script
    return script


# MARK: - Text

# Line-break rules for Japanese and Chinese: closing punctuation, small kana and
# the commonest particles never start a line, opening brackets never end one.
NO_START = set("、。，．・：；？！ー」』）】〉》〕｝〜…‥,.!?:;)]}%’”ぁぃぅぇぉっゃゅょァィゥェォッャュョ"
               "をはがにでのへもと的了")
NO_END = set("「『（【〈《〔｛([{‘“")


def wide(ch: str) -> bool:
    return bool(ch) and ord(ch) >= 0x2E80


@dataclass
class Word:
    segs: list          # [(text, accent)]
    space: bool         # a space comes before it


def tokenize(text: str, cjk: bool) -> list[list[Word]]:
    """Words per hard line ("\\n"); *asterisks* toggle the accent."""
    lines: list[list[Word]] = [[]]
    word: list = []
    space = pending = accent = False
    prev = ""

    def flush():
        nonlocal word, space
        if word:
            lines[-1].append(Word(word, space))
            word, space = [], False

    for ch in text:
        if ch == "*":
            accent = not accent
            continue
        if ch == "\n":
            flush()
            lines.append([])
            pending, prev = False, ""
            continue
        if ch in " \t":  # a no-break space (U+00A0) stays inside the word
            flush()
            pending, prev = bool(lines[-1]), " "
            continue
        breakable = (wide(ch) or wide(prev)) and ch not in NO_START and prev not in NO_END
        if word and cjk and breakable and not (accent and word[-1][1]):  # an accent stays whole
            flush()
        if not word:
            space, pending = pending, False
        if word and word[-1][1] == accent:
            word[-1] = (word[-1][0] + ch, accent)
        else:
            word.append((ch, accent))
        prev = ch
    flush()
    return [line for line in lines if line]


@dataclass
class Style:
    """How a block of text is set: script, size, weight and spacing."""
    script: Script
    size: float
    weight: str = "heavy"      # heavy, medium or semibold
    tracking: float = 0.0
    leading: float = 1.3

    def face(self, accent: bool) -> tuple[Face, float]:
        if accent and self.weight == "heavy" and self.script.accent:
            return self.script.accent, self.size * self.script.accent_scale
        return getattr(self.script, self.weight), self.size

    def font(self, accent: bool) -> ImageFont.FreeTypeFont:
        face, size = self.face(accent)
        return face.at(size)

    def italic(self, accent: bool) -> bool:
        return accent and self.weight == "heavy" and self.script.accent is not None

    def run(self, text: str, accent: bool) -> tuple[float, float, float]:
        """(shift before, advance, space after) of a run. An italic accent
        starts at its ink and leaves room for its overhang, so the spaces on
        either side look even next to the upright face."""
        text = text.replace("\u00a0", " ")
        font = self.font(accent)
        advance = font.getlength(text) + self.tracking * self.size * len(text)
        if not self.italic(accent):
            return 0.0, advance, 0.0
        box = font.getbbox(text, anchor="ls")
        return -box[0] * 0.85, advance, max(0.0, box[2] - advance) + self.size * 0.015

    def run_width(self, text: str, accent: bool) -> float:
        return sum(self.run(text, accent))

    def word_width(self, word: Word) -> float:
        return sum(self.run_width(text, accent) for text, accent in word.segs)

    def space_width(self) -> float:
        return self.font(False).getlength(" ")


def line_width(style: Style, line: list[Word]) -> float:
    total = 0.0
    for i, word in enumerate(line):
        if i and word.space:
            total += style.space_width()
        total += style.word_width(word)
    return total


def break_bonus(word: Word) -> float:
    """How good a line break after this word is: best after a sentence, then
    after a comma or a colon."""
    last = word.segs[-1][0][-1:]
    return 4.0 if last in set(".!?。！？") else 1.0 if last in set(",:;—–、，：；") else 0.0


def balanced(style: Style, words: list[Word], max_width: float) -> list[list[Word]]:
    """The fewest lines that fit, then the split with the most even lengths,
    preferring breaks after punctuation."""
    count, width = 1, 0.0
    for i, word in enumerate(words):
        w = style.word_width(word) + (style.space_width() if i and word.space else 0)
        if width and width + w > max_width:
            count, width = count + 1, style.word_width(word)
        else:
            width += w
    if count == 1 or len(words) < 2:
        return [words]
    count = min(count, len(words))
    best, best_cost = None, math.inf

    def splits(start, parts):
        if parts == 1:
            yield [words[start:]]
            return
        for end in range(start + 1, len(words) - parts + 2):
            for rest in splits(end, parts - 1):
                yield [words[start:end]] + rest

    for lines in splits(0, count):
        widths = [line_width(style, line) for line in lines]
        if max(widths) > max_width * 1.0001:
            continue
        cost = max(widths) - min(widths) * 0.15
        # Prefer breaking after punctuation; much more so without spaces, where any
        # other break may fall inside a word.
        bonus = max_width * (0.3 if style.script.cjk else 0.06)
        cost -= sum(bonus * break_bonus(line[-1]) for line in lines[:-1])
        if cost < best_cost:
            best, best_cost = lines, cost
    if best is None:  # a word longer than the line: greedy
        best, line = [], []
        for word in words:
            if line and line_width(style, line + [word]) > max_width:
                best.append(line)
                line = []
            line.append(word)
        best.append(line)
    return best


def arrange(style: Style, text: str, max_width: float) -> list[list[Word]]:
    lines = []
    for hard in tokenize(text, style.script.cjk):
        lines += balanced(style, hard, max_width)
    return lines


def fit(script: Script, text: str, max_width: float, sizes, max_lines: int, **style) -> tuple[Style, list]:
    """The biggest size whose lines fit; past the smallest, more lines. A "\\n"
    marks where to break only when the text doesn't fit on one line."""
    if "\n" in text:
        one = Style(script, sizes[0], **style)
        lines = arrange(one, text.replace("\n", " "), max_width)
        if len(lines) == 1 and line_width(one, lines[0]) <= max_width + 0.5:
            return one, lines
    result = None
    for size in sizes:
        s = Style(script, size, **style)
        lines = arrange(s, text, max_width)
        result = (s, lines)
        if len(lines) <= max_lines and all(line_width(s, line) <= max_width + 0.5 for line in lines):
            return result
    return result


def draw_run(draw, x, baseline, text, style: Style, accent: bool) -> float:
    """Draws a run at x (before its optical shift); returns its full width."""
    face, size = style.face(accent)
    font = face.at(size)
    stroke = face.stroke(size)
    track = style.tracking * style.size
    pre, advance, post = style.run(text, accent)
    text = text.replace("\u00a0", " ")
    if not track:
        draw.text((x + pre, baseline), text, font=font, fill=255, anchor="ls", stroke_width=stroke, stroke_fill=255)
    else:
        cx = x + pre
        for ch in text:
            draw.text((cx, baseline), ch, font=font, fill=255, anchor="ls", stroke_width=stroke, stroke_fill=255)
            cx += font.getlength(ch) + track
    return pre + advance + post


def vertical_extent(style: Style, line: list[Word]) -> tuple[float, float]:
    """Top and bottom of a line's ink, relative to its baseline."""
    top, bottom = 0.0, 0.0
    for word in line:
        for text, accent in word.segs:
            box = style.font(accent).getbbox(text, anchor="ls")
            top, bottom = min(top, box[1]), max(bottom, box[3])
    return top, bottom


def text_block(canvas, style: Style, lines, x, top, color, align="center", accent_colors=ACCENT, boxes=None):
    """Draws lines of text; x is the centre (or left edge). Returns the bottom,
    and appends each line's (left, top, right, bottom) to boxes if given."""
    advance = style.size * style.leading
    first_top, _ = vertical_extent(style, lines[0])
    _, last_bottom = vertical_extent(style, lines[-1])
    baseline = top - first_top
    height = round((len(lines) - 1) * advance + last_bottom - first_top) + 4
    body = Image.new("L", (canvas.width, height + round(style.size)), 0)
    accent = Image.new("L", body.size, 0)
    accent_box = None
    for i, line in enumerate(lines):
        y = baseline - top + i * advance + round(style.size * 0.2)
        lw = line_width(style, line)
        cx = x - lw / 2 if align == "center" else x
        if boxes is not None:
            line_top, line_bottom = vertical_extent(style, line)
            line_base = baseline + i * advance
            boxes.append((cx, line_base + line_top, cx + lw, line_base + line_bottom))
        for j, word in enumerate(line):
            if j and word.space:
                cx += style.space_width()
            for text, is_accent in word.segs:
                target = accent if is_accent and accent_colors else body
                w = draw_run(ImageDraw.Draw(target), cx, y, text, style, is_accent)
                if target is accent:
                    box = (cx, y - style.size, cx + w, y + style.size * 0.3)
                    accent_box = box if accent_box is None else (min(accent_box[0], box[0]), min(accent_box[1], box[1]),
                                                                max(accent_box[2], box[2]), max(accent_box[3], box[3]))
                cx += w
    offset = top - round(style.size * 0.2)
    layer = solid(body, color)
    if accent_box:
        x0, x1 = int(accent_box[0]) - 4, int(accent_box[2]) + 8
        fill = Image.new("RGBA", body.size, accent_colors[0] + (255,))
        fill.paste(gradient((max(1, x1 - x0), body.height), [(0, accent_colors[0]), (1, accent_colors[1])], angle=0), (x0, 0))
        layer.alpha_composite(textured(accent, fill))
    place(canvas, layer, 0, offset)
    return top + height


def plain(text: str) -> str:
    return text.replace("*", "").replace("\n", " ")


# MARK: - Decoration: sparkles, chips, badges

def sparkle(r: float, color=WHITE, glow: float = 0.55, tall: float = 1.12) -> Image.Image:
    """A sparkle with a soft halo."""
    size = round(r * 4.4)
    c = size / 2
    m = mask((size, size), lambda d, k: d.polygon(sparkle_points(c * k, c * k, r * k, 0.28, tall), fill=255))
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    if glow:
        halo = Image.new("L", (size, size), 0)
        ImageDraw.Draw(halo).ellipse((c - r * 0.7, c - r * 0.7, c + r * 0.7, c + r * 0.7), fill=255)
        out.alpha_composite(solid(fade(halo.filter(ImageFilter.GaussianBlur(r * 0.55)), glow), WHITE))
    out.alpha_composite(solid(m, color))
    return out


def icon(kind: str, size: float, color) -> Image.Image:
    s = round(size)

    def paint(d, k):
        u = s * k
        if kind == "sparkle":
            d.polygon(sparkle_points(u * 0.5, u * 0.5, u * 0.5, 0.28, 1.0), fill=255)
        elif kind == "heart":
            paint_heart(d, u * 0.5, u * 0.52, u * 0.92)
        elif kind == "check":
            d.line([(u * 0.12, u * 0.52), (u * 0.4, u * 0.8), (u * 0.9, u * 0.22)], fill=255, width=round(u * 0.17),
                   joint="curve")
            for p in [(u * 0.12, u * 0.52), (u * 0.9, u * 0.22)]:
                d.ellipse((p[0] - u * 0.085, p[1] - u * 0.085, p[0] + u * 0.085, p[1] + u * 0.085), fill=255)
        elif kind == "lock":
            d.rounded_rectangle((u * 0.14, u * 0.42, u * 0.86, u * 0.98), radius=u * 0.14, fill=255)
            d.arc((u * 0.27, u * 0.04, u * 0.73, u * 0.64), 180, 360, fill=255, width=round(u * 0.13))
            d.rectangle((u * 0.27, u * 0.32, u * 0.27 + u * 0.13, u * 0.5), fill=255)
            d.rectangle((u * 0.73 - u * 0.13, u * 0.32, u * 0.73, u * 0.5), fill=255)
    return solid(mask((s, s), paint), color)


def chip(text: str, script: Script, height: float, glyph: str | None = None) -> Image.Image:
    """A pill callout in the app's primary style: ink with a blush label."""
    style = Style(script, height * 0.4, weight="semibold")
    font = style.font(False)
    pad, gap = height * 0.42, height * 0.16
    glyph_size = height * 0.36 if glyph else 0
    tw = font.getlength(text)
    w, h = round(pad * 2 + tw + (glyph_size + gap if glyph else 0)), round(height)
    art = solid(rounded((w, h), h / 2), INK)
    x = pad
    if glyph:
        place(art, icon(glyph, glyph_size, BLUSH), x, (h - glyph_size) / 2)
        x += glyph_size + gap
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).text((x, h / 2 + optical_middle(style, text)), text, font=font, fill=255, anchor="ls",
                           stroke_width=style.script.semibold.stroke(style.size), stroke_fill=255)
    art.alpha_composite(solid(m, BLUSH))
    return with_shadows(art, [(h * 0.32, 0.22, h * 0.12), (h * 0.06, 0.12, h * 0.03)])


def optical_middle(style: Style, text: str) -> float:
    """How far below the centre line the baseline goes to centre text optically."""
    font = style.font(False)
    if style.script.cjk or any(wide(ch) for ch in text):
        box = font.getbbox(text, anchor="ls")
        return -(box[1] + box[3]) / 2
    return -font.getbbox("H", anchor="ls")[1] / 2


def before_after_badge(before: str, after: str, script: Script, height: float) -> Image.Image:
    """'Before | After' split pill with the compare handle in the middle."""
    style = Style(script, height * 0.4, weight="semibold")
    font = style.font(False)
    h = round(height)
    knob = round(h * 1.16)
    pad, inner = h * 0.5, knob / 2 + h * 0.2
    lw, rw = round(font.getlength(before) + pad + inner), round(font.getlength(after) + pad + inner)
    w = lw + rw
    canvas_h = knob
    art = Image.new("RGBA", (w, canvas_h), (0, 0, 0, 0))
    top = (canvas_h - h) / 2
    pill = rounded((w, h), h / 2)
    left = Image.new("L", (w, h), 0)
    left.paste(pill.crop((0, 0, lw, h)), (0, 0))
    right = Image.new("L", (w, h), 0)
    right.paste(pill.crop((lw, 0, w, h)), (lw, 0))
    place(art, solid(left, WHITE), 0, top)
    place(art, solid(right, INK), 0, top)
    m = Image.new("L", (w, canvas_h), 0)
    baseline = canvas_h / 2 + optical_middle(style, before + after)
    ImageDraw.Draw(m).text((pad, baseline), before, font=font, fill=255, anchor="ls")
    art.alpha_composite(solid(m, INK))
    m = Image.new("L", (w, canvas_h), 0)
    ImageDraw.Draw(m).text((lw + inner, baseline), after, font=font, fill=255, anchor="ls")
    art.alpha_composite(solid(m, BLUSH))
    # The compare handle: a white disc with ‹ › chevrons, as in the editor.
    disc = Image.new("RGBA", (knob, knob), (0, 0, 0, 0))
    disc.alpha_composite(solid(mask((knob, knob), lambda d, k: d.ellipse((0, 0, knob * k - 1, knob * k - 1), fill=255)), WHITE))

    def chevrons(d, k):
        u = knob * k
        stroke = round(u * 0.07)
        d.line([(u * 0.42, u * 0.36), (u * 0.3, u * 0.5), (u * 0.42, u * 0.64)], fill=255, width=stroke, joint="curve")
        d.line([(u * 0.58, u * 0.36), (u * 0.7, u * 0.5), (u * 0.58, u * 0.64)], fill=255, width=stroke, joint="curve")
    disc.alpha_composite(solid(mask((knob, knob), chevrons), INK))
    disc = with_shadows(disc, [(knob * 0.12, 0.28, knob * 0.05)])
    place_centered(art, disc, lw, canvas_h / 2)
    return with_shadows(art, [(h * 0.34, 0.24, h * 0.14), (h * 0.06, 0.12, h * 0.03)])


# MARK: - Stickers (die-cut, drawn like the app's sticker sheet)

def die_cut(art: Image.Image, shape: Image.Image, edge: float) -> Image.Image:
    """The art on a white sticker edge grown around its (supersampled) shape."""
    border = grow(shape, edge)
    out = solid(border, WHITE)
    out.alpha_composite(art)
    return out


def glossy(d_size, box, alpha=150):
    """A soft white highlight ellipse (supersampled coordinates)."""
    m = Image.new("L", d_size, 0)
    ImageDraw.Draw(m).ellipse(box, fill=255)
    return solid(fade(m.filter(ImageFilter.GaussianBlur(max(1, (box[2] - box[0]) * 0.08))), alpha / 255), WHITE)


def art_heart(u: int, chrome: bool = False):
    shape = Image.new("L", (u, u), 0)
    paint_heart(ImageDraw.Draw(shape), u * 0.5, u * 0.52, u * 0.82)
    shape = soften(shape, u * 0.012)
    if chrome:
        fill = gradient((u, u), [(0.12, (255, 255, 255)), (0.3, (236, 226, 255)), (0.47, (178, 154, 245)),
                                 (0.5, (62, 30, 110)), (0.55, (150, 112, 232)), (0.75, (238, 178, 222)),
                                 (0.92, (255, 240, 248))])
    else:
        fill = gradient((u, u), [(0.15, (255, 140, 196)), (0.85, (240, 60, 145))])
    art = textured(shape, fill)
    if chrome:
        ring = ImageChops.subtract(shape, shrink(shape, u * 0.025))
        art.alpha_composite(solid(ring, (150, 128, 226)))
        glint = Image.new("L", (u, u), 0)
        ImageDraw.Draw(glint).polygon(sparkle_points(u * 0.66, u * 0.3, u * 0.09), fill=255)
        art.alpha_composite(solid(glint, WHITE))
    else:
        art.alpha_composite(glossy((u, u), (u * 0.22, u * 0.22, u * 0.38, u * 0.33), 200))
        art.alpha_composite(glossy((u, u), (u * 0.17, u * 0.36, u * 0.22, u * 0.41), 170))
    return art, shape


def art_star(u: int):
    pts = []
    for i in range(10):
        r = u * (0.46 if i % 2 == 0 else 0.235)
        a = -math.pi / 2 + i * math.pi / 5
        pts.append((u * 0.5 + r * math.cos(a), u * 0.54 + r * math.sin(a)))
    shape = Image.new("L", (u, u), 0)
    ImageDraw.Draw(shape).polygon(pts, fill=255)
    shape = soften(shape, u * 0.03)
    art = textured(shape, gradient((u, u), [(0.1, (255, 236, 150)), (0.9, (255, 196, 64))]))
    inner = Image.new("L", (u, u), 0)
    ImageDraw.Draw(inner).polygon([(u * 0.5 + (x - u * 0.5) * 0.5, u * 0.56 + (y - u * 0.54) * 0.5) for x, y in pts], fill=255)
    art.alpha_composite(solid(fade(soften(inner, u * 0.02), 0.45), (255, 248, 210)))
    return art, shape


def art_sparkles(u: int):
    shape = Image.new("L", (u, u), 0)
    d = ImageDraw.Draw(shape)
    big = sparkle_points(u * 0.42, u * 0.55, u * 0.36, 0.3, 1.08)
    small = sparkle_points(u * 0.78, u * 0.22, u * 0.15, 0.3)
    tiny = sparkle_points(u * 0.8, u * 0.74, u * 0.1, 0.3)
    for pts in (big, small, tiny):
        d.polygon(pts, fill=255)
    art = Image.new("RGBA", (u, u), (0, 0, 0, 0))
    big_m = Image.new("L", (u, u), 0)
    ImageDraw.Draw(big_m).polygon(big, fill=255)
    art.alpha_composite(solid(big_m, (150, 120, 240)))
    art.alpha_composite(solid(shrink(big_m, u * 0.03), WHITE))
    for pts, color in ((small, (255, 214, 92)), (tiny, PINK)):
        m = Image.new("L", (u, u), 0)
        ImageDraw.Draw(m).polygon(pts, fill=255)
        art.alpha_composite(solid(m, color))
    return art, grow(shape, u * 0.02)


def art_bow(u: int):
    def loop(d, side):
        sx = 1 if side > 0 else -1
        cx = u * 0.5
        pts = [(cx + sx * u * 0.04, u * 0.42), (cx + sx * u * 0.44, u * 0.16), (cx + sx * u * 0.47, u * 0.4),
               (cx + sx * u * 0.42, u * 0.66), (cx + sx * u * 0.04, u * 0.5)]
        d.polygon(pts, fill=255)

    def tail(d, side):
        sx = 1 if side > 0 else -1
        cx = u * 0.5
        d.polygon([(cx + sx * u * 0.01, u * 0.48), (cx + sx * u * 0.13, u * 0.5), (cx + sx * u * 0.31, u * 0.88),
                   (cx + sx * u * 0.2, u * 0.82), (cx + sx * u * 0.16, u * 0.93)], fill=255)
    loops = Image.new("L", (u, u), 0)
    d = ImageDraw.Draw(loops)
    loop(d, 1)
    loop(d, -1)
    loops = soften(loops, u * 0.05)
    tails = Image.new("L", (u, u), 0)
    d = ImageDraw.Draw(tails)
    tail(d, 1)
    tail(d, -1)
    tails = soften(tails, u * 0.012)
    knot = Image.new("L", (u, u), 0)
    ImageDraw.Draw(knot).rounded_rectangle((u * 0.42, u * 0.37, u * 0.58, u * 0.55), radius=u * 0.06, fill=255)
    pink = gradient((u, u), [(0.15, (255, 135, 190)), (0.85, (238, 62, 146))])
    deep = (214, 52, 128)
    art = textured(tails, gradient((u, u), [(0.4, (240, 80, 156)), (1, (214, 46, 126))]))
    art.alpha_composite(textured(loops, pink))
    folds = Image.new("L", (u, u), 0)
    d = ImageDraw.Draw(folds)
    for sx in (1, -1):
        d.line([(u * 0.5 + sx * u * 0.08, u * 0.45), (u * 0.5 + sx * u * 0.3, u * 0.36)], fill=255, width=round(u * 0.022))
    art.alpha_composite(solid(fade(folds.filter(ImageFilter.GaussianBlur(u * 0.006)), 0.55), deep))
    art.alpha_composite(solid(knot, deep))
    for sx in (1, -1):
        cx = u * (0.5 + sx * 0.26)
        art.alpha_composite(glossy((u, u), (cx - u * 0.06, u * 0.24, cx + u * 0.06, u * 0.3), 170))
    shape = ImageChops.lighter(ImageChops.lighter(loops, tails), knot)
    return art, shape


def art_butterfly(u: int):
    art = Image.new("RGBA", (u, u), (0, 0, 0, 0))
    shape = Image.new("L", (u, u), 0)
    d = ImageDraw.Draw(shape)
    upper = [(u * 0.08, u * 0.16, u * 0.5, u * 0.58), (u * 0.5, u * 0.16, u * 0.92, u * 0.58)]
    lower = [(u * 0.17, u * 0.5, u * 0.49, u * 0.84), (u * 0.51, u * 0.5, u * 0.83, u * 0.84)]
    for box in upper + lower:
        d.ellipse(box, fill=255)
    d.rounded_rectangle((u * 0.455, u * 0.2, u * 0.545, u * 0.84), radius=u * 0.045, fill=255)
    for box in upper:
        m = mask((u, u), lambda dd, k, b=box: dd.ellipse([v * k for v in b], fill=255), ss=1)
        art.alpha_composite(textured(m, gradient((u, u), [(0.2, (196, 176, 255)), (0.6, (150, 116, 246))])))
    for box in lower:
        m = mask((u, u), lambda dd, k, b=box: dd.ellipse([v * k for v in b], fill=255), ss=1)
        art.alpha_composite(textured(m, gradient((u, u), [(0.5, (255, 130, 186)), (0.9, (240, 70, 150))])))
    spots = Image.new("L", (u, u), 0)
    ds = ImageDraw.Draw(spots)
    for cx in (0.29, 0.71):
        ds.ellipse((u * (cx - 0.08), u * 0.3, u * (cx + 0.08), u * 0.46), fill=255)
    art.alpha_composite(solid(fade(spots, 0.8), (236, 228, 255)))
    dots = Image.new("L", (u, u), 0)
    dd = ImageDraw.Draw(dots)
    for cx in (0.34, 0.66):
        dd.ellipse((u * (cx - 0.055), u * 0.63, u * (cx + 0.055), u * 0.74), fill=255)
    art.alpha_composite(solid(dots, (255, 214, 92)))
    body = Image.new("L", (u, u), 0)
    db = ImageDraw.Draw(body)
    db.rounded_rectangle((u * 0.465, u * 0.22, u * 0.535, u * 0.84), radius=u * 0.035, fill=255)
    for sx in (1, -1):
        db.line([(u * 0.5, u * 0.24), (u * 0.5 + sx * u * 0.08, u * 0.1)], fill=255, width=round(u * 0.022))
        db.ellipse((u * 0.5 + sx * u * 0.08 - u * 0.03, u * 0.07, u * 0.5 + sx * u * 0.08 + u * 0.03, u * 0.13), fill=255)
    art.alpha_composite(solid(body, (66, 28, 100)))
    shape = ImageChops.lighter(shape, grow(body, u * 0.01))
    return art, soften(shape, u * 0.01)


def art_camera(u: int):
    shape = Image.new("L", (u, u), 0)
    d = ImageDraw.Draw(shape)
    d.rounded_rectangle((u * 0.06, u * 0.3, u * 0.94, u * 0.82), radius=u * 0.09, fill=255)
    d.rounded_rectangle((u * 0.3, u * 0.2, u * 0.56, u * 0.34), radius=u * 0.04, fill=255)
    d.rounded_rectangle((u * 0.68, u * 0.23, u * 0.82, u * 0.32), radius=u * 0.03, fill=255)
    art = textured(shape, gradient((u, u), [(0.25, (255, 196, 222)), (0.85, (248, 160, 200))]))
    stripe = Image.new("L", (u, u), 0)
    ImageDraw.Draw(stripe).rectangle((u * 0.06, u * 0.6, u * 0.94, u * 0.68), fill=255)
    art.alpha_composite(solid(ImageChops.multiply(stripe, shape), (244, 140, 186)))
    lens = [(0.25, (40, 22, 62)), (0.19, (124, 92, 214)), (0.12, (52, 26, 90)), (0.06, (26, 12, 46))]
    for r, color in lens:
        m = Image.new("L", (u, u), 0)
        ImageDraw.Draw(m).ellipse((u * (0.5 - r), u * (0.56 - r), u * (0.5 + r), u * (0.56 + r)), fill=255)
        art.alpha_composite(solid(m, color))
    art.alpha_composite(glossy((u, u), (u * 0.4, u * 0.42, u * 0.47, u * 0.49), 230))
    flash = Image.new("L", (u, u), 0)
    ImageDraw.Draw(flash).rounded_rectangle((u * 0.14, u * 0.38, u * 0.27, u * 0.46), radius=u * 0.02, fill=255)
    art.alpha_composite(solid(flash, (255, 222, 110)))
    heart = Image.new("L", (u, u), 0)
    paint_heart(ImageDraw.Draw(heart), u * 0.8, u * 0.42, u * 0.09)
    art.alpha_composite(solid(heart, PINK))
    return art, shape


def art_lipstick(u: int):
    """A lipstick (the object only), tilted: a metal case, a gold band and a
    pink bullet with a slanted tip."""
    flat = Image.new("RGBA", (u, u), (0, 0, 0, 0))
    shape = Image.new("L", (u, u), 0)
    bullet = Image.new("L", (u, u), 0)
    ImageDraw.Draw(bullet).polygon([(u * 0.415, u * 0.42), (u * 0.415, u * 0.16), (u * 0.585, u * 0.06), (u * 0.585, u * 0.42)],
                                   fill=255)
    bullet = soften(bullet, u * 0.025)
    pink = [(0, (255, 120, 178)), (0.45, (246, 72, 150)), (1, (206, 34, 118))]
    flat.alpha_composite(textured(bullet, gradient((u, u), pink, angle=0)))
    shape = ImageChops.lighter(shape, bullet)
    parts = (((0.39, 0.4, 0.61, 0.5), 0.015, [(0, (214, 170, 92)), (0.4, (255, 232, 170)), (1, (198, 150, 76))]),
             ((0.37, 0.48, 0.63, 0.95), 0.05,
              [(0, (92, 40, 112)), (0.36, (160, 96, 190)), (0.6, (110, 52, 136)), (1, (66, 26, 86))]))
    for box, radius, stops in parts:
        m = Image.new("L", (u, u), 0)
        ImageDraw.Draw(m).rounded_rectangle([v * u for v in box], radius=radius * u, fill=255)
        flat.alpha_composite(textured(m, gradient((u, u), stops, angle=0)))
        shape = ImageChops.lighter(shape, m)
    flat.alpha_composite(glossy((u, u), (u * 0.44, u * 0.15, u * 0.47, u * 0.38), 170))
    flat.alpha_composite(glossy((u, u), (u * 0.415, u * 0.53, u * 0.445, u * 0.9), 110))
    heart = Image.new("L", (u, u), 0)
    paint_heart(ImageDraw.Draw(heart), u * 0.5, u * 0.72, u * 0.1)
    flat.alpha_composite(solid(heart, BLUSH))
    return flat.rotate(-30, resample=Image.BICUBIC), shape.rotate(-30, resample=Image.BICUBIC)


ARTS = {"heart": art_heart, "chromeheart": lambda u: art_heart(u, chrome=True), "star": art_star,
        "sparkles": art_sparkles, "bow": art_bow, "butterfly": art_butterfly, "camera": art_camera,
        "lipstick": art_lipstick}


@lru_cache(maxsize=64)
def sticker(kind: str, size: int, angle: float = 0) -> Image.Image:
    """A die-cut sticker: the art, a white edge and a soft shadow, rotated."""
    u = size * SS
    art, shape = ARTS[kind](u)
    pad = round(u * 0.08)
    big = Image.new("RGBA", (u + pad * 2, u + pad * 2), (0, 0, 0, 0))
    big_shape = Image.new("L", big.size, 0)
    big_shape.paste(shape, (pad, pad))
    framed = Image.new("RGBA", big.size, (0, 0, 0, 0))
    framed.alpha_composite(art, (pad, pad))
    cut = die_cut(framed, big_shape, u * 0.055)
    small = cut.reduce(SS)
    if angle:
        small = small.rotate(angle, resample=Image.BICUBIC, expand=True)
    return with_shadows(small, [(size * 0.05, 0.26, size * 0.035), (size * 0.012, 0.16, size * 0.01)])


# MARK: - Backgrounds: one Aura panorama per set, cut into slides

def aura_panorama(size, palettes, seed: int = 7) -> list[Image.Image]:
    """Soft Aura glows across all slides side by side, so neighbours flow into
    each other; returns one background per slide."""
    w, h = size
    q = 8
    n = len(palettes)
    pw, ph = math.ceil(w * n / q), math.ceil(h / q)
    sw = w / q
    base = gradient((pw, ph), [(0, (255, 247, 251)), (0.55, (252, 236, 244)), (1, (249, 226, 238))]).convert("RGB")
    rng = random.Random(seed)

    def blob(cx, cy, rx, ry, color, alpha):
        m = Image.new("L", (pw, ph), 0)
        ImageDraw.Draw(m).ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=round(255 * alpha))
        m = m.filter(ImageFilter.GaussianBlur(min(rx, ry) * 0.55))
        base.paste(Image.new("RGB", (pw, ph), color), (0, 0), m)

    portrait = h > w
    for i, (top, bottom) in enumerate(palettes):
        x0 = i * sw
        jitter = rng.uniform(-0.06, 0.06)
        if portrait:
            blob(x0 + sw * (0.2 + jitter), ph * 0.16, sw * 0.62, ph * 0.16, mix(top, WHITE, 0.32), 0.55)
            blob(x0 + sw * 0.86, ph * 0.56, sw * 0.62, ph * 0.26, mix(bottom, WHITE, 0.12), 0.72)
            blob(x0 + sw * 0.12, ph * 0.84, sw * 0.58, ph * 0.2, mix(top, WHITE, 0.1), 0.66)
        else:
            blob(x0 + sw * (0.12 + jitter), ph * 0.2, sw * 0.36, ph * 0.38, mix(top, WHITE, 0.25), 0.6)
            blob(x0 + sw * 0.88, ph * 0.72, sw * 0.38, ph * 0.46, mix(bottom, WHITE, 0.12), 0.7)
        if i + 1 < n:  # a bridge glow mixing this slide's colour with the next one's
            nxt = palettes[i + 1][0]
            blob(x0 + sw, ph * (0.36 if portrait else 0.45), sw * 0.32, ph * (0.14 if portrait else 0.3),
                 mix(mix(bottom, nxt, 0.5), WHITE, 0.2), 0.55)
    for i in range(n):  # light behind the headline and the device
        x0 = i * sw
        if portrait:
            blob(x0 + sw * 0.5, ph * 0.06, sw * 0.62, ph * 0.12, WHITE, 0.62)
            blob(x0 + sw * 0.5, ph * 0.6, sw * 0.4, ph * 0.18, WHITE, 0.32)
        else:
            blob(x0 + sw * 0.5, ph * 0.1, sw * 0.4, ph * 0.22, WHITE, 0.6)
            blob(x0 + sw * 0.5, ph * 0.62, sw * 0.32, ph * 0.3, WHITE, 0.3)
    slides = []
    for i in range(n):
        crop = base.crop((round(i * sw), 0, round((i + 1) * sw), ph))
        slides.append(dither(crop.resize((w, h), Image.BICUBIC)).convert("RGBA"))
    return slides


# MARK: - Devices

def iphone(screen: Image.Image, screen_w: int) -> tuple[Image.Image, tuple]:
    """A modern iPhone: titanium rim, thin black bezel, Dynamic Island.
    Returns the device and its screen's box inside it."""
    sw = round(screen_w)
    sh = round(screen.height * sw / screen.width)
    bez, rim = round(sw * 0.026), max(3, round(sw * 0.011))
    r = sw * 0.122
    w, h = sw + 2 * (bez + rim), sh + 2 * (bez + rim)
    knob = max(2, round(sw * 0.006))
    out = Image.new("RGBA", (w + knob * 2, h), (0, 0, 0, 0))
    metal = [(0, (226, 214, 220)), (0.45, (188, 176, 184)), (0.55, (204, 193, 200)), (1, (232, 222, 228))]
    for side, spots in ((-1, ((0.165, 0.2), (0.235, 0.3), (0.32, 0.385))), (1, ((0.255, 0.355),))):
        for a, b in spots:
            bw, bh = knob * 3, round(h * (b - a))
            button = textured(rounded((bw, bh), knob * 1.2), gradient((bw, bh), metal, angle=0))
            place(out, button, 0 if side < 0 else w + knob * 2 - bw, h * a)
    body = textured(rounded((w, h), r + bez + rim), gradient((w, h), metal, angle=20))
    place(out, body, knob, 0)
    place(out, solid(rounded((w - rim * 2, h - rim * 2), r + bez), (12, 11, 13)), knob + rim, rim)
    shot = screen.convert("RGB").resize((sw, sh), Image.LANCZOS)
    screen_box = (knob + rim + bez, rim + bez, sw, sh)
    out.paste(shot, screen_box[:2], rounded((sw, sh), r))
    iw, ih = sw * 0.318, sw * 0.093
    island = solid(rounded((iw, ih), ih / 2), (6, 6, 7))
    place(out, island, screen_box[0] + (sw - iw) / 2, screen_box[1] + sw * 0.03)
    # A hairline of light on the rim, as metal catches it.
    place(out, solid(fade(outline((w, h), r + bez + rim, 2), 0.6), (250, 244, 247)), knob, 0)
    return out, screen_box


def ipad(screen: Image.Image, screen_w: int) -> tuple[Image.Image, tuple]:
    sw = round(screen_w)
    sh = round(screen.height * sw / screen.width)
    bez, rim = round(sw * 0.03), max(3, round(sw * 0.007))
    r = sw * 0.03
    w, h = sw + 2 * (bez + rim), sh + 2 * (bez + rim)
    metal = [(0, (224, 216, 221)), (0.5, (190, 180, 187)), (1, (230, 222, 227))]
    out = textured(rounded((w, h), r + bez + rim), gradient((w, h), metal, angle=20))
    place(out, solid(rounded((w - rim * 2, h - rim * 2), r + bez), (12, 11, 13)), rim, rim)
    shot = screen.convert("RGB").resize((sw, sh), Image.LANCZOS)
    box = (rim + bez, rim + bez, sw, sh)
    out.paste(shot, box[:2], rounded((sw, sh), r))
    place(out, solid(fade(outline((w, h), r + bez + rim, 2), 0.6), (250, 244, 247)), 0, 0)
    return out, box


def mac_window(capture: Image.Image, width: int) -> Image.Image:
    """A Mac window capture with even corners and a hairline edge."""
    ww = round(width)
    wh = round(capture.height * ww / capture.width)
    window = capture.convert("RGBA").resize((ww, wh), Image.LANCZOS)
    radius = ww * 0.011
    window.putalpha(ImageChops.darker(window.getchannel("A"), rounded((ww, wh), radius)))
    window.alpha_composite(solid(fade(outline((ww, wh), radius, 1.5), 0.18), INK))
    return window


def macbook(content: Image.Image, width: int) -> Image.Image:
    """A laptop: a thin black bezel with a notch around content, on a slim base."""
    lid_w = round(width * 0.9)
    bez = round(lid_w * 0.018)
    sw = lid_w - bez * 2
    sh = round(sw / 1.545)
    lid_h = sh + bez * 2 + round(bez * 0.4)
    lid = Image.new("RGBA", (lid_w, lid_h), (0, 0, 0, 0))
    top_r = lid_w * 0.028
    lid.alpha_composite(solid(mask((lid_w, lid_h), lambda d, k: d.rounded_rectangle(
        (0, 0, lid_w * k - 1, (lid_h + top_r) * k), radius=top_r * k, fill=255), ss=3), (20, 19, 22)))
    lid_edge = mask((lid_w, lid_h), lambda d, k: d.rounded_rectangle(
        (0, 0, lid_w * k - 1, (lid_h + top_r) * k), radius=top_r * k, outline=255, width=3 * k), ss=3)
    lid.alpha_composite(solid(fade(lid_edge, 0.9), (150, 146, 152)))
    screen = content.convert("RGB").resize((sw, sh), Image.LANCZOS)
    lid.paste(screen, (bez, bez), rounded((sw, sh), sw * 0.01))
    notch_w, notch_h = sw * 0.1, bez * 1.25
    place(lid, solid(mask((notch_w, notch_h), lambda d, k: d.rounded_rectangle(
        (0, -notch_h * k, notch_w * k - 1, notch_h * k - 1), radius=notch_h * 0.6 * k, fill=255), ss=3), (20, 19, 22)),
        bez + (sw - notch_w) / 2, bez)
    base_w, base_h = width, round(width * 0.022)
    base = Image.new("RGBA", (base_w, base_h), (0, 0, 0, 0))
    base.alpha_composite(textured(mask((base_w, base_h), lambda d, k: d.rounded_rectangle(
        (0, -base_h * k, base_w * k - 1, base_h * k - 1), radius=base_h * 0.9 * k, fill=255), ss=3),
        gradient((base_w, base_h), [(0, (236, 230, 234)), (0.35, (214, 206, 212)), (1, (168, 160, 168))])))
    groove_w = base_w * 0.13
    place(base, solid(mask((groove_w, base_h * 0.4), lambda d, k: d.rounded_rectangle(
        (0, -base_h * k, groove_w * k - 1, base_h * 0.4 * k - 1), radius=base_h * 0.4 * k, fill=255), ss=3), (176, 168, 176)),
        (base_w - groove_w) / 2, 0)
    out = Image.new("RGBA", (base_w, lid_h + base_h), (0, 0, 0, 0))
    out.alpha_composite(lid, ((base_w - lid_w) // 2, 0))
    out.alpha_composite(base, (0, lid_h))
    return out


def device_shadows(device: Image.Image, scale: float) -> Image.Image:
    return with_shadows(device, [(scale * 0.055, 0.34, scale * 0.04), (scale * 0.012, 0.22, scale * 0.01)])


# MARK: - Stand-ins for missing iPad and Mac captures (layout previews only)

def backdrop_color(capture: Image.Image) -> tuple:
    rgb = capture.convert("RGB")
    samples = [rgb.getpixel((4, y)) for y in range(rgb.height // 4, rgb.height * 3 // 4, 37)]
    return tuple(sorted(c[i] for c in samples)[len(samples) // 2] for i in range(3))


def ipad_stand_in(capture: Image.Image) -> Image.Image:
    out = Image.new("RGB", IPAD, backdrop_color(capture))
    shot = capture.convert("RGB")
    shot = shot.resize((round(shot.width * IPAD[1] / shot.height), IPAD[1]), Image.LANCZOS)
    out.paste(shot, ((IPAD[0] - shot.width) // 2, 0))
    return out


def mac_stand_in(capture: Image.Image) -> Image.Image:
    size, bar = (2464, 1540), 104
    out = Image.new("RGBA", size, backdrop_color(capture) + (255,))
    shot = capture.convert("RGB")
    shot = shot.resize((round(shot.width * (size[1] - bar) / shot.height), size[1] - bar), Image.LANCZOS)
    out.paste(shot, ((size[0] - shot.width) // 2, bar))
    for i, color in enumerate(((255, 95, 87), (254, 188, 46), (40, 200, 64))):
        light = mask((26, 26), lambda d, k: d.ellipse((0, 0, 26 * k - 1, 26 * k - 1), fill=255))
        place(out, solid(light, color), 40 + i * 42, 39)
    return out


# MARK: - Slides

@dataclass(frozen=True)
class Look:
    aura: tuple                     # (top, bottom) Aura colours
    stickers: tuple = ()            # (kind, fx, fy, size, angle): centre at a fraction of the device box
    glyph: str | None = None        # the chip's icon
    tilt: float = 0.0               # degrees, counter-clockwise
    hero: bool = False


# Stickers sit on the device's side edges, reaching no more than ~4% into the
# screen, at heights where the app's screens keep an empty margin or a photo edge.
LOOKS = {
    "result": Look((PINK, PEACH), (("heart", 1.035, 0.4, 0.17, -12), ("sparkles", -0.035, 0.58, 0.16, 8)),
                   tilt=-3.5, hero=True),
    "makeup": Look((PINK, LILAC), (("lipstick", -0.04, 0.34, 0.18, 0), ("bow", 1.04, 0.58, 0.17, 10)), glyph="sparkle"),
    "home": Look((LILAC, MINT), (("star", 1.035, 0.3, 0.16, 12), ("chromeheart", -0.035, 0.6, 0.17, -10))),
    "effects": Look((PEACH, BUTTER), (("camera", -0.04, 0.28, 0.18, -10), ("star", 1.035, 0.64, 0.14, 14)), glyph="check"),
    "textStickers": Look((BUTTER, PINK), (("bow", -0.035, 0.18, 0.14, -8), ("butterfly", 1.035, 0.27, 0.17, 12),
                                          ("heart", -0.035, 0.46, 0.15, -14), ("star", 1.035, 0.53, 0.13, 10)), glyph="sparkle"),
    "create": Look((LILAC, PINK), (("sparkles", 1.035, 0.27, 0.16, 6), ("chromeheart", -0.035, 0.6, 0.16, -8)), glyph="sparkle"),
    "share-cover": Look((PEACH, PINK), (("star", -0.035, 0.3, 0.15, -12), ("heart", 1.035, 0.52, 0.16, 12))),
    "collage": Look((MINT, LILAC), (("camera", 1.04, 0.26, 0.17, 10), ("heart", -0.035, 0.58, 0.14, -10)), glyph="check"),
    "consent": Look((MINT, LILAC), (("sparkles", 1.035, 0.42, 0.13, 6),), glyph="lock"),
    "paywall": Look((BUTTER, PINK), (("heart", 1.035, 0.36, 0.16, 12), ("star", -0.035, 0.62, 0.12, -10)), glyph="heart"),
    "cutout": Look((MINT, PINK), (("star", -0.035, 0.3, 0.14, -10),), glyph="check"),
    "hideFaces": Look((LILAC, PEACH), (("heart", 1.035, 0.3, 0.14, 12),), glyph="lock"),
}
FALLBACK_AURAS = [(PINK, PEACH), (LILAC, MINT), (PEACH, BUTTER), (MINT, LILAC), (BUTTER, PINK)]


def look_for(scene: str, index: int) -> Look:
    return LOOKS.get(scene) or Look(FALLBACK_AURAS[index % len(FALLBACK_AURAS)])


class Slide:
    """One App Store image: background, text, device, decorations."""

    def __init__(self, size, background: Image.Image, lang: str, item: dict, look: Look):
        self.size, self.lang, self.item, self.look = size, lang, item, look
        self.script = script_for(lang)
        self.image = background.copy()
        self.avoid: list[tuple] = []
        self.lines: list[tuple] = []
        self.rng = random.Random(f"{item['scene']}-{size}")

    def headline(self, top, max_width, sizes, sub_size, gap):
        """The centred title (two lines; three at the smallest size if it must)
        and the subtitle under it. Returns the bottom of the block."""
        x = self.size[0] / 2
        setting = dict(leading=self.script.leading, tracking=self.script.tracking)
        style, lines = fit(self.script, self.item["title"], max_width, sizes, 2, **setting)
        if len(lines) > 2:
            style, lines = fit(self.script, self.item["title"], max_width, [sizes[-1]], 3, **setting)
        bottom = text_block(self.image, style, lines, x, top, INK, boxes=self.lines)
        for left, line_top, right, line_bottom in self.lines:
            self.avoid.append((left - 24, line_top - 24, right + 24, line_bottom + 16))
        subtitle = self.item.get("subtitle", "")
        if subtitle:
            if self.script.cjk or self.script is KOREAN:
                sub_size *= 0.94
            s_style, s_lines = fit(self.script, subtitle, max_width * 0.92, [sub_size, sub_size * 0.94, sub_size * 0.88], 2,
                                   weight="medium", leading=1.32)
            boxes: list[tuple] = []
            bottom = text_block(self.image, s_style, s_lines, x, bottom + gap, INK_SOFT, accent_colors=None, boxes=boxes)
            for left, line_top, right, line_bottom in boxes:
                self.avoid.append((left - 20, line_top - 20, right + 20, line_bottom + 20))
        return bottom

    def put_device(self, device: Image.Image, cx: float, top: float, scale: float):
        framed = device_shadows(device, scale)
        pad_x, pad_y = (framed.width - device.width) / 2, (framed.height - device.height) / 2
        x, y = cx - device.width / 2, top
        place(self.image, framed, x - pad_x, y - pad_y)
        box = (x, y, x + device.width, y + device.height)
        self.avoid.append(box)
        return box

    def badge(self, layer: Image.Image, cx: float, cy: float):
        place_centered(self.image, layer, cx, cy)
        self.avoid.append((cx - layer.width / 2, cy - layer.height / 2, cx + layer.width / 2, cy + layer.height / 2))

    def stickers(self, box, specs, unit: float):
        x0, y0, x1, y1 = box
        for kind, fx, fy, size, angle in specs:
            art = sticker(kind, round(unit * size), angle)
            cx, cy = x0 + (x1 - x0) * fx, y0 + (y1 - y0) * fy
            place_centered(self.image, art, cx, cy)
            r = unit * size * 0.5
            self.avoid.append((cx - r, cy - r, cx + r, cy + r))

    def free(self, x, y, r) -> bool:
        w, h = self.size
        margin = max(36, w * 0.03)
        inside = margin + r < x < w - margin - r and h * 0.04 + r < y < h - margin - r
        return inside and not any(x + r > a and x - r < c and y + r > b and y - r < d for a, b, c, d in self.avoid)

    def signature(self, r: float):
        """The brand's sparkle pair (a big white one, a small ink one) beside
        the headline: after its first line, or before it, or by the last."""
        if not self.lines:
            return
        candidates = []
        for left, top, right, bottom in (self.lines[0], self.lines[-1]):
            mid = top + (bottom - top) * 0.3
            candidates += [(right + r * 1.5, mid), (left - r * 1.5, mid)]
        for x, y in candidates:
            if self.free(x, y, r * 1.3):
                place_centered(self.image, sparkle(r, WHITE, glow=0.6), x, y)
                small = r * 0.42
                sx = x + r * 1.05 if x > self.size[0] / 2 else x - r * 1.05
                place_centered(self.image, sparkle(small, INK, glow=0), sx, y + r * 1.15)
                self.avoid.append((x - r * 1.7, y - r * 1.5, x + r * 1.7, y + r * 2))
                return

    def sparkles(self, count: int, r_range):
        """Sparkles where they cover nothing, spread out: each one takes the
        free spot farthest from everything placed so far."""
        w, h = self.size
        spots: list[tuple] = []
        for _ in range(count):
            r = self.rng.uniform(*r_range)
            best, best_gap = None, 0.0
            for _ in range(60):
                x, y = self.rng.uniform(0, w), self.rng.uniform(0, h)
                if not self.free(x, y, r * 1.2):
                    continue
                gap = min([math.hypot(x - sx, y - sy) for sx, sy in spots] + [w * 0.5])
                if gap > best_gap:
                    best, best_gap = (x, y), gap
            if best is None:
                break
            x, y = best
            color = WHITE if self.rng.random() < 0.75 else self.rng.choice([(255, 214, 92), PINK, LILAC])
            place_centered(self.image, sparkle(r, color, glow=0.5 if color == WHITE else 0), x, y)
            self.avoid.append((x - r * 1.8, y - r * 1.8, x + r * 1.8, y + r * 1.8))
            spots.append((x, y))

    def jpeg(self) -> Image.Image:
        return self.image.convert("RGB")


def chip_layer(slide: Slide, height: float) -> Image.Image | None:
    item = slide.item
    if item.get("before") or item.get("after") or item["scene"] == "result":
        return before_after_badge(item.get("before", "Before"), item.get("after", "After"), slide.script, height)
    if item.get("chip"):
        return chip(item["chip"], slide.script, height, glyph=slide.look.glyph)
    return None


def tilted(device: Image.Image, angle: float) -> tuple[Image.Image, tuple]:
    """The device turned by angle (counter-clockwise), and where the middle of
    its top edge lands in the turned image."""
    if not angle:
        return device, (device.width / 2, 0.0)
    w, h = device.size
    turned = device.rotate(angle, resample=Image.BICUBIC, expand=True)
    t = math.radians(angle)
    return turned, (turned.width / 2 - h / 2 * math.sin(t), turned.height / 2 - h / 2 * math.cos(t))


def pinned(slide: Slide, badge: Image.Image | None, box, top_mid, angle: float) -> None:
    """A chip or badge on the middle of the device's top edge, over the island."""
    if badge is None:
        return
    if angle:
        badge = badge.rotate(angle, resample=Image.BICUBIC, expand=True)
    slide.badge(badge, box[0] + top_mid[0], box[1] + top_mid[1] + 6)


def phone_slide(capture: Image.Image, item: dict, lang: str, background: Image.Image, look: Look) -> Image.Image:
    """1290×2796: headline, subtitle, the iPhone, a chip on its top edge."""
    w, h = IPHONE
    slide = Slide(IPHONE, background, lang, item, look)
    sizes = [164, 156, 148, 140, 132, 124, 116, 108, 102] if look.hero else [148, 140, 132, 124, 116, 108, 102]
    bottom = slide.headline(150, w - 170, sizes, 50, 42)
    badge = chip_layer(slide, 100)
    top = bottom + (100 if badge is None else 140)
    aspect = capture.height / capture.width
    screen_w = min(round(w * 0.71), round((h - top - 90) / aspect / 1.07 / (1.04 if look.tilt else 1)))
    device, top_mid = tilted(iphone(capture, screen_w)[0], look.tilt)
    box = slide.put_device(device, w / 2, top - top_mid[1], screen_w)
    pinned(slide, badge, box, top_mid, look.tilt)
    slide.stickers(box, look.stickers, w)
    slide.signature(34)
    slide.sparkles(5, (14, 30))
    return slide.jpeg()


def tablet_slide(capture: Image.Image, item: dict, lang: str, background: Image.Image, look: Look) -> Image.Image:
    """2064×2752: the same story on the iPad, with more room around the device."""
    w, h = IPAD
    slide = Slide(IPAD, background, lang, item, look)
    sizes = [180, 170, 160, 150, 140, 130, 120] if look.hero else [168, 158, 148, 138, 128, 120]
    bottom = slide.headline(150, w - 440, sizes, 64, 50)
    badge = chip_layer(slide, 124)
    top = bottom + (116 if badge is None else 170)
    aspect = capture.height / capture.width
    tilt = look.tilt * 0.6
    screen_w = min(round(w * 0.68), round((h - top - 110) / aspect / 1.075 / (1.05 if tilt else 1)))
    device, top_mid = tilted(ipad(capture, screen_w)[0], tilt)
    box = slide.put_device(device, w / 2, top - top_mid[1], screen_w)
    pinned(slide, badge, box, top_mid, tilt)
    slide.stickers(box, tuple((k, fx, fy, s * 0.8, a) for k, fx, fy, s, a in look.stickers), w)
    slide.signature(44)
    slide.sparkles(7, (18, 38))
    return slide.jpeg()


MAC_LOOKS = {
    "home": Look((PINK, LILAC), (("heart", 0.95, 0.1, 0.075, -12), ("sparkles", 0.06, 0.84, 0.07, 8)), hero=True),
    "makeup": Look((PINK, LILAC), (("lipstick", -0.025, 0.45, 0.075, 0), ("bow", 1.025, 0.7, 0.065, 10)), glyph="sparkle"),
    "result": Look((PINK, PEACH), (("heart", 1.025, 0.48, 0.07, -12), ("sparkles", -0.025, 0.7, 0.065, 8))),
    "create": Look((LILAC, PINK), (("sparkles", 1.025, 0.3, 0.07, 6), ("chromeheart", -0.025, 0.66, 0.065, -8)),
                   glyph="sparkle"),
    "effects": Look((PEACH, BUTTER), (("camera", -0.025, 0.32, 0.075, -10), ("star", 1.025, 0.68, 0.06, 14)), glyph="check"),
    "share-cover": Look((PEACH, PINK), (("star", -0.025, 0.36, 0.065, -12), ("heart", 1.025, 0.62, 0.07, 12))),
    "cutout": Look((MINT, PINK), (("butterfly", 1.025, 0.3, 0.07, 10), ("star", -0.025, 0.62, 0.06, -10)), glyph="check"),
    "hideFaces": Look((LILAC, MINT), (("heart", 1.025, 0.42, 0.065, 12),), glyph="lock"),
}


def wallpaper(size) -> Image.Image:
    """A brighter Aura for the laptop's desktop, so the screen reads as a screen."""
    w, h = size
    out = gradient((w, h), [(0, (200, 182, 255)), (0.55, (255, 168, 208)), (1, (255, 204, 170))], angle=35)
    for cx, cy, r, alpha in ((0.25, 0.2, 0.45, 0.5), (0.8, 0.85, 0.4, 0.35)):
        m = Image.new("L", (w // 8, h // 8), 0)
        ImageDraw.Draw(m).ellipse(((cx - r) * w / 8, (cy - r) * h / 8, (cx + r) * w / 8, (cy + r) * h / 8),
                                  fill=round(255 * alpha))
        out.alpha_composite(solid(m.filter(ImageFilter.GaussianBlur(r * w / 20)).resize((w, h), Image.BICUBIC), WHITE))
    return out


def mac_slide(capture: Image.Image, item: dict, lang: str, background: Image.Image, look: Look) -> Image.Image:
    """2880×1800: headline over the app's window, or a laptop for the first.
    Chips go on the window's top-right corner: Mac Catalyst puts the tabs in
    the middle of the title bar."""
    w, h = MAC
    slide = Slide(MAC, background, lang, item, look)
    bottom = slide.headline(104, 2400, [164, 154, 144, 134, 124, 116, 108], 56, 26)
    badge = chip_layer(slide, 96)
    top = bottom + 90
    if look.hero:
        width = min(round(w * 0.76), round((h - top - 36) / 0.6224))
        sw = round(width * 0.9 * (1 - 0.036))
        sh = round(sw / 1.545)
        desk = wallpaper((sw, sh))
        win = mac_window(capture, round(sw * 0.88))
        place_centered(desk, with_shadows(win, [(sw * 0.02, 0.3, sw * 0.01)]), sw / 2, sh / 2 + sh * 0.025)
        device = macbook(desk, width)
        box = slide.put_device(device, w / 2, top, width)
    else:
        win_w = min(round(w * 0.78), round((h - top - 70) * capture.width / capture.height))
        box = slide.put_device(mac_window(capture, win_w), w / 2, top, win_w * 0.7)
    if badge is not None:
        slide.badge(badge, box[2] - badge.width * 0.36, box[1] + 4)
    slide.stickers(box, look.stickers, w)
    slide.signature(40)
    slide.sparkles(6, (16, 34))
    return slide.jpeg()


# MARK: - Social and web images (English)

def social_post(captures: Path) -> Image.Image:
    size = (1080, 1350)
    bg = aura_panorama(size, [(PINK, LILAC)])[0]
    item = {"scene": "home", "title": "Make it *glow.*", "subtitle": "AI glow-ups for girls who glow"}
    slide = Slide(size, bg, "en", item, LOOKS["home"])
    bottom = slide.headline(96, 900, [112, 104, 96], 40, 22)
    capture = Image.open(captures / "home.png")
    screen_w = round((1350 - bottom - 230) / (capture.height / capture.width) / 1.064)
    device, _ = iphone(capture, screen_w)
    box = slide.put_device(device, 540, bottom + 60, screen_w)
    slide.stickers(box, (("heart", 1.1, 0.3, 0.17, -12), ("star", -0.1, 0.62, 0.14, 10)), 1080)
    slide.badge(chip("Coming soon to the App Store", LATIN, 78, glyph="sparkle"), 540, 1262)
    slide.sparkles(5, (12, 24))
    return slide.jpeg()


def social_story(captures: Path) -> Image.Image:
    size = (1080, 1920)
    bg = aura_panorama(size, [(PEACH, PINK)])[0]
    item = {"scene": "result", "title": "Say it, *see it*", "subtitle": "“Give me pink hair.” Done."}
    slide = Slide(size, bg, "en", item, LOOKS["result"])
    bottom = slide.headline(250, 900, [112, 104, 96], 42, 24)
    capture = Image.open(captures / "result.png")
    screen_w = round((1920 - bottom - 330) / (capture.height / capture.width) / 1.064)
    device, _ = iphone(capture, screen_w)
    box = slide.put_device(device, 540, bottom + 70, screen_w)
    slide.stickers(box, (("heart", 1.08, 0.28, 0.18, -12), ("sparkles", -0.08, 0.68, 0.16, 8)), 1080)
    slide.badge(chip(f"{APP_NAME} · AI photo editor", LATIN, 84, glyph="sparkle"), 540, 1790)
    slide.sparkles(6, (12, 26))
    return slide.jpeg()


def og_image(captures: Path) -> Image.Image:
    size = (1200, 630)
    bg = aura_panorama(size, [(LILAC, PINK)])[0]
    item = {"scene": "home", "title": "", "subtitle": ""}
    slide = Slide(size, bg, "en", item, LOOKS["home"])
    icon_img = Image.open(ICON).convert("RGB").resize((136, 136), Image.LANCZOS)
    tile = Image.new("RGBA", (136, 136))
    tile.paste(icon_img, (0, 0))
    tile.putalpha(rounded((136, 136), 31))
    place(slide.image, with_shadows(tile, [(12, 0.25, 6)]), 80 - 26, 74 - 26)
    name = Style(LATIN, 104)
    text_block(slide.image, name, [[Word([(APP_NAME, False)], False)]], 80, 248, INK, align="left")
    tag = Style(LATIN, 62, leading=1.0)
    text_block(slide.image, tag, arrange(tag, "Make it *glow.*", 900), 84, 392, INK, align="left")
    sub = Style(LATIN, 32, weight="medium")
    text_block(slide.image, sub, arrange(sub, "AI glow-ups, trends & dreamy art", 900), 84, 500, INK_SOFT, align="left",
               accent_colors=None)
    capture = Image.open(captures / "home.png")
    device, _ = iphone(capture, 250)
    device = device.rotate(-6, resample=Image.BICUBIC, expand=True)
    framed = device_shadows(device, 250)
    pad_x, pad_y = (framed.width - device.width) / 2, (framed.height - device.height) / 2
    place(slide.image, framed, 1200 - device.width - 70 - pad_x, 44 - pad_y)
    place_centered(slide.image, sticker("heart", 92, -12), 1200 - device.width - 60, 150)
    place_centered(slide.image, sparkle(18), 700, 96)
    place_centered(slide.image, sparkle(10, INK, glow=0), 742, 136)
    return slide.jpeg()


# MARK: - Main

def find_capture(base: Path, lang: str, scene: str) -> Path | None:
    names = {scene, scene.replace("-", "_")}
    parts = scene.split("-")
    names.add(parts[0] + "".join(p[:1].upper() + p[1:] for p in parts[1:]))  # share-cover → shareCover
    for folder in (base / lang, base):
        for name in sorted(names):
            path = folder / f"{name}.png"
            if path.exists():
                return path
    return None


def check_lengths(captions: dict) -> None:
    lists = [(lang, items) for lang, items in captions.items() if lang != "mac"]
    lists += [(f"mac/{lang}", items) for lang, items in captions.get("mac", {}).items()]
    for lang, items in lists:
        for item in items:
            for key, limit in (("title", TITLE_LIMIT), ("subtitle", SUBTITLE_LIMIT)):
                text = plain(item.get(key, ""))
                if len(text) > limit:
                    print(f"warning: {lang}/{item['scene']}: {key} has {len(text)} characters (limit {limit}): {text}")
            if item.get("title", "").count("*") != 2:
                print(f"warning: {lang}/{item['scene']}: the title should mark one *accent*")


def clean(folder: Path) -> None:
    folder.mkdir(parents=True, exist_ok=True)
    # Start clean so a shorter or reordered list leaves no stale images.
    for old in folder.glob("[0-9][0-9]-*.jpg"):
        old.unlink()


def save(image: Image.Image, path: Path, size) -> None:
    assert image.size == tuple(size), (path, image.size)
    image.save(path, quality=92, subsampling=0)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("captures", type=Path)
    parser.add_argument("--out", type=Path, help="write under this folder instead of the repo")
    parser.add_argument("--lang", help="comma-separated languages")
    parser.add_argument("--only", default="iphone,ipad,mac,social", help="comma-separated: iphone, ipad, mac, social")
    parser.add_argument("--stand-ins", action="store_true", help="frame iPhone captures where iPad or Mac captures are missing")
    args = parser.parse_args()
    captures: Path = args.captures
    sets = set(args.only.split(","))
    out_store = (args.out / "app-store") if args.out else ROOT / "docs" / "marketing" / "app-store"
    out_social = (args.out / "social") if args.out else ROOT / "docs" / "marketing" / "social"
    out_web = (args.out / "web") if args.out else ROOT / "web" / "assets"

    captions = json.loads(CAPTIONS.read_text(encoding="utf-8"))
    check_lengths(captions)
    mac_captions = captions.pop("mac", {})
    langs = args.lang.split(",") if args.lang else list(captions)

    jobs = [("iphone", IPHONE, captures, "", phone_slide, captions, LOOKS),
            ("ipad", IPAD, captures / "ipad", "ipad", tablet_slide, captions, LOOKS),
            ("mac", MAC, captures / "mac", "mac", mac_slide, mac_captions, MAC_LOOKS)]
    for name, size, base, sub, render, lists, looks in jobs:
        if name not in sets:
            continue
        if not base.exists() and not args.stand_ins:
            print(f"skip the {name} set: no {base}")
            continue
        backgrounds: dict = {}
        for lang in langs:
            items = lists.get(lang)
            if not items:
                continue
            key = tuple(item["scene"] for item in items)
            if key not in backgrounds:
                palettes = [(looks.get(s) or look_for(s, i)).aura for i, s in enumerate(key)]
                backgrounds[key] = aura_panorama(size, palettes)
            folder = out_store / lang / sub if sub else out_store / lang
            wrote = False
            for index, item in enumerate(items, start=1):
                path = find_capture(base, lang, item["scene"]) if base.exists() else None
                stand_in = False
                if path is None and args.stand_ins and name != "iphone":
                    path, stand_in = find_capture(captures, lang, item["scene"]), True
                if path is None:
                    print(f"skip {lang}{'/' + sub if sub else ''}/{item['scene']}: no capture")
                    continue
                if not wrote:
                    clean(folder)
                    wrote = True
                capture = Image.open(path)
                if stand_in:
                    capture = ipad_stand_in(capture) if name == "ipad" else mac_stand_in(capture)
                look = looks.get(item["scene"]) or look_for(item["scene"], index - 1)
                image = render(capture, item, lang, backgrounds[key][index - 1], look)
                save(image, folder / f"{index:02d}-{item['scene']}.jpg", size)
            if wrote:
                print(f"wrote {folder.relative_to(out_store.parent) if args.out else folder.relative_to(ROOT)}")

    if "social" in sets:
        # Social and web images use the English captures when they're in en/.
        english = captures / "en" if (captures / "en" / "home.png").exists() else captures
        if (english / "home.png").exists() and (english / "result.png").exists():
            out_social.mkdir(parents=True, exist_ok=True)
            screens = out_web / "screens"
            screens.mkdir(parents=True, exist_ok=True)
            for scene in ("home", "result", "share", "create", "library", "consent"):
                capture = english / f"{scene}.png"
                if capture.exists():
                    shot = Image.open(capture).convert("RGB")
                    shot = shot.resize((540, round(shot.height * 540 / shot.width)), Image.LANCZOS)
                    shot.save(screens / f"{scene}.jpg", quality=86)
            social_post(english).save(out_social / "post-launch.png")
            social_story(english).save(out_social / "story-launch.png")
            og_image(english).save(out_web / "og-image.png")
            print("wrote the social images and the link preview")
        else:
            print("skip social images: no home.png and result.png")


if __name__ == "__main__":
    main()
