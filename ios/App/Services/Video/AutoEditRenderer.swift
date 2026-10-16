import AVFoundation
import CoreImage
import ImageIO
import AppCore

/// An Auto edit stitched for playback and export: the kept parts back to
/// back on the main video track, the moments the crossfades borrow on a
/// second one, and the sound with a soft dip at each crossfade.
struct AutoEditBuild {
    let composition: AVMutableComposition
    let duration: CMTime
    let audioMix: AVAudioMix?
    let mainTrack: CMPersistentTrackID
    let handleTrack: CMPersistentTrackID
    /// The kept parts in source seconds, as inserted.
    let ranges: [ClosedRange<Double>]
    let transitions: [AutoEditTransition]
    /// The source frame as it's shown (after its rotation), in pixels.
    let sourceSize: CGSize
    let orientation: CGImagePropertyOrientation
    let fps: Double
}

/// The vertical Auto edit on the device: every frame is framed on her
/// (`FramingPath`), cut to 9:16 at 1080 × 1920, crossfaded where the cut
/// jumps, then styled like the plain editor's (`FrameStyler`). A custom
/// compositor, because a crossfade needs two frames at once.
enum AutoEditRenderer {
    static let renderSize = CGSize(width: SocialPlatform.frameWidth, height: SocialPlatform.frameHeight)

    static func build(_ asset: AVAsset, keeping ranges: [ClosedRange<Double>]) async throws -> AutoEditBuild {
        guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else { throw VideoEngine.VideoError.noVideo }
        let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first
        let (transform, naturalSize, nominalRate) = try await sourceVideo.load(.preferredTransform, .naturalSize, .nominalFrameRate)
        let total = try await asset.load(.duration)

        let composition = AVMutableComposition()
        guard let main = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let handle = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw VideoEngine.VideoError.exportFailed
        }
        let audio = sourceAudio == nil ? nil : composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        var kept: [ClosedRange<Double>] = []
        var cursor = CMTime.zero
        for range in ranges {
            let start = CMTime(seconds: range.lowerBound, preferredTimescale: 600)
            let end = CMTimeMinimum(CMTime(seconds: range.upperBound, preferredTimescale: 600), total)
            guard end > start else { continue }
            let timeRange = CMTimeRange(start: start, end: end)
            try main.insertTimeRange(timeRange, of: sourceVideo, at: cursor)
            if let audio, let sourceAudio {
                try? audio.insertTimeRange(timeRange, of: sourceAudio, at: cursor)
            }
            cursor = cursor + timeRange.duration
            kept.append(start.seconds...end.seconds)
        }
        guard cursor > .zero else { throw VideoEngine.VideoError.exportFailed }

        let transitions = AutoEditTimeline.transitions(keeping: kept, sourceDuration: total.seconds)
        var handleEnd = CMTime.zero
        var ramps: [(CMTimeRange, Float, Float)] = []
        for transition in transitions {
            let half = time(transition.half)
            let cut = time(transition.cut)
            if cut - half > handleEnd {
                handle.insertEmptyTimeRange(CMTimeRange(start: handleEnd, end: cut - half))
            }
            // The incoming part's lead-in before the cut, the outgoing part's run-out after it.
            try handle.insertTimeRange(CMTimeRange(start: time(transition.incomingStart) - half, duration: half), of: sourceVideo, at: cut - half)
            try handle.insertTimeRange(CMTimeRange(start: time(transition.outgoingEnd), duration: half), of: sourceVideo, at: cut)
            handleEnd = cut + half
            // A quick dip in the sound, so the jump doesn't click.
            let dip = time(0.08)
            ramps.append((CMTimeRange(start: cut - dip, duration: dip), 1, 0.15))
            ramps.append((CMTimeRange(start: cut, duration: dip), 0.15, 1))
        }

        // Without crossfades the second track stays empty: leave it out.
        if transitions.isEmpty { composition.removeTrack(handle) }

