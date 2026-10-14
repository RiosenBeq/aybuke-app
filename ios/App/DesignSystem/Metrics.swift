import SwiftUI

enum Metrics {
    static let gutter: CGFloat = 16
    static let sectionSpacing: CGFloat = 28
    /// Crisp corners, from big to small: cards and panels, buttons, controls
    /// (fields, tiles, photos on a canvas), chips and pills, then tags and
    /// badges. Every corner in the app comes from here (see the shapes below).
    static let cardRadius: CGFloat = 14
    static let buttonRadius: CGFloat = 12
    static let controlRadius: CGFloat = 10
    static let chipRadius: CGFloat = 8
    static let tagRadius: CGFloat = 5
    /// Template cards are square-edged like prints.
    static let printRadius: CGFloat = 0
    static let buttonHeight: CGFloat = 52
    /// Widest a column of content gets on iPad and in landscape.
    static let readableWidth: CGFloat = 820
    /// Narrower column for forms, panels and flows (onboarding, editor panels).
    static let compactWidth: CGFloat = 620
}

/// The shapes behind `Metrics`' radii: `.background(Palette.surface, in: .chip)`,
/// `RoundedRectangle.card.strokeBorder(…)`.
extension Shape where Self == RoundedRectangle {
    static var card: RoundedRectangle { RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous) }
    static var button: RoundedRectangle { RoundedRectangle(cornerRadius: Metrics.buttonRadius, style: .continuous) }
    static var control: RoundedRectangle { RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous) }
    static var chip: RoundedRectangle { RoundedRectangle(cornerRadius: Metrics.chipRadius, style: .continuous) }
    static var tag: RoundedRectangle { RoundedRectangle(cornerRadius: Metrics.tagRadius, style: .continuous) }
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
