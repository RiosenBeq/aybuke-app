#!/usr/bin/env python3
"""Render Aybuke's app icons and brand board.

    python3 scripts/render-brand-assets.py                   # the app icon: concept C, "Glow Gem"
    python3 scripts/render-brand-assets.py --concept a       # switch every output below to concept A or B
    python3 scripts/render-brand-assets.py --concept-sheets  # redraw the concept comparison images

Writes, from the chosen concept:
  ios/App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon{,-Dark,-Tinted}.png  1024 px for iOS
      (default and dark are opaque RGB; tinted is grayscale on black)
  ios/App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-Mac-{16…1024}.png    Mac Catalyst
  ios/App/Resources/Assets.xcassets/BrandIcon.imageset/BrandIcon.png                512 px, in-app art (invite card)
  web/assets/icon.png                                                               256 px, favicon and site header
  docs/assets/brand/app-icon-1024.png
  docs/assets/brand/app-icon.svg       the same paths as vectors (a start for an Icon Composer file)
  docs/assets/brand/brand-board.png
scripts/marketing-images.py puts app-icon-1024.png into web/assets/og-image.png
(the link preview) the next time it runs.

--concept-sheets writes docs/brand/icon-concepts/: concept-{a,b,c}.png (1024 px),
concept-{a,b,c}-small.png (60 and 29 px, enlarged 4x without smoothing, on light
and dark) and concepts.png (all three on light and dark Home Screens, with their
dark and tinted versions).

The concepts (docs/02-brand-identity.md):
  a  "Spark Cam"    a crisp white digicam whose lens glows pink around a sparkle
  b  "Heart Print"  a sharp-cornered white print whose photo is a glowing heart
  c  "Glow Gem"     a faceted pink heart, cut like a gem, with a white glint

Shapes are exact paths (lines, Bezier curves, circular arcs), drawn at 4x and
downsampled for clean anti-aliasing. Requires Pillow; the brand board uses
macOS's New York Italic.
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path as FilePath

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = FilePath(__file__).resolve().parent.parent
FONTS = ROOT / "ios" / "App" / "Resources" / "Fonts"
ICONSET = ROOT / "ios" / "App" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
BRAND = ROOT / "docs" / "assets" / "brand"
CONCEPT_SHEETS = ROOT / "docs" / "brand" / "icon-concepts"
BRAND_ICON = ROOT / "ios" / "App" / "Resources" / "Assets.xcassets" / "BrandIcon.imageset"
WEB_ICON = ROOT / "web" / "assets" / "icon.png"
SERIF_ITALIC = FilePath("/System/Library/Fonts/NewYorkItalic.ttf")

BLUSH = (247, 193, 217)
PETAL = (248, 224, 234)
INK = (18, 18, 18)
WHITE = (255, 255, 255)
BLACK = (0, 0, 0)
PETAL_WHITE = (250, 240, 246)

# Aura accents: the colorful side of the brand (icon, share cards, template art).
AURA_PINK = (255, 92, 161)
AURA_LILAC = (167, 139, 250)
AURA_PEACH = (255, 170, 120)
AURA_BUTTER = (255, 222, 110)
AURA_MINT = (120, 225, 205)
PLUM = (60, 24, 90)

SCALE = 4
SIZE = 1024
VARIANTS = ("default", "dark", "tinted")


# MARK: - Paths

class Path:
    """Closed shapes made of lines, Bezier curves and circular arcs, in tile
    units (0…1 across the icon, y down). Pillow gets polygons, SVG the curves."""

    def __init__(self) -> None:
        self.subpaths: list[tuple[tuple[float, float], list[tuple]]] = []

    def move(self, p) -> Path:
        self.subpaths.append((p, []))
        return self

    def line(self, p) -> Path:
        self.subpaths[-1][1].append(("L", p))
        return self

    def quad(self, control, p) -> Path:
        self.subpaths[-1][1].append(("Q", control, p))
        return self

    def cubic(self, c1, c2, p) -> Path:
        self.subpaths[-1][1].append(("C", c1, c2, p))
        return self

    def arc(self, center, r: float, a0: float, a1: float) -> Path:
        """Arc from angle a0 to a1 in degrees (increasing = clockwise on screen),
        as cubic curves of at most 90 degrees each."""
        cx, cy = center
        pieces = max(1, math.ceil(abs(a1 - a0) / 90))
        step = (a1 - a0) / pieces
        for index in range(pieces):
            t0, t1 = math.radians(a0 + index * step), math.radians(a0 + (index + 1) * step)
            k = 4 / 3 * math.tan((t1 - t0) / 4)
            p0 = (cx + r * math.cos(t0), cy + r * math.sin(t0))
            p3 = (cx + r * math.cos(t1), cy + r * math.sin(t1))
            self.cubic((p0[0] - k * r * math.sin(t0), p0[1] + k * r * math.cos(t0)),
                       (p3[0] + k * r * math.sin(t1), p3[1] - k * r * math.cos(t1)), p3)
        return self

    def add(self, other: Path) -> Path:
        self.subpaths.extend(other.subpaths)
        return self

    def map(self, transform) -> Path:
        out = Path()
        for start, segments in self.subpaths:
            out.subpaths.append((transform(start), [(s[0],) + tuple(transform(p) for p in s[1:]) for s in segments]))
        return out

    def rotated(self, degrees: float, center) -> Path:
        return self.map(lambda p: rotate_point(p, degrees, center))

    def moved(self, dx: float, dy: float) -> Path:
        return self.map(lambda p: (p[0] + dx, p[1] + dy))

    def polygons(self, steps: int = 32) -> list[list[tuple[float, float]]]:
        result = []
        for start, segments in self.subpaths:
            points = [start]
            for segment in segments:
                p0 = points[-1]
                if segment[0] == "L":
                    points.append(segment[1])
                    continue
                for i in range(1, steps + 1):
                    t, m = i / steps, 1 - i / steps
                    if segment[0] == "Q":
                        c, p = segment[1], segment[2]
                        points.append(tuple(m * m * p0[j] + 2 * m * t * c[j] + t * t * p[j] for j in (0, 1)))
                    else:
                        c1, c2, p = segment[1], segment[2], segment[3]
                        points.append(tuple(m ** 3 * p0[j] + 3 * m * m * t * c1[j] + 3 * m * t * t * c2[j] + t ** 3 * p[j]
                                            for j in (0, 1)))
            result.append(points)
        return result

    def svg(self, size: float) -> str:
        def xy(p) -> str:
            return f"{p[0] * size:.1f} {p[1] * size:.1f}"
        parts = []
        for start, segments in self.subpaths:
            parts.append("M" + xy(start))
            parts.extend(segment[0] + " ".join(xy(p) for p in segment[1:]) for segment in segments)
            parts.append("Z")
        return "".join(parts)


def rotate_point(p, degrees: float, center) -> tuple[float, float]:
    a = math.radians(degrees)
    dx, dy = p[0] - center[0], p[1] - center[1]
    return (center[0] + dx * math.cos(a) - dy * math.sin(a), center[1] + dx * math.sin(a) + dy * math.cos(a))


def rect(x0, y0, x1, y1) -> Path:
    return Path().move((x0, y0)).line((x1, y0)).line((x1, y1)).line((x0, y1))


def polygon(points) -> Path:
    path = Path().move(points[0])
    for p in points[1:]:
        path.line(p)
    return path


def circle(center, r: float) -> Path:
    return Path().move((center[0] + r, center[1])).arc(center, r, 0, 360)


def sparkle(center, r: float, inner: float = 0.28) -> Path:
    """The app's four-point sparkle (`SparkleShape`): concave sides, needle points.
    A smaller `inner` makes thinner, sharper points."""
    cx, cy = center
    k = inner * r
    return (Path().move((cx, cy - r))
            .quad((cx + k, cy - k), (cx + r, cy)).quad((cx + k, cy + k), (cx, cy + r))
            .quad((cx - k, cy + k), (cx - r, cy)).quad((cx - k, cy - k), (cx, cy - r)))


class HeartShape:
    """A crisp heart: two circular lobes, straight sides down to a sharp point
    and a sharp notch between the lobes. Local units: the heart is 1 wide."""

    lobe, spread, tip = 0.27, 0.23, 0.68

    def __init__(self, center, width: float) -> None:
        self.center, self.k = center, width / (2 * (self.spread + self.lobe))
        self.notch_y = -math.sqrt(self.lobe ** 2 - self.spread ** 2)
        theta = math.atan2(self.tip, -self.spread)
        # Right lobe, from the notch over the top to where the straight side leaves it.
        self.a_notch = math.degrees(math.atan2(self.notch_y, -self.spread)) + 360
        self.a_side = math.degrees(theta - math.acos(self.lobe / math.hypot(self.spread, self.tip))) + 360

    def point(self, x: float, y: float) -> tuple[float, float]:
        """Local → tile units, centred on the heart's bounding box."""
        return (self.center[0] + x * self.k, self.center[1] + (y - (self.tip - self.lobe) / 2) * self.k)

    def path(self) -> Path:
        r = self.lobe * self.k
        side = math.radians(self.a_side)
        path = Path().move(self.point(0, self.notch_y))
        path.arc(self.point(self.spread, 0), r, self.a_notch, self.a_side)
        path.line(self.point(0, self.tip))
        path.line(self.point(-(self.spread + self.lobe * math.cos(side)), self.lobe * math.sin(side)))
        return path.arc(self.point(-self.spread, 0), r, 540 - self.a_side, 540 - self.a_notch)

    def facets(self, per_lobe: int) -> list[tuple[float, float]]:
        """Outline as a polygon (clockwise): notch, right lobe, tip, left lobe."""
        right = []
        for i in range(per_lobe + 1):
            a = math.radians(self.a_notch + (self.a_side - self.a_notch) * i / per_lobe)
            right.append((self.spread + self.lobe * math.cos(a), self.lobe * math.sin(a)))
        local = right + [(0, self.tip)] + [(-x, y) for x, y in reversed(right[1:])]
        return [self.point(x, y) for x, y in local]


