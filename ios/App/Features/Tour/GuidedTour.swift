import SwiftUI
import AppCore

/// One stop on the first-run tour. Each step lives on a tab and points at a
/// view marked with `.tourAnchor(_:)`.
enum TourStep: Int, CaseIterable, Identifiable {
    case hero
    case credits
    case quickTools
    case create
    case edit
    case library
    case settings

    var id: Int { rawValue }

    /// Steps that show cloud AI features or credits.
    var isAboutCloudAI: Bool { self == .hero || self == .credits || self == .create }

    var tab: AppTab {
        switch self {
        case .hero, .credits, .quickTools, .settings: return .home
        case .create: return .create
        case .edit: return .edit
        case .library: return .library
        }
    }

    /// Headline with an *italic accent*, as in the app's other headlines.
    /// People who start Pro during onboarding see the tour as Pro members.
    func title(isPro: Bool) -> String {
        switch self {
        case .hero: return String(localized: "Say the *change*")
        case .credits: return isPro ? String(localized: "Your monthly *glow*") : String(localized: "Your daily *glow*")
        case .quickTools: return String(localized: "Free on your *device*")
        case .create: return String(localized: "Create *anything*")
        case .edit: return String(localized: "Photos *and* videos")
        case .library: return String(localized: "Your *gallery*")
        case .settings: return String(localized: "Make it *yours*")
        }
    }

    /// `cloudAI` false (under 13): only the free on-device tools are named.
    func message(isPro: Bool, policy: CreditPolicy, cloudAI: Bool = true) -> String {
        switch self {
        case .hero:
            return String(localized: "Describe any change, like pink hair, golden hour or soft glam, and watch your photo glow. Or tap a trend below.")
        case .credits:
            return isPro
                ? String(localized: "Pro gives you \(policy.proMonthlyAllowance) credits every month. Free tools never use credits, and failed edits are always refunded.")
                : String(localized: "You get \(policy.freeDailyAllowance) free credits every day. Free tools never use credits, and failed edits are always refunded.")
        case .quickTools:
            return cloudAI
                ? String(localized: "80s & 90s effects, Cut out and Adjust are free and run right on your device. Enhance and Erase add AI magic.")
                : String(localized: "80s & 90s effects, Cut out and Adjust are free and run right on your device.")
        case .create:
            return String(localized: "Type an idea, pick a style and get art in seconds. No prompt skills needed.")
        case .edit:
            return String(localized: "Find your best selfie, cut the silences out of a video and add 80s & 90s effects. All free.")
        case .library:
            return Platform.isMac
                ? String(localized: "Everything you make stays on your Mac. Heart your favorites and share in one click.")
                : String(localized: "Everything you make stays on your device. Heart your favorites and share in one tap.")
        case .settings:
            return String(localized: "Language, look, privacy and your account live here. Enjoy the glow ✨")
        }
    }
}

/// Runs the first-run tour: which step is showing and where its target is
/// on screen (window coordinates, so it works across tabs). Shown once,
/// and again from Settings.
@MainActor
@Observable
final class TourGuide {
    private(set) var current: TourStep?
    /// Window frames of the views marked with `.tourAnchor(_:)`.
    var frames: [TourStep: CGRect] = [:]
    private(set) var hasSeen: Bool

    @ObservationIgnored private let defaults: UserDefaults
    private static let seenKey = "tour.seen.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasSeen = defaults.bool(forKey: Self.seenKey)
        GlowTips.isTourOver = hasSeen
    }

    var isRunning: Bool { current != nil }

    /// The steps of this run (the AI ones are left out under 13).
    private(set) var steps: [TourStep] = TourStep.allCases

    var stepNumber: Int { (current.flatMap { steps.firstIndex(of: $0) } ?? 0) + 1 }
    var stepCount: Int { steps.count }
    var isLastStep: Bool { current == steps.last }

    func start(steps: [TourStep] = TourStep.allCases) {
        self.steps = steps
        current = steps.first
        GlowTips.isTourOver = false
    }

    func next() {
        guard let current, let index = steps.firstIndex(of: current) else { return }
        if index + 1 < steps.count {
            self.current = steps[index + 1]
        } else {
            finish()
        }
    }

    func finish() {
        current = nil
        hasSeen = true
        defaults.set(true, forKey: Self.seenKey)
        GlowTips.isTourOver = true
    }

    /// "Delete my data": the tour shows again after onboarding.
    func reset() {
        current = nil
        hasSeen = false
        defaults.removeObject(forKey: Self.seenKey)
        GlowTips.isTourOver = false
    }
}

extension View {
    /// Marks this view as the target of a tour step.
    func tourAnchor(_ step: TourStep) -> some View {
        modifier(TourAnchorModifier(step: step))
    }
}

