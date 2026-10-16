#!/usr/bin/env python3
"""Render Aybuke's app icons and brand board.

    python3 scripts/render-brand-assets.py                   # the app icon: concept D, "Aura Lens"
    python3 scripts/render-brand-assets.py --concept e       # switch every output below to another concept (a–e)
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
  docs/assets/brand/wordmark{,-gradient}.{svg,png}  the "aybuke" logotype, ink and plum-pink-peach
  ios/App/Resources/Assets.xcassets/Wordmark.imageset/Wordmark.svg                 the same, a template vector
  ios/App/DesignSystem/Components/WordmarkGlyphs.swift                              the same, per letter (the launch splash)
  ios/App/Resources/Assets.xcassets/LaunchIcon.imageset/LaunchIcon@{2,3}x.png      the launch screen's icon
  (--wordmark redraws only these and the brand board, from app-icon-1024.png)
scripts/marketing-images.py puts app-icon-1024.png into web/assets/og-image.png
(the link preview) the next time it runs.

--concept-sheets writes docs/brand/icon-concepts/: concept-{a…e}.png (1024 px),
concept-{a…e}-small.png (60 and 29 px, enlarged 4x without smoothing, on light
and dark) and concepts.png (all five on light and dark Home Screens, with their
dark and tinted versions).

The concepts (docs/02-brand-identity.md):
  a  "Spark Cam"    a crisp white digicam whose lens glows pink around a sparkle
  b  "Heart Print"  a sharp-cornered white print whose photo is a glowing heart
  c  "Glow Gem"     a faceted pink heart, cut like a gem, with a white glint
  d  "Aura Lens"    a liquid-glass lens glowing white-hot through blush to magenta
                    in a thin iridescent ring, with a sparkle glinting on its rim
  e  "Holo Heart"   a puffy glass heart glowing from within, with an iridescent rim

Shapes are exact paths (lines, Bezier curves, circular arcs), drawn at 4x and
downsampled for clean anti-aliasing; glows, soft light and the iridescent sweeps
(conic gradients, drawn as thin wedges) are layered over them. Requires Pillow
(no numpy); the brand board uses macOS's New York Italic.
"""

from __future__ import annotations

