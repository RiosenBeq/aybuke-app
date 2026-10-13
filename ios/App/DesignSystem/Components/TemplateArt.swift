import SwiftUI

/// The colorful side of the brand for illustrated surfaces: six aura
/// palettes (soft gradients plus a sticker colour). Template cards cycle
/// through them so neighbours never match.
struct AuraPalette: Equatable {
    /// Gradient stops, top-leading to bottom-trailing.
    let colors: [Color]
    /// The sticker's gradient.
    let emblem: [Color]
    let isDark: Bool

    /// Label colour on this palette.
    var foreground: Color { isDark ? Palette.white : Palette.ink }

    static let bubblegum = AuraPalette(
        colors: [Color(hex: 0xFFD6E8), Color(hex: 0xFF9CC8), Color(hex: 0xFFC2A3)],
        emblem: [Color(hex: 0xFF5CA1), Color(hex: 0xC2338A)], isDark: false
    )
    static let lilac = AuraPalette(
        colors: [Color(hex: 0xEDE6FF), Color(hex: 0xC4B0FF), Color(hex: 0xFFC9E2)],
        emblem: [Color(hex: 0x8B6CF6), Color(hex: 0x5B3FD0)], isDark: false
    )
    static let sunset = AuraPalette(
        colors: [Color(hex: 0xFFEDB8), Color(hex: 0xFFBE9A), Color(hex: 0xFF8DB8)],
        emblem: [Color(hex: 0xFF7A59), Color(hex: 0xFF4F8B)], isDark: false
    )
    static let mint = AuraPalette(
        colors: [Color(hex: 0xDCFFF5), Color(hex: 0xA6EBDC), Color(hex: 0xC3CEFF)],
        emblem: [Color(hex: 0x1FB394), Color(hex: 0x4A7BF7)], isDark: false
    )
    static let nightGlam = AuraPalette(
        colors: [Color(hex: 0x4A1F6B), Color(hex: 0x1C1026), Color(hex: 0x7A2A6E)],
        emblem: [Color(hex: 0xFFC1DE), Color(hex: 0xFF5CA1)], isDark: true
    )
    static let butter = AuraPalette(
        colors: [Color(hex: 0xFFF6CC), Color(hex: 0xFFE38A), Color(hex: 0xFFBFD9)],
        emblem: [Color(hex: 0xFF9F1C), Color(hex: 0xFF5CA1)], isDark: false
    )

    static let all: [AuraPalette] = [.bubblegum, .nightGlam, .lilac, .sunset, .mint, .butter]

    static func at(_ index: Int) -> AuraPalette {
        all[((index % all.count) + all.count) % all.count]
    }
}

/// A soft multi-colour glow filling its frame: a mesh gradient on iOS 18,
/// a linear gradient with radial glows before that.
struct AuraFill: View {
    let palette: AuraPalette

    var body: some View {
        let colors = palette.colors
        if #available(iOS 18.0, *) {
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.55, 0.45], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: [
                    colors[0], colors[0], colors[1],
                    colors[0], colors[1], colors[2],
                    colors[1], colors[2], colors[2],
                ]
            )
        } else {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(RadialGradient(colors: [colors[0].opacity(0.9), .clear], center: .topLeading, startRadius: 0, endRadius: 160))
        }
    }
}

/// An SF Symbol as a glossy die-cut sticker: white border, gradient fill,
/// a highlight on top and a soft shadow.
struct StickerSymbol: View {
    let name: String
    let fill: [Color]
    let size: CGFloat

    var body: some View {
        let symbol = Image(systemName: name).font(.system(size: size, weight: .bold))
        let border = max(2, size * 0.075)
        ZStack {
            ForEach(0..<12, id: \.self) { step in
                let angle = Double(step) / 12 * 2 * .pi
                symbol
                    .foregroundStyle(.white)
                    .offset(x: cos(angle) * border, y: sin(angle) * border)
            }
            symbol
                .foregroundStyle(LinearGradient(colors: fill, startPoint: .topLeading, endPoint: .bottomTrailing))
            symbol
                .foregroundStyle(LinearGradient(colors: [.white.opacity(0.5), .clear], startPoint: .top, endPoint: .center))
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.16), radius: size * 0.14, y: size * 0.09)
        .accessibilityHidden(true)
    }
}

/// Illustrated art for a template without a photo thumbnail: an aura
/// gradient, the template's symbol as a sticker and a few sparkles placed
/// from the template's id, so every card is its own little poster.
struct TemplateArt: View {
    let symbolName: String
    let palette: AuraPalette
    let seed: String

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let emblem = min(size.width * 0.4, 66)
            ZStack {
                AuraFill(palette: palette)
                Circle()
                    .fill(.white.opacity(palette.isDark ? 0.08 : 0.35))
                    .frame(width: size.width * 0.78)
                    .blur(radius: 18)
                    .offset(y: -size.height * 0.1)
                ForEach(Array(sparkles(in: size).enumerated()), id: \.offset) { _, sparkle in
                    Image(systemName: sparkle.heart ? "heart.fill" : "sparkle")
                        .font(.system(size: sparkle.size, weight: .bold))
                        .foregroundStyle(sparkle.heart ? palette.emblem[0].opacity(0.75) : .white.opacity(0.9))
                        .rotationEffect(.degrees(sparkle.angle))
                        .position(sparkle.point)
                }
                StickerSymbol(name: symbolName, fill: palette.emblem, size: emblem)
                    .rotationEffect(.degrees(tilt))
                    .position(x: size.width / 2, y: size.height * 0.4)
            }
        }
        .accessibilityHidden(true)
    }

    private var hash: UInt64 {
        // FNV-1a: stable across launches (String.hashValue isn't).
        seed.utf8.reduce(14_695_981_039_346_656_037) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }

    private var tilt: Double { Double(Int(hash % 13)) - 6 }

    private struct Sparkle {
        let point: CGPoint
        let size: CGFloat
        let angle: Double
        let heart: Bool
    }

    /// Three sparkles (one sometimes a heart) around the sticker, away from
    /// the label at the bottom.
    private func sparkles(in size: CGSize) -> [Sparkle] {
        var generator = SplitMix64(seed: hash)
        let spots: [CGPoint] = [CGPoint(x: 0.18, y: 0.14), CGPoint(x: 0.84, y: 0.2), CGPoint(x: 0.22, y: 0.58), CGPoint(x: 0.8, y: 0.6)]
        return spots.enumerated().compactMap { index, spot in
            let roll = generator.next()
            if index == 3, roll % 2 == 0 { return nil }
            let jitter = CGFloat(roll % 9) / 100 - 0.04
            return Sparkle(
                point: CGPoint(x: (spot.x + jitter) * size.width, y: (spot.y - jitter) * size.height),
                size: CGFloat(9 + roll % 9),
                angle: Double(roll % 30) - 15,
                heart: index == 2 && roll % 3 == 0
            )
        }
    }
}