# MARK: - Canvases

class Gradient:
    """Linear gradient through (offset, rgb) stops, from `start` to `end` (tile units)."""

    def __init__(self, stops, start, end) -> None:
        self.stops, self.start, self.end = stops, start, end


def color_at(stops, t: float) -> tuple[int, int, int]:
    if t <= stops[0][0]:
        return stops[0][1]
    for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
        if t <= p1:
            u = (t - p0) / (p1 - p0)
            return tuple(round(c0[i] + (c1[i] - c0[i]) * u) for i in range(3))
    return stops[-1][1]


def falloff(d: float) -> float:
    """Glow strength at distance d (0 = centre, 1 = edge): a smooth step down to zero."""
    return 0.0 if d >= 1 else 1 - (3 * d * d - 2 * d * d * d)


class Raster:
    """Draws into a supersampled RGBA image; `result()` downsamples it."""

    def __init__(self, size: int = SIZE * SCALE) -> None:
        self.px = size
        self.image = Image.new("RGBA", (size, size), BLACK + (255,))
        self.profiles: dict[float, Image.Image] = {}

    def mask(self, path: Path) -> Image.Image:
        mask = Image.new("L", (self.px, self.px), 0)
        draw = ImageDraw.Draw(mask)
        for points in path.polygons():
            draw.polygon([(x * self.px, y * self.px) for x, y in points], fill=255)
        return mask

    def gradient(self, paint: Gradient) -> Image.Image:
        small = 256
        (sx, sy), (ex, ey) = paint.start, paint.end
        dx, dy = ex - sx, ey - sy
        length = dx * dx + dy * dy
        image = Image.new("RGB", (small, small))
        image.putdata([color_at(paint.stops, (((x + 0.5) / small - sx) * dx + ((y + 0.5) / small - sy) * dy) / length)
                       for y in range(small) for x in range(small)])
        return image.resize((self.px, self.px), Image.BICUBIC)

    def composite(self, paint, alpha: Image.Image) -> None:
        box = alpha.getbbox()
        if box is None:
            return
        if isinstance(paint, Gradient):
            layer = self.gradient(paint).crop(box).convert("RGBA")
        else:
            layer = Image.new("RGBA", (box[2] - box[0], box[3] - box[1]), paint + (255,))
        layer.putalpha(alpha.crop(box))
        self.image.alpha_composite(layer, dest=box[:2])

    def background(self, paint) -> None:
        self.composite(paint, Image.new("L", (self.px, self.px), 255))

    def fill(self, path: Path, paint, clip: Path | None = None) -> None:
        mask = self.mask(path)
        if clip is not None:
            mask = ImageChops.multiply(mask, self.mask(clip))
        self.composite(paint, mask)

    def glow(self, center, radius: float, color, alpha: float, clip: Path | None = None) -> None:
        if alpha not in self.profiles:
            size = 256
            profile = Image.new("L", (size, size))
            profile.putdata([round(255 * alpha * falloff(math.hypot((x + 0.5) / 128 - 1, (y + 0.5) / 128 - 1)))
                             for y in range(size) for x in range(size)])
            self.profiles[alpha] = profile
        r = radius * self.px
        mask = Image.new("L", (self.px, self.px), 0)
        mask.paste(self.profiles[alpha].resize((round(2 * r), round(2 * r)), Image.BICUBIC),
                   (round(center[0] * self.px - r), round(center[1] * self.px - r)))
        if clip is not None:
            mask = ImageChops.multiply(mask, self.mask(clip))
        self.composite(color, mask)

    def shadow(self, path: Path, offset, blur: float, color, alpha: float) -> None:
        mask = self.mask(path.moved(*offset)).filter(ImageFilter.GaussianBlur(blur * self.px))
        self.composite(color, mask.point(lambda value: round(value * alpha)))

    def result(self, size: int = SIZE) -> Image.Image:
        return self.image.resize((size, size), Image.LANCZOS).convert("RGB")


