import SwiftUI
import AVFoundation
import AppCore

/// Auto edit in the video editor: one tap turns the clip into a vertical cut
/// for TikTok, Instagram Reels or YouTube Shorts, on the device. It stays an
/// ordinary edit afterwards (trim, effects and captions still work on it),
/// and Undo goes back to the clip as it was.
@MainActor
@Observable
final class VideoAutoEdit {
    /// One Auto edit, which she can still change.
    struct Edit: Equatable {
        var platform: SocialPlatform
        var length: Double
        var look: AdjustVibe?
        /// Source seconds to keep, in order.
        var parts: [ClosedRange<Double>]
        var framing: FramingPath
    }

    /// The work under the progress overlay.
    enum Phase: Equatable {
        case moments(Double)
        case captions
    }

    /// What Undo goes back to.
    struct Original {
        let cutSilences: Bool
        let effect: RetroEffect?
        let showsExtra: Bool
        let trim: ClosedRange<Double>
        let captions: VideoCaptions.Snapshot
    }

    var edit: Edit? { didSet { if edit != oldValue { onChange?() } } }
    var phase: Phase?
    var original: Original?
    /// This clip has used today's free one: changing or redoing it is free.
    var isCounted = false
    /// What the clip looks like, kept for changes of platform, length or look.
    var analysis: AutoEditAnalyzer.Result?
    let post = AutoEditPostText()
    /// Called when the edit changes what plays.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored var task: Task<Void, Never>?

    var isWorking: Bool { phase != nil }
}

extension VideoEditorModel {
    /// The vertical cut for `platform`: finds the best moments and where she
    /// is, makes captions when the clip talks and has none yet, then puts it
    /// on screen. False when cancelled or the clip couldn't be read.
    func makeAutoEdit(for platform: SocialPlatform, length: Double, look: AdjustVibe?) async -> Bool {
        guard !autoEdit.isWorking, !loadFailed, !isAnalyzing, !isExporting, duration > 0 else { return false }
        pausePreview()
        autoEdit.phase = .moments(0)
        defer { autoEdit.phase = nil }
        // How the clip is before this run: Undo goes back to it, and a cancel
        // takes off captions made for it.
        let before = VideoAutoEdit.Original(cutSilences: cutSilences, effect: effect, showsExtra: showsExtra,
                                            trim: trim, captions: captions.snapshot)
        var madeCaptions = false
        do {
            let analysis: AutoEditAnalyzer.Result
            if let cached = autoEdit.analysis {
                analysis = cached
            } else {
                var looked = try await AutoEditAnalyzer.analyze(asset, duration: duration) { [weak self] value in
                    guard let self, case .moments = self.autoEdit.phase else { return }
                    self.autoEdit.phase = .moments(value)
                }
                #if DEBUG
                // `-GLAutoEditFraming fixture`: where the landscape test clip's
                // subject walks (`-GLVideoLandscape YES`), for the Simulator,
                // which can't run Vision's face detection.
                if UserDefaults.standard.string(forKey: "GLAutoEditFraming") == "fixture" {
                    looked.framing = looked.framing.map { FramingSample(time: $0.time, center: 0.5 + 0.3 * sin($0.time * 0.6)) }
                }
                AutoEditTrace.note("\(looked.framing.count) looks, \(looked.framing.filter { $0.center != nil }.count) with her, "
                                   + "\(looked.motion.count) motion samples, source \(looked.sourceSize)")
                #endif
                analysis = looked
                autoEdit.analysis = analysis
            }
            try Task.checkCancellation()
            // Captions she already has (or is making) stay; otherwise they're
            // made on the device now. A clip without speech goes on without.
            if captions.isWorking || (hasSound && captions.cues.isEmpty && captions.status == .idle) {
                autoEdit.phase = .captions
                if !captions.isWorking {
                    captions.make(from: asset, duration: duration)
                    madeCaptions = true
                }
                await captions.finishMaking()
            }
            try Task.checkCancellation()
            if autoEdit.edit == nil {
                // Captions made for the Auto edit come off with Undo; ones she
                // was already making herself stay.
                autoEdit.original = VideoAutoEdit.Original(cutSilences: before.cutSilences, effect: before.effect,
                                                           showsExtra: before.showsExtra, trim: before.trim,
                                                           captions: madeCaptions ? before.captions : captions.snapshot)
            }
            captions.style = platform.captionStyle
            captions.position = .bottom
            if !captions.cues.isEmpty { captions.isOn = true }
            autoEdit.edit = plannedEdit(platform: platform, length: length, look: look, analysis: analysis)
            #if DEBUG
            AutoEditTrace.note("\(platform.rawValue) \(Int(length)) s: "
                               + keptRanges.map { String(format: "%.2f–%.2f", $0.lowerBound, $0.upperBound) }.joined(separator: ", ")
                               + ", crossfades at " + AutoEditTimeline.transitions(keeping: keptRanges, sourceDuration: duration)
                                   .map { String(format: "%.2f", $0.cut) }.joined(separator: ", "))
            #endif
            return true
        } catch {
            if madeCaptions { captions.restore(before.captions) }
            return false
        }
    }

