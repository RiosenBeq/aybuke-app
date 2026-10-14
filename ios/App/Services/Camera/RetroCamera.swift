import AVFoundation
import CoreImage
import UIKit

/// What Retro Cam offers right now, for its controls.
struct RetroCamFeatures: Equatable, Sendable {
    var canSwitchCamera = false
    var hasFlash = false
}

/// Why the camera paused; it resumes by itself when the reason goes away.
enum RetroCamPause: Equatable, Sendable {
    case inUseElsewhere, multitasking, systemPressure, other

    var message: LocalizedStringResource {
        switch self {
        case .inUseElsewhere: return "Another app is using the camera."
        case .multitasking: return "The camera pauses while another app is open next to Glowlit."
        case .systemPressure: return "The camera paused to cool down. It will be back in a moment."
        case .other: return "The camera paused. It will be back in a moment."
        }
    }
}

/// Where Retro Cam's pictures come from: the camera or, in DEBUG builds
/// without one, demo art (`RetroCamFixture`).
protocol RetroCamSource: AnyObject {
    /// Live frames, upright and mirrored the way the photo will be, with the
    /// seconds since the camera started. Called on a background queue.
    var frameHandler: (@Sendable (CIImage, Double) -> Void)? { get set }
    /// Pauses (nil when it runs again), on the main actor.
    var pauseHandler: (@MainActor (RetroCamPause?) -> Void)? { get set }
    /// Sets up the camera the first time and starts it; nil when it can't.
    func start(previewLayer: CALayer) async -> RetroCamFeatures?
    func stop()
    func switchCamera() async -> RetroCamFeatures?
    /// A still of at most `maxPixel` on the long edge, upright, mirrored
    /// like the preview and in the preview's shape.
    func capture(flash: Bool, maxPixel: Int) async throws -> UIImage
}

enum RetroCam {
    /// The camera entries are hidden on a Mac without a camera (every iPhone
    /// and iPad has one).
    static let isAvailable: Bool = {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "GLCameraFixture") { return true }
        #endif
        #if targetEnvironment(macCatalyst)
        return RetroCamera.device(at: .unspecified) != nil
        #else
        return true
        #endif
    }()

    /// The camera, or nil without one. DEBUG builds use the demo-art fixture
    /// when there's no camera (the simulator) or with `-GLCameraFixture YES`.
    static func makeSource() async -> RetroCamSource? {
        let hasCamera = await Task.detached(priority: .userInitiated) { RetroCamera.device(at: .unspecified) != nil }.value
        #if DEBUG
        if !hasCamera || UserDefaults.standard.bool(forKey: "GLCameraFixture") { return RetroCamFixture() }
        #endif
        return hasCamera ? RetroCamera() : nil
    }

    /// Whether the source needs camera permission (the fixture doesn't).
    static func needsPermission(_ source: RetroCamSource) -> Bool {
        source is RetroCamera
    }
}

/// The camera: an AVCaptureSession with a video data output for the live
/// preview (frames go to the Metal renderer as CIImages, never UIImages) and
/// a photo output for full-resolution stills. Session work runs on its own
/// queue, never on the main thread. Buffers arrive as the sensor sees them;
/// turning and mirroring happen in Core Image, so the preview and the photo
/// always match.
final class RetroCamera: NSObject, RetroCamSource, @unchecked Sendable {
    enum CameraError: Error { case captureFailed }

    var frameHandler: (@Sendable (CIImage, Double) -> Void)?
    var pauseHandler: (@MainActor (RetroCamPause?) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "app.glowlit.retrocam.session")
    private let videoQueue = DispatchQueue(label: "app.glowlit.retrocam.frames", qos: .userInteractive)
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    // Session queue only.
    private var input: AVCaptureDeviceInput?
    private var isConfigured = false
    private var wantsRunning = false
    private var observers: [NSObjectProtocol] = []
    // Main actor only.
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private var rotationObservations: [NSKeyValueObservation] = []
    private weak var previewLayer: CALayer?

