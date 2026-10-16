import SwiftUI
import AppCore

/// Drawn art for a local season's banner and Coming soon card: lanterns,
/// blossoms, a harvest moon, paper flags or marigolds, in the season's
/// palette. Made in code (no photos, no emoji), so it's sharp at any size
/// and never shows a face. Decorations only, never anyone's dress.
struct SeasonArt: View {
    let theme: SeasonalTheme

    var body: some View {
        Canvas { context, size in
            let frame = ArtFrame(size: size)
            switch theme {
            case .eidAlFitr: SeasonScene.eidAlFitr(&context, frame)
            case .eidAlAdha: SeasonScene.eidAlAdha(&context, frame)
            case .lunarNewYear: SeasonScene.lunarNewYear(&context, frame)
            case .chuseok: SeasonScene.chuseok(&context, frame)
            case .hanami: SeasonScene.hanami(&context, frame)
            case .tanabata: SeasonScene.tanabata(&context, frame)
            case .carnaval: SeasonScene.carnaval(&context, frame)
            case .festaJunina: SeasonScene.festaJunina(&context, frame)
            case .diaDeMuertos: SeasonScene.diaDeMuertos(&context, frame)
            case .halloween, .winter, .galentines: break
            }
        }
        .accessibilityHidden(true)
    }
}

/// The art on its season's colours, as a small rounded tile (Coming soon).
struct SeasonArtTile: View {
    let theme: SeasonalTheme
    var side: CGFloat = 58

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: side * 0.24, style: .continuous)
        AuraFill(palette: theme.bannerPalette)
            .overlay { SeasonArt(theme: theme) }
            .frame(width: side, height: side)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Palette.stroke, lineWidth: 1))
            .shadow(color: theme.bannerPalette.colors[1].opacity(0.35), radius: 8, y: 4)
            .accessibilityHidden(true)
    }
}

extension AuraPalette {
    // The local seasons' colours: a banner palette and a second one, so the
    // two looks of a season sit side by side on Explore in its colours.
    static let eidNight = AuraPalette(
        colors: [Color(hex: 0x0E3B43), Color(hex: 0x12524F), Color(hex: 0x3A2A5C)],
        emblem: [Color(hex: 0xF7D58B), Color(hex: 0xE0A84F)], isDark: true
    )
    static let eidDay = AuraPalette(
        colors: [Color(hex: 0xFFF4DC), Color(hex: 0xF9DCA8), Color(hex: 0xF6C9C4)],
        emblem: [Color(hex: 0xC98A2E), Color(hex: 0x0F766E)], isDark: false
    )
    static let lunarRed = AuraPalette(
        colors: [Color(hex: 0xB3122E), Color(hex: 0x7A0C1F), Color(hex: 0xD9472B)],
        emblem: [Color(hex: 0xFFD66B), Color(hex: 0xF5A623)], isDark: true
    )
    static let lunarGold = AuraPalette(
        colors: [Color(hex: 0xFFF3D6), Color(hex: 0xFFD27A), Color(hex: 0xFFB3A7)],
        emblem: [Color(hex: 0xD7263D), Color(hex: 0xB5121B)], isDark: false
    )
    static let harvestNight = AuraPalette(
        colors: [Color(hex: 0x1F2A5A), Color(hex: 0x2E1F4F), Color(hex: 0x4B3A78)],
        emblem: [Color(hex: 0xFFD98A), Color(hex: 0xF28C38)], isDark: true
    )
    static let persimmonDay = AuraPalette(
        colors: [Color(hex: 0xFFF0DB), Color(hex: 0xFFC48C), Color(hex: 0xF7A6A0)],
        emblem: [Color(hex: 0xE8590C), Color(hex: 0x2F9E44)], isDark: false
    )
    static let sakura = AuraPalette(
        colors: [Color(hex: 0xFFE4EE), Color(hex: 0xFFC2D6), Color(hex: 0xDCD6FF)],
        emblem: [Color(hex: 0xF06292), Color(hex: 0xC2185B)], isDark: false
    )
    static let sakuraNight = AuraPalette(
        colors: [Color(hex: 0x2B2350), Color(hex: 0x4A2C5E), Color(hex: 0x9C4F8A)],
        emblem: [Color(hex: 0xFFC1DA), Color(hex: 0xFF8FB8)], isDark: true
    )
    static let starNight = AuraPalette(
        colors: [Color(hex: 0x0F1D4A), Color(hex: 0x1B2F6E), Color(hex: 0x3B2A6B)],
        emblem: [Color(hex: 0xFFE27A), Color(hex: 0x8EC5FF)], isDark: true
    )
    static let tanzaku = AuraPalette(
        colors: [Color(hex: 0xE6F0FF), Color(hex: 0xFFE7F3), Color(hex: 0xFFF6C9)],
        emblem: [Color(hex: 0x3A5BD9), Color(hex: 0xFF7AB6)], isDark: false
    )
    static let carnaval = AuraPalette(
        colors: [Color(hex: 0x6A1B9A), Color(hex: 0xC2185B), Color(hex: 0xEF6C00)],
        emblem: [Color(hex: 0xFFEB3B), Color(hex: 0x00E5FF)], isDark: true
    )
    static let carnavalSun = AuraPalette(
        colors: [Color(hex: 0xFFF59D), Color(hex: 0xFFB3D9), Color(hex: 0xA5F3FC)],
        emblem: [Color(hex: 0xE91E63), Color(hex: 0x7B2FF7)], isDark: false
    )
    static let arraia = AuraPalette(
        colors: [Color(hex: 0x1E3A5F), Color(hex: 0x2B4C7E), Color(hex: 0xB4532A)],
        emblem: [Color(hex: 0xFFD54F), Color(hex: 0xFF7043)], isDark: true
    )
    static let junina = AuraPalette(
        colors: [Color(hex: 0xFFF3D1), Color(hex: 0xFFD3A8), Color(hex: 0xBFE6FF)],
        emblem: [Color(hex: 0xE53935), Color(hex: 0x1E88E5)], isDark: false
    )
    static let muertos = AuraPalette(
        colors: [Color(hex: 0x4A1450), Color(hex: 0x8E1E5B), Color(hex: 0xD9620B)],
        emblem: [Color(hex: 0xFFB300), Color(hex: 0xFF4081)], isDark: true
    )
    static let cempasuchil = AuraPalette(
        colors: [Color(hex: 0xFFE8C2), Color(hex: 0xFFC46B), Color(hex: 0xFFB0D0)],
        emblem: [Color(hex: 0xE65100), Color(hex: 0xC2185B)], isDark: false
    )
}

