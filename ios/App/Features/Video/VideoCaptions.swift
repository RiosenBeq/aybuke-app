import SwiftUI
import AVFoundation
import AppCore

/// Automatic captions in the video editor: made on the device from what's
/// said, fixed by hand, and drawn into the preview and the saved video.
/// Cues stay in source time (the whole clip); trim and "Auto-cut silences"
/// map them when the video is built, so those never need a new transcript.
@MainActor
@Observable
final class VideoCaptions {
    enum Status: Equatable {
        case idle
        case working(CaptionTranscriber.Progress)
        case done
        case failed(CaptionTranscriber.Failure)
    }

    private(set) var status: Status = .idle
    var cues: [CaptionCue] = [] { didSet { if cues != oldValue { changed() } } }
    var isOn = true { didSet { if isOn != oldValue { changed() } } }
    var style: CaptionStyle = .pop { didSet { if style != oldValue { changed() } } }
    var position: CaptionPosition = .bottom { didSet { if position != oldValue { changed() } } }
    var size: CaptionSize = .medium { didSet { if size != oldValue { changed() } } }
    private(set) var languages: [CaptionTranscriber.Language] = []
    var languageID: String?
    var isEditing = false
    /// The last automatic try heard no words.
    private(set) var heardNothing = false

    /// Called on every change that shows in the video.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    var isWorking: Bool {
        if case .working = status { return true }
        return false
    }

    var look: CaptionLook { CaptionLook(style: style, position: position, size: size) }

    /// Captions that will be in the video.
    var shows: Bool { isOn && cues.contains { !$0.isBlank } }

    var languageName: String? { languages.first { $0.id == languageID }?.name }

    /// What a save remembers, to know when closing loses something.
    struct Snapshot: Equatable {
        let isOn: Bool
        let cues: [CaptionCue]
        let look: CaptionLook
    }

    var snapshot: Snapshot { Snapshot(isOn: isOn, cues: cues, look: look) }

    private func changed() { onChange?() }

    // MARK: Making captions

    func loadLanguages() async {
        guard languages.isEmpty else { return }
        let found = await CaptionTranscriber.languages()
        languages = found
        if languageID == nil || !found.contains(where: { $0.id == languageID }) {
            languageID = CaptionTranscriber.defaultLanguage(in: found)?.id
        }
    }

    /// Listens to the clip on the device and replaces the captions with what
    /// was said.
    func make(from asset: AVAsset, duration: Double) {
        work?.cancel()
        generation += 1
        let current = generation
        heardNothing = false
        status = .working(.preparing)
        work = Task {
            await loadLanguages()
            guard current == generation else { return }
            guard let language = languageID else {
                status = .failed(.unavailable)
                return
            }
            do {
                let made = try await CaptionTranscriber.transcribe(asset, duration: duration, language: language) { [weak self] progress in
                    guard let self, current == self.generation else { return }
                    self.status = .working(progress)
                }
                guard current == generation else { return }
                cues = made
                isOn = true
                heardNothing = made.isEmpty
                status = .done
                Haptics.success()
                #if DEBUG
                // QA reads what was heard from the console (`-GLCaptions auto`).
                print("[captions] \(language): \(made.map { String(format: "%.2f–%.2f %@", $0.start, $0.end, $0.text) }.joined(separator: " | "))")
                #endif
            } catch {
                guard current == generation else { return }
                if error is CancellationError {
                    status = cues.isEmpty ? .idle : .done
                } else {
                    status = .failed(error as? CaptionTranscriber.Failure ?? .failed)
                }
            }
        }
    }

    func cancel() {
        guard isWorking else { return }
        work?.cancel()
        generation += 1
        status = cues.isEmpty ? .idle : .done
    }

    // MARK: Editing

    private func index(of id: UUID) -> Int? { cues.firstIndex { $0.id == id } }

    func setText(_ text: String, for id: UUID) {
        guard let index = index(of: id) else { return }
        cues[index] = cues[index].withText(text)
    }

    /// Times in source seconds; a caption stays at least 0.2 s long.
    func setStart(_ seconds: Double, for id: UUID) {
        guard let index = index(of: id) else { return }
        cues[index].start = max(0, min(seconds, cues[index].end - 0.2))
        cues.sort { $0.start < $1.start }
    }

    func setEnd(_ seconds: Double, for id: UUID, clipDuration: Double) {
        guard let index = index(of: id) else { return }
        cues[index].end = min(clipDuration, max(seconds, cues[index].start + 0.2))
    }

    func remove(_ id: UUID) {
        cues.removeAll { $0.id == id }
    }

    /// A new, empty caption at `seconds` (source time), up to 2 s long and
    /// not running into the next one.
    @discardableResult
    func add(at seconds: Double, clipDuration: Double) -> UUID {
        let start = min(max(0, seconds), max(0, clipDuration - 0.5))
        let next = cues.first { $0.start > start + 0.05 }?.start ?? clipDuration
        let end = max(min(start + 2, next, clipDuration), start + 0.5)
        let cue = CaptionCue(start: start, end: end, text: "")
        cues.append(cue)
        cues.sort { $0.start < $1.start }
        isOn = true
        if status == .idle { status = .done }
        return cue.id
    }

    /// Empty captions go when the editor closes.
    func removeBlank() {
        cues.removeAll { $0.isBlank }
    }

    // MARK: Output

    /// The captions on the edited timeline, or nil when they're off.
    func track(keeping ranges: [ClosedRange<Double>], overlay: RetroEffect?) -> CaptionTrack? {
        guard isOn else { return nil }
        return CaptionTrack(cues: CaptionTimeline.remap(cues, keeping: ranges), look: look, overlay: overlay)
    }

    /// SubRip text timed to the edited video.
    func subRip(keeping ranges: [ClosedRange<Double>]) -> String {
        CaptionSRT.text(for: CaptionTimeline.remap(cues, keeping: ranges))
    }

    #if DEBUG
    /// `-GLCaptions fixture|auto|listening|downloading|nospeech|denied|unavailable`
    /// with `-GLCaptionStyle`, `-GLCaptionPosition`, `-GLCaptionSize` and
    /// `-GLCaptionsEditor YES` for the `video` screenshot scene. `auto` really
    /// listens (pair it with `-GLVideoSpeech YES`).
    func applyScreenshotOptions(asset: AVAsset, duration: Double) {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: "GLCaptions") == "auto" { make(from: asset, duration: duration) }
        if let style = defaults.string(forKey: "GLCaptionStyle").flatMap(CaptionStyle.init(rawValue:)) { self.style = style }
        if let position = defaults.string(forKey: "GLCaptionPosition").flatMap(CaptionPosition.init(rawValue:)) { self.position = position }
        if let size = defaults.string(forKey: "GLCaptionSize").flatMap(CaptionSize.init(rawValue:)) { self.size = size }
        switch defaults.string(forKey: "GLCaptions") {
        case "fixture"?:
            cues = ScreenshotFixtures.sampleCaptions
            status = .done
        case "listening"?: status = .working(.listening(0.42))
        case "downloading"?: status = .working(.downloading(0.3))
        case "nospeech"?:
            heardNothing = true
            status = .done
        case "denied"?: status = .failed(.notAllowed)
        case "unavailable"?: status = .failed(.unavailable)
        default: break
        }
        if defaults.bool(forKey: "GLCaptionsEditor") { isEditing = true }
    }
    #endif
}
