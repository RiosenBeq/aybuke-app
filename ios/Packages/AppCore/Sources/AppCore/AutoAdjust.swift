import Foundation

/// One-tap "Auto" for the Adjust tool, and the developer for RAW photos.
/// It reads a small sample of the photo's pixels and fixes what's off: dark,
/// flat, dull or blue photos. Good photos stay almost untouched, and every
/// value lands on the sliders, so she can fine-tune it.
public struct AutoAdjustment: Equatable, Sendable {
    public var brightness: Double
    public var contrast: Double
    public var saturation: Double
    public var warmth: Double
    public var sharpness: Double

    public static let neutral = AutoAdjustment(brightness: 0, contrast: 1, saturation: 1, warmth: 0, sharpness: 0)

    public init(brightness: Double, contrast: Double, saturation: Double, warmth: Double, sharpness: Double) {
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.warmth = warmth
        self.sharpness = sharpness
    }
}

public enum AutoAdjust {
    public struct Pixel: Equatable, Sendable {
        public var r: Double
        public var g: Double
        public var b: Double

        public init(r: Double, g: Double, b: Double) {
            self.r = r
            self.g = g
            self.b = b
        }

        var luma: Double { 0.299 * r + 0.587 * g + 0.114 * b }
        var saturation: Double {
            let high = max(r, g, b)
            return high > 0.05 ? (high - min(r, g, b)) / high : 0
        }
    }

    /// `pixels` is a downscaled sample (64×64 is plenty), RGB in 0…1.
    public static func plan(pixels: [Pixel]) -> AutoAdjustment {
        guard pixels.count >= 16 else { return .neutral }
        let lumas = pixels.map(\.luma).sorted()
        let mean = lumas.reduce(0, +) / Double(lumas.count)
        let low = lumas[Int(Double(lumas.count - 1) * 0.05)]
        let high = lumas[Int(Double(lumas.count - 1) * 0.95)]

        // Light: aim the average at a little under middle grey.
        let target = 0.48
        let brightness = abs(mean - target) < 0.04 ? 0 : clamp((target - mean) * 0.55, -0.12, 0.16)

        // Contrast: only for flat photos (a narrow 5–95% range).
        let range = high - low
        let contrast = clamp(1 + max(0, 0.78 - range) * 0.45, 1, 1.25)

        // Colour: lift dull photos, calm loud ones a touch.
        let meanSaturation = pixels.map(\.saturation).reduce(0, +) / Double(pixels.count)
        let saturation = clamp(1 + (0.32 - meanSaturation) * 0.9, 0.95, 1.3)

        // Warmth: correct a blue cast in the midtones, plus a hint of glow.
        // Warm photos flatter skin, so only very orange ones cool a little.
        let midtones = pixels.filter { (0.2...0.85).contains($0.luma) }
        let sample = midtones.count >= 8 ? midtones : pixels
        let red = sample.map(\.r).reduce(0, +) / Double(sample.count)
        let blue = sample.map(\.b).reduce(0, +) / Double(sample.count)
        let blueCast = blue - red
        let warmth = blueCast > 0
            ? clamp(blueCast * 2.5 + 0.05, 0, 0.4)
            : clamp(0.05 - max(0, -blueCast - 0.2), -0.15, 0.05)

        return AutoAdjustment(
            brightness: round2(brightness),
            contrast: round2(contrast),
            saturation: round2(saturation),
            warmth: round2(warmth),
            sharpness: 0.25
        )
    }

    private static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        min(max(value, low), high)
    }

    private static func round2(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}
