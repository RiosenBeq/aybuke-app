import Foundation

// Glow Cam: Retro Cam's Glow tab. Live looks that flatter with light, colour,
// a sheer makeup tint and sparkle, never by retouching: nothing here smooths
// or blurs skin, reshapes a face or body, slims or changes skin tone
// (AGENTS.md §5). The looks are the editor's Adjust vibes, so a Glow photo
// gets the same numbers as that vibe picked in the editor, and the makeup
// colours are Makeup Studio's. The numbers live here so the live preview and
// the full-size still match; the app's Core Image code only draws them.

/// What the Glow tab is set to.
public struct GlowCamSettings: Hashable, Sendable {
    /// One of `GlowCam.vibeIDs`; nil is Natural (her own light and colour).
    public var vibeID: String?
    /// The quick sliders, −1…1; zero changes nothing.
    public var brightness: Double
    public var contrast: Double
    /// Soft glints of light drifting through the picture (`SparkleField`).
    public var sparkle: Bool
    /// The live makeup tint; it starts off (`.none` for both).
    public var lips: MakeupLips
    public var cheeks: MakeupCheeks

    public init(vibeID: String? = nil, brightness: Double = 0, contrast: Double = 0, sparkle: Bool = false,
                lips: MakeupLips = .none, cheeks: MakeupCheeks = .none) {
        self.vibeID = vibeID
        self.brightness = brightness
        self.contrast = contrast
        self.sparkle = sparkle
        self.lips = lips
        self.cheeks = cheeks
    }

    public var vibe: AdjustVibe? { vibeID.flatMap(AdjustVibes.preset(id:)) }

    /// The editor's Adjust sliders for this look: her light from the quick
    /// sliders, then the vibe put on exactly as the editor puts it on an
    /// untouched photo.
    public var adjustment: AdjustmentSettings {
        var settings = AdjustmentSettings.neutral
        settings.brightness = GlowCam.brightness(slider: brightness)
        settings.contrast = GlowCam.contrast(slider: contrast)
        guard let vibe else { return settings.clamped() }
        return vibe.applied(to: settings, replacing: nil)
    }

    /// A lip or cheek colour is on, so the camera looks for faces.
    public var hasTint: Bool { lips != .none || cheeks != .none }

    /// The quick sliders are away from the middle.
    public var hasLightChange: Bool { brightness != 0 || contrast != 0 }
}

public enum GlowCam {
    /// The Glow tab's looks after Natural, in the order its strip shows them.
    public static let vibeIDs = ["dreamy", "golden", "analog", "moody"]

    public static var vibes: [AdjustVibe] { vibeIDs.compactMap(AdjustVibes.preset(id:)) }

    /// Half the editor's Brightness range: a quick lift in the camera, not a grade.
    public static func brightness(slider: Double) -> Double {
        0.15 * unit(slider)
    }

    /// About half the editor's Contrast range either way.
    public static func contrast(slider: Double) -> Double {
        let value = unit(slider)
        return 1 + (value < 0 ? 0.15 : 0.2) * value
    }

    // MARK: Makeup tint

    /// Makeup Studio's lip colours that read well as a sheer live tint (gloss
    /// is shine rather than colour; the darkest browns and plums go muddy).
    public static let lipColors: [MakeupLips] = [.softPink, .rosy, .coral, .cherryRed, .berry, .mocha]
    /// Makeup Studio's blushes (its iridescent shine is light, not colour).
    public static let cheekColors: [MakeupCheeks] = [.softBlush, .rosyFlush, .drapedBlush, .sunKissed]

    /// A sheer wash inside the lip line. Deep shades mix in some multiply so
    /// they read as colour rather than grey; light ones are only their hue
    /// over her own lips, which keep their light and texture.
    public static func lipTint(_ lips: MakeupLips) -> TintBlend? {
        guard lipColors.contains(lips), let color = lips.swatch.flatMap(GlowColor.init(hex:)) else { return nil }
        return TintBlend(color: color, opacity: 0.5, depth: min(max(0.55 - color.luma, 0), 0.4))
    }

    /// A soft flush of colour on the apples of the cheeks, fading out to nothing.
    public static func cheekTint(_ cheeks: MakeupCheeks) -> TintBlend? {
        guard cheekColors.contains(cheeks), let color = cheeks.swatch.flatMap(GlowColor.init(hex:)) else { return nil }
        return TintBlend(color: color, opacity: 0.26, depth: 0.35)
    }

