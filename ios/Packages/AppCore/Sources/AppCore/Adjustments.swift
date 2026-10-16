import Foundation

// The editor's Adjust tool: free, on the device. The sliders fix light and
// colour ("Auto" sets those) or give the photo a vibe: highlights, shadows, a
// pink or lilac tint, soft glow, a matte fade, film grain and a vignette. They
// change light and colour only: nothing here retouches skin or reshapes
// anything, and the glow is light added on top, never a blur in its place.
//
// The numbers live here so the preview and the full-size render match: the
// app's Core Image pipeline (`ImageFilters.adjust`) only turns them into
// filters. Vibe names are English; the app shows them with `L10n.core(_:)`,
// and scripts/export-core-strings.py registers every name marked with `vibe`.

/// Marks a vibe's name for scripts/export-core-strings.py.
private func vibe(_ english: String) -> String { english }

/// Every slider of the Adjust tool. Neutral values change nothing.
public struct AdjustmentSettings: Hashable, Sendable {
    // Light and colour, which "Auto" sets.
    public var brightness: Double
    public var contrast: Double
    public var saturation: Double
    public var warmth: Double
    public var sharpness: Double
    // The vibe.
    public var highlights: Double
    public var shadows: Double
    /// Below zero pink, above zero lilac.
    public var tint: Double
    public var glow: Double
    public var fade: Double
    public var grain: Double
    public var vignette: Double

    public init(brightness: Double = 0, contrast: Double = 1, saturation: Double = 1, warmth: Double = 0, sharpness: Double = 0,
                vignette: Double = 0, glow: Double = 0, fade: Double = 0, grain: Double = 0, tint: Double = 0,
                highlights: Double = 0, shadows: Double = 0) {
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.warmth = warmth
        self.sharpness = sharpness
        self.highlights = highlights
        self.shadows = shadows
        self.tint = tint
        self.glow = glow
        self.fade = fade
        self.grain = grain
        self.vignette = vignette
    }

    public static let neutral = AdjustmentSettings()

    public var isNeutral: Bool { self == .neutral }

    /// "Auto" for a photo: its light and colour, with every vibe slider at rest.
    /// The vignette stays off, as it always has.
    public init(auto plan: AutoAdjustment) {
        self.init(brightness: plan.brightness, contrast: plan.contrast, saturation: plan.saturation,
                  warmth: plan.warmth, sharpness: plan.sharpness)
    }

    /// "Auto" on the sliders she has: the plan's light and colour, the vibe
    /// sliders as they are, and the vibe she picked still on top.
    public func applyingAuto(_ plan: AutoAdjustment, vibe: AdjustVibe?) -> AdjustmentSettings {
        var settings = self
        settings.brightness = plan.brightness
        settings.contrast = plan.contrast
        settings.saturation = plan.saturation
        settings.warmth = plan.warmth
        settings.sharpness = plan.sharpness
        guard let vibe else { return settings }
        for parameter in AdjustmentParameter.shifted {
            settings[parameter] += vibe.shift(of: parameter)
        }
        return settings.clamped()
    }

    public subscript(parameter: AdjustmentParameter) -> Double {
        get { self[keyPath: parameter.keyPath] }
        set { self[keyPath: parameter.keyPath] = newValue }
    }

    /// Every slider inside its range. A value a hair from its resting point
    /// is the resting point: taking a vibe off after another one can leave
    /// ±1e-17 behind, which would count as an invisible edit.
    public func clamped() -> AdjustmentSettings {
        var settings = self
        for parameter in AdjustmentParameter.allCases {
            let value = parameter.range.clamp(settings[parameter])
            settings[parameter] = abs(value - parameter.neutral) < Self.restTolerance ? parameter.neutral : value
        }
        return settings
    }

    /// How close to its resting point a slider counts as at rest.
    static let restTolerance = 1e-9

    /// Highlights, shadows, fade or tint: the tone and colour map (`ToneMap`).
    public var hasToneMap: Bool { highlights != 0 || shadows != 0 || fade != 0 || tint != 0 }
}

/// One slider, in the order the panel shows them.
public enum AdjustmentParameter: String, CaseIterable, Identifiable, Sendable {
    case brightness, contrast, highlights, shadows, saturation, warmth, tint, glow, fade, grain, vignette, sharpness

    public var id: String { rawValue }

    public var range: ClosedRange<Double> {
        switch self {
        case .brightness: return -0.3...0.3
        case .contrast: return 0.7...1.4
        case .saturation: return 0...2
        case .warmth, .tint, .highlights, .shadows: return -1...1
        case .sharpness, .glow, .fade, .grain, .vignette: return 0...1
        }
    }

