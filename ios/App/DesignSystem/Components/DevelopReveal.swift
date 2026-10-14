import SwiftUI

extension View {
    /// Develops a new AI result like an instant photo: it starts soft, pale and
    /// warm under one gentle flash, then clears over about 1.2 s with a small
    /// sparkle burst and a success haptic. With Reduce Motion it's a 0.25 s
    /// crossfade with no flash or particles.
    ///
    /// Plays once per `id` for the app's lifetime, so a view that comes back
    /// (paging through results, toggling before/after) shows the finished
    /// picture straight away. Give every new result its own id, for example a
    /// UUID per batch plus the image's index.
    func developReveal(id: some Hashable, haptic: Bool = true) -> some View {
        modifier(DevelopReveal(id: AnyHashable(id), haptic: haptic))
    }
}

/// Ids that already played, so the reveal never repeats.
@MainActor
private enum RevealLedger {
    static var played: Set<AnyHashable> = []
}

private struct DevelopReveal: ViewModifier {
    let id: AnyHashable
    let haptic: Bool

    /// 0 = still developing, 1 = clear. Only effect values change per frame
    /// (blur, saturation, brightness, tint), all GPU-composited.
    @State private var developed: Double
    @State private var flash: Double = 0
    @State private var burst = 0
    @State private var done = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(id: AnyHashable, haptic: Bool) {
        self.id = id
        self.haptic = haptic
        _developed = State(initialValue: RevealLedger.played.contains(id) ? 1 : 0)
    }

    func body(content: Content) -> some View {
        let fog = 1 - developed
        content
            .blur(radius: reduceMotion ? 0 : fog * 14)
            .saturation(reduceMotion ? 1 : 1 - fog * 0.85)
            .brightness(reduceMotion ? 0 : fog * 0.16 + flash * 0.22)
            // Instant film starts warm and creamy before its colours settle.
            .colorMultiply(reduceMotion ? .white : Color(red: 1, green: 1 - fog * 0.06, blue: 1 - fog * 0.16))
            .opacity(reduceMotion ? developed : 1)
            .overlay {
                SparkleBurst(trigger: burst, colors: [Palette.auraPink, Palette.auraLilac, Palette.auraButter, Palette.auraMint, Palette.white])
            }
            .sensoryFeedback(.success, trigger: done)
            .onAppear(perform: play)
    }

    private func play() {
        guard !RevealLedger.played.contains(id) else {
            developed = 1
            return
        }
        RevealLedger.played.insert(id)
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.25)) { developed = 1 }
            if haptic { done += 1 }
            return
        }
        // One soft flash (no strobe), then the picture clears.
        withAnimation(.easeOut(duration: 0.18)) { flash = 1 }
        withAnimation(.easeInOut(duration: 0.55).delay(0.18)) { flash = 0 }
        withAnimation(.easeOut(duration: 1.2)) { developed = 1 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            burst += 1
            try? await Task.sleep(for: .milliseconds(500))
            if haptic { done += 1 }
        }
    }
}
