import AVFoundation
import CoreImage
import Photos
import SwiftUI
import UniformTypeIdentifiers
import AppCore

/// A video picked from Photos, copied to a temporary file we own.
struct VideoFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { file in
            SentTransferredFile(file.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("glowlit-\(UUID().uuidString)")
                .appendingPathExtension(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: copy)
            // The copy keeps the original's date; the launch sweep of old tmp
            // files must see it as new.
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: copy.path)
            return VideoFile(url: copy)
        }
    }
}

/// The simple video editor's engine, all on the device with AVFoundation:
/// read loudness for "Auto-cut silences", stitch the kept parts, colour every
/// frame with a retro effect, and export. Nothing is uploaded.
enum VideoEngine {
    enum VideoError: LocalizedError {
        case noVideo
        case exportFailed

        var errorDescription: String? {
            switch self {
            case .noVideo: return String(localized: "That file doesn't have a video track.")
            case .exportFailed: return String(localized: "Couldn't save the video. Please try again.")
            }
        }
    }

    /// Longest clip the editor takes, to keep exports quick on the phone.
    static let maxDuration: Double = 5 * 60
    /// Loudness window for silence detection.
    static let levelWindow: Double = 0.05

    // MARK: Reading

    static func duration(of asset: AVAsset) async throws -> Double {
        try await asset.load(.duration).seconds
    }