// MARK: - Drawing

/// Unit coordinates over the canvas; `u` is its shorter side.
private struct ArtFrame {
    let size: CGSize
    var u: CGFloat { min(size.width, size.height) }

    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size.width, y: y * size.height) }
}

private extension Color {
    static func hex(_ value: UInt32, _ opacity: Double = 1) -> Color { Color(hex: value, opacity: opacity) }
}

private enum SeasonScene {
    static func eidAlFitr(_ c: inout GraphicsContext, _ f: ArtFrame) {
        Draw.glow(&c, at: f.p(0.56, 0.62), radius: f.u * 0.6, color: .hex(0xFFC56B), opacity: 0.32)
        for (x, y, s) in [(0.1, 0.22, 0.08), (0.92, 0.66, 0.065), (0.42, 0.1, 0.05), (0.76, 0.92, 0.055), (0.12, 0.78, 0.045)] {
            Draw.sparkle(&c, at: f.p(x, y), size: f.u * s, color: .hex(0xFFE7A8))
        }
        let metal = Color.hex(0xE9B949), shade = Color.hex(0x7A4E18), light = Color.hex(0xFFB547)
        Draw.brassLantern(&c, x: f.size.width * 0.27, hang: f.u * 0.12, height: f.u * 0.5, metal: metal, shade: shade, light: light)
        Draw.brassLantern(&c, x: f.size.width * 0.58, hang: f.u * 0.3, height: f.u * 0.6, metal: metal, shade: shade, light: light)
        Draw.brassLantern(&c, x: f.size.width * 0.86, hang: f.u * 0.06, height: f.u * 0.42, metal: metal, shade: shade, light: light)
    }

    static func eidAlAdha(_ c: inout GraphicsContext, _ f: ArtFrame) {
        // A pointed courtyard arch, a lantern from its top, flowers below.
        var arch = Path()
        arch.move(to: f.p(0.16, 1.05))
        arch.addLine(to: f.p(0.16, 0.5))
        arch.addQuadCurve(to: f.p(0.5, 0.08), control: f.p(0.16, 0.14))
        arch.addQuadCurve(to: f.p(0.84, 0.5), control: f.p(0.84, 0.14))
        arch.addLine(to: f.p(0.84, 1.05))
        c.fill(arch, with: .color(.white.opacity(0.34)))
        c.stroke(arch, with: .color(.hex(0xC9973B)), style: StrokeStyle(lineWidth: f.u * 0.028, lineJoin: .round))
        Draw.glow(&c, at: f.p(0.5, 0.5), radius: f.u * 0.42, color: .hex(0xFFC46B), opacity: 0.45)
        Draw.brassLantern(&c, x: f.size.width * 0.5, top: f.size.height * 0.08, hang: f.u * 0.05, height: f.u * 0.44,
                          metal: .hex(0xC98A2E), shade: .hex(0x6E4314), light: .hex(0xFFB547))
        for (x, y, angle) in [(0.1, 0.84, -0.6), (0.24, 0.93, 0.4), (0.78, 0.9, -0.3), (0.92, 0.8, 0.7)] {
            Draw.leaf(&c, at: f.p(x, y), length: f.u * 0.13, angle: angle, color: .hex(0x7CB342))
        }
        let cream = (petal: Color.hex(0xFFF8EE), edge: Color.hex(0xF3C9A6))
        let rose = (petal: Color.hex(0xFFC9D6), edge: Color.hex(0xE07A95))
        for (x, y, r, colors) in [(0.14, 0.9, 0.11, rose), (0.31, 0.97, 0.085, cream), (0.7, 0.96, 0.09, cream), (0.88, 0.87, 0.12, rose)] {
            Draw.blossom(&c, at: f.p(x, y), radius: f.u * r, petal: colors.petal, edge: colors.edge, heart: .hex(0xF2B84B))
        }
    }

    static func lunarNewYear(_ c: inout GraphicsContext, _ f: ArtFrame) {
        Draw.firework(&c, at: f.p(0.2, 0.22), radius: f.u * 0.17, color: .hex(0xFFD66B))
        Draw.firework(&c, at: f.p(0.66, 0.12), radius: f.u * 0.1, color: .hex(0xFFB3C1), rays: 10)
        Draw.firework(&c, at: f.p(0.92, 0.32), radius: f.u * 0.07, color: .hex(0xFFE9A8), rays: 8)
        let red = Color.hex(0xE53935), deep = Color.hex(0x8E0E1A), gold = Color.hex(0xFFC94D)
        Draw.roundLantern(&c, center: f.p(0.46, 0.44), width: f.u * 0.36, height: f.u * 0.3, red: red, deep: deep, gold: gold)
        Draw.roundLantern(&c, center: f.p(0.82, 0.66), width: f.u * 0.26, height: f.u * 0.22, red: red, deep: deep, gold: gold)
        // A plum branch from the corner.
        var branch = Path()
        branch.move(to: f.p(-0.05, 1.0))
        branch.addQuadCurve(to: f.p(0.36, 0.7), control: f.p(0.16, 0.74))
        var twig = Path()
        twig.move(to: f.p(0.15, 0.82))
        twig.addQuadCurve(to: f.p(0.07, 0.6), control: f.p(0.07, 0.72))
        c.stroke(branch, with: .color(.hex(0x4E2A22)), style: StrokeStyle(lineWidth: f.u * 0.032, lineCap: .round))
        c.stroke(twig, with: .color(.hex(0x4E2A22)), style: StrokeStyle(lineWidth: f.u * 0.02, lineCap: .round))
        for (x, y, r) in [(0.36, 0.7, 0.075), (0.25, 0.75, 0.055), (0.07, 0.6, 0.055), (0.15, 0.86, 0.06)] {
            Draw.blossom(&c, at: f.p(x, y), radius: f.u * r, petal: .hex(0xFFE0E8), edge: .hex(0xFF8FAB), heart: .hex(0xFFD54F))
        }
    }