def hex_color(rgb) -> str:
    return "#{:02X}{:02X}{:02X}".format(*rgb)


class Vector:
    """The same drawing calls as `Raster`, written out as SVG."""

    def __init__(self, size: int = SIZE) -> None:
        self.size = size
        self.defs: list[str] = []
        self.body: list[str] = []
        self.count = 0

    def _id(self, prefix: str) -> str:
        self.count += 1
        return f"{prefix}{self.count}"

    def _paint(self, paint) -> str:
        if not isinstance(paint, Gradient):
            return hex_color(paint)
        gradient_id, s = self._id("gradient"), self.size
        stops = "".join(f'<stop offset="{t:g}" stop-color="{hex_color(color)}"/>' for t, color in paint.stops)
        self.defs.append(f'<linearGradient id="{gradient_id}" gradientUnits="userSpaceOnUse" '
                         f'x1="{paint.start[0] * s:.1f}" y1="{paint.start[1] * s:.1f}" '
                         f'x2="{paint.end[0] * s:.1f}" y2="{paint.end[1] * s:.1f}">{stops}</linearGradient>')
        return f"url(#{gradient_id})"

    def _clip(self, clip: Path | None) -> str:
        if clip is None:
            return ""
        clip_id = self._id("clip")
        self.defs.append(f'<clipPath id="{clip_id}"><path d="{clip.svg(self.size)}"/></clipPath>')
        return f' clip-path="url(#{clip_id})"'

    def background(self, paint) -> None:
        self.body.append(f'<rect width="{self.size}" height="{self.size}" fill="{self._paint(paint)}"/>')

    def fill(self, path: Path, paint, clip: Path | None = None) -> None:
        # A hairline stroke in the same paint hides anti-aliasing seams between facets.
        paint = self._paint(paint)
        self.body.append(f'<path d="{path.svg(self.size)}" fill="{paint}" stroke="{paint}" stroke-width="1" '
                         f'stroke-linejoin="round"{self._clip(clip)}/>')

    def glow(self, center, radius: float, color, alpha: float, clip: Path | None = None) -> None:
        glow_id, s = self._id("glow"), self.size
        stops = "".join(f'<stop offset="{d:g}" stop-color="{hex_color(color)}" stop-opacity="{alpha * falloff(d):.3f}"/>'
                        for d in (i / 8 for i in range(9)))
        self.defs.append(f'<radialGradient id="{glow_id}">{stops}</radialGradient>')
        self.body.append(f'<circle cx="{center[0] * s:.1f}" cy="{center[1] * s:.1f}" r="{radius * s:.1f}" '
                         f'fill="url(#{glow_id})"{self._clip(clip)}/>')

    def shadow(self, path: Path, offset, blur: float, color, alpha: float) -> None:
        filter_id = self._id("blur")
        self.defs.append(f'<filter id="{filter_id}" x="-50%" y="-50%" width="200%" height="200%">'
                         f'<feGaussianBlur stdDeviation="{blur * self.size:.1f}"/></filter>')
        self.body.append(f'<path d="{path.moved(*offset).svg(self.size)}" fill="{hex_color(color)}" '
                         f'fill-opacity="{alpha:g}" filter="url(#{filter_id})"/>')

    def document(self, comment: str) -> str:
        lines = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.size}" height="{self.size}" '
                 f'viewBox="0 0 {self.size} {self.size}">', f"  <!-- {comment} -->",
                 "  <defs>", *(f"    {d}" for d in self.defs), "  </defs>", *(f"  {b}" for b in self.body), "</svg>", ""]
        return "\n".join(lines)