    static func thumbnail(of asset: AVAsset, at seconds: Double = 0.1, maxSize: CGFloat = 600) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxSize, height: maxSize)
        guard let image = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image else { return nil }
        return UIImage(cgImage: image)
    }

    /// Loudness (dBFS) per `levelWindow`, from a mono 16 kHz copy of the audio.
    /// Empty when the clip has no sound. Only the first `maxDuration` counts,
    /// like everywhere else in the editor.
    static func loudness(of asset: AVAsset) async throws -> [Double] {
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return [] }
        return try await Task.detached(priority: .userInitiated) {
            let reader = try AVAssetReader(asset: asset)
            reader.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: maxDuration, preferredTimescale: 600))
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
                AVNumberOfChannelsKey: 1,
                AVSampleRateKey: 16_000,
            ])
            reader.add(output)
            guard reader.startReading() else { return [] }
            let perWindow = Int(16_000 * levelWindow)
            var levels: [Double] = []
            var sum = 0.0
            var count = 0
            while let buffer = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buffer) {
                let length = CMBlockBufferGetDataLength(block)
                var samples = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: &samples)
                for sample in samples {
                    sum += Double(sample * sample)
                    count += 1
                    if count == perWindow {
                        levels.append(20 * log10(max(sqrt(sum / Double(count)), 1e-6)))
                        sum = 0
                        count = 0
                    }
                }
            }
            return levels
        }.value
    }

    // MARK: Building

    /// Stitches the kept time ranges (seconds) of the clip, video and sound.
    static func composition(of asset: AVAsset, keeping ranges: [ClosedRange<Double>]) async throws -> AVMutableComposition {
        let composition = AVMutableComposition()
        guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else { throw VideoError.noVideo }
        let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first
        let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let audioTrack = sourceAudio == nil ? nil : composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        videoTrack?.preferredTransform = try await sourceVideo.load(.preferredTransform)
        let total = try await asset.load(.duration)

        var cursor = CMTime.zero
        for range in ranges {
            let start = CMTime(seconds: range.lowerBound, preferredTimescale: 600)
            let end = CMTimeMinimum(CMTime(seconds: range.upperBound, preferredTimescale: 600), total)
            guard end > start else { continue }
            let timeRange = CMTimeRange(start: start, end: end)
            try videoTrack?.insertTimeRange(timeRange, of: sourceVideo, at: cursor)
            if let audioTrack, let sourceAudio {
                try? audioTrack.insertTimeRange(timeRange, of: sourceAudio, at: cursor)
            }
            cursor = cursor + timeRange.duration
        }
        return composition
    }

    /// Colours every frame with the effect and, when `showsExtra` is on, its
    /// overlay (date stamp, letterbox or camcorder display). Nil = no effect.
    /// `fps` sets the camcorder timecode's frame count.
    static func videoComposition(for asset: AVAsset, effect: RetroEffect?, showsExtra: Bool, fps: Double = 30) async throws -> AVVideoComposition? {
        guard let effect else { return nil }
        let overlays = OverlayCache(effect: showsExtra && effect.option?.worksOnVideo == true ? effect : nil)
        let rate = CamcorderClock.frameRate(fps)
        return try await AVMutableVideoComposition.videoComposition(with: asset) { request in
            let source = request.sourceImage.clampedToExtent().cropped(to: request.sourceImage.extent)
            var frame = effect.grade(source).cropped(to: source.extent)
            if let overlay = overlays.overlay(for: source.extent) {
                frame = overlay.composited(over: frame)
            }
            // The output timeline's time, so the preview and the export match.
            if let camcorder = overlays.camcorder(for: source.extent) {
                frame = camcorder.composite(over: frame, seconds: request.compositionTime.seconds, fps: rate)
            }
            request.finish(with: frame, context: nil)
        }
    }

    /// Frame rate of the clip's video track, for the camcorder timecode.
    static func frameRate(of asset: AVAsset) async -> Double {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let rate = try? await track.load(.nominalFrameRate) else { return 30 }
        return CamcorderClock.frameRate(Double(rate))
    }

    /// Overlays are drawn once per frame size, not every frame.
    private struct ExportCanceller: @unchecked Sendable {
        let session: AVAssetExportSession
        func cancel() { session.cancelExport() }
    }

    private final class OverlayCache: @unchecked Sendable {
        private let effect: RetroEffect?
        private var cached: (CGRect, CIImage?)?
        private var parts: (CGRect, CamcorderChrome.VideoParts)?
        private let lock = NSLock()

        init(effect: RetroEffect?) { self.effect = effect }

        func overlay(for extent: CGRect) -> CIImage? {
            guard let effect else { return nil }
            lock.lock()
            defer { lock.unlock() }
            if let cached, cached.0 == extent { return cached.1 }
            let layer = effect.videoOverlay(size: extent.size)?
                .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            cached = (extent, layer)
            return layer
        }

        func camcorder(for extent: CGRect) -> CamcorderChrome.VideoParts? {
            guard effect?.option == .cameraInfo else { return nil }
            lock.lock()
            defer { lock.unlock() }
            if let parts, parts.0 == extent { return parts.1 }
            let made = CamcorderChrome.VideoParts(size: extent.size)
            parts = (extent, made)
            return made
        }
    }

    // MARK: Export

    /// Renders `asset` into a temporary .mp4, reporting progress (0…1) on the
    /// main actor. Cancelling the calling task stops the export, throws
    /// `CancellationError` and leaves no file behind.
    static func export(_ asset: AVAsset, videoComposition: AVVideoComposition?, progress: @escaping @MainActor (Double) -> Void = { _ in }) async throws -> URL {
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw VideoError.exportFailed
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Glowlit-\(UUID().uuidString.prefix(6)).mp4")
        session.videoComposition = videoComposition
        session.shouldOptimizeForNetworkUse = true
        do {
            if #available(iOS 18.0, *) {
                let watcher = Task {
                    for await state in session.states(updateInterval: 0.1) {
                        if case .exporting(let done) = state { await progress(done.fractionCompleted) }
                    }
                }
                defer { watcher.cancel() }
                // Throws CancellationError when the task is cancelled.
                try await session.export(to: url, as: .mp4)
            } else {
                session.outputURL = url
                session.outputFileType = .mp4
                let poller = Task {
                    while !Task.isCancelled {
                        await progress(Double(session.progress))
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                }
                defer { poller.cancel() }
                // cancelExport() is safe from any thread; the box only tells
                // the compiler so for the @Sendable cancellation handler.
                let canceller = ExportCanceller(session: session)
                await withTaskCancellationHandler {
                    await withCheckedContinuation { continuation in
                        session.exportAsynchronously { continuation.resume() }
                    }
                } onCancel: {
                    canceller.cancel()
                }
                if session.status == .cancelled { throw CancellationError() }
                guard session.status == .completed else { throw session.error ?? VideoError.exportFailed }
            }
        } catch {
            try? FileManager.default.removeItem(at: url)
            // A stopped export isn't a failure to report.
            if (error as? AVError)?.code == .operationCancelled { throw CancellationError() }
            throw error
        }
        await progress(1)
        return url
    }

    /// True when iOS stopped the export because the app left the foreground:
    /// the GPU and the video encoder don't run in the background.
    static func isInterruption(_ error: Error) -> Bool {
        (error as? AVError)?.code == .operationInterrupted
    }

    /// "Add only" Photos access, asked before a long export so the work isn't
    /// wasted when she says no.
    static func requestPhotosAccess() async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw PhotoLibrarySaver.SaveError.denied }
    }

    static func saveToPhotos(_ url: URL) async throws {
        try await requestPhotosAccess()
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: nil)
        }
    }
}
