import SwiftUI

/// Ink capsule with a blush label (blush with ink on the dark canvas) for the
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
                .foregroundStyle(isEnabled ? Palette.onAccent : Palette.textTertiary)
                .frame(maxWidth: .infinity, minHeight: Metrics.buttonHeight)
                .padding(.horizontal, 20)
                .background {
                    Capsule()
                        .fill(isEnabled ? Palette.accent : Palette.strokeStrong)
                }
                .shadow(color: Palette.ink.opacity(isEnabled ? 0.18 : 0), radius: 16, y: 8)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
        }
    }
}

/// White capsule for secondary actions.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.buttonLabel)
            .foregroundStyle(Palette.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, 18)
            .background(Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.strokeStrong, lineWidth: 1))
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
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

extension ButtonStyle where Self == IconButtonStyle {
    static var icon: IconButtonStyle { IconButtonStyle() }
}

/// Label for a primary action that costs credits, e.g. "Generate · 1 ⚡︎".
struct CostLabel: View {
    let title: LocalizedStringKey
    let cost: Int
    var isLoading = false

    var body: some View {
        HStack(spacing: 10) {
            if isLoading {
                ProgressView().tint(Palette.onAccent)
            } else {
                Image(systemName: "sparkles")
            }
            Text(title)
            if cost > 0 && !isLoading {
                HStack(spacing: 3) {
                    Image(systemName: "bolt.fill").font(.caption)
                    Text("\(cost)").monospacedDigit()
                }
                .font(.subheadline.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Palette.onAccent.opacity(0.18), in: Capsule())
            }
        }
    }
}