    static func chuseok(_ c: inout GraphicsContext, _ f: ArtFrame) {
        for (x, y, r) in [(0.12, 0.14, 0.012), (0.3, 0.3, 0.008), (0.9, 0.12, 0.01), (0.2, 0.5, 0.007), (0.95, 0.5, 0.008)] {
            Draw.dot(&c, at: f.p(x, y), radius: f.u * r, color: .white.opacity(0.85))
        }
        Draw.moon(&c, at: f.p(0.6, 0.38), radius: f.u * 0.27)
        // Silver grass from the lower left.
        for index in 0..<5 {
            let i = CGFloat(index)
            let base = f.p(0.04 + i * 0.07, 1.04)
            let tip = f.p(0.12 + i * 0.075, 0.6 - i * 0.025)
            var blade = Path()
            blade.move(to: base)
            blade.addQuadCurve(to: tip, control: CGPoint(x: base.x - f.u * 0.02, y: (base.y + tip.y) / 2))
            c.stroke(blade, with: .color(.hex(0xD9D2F2, 0.7)), style: StrokeStyle(lineWidth: f.u * 0.012, lineCap: .round))
            Draw.leaf(&c, at: tip, length: f.u * 0.11, angle: 0.5 + Double(i) * 0.08, color: .hex(0xF4EEDC, 0.75))
        }
        // A persimmon branch from the right.
        var branch = Path()
        branch.move(to: f.p(1.06, 0.7))
        branch.addQuadCurve(to: f.p(0.52, 0.84), control: f.p(0.78, 0.7))
        c.stroke(branch, with: .color(.hex(0x3E2723)), style: StrokeStyle(lineWidth: f.u * 0.026, lineCap: .round))
        for (x, y, angle) in [(0.6, 0.78, -0.9), (0.76, 0.72, 0.6), (0.94, 0.68, -0.4)] {
            Draw.leaf(&c, at: f.p(x, y), length: f.u * 0.12, angle: angle, color: .hex(0x558B2F))
        }
        for (x, y, r) in [(0.64, 0.9, 0.075), (0.82, 0.86, 0.065), (0.97, 0.82, 0.06)] {
            Draw.persimmon(&c, at: f.p(x, y), radius: f.u * r)
        }
    }

    static func hanami(_ c: inout GraphicsContext, _ f: ArtFrame) {
        let bark = Color.hex(0x6D4C41)
        var branch = Path()
        branch.move(to: f.p(1.06, 0.06))
        branch.addQuadCurve(to: f.p(0.24, 0.32), control: f.p(0.6, 0.02))
        c.stroke(branch, with: .color(bark), style: StrokeStyle(lineWidth: f.u * 0.036, lineCap: .round))
        for (from, to, control) in [((0.6, 0.12), (0.5, 0.48), (0.6, 0.3)), ((0.84, 0.08), (0.92, 0.4), (0.92, 0.2))] {
            var twig = Path()
            twig.move(to: f.p(from.0, from.1))
            twig.addQuadCurve(to: f.p(to.0, to.1), control: f.p(control.0, control.1))
            c.stroke(twig, with: .color(bark), style: StrokeStyle(lineWidth: f.u * 0.02, lineCap: .round))
        }
        let clusters: [(CGFloat, CGFloat, CGFloat, Double)] = [
            (0.25, 0.32, 0.1, 0.2), (0.36, 0.2, 0.085, 0.6), (0.5, 0.48, 0.11, 0.1), (0.57, 0.3, 0.08, 0.9), (0.7, 0.1, 0.09, 0.4),
            (0.92, 0.42, 0.1, 0.7), (0.8, 0.24, 0.075, 0.3), (0.43, 0.36, 0.07, 0.5), (0.62, 0.16, 0.065, 1.1), (0.88, 0.1, 0.07, 0.2),
        ]
        for (x, y, r, turn) in clusters {
            Draw.blossom(&c, at: f.p(x, y), radius: f.u * r, petal: .hex(0xFFF3F7), edge: .hex(0xF6A5C4),
                         heart: .hex(0xF06292), notched: true, turn: turn)
        }
        for (x, y, angle) in [(0.14, 0.62, 0.4), (0.3, 0.8, -0.6), (0.56, 0.7, 1.1), (0.72, 0.88, -0.2), (0.86, 0.64, 0.8),
                              (0.44, 0.94, 0.3), (0.2, 0.95, 1.4), (0.66, 0.6, -0.9), (0.95, 0.85, 0.5)] {
            Draw.petal(&c, at: f.p(x, y), size: f.u * 0.06, angle: angle, color: .hex(0xF8A5C2))
        }
    }

    static func tanabata(_ c: inout GraphicsContext, _ f: ArtFrame) {
        // The Milky Way, a soft band across the sky.
        c.drawLayer { layer in
            layer.addFilter(.blur(radius: f.u * 0.07))
            var band = Path()
            band.move(to: f.p(-0.1, 0.92))
            band.addLine(to: f.p(1.1, 0.04))
            layer.stroke(band, with: .color(.hex(0xC9B8FF, 0.42)), lineWidth: f.u * 0.3)
        }
        var stars = SplitMix64(seed: 7)
        for _ in 0..<26 {
            let t = CGFloat(stars.next() % 1000) / 1000
            let spread = (CGFloat(stars.next() % 1000) / 1000 - 0.5) * 0.36
            let point = f.p(t + spread * 0.5, 0.92 - t * 0.88 + spread * 0.5)
            Draw.dot(&c, at: point, radius: f.u * (0.004 + CGFloat(stars.next() % 6) / 1000), color: .white.opacity(0.9))
        }
        for (x, y, s) in [(0.14, 0.16, 0.08), (0.4, 0.36, 0.05), (0.9, 0.2, 0.065), (0.22, 0.6, 0.045)] {
            Draw.sparkle(&c, at: f.p(x, y), size: f.u * s, color: .hex(0xFFF59D))
        }
        // Bamboo with paper wishes (no writing on them).
        let bottom = f.p(0.8, 1.05), top = f.p(0.62, 0.1), bend = f.p(0.8, 0.5)
        var stalk = Path()
        stalk.move(to: bottom)
        stalk.addQuadCurve(to: top, control: bend)
        c.stroke(stalk, with: .color(.hex(0x2E7D32)), style: StrokeStyle(lineWidth: f.u * 0.045, lineCap: .round))
        c.stroke(stalk, with: .color(.hex(0x81C784, 0.7)), style: StrokeStyle(lineWidth: f.u * 0.014, lineCap: .round))
        for (dx, dy, angle) in [(0.0, 0.0, -0.9), (0.05, 0.05, -0.3), (-0.05, 0.08, -1.6), (0.04, 0.15, 0.2)] {
            Draw.leaf(&c, at: f.p(0.62 + dx, 0.12 + dy), length: f.u * 0.16, angle: angle, color: .hex(0x43A047))
        }
        let strips: [(CGFloat, UInt32, Double)] = [(0.3, 0xFF8FB8, -0.1), (0.48, 0xFFE066, 0.08), (0.64, 0x7FE0C1, -0.06), (0.8, 0x9FB8FF, 0.1)]
        for (t, color, tilt) in strips {
            let point = Draw.quadPoint(t, from: bottom, control: bend, to: top)
            let left = t > 0.5
            let hook = CGPoint(x: point.x + (left ? -1 : 1) * f.u * 0.03, y: point.y)
            var string = Path()
            string.move(to: point)
            string.addLine(to: CGPoint(x: hook.x, y: hook.y + f.u * 0.04))
            c.stroke(string, with: .color(.white.opacity(0.7)), lineWidth: max(0.6, f.u * 0.006))
            let strip = CGRect(x: -f.u * 0.04, y: 0, width: f.u * 0.08, height: f.u * 0.2)
            let placed = Path(roundedRect: strip, cornerRadius: f.u * 0.008)
                .applying(CGAffineTransform(rotationAngle: tilt))
                .applying(CGAffineTransform(translationX: hook.x, y: hook.y + f.u * 0.04))
            c.fill(placed, with: .color(.hex(color)))
        }
    }

