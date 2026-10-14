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
    @ObservationIgnored private var rebuildTask: Task<Void, Never>?
    @ObservationIgnored private var captionsTask: Task<Void, Never>?
    @ObservationIgnored private var currentComposition: AVMutableComposition?
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
    }

    private var edits: Edits {
        Edits(cutSilences: cutSilences, effect: effect, showsExtra: showsExtra, trim: trim, captions: captions.snapshot)
    }

    init(url: URL) {
        asset = AVURLAsset(url: url)
        player.isMuted = false
        player.actionAtItemEnd = .none
        captions.onChange = { [weak self] in self?.captionsChanged() }
    }

    var hasSound: Bool { silencePlan != nil }

    /// Changes she'd lose by closing: anything but the untouched clip, unless
    /// exactly this version was already saved or shared.
    var hasUnsavedEdits: Bool {
        let edited = cutSilences || effect != nil || trim != 0...max(duration, 0.1) || captions.shows
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

    /// The parts of the clip that make it into the video.
    var keptRanges: [ClosedRange<Double>] {
        let base = cutSilences ? (silencePlan?.keep ?? [0...duration]) : [0...duration]
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
        guard !ranges.isEmpty, let composition = try? await VideoEngine.composition(of: asset, keeping: ranges) else { return false }
        let videoComposition = try? await VideoEngine.videoComposition(for: composition, effect: effect, showsExtra: showsExtra, fps: frameRate,
                                                                       captions: captionTrack(for: ranges))
        guard !Task.isCancelled else { return true }
        resultDuration = ranges.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) }
        let item = AVPlayerItem(asset: composition)
        item.videoComposition = videoComposition
        currentComposition = composition
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

    /// Captions drawn above the effect's own date stamp, display or bars.
    private func captionTrack(for ranges: [ClosedRange<Double>]) -> CaptionTrack? {
        captions.track(keeping: ranges, overlay: showsExtra && effect?.option?.worksOnVideo == true ? effect : nil)
    }

    /// Captions changed: the playing item gets a new video composition, so
    /// the preview keeps its place instead of starting over.
    private func captionsChanged() {
        captionsTask?.cancel()
        captionsTask = Task {
            // Typing in a caption settles before the redraw.
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let composition = currentComposition, let item = player.currentItem else { return }
            let videoComposition = try? await VideoEngine.videoComposition(for: composition, effect: effect, showsExtra: showsExtra, fps: frameRate,
                                                                           captions: captionTrack(for: keptRanges))
            guard !Task.isCancelled, item === player.currentItem else { return }
            item.videoComposition = videoComposition
            // A paused frame redraws only when asked.
            if !isPlaying { await player.seek(to: seekTarget ?? player.currentTime(), toleranceBefore: .zero, toleranceAfter: .zero) }
        }
    }

    func togglePlayback() {
        seekTarget = nil
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
        Haptics.tap()
    }

    /// Renders the final video and, for Save, writes it to Photos. Returns the
    /// file for Share. Throws `CancellationError` when she cancels, and also
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
            let ranges = keptRanges, effect = effect, showsExtra = showsExtra, fps = frameRate, asset = asset
            let captionTrack = captionTrack(for: ranges)
            let task = Task<URL, Error> {
                let composition = try await VideoEngine.composition(of: asset, keeping: ranges)
                let videoComposition = try await VideoEngine.videoComposition(for: composition, effect: effect, showsExtra: showsExtra, fps: fps,
                                                                              captions: captionTrack)
                try Task.checkCancellation()
                return try await VideoEngine.export(composition, videoComposition: videoComposition) { [weak self] value in
                    self?.exportProgress = value
                }
            }
            exportTask = task
            if cancelledByUser { task.cancel() }
            let url = try await task.value
            if action == .save {
                defer { try? FileManager.default.removeItem(at: url) }
                try await VideoEngine.saveToPhotos(url)
            }
            savedEdits = edits
            restarts = 0
            return action == .share ? url : nil
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

/// Simple video editing, free and on the iPhone: auto-cut silences, retro
/// effects, trim, then save or share. No watermark, no ending clip.
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
                        // Esc on the Mac still reaches this under the export overlay.
                        if model.isExporting {
                            model.cancelExport()
                        } else if model.hasUnsavedEdits {
                            showDiscardAlert = true
                        } else {
                            close()
                        }
                    } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Close")
                    .macKeyboardShortcut(.cancelAction)
                }
                if !model.loadFailed {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button { Task { await perform(.share) } } label: { Image(systemName: "paperplane.fill") }
                            .accessibilityLabel("Share")
                        Button("Save") { Task { await perform(.save) } }
                            .fontWeight(.bold)
                            .macKeyboardShortcut(KeyboardShortcut("s"))
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
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.isExporting)
        .alert("Discard your edits?", isPresented: $showDiscardAlert) {
            Button("Discard", role: .destructive) { close() }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("Save to Photos first if you want to keep them.")
        }
        .task {
            await model.load()
            #if DEBUG
            applyScreenshotOptions()
            #endif
        }
        .onDisappear { model.stop() }
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
                            .font(.caption.weight(.bold).monospacedDigit())
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
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            silenceCard
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
                .font(.caption)
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
                app.countHappyMoment()
                app.showToast("Video saved to Photos ✨", style: .success)
            case .share:
                guard let url else { return }
                sharedFile = url
                shareItems = ActivityItems(items: [url])
                app.countHappyMoment()
            }
            // Free members: an ad may follow once the video editor closes.
            app.ads.noteFinishedExport()
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

    #if DEBUG
    /// Screenshot scene `video`: `-GLEffect <effect>`, `-GLCutSilences YES`,
    /// and `-GLVideoAction save|share|close` to export or ask before closing.
    private func applyScreenshotOptions() {
        guard ScreenshotScene.current == .video, !model.loadFailed else { return }
        let defaults = UserDefaults.standard
        if let effect = defaults.string(forKey: "GLEffect").flatMap(RetroEffect.init(rawValue:)) { model.effect = effect }
        if defaults.bool(forKey: "GLCutSilences") { model.cutSilences = true }
        model.captions.applyScreenshotOptions(asset: model.asset, duration: model.duration)
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
                .clipShape(RoundedRectangle(cornerRadius: Metrics.printRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.printRadius)
                        .strokeBorder(isSelected ? Palette.accent : Palette.stroke, lineWidth: isSelected ? 3 : 1)
                )
                Text(title)
                    .font(.caption2.weight(isSelected ? .bold : .semibold))
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
