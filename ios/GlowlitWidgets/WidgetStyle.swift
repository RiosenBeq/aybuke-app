import SwiftUI

/// The app's "Blush" swatches for the widget extension (ios/App/DesignSystem/Palette.swift).
enum WidgetPalette {
    static let blush = Color(red: 247 / 255, green: 193 / 255, blue: 217 / 255)
    static let petal = Color(red: 248 / 255, green: 224 / 255, blue: 234 / 255)
    static let ink = Color(red: 18 / 255, green: 18 / 255, blue: 18 / 255)
    static let charcoal = Color(red: 36 / 255, green: 39 / 255, blue: 42 / 255)
    static let paper = Color(red: 248 / 255, green: 248 / 255, blue: 246 / 255)
    static let inkSoft = Color(red: 92 / 255, green: 84 / 255, blue: 87 / 255)
}

extension Font {
    /// Headline face for widgets (system rounded; the app's display font isn't bundled here).
    static func widgetTitle(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    /// The editorial italic accent ("glow").
    static func widgetAccent(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .serif).italic() }
}

/// Petal-to-blush wash with a soft white glow — the widgets' background.
struct GlowWash: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [WidgetPalette.petal, WidgetPalette.blush], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [.white.opacity(0.7), .clear], center: .topLeading, startRadius: 4, endRadius: 170)
        }
    }
}

/// Four-point sparkle, drawn as a shape so it scales crisply.
struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let inner = r * 0.28
        var path = Path()
        path.move(to: CGPoint(x: c.x, y: c.y - r))
        path.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + inner, y: c.y - inner))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + inner, y: c.y + inner))
        path.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - inner, y: c.y + inner))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - inner, y: c.y - inner))
        return path
    }
}

/// A couple of sparkles for corners.
struct SparklePair: View {
    var color: Color = .white
    var size: CGFloat = 22

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            SparkleShape().fill(color).frame(width: size, height: size)
            SparkleShape().fill(color.opacity(0.85)).frame(width: size * 0.45, height: size * 0.45)
                .offset(x: -size * 0.55, y: size * 0.45)
        }
        .accessibilityHidden(true)
    }
}
