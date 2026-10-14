import SwiftUI

extension View {
    /// Fine print over the aurora: the glow lowers its contrast (about 3:1 in
    /// dark mode), so in dark mode it sits on a solid surface.
    func finePrintBacking() -> some View {
        modifier(FinePrintBacking())
    }
}

private struct FinePrintBacking: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if colorScheme == .dark {
            content
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Palette.surface, in: .chip)
        } else {
            content
        }
    }
}

/// Slow-moving blurred blush and white fields behind hero areas — a soft
/// pink glow on the petal canvas. Static when the user prefers reduced motion.
struct AuroraBackground: View {
    var intensity: Double = 1
    @State private var animate = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        ZStack {
            Palette.background
            Circle()
                .fill(Palette.blush)
                .frame(width: 360, height: 360)
                .blur(radius: 110)
                .offset(x: animate ? -70 : -150, y: animate ? -280 : -220)
                .opacity((isDark ? 0.30 : 0.9) * intensity)
            Circle()
                .fill(isDark ? Palette.charcoal : Palette.white)
                .frame(width: 300, height: 300)
                .blur(radius: 110)
                .offset(x: animate ? 150 : 90, y: animate ? -120 : -190)
                .opacity((isDark ? 0.9 : 0.85) * intensity)
            Circle()
                .fill(Palette.blush)
                .frame(width: 340, height: 340)
                .blur(radius: 130)
                .offset(x: animate ? 30 : 120, y: animate ? 320 : 230)
                .opacity((isDark ? 0.22 : 0.75) * intensity)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

/// Checkerboard used behind images with transparency (background removal):
/// white and petal squares, or two charcoal greys in dark mode.
struct CheckerboardBackground: View {
    var squareSize: CGFloat = 12
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        let base = isDark ? Color(hex: 0x2A2D30) : Palette.white
        let alternate = isDark ? Color(hex: 0x35383C) : Palette.petal
        Canvas { context, size in
            let columns = Int(ceil(size.width / squareSize))
            let rows = Int(ceil(size.height / squareSize))
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(base))
            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    let rect = CGRect(x: CGFloat(column) * squareSize, y: CGFloat(row) * squareSize, width: squareSize, height: squareSize)
                    context.fill(Path(rect), with: .color(alternate))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
