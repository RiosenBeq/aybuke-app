#if DEBUG
import UIKit
import CoreImage

/// DEBUG stand-in for the camera: the simulator has none (also with
/// `-GLCameraFixture YES`). It feeds the demo art at 30 fps, drifting a
/// little like a hand-held phone, so the live effects and the whole booth
/// can be checked and screenshotted.
final class RetroCamFixture: RetroCamSource, @unchecked Sendable {
    var frameHandler: (@Sendable (CIImage, Double) -> Void)?
    var pauseHandler: (@MainActor (RetroCamPause?) -> Void)?

    private let queue = DispatchQueue(label: "app.glowlit.retrocam.fixture", qos: .userInteractive)
    // Fixture queue only.
    private var timer: DispatchSourceTimer?
    private var scene: CIImage?
    private var started = CACurrentMediaTime()

    func start(previewLayer: CALayer) async -> RetroCamFeatures? {
        queue.async { [self] in
            if scene == nil { scene = Self.makeScene() }
            guard timer == nil else { return }
            started = CACurrentMediaTime()
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now(), repeating: .milliseconds(33))
            source.setEventHandler { [weak self] in self?.tick() }
            source.resume()
            timer = source
        }
        return RetroCamFeatures(canSwitchCamera: true, hasFlash: true)
    }

    func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
        }
    }

    func switchCamera() async -> RetroCamFeatures? {
        RetroCamFeatures(canSwitchCamera: true, hasFlash: true)
    }

    func capture(flash: Bool, maxPixel: Int) async throws -> UIImage {
        let frame: CIImage? = await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.frame(at: CACurrentMediaTime() - self.started)) }
        }
        guard let frame, let still = ImageFilters.render(frame, extent: frame.extent) else { throw CocoaError(.featureUnsupported) }
        return ImageUtilities.normalized(still, maxLongEdge: maxPixel)
    }

    private func tick() {
        let seconds = CACurrentMediaTime() - started
        guard let frame = frame(at: seconds) else { return }
        frameHandler?(frame, seconds)
    }

    private func frame(at seconds: Double) -> CIImage? {
        guard let scene else { return nil }
        let extent = scene.extent
        let zoom: CGFloat = 1.05
        let dx = CGFloat(sin(seconds * 0.9)) * extent.width * 0.012
        let dy = CGFloat(cos(seconds * 0.7)) * extent.height * 0.01
        return scene
            .transformed(by: CGAffineTransform(scaleX: zoom, y: zoom))
            .transformed(by: CGAffineTransform(translationX: -extent.width * (zoom - 1) / 2 + dx, y: -extent.height * (zoom - 1) / 2 + dy))
            .cropped(to: extent)
    }

    /// The cartoon friend and pet by the golden lake, 3:4 like a phone photo.
    private static func makeScene() -> CIImage? {
        let art = ScreenshotFixtures.sample("portrait-c") ?? ScreenshotFixtures.cutoutPhoto
        let size = CGSize(width: 1200, height: 1600)
        let image = ShareRenderer.renderer(size, opaque: true).image { _ in
            art.draw(in: ShareRenderer.fillRect(for: art.size, in: CGRect(origin: .zero, size: size), face: nil))
        }
        return image.cgImage.map { CIImage(cgImage: $0) }
    }
}
#endif