    public var neutral: Double { AdjustmentSettings.neutral[keyPath: keyPath] }

    /// Both ways from the middle (warmth, tint, highlights, shadows…), or up from zero.
    public var isCentered: Bool { range.lowerBound < neutral && neutral < range.upperBound }

    public var keyPath: WritableKeyPath<AdjustmentSettings, Double> {
        switch self {
        case .brightness: return \.brightness
        case .contrast: return \.contrast
        case .saturation: return \.saturation
        case .warmth: return \.warmth
        case .sharpness: return \.sharpness
        case .highlights: return \.highlights
        case .shadows: return \.shadows
        case .tint: return \.tint
        case .glow: return \.glow
        case .fade: return \.fade
        case .grain: return \.grain
        case .vignette: return \.vignette
        }
    }

    /// Light and colour, which "Auto" sets and a vibe only nudges.
    public static let autoSet: [AdjustmentParameter] = [.brightness, .contrast, .saturation, .warmth, .sharpness]
    /// What a vibe moves from her own values instead of setting.
    public static let shifted: [AdjustmentParameter] = [.contrast, .saturation, .warmth]
    /// What a vibe sets outright.
    public static let vibeSet: [AdjustmentParameter] = [.highlights, .shadows, .tint, .glow, .fade, .grain, .vignette]
}

extension ClosedRange where Bound == Double {
    func clamp(_ value: Double) -> Double { Swift.min(Swift.max(value, lowerBound), upperBound) }
}

// MARK: - Vibes

/// A one-tap vibe above the sliders. It sets the vibe sliders and nudges her
/// contrast, saturation and warmth, so a photo "Auto" fixed stays fixed;
/// every value lands on the sliders, so she can tweak it.
public struct AdjustVibe: Identifiable, Hashable, Sendable {
    public let id: String
    /// English name on its chip.
    public let name: String
    public let symbolName: String
    /// The slider the panel turns to after she picks it.
    public let lead: AdjustmentParameter
    /// The vibe on an untouched photo. Brightness and sharpness stay hers.
    public let settings: AdjustmentSettings

    /// How far it moves one of her own sliders (contrast, saturation, warmth).
    public func shift(of parameter: AdjustmentParameter) -> Double {
        guard AdjustmentParameter.shifted.contains(parameter) else { return 0 }
        return settings[parameter] - parameter.neutral
    }

    /// This vibe in place of `previous`: the vibe sliders take its values, and
    /// her contrast, saturation and warmth lose the previous vibe's nudge and
    /// get this one's.
    public func applied(to current: AdjustmentSettings, replacing previous: AdjustVibe?) -> AdjustmentSettings {
        var result = current
        for parameter in AdjustmentParameter.vibeSet {
            result[parameter] = settings[parameter]
        }
        for parameter in AdjustmentParameter.shifted {
            result[parameter] += shift(of: parameter) - (previous?.shift(of: parameter) ?? 0)
        }
        return result.clamped()
    }

    /// Takes the vibe off: its nudge comes off her sliders and the vibe
    /// sliders go back to rest.
    public func removed(from current: AdjustmentSettings) -> AdjustmentSettings {
        var result = current
        for parameter in AdjustmentParameter.vibeSet {
            result[parameter] = parameter.neutral
        }
        for parameter in AdjustmentParameter.shifted {
            result[parameter] -= shift(of: parameter)
        }
        return result.clamped()
    }
}

public enum AdjustVibes {
    /// In the order the panel shows them, after "Auto".
    public static let all: [AdjustVibe] = [
        // Airy and soft: lifted shadows, a glow in the light, a lilac haze.
        AdjustVibe(id: "dreamy", name: vibe("Dreamy"), symbolName: "cloud", lead: .glow,
                   settings: AdjustmentSettings(saturation: 0.95, glow: 0.45, fade: 0.22, tint: 0.2, highlights: 0.2, shadows: 0.3)),
        // A film print: matte blacks, grain, warm and a little muted.
        AdjustVibe(id: "analog", name: vibe("Analog"), symbolName: "film", lead: .grain,
                   settings: AdjustmentSettings(saturation: 0.88, warmth: 0.15, vignette: 0.3, glow: 0.1, fade: 0.35, grain: 0.3,
                                                tint: -0.1, highlights: -0.2, shadows: 0.1)),
        // Deep, cool and calm: darker shadows and highlights, a lilac cast.
        AdjustVibe(id: "moody", name: vibe("Moody"), symbolName: "moon", lead: .shadows,
                   settings: AdjustmentSettings(saturation: 0.82, warmth: -0.12, vignette: 0.5, fade: 0.12, grain: 0.1, tint: 0.2,
                                                highlights: -0.3, shadows: -0.2)),
        // Golden hour: warm light, a glow and pink in the shadows.
        AdjustVibe(id: "golden", name: vibe("Golden"), symbolName: "sun.horizon", lead: .warmth,
                   settings: AdjustmentSettings(saturation: 1.06, warmth: 0.4, vignette: 0.2, glow: 0.35, tint: -0.15,
                                                highlights: 0.15, shadows: 0.15)),
    ]

