import SwiftUI
import AVFoundation
import AppCore

/// The Captions card under "Auto-cut silences": make captions on the
/// device, follow the listening, then switch them on and off or edit them.
struct CaptionsCard: View {
    let model: VideoEditorModel

    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var captions = model.captions
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Captions", systemImage: "captions.bubble")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.textPrimary)
                    detail
                        .font(.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // The button keeps its whole label ("Untertitel hinzufügen");
                // the text beside it wraps instead.
                trailing
                    .layoutPriority(1)
            }
            if case .working(let progress) = captions.status {
                ProgressView(value: fraction(progress))
                    .tint(Palette.accent)
                    .accessibilityLabel(Text("Captions"))
            }
            if let recovery {
                recoveryActions(recovery)
            }
        }
        .padding(14)
        .cardStyle()
        .animation(.easeInOut(duration: 0.2), value: captions.status)
        .sheet(isPresented: $captions.isEditing, onDismiss: { captions.removeBlank() }) {
            CaptionsEditor(model: model)
        }
    }

    @ViewBuilder
    private var detail: some View {
        let captions = model.captions
        switch captions.status {
        case .idle:
            Text("Words appear as you talk. Free, made on your device.")
        case .working(.preparing):
            Text("Getting ready…")
        case .working(.downloading):
            if let name = captions.languageName {
                Text("Downloading \(name) for captions (one time)…")
            } else {
                Text("Downloading the language for captions (one time)…")
            }
        case .working(.listening):
            Text("Listening to your video…")
        case .done:
            if captions.cues.isEmpty {
                Text("We didn't hear any words. You can add your own.")
            } else {
                Text("\(captions.cues.count) captions")
            }
        case .failed(let failure):
            Self.failureText(failure)
        }
    }

    static func failureText(_ failure: CaptionTranscriber.Failure) -> Text {
        switch failure {
        case .noSound:
            return Text("This video has no sound. You can add captions yourself.")
        case .notAllowed:
            return Platform.isMac
                ? Text("Speech recognition is off for Glowlit. Turn it on in System Settings, or add captions yourself.")
                : Text("Speech recognition is off for Glowlit. Turn it on in Settings, or add captions yourself.")
        case .unavailable:
            return Text("Automatic captions aren't available for this language on this device. You can add them yourself.")
        case .downloadFailed:
            return Text("Couldn't download the language. Connect to the internet and try again.")
        case .failed:
            return Text("Couldn't make captions. Try again, or add them yourself.")
        }
    }

    @ViewBuilder
    private var trailing: some View {
        @Bindable var captions = model.captions
        switch captions.status {
        case .idle:
            Button("Add captions") { start() }
                .buttonStyle(CaptionPillButtonStyle(prominent: true))
                .disabled(model.duration <= 0)
        case .working:
            Button("Cancel") { captions.cancel() }
                .buttonStyle(CaptionPillButtonStyle())
        case .done, .failed:
            // Captions from before a failed redo stay editable.
            if !captions.cues.isEmpty {
                HStack(spacing: 10) {
                    Button("Edit") { captions.isEditing = true }
                        .buttonStyle(CaptionPillButtonStyle())
                    Toggle("Show captions", isOn: $captions.isOn)
                        .labelsHidden()
                        .tint(Palette.accent)
                }
            }
        }
    }

    private enum Recovery { case retry, settings, manualOnly }

    /// Ways forward after a failed or empty try; writing captions by hand always works.
    private var recovery: Recovery? {
        switch model.captions.status {
        case .done where model.captions.cues.isEmpty: return .manualOnly
        case .failed(.notAllowed): return .settings
        case .failed(.downloadFailed), .failed(.failed): return .retry
        case .failed: return .manualOnly
        default: return nil
        }
    }

    private func recoveryActions(_ recovery: Recovery) -> some View {
        HStack(spacing: 8) {
            switch recovery {
            case .retry:
                Button("Try again") { start() }
                    .buttonStyle(CaptionPillButtonStyle(prominent: true))
            case .settings:
                Button(Platform.isMac ? "Open System Settings" : "Open Settings") { openSettings() }
                    .buttonStyle(CaptionPillButtonStyle(prominent: true))
            case .manualOnly:
                EmptyView()
            }
            Button("Add a caption") { addCaption() }
                .buttonStyle(CaptionPillButtonStyle(prominent: recovery == .manualOnly))
        }
    }

    private func fraction(_ progress: CaptionTranscriber.Progress) -> Double? {
        switch progress {
        case .preparing: return nil
        case .downloading(let value), .listening(let value): return value
        }
    }

    private func start() {
        Haptics.tap()
        model.captions.make(from: model.asset, duration: model.duration)
    }

    private func addCaption() {
        let source = CaptionTimeline.sourceTime(model.playheadSeconds, keeping: model.keptRanges)
        model.captions.add(at: source, clipDuration: model.duration)
        model.captions.isEditing = true
    }

    private func openSettings() {
        let address = Platform.isMac
            ? "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
            : UIApplication.openSettingsURLString
        if let url = URL(string: address) { openURL(url) }
    }
}

