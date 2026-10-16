import Vision
import CoreImage
import QuartzCore
import AppCore

/// Finds faces for Glow Cam's live makeup tint: Vision's face landmarks a few
/// times a second on a small copy of the frame, on a queue of its own (frames
/// never wait for it), smoothed in between (`FaceTrackSmoother`) and paced so
/// the camera stays smooth (`MakeupTintPacing`). Nothing leaves the device.
final class GlowFaceTracker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.glowlit.retrocam.faces", qos: .userInitiated)
    private let lock = NSLock()
    private var smoother = FaceTrackSmoother()
    private var pacing = MakeupTintPacing()
    /// Bumped by `reset()`, so a look still on its way from before is dropped.
    private var generation = 0

    /// On the frame queue: starts a look at `frame` when it's time.
    func look(at frame: CIImage, seconds: Double) {
        let generation: Int? = lock.withLock { pacing.shouldDetect(at: seconds) ? self.generation : nil }
        guard let generation else { return }
        queue.async { [self] in
            let started = CACurrentMediaTime()
            let faces = Self.landmarks(in: frame, maxPixel: 640)
            let duration = CACurrentMediaTime() - started
            lock.withLock {
                guard generation == self.generation else { return }
                pacing.detectionFinished(duration: duration)
                // Seen as of now (the frames' clock), and kept until a look or two
                // later however slow Vision is.
                smoother.grace = max(0.35, 2 * pacing.interval)
                smoother.update(faces, at: seconds + duration)
            }
        }
    }

    /// The faces to tint at `seconds`, in fractions of the frame (y up).
    func faces(at seconds: Double) -> [FaceTrackSmoother.Face] {
        lock.withLock { smoother.advance(to: seconds) }
    }

    /// A tinted frame took `duration` to draw; true once the tint should pause.
    func frameDrawn(at seconds: Double, duration: Double) -> Bool {
        lock.withLock {
            pacing.frameDrawn(at: seconds, duration: duration)
            return pacing.isPaused
        }
    }

    /// The device is running hot.
    func pause() {
        lock.withLock { pacing.pause() }
    }

    /// Starts over: the tint was turned on again, or the camera changed.
    func reset() {
        lock.withLock {
            generation += 1
            smoother.reset()
            pacing = MakeupTintPacing()
        }
    }

    /// Up to four faces' landmarks in fractions of `image` (y up, like Core
    /// Image), biggest first. Vision gets a copy at most `maxPixel` on its
    /// long edge.
    static func landmarks(in image: CIImage, maxPixel: CGFloat) -> [FaceLandmarks] {
        #if DEBUG
        // The Simulator's Vision can't find landmarks: captures use ones found on a Mac.
        if let saved = RetroCamFixture.savedLandmarks { return saved }
        #endif
        let extent = image.extent
        guard !extent.isInfinite, extent.width >= 1, extent.height >= 1 else { return [] }
        let scale = min(1, maxPixel / max(extent.width, extent.height))
        let small = image
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(ciImage: small, orientation: .up, options: [.ciContext: ImageFilters.context])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        func area(_ face: VNFaceObservation) -> CGFloat { face.boundingBox.width * face.boundingBox.height }
        return (request.results ?? [])
            // Faces far in the background aren't worth a tint.
            .filter { area($0) > 0.003 }
            .sorted { area($0) > area($1) }
            .prefix(FaceTrackSmoother.maxFaces)
            .compactMap(landmarks(of:))
    }

    private static func landmarks(of face: VNFaceObservation) -> FaceLandmarks? {
        guard let marks = face.landmarks, let lips = marks.outerLips, let left = marks.leftEye, let right = marks.rightEye else { return nil }
        let box = face.boundingBox
        // Vision's points are fractions of the face's box; these are fractions of the image.
        func points(_ region: VNFaceLandmarkRegion2D?) -> [FacePoint] {
            (region?.normalizedPoints ?? []).map {
                FacePoint(x: Double(box.minX + $0.x * box.width), y: Double(box.minY + $0.y * box.height))
            }
        }
        return FaceLandmarks(outerLips: points(lips), innerLips: points(marks.innerLips), leftEye: points(left),
                             rightEye: points(right), nose: points(marks.nose), faceContour: points(marks.faceContour))
    }
}

