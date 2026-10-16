import SwiftUI
import AVFoundation
import AppCore

/// A picked video waiting for the editor.
struct VideoSource: Identifiable {
    let id = UUID()
    let url: URL
}

@MainActor
@Observable
final class VideoEditorModel {
    /// Save writes the video to Photos; Share hands the file to the share sheet.
    enum ExportAction { case save, share }

    let asset: AVURLAsset
    private(set) var duration: Double = 0
    /// The clip is longer than `VideoEngine.maxDuration`, so only its start is used.
    private(set) var isCutToLimit = false
    /// AVFoundation couldn't read the clip (no video track, or a broken file).
    private(set) var loadFailed = false
    private(set) var thumbnail: UIImage?
    private(set) var effectThumbnails: [RetroEffect: UIImage] = [:]
    private(set) var silencePlan: SilenceCutter.Plan?
    private(set) var isAnalyzing = true
    private(set) var isExporting = false
    private(set) var exportProgress: Double = 0
    /// Set when leaving the app stopped an export, so it can start again on return.
    private(set) var interruptedAction: ExportAction?
    private(set) var resultDuration: Double = 0
    @ObservationIgnored private var frameRate: Double = 30
    /// Loudness per `VideoEngine.levelWindow`, for Auto edit.
    @ObservationIgnored private(set) var levels: [Double] = []

    var cutSilences = false { didSet { scheduleRebuild() } }
    var effect: RetroEffect? {
        didSet {
            // Each effect starts with its own switch at its default, so turning
            // off one effect's date stamp doesn't turn off another's letterbox.
            if effect != oldValue { showsExtra = effect?.option?.isOnByDefault ?? true }
            scheduleRebuild()
        }
    }
    /// The effect's switch (date stamp, letterbox or camera info).
    var showsExtra = true { didSet { if showsExtra != oldValue { scheduleRebuild() } } }
    var trim: ClosedRange<Double> = 0...1

    let player = AVPlayer()
    private(set) var isPlaying = false
    /// Automatic captions; their changes redraw the preview in place.
    let captions = VideoCaptions()
    /// The vertical Auto edit, when she made one.
    let autoEdit = VideoAutoEdit()
    @ObservationIgnored private var rebuildTask: Task<Void, Never>?
    @ObservationIgnored private var captionsTask: Task<Void, Never>?
    @ObservationIgnored private var currentComposition: AVMutableComposition?
    /// The Auto edit build playing, so a caption change only redraws it.
    @ObservationIgnored private var currentAutoBuild: AutoEditBuild?
    /// A seek still on its way, which a caption redraw mustn't undo.
    @ObservationIgnored private var seekTarget: CMTime?
    @ObservationIgnored private var loopObserver: NSObjectProtocol?

    @ObservationIgnored private var exportTask: Task<URL, Error>?
    @ObservationIgnored private var cancelledByUser = false
    @ObservationIgnored private var leftAppDuringExport = false
    /// Restarts in a row, so an export that keeps getting stopped can't loop.
    @ObservationIgnored private var restarts = 0
    /// The edits last saved or shared: closing after that needs no warning.
    private var savedEdits: Edits?

    private struct Edits: Equatable {
        let cutSilences: Bool
        let effect: RetroEffect?
        let showsExtra: Bool
        let trim: ClosedRange<Double>
        let captions: VideoCaptions.Snapshot
        let autoEdit: VideoAutoEdit.Edit?
    }

    private var edits: Edits {
        Edits(cutSilences: cutSilences, effect: effect, showsExtra: showsExtra, trim: trim, captions: captions.snapshot,
              autoEdit: autoEdit.edit)
    }

    init(url: URL) {
        asset = AVURLAsset(url: url)
        player.isMuted = false
        player.actionAtItemEnd = .none
        captions.onChange = { [weak self] in self?.captionsChanged() }
        autoEdit.onChange = { [weak self] in self?.scheduleRebuild() }
    }

    var hasSound: Bool { silencePlan != nil }

    /// Changes she'd lose by closing: anything but the untouched clip, unless
    /// exactly this version was already saved or shared.
    var hasUnsavedEdits: Bool {
        let edited = cutSilences || effect != nil || trim != 0...max(duration, 0.1) || captions.shows || autoEdit.edit != nil
        return edited && edits != savedEdits
    }

