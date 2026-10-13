import SwiftUI

enum Metrics {
    static let gutter: CGFloat = 16
    static let sectionSpacing: CGFloat = 28
    static let cardRadius: CGFloat = 22
    static let controlRadius: CGFloat = 16
    /// Template cards are sharp-edged like prints; controls stay soft.
    static let printRadius: CGFloat = 0
    static let buttonHeight: CGFloat = 56
    /// Widest a column of content gets on iPad and in landscape.
    static let readableWidth: CGFloat = 820
    /// Narrower column for forms, panels and flows (onboarding, editor panels).
    static let compactWidth: CGFloat = 620
}

/// White card on the petal canvas: a soft shadow in light mode, a hairline
/// stroke in dark mode.
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
            .shadow(color: Palette.shadow, radius: 14, y: 6)
    }
}

extension View {
    func cardStyle(radius: CGFloat = Metrics.cardRadius, fill: Color = Palette.surface) -> some View {
        modifier(CardBackground(radius: radius, fill: fill))
    }

    /// Frosted panel used for floating controls over photos.
    func glassPanel(radius: CGFloat = Metrics.cardRadius) -> some View {
        background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Palette.strokeStrong, lineWidth: 1)
            )
            .shadow(color: Palette.shadow, radius: 18, y: 8)
    }

    /// Keeps a screen's content at a comfortable width, centred, so iPad and
    /// landscape layouts don't stretch cards edge to edge. No-op on iPhone.
    func readableWidth(_ width: CGFloat = Metrics.readableWidth, alignment: Alignment = .leading) -> some View {
        frame(maxWidth: width, alignment: alignment)
            .frame(maxWidth: .infinity)
    }

    /// Roomier sheets on iPad for content-heavy flows (paywall, share
    /// composer). iPhone sheets are unchanged.
    @ViewBuilder
    func pageSheetSizing() -> some View {
        if #available(iOS 18.0, *) {
            presentationSizing(.page)
        } else {
            self
        }
    }

    /// Small uppercase label above a headline ("MAGIC EDIT").
    func eyebrowStyle(_ color: Color = Palette.textSecondary) -> some View {
        font(.caption.weight(.heavy))
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}
