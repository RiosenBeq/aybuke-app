import SwiftUI

/// Small motion vocabulary shared by every screen: short (0.2–0.35 s) and
/// gentle. Every effect is skipped or reduced when the user turns on Reduce
/// Motion (a fade or nothing in place of movement).
enum Motion {
    static let press = Animation.spring(response: 0.28, dampingFraction: 0.62)
    static let reveal = Animation.spring(response: 0.55, dampingFraction: 0.82)
    static let bouncy = Animation.spring(response: 0.4, dampingFraction: 0.6)
    /// Something settling into its new state: a chip, a style, a tab.
    static let select = Animation.spring(response: 0.3, dampingFraction: 0.72)
    /// Cards and small panels arriving or leaving (the invite card, notices).
    static let appear = Animation.spring(response: 0.34, dampingFraction: 0.86)
    /// A tab or section coming to the front.
    static let tab = Animation.easeOut(duration: 0.26)
}

/// Squishy press feedback for cards and tiles: scale down a little, spring back.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.95

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.02 : 0)
            .pressFeedback(configuration.isPressed, scale: scale)
    }
}

/// The press feedback every button style shares: a small squish that springs
/// back, or with Reduce Motion a light dim in place of the movement.
private struct PressFeedback: ViewModifier {
    let isPressed: Bool
    let scale: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed && !reduceMotion ? scale : 1)
            .opacity(isPressed && reduceMotion ? 0.8 : 1)
            .animation(reduceMotion ? .easeOut(duration: 0.12) : Motion.press, value: isPressed)
    }
}

/// A small spring "pop" as something becomes selected; with Reduce Motion the
/// colour change says it alone. Scaling never moves the layout.
private struct SelectionPop: ViewModifier {
    let isSelected: Bool
    @State private var pops = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: 1.0, trigger: pops) { view, scale in
                view.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    SpringKeyframe(1.06, duration: 0.12, spring: .snappy)
                    SpringKeyframe(1.0, duration: 0.24, spring: .bouncy)
                }
            }
            .onChange(of: isSelected) { _, selected in
                if selected && !reduceMotion { pops += 1 }
            }
    }
}

private struct EntranceValues {
    var opacity = 1.0
    var lift = 0.0
}

/// A tab (or a Mac section) coming to the front fades up a few points; a plain
/// quick fade with Reduce Motion. Never on the first appearance of a tab: the
/// launch splash has that moment.
private struct TabEntrance: ViewModifier {
    let isFront: Bool
    let onEachAppear: Bool
    @State private var entrances = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: EntranceValues(), trigger: entrances) { view, value in
                view.opacity(value.opacity).offset(y: value.lift)
            } keyframes: { _ in
                KeyframeTrack(\.opacity) {
                    MoveKeyframe(reduceMotion ? 0.6 : 0.4)
                    CubicKeyframe(1, duration: reduceMotion ? 0.16 : 0.26)
                }
                KeyframeTrack(\.lift) {
                    MoveKeyframe(reduceMotion ? 0 : 6)
                    SpringKeyframe(0, duration: 0.3, spring: .smooth)
                }
            }
            .onChange(of: isFront) { _, front in
                if front { entrances += 1 }
            }
            .onAppear {
                if onEachAppear { entrances += 1 }
            }
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
    /// Button styles' press feedback (see `PressFeedback`).
    func pressFeedback(_ isPressed: Bool, scale: CGFloat = 0.95) -> some View {
        modifier(PressFeedback(isPressed: isPressed, scale: scale))
    }
    /// A gentle spring as it becomes selected (chips, styles, effects, looks).
    func selectionPop(_ isSelected: Bool) -> some View { modifier(SelectionPop(isSelected: isSelected)) }
    /// A tab fading up as it comes to the front.
    func tabEntrance(_ isFront: Bool) -> some View { modifier(TabEntrance(isFront: isFront, onEachAppear: false)) }
    /// The same for views built anew each time they come to the front (the Mac's sections).
    func sectionEntrance() -> some View { modifier(TabEntrance(isFront: true, onEachAppear: true)) }
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