/// Small capsule buttons inside the card.
private struct CaptionPillButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .foregroundStyle(prominent ? Palette.onAccent : Palette.textPrimary)
            .background(prominent ? Palette.accent : Palette.surfaceRaised, in: Capsule())
            .overlay(Capsule().strokeBorder(prominent ? Color.clear : Palette.strokeStrong, lineWidth: 1))
            .frame(minHeight: 44)
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

/// Every caption, editable: text, timing, delete, add at the playhead, plus
/// the style, language, redo and copy. A small player stays on top so each
/// change shows on the video right away.
struct CaptionsEditor: View {
    let model: VideoEditorModel

    @Environment(\.dismiss) private var dismiss
    @State private var playhead: Double = 0
    @State private var samples: [CaptionStyle: UIImage] = [:]
    @State private var confirmRedo = false
    @State private var copied = false
    @FocusState private var focused: UUID?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                preview
                    .padding(.vertical, 12)
                ScrollViewReader { proxy in
                    List {
                        styleSection
                        progressSection
                        cuesSection
                        languageSection
                    }
                    .scrollContentBackground(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: focused) { _, id in
                        if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
                    }
                    #if DEBUG
                    // `-GLCaptionsEditorScroll bottom` for a shot of the language rows.
                    .task {
                        guard UserDefaults.standard.string(forKey: "GLCaptionsEditorScroll") == "bottom" else { return }
                        try? await Task.sleep(for: .milliseconds(800))
                        proxy.scrollTo("copy", anchor: .bottom)
                    }
                    #endif
                }
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Captions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .confirmationDialog("Redo captions?", isPresented: $confirmRedo, titleVisibility: .visible) {
                Button("Redo captions", role: .destructive) { remake() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Glowlit listens to your video again and replaces these captions, including your changes.")
            }
        }
        .tint(Palette.accent)
        .presentationDetents([.large])
        .presentationBackground(Palette.background)
        .task { await followPlayhead() }
        .task { await makeSamples() }
        .task { await model.captions.loadLanguages() }
        .onAppear { focused = model.captions.cues.first(where: \.isBlank)?.id }
    }

    // MARK: Preview

    private var preview: some View {
        let aspect = model.thumbnail.map { $0.size.width / max($0.size.height, 1) } ?? 9 / 16
        return Button { model.togglePlayback() } label: {
            CaptionsPlayerView(player: model.player)
                .aspectRatio(aspect, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    if !model.isPlaying {
                        Image(systemName: "play.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Palette.ink)
                            .frame(width: 48, height: 48)
                            .liquidGlass(in: Circle())
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(height: 200)
        .frame(maxWidth: .infinity)
        .shadow(color: Palette.shadow, radius: 10, y: 4)
        .accessibilityLabel(model.isPlaying ? Text("Pause") : Text("Play"))
    }

    // MARK: Sections

    private var styleSection: some View {
        @Bindable var captions = model.captions
        return Section {
            HStack(spacing: 8) {
                ForEach(CaptionStyle.allCases) { style in
                    CaptionStyleButton(style: style, image: samples[style], isSelected: captions.style == style) {
                        Haptics.selection()
                        captions.style = style
                    }
                }
            }
            .padding(.vertical, 4)
            HStack {
                Text("Position")
                Spacer()
                Picker("Position", selection: $captions.position) {
                    ForEach(CaptionPosition.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            HStack {
                Text("Size")
                Spacer()
                Picker("Size", selection: $captions.size) {
                    ForEach(CaptionSize.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        } header: {
            Text("Style")
        } footer: {
            if captions.style == .karaoke {
                Text("Each word lights up as it's said. Captions you write or rewrite yourself show like Pop.")
            }
        }
        .listRowBackground(Palette.surface)
    }

    @ViewBuilder
    private var progressSection: some View {
        let captions = model.captions
        if case .failed(let failure) = captions.status {
            Section {
                Label { CaptionsCard.failureText(failure) } icon: { Image(systemName: "exclamationmark.bubble") }
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
            }
            .listRowBackground(Palette.surface)
        }
        if case .working(let progress) = captions.status {
            Section {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        switch progress {
                        case .preparing: Text("Getting ready…")
                        case .downloading: Text("Downloading the language for captions (one time)…")
                        case .listening: Text("Listening to your video…")
                        }
                        switch progress {
                        case .preparing: ProgressView().frame(maxWidth: .infinity, alignment: .leading)
                        case .downloading(let value), .listening(let value): ProgressView(value: value)
                        }
                    }
                    .font(.subheadline)
                    Button("Cancel") { captions.cancel() }
                        .buttonStyle(.borderless)
                }
            }
            .listRowBackground(Palette.surface)
        }
    }

    private var cuesSection: some View {
        let captions = model.captions
        let ranges = model.keptRanges
        return Section {
            ForEach(captions.cues) { cue in
                let shown = CaptionTimeline.outputRange(of: cue, keeping: ranges)
                CaptionCueRow(cue: cue, shown: shown, isCurrent: shown?.contains(playhead) == true, ranges: ranges,
                              clipDuration: model.duration, captions: captions, focus: $focused) {
                    if let shown { model.seek(to: shown.lowerBound + 0.05) }
                }
                .id(cue.id)
            }
            Button { addCaption() } label: {
                Label("Add a caption", systemImage: "plus.bubble")
            }
            .disabled(model.duration <= 0)
        } header: {
            Text("Captions")
        } footer: {
            if captions.cues.isEmpty {
                if captions.heardNothing {
                    Text("We didn't hear any words. Add your own at any moment of the video.")
                } else {
                    Text("Add a caption where the video is now, or make them from what's said.")
                }
            } else {
                Text("Tap a time to see that caption on the video.")
            }
        }
        .listRowBackground(Palette.surface)
    }

    private var languageSection: some View {
        @Bindable var captions = model.captions
        return Section {
            if captions.languages.isEmpty {
                LabeledContent("Language") { ProgressView() }
            } else {
                Picker("Language", selection: $captions.languageID) {
                    ForEach(captions.languages) { language in
                        Text(language.name).tag(Optional(language.id))
                    }
                }
                .pickerStyle(.navigationLink)
            }
            Button {
                if captions.cues.contains(where: { !$0.isBlank }) { confirmRedo = true } else { remake() }
            } label: {
                Label(captions.cues.isEmpty ? "Make captions" : "Redo captions", systemImage: "waveform")
            }
            .disabled(captions.isWorking || model.duration <= 0 || captions.languages.isEmpty)
            Button { copy() } label: {
                Label(copied ? "Copied" : "Copy captions (SRT)", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .disabled(!captions.shows)
            .id("copy")
        } footer: {
            Text("Captions are made on your device with Apple's speech recognition. The sound and words of your video are never uploaded.")
        }
        .listRowBackground(Palette.surface)
    }

    // MARK: Actions

    private func addCaption() {
        let source = CaptionTimeline.sourceTime(playhead, keeping: model.keptRanges)
        let id = model.captions.add(at: source, clipDuration: model.duration)
        focused = id
    }

    private func remake() {
        focused = nil
        model.captions.make(from: model.asset, duration: model.duration)
    }

    private func copy() {
        UIPasteboard.general.string = model.captions.subRip(keeping: model.keptRanges)
        Haptics.success()
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }

    /// The current caption is marked in the list while the video plays.
    private func followPlayhead() async {
        while !Task.isCancelled {
            playhead = model.playheadSeconds
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private func makeSamples() async {
        guard samples.isEmpty else { return }
        let background = model.thumbnail
        samples = await Task.detached(priority: .userInitiated) {
            Dictionary(uniqueKeysWithValues: CaptionStyle.allCases.map { style in
                (style, CaptionTrack.sample(style, over: background, size: CGSize(width: 132, height: 176)))
            })
        }.value
    }
}

private struct CaptionCueRow: View {
    let cue: CaptionCue
    /// When it shows in the edited video; nil when that part was cut.
    let shown: ClosedRange<Double>?
    let isCurrent: Bool
    let ranges: [ClosedRange<Double>]
    let clipDuration: Double
    let captions: VideoCaptions
    var focus: FocusState<UUID?>.Binding
    let onSeek: () -> Void

    @State private var showsTiming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                Button(action: onSeek) {
                    Label {
                        if let shown {
                            Text(verbatim: "\(Self.format(shown.lowerBound)) – \(Self.format(shown.upperBound))")
                                .monospacedDigit()
                        } else {
                            Text("Cut from the video")
                        }
                    } icon: {
                        Image(systemName: isCurrent ? "waveform" : "play.fill")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isCurrent ? Palette.accent : Palette.textSecondary)
                }
                .buttonStyle(.borderless)
                .disabled(shown == nil)
                .accessibilityHint(Text("Shows this caption on the video"))
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showsTiming.toggle() }
                } label: {
                    Image(systemName: "timer")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Change timing"))
                Button(role: .destructive) {
                    captions.remove(cue.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Delete caption"))
            }
            TextField("Write a caption", text: Binding(get: { cue.text }, set: { captions.setText($0, for: cue.id) }), axis: .vertical)
                .lineLimit(1...4)
                .font(.body.weight(.medium))
                .foregroundStyle(Palette.textPrimary)
                .focused(focus, equals: cue.id)
            if showsTiming {
                Stepper(value: Binding(get: { cue.start }, set: { captions.setStart($0, for: cue.id) }),
                        in: 0...max(0, cue.end - 0.2), step: 0.1) {
                    Text("Starts at \(Self.format(edited(cue.start)))")
                        .font(.subheadline.monospacedDigit())
                }
                Stepper(value: Binding(get: { cue.end }, set: { captions.setEnd($0, for: cue.id, clipDuration: clipDuration) }),
                        in: (cue.start + 0.2)...max(cue.start + 0.2, clipDuration), step: 0.1) {
                    Text("Ends at \(Self.format(edited(cue.end)))")
                        .font(.subheadline.monospacedDigit())
                }
            }
        }
        .padding(.vertical, 4)
        .swipeActions {
            Button(role: .destructive) {
                captions.remove(cue.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// Times read on the edited video, like the rest of the editor.
    private func edited(_ source: Double) -> Double {
        CaptionTimeline.outputTime(source, keeping: ranges) ?? source
    }

    static func format(_ seconds: Double) -> String {
        let value = max(0, seconds)
        return String(format: "%d:%04.1f", Int(value) / 60, value.truncatingRemainder(dividingBy: 60))
    }
}

private struct CaptionStyleButton: View {
    let style: CaptionStyle
    let image: UIImage?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    Palette.charcoal
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill()
                    }
                }
                .frame(width: 64, height: 86)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isSelected ? Palette.accent : Palette.stroke, lineWidth: isSelected ? 3 : 1)
                )
                Text(style.title)
                    .font(.caption2.weight(isSelected ? .bold : .semibold))
                    .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text(style.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The editor's player again, small, in the captions sheet.
private struct CaptionsPlayerView: UIViewRepresentable {
    let player: AVPlayer

    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: LayerView, context: Context) {
        view.playerLayer.player = player
    }
}