        var audioMix: AVAudioMix?
        if let audio, !ramps.isEmpty {
            let parameters = AVMutableAudioMixInputParameters(track: audio)
            for (range, from, to) in ramps {
                parameters.setVolumeRamp(fromStartVolume: from, toEndVolume: to, timeRange: range)
            }
            let mix = AVMutableAudioMix()
            mix.inputParameters = [parameters]
            audioMix = mix
        }

        let orientation = CGImagePropertyOrientation(videoTransform: transform)
        let turned = [CGImagePropertyOrientation.left, .right, .leftMirrored, .rightMirrored].contains(orientation)
        let shown = turned ? CGSize(width: naturalSize.height, height: naturalSize.width) : naturalSize
        return AutoEditBuild(composition: composition, duration: cursor, audioMix: audioMix,
                             mainTrack: main.trackID, handleTrack: handle.trackID, ranges: kept, transitions: transitions,
                             sourceSize: CGSize(width: abs(shown.width), height: abs(shown.height)), orientation: orientation,
                             fps: nominalRate > 0 ? Double(nominalRate) : 30)
    }

    /// How the build is drawn: framed on her, crossfaded, styled.
    static func videoComposition(for build: AutoEditBuild, framing: FramingPath, styler: FrameStyler) -> AVVideoComposition {
        let plan = AutoEditFramePlan(build: build, framing: framing, styler: styler, canvas: CGRect(origin: .zero, size: renderSize))
        var instructions: [AutoEditInstruction] = []
        var cursor = CMTime.zero
        for transition in build.transitions {
            let half = time(transition.half)
            let cut = time(transition.cut)
            if cut - half > cursor {
                instructions.append(AutoEditInstruction(CMTimeRange(start: cursor, end: cut - half), plan: plan))
            }
            instructions.append(AutoEditInstruction(CMTimeRange(start: cut - half, end: cut), plan: plan, transition: transition))
            instructions.append(AutoEditInstruction(CMTimeRange(start: cut, end: cut + half), plan: plan, transition: transition))
            cursor = cut + half
        }
        if build.duration > cursor {
            instructions.append(AutoEditInstruction(CMTimeRange(start: cursor, end: build.duration), plan: plan))
        }
        let composition = AVMutableVideoComposition()
        composition.customVideoCompositorClass = AutoEditCompositor.self
        composition.renderSize = renderSize
        composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(min(max(build.fps.rounded(), 24), 60)))
        // SDR, whatever the source: what every platform shows best.
        composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        composition.instructions = instructions
        return composition
    }

    private static func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }
}

/// What every frame of one Auto edit needs; shared by its instructions and
/// read on the compositor's threads.
final class AutoEditFramePlan: @unchecked Sendable {
    let mainTrack: CMPersistentTrackID
    let handleTrack: CMPersistentTrackID
    private let ranges: [ClosedRange<Double>]
    private let framing: FramingPath
    private let window: (width: Double, height: Double)
    private let orientation: CGImagePropertyOrientation
    private let styler: FrameStyler
    private let canvas: CGRect

    init(build: AutoEditBuild, framing: FramingPath, styler: FrameStyler, canvas: CGRect) {
        mainTrack = build.mainTrack
        handleTrack = build.handleTrack
        ranges = build.ranges
        self.framing = framing
        window = AutoFraming.window(sourceWidth: build.sourceSize.width, sourceHeight: build.sourceSize.height,
                                    aspect: canvas.width / canvas.height)
        orientation = build.orientation
        self.styler = styler
        self.canvas = canvas
    }

