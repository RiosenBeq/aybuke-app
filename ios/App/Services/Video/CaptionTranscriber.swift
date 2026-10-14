import AVFoundation
import Speech
import AppCore

/// Automatic captions: what's said in a clip, recognized on the device with
/// Apple's speech recognition. Audio and text never leave the device. iOS 26
/// uses SpeechAnalyzer (each language's model downloads once from Apple, with
/// no audio sent); earlier versions use SFSpeechRecognizer, and only when it
/// can recognize that language on the device.
enum CaptionTranscriber {
    enum Failure: Error, Equatable {
        /// The clip has no sound.
        case noSound
        /// Speech recognition is off for the app (SFSpeechRecognizer only).
        case notAllowed
        /// No on-device recognizer for the language, or none at all.
        case unavailable
        /// The language's model couldn't be downloaded (offline).
        case downloadFailed
        case failed
    }

    enum Progress: Equatable {
        case preparing
        /// The language's speech model downloading, 0…1.
        case downloading(Double)
        /// Share of the clip heard so far, 0…1.
        case listening(Double)
    }

    struct Language: Identifiable, Hashable {
        /// BCP 47, like "en-US".
        let id: String
        let name: String
    }

    // MARK: Languages

    /// Every language the device can turn into captions without the network
    /// (iOS 26 models included, which download once), sorted by name.
    static func languages() async -> [Language] {
        var identifiers = Set<String>()
        if #available(iOS 26.0, *) {
            identifiers.formUnion(await analyzerLocales().all)
        }
        identifiers.formUnion(await legacyLocales())
        let names = Locale.current
        return identifiers.map { id in
            Language(id: id, name: names.localizedString(forIdentifier: id) ?? id)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The app's language when the device can do it, else the device's.
    static func defaultLanguage(in languages: [Language]) -> Language? {
        let preferred = CaptionLanguage.preferred(appLanguage: Bundle.main.preferredLocalizations.first ?? "en",
                                                  deviceLanguages: Locale.preferredLanguages)
        let match = CaptionLanguage.bestMatch(preferred: preferred, available: languages.map(\.id),
                                              region: Locale.current.region?.identifier)
        return languages.first { $0.id == match }
    }

    private static func bcp47(_ locale: Locale) -> String {
        locale.identifier(.bcp47)
    }

    @available(iOS 26.0, *)
    private static func analyzerLocales() async -> (speech: Set<String>, dictation: Set<String>, all: Set<String>) {
        let speech = SpeechTranscriber.isAvailable ? Set(await SpeechTranscriber.supportedLocales.map(bcp47)) : []
        let dictation = Set(await DictationTranscriber.supportedLocales.map(bcp47))
        return (speech, dictation, speech.union(dictation))
    }

    /// SFSpeechRecognizer languages that run on the device; checking each
    /// creates a recognizer, so it runs off the main thread.
    private static func legacyLocales() async -> Set<String> {
        await Task.detached(priority: .userInitiated) {
            Set(SFSpeechRecognizer.supportedLocales().compactMap { locale in
                SFSpeechRecognizer(locale: locale)?.supportsOnDeviceRecognition == true ? bcp47(locale) : nil
            })
        }.value
    }

    // MARK: Transcribing

    /// Captions for the first `duration` seconds of `asset`, in source time.
    /// Cancelling the task stops listening and throws `CancellationError`.
    static func transcribe(_ asset: AVAsset, duration: Double, language: String,
                           progress: @escaping @MainActor (Progress) -> Void) async throws -> [CaptionCue] {
        await progress(.preparing)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw Failure.noSound }
        let locale = Locale(identifier: language)
        let relay = ProgressRelay(progress)
        let phrases: [TranscriptPhrase]
        if #available(iOS 26.0, *), let dictation = await analyzerUses(language) {
            #if DEBUG
            CaptionsTrace.note("\(language) with SpeechAnalyzer (\(dictation ? "DictationTranscriber" : "SpeechTranscriber"))")
            #endif
            do {
                phrases = try await analyze(asset, track: track, duration: duration, locale: locale, dictation: dictation, relay: relay)
            } catch Failure.unavailable where SFSpeechRecognizer(locale: locale)?.supportsOnDeviceRecognition == true {
                // No model for SpeechAnalyzer here, but on-device dictation has one.
                phrases = try await recognizeOnDevice(asset, track: track, duration: duration, locale: locale, relay: relay)
            }
        } else {
            #if DEBUG
            CaptionsTrace.note("\(language) with SFSpeechRecognizer on device")
            #endif
            phrases = try await recognizeOnDevice(asset, track: track, duration: duration, locale: locale, relay: relay)
        }
        try Task.checkCancellation()
        return CaptionChunker.cues(from: phrases)
    }

    /// Which SpeechAnalyzer module handles the language: SpeechTranscriber
    /// where it can (better punctuation and timing), DictationTranscriber for
    /// the rest. Nil: neither does.
    @available(iOS 26.0, *)
    private static func analyzerUses(_ language: String) async -> Bool? {
        let locales = await analyzerLocales()
        if locales.speech.contains(language) { return false }
        if locales.dictation.contains(language) { return true }
        return nil
    }

    // MARK: SpeechAnalyzer (iOS 26)

    @available(iOS 26.0, *)
    private static func analyze(_ asset: AVAsset, track: AVAssetTrack, duration: Double, locale: Locale,
                                dictation: Bool, relay: ProgressRelay) async throws -> [TranscriptPhrase] {
        let module: any SpeechModule = dictation
            ? DictationTranscriber(locale: locale, contentHints: [], transcriptionOptions: [.punctuation],
                                   reportingOptions: [], attributeOptions: [.audioTimeRange])
            : SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
        try await installModel(for: module, locale: locale, relay: relay)
        try Task.checkCancellation()
        relay.send(.listening(0))

        let format = monoFormat(like: await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]))
        let analyzer = SpeechAnalyzer(modules: [module])
        await analyzer.setVolatileRangeChangedHandler { range, _, _ in
            relay.listened(range.end.seconds / max(duration, 0.1))
        }
        let (inputs, feed) = AsyncStream<AnalyzerInput>.makeStream()
        let reader = Task.detached(priority: .userInitiated) {
            defer { feed.finish() }
            try readAudio(of: asset, track: track, duration: duration, format: format) { buffer in
                feed.yield(AnalyzerInput(buffer: buffer))
            }
        }
        let collector: Task<[TranscriptPhrase], Error>
        if let transcriber = module as? SpeechTranscriber {
            collector = Task { try await collect(transcriber.results, duration: duration, relay: relay) }
        } else if let transcriber = module as? DictationTranscriber {
            collector = Task { try await collect(transcriber.results, duration: duration, relay: relay) }
        } else {
            throw Failure.failed
        }
        return try await withTaskCancellationHandler {
            do {
                if let last = try await analyzer.analyzeSequence(inputs) {
                    try await analyzer.finalizeAndFinish(through: last)
                } else {
                    await analyzer.cancelAndFinishNow()
                }
                try await reader.value
                try Task.checkCancellation()
                return try await collector.value
            } catch {
                #if DEBUG
                CaptionsTrace.note("SpeechAnalyzer stopped: \(error)")
                #endif
                reader.cancel()
                collector.cancel()
                await analyzer.cancelAndFinishNow()
                if error is CancellationError || Task.isCancelled { throw CancellationError() }
                if let failure = error as? Failure { throw failure }
                if let speechError = error as? SFSpeechError {
                    switch speechError.code {
                    case .noModel, .assetLocaleNotAllocated, .tooManyAssetLocalesAllocated, .cannotAllocateUnsupportedLocale:
                        throw Failure.unavailable
                    default:
                        break
                    }
                }
                throw Failure.failed
            }
        } onCancel: {
            reader.cancel()
            Task { await analyzer.cancelAndFinishNow() }
        }
    }

    /// Downloads the language's speech model the first time (Apple's
    /// download, no audio involved), with progress.
    @available(iOS 26.0, *)
    private static func installModel(for module: any SpeechModule, locale: Locale, relay: ProgressRelay) async throws {
        // Apps reserve the languages they use, a few at most; the oldest
        // reservation makes room for a new one.
        let reserved = await AssetInventory.reservedLocales
        if !reserved.contains(where: { bcp47($0) == bcp47(locale) }) {
            if reserved.count >= AssetInventory.maximumReservedLocales, let oldest = reserved.first {
                await AssetInventory.release(reservedLocale: oldest)
            }
            _ = try? await AssetInventory.reserve(locale: locale)
        }
        let request: AssetInstallationRequest?
        do {
            request = try await AssetInventory.assetInstallationRequest(supporting: [module])
        } catch {
            #if DEBUG
            CaptionsTrace.note("asset request: \(error)")
            #endif
            // Apps can keep only a few languages; make room and ask again.
            for reserved in await AssetInventory.reservedLocales where reserved != locale {
                await AssetInventory.release(reservedLocale: reserved)
            }
            guard let retry = try? await AssetInventory.assetInstallationRequest(supporting: [module]) else { throw Failure.unavailable }
            request = retry
        }
        guard let request else { return }
        relay.send(.downloading(0))
        let watcher = Task {
            while !Task.isCancelled {
                relay.send(.downloading(request.progress.fractionCompleted))
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        defer { watcher.cancel() }
        do {
            try await request.downloadAndInstall()
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw Failure.downloadFailed
        }
    }

    @available(iOS 26.0, *)
    private static func collect<Results: AsyncSequence>(_ results: Results, duration: Double,
                                                        relay: ProgressRelay) async throws -> [TranscriptPhrase] where Results.Element: RecognizedSpeech {
        var phrases: [TranscriptPhrase] = []
        for try await result in results {
            let text = result.text
            var pieces: [TranscriptPiece] = []
            for run in text.runs {
                let piece = String(text[run.range].characters)
                if let range = run.audioTimeRange, range.start.isNumeric, range.end.isNumeric {
                    pieces.append(TranscriptPiece(text: piece, start: range.start.seconds, end: range.end.seconds))
                } else {
                    pieces.append(TranscriptPiece(text: piece))
                }
            }
            var phrase = TranscriptPhrase(pieces: pieces)
            let plain = String(text.characters)
            if phrase.words.isEmpty, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               result.range.start.isNumeric, result.range.end.isNumeric {
                phrase = TranscriptPhrase(text: plain, start: result.range.start.seconds, end: result.range.end.seconds)
            }
            phrases.append(phrase)
            if result.range.end.isNumeric { relay.listened(result.range.end.seconds / max(duration, 0.1)) }
        }
        return phrases
    }

    /// Mono, in the sample type and rate the analyzer prefers.
    private static func monoFormat(like preferred: AVAudioFormat?) -> AVAudioFormat {
        if let preferred, preferred.channelCount == 1, [.pcmFormatInt16, .pcmFormatFloat32].contains(preferred.commonFormat) {
            return preferred
        }
        let rate = preferred?.sampleRate ?? 16_000
        let common: AVAudioCommonFormat = preferred?.commonFormat == .pcmFormatInt16 ? .pcmFormatInt16 : .pcmFormatFloat32
        return AVAudioFormat(commonFormat: common, sampleRate: rate, channels: 1, interleaved: false)
            ?? AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
    }

    // MARK: SFSpeechRecognizer on the device (iOS 17–25)

    private static func recognizeOnDevice(_ asset: AVAsset, track: AVAssetTrack, duration: Double, locale: Locale,
                                          relay: ProgressRelay) async throws -> [TranscriptPhrase] {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.supportsOnDeviceRecognition else {
            throw Failure.unavailable
        }
        try await authorize()
        guard recognizer.isAvailable else { throw Failure.unavailable }
        // Results arrive off the main thread.
        recognizer.queue = OperationQueue()
        relay.send(.listening(0))

        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false) else {
            throw Failure.failed
        }
        let reading = Task.detached(priority: .userInitiated) {
            var samples: [Float] = []
            samples.reserveCapacity(Int(duration * format.sampleRate))
            try readAudio(of: asset, track: track, duration: duration, format: format) { buffer in
                guard let channel = buffer.floatChannelData?[0] else { return }
                samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            }
            return samples
        }
        let samples = try await withTaskCancellationHandler { try await reading.value } onCancel: { reading.cancel() }
        try Task.checkCancellation()

        // Long clips go in parts of under a minute, cut where it's quietest.
        let window = 0.05
        let perWindow = Int(format.sampleRate * window)
        let levels = stride(from: 0, to: samples.count, by: perWindow).map { start -> Double in
            let part = samples[start..<min(start + perWindow, samples.count)]
            let power = part.reduce(0) { $0 + Double($1 * $1) } / Double(max(part.count, 1))
            return 20 * log10(max(sqrt(power), 1e-6))
        }
        let parts = SpeechChunks.ranges(levels: levels, window: window)
        var phrases: [TranscriptPhrase] = []
        for part in parts {
            let lower = min(samples.count, Int(part.lowerBound * format.sampleRate))
            let upper = min(samples.count, Int(part.upperBound * format.sampleRate))
            guard upper > lower else { continue }
            let length = part.upperBound - part.lowerBound
            phrases += try await recognize(samples[lower..<upper], offset: part.lowerBound, format: format, recognizer: recognizer) { fraction in
                relay.listened((part.lowerBound + fraction * length) / max(duration, 0.1))
            }
        }
        return phrases
    }

    private static func authorize() async throws {
        var status = SFSpeechRecognizer.authorizationStatus()
        if status == .notDetermined {
            status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
        }
        guard status == .authorized else { throw Failure.notAllowed }
    }

    private static func recognize(_ samples: ArraySlice<Float>, offset: Double, format: AVAudioFormat, recognizer: SFSpeechRecognizer,
                                  onProgress: @escaping @Sendable (Double) -> Void) async throws -> [TranscriptPhrase] {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        let length = Double(samples.count) / format.sampleRate
        let pending = PendingRecognition()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending.start(continuation)
                let task = recognizer.recognitionTask(with: request) { result, error in
                    if let result {
                        let transcription = result.bestTranscription
                        if result.isFinal {
                            let segments = transcription.segments.map { segment in
                                (range: segment.substringRange.location..<(segment.substringRange.location + segment.substringRange.length),
                                 start: offset + segment.timestamp, end: offset + segment.timestamp + segment.duration)
                            }
                            pending.finish(.success([TranscriptPhrase(text: transcription.formattedString, segments: segments)]))
                        } else if let last = transcription.segments.last {
                            onProgress(min(1, (last.timestamp + last.duration) / max(length, 0.1)))
                        }
                    }
                    if let error {
                        let code = (error as NSError).code
                        #if DEBUG
                        CaptionsTrace.note("SFSpeechRecognizer: \(error)")
                        #endif
                        let domain = (error as NSError).domain
                        if domain == "kAFAssistantErrorDomain", code == 1110 {
                            // "No speech detected": not a failure, just no captions.
                            pending.finish(.success([]))
                        } else if domain == "kLSRErrorDomain", code == 300 || code == 201 {
                            // No recognizer model on this device, or dictation is off.
                            pending.finish(.failure(Failure.unavailable))
                        } else {
                            pending.finish(.failure(Failure.failed))
                        }
                    }
                }
                pending.attach(task)
                var start = samples.startIndex
                let step = Int(format.sampleRate / 2)
                while start < samples.endIndex {
                    let end = min(start + step, samples.endIndex)
                    if let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(end - start)),
                       let channel = buffer.floatChannelData?[0] {
                        buffer.frameLength = AVAudioFrameCount(end - start)
                        samples[start..<end].withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: end - start) }
                        request.append(buffer)
                    }
                    start = end
                }
                request.endAudio()
            }
        } onCancel: {
            pending.cancel()
        }
    }

    // MARK: Reading audio

    /// The clip's sound from 0 to `duration`, converted to `format`, one
    /// buffer at a time.
    private static func readAudio(of asset: AVAsset, track: AVAssetTrack, duration: Double, format: AVAudioFormat,
                                  onBuffer: (AVAudioPCMBuffer) -> Void) throws {
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: duration, preferredTimescale: 600))
        let isInteger = format.commonFormat == .pcmFormatInt16
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: isInteger ? 16 : 32,
            AVLinearPCMIsFloatKey: !isInteger,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? Failure.failed }
        defer { if reader.status == .reading { reader.cancelReading() } }
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            let frames = CMSampleBufferGetNumSamples(sample)
            guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else { continue }
            buffer.frameLength = AVAudioFrameCount(frames)
            guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList) == noErr else { continue }
            onBuffer(buffer)
        }
        if reader.status == .failed { throw reader.error ?? Failure.failed }
    }
}

