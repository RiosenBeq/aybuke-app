import SwiftUI

// Apple's Liquid Glass (iOS 26) for floating controls, with a frosted
// material fallback on iOS 17–25. The glass APIs only exist in the iOS 26
// SDK (Swift 6.2), so older toolchains compile the fallback.

extension View {
    /// Liquid Glass in `shape`, optionally tinted; frosted material before iOS 26.
    @ViewBuilder
    func liquidGlass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = true) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Palette.white.opacity(0.55), lineWidth: 1))
        }
        #else
        background(.ultraThinMaterial, in: shape)
            .overlay(shape.stroke(Palette.white.opacity(0.55), lineWidth: 1))
        #endif
    }

    /// The tab bar shrinks while she scrolls, like Apple's own apps (iOS 26).
    @ViewBuilder
    func minimizingTabBar() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

/// Groups glass shapes so they blend and morph into each other (iOS 26).
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder let content: Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
        #else
        content
        #endif
    }
}