    public static func preset(id: String) -> AdjustVibe? {
        all.first { $0.id == id }
    }
}

// MARK: - Rendering numbers

/// Sizes for a photo of any size. One unit is a thousandth of the long edge,
/// so blur radii and grain grow with the photo: a 1200 px preview and the
/// full-size render look the same.
public enum AdjustRendering {
    public static func unit(longEdge: Double) -> Double { longEdge / 1000 }

    /// Soft light: the brighter tones, blurred wide and screened back over the
    /// photo in gamma-encoded values. Light is only added, never a blur in
    /// place of the photo, so texture stays.
    public struct Glow: Equatable, Sendable {
        /// Gaussian sigma, in pixels.
        public var radius: Double
        /// How much of the glow is screened over the photo.
        public var strength: Double
        /// Tones below this (sRGB, 0…1) don't glow.
        public var threshold: Double
    }

    public static func glow(_ amount: Double, longEdge: Double) -> Glow? {
        guard amount > 0 else { return nil }
        let amount = min(amount, 1)
        return Glow(radius: (12 + 16 * amount) * unit(longEdge: longEdge), strength: 0.75 * amount, threshold: 0.42 - 0.12 * amount)
    }

    /// Dark corners that leave the middle alone: none inside `radius` (from the
    /// centre), then falling off toward the corners.
    public struct Vignette: Equatable, Sendable {
        /// In pixels, from the centre.
        public var radius: Double
        public var intensity: Double
        public var falloff: Double
    }

    public static func vignette(_ amount: Double, width: Double, height: Double) -> Vignette? {
        guard amount > 0 else { return nil }
        let halfDiagonal = (width * width + height * height).squareRoot() / 2
        return Vignette(radius: 0.6 * halfDiagonal, intensity: min(amount, 1), falloff: 0.5)
    }

    /// Film grain: grey noise centred on 50% (neutral in a soft-light blend),
    /// one noise cell per unit, so it's as fine on the full-size photo as on
    /// the preview.
    public struct Grain: Equatable, Sendable {
        /// Spread of the noise around 50%.
        public var amount: Double
        /// Noise cell size, in pixels (at least one).
        public var scale: Double
    }

    public static func grain(_ amount: Double, longEdge: Double) -> Grain? {
        guard amount > 0 else { return nil }
        return Grain(amount: 0.22 * min(amount, 1), scale: max(1, 1.2 * unit(longEdge: longEdge)))
    }
}

// MARK: - Tone and tint

/// Fade, highlights, shadows and the pink-to-lilac split tone as one colour
/// map on gamma-encoded sRGB values, which the app hands to Core Image as a
/// colour cube. It's a map of colours, not of places, so it's the same at
/// every size.
public enum ToneMap {
    public struct Point: Equatable, Sendable {
        public var x: Double
        public var y: Double
    }

    /// The tone curve through five points (0, ¼, ½, ¾, 1). Fade lifts black
    /// and softens white (matte), shadows move the dark quarter without
    /// lifting black, highlights move the bright quarter without dimming white.
    public static func curvePoints(fade: Double, highlights: Double, shadows: Double) -> [Point] {
        [
            Point(x: 0, y: 0.14 * fade),
            Point(x: 0.25, y: 0.25 + 0.1 * shadows + 0.05 * fade),
            Point(x: 0.5, y: 0.5 + 0.03 * shadows + 0.03 * highlights + 0.01 * fade),
            Point(x: 0.75, y: 0.75 + 0.09 * highlights - 0.01 * fade),
            Point(x: 1, y: 1 - 0.05 * fade),
        ]
    }

    /// A monotone cubic (Fritsch–Carlson) through `points`: it never
    /// overshoots, so an increasing set of points gives an increasing curve.
    public struct Curve: Sendable {
        let xs: [Double]
        let ys: [Double]
        let tangents: [Double]

