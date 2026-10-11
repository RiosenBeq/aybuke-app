import SwiftUI

/// Brand color tokens. The app is dark-first so photos are the brightest thing
/// on screen; one warm signature gradient is reserved for primary actions.
/// Values and rationale: docs/02-brand-identity.md
enum Palette {
    // MARK: Surfaces — near-neutral graphite so photos stay true-to-color
    static let background = Color(hex: 0x0C0C0E)
    static let surface = Color(hex: 0x17171B)
    static let surfaceRaised = Color(hex: 0x222228)
    static let stroke = Color.white.opacity(0.08)
    static let strokeStrong = Color.white.opacity(0.16)

    // MARK: Text — warm off-white (17.6:1 on background)
    static let textPrimary = Color(hex: 0xF5F3EE)
    static let textSecondary = Color(hex: 0xA9A7A2)
    static let textTertiary = Color(hex: 0x8E8C87)

    // MARK: Brand — "Golden Hour" amber, the one hue reserved for primary actions
    static let primary = Color(hex: 0xFF9A3D)
    static let gradientStart = Color(hex: 0xFFC25C)
    static let gradientEnd = Color(hex: 0xFF7A3D)
    /// Dark ink for labels on amber (7.2–11.6:1). Never put white text on amber (2.1:1).
    static let onPrimary = Color(hex: 0x1A1206)
    /// "Blue hour" secondary for selection, links and info.
    static let secondary = Color(hex: 0x5B8CFF)

    // MARK: Feedback (always paired with an icon, never color alone)
    static let success = Color(hex: 0x34D399)
    static let warning = Color(hex: 0xFFD43B)
    static let danger = Color(hex: 0xFF5C5C)

    static let brandGradient = LinearGradient(
        colors: [gradientStart, gradientEnd],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Warm "light sweep" colors for ambient glows and the generating state.
    static let auroraColors: [Color] = [gradientStart, gradientEnd, secondary]
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// Parses "#RRGGBB" strings coming from the template catalog.
    init?(hexString: String) {
        let digits = hexString.hasPrefix("#") ? String(hexString.dropFirst()) : hexString
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(hex: value)
    }
}

extension Array where Element == String {
    /// Template/style gradient stops → SwiftUI colors (falls back to brand colors).
    var gradientColors: [Color] {
        let colors = compactMap { Color(hexString: $0) }
        return colors.count >= 2 ? colors : [Palette.gradientStart, Palette.gradientEnd]
    }
}
