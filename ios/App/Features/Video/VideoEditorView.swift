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
    let asset: AVURLAsset
    private(set) var duration: Double = 0
    private(set) var thumbnail: UIImage?
    private(set) var effectThumbnails: [RetroEffect: UIImage] = [:]
    private(set) var silencePlan: SilenceCutter.Plan?
    private(set) var isAnalyzing = true
    private(set) var isExporting = false
    private(set) var resultDuration: Double = 0

    var cutSilences = false { didSet { scheduleRebuild() } }
    var effect: RetroEffect? { didSet { scheduleRebuild() } }
    var dateStamp = true { didSet { scheduleRebuild() } }
    var trim: ClosedRange<Double> = 0...1

    let player = AVPlayer()
    private(set) var isPlaying = false
    @ObservationIgnored private var rebuildTask: Task<Void, Never>?
    @ObservationIgnored private var loopObserver: NSObjectProtocol?

    init(url: URL) {
        asset = AVURLAsset(url: url)
        player.isMuted = false
        player.actionAtItemEnd = .none
    }

    var hasSound: Bool { silencePlan != nil }

    func load() async {
        duration = min((try? await VideoEngine.duration(of: asset)) ?? 0, VideoEngine.maxDuration)
        trim = 0...max(duration, 0.1)
        thumbnail = await VideoEngine.thumbnail(of: asset)
        if let thumbnail {
            let small = ImageUtilities.normalized(thumbnail, maxLongEdge: 240)
            effectThumbnails = await Task.detached(priority: .userInitiated) {
                Dictionary(uniqueKeysWithValues: RetroEffect.videoEffects.map { ($0, $0.apply(to: small, dateStamp: false)) })
            }.value
        }
        await rebuild()
        let levels = (try? await VideoEngine.loudness(of: asset)) ?? []
        silencePlan = levels.isEmpty ? nil : SilenceCutter.plan(levels: levels, window: VideoEngine.levelWindow)
        isAnalyzing = false
        if cutSilences { await rebuild() }
    }

    func trimChanged() {
        scheduleRebuild(delay: .milliseconds(250))
    }

    /// The parts of the clip that make it into the video.
    private var keptRanges: [ClosedRange<Double>] {
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

    private func rebuild() async {
        let ranges = keptRanges
        guard !ranges.isEmpty, let composition = try? await VideoEngine.composition(of: asset, keeping: ranges) else { return }
        let videoComposition = try? await VideoEngine.videoComposition(for: composition, effect: effect, dateStamp: dateStamp)
        guard !Task.isCancelled else { return }
        resultDuration = ranges.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) }
        let item = AVPlayerItem(asset: composition)
        item.videoComposition = videoComposition
        player.replaceCurrentItem(with: item)
        if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
        loopObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.player.seek(to: .zero)
                self?.player.play()
            }
        }
        player.play()
        isPlaying = true
    }

    func togglePlayback() {
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
        Haptics.tap()
    }

    /// Renders the final video into a temporary .mp4.
    func export() async throws -> URL {
        isExporting = true
        defer { isExporting = false }
        let composition = try await VideoEngine.composition(of: asset, keeping: keptRanges)
        let videoComposition = try await VideoEngine.videoComposition(for: composition, effect: effect, dateStamp: dateStamp)
        return try await VideoEngine.export(composition, videoComposition: videoComposition)
    }

    func stop() {
        player.pause()
        isPlaying = false
        if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
    }
}

/// Simple video editing, free and on the iPhone: auto-cut silences, retro
/// effects, trim, then save or share. No watermark, no ending clip.
struct VideoEditorView: View {
    let source: VideoSource

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model: VideoEditorModel
    @State private var shareItems: ActivityItems?

    init(source: VideoSource) {
        self.source = source
        _model = State(initialValue: VideoEditorModel(url: source.url))
    }

    var body: some View {
        NavigationStack {
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
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        model.stop()
                        try? FileManager.default.removeItem(at: source.url)
                        dismiss()
                    } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Close")
                    .macKeyboardShortcut(.cancelAction)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { Task { await shareVideo() } } label: { Image(systemName: "paperplane.fill") }
                        .accessibilityLabel("Share")
                    Button("Save") { Task { await saveVideo() } }
                        .fontWeight(.bold)
                        .macKeyboardShortcut(KeyboardShortcut("s"))
                }
            }
        }
        .tint(Palette.accent)
        .overlay {
            if model.isExporting {
                GeneratingOverlay(title: String(localized: "Saving your video…"))
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.isExporting)
        .task { await model.load() }
        .onDisappear { model.stop() }
        .shareSheet(item: $shareItems)
    }

    private var playerCard: some View {
        PlayerView(player: model.player)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if model.resultDuration > 0 {
                    Text(timeLabel)
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(Palette.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .liquidGlass(in: Capsule())
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
                        .allowsHitTesting(false)
                }
            }
            .shadow(color: Palette.shadow, radius: 16, y: 8)
            .onTapGesture { model.togglePlayback() }
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
            silenceCard
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

            if model.effect?.hasDateStamp == true {
                Toggle(isOn: $model.dateStamp) {
                    Label("Date stamp", systemImage: "calendar")
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
        }
        .tint(Palette.accent)
        .disabled(model.isAnalyzing || !(model.silencePlan?.cutsSomething ?? false))
        .padding(14)
        .cardStyle()
    }

    // MARK: Actions

    private func saveVideo() async {
        do {
            let url = try await model.export()
            try await VideoEngine.saveToPhotos(url)
            try? FileManager.default.removeItem(at: url)
            Haptics.success()
            app.countHappyMoment()
            app.showToast("Video saved to Photos ✨", style: .success)
        } catch {
            app.handle(error)
        }
    }

    private func shareVideo() async {
        do {
            let url = try await model.export()
            shareItems = ActivityItems(items: [url])
            app.countHappyMoment()
        } catch {
            app.handle(error)
        }
    }
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
                handle.offset(x: startX)
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("trim")).onChanged { value in
                        let seconds = bounds.lowerBound + min(max(value.location.x - 14, 0), width) / width * span
                        range = min(seconds, range.upperBound - minimumLength)...range.upperBound
                        onChange()
                    })
                    .accessibilityLabel("Start")
                handle.offset(x: endX)
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("trim")).onChanged { value in
                        let seconds = bounds.lowerBound + min(max(value.location.x - 14, 0), width) / width * span
                        range = range.lowerBound...max(seconds, range.lowerBound + minimumLength)
                        onChange()
                    })
                    .accessibilityLabel("End")
            }
            .frame(height: 28)
            .coordinateSpace(name: "trim")
        }
        .frame(height: 28)
    }

    private var handle: some View {
        Circle()
            .fill(Palette.white)
            .frame(width: 28, height: 28)
            .shadow(color: Palette.shadow, radius: 4, y: 2)
            .overlay(Circle().strokeBorder(Palette.accent, lineWidth: 2))
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
        return view
    }

    func updateUIView(_ view: LayerView, context: Context) {
        view.playerLayer.player = player
    }
}