    /// Where the preview is on the edited timeline, in seconds.
    var playheadSeconds: Double {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? max(0, seconds) : 0
    }

    /// Shows the frame at `seconds` on the edited timeline, paused.
    func seek(to seconds: Double) {
        player.pause()
        isPlaying = false
        let target = CMTime(seconds: seconds, preferredTimescale: 600)
        seekTarget = target
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in if self?.seekTarget == target { self?.seekTarget = nil } }
        }
    }

    func load() async {
        let full = (try? await VideoEngine.duration(of: asset)) ?? 0
        guard full.isFinite, full > 0 else { return failLoading() }
        isCutToLimit = full > VideoEngine.maxDuration + 0.5
        duration = min(full, VideoEngine.maxDuration)
        trim = 0...max(duration, 0.1)
        thumbnail = await VideoEngine.thumbnail(of: asset)
        frameRate = await VideoEngine.frameRate(of: asset)
        if let thumbnail {
            let small = ImageUtilities.normalized(thumbnail, maxLongEdge: 240)
            effectThumbnails = await Task.detached(priority: .userInitiated) {
                Dictionary(uniqueKeysWithValues: RetroEffect.videoEffects.map { ($0, $0.apply(to: small, options: .plain)) })
            }.value
        }
        guard await rebuild() else { return failLoading() }
        let levels = (try? await VideoEngine.loudness(of: asset)) ?? []
        self.levels = levels
        silencePlan = levels.isEmpty ? nil : SilenceCutter.plan(levels: levels, window: VideoEngine.levelWindow)
        isAnalyzing = false
        if cutSilences { await rebuild() }
    }

    private func failLoading() {
        loadFailed = true
        isAnalyzing = false
    }

    func trimChanged() {
        scheduleRebuild(delay: .milliseconds(250))
    }

    /// The parts of the clip that make it into the video: Auto edit's, or
    /// the clip without its silences when she cut them, inside her trim.
    var keptRanges: [ClosedRange<Double>] {
        let base = autoEdit.edit?.parts ?? (cutSilences ? (silencePlan?.keep ?? [0...duration]) : [0...duration])
        return base.compactMap { range in
            let lower = max(range.lowerBound, trim.lowerBound)
            let upper = min(range.upperBound, trim.upperBound)
            return upper - lower > 0.05 ? lower...upper : nil
        }
    }

    private func scheduleRebuild(delay: Duration = .zero) {
        rebuildTask?.cancel()
        rebuildTask = Task {
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            await rebuild()
        }
    }

    /// False when the clip can't be turned into a playable composition.
    @discardableResult
    private func rebuild() async -> Bool {
        let ranges = keptRanges
        guard !ranges.isEmpty, let output = try? await output(keeping: ranges) else { return false }
        guard !Task.isCancelled else { return true }
        resultDuration = ranges.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) }
        let item = AVPlayerItem(asset: output.composition)
        item.videoComposition = output.videoComposition
        item.audioMix = output.audioMix
        currentComposition = output.composition
        currentAutoBuild = output.autoBuild
        player.replaceCurrentItem(with: item)
        if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
        loopObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.player.seek(to: .zero)
                self?.player.play()
            }
        }
        // Exports render on the same GPU; the preview waits.
        if !isExporting {
            player.play()
            isPlaying = true
        }
        return true
    }

    /// What plays and what's saved: the stitched clip, how its frames are
    /// drawn, and its sound.
    private struct Output {
        let composition: AVMutableComposition
        let videoComposition: AVVideoComposition?
        let audioMix: AVAudioMix?
        let autoBuild: AutoEditBuild?
    }

    /// The plain edit in the clip's own shape, or the vertical Auto edit.
    private func output(keeping ranges: [ClosedRange<Double>]) async throws -> Output {
        let edit = autoEdit.edit, effect = effect, showsExtra = showsExtra, fps = frameRate, asset = asset
        let captionTrack = captionTrack(for: ranges)
        if let edit {
            let build = try await AutoEditRenderer.build(asset, keeping: ranges)
            let styler = FrameStyler(effect: effect, showsExtra: showsExtra, fps: fps, look: edit.look, captions: captionTrack)
            return Output(composition: build.composition,
                          videoComposition: AutoEditRenderer.videoComposition(for: build, framing: edit.framing, styler: styler),
                          audioMix: build.audioMix, autoBuild: build)
        }
        let composition = try await VideoEngine.composition(of: asset, keeping: ranges)
        let videoComposition = try await VideoEngine.videoComposition(for: composition, effect: effect, showsExtra: showsExtra, fps: fps,
                                                                      captions: captionTrack)
        return Output(composition: composition, videoComposition: videoComposition, audioMix: nil, autoBuild: nil)
    }

    /// Captions drawn above the effect's own date stamp, display or bars,
    /// and clear of an Auto edit platform's buttons.
    private func captionTrack(for ranges: [ClosedRange<Double>]) -> CaptionTrack? {
        captions.track(keeping: ranges, overlay: showsExtra && effect?.option?.worksOnVideo == true ? effect : nil,
                       safeArea: autoEdit.edit?.platform.safeArea)
    }

    /// Captions changed: the playing item gets a new video composition, so
    /// the preview keeps its place instead of starting over.
    private func captionsChanged() {
        captionsTask?.cancel()
        captionsTask = Task {
            // Typing in a caption settles before the redraw.
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let composition = currentComposition, let item = player.currentItem else { return }
            // Auto edit just started or was undone: the rebuild on its way draws the captions.
            guard (currentAutoBuild != nil) == (autoEdit.edit != nil) else { return }
            let videoComposition: AVVideoComposition?
            if let build = currentAutoBuild, let edit = autoEdit.edit {
                let styler = FrameStyler(effect: effect, showsExtra: showsExtra, fps: frameRate, look: edit.look,
                                         captions: captionTrack(for: keptRanges))
                videoComposition = AutoEditRenderer.videoComposition(for: build, framing: edit.framing, styler: styler)
            } else {
                videoComposition = try? await VideoEngine.videoComposition(for: composition, effect: effect, showsExtra: showsExtra,
                                                                           fps: frameRate, captions: captionTrack(for: keptRanges))
            }
            guard !Task.isCancelled, item === player.currentItem else { return }
            item.videoComposition = videoComposition
            // A paused frame redraws only when asked.
            if !isPlaying { await player.seek(to: seekTarget ?? player.currentTime(), toleranceBefore: .zero, toleranceAfter: .zero) }
        }
    }

    /// Stops the preview for work that needs the GPU (Auto edit's look at the clip).
    func pausePreview() {
        player.pause()
        isPlaying = false
    }

    func togglePlayback() {
        seekTarget = nil
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
        Haptics.tap()
    }

    /// Renders the final video and, for Save, writes it to Photos. Returns the
    /// file for Share, and for an Auto edit's Save too (its post sheet can
    /// share it). Throws `CancellationError` when she cancels, and also
    /// when leaving the app stopped the export: then `interruptedAction` is
    /// set and the view starts it again once she's back.
    func run(_ action: ExportAction, isRestart: Bool = false) async throws -> URL? {
        guard !isExporting, !loadFailed else { return nil }
        isExporting = true
        exportProgress = 0
        interruptedAction = nil
        cancelledByUser = false
        leftAppDuringExport = false
        if !isRestart { restarts = 0 }
        player.pause()
        isPlaying = false
        let edits = self.edits
        // Keeps the app running for the Photos write and an export that's
        // nearly done. When the time runs out, stop cleanly instead of being
        // killed; the export starts again on return.
        let background = BackgroundTime(name: "glowlit.video-export") { [weak self] in
            self?.leftAppDuringExport = true
            self?.exportTask?.cancel()
        }
        defer {
            background.end()
            exportTask = nil
            isExporting = false
        }
        do {
            // Ask before the export, so a long render isn't wasted on a "no".
            if action == .save { try await VideoEngine.requestPhotosAccess() }
            let ranges = keptRanges
            let keepsFile = autoEdit.edit != nil
            let task = Task<URL, Error> {
                let output = try await self.output(keeping: ranges)
                try Task.checkCancellation()
                return try await VideoEngine.export(output.composition, videoComposition: output.videoComposition,
                                                    audioMix: output.audioMix) { [weak self] value in
                    self?.exportProgress = value
                }
            }
            exportTask = task
            if cancelledByUser { task.cancel() }
            let url = try await task.value
            if action == .save {
                do {
                    try await VideoEngine.saveToPhotos(url)
                } catch {
                    try? FileManager.default.removeItem(at: url)
                    throw error
                }
                if !keepsFile { try? FileManager.default.removeItem(at: url) }
            }
            savedEdits = edits
            restarts = 0
            return action == .share || keepsFile ? url : nil
        } catch {
            // The Mac keeps rendering in the background, so a failure there is real.
            let stoppedByLeaving = !Platform.isMac && (leftAppDuringExport || VideoEngine.isInterruption(error)
                || UIApplication.shared.applicationState != .active)
            if !cancelledByUser, stoppedByLeaving, restarts < 3 {
                restarts += 1
                interruptedAction = action
                throw CancellationError()
            }
            throw error
        }
    }

    func cancelExport() {
        cancelledByUser = true
        interruptedAction = nil
        exportTask?.cancel()
    }

    /// The app went to the background while exporting: iOS stops the GPU work.
    func noteLeftApp() {
        if isExporting { leftAppDuringExport = true }
    }

    func stop() {
        player.pause()
        isPlaying = false
        autoEdit.task?.cancel()
        captions.cancel()
        if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
    }
}

