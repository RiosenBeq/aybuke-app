import SwiftUI

/// A short burst of hearts and sparkles that celebrates a finished creation.
/// Plays once each time `trigger` changes; skipped with Reduce Motion.
struct SparkleBurst: View {
    let trigger: Int
    var colors: [Color] = [Palette.blush, Palette.white, Palette.ink, Palette.blush]

    @State private var particles: [Particle] = []
    @State private var progress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Particle: Identifiable {
        let id = UUID()
        let symbol: String
        let angle: Double
        let distance: CGFloat
        let size: CGFloat
        let spin: Double
        let color: Color
    }

    var body: some View {
        ZStack {
            ForEach(particles) { particle in
                Image(systemName: particle.symbol)
                    .font(.system(size: particle.size, weight: .bold))
                    .foregroundStyle(particle.color)
                    .shadow(color: Palette.ink.opacity(0.12), radius: 2, y: 1)
                    .rotationEffect(.degrees(particle.spin * Double(progress)))
                    .offset(
                        x: cos(particle.angle) * particle.distance * progress,
                        y: sin(particle.angle) * particle.distance * progress - 40 * progress
                    )
                    .scaleEffect(0.4 + progress * 0.8)
                    .opacity(Double(1 - progress) * 1.4)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, _ in fire() }
    }

    private func fire() {
        guard !reduceMotion else { return }
        let symbols = ["heart.fill", "sparkle", "star.fill", "sparkles", "heart.fill"]
        particles = (0..<18).map { index in
            Particle(
                symbol: symbols[index % symbols.count],
                angle: Double(index) / 18 * 2 * .pi + .random(in: -0.2...0.2),
                distance: .random(in: 90...170),
                size: .random(in: 12...22),
                spin: .random(in: -120...120),
                color: colors[index % colors.count]
            )
        }
        progress = 0
        withAnimation(.easeOut(duration: 1.1)) { progress = 1 }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            particles = []
        }
    }
}