import argparse
import json
import math
import struct
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
    units (0…1 across the icon, y down). Pillow gets polygons, SVG the curves.
    An even-odd path leaves a hole wherever its subpaths overlap (rings, crescents)."""

    def __init__(self, evenodd: bool = False) -> None:
        self.subpaths: list[tuple[tuple[float, float], list[tuple]]] = []
        self.evenodd = evenodd

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
        out = Path(self.evenodd)
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


def even_odd(*paths: Path) -> Path:
    """One path from several, filled even-odd: where they overlap is a hole."""
    out = Path(evenodd=True)
    for path in paths:
        out.add(path)
    return out


def ring(center, outer: float, inner: float) -> Path:
    return even_odd(circle(center, outer), circle(center, inner))


def arc_band(center, outer: float, inner: float, a0: float, a1: float) -> Path:
    """A piece of a ring, from angle a0 to a1 (degrees, clockwise on screen)."""
    cx, cy = center
    path = Path().move((cx + outer * math.cos(math.radians(a0)), cy + outer * math.sin(math.radians(a0))))
    path.arc(center, outer, a0, a1).line((cx + inner * math.cos(math.radians(a1)), cy + inner * math.sin(math.radians(a1))))
    return path.arc(center, inner, a1, a0)


def ellipse(center, rx: float, ry: float, degrees: float = 0) -> Path:
    return circle((0, 0), 1).map(lambda p: rotate_point((center[0] + p[0] * rx, center[1] + p[1] * ry), degrees, center))


def puffy_heart(center, width: float) -> Path:
    """A soft, rounded heart: circular lobes curving into a rounded notch, full
    sides and a gently rounded tip. Centred on its bounding box."""
    k = width / 2.028
    r, notch, ease = 0.514, 193.5, 22
    top, tip = -0.38 - r, 1.0

    def point(p):
        return (center[0] + p[0] * k, center[1] + (p[1] - (top + tip) / 2) * k)

    def on_lobe(x, angle):
        a = math.radians(angle)
        return point((x + r * math.cos(a), -0.38 + r * math.sin(a)))

    path = Path().move(on_lobe(0.5, notch + ease))
    path.arc(point((0.5, -0.38)), r * k, notch + ease, 360)
    path.cubic(point((1.014, 0.02)), point((0.52, 0.56)), point((0.06, 0.96)))
    path.quad(point((0, 1.012)), point((-0.06, 0.96)))
    path.cubic(point((-0.52, 0.56)), point((-1.014, 0.02)), point((-1.014, -0.38)))
    path.arc(point((-0.5, -0.38)), r * k, 180, 540 - notch - ease)
    return path.quad(point((0, -0.475)), on_lobe(0.5, notch + ease))


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
    """Linear gradient through (offset, colour) stops, from `start` to `end` (tile
    units). Colours are RGB, or RGBA where the paint fades out."""

    def __init__(self, stops, start, end) -> None:
        self.stops, self.start, self.end = stops, start, end

    def offset(self, x: float, y: float) -> float:
        (sx, sy), (ex, ey) = self.start, self.end
        dx, dy = ex - sx, ey - sy
        return ((x - sx) * dx + (y - sy) * dy) / (dx * dx + dy * dy)


class RadialGradient:
    """Gradient through (offset, colour) stops from `center` (0) out to `radius` (1)."""

    def __init__(self, stops, center, radius: float) -> None:
        self.stops, self.center, self.radius = stops, center, radius

    def offset(self, x: float, y: float) -> float:
        return math.hypot(x - self.center[0], y - self.center[1]) / self.radius


class ConicGradient:
    """Sweep gradient through (offset, colour) stops once around `center`, starting
    at `angle` degrees (0 = right, increasing clockwise on screen, like `Path.arc`).
    Drawn as many thin wedges; the stops should end where they start."""

    wedges = 720

    def __init__(self, stops, center, angle: float = 0) -> None:
        self.stops, self.center, self.angle = stops, center, angle


def rgba(color) -> tuple[int, int, int, int]:
    return tuple(color) if len(color) == 4 else tuple(color) + (255,)


def color_at(stops, t: float) -> tuple:
    if any(len(color) == 4 for _, color in stops):
        stops = [(offset, rgba(color)) for offset, color in stops]
    if t <= stops[0][0]:
        return stops[0][1]
    for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
        if t <= p1:
            u = (t - p0) / (p1 - p0)
            return tuple(round(a + (b - a) * u) for a, b in zip(c0, c1))
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
        for points in path.polygons():
            xy = [(x * self.px, y * self.px) for x, y in points]
            if not path.evenodd:
                ImageDraw.Draw(mask).polygon(xy, fill=255)
                continue
            single = Image.new("L", (self.px, self.px), 0)
            ImageDraw.Draw(single).polygon(xy, fill=255)
            mask = ImageChops.difference(mask, single)
        return mask

    def paint_layer(self, paint, box) -> Image.Image:
        """The paint over `box` (pixels) as an RGBA image. Gradients are sampled
        at up to 256 px and enlarged smoothly; conic ones are drawn as wedges."""
        x0, y0, x1, y1 = box
        w, h = x1 - x0, y1 - y0
        if isinstance(paint, ConicGradient):
            return self.conic_layer(paint, box)
        if not isinstance(paint, (Gradient, RadialGradient)):
            return Image.new("RGBA", (w, h), rgba(paint))
        sw, sh = min(w, 256), min(h, 256)
        stops = [(t, rgba(color)) for t, color in paint.stops]
        image = Image.new("RGBA", (sw, sh))
        image.putdata([color_at(stops, paint.offset((x0 + (i + 0.5) * w / sw) / self.px, (y0 + (j + 0.5) * h / sh) / self.px))
                       for j in range(sh) for i in range(sw)])
        return image.resize((w, h), Image.BICUBIC)

    def conic_layer(self, paint: ConicGradient, box) -> Image.Image:
        x0, y0, x1, y1 = box
        stops = [(t, rgba(color)) for t, color in paint.stops]
        layer = Image.new("RGBA", (x1 - x0, y1 - y0), stops[0][1])
        draw = ImageDraw.Draw(layer)
        cx, cy = paint.center[0] * self.px - x0, paint.center[1] * self.px - y0
        reach = 2 * (x1 - x0 + y1 - y0)
        n = paint.wedges
        for i in range(n):
            # Each wedge overlaps its neighbours a little, so no seam shows between them.
            a0, a1 = (math.radians(paint.angle + 360 * (i + d) / n) for d in (-0.3, 1.3))
            draw.polygon([(cx, cy), (cx + reach * math.cos(a0), cy + reach * math.sin(a0)),
                          (cx + reach * math.cos(a1), cy + reach * math.sin(a1))], fill=color_at(stops, (i + 0.5) / n))
        return layer

    def composite(self, paint, alpha: Image.Image) -> None:
        box = alpha.getbbox()
        if box is None:
            return
        layer = self.paint_layer(paint, box)
        layer.putalpha(ImageChops.multiply(layer.getchannel("A"), alpha.crop(box)))
        self.image.alpha_composite(layer, dest=box[:2])

    def background(self, paint) -> None:
        self.composite(paint, Image.new("L", (self.px, self.px), 255))

    def fill(self, path: Path, paint, clip: Path | None = None) -> None:
        mask = self.mask(path)
        if clip is not None:
            mask = ImageChops.multiply(mask, self.mask(clip))
        self.composite(paint, mask)

    def stroke(self, path: Path, width: float, paint, clip: Path | None = None) -> None:
        """The outline, `width` wide and centred on it, with round joins."""
        mask = Image.new("L", (self.px, self.px), 0)
        draw = ImageDraw.Draw(mask)
        w = width * self.px
        for points in path.polygons():
            xy = [(x * self.px, y * self.px) for x, y in points]
            draw.line(xy + xy[:1], fill=255, width=round(w))
            # A dot on every vertex rounds the joins (Pillow's own leave gaps on tight curves).
            for x, y in xy:
                draw.ellipse((x - w / 2, y - w / 2, x + w / 2, y + w / 2), fill=255)
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

    def shadow(self, path: Path, offset, blur: float, color, alpha: float, clip: Path | None = None) -> None:
        """A blurred copy of the shape: a shadow, or soft light in a light colour."""
        mask = self.mask(path.moved(*offset)).filter(ImageFilter.GaussianBlur(blur * self.px))
        if clip is not None:
            mask = ImageChops.multiply(mask, self.mask(clip))
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

    def _paint(self, paint) -> tuple[str, bool]:
        """The paint as an SVG fill value, and whether it is fully opaque."""
        if not isinstance(paint, (Gradient, RadialGradient)):
            return hex_color(paint), True
        gradient_id, s = self._id("gradient"), self.size
        stops = "".join(f'<stop offset="{t:g}" stop-color="{hex_color(color)}"{self._opacity("stop-opacity", color)}/>'
                        for t, color in paint.stops)
        if isinstance(paint, Gradient):
            self.defs.append(f'<linearGradient id="{gradient_id}" gradientUnits="userSpaceOnUse" '
                             f'x1="{paint.start[0] * s:.1f}" y1="{paint.start[1] * s:.1f}" '
                             f'x2="{paint.end[0] * s:.1f}" y2="{paint.end[1] * s:.1f}">{stops}</linearGradient>')
        else:
            self.defs.append(f'<radialGradient id="{gradient_id}" gradientUnits="userSpaceOnUse" '
                             f'cx="{paint.center[0] * s:.1f}" cy="{paint.center[1] * s:.1f}" r="{paint.radius * s:.1f}">'
                             f'{stops}</radialGradient>')
        return f"url(#{gradient_id})", all(rgba(color)[3] == 255 for _, color in paint.stops)

    @staticmethod
    def _opacity(attribute: str, color) -> str:
        alpha = rgba(color)[3]
        return "" if alpha == 255 else f' {attribute}="{alpha / 255:.3g}"'

    @staticmethod
    def _rule(path: Path, attribute: str = "fill-rule") -> str:
        return f' {attribute}="evenodd"' if path.evenodd else ""

    def _clip(self, clip: Path | None) -> str:
        if clip is None:
            return ""
        clip_id = self._id("clip")
        self.defs.append(f'<clipPath id="{clip_id}"><path d="{clip.svg(self.size)}"{self._rule(clip, "clip-rule")}/></clipPath>')
        return f' clip-path="url(#{clip_id})"'

    def background(self, paint) -> None:
        self.body.append(f'<rect width="{self.size}" height="{self.size}" fill="{self._paint(paint)[0]}"/>')

    def fill(self, path: Path, paint, clip: Path | None = None) -> None:
        if isinstance(paint, ConicGradient):
            self._conic(path, paint, clip)
            return
        value, opaque = self._paint(paint)
        attributes = f'fill="{value}"{self._rule(path)}'
        if not isinstance(paint, (Gradient, RadialGradient)):
            attributes += self._opacity("fill-opacity", paint)
            opaque = rgba(paint)[3] == 255
        if opaque:
            # A hairline stroke in the same paint hides anti-aliasing seams between facets.
            attributes += f' stroke="{value}" stroke-width="1" stroke-linejoin="round"'
        self.body.append(f'<path d="{path.svg(self.size)}" {attributes}{self._clip(clip)}/>')

    def stroke(self, path: Path, width: float, paint, clip: Path | None = None) -> None:
        if isinstance(paint, ConicGradient):
            # Wedges clipped to the outline's band: the band as an even-odd path isn't exact, so
            # clip the wedges to a mask of the stroked outline.
            mask_id = self._id("mask")
            self.defs.append(f'<mask id="{mask_id}" maskUnits="userSpaceOnUse" x="0" y="0" width="{self.size}" '
                             f'height="{self.size}"><path d="{path.svg(self.size)}" fill="none" stroke="#FFFFFF" '
                             f'stroke-width="{width * self.size:.1f}" stroke-linejoin="round"/></mask>')
            before = len(self.body)
            self._conic(rect(0, 0, 1, 1), paint, clip)
            self.body[before] = f'<g mask="url(#{mask_id})">{self.body[before]}</g>'
            return
        value, _ = self._paint(paint)
        opacity = "" if isinstance(paint, (Gradient, RadialGradient)) else self._opacity("stroke-opacity", paint)
        self.body.append(f'<path d="{path.svg(self.size)}" fill="none" stroke="{value}"{opacity} '
                         f'stroke-width="{width * self.size:.1f}" stroke-linejoin="round"{self._clip(clip)}/>')

    def _conic(self, path: Path, paint: ConicGradient, clip: Path | None) -> None:
        """SVG has no sweep gradient: thin wedges in the path's clip, 2 degrees each."""
        s, n = self.size, 180
        cx, cy = paint.center[0] * s, paint.center[1] * s
        wedges = []
        for i in range(n):
            a0, a1 = (math.radians(paint.angle + 360 * (i + d) / n) for d in (-0.3, 1.3))
            color = color_at(paint.stops, (i + 0.5) / n)
            wedges.append(f'<path d="M{cx:.1f} {cy:.1f}L{cx + 2 * s * math.cos(a0):.1f} {cy + 2 * s * math.sin(a0):.1f}'
                          f'L{cx + 2 * s * math.cos(a1):.1f} {cy + 2 * s * math.sin(a1):.1f}Z" '
                          f'fill="{hex_color(color)}"{self._opacity("fill-opacity", color)}/>')
        group = f'<g{self._clip(path)}>' + "".join(wedges) + "</g>"
        self.body.append(group if clip is None else f"<g{self._clip(clip)}>{group}</g>")

    def glow(self, center, radius: float, color, alpha: float, clip: Path | None = None) -> None:
        glow_id, s = self._id("glow"), self.size
        stops = "".join(f'<stop offset="{d:g}" stop-color="{hex_color(color)}" stop-opacity="{alpha * falloff(d):.3f}"/>'
                        for d in (i / 8 for i in range(9)))
        self.defs.append(f'<radialGradient id="{glow_id}">{stops}</radialGradient>')
        self.body.append(f'<circle cx="{center[0] * s:.1f}" cy="{center[1] * s:.1f}" r="{radius * s:.1f}" '
                         f'fill="url(#{glow_id})"{self._clip(clip)}/>')

    def shadow(self, path: Path, offset, blur: float, color, alpha: float, clip: Path | None = None) -> None:
        filter_id = self._id("blur")
        self.defs.append(f'<filter id="{filter_id}" x="-50%" y="-50%" width="200%" height="200%">'
                         f'<feGaussianBlur stdDeviation="{blur * self.size:.1f}"/></filter>')
        blurred = (f'<path d="{path.moved(*offset).svg(self.size)}" fill="{hex_color(color)}"{self._rule(path)} '
                   f'fill-opacity="{alpha:g}" filter="url(#{filter_id})"/>')
        # Clip a group around the blurred shape, so the blur happens before the clip.
        self.body.append(blurred if clip is None else f"<g{self._clip(clip)}>{blurred}</g>")

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