# MARK: - Concepts

def dark_tile(c) -> None:
    """Ink tile with the lilac and pink glows used by every dark variant."""
    c.background(INK)
    c.glow((0.1, 0.06), 0.62, AURA_LILAC, 0.32)
    c.glow((0.94, 0.96), 0.56, AURA_PINK, 0.32)


def draw_spark_cam(c, variant: str) -> None:
    """A, "Spark Cam": a crisp white digicam whose lens glows pink on plum
    around a sparkle. The camera = Retro Cam and Photo Booth; the sparkle = AI."""
    if variant == "default":
        c.background(Gradient([(0, (255, 204, 228)), (0.55, (255, 143, 194)), (1, AURA_PINK)], (0.15, 0), (0.85, 1)))
        c.glow((0.86, 0.1), 0.42, AURA_BUTTER, 0.55)
        c.glow((0.12, 0.92), 0.4, AURA_LILAC, 0.35)
        body, ring, glass, flash, shutter = WHITE, INK, PLUM, AURA_BUTTER, AURA_PINK
        glows = (AURA_PINK, AURA_LILAC)
    elif variant == "dark":
        dark_tile(c)
        body, ring, glass, flash, shutter = PETAL_WHITE, INK, PLUM, AURA_BUTTER, AURA_PINK
        glows = (AURA_PINK, AURA_LILAC)
    else:
        c.background(BLACK)
        body, ring, glass, flash, shutter = WHITE, (34, 34, 34), BLACK, (170, 170, 170), (120, 120, 120)
        glows = ((130, 130, 130), (80, 80, 80))
    shape = rect(0.15, 0.335, 0.85, 0.765)
    hump = rect(0.22, 0.285, 0.43, 0.34)
    if variant != "tinted":
        c.shadow(Path().add(shape).add(hump), (0, 0.022), 0.03,
                 PLUM if variant == "default" else BLACK, 0.28 if variant == "default" else 0.5)
    c.fill(shape, body)
    c.fill(hump, body)
    c.fill(rect(0.63, 0.30, 0.76, 0.34), shutter)
    c.fill(rect(0.67, 0.375, 0.785, 0.44), flash)
    lens = (0.5, 0.56)
    c.fill(circle(lens, 0.172), ring)
    window = circle(lens, 0.136)
    c.fill(window, glass)
    c.glow(lens, 0.2, glows[0], 0.95, clip=window)
    c.glow((0.44, 0.62), 0.12, glows[1], 0.6, clip=window)
    c.fill(sparkle(lens, 0.108, inner=0.2), WHITE)


