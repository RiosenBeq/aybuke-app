import SwiftUI

/// A soft blush glint gliding over a placeholder while something loads (a My
/// Works tile, a creation opening, Aybik's picks or answer), in place of a
/// spinner. Clipped to the placeholder's own shape; with Reduce Motion the
/// placeholder stays still and says "loading" alone.
private struct Shimmer: ViewModifier {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            if isActive && !reduceMotion {
                GeometryReader { proxy in
                    let width = proxy.size.width
                    LinearGradient(
                        colors: [Palette.blush.opacity(0), Palette.blush.opacity(0.5), Palette.blush.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: max(width * 0.5, 60))
                    .keyframeAnimator(initialValue: -1.0, repeating: true) { band, position in
                        band.offset(x: position * width)
                    } keyframes: { _ in
                        // Across, then a short rest, like `GlowSweep` but quicker.
                        KeyframeTrack {
                            CubicKeyframe(1.2, duration: 1.0)
                            LinearKeyframe(1.2, duration: 0.35)
                        }
                    }
                }
                .mask(content)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .transition(.opacity)
            }
        }
    }
}

/// A rounded bar standing in for a line of text that hasn't arrived yet.
struct SkeletonLine: View {
    var width: CGFloat? = nil
    var height: CGFloat = 10

    var body: some View {
        Capsule()
            .fill(Palette.strokeStrong.opacity(0.55))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

extension View {
    /// A light band gliding over the view while `isActive` (see `Shimmer`).
    func shimmering(_ isActive: Bool = true) -> some View {
        modifier(Shimmer(isActive: isActive))
    }
}