def glint(c, center, r: float, glow: float) -> None:
    """A crisp white four-point sparkle with its own soft light."""
    c.glow(center, r * 2.0, WHITE, glow)
    c.shadow(sparkle(center, r * 1.25, inner=0.3), (0, 0), r * 0.14, WHITE, 0.6)
    c.fill(sparkle(center, r, inner=0.2), WHITE)


LENS_CORE = [(0, WHITE), (0.18, (255, 246, 250)), (0.34, (255, 190, 222)), (0.5, (255, 92, 164)), (0.68, (190, 30, 130)),
             (0.86, (100, 18, 96)), (1, (74, 14, 80))]
LENS_CORE_GRAY = [(0, WHITE), (0.18, (252, 252, 252)), (0.34, (236, 236, 236)), (0.5, (200, 200, 200)),
                  (0.68, (140, 140, 140)), (0.86, (84, 84, 84)), (1, (64, 64, 64))]
# The ring's pastel sweep: pink, lilac, soft aqua, peach and back to pink.
LENS_RING = [(0, (255, 168, 214)), (0.25, (196, 166, 255)), (0.5, (140, 230, 236)), (0.75, (255, 200, 160)),
             (1, (255, 168, 214))]
LENS_RING_GRAY = [(0, (222, 222, 222)), (0.25, (206, 206, 206)), (0.5, (236, 236, 236)), (0.75, (226, 226, 226)),
                  (1, (222, 222, 222))]