private struct TourAnchorModifier: ViewModifier {
    let step: TourStep
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            app.tour.frames[step] = frame
        }
    }
}

/// Dims the screen, spotlights the current step's target and explains it,
/// with Next / Skip. Tapping the dimmed area moves on too.
struct TourOverlay: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        let tour = app.tour
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            if let step = tour.current {
                let target = tour.frames[step].map { $0.offsetBy(dx: -origin.x, dy: -origin.y) }
                let hole = target.map { spotlight(for: $0, in: proxy.size) } ?? .zero
                ZStack(alignment: .topLeading) {
                    SpotlightShape(hole: hole)
                        .fill(Palette.ink.opacity(0.62), style: FillStyle(eoFill: true))
                        .contentShape(Rectangle())
                        .onTapGesture { advance() }
                        .accessibilityHidden(true)

                    if target != nil {
                        RoundedRectangle.card
                            .strokeBorder(Palette.blush, lineWidth: 2.5)
                            .frame(width: hole.width, height: hole.height)
                            .scaleEffect(pulse ? 1.03 : 1)
                            .opacity(pulse ? 0.55 : 1)
                            .position(x: hole.midX, y: hole.midY)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)

                        placed(card(for: step), around: hole, in: proxy.size)
                            .id(step)
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
                // Reduce Motion: the spotlight moves without sliding across the screen.
                .animation(reduceMotion ? nil : .snappy(duration: 0.35), value: hole)
                .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.3), value: step)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
        }
        .onChange(of: app.tour.current) { _, step in
            if let step, app.selectedTab != step.tab { app.selectedTab = step.tab }
            focusTitle()
        }
        .onAppear(perform: focusTitle)
        .accessibilityAddTraits(.isModal)
    }

    /// VoiceOver starts each step at its title, after the new card is in place.
    private func focusTitle() {
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            titleFocused = true
        }
    }

    private func card(for step: TourStep) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(app.tour.stepNumber) of \(app.tour.stepCount)")
                .eyebrowStyle(Palette.textSecondary)
            Text(styled: step.title(isPro: app.purchases.isPro), size: 22)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused)
            Text(step.message(isPro: app.purchases.isPro, policy: app.credits.policy, cloudAI: app.allowsCloudAI))
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if !app.tour.isLastStep {
                    Button("Skip") { app.tour.finish() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.textSecondary)
                }
                Spacer()
                Button {
                    advance()
                } label: {
                    HStack(spacing: 6) {
                        Text(app.tour.isLastStep ? "Let's glow" : "Next")
                        Image(systemName: app.tour.isLastStep ? "sparkles" : "arrow.right")
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Palette.onAccent)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(Palette.accent, in: .chip)
                }
                .buttonStyle(.pressable)
            }
            .padding(.top, 4)
        }
        .padding(18)
        .background(Palette.surface, in: .card)
        .overlay(RoundedRectangle.card.strokeBorder(Palette.stroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 24, y: 10)
        // The whole card moves on too (Skip and Next keep their own taps).
        .contentShape(.card)
        .onTapGesture { advance() }
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape) { app.tour.finish() }
    }

    private func advance() {
        Haptics.selection()
        app.tour.next()
    }

    /// The target with breathing room, kept on screen.
    private func spotlight(for target: CGRect, in size: CGSize) -> CGRect {
        let padded = target.insetBy(dx: -8, dy: -8)
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 6, dy: 6)
        let clipped = padded.intersection(bounds)
        return clipped.isNull ? padded : clipped
    }

    /// The card goes on whichever side of the spotlight has more room.
    private func placed(_ card: some View, around hole: CGRect, in size: CGSize) -> some View {
        let below = size.height - hole.maxY >= hole.minY
        return VStack(spacing: 0) {
            if below {
                Color.clear.frame(height: max(hole.maxY + 16, 0))
                card
                Spacer(minLength: 24)
            } else {
                Spacer(minLength: 54)
                card
                Color.clear.frame(height: max(size.height - hole.minY + 16, 0))
            }
        }
        .frame(width: min(size.width - 32, 420))
        .frame(width: size.width, height: size.height)
    }
}

/// The dim layer with a rounded hole; the hole animates between steps.
private struct SpotlightShape: Shape {
    var hole: CGRect

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(hole.minX, hole.minY), AnimatablePair(hole.width, hole.height)) }
        set { hole = CGRect(x: newValue.first.first, y: newValue.first.second, width: newValue.second.first, height: newValue.second.second) }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if hole.width > 0, hole.height > 0 {
            path.addRoundedRect(in: hole, cornerSize: CGSize(width: Metrics.cardRadius, height: Metrics.cardRadius), style: .continuous)
        }
        return path
    }
}
