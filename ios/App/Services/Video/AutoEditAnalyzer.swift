import AVFoundation
import CoreGraphics
import CoreML
import Vision
import AppCore

/// Looks at a clip for Auto edit, on the device: small frames a few times a
/// second (never every frame), where her face or upper body is for the
/// vertical window, and how much the picture changes for picking the
/// liveliest parts. Nothing leaves the device.
enum AutoEditAnalyzer {
    struct Result: Sendable {
        var framing: [FramingSample]
        var motion: [AutoEditPlanner.Sample]
        var presence: [AutoEditPlanner.Sample]
        /// The frame as it's shown (after its rotation), in pixels.
        var sourceSize: CGSize
    }

    /// At most this many looks, however long the clip.
    static let maxLooks = 240

    /// `progress` (0…1) is reported on the main actor. Cancelling the
    /// calling task stops it.
    static func analyze(_ asset: AVAsset, duration: Double, progress: @escaping @MainActor (Double) -> Void) async throws -> Result {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw VideoEngine.VideoError.noVideo }
        let (natural, transform) = try await track.load(.naturalSize, .preferredTransform)
        let shown = natural.applying(transform)
        let sourceSize = CGSize(width: abs(shown.width), height: abs(shown.height))
        let step = max(0.5, duration / Double(maxLooks))
        let times = stride(from: min(0.1, duration / 2), to: duration, by: step).map { CMTime(seconds: $0, preferredTimescale: 600) }
        guard !times.isEmpty else { return Result(framing: [], motion: [], presence: [], sourceSize: sourceSize) }

        let work = Task.detached(priority: .userInitiated) { () throws -> Result in
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 320, height: 320)
            // Near enough is fine, and much faster than the exact frame.
            let tolerance = CMTime(seconds: step / 2, preferredTimescale: 600)
            generator.requestedTimeToleranceBefore = tolerance
            generator.requestedTimeToleranceAfter = tolerance

            var result = Result(framing: [], motion: [], presence: [], sourceSize: sourceSize)
            var previous: [UInt8]?
            var looked = 0
            for await answer in generator.images(for: times) {
                try Task.checkCancellation()
                looked += 1
                if looked % 4 == 0 {
                    let done = Double(looked) / Double(times.count)
                    await progress(done)
                }
                guard case let .success(_, image, actual) = answer else { continue }
                let time = actual.seconds
                let center = subjectCenter(in: image)
                result.framing.append(FramingSample(time: time, center: center))
                result.presence.append(AutoEditPlanner.Sample(time: time, value: center == nil ? 0 : 1))
                let grays = grays(of: image)
                if let previous {
                    result.motion.append(AutoEditPlanner.Sample(time: time, value: difference(previous, grays)))
                }
                previous = grays
            }
            return result
        }
        return try await withTaskCancellationHandler {
            try await work.value
        } onCancel: {
            work.cancel()
        }
    }

    /// The centre across the frame (0…1) of the biggest face, else of the
    /// biggest upper body; nil when nobody's there.
    static func subjectCenter(in image: CGImage) -> Double? {
        let faces = VNDetectFaceRectanglesRequest()
        let bodies = VNDetectHumanRectanglesRequest()
        bodies.upperBodyOnly = true
        #if targetEnvironment(simulator)
        // The Simulator has no Neural Engine or GPU inference: the CPU, for QA.
        for request in [faces, bodies] as [VNRequest] {
            if let cpu = (try? request.supportedComputeStageDevices[.main])??.first(where: {
                if case .cpu = $0 { return true }
                return false
            }) {
                request.setComputeDevice(cpu, for: .main)
            }
        }
        #endif
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([faces, bodies])
        } catch {
            #if DEBUG
            AutoEditTrace.note("Vision: \(error)")
            #endif
        }
        func area(_ box: CGRect) -> CGFloat { box.width * box.height }
        if let face = faces.results?.filter({ $0.confidence > 0.5 }).max(by: { area($0.boundingBox) < area($1.boundingBox) }) {
            return Double(face.boundingBox.midX)
        }
        if let body = bodies.results?.filter({ $0.confidence > 0.5 }).max(by: { area($0.boundingBox) < area($1.boundingBox) }) {
            return Double(body.boundingBox.midX)
        }
        return nil
    }

    /// A 32 × 32 grey thumbnail, to compare looks.
    static func grays(of image: CGImage) -> [UInt8] {
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        return pixels
    }

    /// How much the picture changed: the mean difference of the greys, 0…1.
    static func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var sum = 0
        for index in a.indices {
            sum += abs(Int(a[index]) - Int(b[index]))
        }
        return Double(sum) / Double(a.count) / 255
    }
}

#if DEBUG
/// QA reads what Auto edit decided from `tmp/autoedit.log` in the app's container
/// (the Simulator's unified log hides the app's messages).
enum AutoEditTrace {
    private static let lock = NSLock()

    static func note(_ message: String) {
        NSLog("[autoedit] %@", message)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("autoedit.log")
        lock.withLock {
            let line = Data((message + "\n").utf8)
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: line)
            } else {
                try? line.write(to: url)
            }
        }
    }
}
#endif
