#if DEBUG
import AVFoundation
import UIKit

extension ScreenshotFixtures {
    /// A synthetic 9:16 clip for the `video` scene, so QA never needs a real
    /// video: the golden landscape panning, a bouncing dot and the source time
    /// printed on every frame (to compare with the camcorder timecode), over a
    /// tone with quiet gaps for "Auto-cut silences". `broken` writes a file
    /// AVFoundation can't open.
    static func sampleVideo(seconds: Double, broken: Bool) async throws -> URL {
        let folder = FileManager.default.temporaryDirectory
        let output = folder.appendingPathComponent("glowlit-sample-\(UUID().uuidString).mov")
        if broken {
            try Data("This is not a video.".utf8).write(to: output)
            return output
        }
        return try await Task.detached(priority: .userInitiated) {
            let video = folder.appendingPathComponent("glowlit-sample-video.mov")
            let audio = folder.appendingPathComponent("glowlit-sample-audio.caf")
            defer {
                try? FileManager.default.removeItem(at: video)
                try? FileManager.default.removeItem(at: audio)
            }
            try? FileManager.default.removeItem(at: video)
            try? FileManager.default.removeItem(at: audio)
            try await writeFrames(to: video, seconds: seconds)
            try writeTone(to: audio, seconds: seconds)
            try await combine(video: video, audio: audio, into: output)
            return output
        }.value
    }

    private static func writeFrames(to url: URL, seconds: Double) async throws {
        // Long clips only need to exist, not to look smooth.
        let isLong = seconds > 30
        let size = isLong ? CGSize(width: 270, height: 480) : CGSize(width: 540, height: 960)
        let fps: Int32 = isLong ? 1 : 30
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let backdrop = goldenLandscape
        let fill = max(size.width / backdrop.size.width, size.height / backdrop.size.height)
        let drawn = CGSize(width: backdrop.size.width * fill, height: backdrop.size.height * fill)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 56, weight: .heavy),
            .foregroundColor: UIColor.white,
        ]

        for index in 0..<Int(seconds * Double(fps)) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            let time = Double(index) / Double(fps)
            let frame = renderer.image { _ in
                let pan = (drawn.width - size.width) * (0.5 + 0.45 * sin(time / 2))
                backdrop.draw(in: CGRect(x: -pan, y: (size.height - drawn.height) / 2, width: drawn.width, height: drawn.height))
                UIColor(red: 0.97, green: 0.76, blue: 0.85, alpha: 1).setFill()
                UIBezierPath(ovalIn: CGRect(x: size.width / 2 - 40, y: size.height * 0.62 + sin(time * 2) * 80, width: 80, height: 80)).fill()
                (String(format: "%.1f s", time) as NSString).draw(at: CGPoint(x: 40, y: size.height * 0.45), withAttributes: attributes)
            }
            guard let image = frame.cgImage, let pool = adaptor.pixelBufferPool,
                  let buffer = pixelBuffer(from: image, pool: pool) else { throw CocoaError(.fileWriteUnknown) }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }

    private static func pixelBuffer(from image: CGImage, pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var made: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
        guard let buffer = made else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                                width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer),
                                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        context?.draw(image, in: CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer)))
        return buffer
    }

    /// A soft 440 Hz tone; short clips go quiet from 35% to 60% of the way
    /// through, long ones for the last 4 s of every 20.
    private static func writeTone(to url: URL, seconds: Double) throws {
        let rate = 16_000.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else { throw CocoaError(.fileWriteUnknown) }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let total = Int(seconds * rate)
        var written = 0
        while written < total {
            let count = min(Int(rate), total - written)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
                  let samples = buffer.floatChannelData?[0] else { throw CocoaError(.fileWriteUnknown) }
            buffer.frameLength = AVAudioFrameCount(count)
            for offset in 0..<count {
                let time = Double(written + offset) / rate
                let quiet = seconds <= 30
                    ? (seconds * 0.35..<seconds * 0.6).contains(time)
                    : time.truncatingRemainder(dividingBy: 20) >= 16
                samples[offset] = quiet ? 0 : Float(0.25 * sin(2 * .pi * 440 * time))
            }
            try file.write(from: buffer)
            written += count
        }
    }

    private static func combine(video: URL, audio: URL, into output: URL) async throws {
        let videoAsset = AVURLAsset(url: video)
        let audioAsset = AVURLAsset(url: audio)
        guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
              let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first else { throw CocoaError(.fileReadCorruptFile) }
        let duration = try await videoAsset.load(.duration)
        let audioDuration = try await audioAsset.load(.duration)
        let composition = AVMutableComposition()
        try composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)?
            .insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: videoTrack, at: .zero)
        try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)?
            .insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(duration, audioDuration)), of: audioTrack, at: .zero)
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw CocoaError(.fileWriteUnknown)
        }
        session.outputURL = output
        session.outputFileType = .mov
        await withCheckedContinuation { continuation in
            session.exportAsynchronously { continuation.resume() }
        }
        guard session.status == .completed else { throw session.error ?? CocoaError(.fileWriteUnknown) }
    }
}
#endif