    static func carnaval(_ c: inout GraphicsContext, _ f: ArtFrame) {
        Draw.streamer(&c, from: f.p(-0.05, 0.16), to: f.p(1.05, 0.26), amplitude: f.u * 0.05, waves: 3, color: .hex(0xFFEB3B), width: f.u * 0.022)
        Draw.streamer(&c, from: f.p(-0.05, 0.9), to: f.p(1.05, 0.8), amplitude: f.u * 0.045, waves: 2.5, color: .hex(0x18FFFF), width: f.u * 0.022)
        Draw.confetti(&c, f, count: 34, colors: [.hex(0xFFEB3B), .hex(0x18FFFF), .hex(0x76FF03), .hex(0xFF80AB), .white, .hex(0xFFAB40)], seed: 11)
        Draw.carnivalMask(&c, at: f.p(0.5, 0.56), width: f.u * 0.72)
        for (x, y, s) in [(0.16, 0.42, 0.07), (0.86, 0.5, 0.06), (0.36, 0.86, 0.05)] {
            Draw.sparkle(&c, at: f.p(x, y), size: f.u * s, color: .white)
        }
    }

    static func festaJunina(_ c: inout GraphicsContext, _ f: ArtFrame) {
        // String lights, two rows of paper flags and a bonfire.
        let lights = Draw.curve(from: f.p(-0.05, 0.04), to: f.p(1.05, 0.04), sag: f.u * 0.08)
        c.stroke(lights.path, with: .color(.hex(0x2B2B2B, 0.6)), lineWidth: max(0.8, f.u * 0.008))
        for index in 0..<8 {
            let point = lights.point((CGFloat(index) + 0.5) / 8)
            Draw.glow(&c, at: point, radius: f.u * 0.05, color: .hex(0xFFE082), opacity: 0.8)
            Draw.dot(&c, at: point, radius: f.u * 0.016, color: .hex(0xFFF3C4))
        }
        let flags: [Color] = [.hex(0xE53935), .hex(0xFDD835), .hex(0x43A047), .hex(0x1E88E5), .hex(0xFB8C00), .hex(0xEC407A)]
        Draw.bunting(&c, Draw.curve(from: f.p(-0.05, 0.14), to: f.p(1.05, 0.14), sag: f.u * 0.1), count: 7, colors: flags,
                     flag: CGSize(width: f.u * 0.12, height: f.u * 0.14), line: .white.opacity(0.75), cutPaper: false)
        Draw.bunting(&c, Draw.curve(from: f.p(-0.05, 0.38), to: f.p(1.05, 0.34), sag: f.u * 0.08), count: 6,
                     colors: Array(flags.dropFirst(3) + flags.prefix(3)),
                     flag: CGSize(width: f.u * 0.11, height: f.u * 0.13), line: .white.opacity(0.75), cutPaper: false)
        Draw.bonfire(&c, at: f.p(0.52, 0.98), size: f.u * 0.38)
    }

    static func diaDeMuertos(_ c: inout GraphicsContext, _ f: ArtFrame) {
        let paper: [Color] = [.hex(0xFF4081), .hex(0xFF9800), .hex(0x26C6DA), .hex(0xFFEB3B), .hex(0xAB47BC)]
        Draw.bunting(&c, Draw.curve(from: f.p(-0.04, 0.05), to: f.p(1.04, 0.05), sag: f.u * 0.05), count: 5, colors: paper,
                     flag: CGSize(width: f.u * 0.18, height: f.u * 0.25), line: .white.opacity(0.8), cutPaper: true)
        Draw.candle(&c, base: f.p(0.37, 0.97), width: f.u * 0.07, height: f.u * 0.2)
        Draw.candle(&c, base: f.p(0.66, 0.99), width: f.u * 0.06, height: f.u * 0.15)
        for (x, y, r) in [(0.13, 0.88, 0.12), (0.52, 0.96, 0.1), (0.87, 0.86, 0.13), (0.27, 1.0, 0.08), (0.76, 1.0, 0.08)] {
            Draw.marigold(&c, at: f.p(x, y), radius: f.u * r)
        }
        for (x, y, angle) in [(0.22, 0.62, 0.5), (0.5, 0.7, -0.4), (0.8, 0.6, 1.0), (0.62, 0.52, 0.2)] {
            Draw.petal(&c, at: f.p(x, y), size: f.u * 0.04, angle: angle, color: .hex(0xFFA726))
        }
    }
}

