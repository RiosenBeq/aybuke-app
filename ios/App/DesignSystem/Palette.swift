import SwiftUI
import UIKit

/// Brand colour tokens — the "Blush" palette. Six exact swatches: blush pink,
/// petal, ink, charcoal, paper and white. Light is the default appearance;
/// every semantic token also has a dark value for people who pick Dark in
/// Settings. Values and contrast checks: docs/02-brand-identity.md
enum Palette {
    // MARK: Brand swatches (fixed, never adapt to the appearance)
    static let blush = Color(hex: 0xF7C1D9)
    static let petal = Color(hex: 0xF8E0EA)
    static let ink = Color(hex: 0x121212)
    static let charcoal = Color(hex: 0x24272A)
    static let paper = Color(hex: 0xF8F8F6)
    static let white = Color(hex: 0xFFFFFF)

    // MARK: Surfaces — petal-pink canvas, white cards
    static let background = Color(light: 0xF8E0EA, dark: 0x121212)
    static let surface = Color(light: 0xFFFFFF, dark: 0x24272A)
    static let surfaceRaised = Color(light: 0xF8F8F6, dark: 0x303337)
    static let stroke = Color(light: 0x121212, dark: 0xFFFFFF, opacity: 0.08)
    static let strokeStrong = Color(light: 0x121212, dark: 0xFFFFFF, opacity: 0.16)
    /// Soft drop shadow for cards in light mode (dark mode relies on strokes).
    static let shadow = Color(light: 0x121212, dark: 0x000000, lightOpacity: 0.07, darkOpacity: 0)

    // MARK: Text — ink on petal is 15:1, secondary 5.9:1, tertiary 4.6:1
    static let textPrimary = Color(light: 0x121212, dark: 0xF8F8F6)
    static let textSecondary = Color(light: 0x5C5457, dark: 0xAAAAA8)
    static let textTertiary = Color(light: 0x6E6468, dark: 0x90908F)

    // MARK: Brand roles
    /// Blush: selection, highlights, hero fills and glows.
    static let primary = blush
    /// Label on blush (12.1:1). Never put white text on blush.
    static let onPrimary = ink
    /// The one primary action per screen, links and tints: ink on the light
    /// canvas, blush on the dark one.
    static let accent = Color(light: 0x121212, dark: 0xF7C1D9)
    /// Label on `accent`: blush on ink / ink on blush (12.1:1 both ways).
    static let onAccent = Color(light: 0xF7C1D9, dark: 0x121212)

    // MARK: Feedback (functional colours — always paired with an icon)
    static let success = Color(light: 0x0B7A54, dark: 0x34D399)
    static let warning = Color(light: 0x8A6100, dark: 0xFFD43B)
    static let danger = Color(light: 0xB42318, dark: 0xFF6B6B)

    /// Colours of the slow ambient glow behind hero areas.
    static let glowColors: [Color] = [blush, white, blush]
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

    /// A colour that resolves per appearance (light / dark).
    init(light: UInt32, dark: UInt32, opacity: Double = 1) {
        self.init(light: light, dark: dark, lightOpacity: opacity, darkOpacity: opacity)
    }

    init(light: UInt32, dark: UInt32, lightOpacity: Double, darkOpacity: Double) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkOpacity)
                : UIColor(hex: light, alpha: lightOpacity)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    /// Parses "#RRGGBB" strings (style swatches in the catalog).
    convenience init?(hexString: String) {
        let digits = hexString.hasPrefix("#") ? String(hexString.dropFirst()) : hexString
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(hex: value)
    }

    /// Fixed brand swatches for images rendered outside SwiftUI (share cards,
    /// watermarks). Same values as `Palette`.
    static let brandBlush = UIColor(hex: 0xF7C1D9)
    static let brandPetal = UIColor(hex: 0xF8E0EA)
    static let brandInk = UIColor(hex: 0x121212)
    static let brandCharcoal = UIColor(hex: 0x24272A)
    static let brandPaper = UIColor(hex: 0xF8F8F6)
}

/// Flat pairings of brand swatches for artwork without a photo (template
/// cards, style tiles). Picked by position so rows get a steady
/// blush / ink / white / charcoal rhythm, and the same item always gets the
/// same tone on every screen.
enum PaletteTone: CaseIterable {
    case blush, ink, white, charcoal

    static func at(_ index: Int) -> PaletteTone {
        allCases[((index % allCases.count) + allCases.count) % allCases.count]
    }

    var fill: Color {
        switch self {
        case .blush: return Palette.blush
        case .ink: return Palette.ink
        case .white: return Palette.white
        case .charcoal: return Palette.charcoal
        }
    }

    /// Text and glyphs on `fill`.
    var foreground: Color {
        switch self {
        case .blush, .white: return Palette.ink
        case .ink: return Palette.blush
        case .charcoal: return Palette.white
        }
    }

    var isDark: Bool { self == .ink || self == .charcoal }
}