    static func unit(_ value: Double) -> Double {
        value.isFinite ? min(max(value, -1), 1) : 0
    }
}

/// An sRGB colour, 0…1 per channel.
public struct GlowColor: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// "#RRGGBB", as Makeup Studio's swatches are written.
    public init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    /// How light it looks.
    public var luma: Double { ToneMap.luma(red, green, blue) }
}

/// How a makeup colour goes on: a sheer wash that keeps the light and texture
/// underneath (the colour's hue and saturation over her own lightness), with
/// some multiply mixed in for depth. Never opaque paint.
public struct TintBlend: Hashable, Sendable {
    public var color: GlowColor
    /// Strength of the wash where its mask is full.
    public var opacity: Double
    /// Share of multiply in the wash, 0…1.
    public var depth: Double
}

// MARK: - Sparkle

/// Sparkle: a few soft bokeh dots and star glints drifting up through the
/// picture and twinkling, like light catching glitter in the air. Places are
/// fractions of the frame and sizes fractions of its long edge, so the live
/// preview and the full-size still show them in the same spots. The middle,
/// where a face usually is, stays clear.
public enum SparkleField {
    public enum Kind: Sendable {
        case bokeh, star
    }

    public struct Glint: Equatable, Sendable {
        /// 0…1 from the left.
        public var x: Double
        /// 0…1 from the bottom (Core Image's way up).
        public var y: Double
        /// A fraction of the frame's long edge.
        public var radius: Double
        /// 0…1.
        public var opacity: Double
        public var kind: Kind
        public var color: GlowColor
    }

    public static let count = 20
    /// The clear middle: no glint closer than `clearRadius` to this point
    /// (fractions of the frame), full strength from `fullRadius`.
    public static let clearX = 0.5
    public static let clearY = 0.56
    public static let clearRadius = 0.24
    public static let fullRadius = 0.42

    /// Warm white, gold, blush and lilac light.
    static let colors = [
        GlowColor(red: 1, green: 0.96, blue: 0.9),
        GlowColor(red: 1, green: 0.88, blue: 0.62),
        GlowColor(red: 1, green: 0.74, blue: 0.86),
        GlowColor(red: 0.86, green: 0.8, blue: 1),
    ]

    /// Every glint at `seconds` since the camera started.
    public static func glints(at seconds: Double) -> [Glint] {
        let time = seconds.isFinite ? max(0, seconds) : 0
        return (0..<count).map { glint($0, at: time) }
    }

    static func glint(_ index: Int, at time: Double) -> Glint {
        func random(_ salt: UInt64) -> Double { SparkleField.random(index, salt) }
        let isStar = random(1) < 0.3
        // A slow rise with a little sway, wrapping round at the top.
        let rise = 0.012 + 0.018 * random(4)
        let y = fraction(random(3) + rise * time)
        let sway = (0.008 + 0.014 * random(5)) * sin(2 * .pi * ((0.15 + 0.2 * random(6)) * time + random(7)))
        let x = random(2) + sway
        // Bokeh breathes; a star flashes briefly once a cycle.
        let wave = 0.5 - 0.5 * cos(2 * .pi * (time / (2.4 + 2.6 * random(8)) + random(9)))
        var opacity = isStar ? 0.85 * wave * wave * wave : (0.15 + 0.18 * random(10)) * (0.4 + 0.6 * wave)
        // In and out at the edges instead of popping when it wraps.
        opacity *= smoothstep(0, 0.08, y) * (1 - smoothstep(0.92, 1, y))
        let distance = ((x - clearX) * (x - clearX) + (y - clearY) * (y - clearY)).squareRoot()
        opacity *= smoothstep(clearRadius, fullRadius, distance)
        let radius = isStar ? 0.01 + 0.012 * random(11) : 0.012 + 0.02 * random(11)
        let color = colors[min(colors.count - 1, Int(random(12) * Double(colors.count)))]
        return Glint(x: x, y: y, radius: radius, opacity: min(max(opacity, 0), 1), kind: isStar ? .star : .bokeh, color: color)
    }

    /// The same number for the same glint and salt on every device (SplitMix64), 0..<1.
    static func random(_ index: Int, _ salt: UInt64) -> Double {
        var z = UInt64(truncatingIfNeeded: index) &* 0x9E37_79B9_7F4A_7C15 &+ salt &* 0xD1B5_4A32_D192_ED03
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(UInt64(1) << 53)
    }

    static func fraction(_ value: Double) -> Double {
        value - value.rounded(.down)
    }

    static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