    /// Shared by the session, frame and main queues.
    private let lock = NSLock()
    private var previewAngle: CGFloat = 90
    private var captureAngle: CGFloat = 90
    private var isMirrored = true
    /// Width over height of the upright preview frames.
    private var frameAspect: CGFloat = 0
    private var startTime = CACurrentMediaTime()
    private var captures: [Int64: PhotoCapture] = [:]

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    /// On the Mac, USB and Continuity cameras also count as built-in wide-angle
    /// cameras; `.external` finds USB cameras on iPad.
    static func device(at position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external], mediaType: .video, position: position).devices.first
    }

    // MARK: Session

    func start(previewLayer: CALayer) async -> RetroCamFeatures? {
        let started: (RetroCamFeatures, AVCaptureDevice)? = await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                if !isConfigured { configure() }
                guard let device = input?.device else { return continuation.resume(returning: nil) }
                wantsRunning = true
                lock.withLock { startTime = CACurrentMediaTime() }
                if !session.isRunning { session.startRunning() }
                // A pause from before (say, the trip to the background) is over.
                if !session.isInterrupted { report(nil) }
                continuation.resume(returning: (features(), device))
            }
        }
        guard let started else { return nil }
        await followRotation(of: started.1, layer: previewLayer)
        return started.0
    }

    func stop() {
        sessionQueue.async { [self] in
            wantsRunning = false
            if session.isRunning { session.stopRunning() }
        }
    }

    func switchCamera() async -> RetroCamFeatures? {
        let switched: (RetroCamFeatures, AVCaptureDevice)? = await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                guard let current = input,
                      let device = Self.device(at: current.device.position == .back ? .front : .back),
                      let next = try? AVCaptureDeviceInput(device: device) else { return continuation.resume(returning: nil) }
                session.beginConfiguration()
                session.removeInput(current)
                if session.canAddInput(next) {
                    session.addInput(next)
                    input = next
                } else {
                    session.addInput(current)
                }
                prepareConnections(for: input?.device ?? current.device)
                session.commitConfiguration()
                continuation.resume(returning: (features(), input?.device ?? current.device))
            }
        }
        guard let switched else { return nil }
        await followRotation(of: switched.1, layer: nil)
        return switched.0
    }

    /// Front camera first: the booth is about selfies.
    private func configure() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = session.canSetSessionPreset(.photo) ? .photo : .high
        guard let device = Self.device(at: .front) ?? Self.device(at: .unspecified),
              let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return }
        session.addInput(input)
        self.input = input

        if session.canAddOutput(videoOutput) {
            videoOutput.alwaysDiscardsLateVideoFrames = true
            // The camera's own format: Core Image reads it without a conversion.
            let format = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            if videoOutput.availableVideoPixelFormatTypes.contains(format) {
                videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: format]
            }
            videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
            session.addOutput(videoOutput)
        }
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .balanced
        }
        #if !targetEnvironment(macCatalyst)
        // iPad: keep the camera running in Split View where the hardware allows.
        if session.isMultitaskingCameraAccessSupported {
            session.isMultitaskingCameraAccessEnabled = true
        }
        #endif
        prepareConnections(for: device)
        observeSession()
        isConfigured = true
    }

    /// Raw, unmirrored sensor buffers on both outputs.
    private func prepareConnections(for device: AVCaptureDevice) {
        lock.withLock { isMirrored = device.position != .back }
        for connection in [videoOutput.connection(with: .video), photoOutput.connection(with: .video)].compactMap({ $0 }) {
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
        }
        videoOutput.connection(with: .video)?.videoRotationAngle = 0
    }

    private func features() -> RetroCamFeatures {
        RetroCamFeatures(
            canSwitchCamera: Self.device(at: .front) != nil && Self.device(at: .back) != nil,
            hasFlash: photoOutput.supportedFlashModes.contains(.on)
        )
    }

    private func observeSession() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { [weak self] note in
                let reason = (note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int).flatMap(AVCaptureSession.InterruptionReason.init(rawValue:))
                switch reason {
                case .videoDeviceInUseByAnotherClient: self?.report(.inUseElsewhere)
                case .videoDeviceNotAvailableWithMultipleForegroundApps: self?.report(.multitasking)
                case .videoDeviceNotAvailableDueToSystemPressure: self?.report(.systemPressure)
                default: self?.report(.other)
                }
            },
            center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) { [weak self] _ in
                self?.report(nil)
            },
            center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] note in
                guard let self else { return }
                // After a media services reset the session can simply start again.
                if (note.userInfo?[AVCaptureSessionErrorKey] as? AVError)?.code == .mediaServicesWereReset {
                    sessionQueue.async { if self.wantsRunning, !self.session.isRunning { self.session.startRunning() } }
                } else {
                    report(.other)
                }
            },
        ]
    }

    private func report(_ pause: RetroCamPause?) {
        Task { @MainActor [weak self] in self?.pauseHandler?(pause) }
    }

    // MARK: Rotation

    /// Keeps the preview level with the screen and photos level with the
    /// horizon (a sideways phone takes a landscape photo). `layer`: the
    /// preview's layer, nil to keep the one from before.
    @MainActor
    private func followRotation(of device: AVCaptureDevice, layer: CALayer?) {
        if let layer { previewLayer = layer }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotation = coordinator
        lock.withLock {
            previewAngle = coordinator.videoRotationAngleForHorizonLevelPreview
            captureAngle = coordinator.videoRotationAngleForHorizonLevelCapture
        }
        rotationObservations = [
            coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: .new) { [weak self] coordinator, _ in
                let angle = coordinator.videoRotationAngleForHorizonLevelPreview
                self?.lock.withLock { self?.previewAngle = angle }
            },
            coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: .new) { [weak self] coordinator, _ in
                let angle = coordinator.videoRotationAngleForHorizonLevelCapture
                self?.lock.withLock { self?.captureAngle = angle }
            },
        ]
    }

    static func orientation(forAngle angle: CGFloat) -> CGImagePropertyOrientation {
        switch (Int(angle.rounded()) % 360 + 360) % 360 {
        case 90: return .right
        case 180: return .down
        case 270: return .left
        default: return .up
        }
    }

    // MARK: Stills

    func capture(flash: Bool, maxPixel: Int) async throws -> UIImage {
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                guard session.isRunning, let connection = photoOutput.connection(with: .video) else {
                    return continuation.resume(throwing: CameraError.captureFailed)
                }
                let angle = lock.withLock { captureAngle }
                if connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
                let settings = AVCapturePhotoSettings()
                settings.photoQualityPrioritization = .balanced
                if flash, photoOutput.supportedFlashModes.contains(.on) {
                    settings.flashMode = .on
                }
                let id = settings.uniqueID
                let capture = PhotoCapture { [weak self] result in
                    self?.lock.withLock { _ = self?.captures.removeValue(forKey: id) }
                    continuation.resume(with: result)
                }
                // The photo output doesn't keep its delegate alive.
                lock.withLock { captures[id] = capture }
                photoOutput.capturePhoto(with: settings, delegate: capture)
            }
        }
        let (mirrored, aspect) = lock.withLock { (isMirrored, frameAspect) }
        return try await Task.detached(priority: .userInitiated) {
            // ImageIO applies the photo's orientation and downsamples on the way in.
            guard let photo = ImageUtilities.decodedImage(from: data, maxPixel: maxPixel)?.cgImage else { throw CameraError.captureFailed }
            return RetroCamera.finish(photo, mirrored: mirrored, aspect: aspect)
        }.value
    }

    /// Crops a still to the preview's shape (turned with it) and mirrors a
    /// selfie like the preview.
    static func finish(_ photo: CGImage, mirrored: Bool, aspect: CGFloat) -> UIImage {
        var image = photo
        let width = CGFloat(photo.width), height = CGFloat(photo.height)
        if aspect > 0 {
            let target = (width >= height) == (aspect >= 1) ? aspect : 1 / aspect
            if abs(width / height - target) > 0.01 {
                let crop = width / height > target
                    ? CGRect(x: ((width - height * target) / 2).rounded(), y: 0, width: (height * target).rounded(), height: height)
                    : CGRect(x: 0, y: ((height - width / target) / 2).rounded(), width: width, height: (width / target).rounded())
                image = photo.cropping(to: crop) ?? photo
            }
        }
        guard mirrored else { return UIImage(cgImage: image, scale: 1, orientation: .up) }
        let flipped = UIImage(cgImage: image, scale: 1, orientation: .upMirrored)
        return ImageUtilities.normalized(flipped, maxLongEdge: max(image.width, image.height))
    }
}

extension RetroCamera: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let handler = frameHandler, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let (angle, mirrored, start) = lock.withLock { (previewAngle, isMirrored, startTime) }
        var frame = CIImage(cvPixelBuffer: buffer).oriented(Self.orientation(forAngle: angle))
        if mirrored {
            frame = frame.oriented(.upMirrored)
        }
        let aspect = frame.extent.width / max(frame.extent.height, 1)
        lock.withLock { frameAspect = aspect }
        handler(frame, CACurrentMediaTime() - start)
    }
}

/// One photo on its way: hands over the encoded file once.
private final class PhotoCapture: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private var completion: ((Result<Data, Error>) -> Void)?

    init(completion: @escaping (Result<Data, Error>) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let data = photo.fileDataRepresentation(), error == nil {
            finish(.success(data))
        } else {
            finish(.failure(error ?? RetroCamera.CameraError.captureFailed))
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        finish(.failure(error ?? RetroCamera.CameraError.captureFailed))
    }

    private func finish(_ result: Result<Data, Error>) {
        guard let completion else { return }
        self.completion = nil
        completion(result)
    }
}