    /// The frame at the request's time on the edited timeline.
    func frame(for request: AVAsynchronousVideoCompositionRequest, transition: AutoEditTransition?) -> CIImage {
        let time = request.compositionTime.seconds
        var frame = request.sourceFrame(byTrackID: mainTrack).map {
            placed($0, at: CaptionTimeline.sourceTime(time, keeping: ranges))
        }
        if let transition, let buffer = request.sourceFrame(byTrackID: handleTrack) {
            let borrowed = placed(buffer, at: transition.handleTime(at: time))
            if let main = frame {
                // Before the cut the main track still shows the outgoing part; after it, the incoming one.
                let (from, to) = time < transition.cut ? (main, borrowed) : (borrowed, main)
                frame = from.applyingFilter("CIDissolveTransition", parameters: [
                    kCIInputTargetImageKey: to,
                    kCIInputTimeKey: transition.progress(at: time),
                ]).cropped(to: canvas)
            } else {
                frame = borrowed
            }
        }
        return styler.style(frame ?? CIImage(color: .black).cropped(to: canvas), seconds: time)
    }

    /// A source frame turned upright, cut to the 9:16 window around her at
    /// `sourceTime`, and scaled to fill the canvas.
    private func placed(_ buffer: CVPixelBuffer, at sourceTime: Double) -> CIImage {
        var image = CIImage(cvPixelBuffer: buffer).oriented(orientation)
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        let size = image.extent.size
        let width = size.width * window.width
        let height = size.height * window.height
        guard width > 1, height > 1 else { return image.cropped(to: canvas) }
        let x = min(max(CGFloat(framing.center(at: sourceTime)) * size.width - width / 2, 0), size.width - width)
        let y = (size.height - height) / 2
        // Clamped first, so the scaling never pulls in a transparent edge.
        return image.clampedToExtent()
            .transformed(by: CGAffineTransform(translationX: -x, y: -y)
                .concatenating(CGAffineTransform(scaleX: canvas.width / width, y: canvas.height / height)))
            .cropped(to: canvas)
    }
}

/// One stretch of the edited timeline: plain, or half of a crossfade.
final class AutoEditInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let plan: AutoEditFramePlan
    let transition: AutoEditTransition?

    init(_ timeRange: CMTimeRange, plan: AutoEditFramePlan, transition: AutoEditTransition? = nil) {
        self.timeRange = timeRange
        self.plan = plan
        self.transition = transition
        let tracks = transition == nil ? [plan.mainTrack] : [plan.mainTrack, plan.handleTrack]
        requiredSourceTrackIDs = tracks.map { NSNumber(value: $0) }
        super.init()
    }
}

/// Draws Auto edit frames with the app's shared Core Image context.
final class AutoEditCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    let sourcePixelBufferAttributes: [String: any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ]
    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ]
    /// The output is tagged Rec. 709 (`AutoEditRenderer.videoComposition`).
    private static let colorSpace = CGColorSpace(name: CGColorSpace.itur_709)

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        autoreleasepool {
            guard let instruction = request.videoCompositionInstruction as? AutoEditInstruction,
                  let output = request.renderContext.newPixelBuffer() else {
                request.finish(with: VideoEngine.VideoError.exportFailed)
                return
            }
            let image = instruction.plan.frame(for: request, transition: instruction.transition)
            ImageFilters.context.render(image, to: output,
                                        bounds: CGRect(origin: .zero, size: request.renderContext.size),
                                        colorSpace: Self.colorSpace)
            request.finish(withComposedVideoFrame: output)
        }
    }

    func cancelAllPendingVideoCompositionRequests() {}
}

extension CGImagePropertyOrientation {
    /// How a video track's preferred transform turns its frames upright.
    init(videoTransform transform: CGAffineTransform) {
        switch (transform.a.rounded(), transform.b.rounded(), transform.c.rounded(), transform.d.rounded()) {
        case (0, 1, -1, 0): self = .right
        case (0, -1, 1, 0): self = .left
        case (-1, 0, 0, -1): self = .down
        case (-1, 0, 0, 1): self = .upMirrored
        case (1, 0, 0, -1): self = .downMirrored
        default: self = .up
        }
    }
}