/// The shapes the scenes are made of.
private enum Draw {
    static func circle(_ center: CGPoint, _ radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

    static func glow(_ c: inout GraphicsContext, at center: CGPoint, radius: CGFloat, color: Color, opacity: Double) {
        c.fill(Path(ellipseIn: circle(center, radius)),
               with: .radialGradient(Gradient(colors: [color.opacity(opacity), color.opacity(0)]), center: center, startRadius: 0, endRadius: radius))
    }

    static func dot(_ c: inout GraphicsContext, at center: CGPoint, radius: CGFloat, color: Color) {
        c.fill(Path(ellipseIn: circle(center, radius)), with: .color(color))
    }

    /// A four-pointed sparkle.
    static func sparkle(_ c: inout GraphicsContext, at center: CGPoint, size: CGFloat, color: Color) {
        let s = size / 2, k = size * 0.1
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y - s))
        path.addQuadCurve(to: CGPoint(x: center.x + s, y: center.y), control: CGPoint(x: center.x + k, y: center.y - k))
        path.addQuadCurve(to: CGPoint(x: center.x, y: center.y + s), control: CGPoint(x: center.x + k, y: center.y + k))
        path.addQuadCurve(to: CGPoint(x: center.x - s, y: center.y), control: CGPoint(x: center.x - k, y: center.y + k))
        path.addQuadCurve(to: CGPoint(x: center.x, y: center.y - s), control: CGPoint(x: center.x - k, y: center.y - k))
        c.fill(path, with: .color(color))
    }

    static func leaf(_ c: inout GraphicsContext, at base: CGPoint, length: CGFloat, angle: Double, color: Color) {
        var leaf = Path()
        leaf.move(to: .zero)
        leaf.addQuadCurve(to: CGPoint(x: 0, y: -length), control: CGPoint(x: length * 0.36, y: -length * 0.5))
        leaf.addQuadCurve(to: .zero, control: CGPoint(x: -length * 0.36, y: -length * 0.5))
        let placed = leaf.applying(CGAffineTransform(rotationAngle: angle)).applying(CGAffineTransform(translationX: base.x, y: base.y))
        c.fill(placed, with: .color(color))
    }

    static func petal(_ c: inout GraphicsContext, at center: CGPoint, size: CGFloat, angle: Double, color: Color) {
        let shape = Path(ellipseIn: CGRect(x: -size / 2, y: -size * 0.3, width: size, height: size * 0.6))
            .applying(CGAffineTransform(rotationAngle: angle))
            .applying(CGAffineTransform(translationX: center.x, y: center.y))
        c.fill(shape, with: .color(color))
    }

    /// Five petals; notched ones make it a cherry blossom, round ones plum or rose.
    static func blossom(
        _ c: inout GraphicsContext, at center: CGPoint, radius: CGFloat, petal: Color, edge: Color, heart: Color,
        notched: Bool = false, turn: Double = 0
    ) {
        let length = radius
        var shape = Path()
        shape.move(to: .zero)
        shape.addCurve(to: CGPoint(x: -length * 0.2, y: -length), control1: CGPoint(x: -length * 0.6, y: -length * 0.25),
                       control2: CGPoint(x: -length * 0.5, y: -length * 0.9))
        if notched {
            shape.addLine(to: CGPoint(x: 0, y: -length * 0.82))
            shape.addLine(to: CGPoint(x: length * 0.2, y: -length))
        } else {
            shape.addQuadCurve(to: CGPoint(x: length * 0.2, y: -length), control: CGPoint(x: 0, y: -length * 1.14))
        }
        shape.addCurve(to: .zero, control1: CGPoint(x: length * 0.5, y: -length * 0.9), control2: CGPoint(x: length * 0.6, y: -length * 0.25))
        for index in 0..<5 {
            let angle = Double(index) / 5 * 2 * .pi + turn
            let placed = shape.applying(CGAffineTransform(rotationAngle: angle)).applying(CGAffineTransform(translationX: center.x, y: center.y))
            let tip = CGPoint(x: center.x + CGFloat(sin(angle)) * length, y: center.y - CGFloat(cos(angle)) * length)
            c.fill(placed, with: .linearGradient(Gradient(colors: [edge, petal]), startPoint: center, endPoint: tip))
        }
        dot(&c, at: center, radius: radius * 0.14, color: heart)
        for index in 0..<6 {
            let angle = Double(index) / 6 * 2 * .pi
            let point = CGPoint(x: center.x + CGFloat(cos(angle)) * radius * 0.3, y: center.y + CGFloat(sin(angle)) * radius * 0.3)
            dot(&c, at: point, radius: max(0.5, radius * 0.04), color: heart.opacity(0.8))
        }
    }

    /// A pom-pom of ruffled petals, as cempasúchil is.
    static func marigold(_ c: inout GraphicsContext, at center: CGPoint, radius: CGFloat) {
        let rings: [(count: Int, distance: CGFloat, size: CGFloat, color: UInt32)] = [
            (15, 0.74, 0.3, 0xE65100), (12, 0.52, 0.3, 0xF57C00), (9, 0.3, 0.28, 0xFFA000), (5, 0.12, 0.24, 0xFFCA28),
        ]
        for (ring, spec) in rings.enumerated() {
            for index in 0..<spec.count {
                let angle = Double(index) / Double(spec.count) * 2 * .pi + Double(ring) * 0.35
                let point = CGPoint(x: center.x + CGFloat(cos(angle)) * radius * spec.distance,
                                    y: center.y + CGFloat(sin(angle)) * radius * spec.distance)
                dot(&c, at: point, radius: radius * spec.size, color: Color(hex: spec.color))
            }
        }
        dot(&c, at: center, radius: radius * 0.12, color: Color(hex: 0xBF360C))
    }

    /// A brass lantern with arched windows, hanging on a chain.
    static func brassLantern(
        _ c: inout GraphicsContext, x: CGFloat, top: CGFloat = 0, hang: CGFloat, height h: CGFloat,
        metal: Color, shade: Color, light: Color
    ) {
        let w = h * 0.46
        let y0 = top + hang
        var chain = Path()
        chain.move(to: CGPoint(x: x, y: top))
        chain.addLine(to: CGPoint(x: x, y: y0))
        c.stroke(chain, with: .color(metal), lineWidth: max(0.8, h * 0.012))
        c.stroke(Path(ellipseIn: CGRect(x: x - h * 0.03, y: y0, width: h * 0.06, height: h * 0.06)), with: .color(metal), lineWidth: max(0.8, h * 0.014))
        glow(&c, at: CGPoint(x: x, y: y0 + h * 0.56), radius: w * 1.3, color: light, opacity: 0.55)

        var dome = Path()
        dome.move(to: CGPoint(x: x - w * 0.42, y: y0 + h * 0.3))
        dome.addCurve(to: CGPoint(x: x, y: y0 + h * 0.06), control1: CGPoint(x: x - w * 0.52, y: y0 + h * 0.15),
                      control2: CGPoint(x: x - w * 0.06, y: y0 + h * 0.17))
        dome.addCurve(to: CGPoint(x: x + w * 0.42, y: y0 + h * 0.3), control1: CGPoint(x: x + w * 0.06, y: y0 + h * 0.17),
                      control2: CGPoint(x: x + w * 0.52, y: y0 + h * 0.15))
        dome.closeSubpath()
        c.fill(dome, with: .linearGradient(Gradient(colors: [metal, shade]), startPoint: CGPoint(x: x - w / 2, y: y0),
                                           endPoint: CGPoint(x: x + w / 2, y: y0 + h * 0.3)))
        c.fill(Path(roundedRect: CGRect(x: x - w * 0.5, y: y0 + h * 0.29, width: w, height: h * 0.05), cornerRadius: h * 0.01), with: .color(metal))

        var body = Path()
        body.move(to: CGPoint(x: x - w * 0.46, y: y0 + h * 0.34))
        body.addLine(to: CGPoint(x: x + w * 0.46, y: y0 + h * 0.34))
        body.addLine(to: CGPoint(x: x + w * 0.36, y: y0 + h * 0.8))
        body.addLine(to: CGPoint(x: x - w * 0.36, y: y0 + h * 0.8))
        body.closeSubpath()
        c.fill(body, with: .color(shade))
        for side in [-1.0, 1.0] {
            let cx = x + CGFloat(side) * w * 0.19, width = w * 0.27
            let windowTop = y0 + h * 0.39, windowBottom = y0 + h * 0.75
            var window = Path()
            window.move(to: CGPoint(x: cx - width / 2, y: windowBottom))
            window.addLine(to: CGPoint(x: cx - width / 2, y: windowTop + width * 0.5))
            window.addQuadCurve(to: CGPoint(x: cx, y: windowTop), control: CGPoint(x: cx - width / 2, y: windowTop))
            window.addQuadCurve(to: CGPoint(x: cx + width / 2, y: windowTop + width * 0.5), control: CGPoint(x: cx + width / 2, y: windowTop))
            window.addLine(to: CGPoint(x: cx + width / 2, y: windowBottom))
            window.closeSubpath()
            c.fill(window, with: .linearGradient(Gradient(colors: [Color(hex: 0xFFF6D5), light]),
                                                 startPoint: CGPoint(x: cx, y: windowTop), endPoint: CGPoint(x: cx, y: windowBottom)))
        }
        c.fill(Path(roundedRect: CGRect(x: x - w * 0.4, y: y0 + h * 0.79, width: w * 0.8, height: h * 0.05), cornerRadius: h * 0.01), with: .color(metal))
        var tip = Path()
        tip.move(to: CGPoint(x: x - w * 0.22, y: y0 + h * 0.84))
        tip.addLine(to: CGPoint(x: x + w * 0.22, y: y0 + h * 0.84))
        tip.addLine(to: CGPoint(x: x, y: y0 + h * 0.98))
        tip.closeSubpath()
        c.fill(tip, with: .color(metal))
    }

    /// A round red paper lantern with gold caps and a tassel.
    static func roundLantern(_ c: inout GraphicsContext, center: CGPoint, width: CGFloat, height: CGFloat, red: Color, deep: Color, gold: Color) {
        let capWidth = width * 0.42, capHeight = height * 0.1
        var string = Path()
        string.move(to: CGPoint(x: center.x, y: 0))
        string.addLine(to: CGPoint(x: center.x, y: center.y - height / 2))
        c.stroke(string, with: .color(gold), lineWidth: max(0.8, width * 0.025))
        glow(&c, at: center, radius: width * 0.95, color: Color(hex: 0xFFB74D), opacity: 0.45)
        let body = Path(ellipseIn: CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height))
        c.fill(body, with: .radialGradient(Gradient(colors: [Color(hex: 0xFF7A59), red, deep]),
                                           center: CGPoint(x: center.x - width * 0.12, y: center.y - height * 0.14),
                                           startRadius: 0, endRadius: width * 0.66))
        for share in [0.32, 0.66] {
            let rib = Path(ellipseIn: CGRect(x: center.x - width * share / 2, y: center.y - height / 2, width: width * share, height: height))
            c.stroke(rib, with: .color(deep.opacity(0.55)), lineWidth: max(0.6, width * 0.02))
        }
        let capTop = CGRect(x: center.x - capWidth / 2, y: center.y - height / 2 - capHeight * 0.7, width: capWidth, height: capHeight)
        let capBottom = CGRect(x: center.x - capWidth / 2, y: center.y + height / 2 - capHeight * 0.3, width: capWidth, height: capHeight)
        c.fill(Path(roundedRect: capTop, cornerRadius: capHeight * 0.3), with: .color(gold))
        c.fill(Path(roundedRect: capBottom, cornerRadius: capHeight * 0.3), with: .color(gold))
        for offset in [-0.06, 0.0, 0.06] {
            var thread = Path()
            thread.move(to: CGPoint(x: center.x + width * offset, y: capBottom.maxY))
            thread.addLine(to: CGPoint(x: center.x + width * offset * 1.5, y: capBottom.maxY + height * 0.42))
            c.stroke(thread, with: .color(gold), style: StrokeStyle(lineWidth: max(0.6, width * 0.022), lineCap: .round))
        }
    }

    static func firework(_ c: inout GraphicsContext, at center: CGPoint, radius: CGFloat, color: Color, rays: Int = 12) {
        for index in 0..<rays {
            let angle = Double(index) / Double(rays) * 2 * .pi
            let (dx, dy) = (CGFloat(cos(angle)), CGFloat(sin(angle)))
            var ray = Path()
            ray.move(to: CGPoint(x: center.x + dx * radius * 0.34, y: center.y + dy * radius * 0.34))
            ray.addLine(to: CGPoint(x: center.x + dx * radius, y: center.y + dy * radius))
            c.stroke(ray, with: .color(color.opacity(0.9)), style: StrokeStyle(lineWidth: max(0.8, radius * 0.05), lineCap: .round))
            dot(&c, at: CGPoint(x: center.x + dx * radius * 1.14, y: center.y + dy * radius * 1.14), radius: max(0.6, radius * 0.04), color: color)
        }
    }

    static func moon(_ c: inout GraphicsContext, at center: CGPoint, radius: CGFloat) {
        glow(&c, at: center, radius: radius * 1.9, color: Color(hex: 0xFFE8A3), opacity: 0.45)
        c.fill(Path(ellipseIn: circle(center, radius)),
               with: .radialGradient(Gradient(colors: [Color(hex: 0xFFFBEA), Color(hex: 0xFCE3A0), Color(hex: 0xF4C66B)]),
                                     center: CGPoint(x: center.x - radius * 0.25, y: center.y - radius * 0.25),
                                     startRadius: 0, endRadius: radius * 1.3))
        for (dx, dy, r) in [(-0.3, 0.1, 0.16), (0.25, -0.28, 0.1), (0.2, 0.32, 0.12), (-0.05, -0.12, 0.07)] {
            dot(&c, at: CGPoint(x: center.x + radius * dx, y: center.y + radius * dy), radius: radius * r, color: Color(hex: 0xE2B35A, opacity: 0.22))
        }
    }

    static func persimmon(_ c: inout GraphicsContext, at center: CGPoint, radius: CGFloat) {
        let fruit = CGRect(x: center.x - radius, y: center.y - radius * 0.88, width: radius * 2, height: radius * 1.76)
        c.fill(Path(ellipseIn: fruit),
               with: .radialGradient(Gradient(colors: [Color(hex: 0xFFC069), Color(hex: 0xF57C00), Color(hex: 0xC43E12)]),
                                     center: CGPoint(x: center.x - radius * 0.35, y: center.y - radius * 0.35),
                                     startRadius: 0, endRadius: radius * 1.4))
        for index in 0..<4 {
            leaf(&c, at: CGPoint(x: center.x, y: center.y - radius * 0.78), length: radius * 0.55,
                 angle: Double(index) * .pi / 2 + .pi / 4, color: Color(hex: 0x33691E))
        }
    }

    static func candle(_ c: inout GraphicsContext, base: CGPoint, width: CGFloat, height: CGFloat) {
        glow(&c, at: CGPoint(x: base.x, y: base.y - height - width * 0.6), radius: width * 2.4, color: Color(hex: 0xFFB300), opacity: 0.55)
        c.fill(Path(roundedRect: CGRect(x: base.x - width / 2, y: base.y - height, width: width, height: height), cornerRadius: width * 0.18),
               with: .linearGradient(Gradient(colors: [Color(hex: 0xFFF8E1), Color(hex: 0xEED29A)]),
                                     startPoint: CGPoint(x: base.x - width / 2, y: base.y), endPoint: CGPoint(x: base.x + width / 2, y: base.y)))
        flame(&c, base: CGPoint(x: base.x, y: base.y - height - width * 0.05), width: width * 0.6, height: width * 1.2,
              colors: [Color(hex: 0xFF9800), Color(hex: 0xFFEB3B)])
    }

    static func flame(_ c: inout GraphicsContext, base: CGPoint, width: CGFloat, height: CGFloat, colors: [Color]) {
        var path = Path()
        path.move(to: CGPoint(x: base.x, y: base.y - height))
        path.addCurve(to: CGPoint(x: base.x + width / 2, y: base.y - height * 0.3),
                      control1: CGPoint(x: base.x + width * 0.1, y: base.y - height * 0.75),
                      control2: CGPoint(x: base.x + width * 0.55, y: base.y - height * 0.6))
        path.addQuadCurve(to: CGPoint(x: base.x - width / 2, y: base.y - height * 0.3), control: CGPoint(x: base.x, y: base.y + height * 0.12))
        path.addCurve(to: CGPoint(x: base.x, y: base.y - height),
                      control1: CGPoint(x: base.x - width * 0.55, y: base.y - height * 0.6),
                      control2: CGPoint(x: base.x - width * 0.1, y: base.y - height * 0.75))
        path.closeSubpath()
        c.fill(path, with: .linearGradient(Gradient(colors: colors), startPoint: base, endPoint: CGPoint(x: base.x, y: base.y - height)))
    }

    static func bonfire(_ c: inout GraphicsContext, at base: CGPoint, size: CGFloat) {
        glow(&c, at: CGPoint(x: base.x, y: base.y - size * 0.4), radius: size * 1.3, color: Color(hex: 0xFF8A00), opacity: 0.55)
        for angle in [-0.32, 0.32] {
            let log = Path(roundedRect: CGRect(x: -size * 0.5, y: -size * 0.07, width: size, height: size * 0.14), cornerRadius: size * 0.07)
                .applying(CGAffineTransform(rotationAngle: angle))
                .applying(CGAffineTransform(translationX: base.x, y: base.y - size * 0.06))
            c.fill(log, with: .color(Color(hex: 0x6D3B1F)))
        }
        flame(&c, base: CGPoint(x: base.x, y: base.y - size * 0.1), width: size * 0.62, height: size * 0.95,
              colors: [Color(hex: 0xFF5722), Color(hex: 0xFF9800)])
        flame(&c, base: CGPoint(x: base.x, y: base.y - size * 0.1), width: size * 0.36, height: size * 0.6,
              colors: [Color(hex: 0xFFC107), Color(hex: 0xFFF59D)])
        for (dx, dy, r) in [(-0.3, -1.05, 0.025), (0.22, -1.2, 0.02), (0.05, -1.4, 0.016), (-0.12, -1.28, 0.014)] {
            dot(&c, at: CGPoint(x: base.x + size * dx, y: base.y + size * dy), radius: size * r, color: Color(hex: 0xFFD54F))
        }
    }

    static func carnivalMask(_ c: inout GraphicsContext, at center: CGPoint, width w: CGFloat) {
        let h = w * 0.42
        // Feathers behind the mask's right side.
        let feathers: [(CGFloat, CGFloat, Double, UInt32)] = [(0.2, -0.95, 0.35, 0x1DE9B6), (0.34, -0.85, 0.75, 0xFF80AB), (0.08, -1.0, 0.05, 0xFFD740)]
        for (dx, dy, angle, color) in feathers {
            let feather = Path(ellipseIn: CGRect(x: -w * 0.07, y: -h * 0.62, width: w * 0.14, height: h * 1.24))
                .applying(CGAffineTransform(rotationAngle: angle))
                .applying(CGAffineTransform(translationX: center.x + w * dx, y: center.y + h * dy))
            c.fill(feather, with: .color(Color(hex: color)))
            var quill = Path()
            quill.move(to: CGPoint(x: center.x + w * dx, y: center.y + h * dy))
            quill.addLine(to: CGPoint(x: center.x + w * (dx - CGFloat(sin(angle)) * 0.12), y: center.y + h * (dy + CGFloat(cos(angle)) * 0.6)))
            c.stroke(quill, with: .color(.white.opacity(0.8)), lineWidth: max(0.6, w * 0.008))
        }
        var mask = Path()
        mask.move(to: CGPoint(x: center.x, y: center.y - h * 0.22))
        mask.addCurve(to: CGPoint(x: center.x + w / 2, y: center.y - h * 0.3),
                      control1: CGPoint(x: center.x + w * 0.15, y: center.y - h * 0.62), control2: CGPoint(x: center.x + w * 0.42, y: center.y - h * 0.62))
        mask.addCurve(to: CGPoint(x: center.x, y: center.y + h * 0.4),
                      control1: CGPoint(x: center.x + w * 0.58, y: center.y + h * 0.22), control2: CGPoint(x: center.x + w * 0.2, y: center.y + h * 0.6))
        mask.addCurve(to: CGPoint(x: center.x - w / 2, y: center.y - h * 0.3),
                      control1: CGPoint(x: center.x - w * 0.2, y: center.y + h * 0.6), control2: CGPoint(x: center.x - w * 0.58, y: center.y + h * 0.22))
        mask.addCurve(to: CGPoint(x: center.x, y: center.y - h * 0.22),
                      control1: CGPoint(x: center.x - w * 0.42, y: center.y - h * 0.62), control2: CGPoint(x: center.x - w * 0.15, y: center.y - h * 0.62))
        mask.closeSubpath()
        for side in [-1.0, 1.0] {
            let eye = CGRect(x: center.x + CGFloat(side) * w * 0.21 - w * 0.11, y: center.y - h * 0.2, width: w * 0.22, height: h * 0.34)
            mask.addEllipse(in: eye)
        }
        c.fill(mask, with: .linearGradient(Gradient(colors: [Color(hex: 0xFFE57F), Color(hex: 0xFF4081)]),
                                           startPoint: CGPoint(x: center.x - w / 2, y: center.y - h / 2),
                                           endPoint: CGPoint(x: center.x + w / 2, y: center.y + h / 2)),
               style: FillStyle(eoFill: true))
        c.stroke(mask, with: .color(.white.opacity(0.9)), lineWidth: max(0.8, w * 0.018))
    }

    static func confetti(_ c: inout GraphicsContext, _ f: ArtFrame, count: Int, colors: [Color], seed: UInt64) {
        var random = SplitMix64(seed: seed)
        for index in 0..<count {
            let point = f.p(CGFloat(random.next() % 1000) / 1000, CGFloat(random.next() % 1000) / 1000)
            let color = colors[Int(random.next() % UInt64(colors.count))]
            let side = f.u * (0.018 + CGFloat(random.next() % 100) / 100 * 0.022)
            if index % 3 == 0 {
                dot(&c, at: point, radius: side * 0.45, color: color)
            } else {
                let piece = Path(CGRect(x: -side / 2, y: -side / 4, width: side, height: side / 2))
                    .applying(CGAffineTransform(rotationAngle: Double(random.next() % 314) / 100))
                    .applying(CGAffineTransform(translationX: point.x, y: point.y))
                c.fill(piece, with: .color(color))
            }
        }
    }

    static func streamer(_ c: inout GraphicsContext, from start: CGPoint, to end: CGPoint, amplitude: CGFloat, waves: CGFloat, color: Color, width: CGFloat) {
        var path = Path()
        let steps = 48
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let point = CGPoint(x: start.x + (end.x - start.x) * t,
                                y: start.y + (end.y - start.y) * t + sin(t * waves * 2 * .pi) * amplitude)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        c.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    /// A string between two points that sags in the middle.
    struct Curve {
        let start: CGPoint
        let control: CGPoint
        let end: CGPoint

        var path: Path {
            var path = Path()
            path.move(to: start)
            path.addQuadCurve(to: end, control: control)
            return path
        }

        func point(_ t: CGFloat) -> CGPoint { Draw.quadPoint(t, from: start, control: control, to: end) }

        func angle(_ t: CGFloat) -> Double {
            let dx = 2 * (1 - t) * (control.x - start.x) + 2 * t * (end.x - control.x)
            let dy = 2 * (1 - t) * (control.y - start.y) + 2 * t * (end.y - control.y)
            return atan2(Double(dy), Double(dx))
        }
    }

    static func curve(from start: CGPoint, to end: CGPoint, sag: CGFloat) -> Curve {
        Curve(start: start, control: CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 + sag * 2), end: end)
    }

    static func quadPoint(_ t: CGFloat, from start: CGPoint, control: CGPoint, to end: CGPoint) -> CGPoint {
        let a = (1 - t) * (1 - t), b = 2 * (1 - t) * t, d = t * t
        return CGPoint(x: a * start.x + b * control.x + d * end.x, y: a * start.y + b * control.y + d * end.y)
    }

    /// Flags on a string: triangles (bandeirinhas), or cut-paper banners
    /// with a scalloped edge and little cut-outs (papel picado).
    static func bunting(
        _ c: inout GraphicsContext, _ curve: Curve, count: Int, colors: [Color], flag: CGSize, line: Color, cutPaper: Bool
    ) {
        c.stroke(curve.path, with: .color(line), lineWidth: max(0.8, flag.width * 0.04))
        let (w, h) = (flag.width, flag.height)
        var shape = Path()
        if cutPaper {
            shape.move(to: CGPoint(x: -w / 2, y: 0))
            shape.addLine(to: CGPoint(x: w / 2, y: 0))
            shape.addLine(to: CGPoint(x: w / 2, y: h * 0.86))
            let teeth = 5
            for tooth in 0..<teeth {
                let right = w / 2 - CGFloat(tooth) * w / CGFloat(teeth)
                shape.addLine(to: CGPoint(x: right - w / CGFloat(teeth) / 2, y: h))
                shape.addLine(to: CGPoint(x: right - w / CGFloat(teeth), y: h * 0.86))
            }
            shape.closeSubpath()
            // Cut-outs: a little flower in the middle, diamonds above and below.
            let middle = CGPoint(x: 0, y: h * 0.45)
            shape.addEllipse(in: circle(middle, w * 0.08))
            for index in 0..<4 {
                let angle = Double(index) * .pi / 2 + .pi / 4
                shape.addEllipse(in: circle(CGPoint(x: middle.x + CGFloat(cos(angle)) * w * 0.17, y: middle.y + CGFloat(sin(angle)) * w * 0.17), w * 0.05))
            }
            for (x, y) in [(-0.28, 0.14), (0.28, 0.14), (-0.28, 0.72), (0.28, 0.72), (0, 0.12), (0, 0.76)] {
                let center = CGPoint(x: w * x, y: h * y), r = w * 0.055
                var diamond = Path()
                diamond.move(to: CGPoint(x: center.x, y: center.y - r))
                diamond.addLine(to: CGPoint(x: center.x + r, y: center.y))
                diamond.addLine(to: CGPoint(x: center.x, y: center.y + r))
                diamond.addLine(to: CGPoint(x: center.x - r, y: center.y))
                diamond.closeSubpath()
                shape.addPath(diamond)
            }
        } else {
            shape.move(to: CGPoint(x: -w / 2, y: 0))
            shape.addLine(to: CGPoint(x: w / 2, y: 0))
            shape.addLine(to: CGPoint(x: 0, y: h))
            shape.closeSubpath()
        }
        for index in 0..<count {
            let t = (CGFloat(index) + 0.5) / CGFloat(count)
            let point = curve.point(t)
            let placed = shape.applying(CGAffineTransform(rotationAngle: curve.angle(t)))
                .applying(CGAffineTransform(translationX: point.x, y: point.y))
            c.fill(placed, with: .color(colors[index % colors.count]), style: FillStyle(eoFill: true))
        }
    }
}