def aura_tile(c) -> None:
    """The Aura tile behind D and E: deep plum at the top left through berry and
    rose to warm peach at the bottom right, with a few out-of-focus lights."""
    c.background(Gradient([(0, (34, 10, 62)), (0.35, (88, 24, 128)), (0.65, (180, 38, 124)), (0.88, (244, 92, 150)),
                           (1, (255, 160, 150))], (0, 0), (1, 1)))
    c.glow((1, 1), 0.5, (255, 178, 140), 0.5)
    for (x, y), r, color, alpha in (((0.14, 0.6), 0.07, AURA_LILAC, 0.22), ((0.86, 0.66), 0.09, (255, 180, 200), 0.2),
                                    ((0.66, 0.9), 0.05, (255, 200, 180), 0.22), ((0.37, 0.1), 0.045, AURA_LILAC, 0.18)):
        c.shadow(circle((x, y), r), (0, 0), 0.006, color, alpha)


def draw_aura_lens(c, variant: str) -> None:
    """D, "Aura Lens": a liquid-glass lens whose core glows white-hot through
    blush to magenta, in a thin iridescent ring, with a sparkle glinting on its
    rim. The lens = the camera and the photo; the glow = "Make it glow"."""
    gray = variant == "tinted"
    center, outer, inner = (0.5, 0.5), 0.268, 0.237
    cx, cy = center
    if variant == "default":
        aura_tile(c)
        halo, bloom, shade = (255, 176, 214), (255, 80, 160), (60, 10, 70)
    elif variant == "dark":
        dark_tile(c)
        halo, bloom, shade = (255, 176, 214), AURA_PINK, BLACK
    else:
        c.background(BLACK)
        halo, bloom, shade = (200, 200, 200), (130, 130, 130), BLACK
    lens = circle(center, outer)
    glass = circle(center, inner)
    rim = ring(center, outer, inner)
    # Light spilling past the ring: a wide bloom and a tight halo.
    c.shadow(lens, (0, 0), 0.09, bloom, 0.75)
    c.shadow(lens, (0, 0), 0.025, halo, 0.85)
    # The ring: an iridescent sweep with a bright edge, like a glass tube lit from the top left.
    c.fill(rim, ConicGradient(LENS_RING_GRAY if gray else LENS_RING, center, angle=200))
    c.fill(rim, Gradient([(0, WHITE + (150,)), (0.5, WHITE + (0,))], (cx - outer, cy - outer), (cx + outer, cy + outer)))
    c.fill(even_odd(lens, circle((cx + 0.005, cy + 0.006), outer)), WHITE + (230,), clip=lens)
    c.fill(even_odd(circle(center, inner + 0.006), circle((cx - 0.004, cy - 0.005), inner + 0.006)), WHITE + (110,), clip=rim)
    # The glass: a white-hot core through blush and magenta into deep glass, warmer at the bottom right.
    c.fill(glass, RadialGradient(LENS_CORE_GRAY if gray else LENS_CORE, center, inner))
    c.glow(center, inner * 0.6, WHITE, 0.3, clip=glass)
    if not gray:
        c.glow((cx + 0.05, cy + 0.06), 0.14, AURA_PEACH, 0.4, clip=glass)
        # A lens coating's faint lilac and aqua reflection.
        c.shadow(arc_band(center, inner * 0.84, inner * 0.7, 120, 175), (0, 0), 0.012, (150, 220, 255), 0.35, clip=glass)
    # Where the ring overhangs the glass, and faint light gathering at the bottom right.
    c.shadow(even_odd(rect(-1, -1, 2, 2), glass), (0, 0.008), 0.01, shade, 0.5, clip=glass)
    c.shadow(even_odd(glass, circle((cx - 0.008, cy - 0.01), inner)), (0, 0), 0.004, (255, 214, 200), 0.5, clip=glass)
    # A slim upper-left crescent highlight, and a small, bright reflection at the bottom right.
    sheen = circle(center, inner * 0.94)
    c.fill(even_odd(sheen, circle((cx + 0.02, cy + 0.024), inner * 0.95)),
           Gradient([(0, WHITE + (225,)), (1, WHITE + (0,))], (cx - 0.15, cy - 0.15), (cx - 0.02, cy - 0.02)), clip=sheen)
    spot = circle(center, inner * 0.86)
    c.fill(even_odd(spot, circle((cx - 0.045, cy - 0.045), inner * 0.86 + 0.054)), WHITE + (215,), clip=spot)
    glint(c, (cx - 0.19, cy - 0.19), 0.095, 0.55)
    glint(c, (0.8, 0.8), 0.042, 0.45)
    glint(c, (0.215, 0.79), 0.026, 0.4)




HEART_CORE = [(0, WHITE), (0.16, (255, 244, 249)), (0.34, (255, 190, 222)), (0.56, (255, 96, 166)), (0.78, (200, 34, 136)),
              (1, (120, 20, 100))]
HEART_CORE_GRAY = [(0, WHITE), (0.16, (248, 248, 248)), (0.34, (226, 226, 226)), (0.56, (188, 188, 188)),
                   (0.78, (140, 140, 140)), (1, (100, 100, 100))]


def draw_holo_heart(c, variant: str) -> None:
    """E, "Holo Heart": a puffy glass heart glowing white-hot from within, edged
    with an iridescent rim, with a sparkle on its lobe. The heart = the app's
    success burst; the glow and rim = the effects."""
    gray = variant == "tinted"
    center, width = (0.5, 0.515), 0.64
    if variant == "default":
        aura_tile(c)
        halo, bloom, deep = (255, 186, 220), (255, 80, 160), (110, 14, 96)
    elif variant == "dark":
        dark_tile(c)
        halo, bloom, deep = (255, 186, 220), AURA_PINK, (110, 14, 96)
    else:
        c.background(BLACK)
        halo, bloom, deep = (200, 200, 200), (130, 130, 130), (70, 70, 70)
    heart = puffy_heart(center, width)
    outside = even_odd(rect(-1, -1, 2, 2), heart)
    c.shadow(heart, (0, 0), 0.09, bloom, 0.75)
    c.shadow(heart, (0, 0), 0.022, halo, 0.85)
    glow_at = (0.5, 0.47)
    c.fill(heart, RadialGradient(HEART_CORE_GRAY if gray else HEART_CORE, glow_at, 0.36))
    c.glow(glow_at, 0.2, WHITE, 0.22, clip=heart)
    if not gray:
        c.glow((0.6, 0.66), 0.16, AURA_PEACH, 0.4, clip=heart)
    # Puffed up: deeper toward the lower-right edges.
    c.shadow(outside, (0.01, 0.016), 0.03, deep, 0.6, clip=heart)
    # The iridescent rim, brightest at the top left.
    c.stroke(heart, 0.026, ConicGradient(LENS_RING_GRAY if gray else LENS_RING, glow_at, angle=200), clip=heart)
    c.stroke(heart, 0.026, Gradient([(0, WHITE + (170,)), (0.5, WHITE + (0,))], (0.2, 0.2), (0.62, 0.62)), clip=heart)
    # Crescent highlights on both lobes, and a small reflection low on the right.
    for lobe, r, offset, alpha in (((0.342, 0.39), 0.13, 0.03, 225), ((0.658, 0.39), 0.13, 0.022, 150)):
        shine = circle(lobe, r)
        c.fill(even_odd(shine, circle((lobe[0] + offset * 0.7, lobe[1] + offset), r * 1.02)),
               Gradient([(0, WHITE + (alpha,)), (1, WHITE + (0,))], (lobe[0] - 0.1, lobe[1] - 0.1), lobe),
               clip=even_odd(shine, outside))
    glint(c, (0.255, 0.33), 0.088, 0.55)
    glint(c, (0.8, 0.8), 0.04, 0.45)
    glint(c, (0.215, 0.79), 0.026, 0.4)


