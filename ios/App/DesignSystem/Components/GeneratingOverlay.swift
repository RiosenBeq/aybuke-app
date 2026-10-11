import SwiftUI

/// Full-screen progress state shown while the AI works. Rotating tips keep the
/// 5–20 s wait feeling shorter.
struct GeneratingOverlay: View {
    var title = "Creating magic…"
    var onCancel: (() -> Void)?

    @State private var tipIndex = 0
    @State private var spin = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let tips = [
        "Tip: be specific — lighting, mood and style words help a lot.",
        "Tip: hold the compare button to see your original.",
        "Background removal runs on your phone and is always free.",
        "Your photos are deleted from our servers within 24 hours.",
        "Tip: try “golden hour”, “film grain” or “studio light”.",
    ]

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            Palette.background.opacity(0.55).ignoresSafeArea()

            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .fill(AngularGradient(colors: Palette.auroraColors + [Palette.primary], center: .center))
                        .frame(width: 132, height: 132)
                        .blur(radius: 22)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                    Circle()
                        .fill(Palette.background.opacity(0.6))
                        .frame(width: 92, height: 92)
                    Image(systemName: "sparkles")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolEffect(.pulse, options: .repeating)
                }
                .accessibilityHidden(true)

                VStack(spacing: 10) {
                    Text(title)
                        .font(.display(24, weight: .bold))
                        .foregroundStyle(Palette.textPrimary)
                    Text(tips[tipIndex])
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
                    tipIndex = (tipIndex + 1) % tips.count
                }
            }
        }
    }
}
