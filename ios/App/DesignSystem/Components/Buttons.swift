import SwiftUI

/// Ink button with a blush label (blush with ink on the dark canvas) for the
/// one primary action on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration)
    }

    private struct PrimaryButtonBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.buttonLabel)
                .multilineTextAlignment(.center)
                .foregroundStyle(isEnabled ? Palette.onAccent : Palette.textTertiary)
                // Long translations and large text wrap instead of truncating.
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, minHeight: Metrics.buttonHeight)
                .padding(.horizontal, 20)
                .background {
                    // Disabled: the tint sits on the page color, so content
                    // scrolling under a floating button doesn't show through.
                    RoundedRectangle.button
                        .fill(isEnabled ? Palette.accent : Palette.strokeStrong)
                        .background(isEnabled ? .clear : Palette.background, in: .button)
                }
                .shadow(color: Palette.ink.opacity(isEnabled ? 0.18 : 0), radius: 16, y: 8)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
        }
    }
}

/// White button for secondary actions.
struct SecondaryButtonStyle: ButtonStyle {
    /// `Metrics.buttonHeight` when it sits under a primary button as an equal choice.
    var minHeight: CGFloat = 46

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.buttonLabel)
            .multilineTextAlignment(.center)
            .foregroundStyle(Palette.textPrimary)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .padding(.horizontal, 18)
            .background(Palette.surface, in: .button)
            .overlay(RoundedRectangle.button.strokeBorder(Palette.strokeStrong, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Round Liquid Glass icon button used in toolbars and over photos.
struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = 40

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(Palette.textPrimary)
            .frame(width: size, height: size)
            .liquidGlass(in: Circle(), tint: Palette.white.opacity(0.35))
            .shadow(color: Palette.shadow, radius: 8, y: 3)
            // The circle can stay 40 pt; the touch target is never under 44.
            .frame(width: max(size, 44), height: max(size, 44))
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
    /// As tall as the primary button: an equal choice, not small print.
    static var secondaryFull: SecondaryButtonStyle { SecondaryButtonStyle(minHeight: Metrics.buttonHeight) }
}

extension ButtonStyle where Self == IconButtonStyle {
    static var icon: IconButtonStyle { IconButtonStyle() }
}

/// Two buttons side by side, the primary action last; stacked, primary on
/// top, when their labels don't fit in one row (long translations, large
/// text), so no label is cut short or broken mid-word.
struct ButtonRow<Secondary: View, Primary: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var secondary: Secondary
    @ViewBuilder var primary: Primary

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: spacing) {
                secondary
                primary
            }
            VStack(spacing: 10) {
                primary
                secondary
            }
        }
    }
}

/// Label for a primary action that costs credits, e.g. "Generate · 1 ⚡︎".
struct CostLabel: View {
    let title: LocalizedStringKey
    let cost: Int
    var isLoading = false

    var body: some View {
        // One line when it fits; with long translations or large text the
        // title gets a line of its own, so no word breaks in the middle.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                icon
                Text(title)
                costBadge
            }
            VStack(spacing: 4) {
                Text(title)
                HStack(spacing: 8) {
                    icon
                    costBadge
                }
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        if isLoading {
            ProgressView().tint(Palette.onAccent)
        } else {
            Image(systemName: "sparkles")
        }
    }

    @ViewBuilder
    private var costBadge: some View {
        if cost > 0 && !isLoading {
            HStack(spacing: 3) {
                Image(systemName: "bolt.fill").font(.caption)
                Text("\(cost)").monospacedDigit()
            }
            .font(.subheadline.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Palette.onAccent.opacity(0.18), in: .tag)
        }
    }
}