CONCEPTS = {
    "a": ("Spark Cam", draw_spark_cam),
    "b": ("Heart Print", draw_heart_print),
    "c": ("Glow Gem", draw_glow_gem),
    "d": ("Aura Lens", draw_aura_lens),
    "e": ("Holo Heart", draw_holo_heart),
}
# The app's icon. `--concept` overrides it for one run; change it here to switch
# for good (the concept sheets mark this one as chosen).
CHOSEN = "d"


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


# MARK: - Wordmark and launch icon

# The logotype: lowercase "aybuke" from Poppins Bold's own outlines, set tight,
# every corner softened, and the icon's sparkle glinting just after the "e" (at
# its shoulder, so it never reads as an accent). Font units (1000 per em), y up,
# until written out.
WORDMARK_CUT = "Bold"
WORDMARK_TEXT = "aybuke"
WORDMARK_TRACKING = -28
WORDMARK_PAIRS = {"ay": -18, "yb": -10, "ke": -12}
# Corner radii: convex corners (the terminals) and concave ones (where strokes join).
WORDMARK_ROUNDING = (26, 10)
# The sparkle: its radius as a share of the e's half-width, its gap after the e,
# how far its centre sits above the e's top (in sparkle radii), and its waist
# (smaller = thinner points), as in `sparkle()`.
WORDMARK_SPARKLE = (0.38, 30, 0.15, 0.24)
WORDMARK_GRADIENT = [(0, PLUM), (0.55, AURA_PINK), (1, AURA_PEACH)]
# The app asset's natural height in points (it is drawn resized, as a vector).
WORDMARK_POINTS = 60
WORDMARK_SET = ROOT / "ios" / "App" / "Resources" / "Assets.xcassets" / "Wordmark.imageset"
WORDMARK_SWIFT = ROOT / "ios" / "App" / "DesignSystem" / "Components" / "WordmarkGlyphs.swift"
# The launch screen's icon, which the SwiftUI splash starts from: the same
# picture at the same size, so the hand-over doesn't jump.
LAUNCH_ICON_SET = ROOT / "ios" / "App" / "Resources" / "Assets.xcassets" / "LaunchIcon.imageset"
LAUNCH_ICON_POINTS = 112
LAUNCH_ICON_CANVAS = 184


class FontOutlines:
    """Just enough of a TrueType reader for glyph outlines (simple glyphs, a
    format 4 cmap and advance widths), so the script needs nothing but Pillow."""

    def __init__(self, path: FilePath) -> None:
        self.data = data = path.read_bytes()
        self.tables = {}
        for index in range(self.u16(4)):
            tag, _, offset, _ = struct.unpack(">4sIII", data[12 + 16 * index:28 + 16 * index])
            self.tables[tag.decode("latin-1")] = offset
        head, maxp, hhea, loca, hmtx = (self.tables[t] for t in ("head", "maxp", "hhea", "loca", "hmtx"))
        long_offsets = self.i16(head + 50) == 1
        glyphs, metrics = self.u16(maxp + 4), self.u16(hhea + 34)
        self.loca = [self.u32(loca + 4 * i) if long_offsets else 2 * self.u16(loca + 2 * i) for i in range(glyphs + 1)]
        self.advances = [self.u16(hmtx + 4 * min(i, metrics - 1)) for i in range(glyphs)]
        self.glyph_ids = self.read_cmap()

    def u16(self, offset: int) -> int:
        return struct.unpack(">H", self.data[offset:offset + 2])[0]

    def i16(self, offset: int) -> int:
        return struct.unpack(">h", self.data[offset:offset + 2])[0]

    def u32(self, offset: int) -> int:
        return struct.unpack(">I", self.data[offset:offset + 4])[0]

    def read_cmap(self) -> dict[int, int]:
        base = self.tables["cmap"]
        for index in range(self.u16(base + 2)):
            platform, encoding = self.u16(base + 4 + 8 * index), self.u16(base + 6 + 8 * index)
            table = base + self.u32(base + 8 + 8 * index)
            if (platform, encoding) not in ((3, 1), (0, 3)) or self.u16(table) != 4:
                continue
            count = self.u16(table + 6) // 2
            ends = table + 14
            starts, deltas = ends + 2 * count + 2, ends + 4 * count + 2
            ranges = deltas + 2 * count
            ids = {}
            for s in range(count):
                start, end = self.u16(starts + 2 * s), self.u16(ends + 2 * s)
                delta, range_offset = self.i16(deltas + 2 * s), self.u16(ranges + 2 * s)
                for code in range(start, min(end, 0xFFFE) + 1):
                    if range_offset:
                        glyph = self.u16(ranges + 2 * s + range_offset + 2 * (code - start))
                        ids[code] = (glyph + delta) & 0xFFFF if glyph else 0
                    else:
                        ids[code] = (code + delta) & 0xFFFF
            return ids
        raise ValueError("The font has no Unicode BMP cmap.")

    def glyph(self, char: str) -> tuple[list[list[tuple[float, float, bool]]], int]:
        """The character's contours as (x, y, on-curve) points, and its advance."""
        glyph = self.glyph_ids[ord(char)]
        start = self.tables["glyf"] + self.loca[glyph]
        count = self.i16(start)
        if count < 0:
            raise ValueError(f"{char!r} is a composite glyph, which this reader doesn't handle.")
        ends = [self.u16(start + 10 + 2 * i) for i in range(count)]
        offset = start + 10 + 2 * count
        offset += 2 + self.u16(offset)  # skip the hinting instructions
        flags: list[int] = []
        while len(flags) < (ends[-1] + 1 if ends else 0):
            flag = self.data[offset]
            offset += 1
            flags.append(flag)
            if flag & 8:  # repeated
                flags.extend([flag] * self.data[offset])
                offset += 1

        def coordinates(short: int, same_or_positive: int) -> list[int]:
            nonlocal offset
            values, value = [], 0
            for flag in flags:
                if flag & short:
                    value += self.data[offset] if flag & same_or_positive else -self.data[offset]
                    offset += 1
                elif not flag & same_or_positive:
                    value += self.i16(offset)
                    offset += 2
                values.append(value)
            return values

        xs = coordinates(2, 16)
        ys = coordinates(4, 32)
        contours, first = [], 0
        for end in ends:
            contours.append([(xs[i], ys[i], bool(flags[i] & 1)) for i in range(first, end + 1)])
            first = end + 1
        return contours, self.advances[glyph]