def draw_heart_print(c, variant: str) -> None:
    """B, "Heart Print": a sharp-cornered white print, tilted like a photo on a
    mood board, whose photo is a heart glowing pink on plum around a sparkle."""
    if variant == "default":
        c.background(Gradient([(0, AURA_LILAC), (0.55, AURA_PINK), (1, AURA_PEACH)], (0.1, 0), (0.9, 1)))
        c.glow((0.06, 0.02), 0.45, WHITE, 0.3)
        c.glow((0.96, 0.98), 0.42, AURA_BUTTER, 0.55)
        paper, photo, glows = WHITE, PLUM, (AURA_PINK, AURA_LILAC)
    elif variant == "dark":
        dark_tile(c)
        paper, photo, glows = PETAL_WHITE, PLUM, (AURA_PINK, AURA_LILAC)
    else:
        c.background(BLACK)
        paper, photo, glows = WHITE, BLACK, ((130, 130, 130), (80, 80, 80))
    tilt, pivot = -8, (0.5, 0.5)
    card = rect(0.2, 0.15, 0.8, 0.85).rotated(tilt, pivot)
    heart_center = (0.5, 0.435)
    window = HeartShape(heart_center, 0.5).path().rotated(tilt, pivot)
    center = rotate_point(heart_center, tilt, pivot)
    if variant != "tinted":
        c.shadow(card, (0, 0.024), 0.032, PLUM if variant == "default" else BLACK, 0.3 if variant == "default" else 0.5)
    c.fill(card, paper)
    c.fill(window, photo)
    c.glow(center, 0.3, glows[0], 0.95, clip=window)
    c.glow(rotate_point((0.36, 0.56), tilt, pivot), 0.17, glows[1], 0.5, clip=window)
    c.fill(sparkle(center, 0.115, inner=0.2), WHITE)
    c.fill(sparkle((0.855, 0.145), 0.062, inner=0.24), WHITE)
    c.fill(sparkle((0.925, 0.25), 0.026, inner=0.26), WHITE)


