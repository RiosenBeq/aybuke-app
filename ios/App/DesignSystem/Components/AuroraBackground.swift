import SwiftUI

/// Slow-moving blurred color fields behind hero areas. Static when the user
/// prefers reduced motion.
struct AuroraBackground: View {
    var intensity: Double = 1
    @State private var animate = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Palette.background
            Circle()
                .fill(Palette.primary)
                .frame(width: 340, height: 340)
                .blur(radius: 120)
                .offset(x: animate ? -80 : -150, y: animate ? -280 : -220)
                .opacity(0.5 * intensity)
            Circle()
                .fill(Palette.gradientEnd)
                .frame(width: 300, height: 300)
                .blur(radius: 120)
                .offset(x: animate ? 150 : 90, y: animate ? -140 : -200)
                .opacity(0.42 * intensity)
            Circle()
                .fill(Palette.secondary)
                .frame(width: 320, height: 320)
                .blur(radius: 140)
                .offset(x: animate ? 30 : 110, y: animate ? 300 : 220)
                .opacity(0.32 * intensity)
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

/// Checkerboard used behind images with transparency (background removal).
struct CheckerboardBackground: View {
    var squareSize: CGFloat = 12

    var body: some View {
        Canvas { context, size in
            let columns = Int(ceil(size.width / squareSize))
            let rows = Int(ceil(size.height / squareSize))
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0x2A2A33)))
            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    let rect = CGRect(x: CGFloat(column) * squareSize, y: CGFloat(row) * squareSize, width: squareSize, height: squareSize)
                    context.fill(Path(rect), with: .color(Color(hex: 0x3A3A45)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