# Outline segments: ("L", p0, p1), ("Q", p0, c, p1) and ("C", p0, c1, c2, p1).

def v_sub(a, b):
    return (a[0] - b[0], a[1] - b[1])


def v_add(a, b):
    return (a[0] + b[0], a[1] + b[1])


def v_scale(a, k: float):
    return (a[0] * k, a[1] * k)


def v_lerp(a, b, t: float):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def v_unit(a):
    length = math.hypot(*a)
    return (a[0] / length, a[1] / length) if length > 1e-9 else (0.0, 0.0)


def segment_point(segment, t: float):
    if segment[0] == "L":
        return v_lerp(segment[1], segment[2], t)
    if segment[0] == "Q":
        p0, c, p1 = segment[1:]
        return v_lerp(v_lerp(p0, c, t), v_lerp(c, p1, t), t)
    p0, c1, c2, p1 = segment[1:]
    a, b, c = v_lerp(p0, c1, t), v_lerp(c1, c2, t), v_lerp(c2, p1, t)
    return v_lerp(v_lerp(a, b, t), v_lerp(b, c, t), t)


def segment_direction(segment, t: float):
    """Unit tangent at t (lines and quadratics; the corners never sit on cubics)."""
    if segment[0] == "L":
        return v_unit(v_sub(segment[2], segment[1]))
    p0, c, p1 = segment[1], segment[2], segment[-1]
    direction = v_add(v_scale(v_sub(c, p0), 1 - t), v_scale(v_sub(p1, c), t))
    return v_unit(direction) if math.hypot(*direction) > 1e-9 else v_unit(v_sub(p1, p0))


def segment_length(segment, t0: float = 0.0, t1: float = 1.0, steps: int = 24) -> float:
    total, previous = 0.0, segment_point(segment, t0)
    for i in range(1, steps + 1):
        point = segment_point(segment, t0 + (t1 - t0) * i / steps)
        total += math.hypot(*v_sub(point, previous))
        previous = point
    return total


def trim_segment(segment, start: float, end: float):
    """The segment without `start` units of length at its start and `end` at its end."""
    def parameter(distance: float, from_end: bool) -> float:
        lo, hi = 0.0, 1.0
        for _ in range(28):
            mid = (lo + hi) / 2
            covered = segment_length(segment, mid, 1.0) if from_end else segment_length(segment, 0.0, mid)
            if (covered > distance) == from_end:
                lo = mid
            else:
                hi = mid
        return (lo + hi) / 2

    t0 = parameter(start, False) if start > 0 else 0.0
    t1 = parameter(end, True) if end > 0 else 1.0
    if segment[0] == "L":
        return ("L", segment_point(segment, t0), segment_point(segment, t1))
    # A quadratic's piece between t0 and t1 is a quadratic too (blossoming).
    p0, c, p1 = segment[1:]

    def blossom(u: float, w: float):
        return v_lerp(v_lerp(p0, c, u), v_lerp(c, p1, u), w)

    return ("Q", blossom(t0, t0), blossom(t0, t1), blossom(t1, t1))


def contour_segments(points) -> list[tuple]:
    """TrueType points to a closed run of lines and quadratics; two off-curve
    points in a row imply an on-curve point halfway between them."""
    if not any(on for _, _, on in points):
        (ax, ay, _), (bx, by, _) = points[0], points[1]
        points = [((ax + bx) / 2, (ay + by) / 2, True)] + points[1:] + points[:1]
    first = next(i for i, p in enumerate(points) if p[2])
    points = points[first:] + points[:first]
    segments, current, control = [], points[0][:2], None
    for x, y, on in points[1:] + points[:1]:
        if on:
            if control is not None:
                segments.append(("Q", current, control, (x, y)))
            elif (x, y) != current:
                segments.append(("L", current, (x, y)))
            current, control = (x, y), None
        else:
            if control is not None:
                middle = ((control[0] + x) / 2, (control[1] + y) / 2)
                segments.append(("Q", current, control, middle))
                current = middle
            control = (x, y)
    return segments


def round_corners(segments, convex: float, concave: float, threshold: float = 25) -> list[tuple]:
    """Replaces every corner sharper than `threshold` degrees with a circular
    arc (as a cubic) tangent to both sides. TrueType fills to the right of the
    path, so a right turn is a convex corner (radius `convex`) and a left turn
    a concave one (`concave`). Each side gives up at most 42% of its length."""
    count = len(segments)
    trims = [[0.0, 0.0] for _ in segments]
    corners = {}
    for i in range(count):
        before, after = segments[i], segments[(i + 1) % count]
        u, v = segment_direction(before, 1.0), segment_direction(after, 0.0)
        turn = math.acos(max(-1.0, min(1.0, u[0] * v[0] + u[1] * v[1])))
        radius = convex if u[0] * v[1] - u[1] * v[0] < 0 else concave
        if math.degrees(turn) < threshold or radius <= 0:
            continue
        cut = min(radius * math.tan(turn / 2), 0.42 * segment_length(before), 0.42 * segment_length(after))
        corners[i] = turn
        trims[i][1] = cut
        trims[(i + 1) % count][0] = cut
    trimmed = [trim_segment(segment, *trims[i]) if any(trims[i]) else segment for i, segment in enumerate(segments)]
    out = []
    for i, segment in enumerate(trimmed):
        out.append(segment)
        if i in corners:
            after = trimmed[(i + 1) % count]
            start, end, turn = segment[-1], after[1], corners[i]
            u, v = segment_direction(segment, 1.0), segment_direction(after, 0.0)
            radius = math.hypot(*v_sub(end, start)) / (2 * math.sin(turn / 2))
            arm = 4 / 3 * math.tan(turn / 4) * radius
            out.append(("C", start, v_add(start, v_scale(u, arm)), v_sub(end, v_scale(v, arm)), end))
    return out


