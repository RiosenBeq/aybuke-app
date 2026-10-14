import SwiftUI

/// Small motion vocabulary shared by every screen. Every effect is skipped or
/// reduced when the user turns on Reduce Motion.
enum Motion {
    static let press = Animation.spring(response: 0.28, dampingFraction: 0.62)
    static let reveal = Animation.spring(response: 0.55, dampingFraction: 0.82)
    static let bouncy = Animation.spring(response: 0.4, dampingFraction: 0.6)
}

/// Squishy press feedback for cards and tiles: scale down a little, spring back.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.95

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .brightness(configuration.isPressed ? -0.02 : 0)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

/// Fades and lifts content in the first time it appears (staggered by `index`).
private struct RevealOnAppear: ViewModifier {
    let index: Int
    @State private var isVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isVisible || reduceMotion ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : 18)
            .scaleEffect(isVisible || reduceMotion ? 1 : 0.98, anchor: .top)
            .onAppear {
                guard !isVisible else { return }
                withAnimation(Motion.reveal.delay(min(Double(index) * 0.06, 0.42))) { isVisible = true }
            }
    }
}

/// A gentle twinkle: scale and opacity breathe forever, offset by `phase`.
private struct Twinkle: ViewModifier {
    let phase: Double
    @State private var isOn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(isOn ? 1.15 : 0.82)
            .opacity(isOn ? 1 : 0.55)
            .rotationEffect(.degrees(isOn ? 12 : -6))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true).delay(phase)) { isOn = true }
            }
    }
}

/// Slow up-and-down float for illustrations.
private struct Floating: ViewModifier {
    var distance: CGFloat = 6
    var duration: Double = 2.6
    @State private var isUp = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .offset(y: isUp ? -distance : distance)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) { isUp = true }
            }
    }
}

extension View {
    func reveal(_ index: Int = 0) -> some View { modifier(RevealOnAppear(index: index)) }
    func twinkle(phase: Double = 0) -> some View { modifier(Twinkle(phase: phase)) }
    func floating(distance: CGFloat = 6, duration: Double = 2.6) -> some View {
        modifier(Floating(distance: distance, duration: duration))
    }

    /// A soft white light band that sweeps across the view every few seconds.
    func glowSweep(cornerRadius: CGFloat = Metrics.cardRadius) -> some View {
        overlay(GlowSweep().clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)).allowsHitTesting(false))
    }
}

struct GlowSweep: View {
    @State private var offset: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            LinearGradient(
                colors: [.white.opacity(0), .white.opacity(0.55), .white.opacity(0)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: proxy.size.width * 0.45)
            .rotationEffect(.degrees(18))
            .offset(x: offset * proxy.size.width * 1.6)
            .blendMode(.plusLighter)
        }
        .task {
            guard !reduceMotion else { return }
            // Sweep, rest, repeat (repeatForever can't pause between runs).
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.6))
                offset = -1
                withAnimation(.easeInOut(duration: 1.4)) { offset = 1 }
                try? await Task.sleep(for: .seconds(1.4))
            }
        }
        .accessibilityHidden(true)
    }
}