        public init(_ points: [Point]) {
            xs = points.map(\.x)
            ys = points.map(\.y)
            let count = points.count
            var slopes: [Double] = []
            for i in 0..<(count - 1) {
                slopes.append((ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]))
            }
            var m = [Double](repeating: 0, count: count)
            m[0] = slopes[0]
            m[count - 1] = slopes[count - 2]
            for i in 1..<(count - 1) {
                m[i] = slopes[i - 1] * slopes[i] <= 0 ? 0 : (slopes[i - 1] + slopes[i]) / 2
            }
            for i in 0..<(count - 1) where slopes[i] != 0 {
                let a = m[i] / slopes[i]
                let b = m[i + 1] / slopes[i]
                let length = a * a + b * b
                if length > 9 {
                    let t = 3 / length.squareRoot()
                    m[i] = t * a * slopes[i]
                    m[i + 1] = t * b * slopes[i]
                }
            }
            tangents = m
        }

        public func callAsFunction(_ x: Double) -> Double {
            if x <= xs[0] { return ys[0] }
            if x >= xs[xs.count - 1] { return ys[ys.count - 1] }
            var i = 0
            while x > xs[i + 1] { i += 1 }
            let h = xs[i + 1] - xs[i]
            let t = (x - xs[i]) / h
            let t2 = t * t
            let t3 = t2 * t
            return (2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * h * tangents[i]
                + (-2 * t3 + 3 * t2) * ys[i + 1] + (t3 - t2) * h * tangents[i + 1]
        }
    }

    /// Rec. 709 luma of gamma-encoded values: how light a colour looks.
    public static func luma(_ r: Double, _ g: Double, _ b: Double) -> Double {
        0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// Split toning: a colour shift for the shadows and a softer one for the
    /// highlights, each with no change of luma. The middle tones, where most
    /// skin is, get little of either, so skin stays natural at moderate values.
    public static func tintShift(luma: Double, tint: Double) -> (r: Double, g: Double, b: Double) {
        guard tint != 0 else { return (0, 0, 0) }
        let shadowWeight = 1 - smoothstep(0, 0.62, luma)
        let highlightWeight = smoothstep(0.55, 1, luma)
        let (shadow, highlight) = tint < 0 ? (pinkShadows, pinkHighlights) : (lilacShadows, lilacHighlights)
        let amount = min(abs(tint), 1)
        return (
            amount * (shadowWeight * shadow.r + highlightWeight * highlight.r),
            amount * (shadowWeight * shadow.g + highlightWeight * highlight.g),
            amount * (shadowWeight * shadow.b + highlightWeight * highlight.b)
        )
    }

    /// Luma-neutral shifts at full strength (green balances red and blue).
    static let pinkShadows = neutralShift(r: 0.05, b: 0.02)
    static let pinkHighlights = neutralShift(r: 0.028, b: 0.008)
    static let lilacShadows = neutralShift(r: 0.022, b: 0.06)
    static let lilacHighlights = neutralShift(r: 0.012, b: 0.032)

    static func neutralShift(r: Double, b: Double) -> (r: Double, g: Double, b: Double) {
        (r, -(0.2126 * r + 0.0722 * b) / 0.7152, b)
    }

    /// The whole map for one colour (gamma-encoded sRGB, 0…1).
    public static func map(_ r: Double, _ g: Double, _ b: Double, curve: Curve, tint: Double) -> (r: Double, g: Double, b: Double) {
        let toned = (curve(r), curve(g), curve(b))
        let shift = tintShift(luma: luma(toned.0, toned.1, toned.2), tint: tint)
        return (unit(toned.0 + shift.r), unit(toned.1 + shift.g), unit(toned.2 + shift.b))
    }

    /// The map as a colour cube for Core Image (`CIColorCubeWithColorSpace`
    /// in sRGB): `dimension`³ RGBA floats, red changing fastest, then green,
    /// then blue; alpha is always 1.
    public static func cube(for settings: AdjustmentSettings, dimension: Int = 32) -> [Float] {
        let curve = Curve(curvePoints(fade: settings.fade, highlights: settings.highlights, shadows: settings.shadows))
        let steps = (0..<dimension).map { Double($0) / Double(dimension - 1) }
        let toned = steps.map { curve($0) }
        var data = [Float](repeating: 1, count: dimension * dimension * dimension * 4)
        var index = 0
        for blue in toned {
            for green in toned {
                for red in toned {
                    let shift = tintShift(luma: luma(red, green, blue), tint: settings.tint)
                    data[index] = Float(unit(red + shift.r))
                    data[index + 1] = Float(unit(green + shift.g))
                    data[index + 2] = Float(unit(blue + shift.b))
                    index += 4
                }
            }
        }
        return data
    }

    static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = unit((x - edge0) / (edge1 - edge0))
        return t * t * (3 - 2 * t)
    }

    static func unit(_ value: Double) -> Double { min(max(value, 0), 1) }
}
