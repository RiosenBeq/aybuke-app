#if DEBUG
import AVFoundation
import AppCore

extension ScreenshotFixtures {
    /// Canned captions for the generated clip (it has no speech), with word
    /// times for Karaoke. The second one runs into the clip's quiet middle,
    /// so "Auto-cut silences" visibly shortens it.
    static var sampleCaptions: [CaptionCue] {
        func cue(_ words: [(String, Double, Double)]) -> CaptionCue {
            CaptionCue(start: words[0].1, end: words[words.count - 1].2 + 0.25,
                       text: words.map(\.0).joined(separator: " "),
                       words: words.map { CaptionWord(text: $0.0, start: $0.1, end: $0.2) })
        }
        return [
            cue([("Hi", 0.2, 0.45), ("besties,", 0.45, 0.95), ("welcome", 1.0, 1.35), ("back!", 1.35, 1.6), ("💖", 1.6, 1.7)]),
            cue([("Today", 2.0, 2.3), ("we're", 2.3, 2.5), ("trying", 2.5, 2.85), ("the", 2.85, 2.95), ("Camcorder", 2.95, 3.4), ("'06", 3.4, 3.7), ("look", 3.7, 3.95)]),
            cue([("Honestly,", 4.3, 4.8), ("it's", 4.85, 5.0), ("giving", 5.0, 5.3), ("2006", 5.3, 5.75), ("energy", 5.75, 6.0)]),
            cue([("Tell", 6.3, 6.5), ("me", 6.5, 6.6), ("what", 6.6, 6.8), ("you", 6.8, 6.95), ("think!", 6.95, 7.5)]),
        ]
    }

    /// `-GLVideoSpeech YES`: a few sentences in the system voice instead of
    /// the tone, so automatic captions can be tried for real.
    static func writeSpeech(to url: URL) async throws {
        let utterance = AVSpeechUtterance(string: "Hi everyone, welcome back to my channel. Today I am trying the new pink hair look. Honestly, I love how it turned out! What do you think?")
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        let synthesizer = AVSpeechSynthesizer()
        let writer = SpeechFileWriter(url: url)
        await withCheckedContinuation { continuation in
            writer.onFinish = { continuation.resume() }
            synthesizer.write(utterance) { buffer in writer.append(buffer) }
        }
        try writer.close()
        _ = synthesizer
    }
}

/// Collects the synthesizer's buffers into a file; an empty buffer ends it.
private final class SpeechFileWriter: @unchecked Sendable {
    let url: URL
    var onFinish: (() -> Void)?
    private var file: AVAudioFile?
    private var failure: Error?
    private var finished = false
    private let lock = NSLock()

    init(url: URL) { self.url = url }

    func append(_ buffer: AVAudioBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
            finished = true
            onFinish?()
            return
        }
        do {
            if file == nil {
                file = try AVAudioFile(forWriting: url, settings: pcm.format.settings,
                                       commonFormat: pcm.format.commonFormat, interleaved: pcm.format.isInterleaved)
            }
            try file?.write(from: pcm)
        } catch {
            failure = error
        }
    }

    func close() throws {
        lock.lock()
        defer { lock.unlock() }
        // Releasing the file finishes writing it.
        file = nil
        if let failure { throw failure }
    }
}
#endif
