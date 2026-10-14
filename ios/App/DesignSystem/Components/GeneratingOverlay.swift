import SwiftUI

/// Hearts and sparkles circling the progress glow.
private struct OrbitingCharms: View {
    let radius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let charms: [(symbol: String, size: CGFloat, ink: Bool)] = [
        ("heart.fill", 15, true), ("sparkle", 18, false), ("star.fill", 11, true),
        ("sparkle", 13, true), ("heart.fill", 12, false), ("sparkles", 15, true),
    ]

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(Array(charms.enumerated()), id: \.offset) { index, charm in
                    let angle = (time * 0.55).truncatingRemainder(dividingBy: 2 * .pi) + Double(index) / Double(charms.count) * 2 * .pi
                    let wobble = sin(time * 2 + Double(index)) * 6
                    Image(systemName: charm.symbol)
                        .font(.system(size: charm.size, weight: .bold))
                        .foregroundStyle(charm.ink ? Palette.ink : Palette.white)
                        .shadow(color: Palette.ink.opacity(0.12), radius: 3, y: 1)
                        .scaleEffect(0.85 + 0.25 * (sin(time * 2.4 + Double(index) * 1.3) + 1) / 2)
                        .offset(x: cos(angle) * (radius + wobble), y: sin(angle) * (radius + wobble))
                }
            }
        }
    }
}

/// Full-screen progress state shown while the AI works. Rotating tips keep the
/// 5–20 s wait feeling shorter.
struct GeneratingOverlay: View {
    /// Already localized.
    var title = String(localized: "Creating magic…")
    /// Cloud jobs: offer "Ping me when it's ready" the first time.
    var offersReadyPing = false
    /// 0…1 when the work reports progress (video exports); nil hides the bar.
    var progress: Double?
    /// The tips talk about AI and our servers, so on-device work turns them off.
    var showsTips = true
    var onCancel: (() -> Void)?

    @Environment(AppModel.self) private var app
    @State private var pingAnswer: Bool?
    @State private var tipIndex = 0
    @State private var spin = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tips: [String] {
        var tips = [
            String(localized: "Tip: be specific — lighting, mood and style words help a lot."),
            String(localized: "Tip: hold the photo to compare with your original."),
            String(localized: "Background removal runs on your device and is always free."),
            String(localized: "Your photos are never used to train AI and are deleted from our servers within \(app.config.retentionPhrase)."),
            String(localized: "Tip: try “soft glam”, “pink hair” or “golden hour”."),
        ]
        // There's no Instagram app on the Mac.
        if !Platform.isMac {
            tips.append(String(localized: "Share straight to Instagram Stories or as a before/after collage."))
        }
        return tips
    }

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            Palette.background.opacity(0.86).ignoresSafeArea()

            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .fill(AngularGradient(colors: Palette.glowColors + [Palette.blush], center: .center))
                        .frame(width: 140, height: 140)
                        .blur(radius: 18)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                    Circle()
                        .fill(Palette.surface)
                        .frame(width: 92, height: 92)
                        .shadow(color: Palette.shadow, radius: 12, y: 6)
                    Image(systemName: "sparkles")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .symbolEffect(.pulse, options: .repeating)
                    OrbitingCharms(radius: 96)
                }
                .frame(width: 230, height: 230)
                .accessibilityHidden(true)

                VStack(spacing: 10) {
                    Text(title)
                        .font(.display(24, weight: .bold))
                        .foregroundStyle(Palette.textPrimary)
                        .multilineTextAlignment(.center)
                    if showsTips {
                        Text(tips[tipIndex % tips.count])
                            .font(.subheadline)
                            .foregroundStyle(Palette.textSecondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 300, minHeight: 44)
                            .id(tipIndex)
                            .transition(.opacity)
                    }
                }

                if let progress {
                    VStack(spacing: 8) {
                        ProgressView(value: min(max(progress, 0), 1))
                            .tint(Palette.accent)
                        Text(min(max(progress, 0), 1), format: .percent.precision(.fractionLength(0)))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .frame(maxWidth: 240)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(title)
                    .accessibilityValue(Text(min(max(progress, 0), 1), format: .percent.precision(.fractionLength(0))))
                }

                if offersReadyPing {
                    readyPing
                }

                if let onCancel {
                    Button("Cancel", action: onCancel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .padding(32)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title). Please wait.")
        .onAppear {
            guard pingAnswer == nil else { return }
            if app.notifier.preferences.glowReady, app.notifier.isAllowedBySystem {
                pingAnswer = true
            } else if !app.notifier.offersReadyPing {
                pingAnswer = false
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 3.5).repeatForever(autoreverses: false)) {
                spin = true
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3.2))
                withAnimation(.easeInOut(duration: 0.35)) {
                    tipIndex += 1
                }
            }
        }
    }

    /// Asks for notification permission in context: she's waiting and may
    /// want to leave the app.
    @ViewBuilder
    private var readyPing: some View {
        switch pingAnswer {
        case nil:
            Button {
                Task {
                    let on = await app.notifier.set(.glowReady, on: true)
                    withAnimation(Motion.bouncy) { pingAnswer = on }
                    if on { Haptics.success() }
                }
            } label: {
                Label("Ping me when it's ready", systemImage: "bell.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Palette.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(Palette.stroke, lineWidth: 1))
                    .shadow(color: Palette.shadow, radius: 8, y: 3)
            }
            .buttonStyle(.pressable)
            .transition(.scale.combined(with: .opacity))
        case true?:
            Label("We'll ping you when it's ready", systemImage: "bell.badge.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
                .symbolEffect(.bounce, value: pingAnswer)
                .transition(.scale.combined(with: .opacity))
        case false?:
            EmptyView()
        }
    }
}