    /// The parts and framing for these choices, within her trim.
    private func plannedEdit(platform: SocialPlatform, length: Double, look: AdjustVibe?,
                             analysis: AutoEditAnalyzer.Result) -> VideoAutoEdit.Edit {
        let input = AutoEditPlanner.Input(duration: duration, levels: levels, window: VideoEngine.levelWindow,
                                          motion: analysis.motion, presence: analysis.presence, bounds: trim)
        let parts = AutoEditPlanner.plan(input, target: length)
        let window = AutoFraming.window(sourceWidth: analysis.sourceSize.width, sourceHeight: analysis.sourceSize.height)
        let framing = AutoFraming.path(analysis.framing, duration: duration, windowWidth: window.width)
        return VideoAutoEdit.Edit(platform: platform, length: length, look: look, parts: parts.isEmpty ? [trim] : parts, framing: framing)
    }

    /// Another platform: its caption style, and a length it takes.
    func changeAutoEdit(platform: SocialPlatform) {
        guard let edit = autoEdit.edit, let analysis = autoEdit.analysis, platform != edit.platform else { return }
        let length = platform.lengths.contains(edit.length)
            ? edit.length : platform.lengths.last { $0 <= edit.length } ?? SocialPlatform.defaultLength
        captions.style = platform.captionStyle
        autoEdit.edit = plannedEdit(platform: platform, length: length, look: edit.look, analysis: analysis)
    }

    func changeAutoEdit(length: Double) {
        guard let edit = autoEdit.edit, let analysis = autoEdit.analysis, length != edit.length else { return }
        autoEdit.edit = plannedEdit(platform: edit.platform, length: length, look: edit.look, analysis: analysis)
    }

    func changeAutoEdit(look: AdjustVibe?) {
        guard autoEdit.edit != nil, autoEdit.edit?.look != look else { return }
        autoEdit.edit?.look = look
    }

    /// Back to the clip as it was before Auto edit, with her own edits.
    func undoAutoEdit() {
        guard autoEdit.edit != nil, let original = autoEdit.original else { return }
        autoEdit.original = nil
        effect = original.effect
        showsExtra = original.showsExtra
        cutSilences = original.cutSilences
        trim = original.trim
        captions.restore(original.captions)
        autoEdit.edit = nil
    }

    func cancelAutoEdit() {
        if autoEdit.phase == .captions { captions.cancel() }
        autoEdit.task?.cancel()
    }

    /// What's said in the edited video, for the caption writer: its captions,
    /// and nothing while they're off.
    var autoEditTranscript: String {
        guard captions.isOn else { return "" }
        return captions.transcript(keeping: keptRanges)
    }
}

/// The free one a day, counted on this device (`AutoEditAllowance`).
@MainActor
enum AutoEditQuota {
    /// Delete my data removes it (`AppModel.Keys.wiped`).
    nonisolated static let key = "autoEdit.allowance"

    #if DEBUG
    /// Screenshot scenes never spend or remember the real one;
    /// `-GLAutoEditUsed YES` shows today's as used.
    private static var scratch: AutoEditAllowance?
    #endif

    private static var allowance: AutoEditAllowance {
        get {
            #if DEBUG
            if ScreenshotScene.current != nil {
                if let scratch { return scratch }
                var made = AutoEditAllowance()
                if UserDefaults.standard.bool(forKey: "GLAutoEditUsed") { made.recordUse(at: .now) }
                return made
            }
            #endif
            guard let data = UserDefaults.standard.data(forKey: key),
                  let stored = try? JSONDecoder().decode(AutoEditAllowance.self, from: data) else { return AutoEditAllowance() }
            return stored
        }
        set {
            #if DEBUG
            if ScreenshotScene.current != nil {
                scratch = newValue
                return
            }
            #endif
            if let data = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(data, forKey: key) }
        }
    }

    static var remainingToday: Int { allowance.remaining(at: .now) }

    /// When the next free one is ready (the paywall's line).
    static var nextFree: Date { allowance.nextFree(after: .now) }

    static func allows(isPro: Bool) -> Bool { allowance.allows(at: .now, isPro: isPro) }

    static func recordUse() {
        var updated = allowance
        updated.recordUse(at: .now)
        allowance = updated
    }
}