def sparkle_segments(center, r: float, waist: float) -> list[tuple]:
    """`sparkle()` in font units (y up), running clockwise like an outer contour."""
    cx, cy = center
    k = waist * r
    tips = [(cx, cy + r), (cx + r, cy), (cx, cy - r), (cx - r, cy)]
    bends = [(cx + k, cy + k), (cx + k, cy - k), (cx - k, cy - k), (cx - k, cy + k)]
    return [("Q", tips[i], bends[i], tips[(i + 1) % 4]) for i in range(4)]


def flatten(segments, steps: int = 16) -> list[tuple[float, float]]:
    points = []
    for segment in segments:
        n = 1 if segment[0] == "L" else steps
        points.extend(segment_point(segment, i / n) for i in range(n))
    return points


def wordmark_glyphs() -> list[list[list[tuple]]]:
    """Each letter (and the sparkle) as its contours, each a closed run of segments."""
    font_file = FontOutlines(FONTS / f"Poppins-{WORDMARK_CUT}.ttf")
    glyphs, x = [], 0
    for index, char in enumerate(WORDMARK_TEXT):
        contours, advance = font_file.glyph(char)
        glyphs.append([round_corners(contour_segments([(px + x, py, on) for px, py, on in contour]), *WORDMARK_ROUNDING)
                       for contour in contours])
        x += advance + WORDMARK_TRACKING + WORDMARK_PAIRS.get(WORDMARK_TEXT[index:index + 2], 0)
    e = [p for contour in glyphs[-1] for p in flatten(contour, 6)]
    left, right, top = min(p[0] for p in e), max(p[0] for p in e), max(p[1] for p in e)
    size, gap, rise, waist = WORDMARK_SPARKLE
    r = (right - left) / 2 * size
    glyphs.append([sparkle_segments((right + gap + r, top + rise * r), r, waist)])
    return glyphs


def wordmark_bounds(glyphs) -> tuple[float, float, float, float]:
    points = [p for glyph in glyphs for contour in glyph for p in flatten(contour, 8)]
    return (min(p[0] for p in points), min(p[1] for p in points), max(p[0] for p in points), max(p[1] for p in points))


def wordmark_path_data(glyphs, height: float) -> tuple[float, list[str]]:
    """The wordmark `height` units tall, cropped to its ink (y down): its width
    and each letter's SVG path data (absolute M, L, Q, C and Z), the sparkle last."""
    x0, y0, x1, y1 = wordmark_bounds(glyphs)
    k = height / (y1 - y0)

    def xy(p) -> str:
        return f"{(p[0] - x0) * k:.2f} {(y1 - p[1]) * k:.2f}"

    letters = []
    for glyph in glyphs:
        data = []
        for contour in glyph:
            data.append("M" + xy(contour[0][1]))
            data.extend(s[0] + " ".join(xy(p) for p in s[2:]) for s in contour)
            data.append("Z")
        letters.append("".join(data))
    return (x1 - x0) * k, letters


def wordmark_svg(glyphs, height: float, paint, comment: str) -> str:
    """The wordmark `height` units tall, cropped to its ink; `paint` is a colour
    or gradient stops (left to right, a little downhill)."""
    width, data = wordmark_path_data(glyphs, height)
    defs, fill = "", hex_color(paint) if isinstance(paint[0], int) else "url(#paint)"
    if fill == "url(#paint)":
        stops = "".join(f'<stop offset="{t:g}" stop-color="{hex_color(color)}"/>' for t, color in paint)
        defs = (f'  <defs><linearGradient id="paint" gradientUnits="userSpaceOnUse" x1="0" y1="0" '
                f'x2="{width:.2f}" y2="{height * 0.5:.2f}">{stops}</linearGradient></defs>\n')
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{width:.2f}" height="{height:g}" '
            f'viewBox="0 0 {width:.2f} {height:g}">\n  <!-- {comment} -->\n{defs}'
            f'  <path fill="{fill}" d="{"".join(data)}"/>\n</svg>\n')


def wordmark_swift(glyphs, height: float) -> str:
    """The app's wordmark split per letter for the launch splash's write-on: the
    same numbers as Wordmark.svg, one path string per letter."""
    width, letters = wordmark_path_data(glyphs, height)
    names = list(WORDMARK_TEXT) + ["sparkle"]
    rows = "\n".join(f'        "{data}", // {name}' for data, name in zip(letters, names))
    return f"""// Written by scripts/render-brand-assets.py (--wordmark); edit the script, not this file.
import CoreGraphics

/// The `Wordmark` vector split per letter, for the launch splash's
/// write-on: the same outlines and numbers as Wordmark.svg (y down, cropped to
/// its ink), each letter as SVG path data (absolute M, L, Q, C and Z), the
/// sparkle last. `WordmarkGlyph` draws one of them.
enum WordmarkGlyphs {{
    static let size = CGSize(width: {width:.2f}, height: {height:g})
    static let letters: [String] = [
{rows}
    ]
}}
"""