#if DEBUG
/// QA trace of automatic captions: the log, standard error, and
/// `glowlit-captions.log` in the app's tmp folder (the simulator script reads it).
enum CaptionsTrace {
    static func note(_ message: String) {
        NSLog("[captions] %@", message)
        FileHandle.standardError.write(Data("[captions] \(message)\n".utf8))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("glowlit-captions.log")
        let line = Data((message + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: url)
        }
    }
}
#endif

/// SpeechTranscriber and DictationTranscriber results alike.
@available(iOS 26.0, *)
private protocol RecognizedSpeech {
    var text: AttributedString { get }
    var range: CMTimeRange { get }
}

@available(iOS 26.0, *)
extension SpeechTranscriber.Result: RecognizedSpeech {}

@available(iOS 26.0, *)
extension DictationTranscriber.Result: RecognizedSpeech {}

/// Hands progress to the main actor from the recognizers' threads, only when
/// it moved by a percent, and never backwards.
private final class ProgressRelay: @unchecked Sendable {
    private let handler: @MainActor (CaptionTranscriber.Progress) -> Void
    private let lock = NSLock()
    private var listenedSoFar = -1.0

    init(_ handler: @escaping @MainActor (CaptionTranscriber.Progress) -> Void) {
        self.handler = handler
    }