/// The words to post an Auto edit with: caption ideas from Apple's
/// on-device writer or the hand-written list, and, only when she taps "More
/// ideas from Aybik", the server's writing help (Claude hears the video's
/// captions while they're on, up to 400 characters); their hashtags and, for
/// Shorts, a title.
@MainActor
@Observable
final class AutoEditPostText {
    /// Without the hashtags they end with; those are in `hashtags`.
    private(set) var captions: [String] = []
    private(set) var hashtags: [String] = []
    private(set) var title: String?
    private(set) var writer: WrittenBy?
    /// Claude's ideas on screen came from what she says in the video.
    private(set) var heardCaptions = false
    private(set) var isLoading = false
    private(set) var loadingWriter: WrittenBy?
    @ObservationIgnored private var loaded: SocialPlatform?

    /// On the device only: hand-written ideas at once, the on-device
    /// writer's when it answers. Nothing leaves the device.
    func load(platform: SocialPlatform, app: AppModel, fresh: Bool = false) async {
        guard !isLoading, fresh || platform != loaded else { return }
        loaded = platform
        let pool = CuratedIdeas.for(.caption(look: nil, madeWithAI: false))
        let unseen = pool.filter { !captions.contains($0) }
        show(Array((unseen.count >= 3 ? unseen : pool).shuffled().prefix(3)), platform: platform, app: app, writer: nil)
        guard app.writer.isAvailable else { return }
        isLoading = true
        defer { isLoading = false }
        await writeOnDevice(platform: platform, app: app)
    }

    /// Her tap on "More ideas from Aybik": the server's writing help hears
    /// `transcript` (empty while captions are off: then a plain line) and the
    /// platform. When it's off or fails, the on-device writer answers quietly.
    func askClaude(platform: SocialPlatform, transcript: String, app: AppModel) async {
        guard !isLoading else { return }
        loaded = platform
        isLoading = true
        defer { isLoading = false }
        loadingWriter = .cloud
        let lines = await app.cloudVideoCaptions(transcript: transcript, platform: platform)
        if !lines.isEmpty {
            show(lines, platform: platform, app: app, writer: .cloud)
            heardCaptions = Assist.sendsVideoWords(transcript: transcript)
            return
        }
        guard app.writer.isAvailable else { return }
        await writeOnDevice(platform: platform, app: app)
    }

    private func writeOnDevice(platform: SocialPlatform, app: AppModel) async {
        loadingWriter = .device
        let lines = await app.writer.ideas(.caption(look: nil, madeWithAI: false))
        if !lines.isEmpty { show(lines, platform: platform, app: app, writer: .device) }
    }

    private func show(_ lines: [String], platform: SocialPlatform, app: AppModel, writer: WrittenBy?) {
        captions = lines.map { PostText.split($0).text }.filter { !$0.isEmpty }
        hashtags = PostText.hashtags(in: lines, adding: app.config.shareHashtags)
        title = platform.hasTitle ? lines.first.map(PostText.title(from:)) : nil
        self.writer = writer
        heardCaptions = false
    }

    /// A caption with its hashtags, ready to paste.
    func clipboard(for caption: String) -> String {
        PostText.clipboard(caption: caption, hashtags: hashtags)
    }
}

extension AppModel {
    /// Caption ideas for an Auto edit from the server's writing help, only
    /// after she asked: Claude hears what she says in it while captions are
    /// on (`Assist.videoCaptionHint`) and the platform. None when writing help
    /// is off or fails, and never under 13 (`usesCloudWriter`).
    func cloudVideoCaptions(transcript: String, platform: SocialPlatform) async -> [String] {
        guard usesCloudWriter, let cloudWriter else { return [] }
        let request = AssistRequest(task: .captions, text: Assist.videoCaptionHint(transcript: transcript),
                                    locale: Assist.languageCode(for: Bundle.main.preferredLocalizations.first ?? "en"),
                                    context: AssistContext(format: platform.assistFormat))
        guard let lines = try? await cloudWriter.suggestions(for: request) else { return [] }
        return Assist.screened(lines, for: AssistTask.captions.screeningOperation)
    }
}

extension SocialPlatform {
    /// The platform's own name, the same in every language.
    var name: String {
        switch self {
        case .tiktok: return "TikTok"
        case .reels: return "Instagram Reels"
        case .shorts: return "YouTube Shorts"
        }
    }

    /// On a button.
    var shortName: String {
        switch self {
        case .tiktok: return "TikTok"
        case .reels: return "Reels"
        case .shorts: return "Shorts"
        }
    }

    /// The caption style that suits it: TikTok's word-by-word highlight, a
    /// soft pill for Reels, bold outlined words for Shorts.
    var captionStyle: CaptionStyle {
        switch self {
        case .tiktok: return .karaoke
        case .reels: return .bubble
        case .shorts: return .pop
        }
    }
}
