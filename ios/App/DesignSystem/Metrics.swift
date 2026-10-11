import SwiftUI

enum Metrics {
    static let gutter: CGFloat = 16
    static let sectionSpacing: CGFloat = 28
    static let cardRadius: CGFloat = 22
    static let controlRadius: CGFloat = 16
    static let buttonHeight: CGFloat = 56
}

struct CardBackground: ViewModifier {
    var radius: CGFloat = Metrics.cardRadius
    var fill: Color = Palette.surface

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Palette.stroke, lineWidth: 1)
            )
    }
}

extension View {
    func cardStyle(radius: CGFloat = Metrics.cardRadius, fill: Color = Palette.surface) -> some View {
        modifier(CardBackground(radius: radius, fill: fill))
    }

    /// Frosted panel used for floating controls over photos.
    func glassPanel(radius: CGFloat = Metrics.cardRadius) -> some View {
        background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Palette.strokeStrong, lineWidth: 1)
            )
    }
}
