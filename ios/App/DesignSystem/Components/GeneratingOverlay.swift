import SwiftUI

/// Full-screen progress state shown while the AI works. Rotating tips keep the
/// 5–20 s wait feeling shorter.
struct GeneratingOverlay: View {
    var title = "Creating magic…"
    var onCancel: (() -> Void)?

    @Environment(AppModel.self) private var app
    @State private var tipIndex = 0
    @State private var spin = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tips: [String] {
        [
            "Tip: be specific — lighting, mood and style words help a lot.",
            "Tip: hold the photo to compare with your original.",
            "Background removal runs on your phone and is always free.",
            "Your photos are never used to train AI and are deleted from our servers within \(app.config.dataRetentionHours) hours.",
            "Tip: try “soft glam”, “pink hair” or “golden hour”.",
            "Share straight to Instagram Stories or as a before/after collage.",
        ]
    }

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            Palette.background.opacity(0.6).ignoresSafeArea()

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
                }
                .accessibilityHidden(true)

                VStack(spacing: 10) {
                    Text(title)
                        .font(.display(24, weight: .bold))
                        .foregroundStyle(Palette.textPrimary)
                        .multilineTextAlignment(.center)
                    Text(tips[tipIndex % tips.count])
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300, minHeight: 44)
                        .id(tipIndex)
                        .transition(.opacity)
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
}