GEM_RAMP = [(0, (128, 24, 96)), (0.28, (200, 40, 122)), (0.55, AURA_PINK), (0.75, (255, 146, 194)),
            (0.9, (255, 196, 222)), (1, (255, 226, 238))]
# Tinted icons read best with a bright foreground: the system colours it by luminance.
GEM_RAMP_GRAY = [(0, (92, 92, 92)), (0.28, (132, 132, 132)), (0.55, (176, 176, 176)), (0.75, (208, 208, 208)),
                 (0.9, (232, 232, 232)), (1, (246, 246, 246))]


def draw_glow_gem(c, variant: str) -> None:
    """C, "Glow Gem": a pink heart cut like a gem — straight facets, a sharp tip
    and notch — lit from the top left, with a white glint on its glowing table
    and two sparkles beside it. The heart and sparkles are the app's success
    burst; the facets catch the light ("Make it glow")."""
    gray = variant == "tinted"
    if variant == "default":
        c.background(Gradient([(0, AURA_LILAC), (0.6, (205, 160, 245)), (1, (255, 170, 205))], (0.1, 0), (0.9, 1)))
        c.glow((0.5, 0.52), 0.6, WHITE, 0.4)
    elif variant == "dark":
        dark_tile(c)
        c.glow((0.5, 0.56), 0.46, AURA_PINK, 0.4)
    else:
        c.background(BLACK)
        c.glow((0.5, 0.56), 0.46, (110, 110, 110), 0.35)
    heart = HeartShape((0.5, 0.535), 0.7)
    outline = heart.facets(per_lobe=4)
    cx, cy = heart.point(0, 0.1)
    table = [(cx + (x - cx) * 0.58, cy + (y - cy) * 0.58) for x, y in outline]
    if variant == "default":
        c.shadow(polygon(outline), (0, 0.026), 0.032, PLUM, 0.32)
    ramp = GEM_RAMP_GRAY if gray else GEM_RAMP
    light = (-0.5, -0.86)  # from the top left
    for i in range(len(outline)):
        a, b = outline[i], outline[(i + 1) % len(outline)]
        ia, ib = table[i], table[(i + 1) % len(table)]
        ex, ey = b[0] - a[0], b[1] - a[1]
        lit = 0.5 + 0.5 * (ey * light[0] - ex * light[1]) / math.hypot(ex, ey)  # outward normal · light
        # Each facet is two triangles, one a touch lighter: the sparkle of a cut stone.
        c.fill(polygon([a, b, ib]), color_at(ramp, min(1, lit + 0.06)))
        c.fill(polygon([a, ib, ia]), color_at(ramp, max(0, lit - 0.05)))
    top = polygon(table)
    stops = [(0, (214, 214, 214)), (1, (170, 170, 170))] if gray else [(0, (255, 160, 204)), (1, (255, 80, 148))]
    c.fill(top, Gradient(stops, heart.point(-0.3, -0.25), heart.point(0.3, 0.45)))
    c.glow(heart.point(-0.12, -0.02), 0.2, WHITE if gray else (255, 236, 245), 0.75, clip=top)
    c.fill(sparkle(heart.point(-0.16, 0), 0.07, inner=0.22), WHITE)
    c.fill(sparkle((0.845, 0.16), 0.055, inner=0.24), WHITE)
    c.fill(sparkle((0.915, 0.255), 0.024, inner=0.26), WHITE)


CONCEPTS = {
    "a": ("Spark Cam", draw_spark_cam),
    "b": ("Heart Print", draw_heart_print),
    "c": ("Glow Gem", draw_glow_gem),
}
# The app's icon. `--concept` overrides it for one run; change it here to switch
# for good (the concept sheets mark this one as chosen).
CHOSEN = "c"


def icon(concept: str, variant: str = "default") -> Image.Image:
    canvas = Raster()
    CONCEPTS[concept][1](canvas, variant)
    return canvas.result()


def icon_svg(concept: str) -> str:
    canvas = Vector()
    CONCEPTS[concept][1](canvas, "default")
    name = CONCEPTS[concept][0]
    return canvas.document(f'Aybuke app icon, concept {concept.upper()} "{name}". Written by '
                           f"scripts/render-brand-assets.py from the same paths as the PNGs; edit the script, not this file.")


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


# MARK: - Brand board and concept sheets