def wordmark_image(glyphs, height: int, paint, padding: int = 0) -> Image.Image:
    """The wordmark as an RGBA image `height` px tall (plus `padding` around it),
    drawn at 4x: each letter's outer contours filled, then its counters cut."""
    x0, y0, x1, y1 = wordmark_bounds(glyphs)
    k = height * SCALE / (y1 - y0)
    pad = padding * SCALE
    size = (round((x1 - x0) * k) + 2 * pad, height * SCALE + 2 * pad)
    alpha = Image.new("L", size, 0)
    for glyph in glyphs:
        layer = Image.new("L", size, 0)
        draw = ImageDraw.Draw(layer)
        polygons = [[((x - x0) * k + pad, (y1 - y) * k + pad) for x, y in flatten(contour)] for contour in glyph]
        # Pixel y runs down, so an outer (clockwise in font units) contour has a positive area here.
        area = [sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(p, p[1:] + p[:1])) for p in polygons]
        for polygon, a in sorted(zip(polygons, area), key=lambda item: item[1] <= 0):
            draw.polygon(polygon, fill=255 if a > 0 else 0)
        alpha = ImageChops.lighter(alpha, layer)
    if isinstance(paint[0], int):
        color = Image.new("RGBA", size, rgba(paint))
    else:
        ramp = Image.new("RGBA", (256, 1))
        ramp.putdata([rgba(color_at(paint, i / 255)) for i in range(256)])
        color = ramp.resize(size, Image.BICUBIC)
    out = Image.new("RGBA", size, (0, 0, 0, 0))
    out.paste(color, (0, 0), alpha)
    return out.resize((size[0] // SCALE, size[1] // SCALE), Image.LANCZOS)


def superellipse(side: float, exponent: float = 5.0, steps: int = 720) -> list[tuple[float, float]]:
    """Apple's continuous-corner icon shape, closely: |x|^n + |y|^n = 1 across `side` px."""
    half, points = side / 2, []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        points.append((half + half * math.copysign(abs(c) ** (2 / exponent), c),
                       half + half * math.copysign(abs(s) ** (2 / exponent), s)))
    return points


def launch_icon(art: Image.Image, scale: int) -> Image.Image:
    """The icon as the launch screen shows it: a continuous-corner tile with a
    soft plum shadow, centred on a transparent canvas, at `scale` px per point."""
    side, canvas = LAUNCH_ICON_POINTS * scale, LAUNCH_ICON_CANVAS * scale
    mask = Image.new("L", (side * SCALE, side * SCALE), 0)
    ImageDraw.Draw(mask).polygon(superellipse(side * SCALE), fill=255)
    mask = mask.resize((side, side), Image.LANCZOS)
    tile = art.convert("RGBA").resize((side, side), Image.LANCZOS)
    tile.putalpha(mask)
    inset = (canvas - side) // 2
    shadow = Image.new("L", (canvas, canvas), 0)
    shadow.paste(mask, (inset, inset + 7 * scale))
    shadow = shadow.filter(ImageFilter.GaussianBlur(9 * scale)).point(lambda value: round(value * 0.3))
    out = Image.new("RGBA", (canvas, canvas), PLUM + (0,))
    out.paste(Image.new("RGBA", (canvas, canvas), PLUM + (255,)), (0, 0), shadow)
    out.alpha_composite(tile, (inset, inset))
    return out


def write_contents(folder: FilePath, images: list[dict], properties: dict | None = None) -> None:
    contents = {"images": images, "info": {"author": "xcode", "version": 1}}
    if properties:
        contents["properties"] = properties
    (folder / "Contents.json").write_text(json.dumps(contents, indent=2).replace('": ', '" : ') + "\n", encoding="utf-8")


def render_wordmark(art: Image.Image) -> None:
    """The wordmark (docs SVGs and PNGs, the app's vector asset) and the launch
    screen's icon, drawn from `art` (the app icon at 1024 px)."""
    glyphs = wordmark_glyphs()
    note = "Aybuke wordmark: Poppins Bold outlines, tightened, corners rounded, with the icon's sparkle. " \
           "Written by scripts/render-brand-assets.py; edit the script, not this file."
    (BRAND / "wordmark.svg").write_text(wordmark_svg(glyphs, 120, INK, note), encoding="utf-8")
    (BRAND / "wordmark-gradient.svg").write_text(wordmark_svg(glyphs, 120, WORDMARK_GRADIENT, note), encoding="utf-8")
    wordmark_image(glyphs, 360, INK, padding=24).save(BRAND / "wordmark.png")
    wordmark_image(glyphs, 360, WORDMARK_GRADIENT, padding=24).save(BRAND / "wordmark-gradient.png")
    # The app tints it like text (ink, or light in dark mode): a template vector.
    WORDMARK_SET.mkdir(parents=True, exist_ok=True)
    (WORDMARK_SET / "Wordmark.svg").write_text(wordmark_svg(glyphs, WORDMARK_POINTS, BLACK, note), encoding="utf-8")
    write_contents(WORDMARK_SET, [{"filename": "Wordmark.svg", "idiom": "universal"}],
                   {"preserves-vector-representation": True, "template-rendering-intent": "template"})
    # The same letters one by one, for the launch splash.
    WORDMARK_SWIFT.write_text(wordmark_swift(glyphs, WORDMARK_POINTS), encoding="utf-8")
    LAUNCH_ICON_SET.mkdir(parents=True, exist_ok=True)
    images = [{"idiom": "universal", "scale": "1x"}]
    for scale in (2, 3):
        launch_icon(art, scale).save(LAUNCH_ICON_SET / f"LaunchIcon@{scale}x.png")
        images.append({"filename": f"LaunchIcon@{scale}x.png", "idiom": "universal", "scale": f"{scale}x"})
    write_contents(LAUNCH_ICON_SET, images)
    print("Rendered the wordmark and the launch icon.")


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
    board.alpha_composite(wordmark_image(wordmark_glyphs(), 132, INK), (x, 168))
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
    """The concepts on a light and a dark Home Screen, then their dark and
    tinted versions."""
    column = 440
    width = column * len(CONCEPTS)
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
    render_wordmark(default)


def main() -> None:
    parser = argparse.ArgumentParser(description="Render Aybuke's app icons and brand board.")
    parser.add_argument("--concept", choices=sorted(CONCEPTS), default=CHOSEN,
                        help=f"icon concept for every output (default: {CHOSEN}, the app's icon)")
    parser.add_argument("--concept-sheets", action="store_true",
                        help="only redraw the concept comparison images in docs/brand/icon-concepts/")
    parser.add_argument("--wordmark", action="store_true",
                        help="only redraw the wordmark, the launch icon and the brand board (from app-icon-1024.png)")
    args = parser.parse_args()
    if args.concept_sheets:
        render_concept_sheets()
    elif args.wordmark:
        art = Image.open(BRAND / "app-icon-1024.png").convert("RGB")
        render_wordmark(art)
        brand_board(art).save(BRAND / "brand-board.png")
    else:
        render_app_icons(args.concept)


if __name__ == "__main__":
    main()
