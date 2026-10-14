import SwiftUI
import TipKit
import AppCore

// One-time hints for the newer features (TipKit), shown in the screen itself
// rather than as popovers, so they never fight a sheet for the screen. At
// most one a day and never two at once, never during the first-run tour, and
// Settings › Show me around brings them back.

/// The features with a tip.
enum FeatureTip: String, CaseIterable {
    case retroCam, collage, textStickers, ideas, captions

    var tip: any Tip {
        switch self {
        case .retroCam: return RetroCamTip()
        case .collage: return CollageTip()
        case .textStickers: return TextStickersTip()
        case .ideas: return IdeasTip()
        case .captions: return CaptionsTip()
        }
    }
}

enum GlowTips {
    private static var defaults: UserDefaults { .standard }
    private static let generationKey = "tips.generation"
    private static let erasePendingKey = "tips.erasePending"

    /// App launches: the Retro Cam and collage tips wait for the second.
    static let appLaunched = Tips.Event(id: "app-launched")
    /// Editor visits: ideas and Text & Stickers wait until she has had one.
    static let editorClosed = Tips.Event(id: "editor-closed")
    /// Video editor visits: captions wait for the second.
    static let videoEditorOpened = Tips.Event(id: "video-editor-opened")

    /// The first-run tour has been seen and isn't running; tips wait for it.
    @Parameter(.transient) static var isTourOver: Bool = false

    /// TipKit can only empty its store before it starts, so a reset gives
    /// every tip a new id instead: to TipKit they're new tips.
    static func id(_ name: String) -> String {
        let generation = defaults.integer(forKey: generationKey)
        return generation == 0 ? name : "\(name).\(generation)"
    }

    /// Once at launch, before any view.
    static func configure() {
        #if DEBUG
        if let scene = ScreenshotScene.current {
            configureForScreenshots(scene)
            return
        }
        #endif
        if defaults.bool(forKey: erasePendingKey) {
            try? Tips.resetDatastore()
            defaults.removeObject(forKey: erasePendingKey)
            defaults.removeObject(forKey: generationKey)
        }
        try? Tips.configure([.displayFrequency(.daily)])
        donate(appLaunched)
    }

    /// Settings › Show me around: every tip can show again, after the tour.
    static func reset() {
        defaults.set(defaults.integer(forKey: generationKey) + 1, forKey: generationKey)
    }

    /// Delete my data: the tips start over now, and their store (visit
    /// counts and dates) is emptied at the next launch.
    static func eraseAll() {
        reset()
        defaults.set(true, forKey: erasePendingKey)
    }

    static func noteEditorClosed() { donate(editorClosed) }
    static func noteVideoEditorOpened() { donate(videoEditorOpened) }

    /// She found the feature on her own, so its tip has nothing to add.
    static func noteUsed(_ feature: FeatureTip) {
        feature.tip.invalidate(reason: .actionPerformed)
    }

    /// The rules count to two at most, so a few dates are all that's kept.
    /// Off the main thread: it reads TipKit's store.
    private static func donate(_ event: Tips.Event<Tips.EmptyDonation>) {
        Task.detached(priority: .utility) {
            guard event.donations.count < 3 else { return }
            await event.donate()
        }
    }

    #if DEBUG
    /// Screenshots use a fresh store of their own and show no tips, except
    /// the one `-GLTip <name>` asks for (the tips scene: Retro Cam).
    /// `-GLTipRules YES` instead runs the real rules on a store kept between
    /// launches (QA; add `-tour.seen.v1 YES`), without the daily limit.
    private static func configureForScreenshots(_ scene: ScreenshotScene) {
        if UserDefaults.standard.bool(forKey: "GLTipRules") {
            let store = FileManager.default.temporaryDirectory.appendingPathComponent("tips-rules", isDirectory: true)
            try? FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
            try? Tips.configure([.displayFrequency(.immediate), .datastoreLocation(.url(store))])
            donate(appLaunched)
            return
        }
        let store = FileManager.default.temporaryDirectory.appendingPathComponent("tips-screenshots", isDirectory: true)
        try? FileManager.default.removeItem(at: store)
        try? FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        let name = UserDefaults.standard.string(forKey: "GLTip") ?? (scene == .tips ? FeatureTip.retroCam.rawValue : nil)
        if let feature = name.flatMap(FeatureTip.init(rawValue:)) {
            Tips.showTipsForTesting([type(of: feature.tip)])
        } else {
            Tips.hideAllTipsForTesting()
        }
        try? Tips.configure([.displayFrequency(.immediate), .datastoreLocation(.url(store))])
    }
    #endif
}

