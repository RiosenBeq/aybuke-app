import SwiftUI

/// The cold-launch splash, over the app's first frame. It begins exactly as
/// the launch screen ends (Info.plist `UILaunchScreen`: the petal colour and
/// `LaunchIcon`, same size, same place), then the icon grows a little into a
/// soft glow while the wordmark writes itself under it, letter by letter (each
/// one rising and fading in, a gentle stagger), the sparkle after the "e"
/// twinkles once as the glow takes a breath, and everything crossfades into
/// the app, about 2 s in all. `AppModel.start()` runs underneath and the
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
    /// The letters write themselves on, each after the one before.
    @State private var writes = false
    /// The sparkle after the "e" twinkles, and the glow breathes with it.
    @State private var twinkles = false

    private var isQuiet: Bool { reduceMotion || UIAccessibility.isVoiceOverRunning }
    private static let iconSize: CGFloat = 112
    private static let wordmarkHeight: CGFloat = 36
    /// When the first letter starts, after the glow begins (so the two read as one flow).
    private static let writeStart = 0.24
    /// Between one letter and the next.
    private static let stagger = 0.075

    var body: some View {
        ZStack {
            Color("LaunchBackground")
            Circle()
                .fill(RadialGradient(colors: [Palette.auraPink.opacity(0.34), Palette.blush.opacity(0.55), Palette.blush.opacity(0)],
                                     center: .center, startRadius: Self.iconSize * 0.4, endRadius: 170))
                .frame(width: 340, height: 340)
                .scaleEffect(blooms || isQuiet ? 1 : 0.6)
                .opacity(blooms ? 1 : 0)
                .keyframeAnimator(initialValue: 1.0, trigger: twinkles) { glow, breath in
                    glow.scaleEffect(breath)
                } keyframes: { _ in
                    KeyframeTrack {
                        CubicKeyframe(isQuiet ? 1 : 1.06, duration: 0.2)
                        SpringKeyframe(1, duration: 0.45, spring: .smooth)
                    }
                }
            // The launch screen's picture: the icon on a canvas with its shadow, centred.
            Image("LaunchIcon")
                .scaleEffect(blooms && !isQuiet ? 1.08 : 1)
            wordmark
                .offset(y: Self.iconSize / 2 + 34 + Self.wordmarkHeight / 2)
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

    /// "aybuke" from the `Wordmark` vector's own letters, written on one by one.
    private var wordmark: some View {
        ZStack {
            ForEach(0..<WordmarkGlyph.sparkleIndex, id: \.self) { index in
                letter(index)
            }
            sparkle
        }
        .frame(width: Self.wordmarkHeight * WordmarkGlyph.aspectRatio, height: Self.wordmarkHeight)
    }

    private func letter(_ index: Int) -> some View {
        let delay = isQuiet ? 0 : Double(index) * Self.stagger
        let anchor = WordmarkGlyph.anchor(of: index)
        return WordmarkGlyph(index: index)
            .fill(Palette.ink)
            // Ink comes in quickly and evenly; the rise settles on a soft spring.
            .animation((isQuiet ? Animation.easeOut(duration: 0.3) : .easeOut(duration: 0.26)).delay(delay)) {
                $0.opacity(writes ? 1 : 0)
            }
            .animation(.spring(response: 0.46, dampingFraction: 0.72).delay(delay)) {
                $0.offset(y: writes || isQuiet ? 0 : 10)
                    .scaleEffect(writes || isQuiet ? 1 : 0.86, anchor: anchor)
            }
    }

    /// The icon's sparkle after the "e": it pops in a turn and a little past
    /// full size, once, with a soft glint behind it.
    private var sparkle: some View {
        let anchor = WordmarkGlyph.anchor(of: WordmarkGlyph.sparkleIndex)
        return WordmarkGlyph(index: WordmarkGlyph.sparkleIndex)
            .fill(Palette.ink)
            .animation(isQuiet ? .easeOut(duration: 0.3) : .easeOut(duration: 0.16)) {
                $0.opacity(twinkles ? 1 : 0)
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.48)) {
                $0.scaleEffect(twinkles || isQuiet ? 1 : 0.2, anchor: anchor)
                    .rotationEffect(.degrees(twinkles || isQuiet ? 0 : -70), anchor: anchor)
            }
            .background {
                GeometryReader { proxy in
                    Circle()
                        .fill(RadialGradient(colors: [Palette.white, Palette.auraPink.opacity(0.5), Palette.auraPink.opacity(0)],
                                             center: .center, startRadius: 0, endRadius: Self.wordmarkHeight * 0.42))
                        .frame(width: Self.wordmarkHeight * 0.84, height: Self.wordmarkHeight * 0.84)
                        .position(x: proxy.size.width * anchor.x, y: proxy.size.height * anchor.y)
                        .keyframeAnimator(initialValue: 0.0, trigger: twinkles) { glint, glow in
                            glint.opacity(glow).scaleEffect(0.6 + glow * 0.5)
                        } keyframes: { _ in
                            KeyframeTrack {
                                CubicKeyframe(isQuiet ? 0 : 1, duration: 0.14)
                                CubicKeyframe(0, duration: 0.4)
                            }
                        }
                }
            }
    }

    private func play() async {
        // The first frame is the launch screen's; then the glow comes up.
        try? await Task.sleep(for: .milliseconds(60))
        if isQuiet {
            withAnimation(.easeOut(duration: 0.3)) {
                blooms = true
                writes = true
                twinkles = true
            }
            try? await Task.sleep(for: .milliseconds(650))
        } else {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.72)) { blooms = true }
            try? await Task.sleep(for: .seconds(Self.writeStart))
            // Each letter carries its own delay (`stagger`).
            writes = true
            // The sparkle as the last letter lands.
            try? await Task.sleep(for: .seconds(Double(WordmarkGlyph.sparkleIndex - 1) * Self.stagger + 0.24))
            guard !Task.isCancelled else { return }
            twinkles = true
            try? await Task.sleep(for: .milliseconds(640))
        }
        guard !Task.isCancelled else { return }
        app.endLaunchSplash()
    }
}