    func send(_ progress: CaptionTranscriber.Progress) {
        let handler = handler
        Task { @MainActor in handler(progress) }
    }

    func listened(_ fraction: Double) {
        guard fraction.isFinite else { return }
        let value = min(max(fraction, 0), 1)
        lock.lock()
        guard value >= listenedSoFar + 0.01 else { lock.unlock(); return }
        listenedSoFar = value
        lock.unlock()
        send(.listening(value))
    }
}

/// One SFSpeechRecognizer task and its continuation, resumed exactly once.
private final class PendingRecognition: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[TranscriptPhrase], Error>?
    private var task: SFSpeechRecognitionTask?
    private var cancelled = false

    func start(_ continuation: CheckedContinuation<[TranscriptPhrase], Error>) {
        lock.lock()
        defer { lock.unlock() }
        if cancelled {
            continuation.resume(throwing: CancellationError())
        } else {
            self.continuation = continuation
        }
    }

    func attach(_ task: SFSpeechRecognitionTask) {
        lock.lock()
        let cancelNow = cancelled
        self.task = task
        lock.unlock()
        if cancelNow { task.cancel() }
    }

    func finish(_ result: Result<[TranscriptPhrase], Error>) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let task = task
        lock.unlock()
        task?.cancel()
        finish(.failure(CancellationError()))
    }
}