// MARK: - Tips

/// Explore: the camera with live effects and the photo booth.
struct RetroCamTip: Tip {
    var id: String { GlowTips.id("retro-cam") }
    var title: Text { Text("Meet Retro Cam") }
    var message: Text? {
        Text("Shoot with live 80s, 90s and Y2K effects, or start a four-shot photo booth. Free, on your device.")
    }
    var image: Image? { Image(systemName: "camera.fill") }
    var actions: [Action] {
        Action(id: "open") { Text("Open Retro Cam") }
    }
    var rules: [Rule] {
        #Rule(GlowTips.$isTourOver) { $0 == true }
        #Rule(GlowTips.appLaunched) { $0.donations.count >= 2 }
    }
    var options: [any TipOption] { MaxDisplayCount(1) }
}

/// The Edit tab: the collage maker.
struct CollageTip: Tip {
    var id: String { GlowTips.id("collage") }
    var title: Text { Text("Make a collage") }
    var message: Text? {
        Text("Turn your photos into a photo dump, a moodboard or a carousel. Free, on your device.")
    }
    var image: Image? { Image(systemName: "rectangle.3.offgrid.fill") }
    var actions: [Action] {
        Action(id: "open") { Text("Try it") }
    }
    var rules: [Rule] {
        #Rule(GlowTips.$isTourOver) { $0 == true }
        #Rule(GlowTips.appLaunched) { $0.donations.count >= 2 }
    }
    var options: [any TipOption] { MaxDisplayCount(1) }
}

/// The Edit tab, once she knows the editor: Text & Stickers.
struct TextStickersTip: Tip {
    var id: String { GlowTips.id("text-stickers") }
    var title: Text { Text("Write on your photos") }
    var message: Text? {
        Text("Add text, stickers and doodles with Text & Stickers. Free, on your device.")
    }
    var image: Image? { Image(systemName: EditorTool.textStickers.symbolName) }
    var actions: [Action] {
        Action(id: "open") { Text("Try it") }
    }
    var rules: [Rule] {
        #Rule(GlowTips.$isTourOver) { $0 == true }
        #Rule(GlowTips.editorClosed) { $0.donations.count >= 1 }
    }
    var options: [any TipOption] { MaxDisplayCount(1) }
}

/// The editor's ideas row, from her second visit.
struct IdeasTip: Tip {
    var id: String { GlowTips.id("editor-ideas") }
    var title: Text { Text("Stuck for ideas?") }
    var message: Text? {
        Platform.isMac
            ? Text("Click Surprise me for a free effect that suits this photo. Click again for another one.")
            : Text("Tap Surprise me for a free effect that suits this photo. Tap again for another one.")
    }
    var image: Image? { Image(systemName: "sparkles") }
    var rules: [Rule] {
        #Rule(GlowTips.$isTourOver) { $0 == true }
        #Rule(GlowTips.editorClosed) { $0.donations.count >= 1 }
    }
    var options: [any TipOption] { MaxDisplayCount(1) }
}

/// The video editor's Captions card, from her second video.
struct CaptionsTip: Tip {
    var id: String { GlowTips.id("video-captions") }
    var title: Text { Platform.isMac ? Text("Captions in one click") : Text("Captions in one tap") }
    var message: Text? {
        Platform.isMac
            ? Text("Click Add captions and the words you say appear on your video. Then fix a word or pick a style in Edit.")
            : Text("Tap Add captions and the words you say appear on your video. Then fix a word or pick a style in Edit.")
    }
    var image: Image? { Image(systemName: "captions.bubble") }
    var rules: [Rule] {
        #Rule(GlowTips.$isTourOver) { $0 == true }
        #Rule(GlowTips.videoEditorOpened) { $0.donations.count >= 2 }
    }
    var options: [any TipOption] { MaxDisplayCount(1) }
}

// MARK: - Showing tips

/// One place per screen where tips appear, at most one at a time.
enum TipSlot: Equatable {
    case explore
    case editHub
    case editorIdeas
    /// `inUse`: she has started captions, so the tip isn't needed.
    case captions(inUse: Bool)