def radial(size: int, center: tuple[float, float], radius: float, color: tuple, alpha: float) -> Image.Image:
    """Soft radial glow layer (RGBA)."""
    layer = Image.new("RGBA", (size, size), color + (0,))
    mask = Image.new("L", (size, size), 0)
    cx, cy = center
    ImageDraw.Draw(mask).ellipse((cx - radius, cy - radius, cx + radius, cy + radius), fill=int(255 * alpha))
    layer.putalpha(mask.filter(ImageFilter.GaussianBlur(radius * 0.45)))
    return layer


def draw_sparkle(draw: ImageDraw.ImageDraw, center: tuple[float, float], radius: float, fill: tuple) -> None:
    """The four-point sparkle in pixel coordinates, for boards and sheets."""
    for points in sparkle(center, radius).polygons():
        draw.polygon(points, fill=fill)


def font(cut: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONTS / f"Poppins-{cut}.ttf"), size)


def serif(size: int) -> ImageFont.FreeTypeFont:
    if SERIF_ITALIC.exists():
        return ImageFont.truetype(str(SERIF_ITALIC), size)
    return font("SemiBold", size)


def masked(art: Image.Image, side: int) -> tuple[Image.Image, Image.Image]:
    """The icon at `side` px with an iOS-like rounded mask (drawn at 4x)."""
    mask = Image.new("L", (side * 4, side * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, side * 4 - 1, side * 4 - 1), radius=round(side * 4 * 0.2237), fill=255)
    return art.resize((side, side), Image.LANCZOS), mask.resize((side, side), Image.LANCZOS)


def brand_board(app_icon: Image.Image) -> Image.Image:
    w, h = 1600, 900
    board = Image.new("RGBA", (w, h), PETAL + (255,))
    board.alpha_composite(radial(w if w > h else h, (260, 200), 520, WHITE, 0.6).crop((0, 0, w, h)))
    board.alpha_composite(radial(w if w > h else h, (1450, 820), 520, BLUSH, 0.8).crop((0, 0, w, h)))
    draw = ImageDraw.Draw(board)

    # Icon with an iOS-like squircle mask and a soft shadow.
    side = 360
    ix, iy = 140, 170
    shadow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((ix, iy + 24, ix + side, iy + side + 24), radius=int(side * 0.225), fill=INK + (60,))
    board.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(28)))
    art, mask = masked(app_icon, side)
    board.paste(art, (ix, iy), mask)

    x = 600
    draw.text((x, 150), "Aybuke", font=font("ExtraBold", 150), fill=INK)
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

    draw_sparkle(draw, (1480, 120), 46, WHITE)
    draw_sparkle(draw, (1530, 205), 22, INK)
    return board.convert("RGB")


def tinted_preview(gray: Image.Image, tint=(255, 122, 182)) -> Image.Image:
    """Roughly how iOS shows a tinted icon: the grayscale art coloured by the tint."""
    tint_layer = Image.new("RGB", gray.size, tint)
    base = Image.new("RGB", gray.size, tuple(round(v * 0.14) for v in tint))
    return Image.composite(tint_layer, base, gray.convert("L"))


