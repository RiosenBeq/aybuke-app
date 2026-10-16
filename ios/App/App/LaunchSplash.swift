import SwiftUI

/// The cold-launch splash, over the app's first frame. It begins exactly as
/// the launch screen ends (Info.plist `UILaunchScreen`: the petal colour and
/// `LaunchIcon`, same size, same place), then the icon grows a little into a
/// soft glow while the wordmark rises under it, and everything crossfades into
/// the app, about 1.9 s in all. `AppModel.start()` runs underneath and the
/// splash never waits for it (or for the network). With Reduce Motion or
/// VoiceOver it's a short hold and a plain fade. Once per process, so never
/// when she comes back from the background; never in screenshot scenes,
/// tests, perf probes or on the Mac; a link (widget, notification, Siri) or
/// leaving the app cuts it short.
enum LaunchSplash {
    static let fadeDuration = 0.38

    /// Decided once, as the model is made.
    static var shouldShow: Bool {
        if Platform.isMac { return false }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return false }
        #if DEBUG
        if ScreenshotScene.current != nil { return false }
        #endif
        #if DEBUG || GL_PERF
        let defaults = UserDefaults.standard
        if defaults.string(forKey: "GLPerfBench") != nil || defaults.string(forKey: "GLPerfOpen") != nil { return false }
        #endif
        return true
    }

    /// The splash leaves with a fade and a breath of scale (a plain fade with Reduce Motion).
    static var exit: AnyTransition {
        UIAccessibility.isReduceMotionEnabled ? .opacity : .opacity.combined(with: .scale(scale: 1.03))
    }
}

struct LaunchSplashView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    /// The glow blooms and the icon grows into it.
    @State private var blooms = false
    @State private var showsWordmark = false

    private var isQuiet: Bool { reduceMotion || UIAccessibility.isVoiceOverRunning }
    private static let iconSize: CGFloat = 112
    private static let wordmarkHeight: CGFloat = 36

    var body: some View {
        ZStack {
            Color("LaunchBackground")
            Circle()
                .fill(RadialGradient(colors: [Palette.auraPink.opacity(0.34), Palette.blush.opacity(0.55), Palette.blush.opacity(0)],
                                     center: .center, startRadius: Self.iconSize * 0.4, endRadius: 170))
                .frame(width: 340, height: 340)
                .scaleEffect(blooms || isQuiet ? 1 : 0.6)
                .opacity(blooms ? 1 : 0)
            // The launch screen's picture: the icon on a canvas with its shadow, centred.
            Image("LaunchIcon")
                .scaleEffect(blooms && !isQuiet ? 1.08 : 1)
            BrandWordmark(height: Self.wordmarkHeight, color: Palette.ink)
                .offset(y: Self.iconSize / 2 + 34 + Self.wordmarkHeight / 2 + (showsWordmark || isQuiet ? 0 : 12))
                .opacity(showsWordmark ? 1 : 0)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: Brand.name))
        .accessibilityAddTraits(.isModal)
        .task { await play() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { app.endLaunchSplash(animated: false) }
        }
    }

    private func play() async {
        // The first frame is the launch screen's; then the glow comes up.
        try? await Task.sleep(for: .milliseconds(60))
        if isQuiet {
            withAnimation(.easeOut(duration: 0.3)) {
                blooms = true
                showsWordmark = true
            }
            try? await Task.sleep(for: .milliseconds(650))
        } else {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.72)) { blooms = true }
            try? await Task.sleep(for: .milliseconds(240))
            withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) { showsWordmark = true }
            try? await Task.sleep(for: .milliseconds(1_250))
        }
        guard !Task.isCancelled else { return }
        app.endLaunchSplash()
    }
}