/// A UIKit background-task assertion that ends exactly once.
@MainActor
private final class BackgroundTime {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    init(name: String, onExpiry: @escaping @MainActor () -> Void) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            // UIKit calls this on the main thread.
            MainActor.assumeIsolated {
                onExpiry()
                self?.end()
            }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}

/// Simple video editing, free and on the device: auto-cut silences, retro
/// effects, trim, captions and Auto edit's vertical cut, then save or share.
/// No watermark, no ending clip.
struct VideoEditorView: View {
    let source: VideoSource

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: VideoEditorModel
    @State private var shareItems: ActivityItems?
    /// The exported file on the share sheet, deleted when the sheet closes.
    @State private var sharedFile: URL?
    @State private var showDiscardAlert = false
    @State private var showsAutoEditOptions = false
    /// Auto edit's export sheet: the words to post it with, then Share.
    @State private var postRequest: AutoEditPostSheet.Request?
    /// Share video in that sheet: the share sheet opens once it's closed.
    @State private var sharesAfterPost = false
    /// The exported Auto edit the sheet can share, deleted when it's done with.
    @State private var postFile: URL?

    init(source: VideoSource) {
        self.source = source
        _model = State(initialValue: VideoEditorModel(url: source.url))
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.loadFailed {
                    loadError
                } else {
                    editor
                }
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        requestClose()
                    } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Close")
                    .macHelp("Close")
                    .macKeyboardShortcut(.cancelAction)
                }
                if !model.loadFailed {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button { Task { await perform(.share) } } label: { Image(systemName: "paperplane.fill") }
                            .accessibilityLabel("Share")
                            .macHelp("Share")
                        Button("Save") { Task { await perform(.save) } }
                            .fontWeight(.bold)
                    }
                }
            }
        }
        .tint(Palette.accent)
        .overlay {
            if model.isExporting {
                // On-device work: no AI tips, but real progress and a way out.
                GeneratingOverlay(title: String(localized: "Saving your video…"), progress: model.exportProgress,
                                  showsTips: false, onCancel: { model.cancelExport() })
                    .transition(.opacity)
            } else if let phase = model.autoEdit.phase {
                GeneratingOverlay(title: autoEditTitle(phase), progress: autoEditProgress(phase),
                                  showsTips: false, onCancel: { model.cancelAutoEdit() })
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.isExporting)
        .animation(.easeInOut(duration: 0.25), value: model.autoEdit.isWorking)
        .sheet(isPresented: $showsAutoEditOptions) {
            AutoEditOptionsSheet(model: model)
                .macSheet(.form)
        }
        .sheet(item: $postRequest, onDismiss: finishPost) { request in
            AutoEditPostSheet(request: request, post: model.autoEdit.post, transcript: model.autoEditTranscript) {
                sharesAfterPost = true
            }
            .environment(app)
            .macSheet(.form)
        }
        .alert("Discard your edits?", isPresented: $showDiscardAlert) {
            Button("Discard", role: .destructive) { close() }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("Save to Photos first if you want to keep them.")
        }
        .task {
            await model.load()
            #if DEBUG
            await applyScreenshotOptions()
            #endif
        }
        // File › Save (⌘S) and File › Close (⌘W) on the Mac use this editor's
        // own save and discard prompt.
        .onAppear {
            app.saveActiveCover = { Task { await perform(.save) } }
            app.closeActiveCover = { requestClose() }
        }
        .onDisappear {
            model.stop()
            app.saveActiveCover = nil
            app.closeActiveCover = nil
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.noteLeftApp() }
            if phase == .active { restartInterruptedExport() }
        }
        .shareSheet(item: $shareItems) {
            if let sharedFile { try? FileManager.default.removeItem(at: sharedFile) }
            sharedFile = nil
        }
        // Toasts and the Photos-access alert: the root's copy is covered.
        .modifier(AppPresentations(isActive: true))
    }

    private var editor: some View {
        VStack(spacing: 14) {
            // The player takes whatever height is left, at 9:16.
            GeometryReader { proxy in
                let height = min(proxy.size.height, proxy.size.width * 16 / 9)
                playerCard
                    .frame(width: height * 9 / 16, height: height)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
            controls
                .readableWidth(Metrics.compactWidth, alignment: .center)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.bottom, 8)
    }

    private var loadError: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .accessibilityHidden(true)
            Text("Couldn't open that video. Try another one.")
                .font(.headline)
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.center)
            Button("Choose another video") { chooseAnotherVideo() }
                .buttonStyle(.primary)
                .frame(maxWidth: 260)
                .padding(.top, 8)
        }
        .padding(Metrics.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var playerCard: some View {
        Button { model.togglePlayback() } label: {
            PlayerView(player: model.player)
                .clipShape(.control)
                // Top center: the corners belong to Camcorder '06's REC, SP,
                // battery, date and timecode.
                .overlay(alignment: .top) {
                    if model.resultDuration > 0 {
                        Text(timeLabel)
                            .font(.legibleCaption.weight(.bold).monospacedDigit())
                            .foregroundStyle(Palette.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .liquidGlass(in: .chip)
                            .padding(10)
                    }
                }
                .overlay {
                    if !model.isPlaying {
                        Image(systemName: "play.fill")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(Palette.ink)
                            .frame(width: 72, height: 72)
                            .liquidGlass(in: Circle())
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .shadow(color: Palette.shadow, radius: 16, y: 8)
        // A real button, so VoiceOver, Voice Control ("Tap Play") and Switch
        // Control can reach it; Space plays and pauses on the Mac.
        .accessibilityLabel(model.isPlaying ? Text("Pause") : Text("Play"))
        .accessibilityValue(model.resultDuration > 0 ? timeLabel : "")
        .accessibilityAddTraits(.startsMediaSession)
        .macKeyboardShortcut(KeyboardShortcut(.space, modifiers: []))
    }

    private var timeLabel: String {
        let original = model.trim.upperBound - model.trim.lowerBound
        if model.resultDuration < original - 0.05 {
            return "\(format(original)) → \(format(model.resultDuration))"
        }
        return format(model.resultDuration)
    }

    private func format(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var controls: some View {
        @Bindable var model = model
        return VStack(spacing: 14) {
            if model.isCutToLimit {
                // The trim handles stay inside the first 5:00, so say only that.
                Label("This video is longer than 5 minutes, so we'll use the first 5:00.", systemImage: "info.circle")
                    .font(.legibleCaption)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            AutoEditCard(model: model, freeLeft: autoEditFreeLeft, canUpgrade: app.allowsPurchases,
                         start: { platform in startAutoEdit(platform) },
                         showOptions: { showsAutoEditOptions = true },
                         showPost: { showPost(saved: false, file: nil) })
            // Auto edit takes out the silences itself.
            if model.autoEdit.edit == nil {
                silenceCard
            }
            CaptionsCard(model: model)
                .tipSlot(.captions(inUse: model.captions.status != .idle), edge: .top)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    EffectChoice(title: "None", image: model.thumbnail, isSelected: model.effect == nil) {
                        model.effect = nil
                    }
                    ForEach(RetroEffect.videoEffects) { effect in
                        EffectChoice(title: LocalizedStringKey(effect.title), image: model.effectThumbnails[effect], isSelected: model.effect == effect) {
                            Haptics.selection()
                            model.effect = effect
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .fixedSize(horizontal: false, vertical: true)

            if let option = model.effect?.option, option.worksOnVideo {
                Toggle(isOn: $model.showsExtra) {
                    Label { Text(option.label) } icon: { Image(systemName: option.symbolName) }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.textPrimary)
                }
                .tint(Palette.accent)
                .transition(.opacity)
            }

            if model.duration > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Trim", systemImage: "scissors")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.textPrimary)
                    TrimSlider(range: $model.trim, bounds: 0...model.duration) {
                        model.trimChanged()
                    }
                }
            }
        }
    }

    private var silenceCard: some View {
        @Bindable var model = model
        return Toggle(isOn: $model.cutSilences) {
            VStack(alignment: .leading, spacing: 2) {
                Label("Auto-cut silences", systemImage: "waveform.badge.minus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                Group {
                    if model.isAnalyzing {
                        Text("Listening for quiet parts…")
                    } else if let plan = model.silencePlan, plan.cutsSomething {
                        Text("Removes \(String(format: "%.1f", plan.removedSeconds)) s of silence, like a jump cut")
                    } else if model.hasSound {
                        Text("No long silences in this video")
                    } else {
                        Text("This video has no sound")
                    }
                }
                .font(.legibleCaption)
                .foregroundStyle(Palette.textSecondary)
            }
            // Wraps instead of cutting long titles ("Cortar silencios automáticamente").
            .fixedSize(horizontal: false, vertical: true)
        }
        .tint(Palette.accent)
        .disabled(model.isAnalyzing || !(model.silencePlan?.cutsSomething ?? false))
        .padding(14)
        .cardStyle()
    }

    // MARK: Actions

    private func perform(_ action: VideoEditorModel.ExportAction, isRestart: Bool = false) async {
        do {
            let url = try await model.run(action, isRestart: isRestart)
            switch action {
            case .save:
                Haptics.success()
                // An Auto edit's export sheet says it's saved, with the words to post it with.
                if model.autoEdit.edit != nil, let url {
                    showPost(saved: true, file: url)
                } else {
                    app.showToast("Video saved to Photos ✨", style: .success)
                }
            case .share:
                guard let url else { return }
                if model.autoEdit.edit != nil {
                    showPost(saved: false, file: url)
                } else {
                    sharedFile = url
                    shareItems = ActivityItems(items: [url])
                }
            }
            // An ad, a rating request or the invite card may follow once the
            // video editor closes.
            app.noteFinishedExport()
        } catch {
            // Cancelled or stopped by leaving the app: no error, no setback.
            // No Photos access: offer Settings, or sharing the video instead.
            app.handleSaveError(error, onShareInstead: action == .save ? { Task { await perform(.share) } } : nil)
            // Already back by the time the stop surfaced.
            restartInterruptedExport()
        }
    }

    /// iOS stops GPU work in the background, so an export cut short by leaving
    /// the app starts over from 0% once she's back.
    private func restartInterruptedExport() {
        guard scenePhase == .active, let action = model.interruptedAction, !model.isExporting else { return }
        Task { await perform(action, isRestart: true) }
    }

    /// Esc and File › Close (⌘W) on the Mac: cancels an export under the
    /// overlay, asks before discarding edits, or closes.
    private func requestClose() {
        if model.isExporting {
            model.cancelExport()
        } else if model.autoEdit.isWorking {
            model.cancelAutoEdit()
        } else if model.hasUnsavedEdits {
            showDiscardAlert = true
        } else {
            close()
        }
    }

    private func close() {
        model.stop()
        try? FileManager.default.removeItem(at: source.url)
        dismiss()
    }

    private func chooseAnotherVideo() {
        close()
        // The picker opens once the editor has finished closing.
        Task { @MainActor [app] in
            try? await Task.sleep(for: .milliseconds(600))
            app.isVideoPickerPresented = true
        }
    }

    // MARK: Auto edit

    /// Free ones left today, for the card; nil with Pro or once this clip is counted.
    private var autoEditFreeLeft: Int? {
        app.purchases.isPro || model.autoEdit.isCounted ? nil : AutoEditQuota.remainingToday
    }

    /// One tap: Pro, a free one left today, or this clip already counted;
    /// otherwise the paywall says why (or, under 13, when the next one comes).
    private func startAutoEdit(_ platform: SocialPlatform, length: Double? = nil, look: AdjustVibe? = nil) {
        guard !model.autoEdit.isWorking else { return }
        let isPro = app.purchases.isPro
        guard model.autoEdit.isCounted || AutoEditQuota.allows(isPro: isPro) else {
            Haptics.tap()
            if app.allowsPurchases {
                app.presentPaywall(source: "auto_edit")
            } else {
                app.showToast("Your next free auto edit is ready tomorrow.", style: .info)
            }
            return
        }
        Haptics.tap()
        model.autoEdit.task = Task {
            let made = await model.makeAutoEdit(for: platform, length: length ?? model.autoEdit.edit?.length ?? SocialPlatform.defaultLength,
                                                look: look ?? model.autoEdit.edit?.look)
            guard made else { return }
            if !model.autoEdit.isCounted {
                if !isPro { AutoEditQuota.recordUse() }
                model.autoEdit.isCounted = true
            }
            Haptics.success()
        }
    }

    private func autoEditTitle(_ phase: VideoAutoEdit.Phase) -> String {
        switch phase {
        case .moments: return String(localized: "Finding the best moments…")
        case .captions: return String(localized: "Adding captions…")
        }
    }

    private func autoEditProgress(_ phase: VideoAutoEdit.Phase) -> Double? {
        switch phase {
        case .moments(let value): return value
        case .captions:
            if case .working(.listening(let value)) = model.captions.status { return value }
            if case .working(.downloading(let value)) = model.captions.status { return value }
            return nil
        }
    }

    private func showPost(saved: Bool, file: URL?) {
        guard let platform = model.autoEdit.edit?.platform else {
            if let file { try? FileManager.default.removeItem(at: file) }
            return
        }
        if let old = postFile, old != file { try? FileManager.default.removeItem(at: old) }
        postFile = file
        sharesAfterPost = false
        postRequest = AutoEditPostSheet.Request(platform: platform, saved: saved, file: file)
    }

    /// The export sheet closed: Share video opens the share sheet with the
    /// file (deleted when that closes); otherwise the file goes now.
    private func finishPost() {
        guard let file = postFile else {
            sharesAfterPost = false
            return
        }
        postFile = nil
        if sharesAfterPost {
            sharesAfterPost = false
            sharedFile = file
            shareItems = ActivityItems(items: [file])
        } else {
            try? FileManager.default.removeItem(at: file)
        }
    }

    #if DEBUG
    /// Screenshot scene `video`: `-GLEffect <effect>`, `-GLCutSilences YES`,
    /// and `-GLVideoAction save|share|close` to export or ask before closing.
    /// Auto edit: `-GLAutoEdit tiktok|reels|shorts` makes one (with
    /// `-GLAutoEditLength 15|30|60|90` and `-GLAutoEditLook dreamy|golden|analog|moody`),
    /// then `-GLAutoEditPanel options|post` opens its options or its export
    /// sheet; `-GLAutoEditPhase moments|captions` pins its progress, and
    /// `-GLAutoEditUsed YES` has today's free one spent (the paywall's reason).
    private func applyScreenshotOptions() async {
        guard ScreenshotScene.current == .video, !model.loadFailed else { return }
        let defaults = UserDefaults.standard
        if let effect = defaults.string(forKey: "GLEffect").flatMap(RetroEffect.init(rawValue:)) { model.effect = effect }
        if defaults.bool(forKey: "GLCutSilences") { model.cutSilences = true }
        model.captions.applyScreenshotOptions(asset: model.asset, duration: model.duration)
        if let phase = defaults.string(forKey: "GLAutoEditPhase") {
            model.autoEdit.phase = phase == "captions" ? .captions : .moments(0.42)
            return
        }
        if let platform = defaults.string(forKey: "GLAutoEdit").flatMap(SocialPlatform.init(rawValue:)) {
            let length = defaults.double(forKey: "GLAutoEditLength")
            startAutoEdit(platform, length: length > 0 ? length : nil,
                          look: defaults.string(forKey: "GLAutoEditLook").flatMap(AdjustVibes.preset(id:)))
            await model.autoEdit.task?.value
            switch defaults.string(forKey: "GLAutoEditPanel") {
            case "options"?: showsAutoEditOptions = true
            case "post"?: showPost(saved: true, file: nil)
            default: break
            }
        }
        // `-GLVideoSeek <seconds>`: paused on one frame, for caption shots.
        if defaults.object(forKey: "GLVideoSeek") != nil {
            let seconds = defaults.double(forKey: "GLVideoSeek")
            Task {
                try? await Task.sleep(for: .milliseconds(1500))
                model.seek(to: seconds)
            }
        }
        switch defaults.string(forKey: "GLVideoAction") {
        case "save"?: Task { await perform(.save) }
        case "share"?: Task { await perform(.share) }
        case "close"?: showDiscardAlert = model.hasUnsavedEdits
        default: break
        }
    }
    #endif
}

private struct EffectChoice: View {
    let title: LocalizedStringKey
    let image: UIImage?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    Palette.petal
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill()
                    }
                }
                .frame(width: 62, height: 78)
                .clipShape(.print)
                .overlay(
                    RoundedRectangle.print
                        .strokeBorder(isSelected ? Palette.accent : Palette.stroke, lineWidth: isSelected ? 3 : 1)
                )
                Text(title)
                    .font(.legibleCaption2.weight(isSelected ? .bold : .semibold))
                    .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 70)
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Two handles on one track: start and end of the clip.
struct TrimSlider: View {
    @Binding var range: ClosedRange<Double>
    let bounds: ClosedRange<Double>
    var minimumLength: Double = 0.5
    let onChange: () -> Void

    private enum Handle { case start, end }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width - 28
            let span = max(bounds.upperBound - bounds.lowerBound, 0.001)
            let startX = (range.lowerBound - bounds.lowerBound) / span * width
            let endX = (range.upperBound - bounds.lowerBound) / span * width
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.strokeStrong).frame(height: 6).padding(.horizontal, 14)
                Capsule().fill(Palette.accent)
                    .frame(width: max(endX - startX, 0), height: 6)
                    .offset(x: startX + 14)
                // 44 pt touch targets, centred on the 28 pt knobs.
                handle(.start).offset(x: startX - 8)
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("trim")).onChanged { value in
                        let seconds = bounds.lowerBound + min(max(value.location.x - 14, 0), width) / width * span
                        range = min(seconds, range.upperBound - minimumLength)...range.upperBound
                        onChange()
                    })
                handle(.end).offset(x: endX - 8)
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("trim")).onChanged { value in
                        let seconds = bounds.lowerBound + min(max(value.location.x - 14, 0), width) / width * span
                        range = range.lowerBound...max(seconds, range.lowerBound + minimumLength)
                        onChange()
                    })
            }
            .frame(height: 44)
            .coordinateSpace(name: "trim")
        }
        .frame(height: 44)
    }

    private func handle(_ which: Handle) -> some View {
        Circle()
            .fill(Palette.white)
            .frame(width: 28, height: 28)
            .shadow(color: Palette.shadow, radius: 4, y: 2)
            .overlay(Circle().strokeBorder(Palette.accent, lineWidth: 2))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            // VoiceOver: swipe up or down to move the handle. The value names
            // the new length, so nothing extra needs announcing.
            .accessibilityElement()
            .accessibilityLabel(which == .start ? Text("Start") : Text("End"))
            .accessibilityValue(Text(verbatim: spoken(which == .start ? range.lowerBound : range.upperBound) + ", ")
                + Text("Clip length \(spoken(range.upperBound - range.lowerBound))"))
            .accessibilityAdjustableAction { direction in
                adjust(which, by: direction)
            }
    }

    /// Steps of at least half a second, and no more than 20 across the clip.
    private func adjust(_ which: Handle, by direction: AccessibilityAdjustmentDirection) {
        let step = max(0.5, (bounds.upperBound - bounds.lowerBound) / 20)
        let delta: Double
        switch direction {
        case .increment: delta = step
        case .decrement: delta = -step
        @unknown default: return
        }
        switch which {
        case .start:
            let lower = min(max(range.lowerBound + delta, bounds.lowerBound), range.upperBound - minimumLength)
            range = max(lower, bounds.lowerBound)...range.upperBound
        case .end:
            let upper = max(min(range.upperBound + delta, bounds.upperBound), range.lowerBound + minimumLength)
            range = range.lowerBound...min(upper, bounds.upperBound)
        }
        onChange()
    }

    private func spoken(_ seconds: Double) -> String {
        Duration.milliseconds(Int64((seconds * 10).rounded()) * 100)
            .formatted(.units(allowed: [.minutes, .seconds], width: .wide, fractionalPart: .show(length: 1)))
    }
}

/// A bare AVPlayerLayer: no system controls, fits the space it's given.
private struct PlayerView: UIViewRepresentable {
    let player: AVPlayer

    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = UIColor.black
        // Taps go to the play button around it.
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: LayerView, context: Context) {
        view.playerLayer.player = player
    }
}