def small_sheet(art: Image.Image) -> Image.Image:
    """60 and 29 px, each enlarged 4x with nearest-neighbour, on light and on dark."""
    pad, gap = 24, 28
    width = pad * 2 + 60 * 4 + gap + 29 * 4
    height = pad * 2 + 60 * 4 * 2 + gap
    sheet = Image.new("RGB", (width, height), (242, 242, 246))
    sheet.paste((28, 28, 30), (0, height // 2, width, height))
    for row, top in enumerate((pad, pad + 60 * 4 + gap)):
        left = pad
        for side in (60, 29):
            image, mask = masked(art, side)
            sheet.paste(image.resize((side * 4, side * 4), Image.NEAREST), (left, top + (60 - side) * 2),
                        mask.resize((side * 4, side * 4), Image.NEAREST))
            left += side * 4 + gap
    return sheet


def wallpaper(width: int, height: int, top: tuple, bottom: tuple, glow: tuple) -> Image.Image:
    image = Image.composite(Image.new("RGB", (width, height), bottom), Image.new("RGB", (width, height), top),
                            Image.linear_gradient("L").resize((width, height))).convert("RGBA")
    image.alpha_composite(radial(max(width, height), (width * 0.85, height * 0.2), height * 0.6, glow, 0.5).crop((0, 0, width, height)))
    return image


def concepts_sheet(icons: dict[str, dict[str, Image.Image]]) -> Image.Image:
    """The three concepts on a light and a dark Home Screen, then their dark
    and tinted versions."""
    width, column = 1320, 440
    light = wallpaper(width, 430, (252, 238, 246), (234, 226, 250), WHITE)
    dark = wallpaper(width, 760, (40, 30, 52), (10, 10, 14), (110, 60, 120))
    sheet = Image.new("RGBA", (width, 430 + 760), WHITE + (255,))
    sheet.alpha_composite(light, (0, 0))
    sheet.alpha_composite(dark, (0, 430))
    draw = ImageDraw.Draw(sheet)
    small, label = font("SemiBold", 24), font("SemiBold", 28)
    draw.text((32, 24), "Light Home Screen", font=small, fill=(92, 84, 87))
    draw.text((32, 454), "Dark Home Screen", font=small, fill=(190, 182, 196))
    draw.text((32, 870), "Dark and tinted icons (iOS 18 and later; tinted shown in pink)", font=small, fill=(190, 182, 196))
    for index, key in enumerate(CONCEPTS):
        name = CONCEPTS[key][0]
        center = column // 2 + index * column
        title = f"{key.upper()} · {name}"
        for top, ink in ((90, INK), (520, (248, 244, 248))):
            art, mask = masked(icons[key]["default"], 220)
            sheet.paste(art, (center - 110, top), mask)
            draw.text((center - draw.textlength(title, font=label) / 2, top + 236), title, font=label, fill=ink)
        for offset, variant, caption in ((-150, "dark", "Dark"), (20, "tinted", "Tinted")):
            art = icons[key][variant] if variant == "dark" else tinted_preview(icons[key][variant])
            art, mask = masked(art, 130)
            sheet.paste(art, (center + offset, 930), mask)
            draw.text((center + offset + 65 - draw.textlength(caption, font=small) / 2, 1072), caption, font=small, fill=(190, 182, 196))
        if key == CHOSEN:
            pill = "Chosen"
            pw = draw.textlength(pill, font=small) + 36
            for y in (378, 808):
                draw.rounded_rectangle((center - pw / 2, y, center + pw / 2, y + 40), radius=20, fill=BLUSH)
                draw.text((center - pw / 2 + 18, y + 5), pill, font=small, fill=INK)
    return sheet.convert("RGB")


def render_concept_sheets() -> None:
    CONCEPT_SHEETS.mkdir(parents=True, exist_ok=True)
    icons = {key: {variant: icon(key, variant) for variant in VARIANTS} for key in CONCEPTS}
    for key, variants in icons.items():
        variants["default"].save(CONCEPT_SHEETS / f"concept-{key}.png")
        small_sheet(variants["default"]).save(CONCEPT_SHEETS / f"concept-{key}-small.png")
    concepts_sheet(icons).save(CONCEPT_SHEETS / "concepts.png")
    print(f"Rendered the icon concepts into {CONCEPT_SHEETS.relative_to(ROOT)}/.")


def render_app_icons(concept: str) -> None:
    default = icon(concept, "default")
    default.save(ICONSET / "AppIcon.png")
    icon(concept, "dark").save(ICONSET / "AppIcon-Dark.png")
    icon(concept, "tinted").convert("L").save(ICONSET / "AppIcon-Tinted.png")
    mac = mac_icon(default)
    for size in MAC_ICON_SIZES:
        mac.resize((size, size), Image.LANCZOS).save(ICONSET / f"AppIcon-Mac-{size}.png")
    default.save(BRAND / "app-icon-1024.png")
    (BRAND / "app-icon.svg").write_text(icon_svg(concept), encoding="utf-8")
    default.resize((512, 512), Image.LANCZOS).save(BRAND_ICON / "BrandIcon.png")
    default.resize((256, 256), Image.LANCZOS).save(WEB_ICON)
    brand_board(default).save(BRAND / "brand-board.png")
    print(f'Rendered app icons (concept {concept.upper()}, "{CONCEPTS[concept][0]}") and the brand board.')


def main() -> None:
    parser = argparse.ArgumentParser(description="Render Aybuke's app icons and brand board.")
    parser.add_argument("--concept", choices=sorted(CONCEPTS), default=CHOSEN,
                        help=f"icon concept for every output (default: {CHOSEN}, the app's icon)")
    parser.add_argument("--concept-sheets", action="store_true",
                        help="only redraw the concept comparison images in docs/brand/icon-concepts/")
    args = parser.parse_args()
    if args.concept_sheets:
        render_concept_sheets()
    else:
        render_app_icons(args.concept)


if __name__ == "__main__":
    main()
