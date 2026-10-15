import Foundation

// DSLR '12, the free on-device effect: the subject stays crisp, the
// background gets a real lens blur with round bokeh, and a "DSLR" grade goes
// over the whole photo. The numbers live here so the editor's preview, the
// full-size render and Shortcuts agree; the app's Core Image pipeline
// (`LensBlur`, `RetroEffect.dslr12`) only turns them into filters.

/// The lens she picks under the effect strip. A longer lens blurs more.
public enum DSLRLens: String, CaseIterable, Identifiable, Sendable {
    case portrait85
    case standard50
    case wide35

    public var id: String { rawValue }

    /// The classic portrait lens: the most blur, as the effect's look promises.
    public static let standard: DSLRLens = .portrait85

    public var focalLength: Int {
        switch self {
        case .portrait85: return 85
        case .standard50: return 50
        case .wide35: return 35
        }
    }

    /// Radius of the background's lens blur, as a share of the photo's long
    /// edge, so a preview and a full-size render look alike.
    public var blurRadius: Double {
        switch self {
        case .portrait85: return 0.026
        case .standard50: return 0.017
        case .wide35: return 0.011
        }
    }

    /// Right around the subject the background is nearer the plane of focus:
    /// it gets this share of the full blur, growing to all of it further away.
    public static let nearBlurShare = 0.45

    /// The lens blur runs on a copy this long (pixels), then is scaled back
    /// up: a blurred background has no fine detail to lose, and the blur
    /// costs the same for a preview and a 48 MP photo.
    public static let workingLongEdge = 1024.0
}

/// The "DSLR" colour grade: a gentle S-curve, warm highlights and slightly
/// cool shadows. Luma-neutral colour shifts, small in the mid-tones where
/// most skin is, so skin keeps its own colour and texture.
public enum DSLRGrade {
    static let curve = ToneMap.Curve([
        ToneMap.Point(x: 0, y: 0.01),
        ToneMap.Point(x: 0.25, y: 0.225),
        ToneMap.Point(x: 0.5, y: 0.5),
        ToneMap.Point(x: 0.75, y: 0.78),
        ToneMap.Point(x: 1, y: 0.99),
    ])
    static let warmHighlights = ToneMap.neutralShift(r: 0.03, b: -0.03)
    static let coolShadows = ToneMap.neutralShift(r: -0.012, b: 0.022)

    /// The grade for one colour (gamma-encoded sRGB, 0…1).
    public static func map(_ r: Double, _ g: Double, _ b: Double) -> (r: Double, g: Double, b: Double) {
        let toned = (curve(r), curve(g), curve(b))
        let luma = ToneMap.luma(toned.0, toned.1, toned.2)
        let highlight = ToneMap.smoothstep(0.5, 1, luma)
        let shadow = 1 - ToneMap.smoothstep(0, 0.42, luma)
        return (
            ToneMap.unit(toned.0 + highlight * warmHighlights.r + shadow * coolShadows.r),
            ToneMap.unit(toned.1 + highlight * warmHighlights.g + shadow * coolShadows.g),
            ToneMap.unit(toned.2 + highlight * warmHighlights.b + shadow * coolShadows.b)
        )
    }

    /// The grade as a colour cube for `CIColorCubeWithColorSpace` in sRGB,
    /// laid out like `ToneMap.cube`.
    public static func cube(dimension: Int = 32) -> [Float] {
        let steps = (0..<dimension).map { Double($0) / Double(dimension - 1) }
        var data = [Float](repeating: 1, count: dimension * dimension * dimension * 4)
        var index = 0
        for blue in steps {
            for green in steps {
                for red in steps {
                    let mapped = map(red, green, blue)
                    data[index] = Float(mapped.r)
                    data[index + 1] = Float(mapped.g)
                    data[index + 2] = Float(mapped.b)
                    index += 4
                }
            }
        }
        return data
    }

    /// Fine grain and a mild vignette, like a clean full-frame sensor.
    public static let grainAmount = 0.035
    public static let vignetteIntensity = 0.32
    public static let vignetteRadius = 1.9
}

/// Cut out's Edge control, from crisp (0) through Vision's own edge (0.5)
/// to a soft feather (1). Crisp narrows the soft part of the edge; soft
/// pulls it in and blurs it, and the app keeps the feather inside the
/// original edge, so it never reaches out into the old background (no halo).
public enum CutoutEdge {
    public static let natural = 0.5

    public struct Plan: Equatable, Sendable {
        /// The matte is remapped so `low` becomes 0 and `high` becomes 1.
        public var low: Double
        public var high: Double
        /// How far the edge moves in, as a share of the long edge.
        public var choke: Double
        /// Gaussian sigma of the feather, as a share of the long edge.
        public var feather: Double

        public var isIdentity: Bool { low == 0 && high == 1 && choke == 0 && feather == 0 }
    }

    public static func plan(_ value: Double) -> Plan {
        let value = min(max(value, 0), 1)
        if value <= natural {
            // 0…1 from natural to crisp.
            let crisp = (natural - value) / natural
            return Plan(low: 0.42 * crisp, high: 1 - 0.36 * crisp, choke: 0, feather: 0)
        }
        let soft = (value - natural) / (1 - natural)
        return Plan(low: 0, high: 1, choke: 0.004 * soft, feather: 0.004 * soft)
    }
}
