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
    /// Empty when the clip has no sound.
    static func loudness(of asset: AVAsset) async throws -> [Double] {
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return [] }
        return try await Task.detached(priority: .userInitiated) {
            let reader = try AVAssetReader(asset: asset)
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

    /// Colours every frame with the effect (and its date stamp). Nil = no effect.
    static func videoComposition(for asset: AVAsset, effect: RetroEffect?, dateStamp: Bool) async throws -> AVVideoComposition? {
        guard let effect else { return nil }
        let overlays = StampCache(effect: dateStamp ? effect : nil)
        return try await AVMutableVideoComposition.videoComposition(with: asset) { request in
            let source = request.sourceImage.clampedToExtent().cropped(to: request.sourceImage.extent)
            var frame = effect.grade(source).cropped(to: source.extent)
            if let stamp = overlays.overlay(for: source.extent) {
                frame = stamp.composited(over: frame)
            }
            request.finish(with: frame, context: nil)
        }
    }

    /// Date stamps are drawn once per frame size, not every frame.
    private final class StampCache: @unchecked Sendable {
        private let effect: RetroEffect?
        private var cached: (CGRect, CIImage)?
        private let lock = NSLock()

        init(effect: RetroEffect?) { self.effect = effect }

        func overlay(for extent: CGRect) -> CIImage? {
            guard let effect else { return nil }
            lock.lock()
            defer { lock.unlock() }
            if let cached, cached.0 == extent { return cached.1 }
            guard let layer = effect.videoStampOverlay(size: extent.size)?
                .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY)) else { return nil }
            cached = (extent, layer)
            return layer
        }
    }

    // MARK: Export

    static func export(_ asset: AVAsset, videoComposition: AVVideoComposition?) async throws -> URL {
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw VideoError.exportFailed
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Glowlit-\(UUID().uuidString.prefix(6)).mp4")
        session.videoComposition = videoComposition
        session.shouldOptimizeForNetworkUse = true
        if #available(iOS 18.0, *) {
            try await session.export(to: url, as: .mp4)
        } else {
            session.outputURL = url
            session.outputFileType = .mp4
            await withCheckedContinuation { continuation in
                session.exportAsynchronously { continuation.resume() }
            }
            guard session.status == .completed else { throw session.error ?? VideoError.exportFailed }
        }
        return url
    }

    static func saveToPhotos(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw PhotoLibrarySaver.SaveError.denied }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: nil)
        }
    }
}