    var features: [FeatureTip] {
        switch self {
        // A Mac without a camera has no Retro Cam.
        case .explore: return RetroCam.isAvailable ? [.retroCam] : []
        case .editHub: return [.collage, .textStickers]
        case .editorIdeas: return [.ideas]
        case .captions: return [.captions]
        }
    }
}

extension View {
    /// The slot's tip next to this view (under it unless `edge` is `.top`).
    /// Without a tip there's nothing, not even spacing.
    func tipSlot(_ slot: TipSlot, edge: VerticalEdge = .bottom, spacing: CGFloat = 12) -> some View {
        modifier(TipSlotModifier(slot: slot, edge: edge, spacing: spacing))
    }
}

private struct TipSlotModifier: ViewModifier {
    let slot: TipSlot
    let edge: VerticalEdge
    let spacing: CGFloat

    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Tips TipKit says may show now (rules, the daily limit, not closed).
    @State private var eligible: Set<FeatureTip> = []

    private var current: FeatureTip? { slot.features.first { eligible.contains($0) } }

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if edge == .top, let current {
                tipView(current)
                    .padding(.bottom, spacing)
            }
            content
            if edge == .bottom, let current {
                tipView(current)
                    .padding(.top, spacing)
            }
        }
        // Reduce Motion: a cross-fade instead of the card growing in.
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.35), value: current)
        .task(id: slot.features) { await watch(slot.features) }
        .onAppear {
            if case .captions = slot { GlowTips.noteVideoEditorOpened() }
        }
        .onChange(of: slot) { _, slot in
            if case .captions(inUse: true) = slot { GlowTips.noteUsed(.captions) }
        }
    }

    private func watch(_ features: [FeatureTip]) async {
        await withTaskGroup(of: Void.self) { group in
            for feature in features {
                group.addTask { @MainActor in
                    for await shows in Self.displayUpdates(of: feature.tip) {
                        if shows { eligible.insert(feature) } else { eligible.remove(feature) }
                    }
                }
            }
        }
    }

    private static func displayUpdates(of tip: some Tip) -> AsyncMapSequence<AsyncStream<Tips.Status>, Bool> {
        tip.shouldDisplayUpdates
    }

    @ViewBuilder
    private func tipView(_ feature: FeatureTip) -> some View {
        switch feature {
        case .retroCam: styled(RetroCamTip(), feature)
        case .collage: styled(CollageTip(), feature)
        case .textStickers: styled(TextStickersTip(), feature)
        case .ideas: styled(IdeasTip(), feature)
        case .captions: styled(CaptionsTip(), feature)
        }
    }

    private func styled(_ tip: some Tip, _ feature: FeatureTip) -> some View {
        TipView(tip)
            .tipViewStyle(GlowTipStyle { perform(feature) })
            // TipView's own animations follow Reduce Motion too.
            .transaction { if reduceMotion { $0.animation = nil } }
            .id(tip.id)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96, anchor: edge == .top ? .bottom : .top)))
    }

    /// A tip's button: straight into the feature.
    private func perform(_ feature: FeatureTip) {
        Haptics.tap()
        switch feature {
        case .retroCam: app.isRetroCamPresented = true
        case .collage: app.isCollagePresented = true
        case .textStickers: app.startEditing(tool: .textStickers)
        case .ideas, .captions: break
        }
    }
}

/// Tips in the app's own look: a card with the feature's symbol, what it
/// does, its button when it has one, and a close button.
private struct GlowTipStyle: TipViewStyle {
    let onAction: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let image = configuration.image {
                image
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 40, height: 40)
                    .background(Palette.blush, in: Circle())
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                configuration.title?
                    .font(.cardTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                configuration.message?
                    .font(.legibleFootnote)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(configuration.actions) { action in
                    Button {
                        onAction()
                        configuration.tip.invalidate(reason: .actionPerformed)
                    } label: {
                        action.label()
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.onAccent)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 36)
                            .background(Palette.accent, in: .chip)
                    }
                    .buttonStyle(.pressable)
                    .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                configuration.tip.invalidate(reason: .tipClosed)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(14)
        .cardStyle()
        .accessibilityElement(children: .contain)
    }
}
