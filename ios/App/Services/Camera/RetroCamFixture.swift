#if DEBUG
import UIKit
import CoreImage
import AppCore

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
        let zoom = Self.zoom
        // `-GLCameraSteady YES` holds still, for before-and-after captures.
        let sway: CGFloat = Self.isSteady ? 0 : 1
        let dx = CGFloat(sin(seconds * 0.9)) * extent.width * 0.012 * sway
        let dy = CGFloat(cos(seconds * 0.7)) * extent.height * 0.01 * sway
        return scene
            .transformed(by: CGAffineTransform(scaleX: zoom, y: zoom))
            .transformed(by: CGAffineTransform(translationX: -extent.width * (zoom - 1) / 2 + dx, y: -extent.height * (zoom - 1) / 2 + dy))
            .cropped(to: extent)
    }

    /// The cartoon friend and pet by the golden lake, 3:4 like a photo, or
    /// with `-GLSamplePhotos` a sample photo (`-GLCameraSample <name>`,
    /// portrait-c by default; Glow Cam's tint needs a face).
    private static let isSteady = UserDefaults.standard.bool(forKey: "GLCameraSteady")
    /// The frames show the photo a little closer, so it can drift.
    private static let zoom: CGFloat = 1.05

    /// `-GLVisionFixtures <folder>`: the sample's face landmarks found on a Mac
    /// (`<folder>/<sample>/landmarks.json`: a list of faces, each a region name
    /// to `[x, y]` points in fractions of the photo, y up), because the
    /// Simulator's Vision can't find them. Glow Cam's makeup tint uses them
    /// where the frames show the photo; hold it still with `-GLCameraSteady YES`.
    static let savedLandmarks: [FaceLandmarks]? = {
        let defaults = UserDefaults.standard
        guard let folder = defaults.string(forKey: "GLVisionFixtures") else { return nil }
        let url = URL(fileURLWithPath: folder)
            .appendingPathComponent(defaults.string(forKey: "GLCameraSample") ?? "portrait-c", isDirectory: true)
            .appendingPathComponent("landmarks.json")
        guard let data = try? Data(contentsOf: url),
              let faces = try? JSONDecoder().decode([[String: [[Double]]]].self, from: data) else { return nil }
        let zoom = Double(RetroCamFixture.zoom)
        return faces.map { face in
            func points(_ region: String) -> [FacePoint] {
                (face[region] ?? []).filter { $0.count == 2 }.map { FacePoint(x: 0.5 + ($0[0] - 0.5) * zoom, y: 0.5 + ($0[1] - 0.5) * zoom) }
            }
            return FaceLandmarks(outerLips: points("outerLips"), innerLips: points("innerLips"), leftEye: points("leftEye"),
                                 rightEye: points("rightEye"), nose: points("nose"), faceContour: points("faceContour"))
        }
    }()

    private static func makeScene() -> CIImage? {
        let name = UserDefaults.standard.string(forKey: "GLCameraSample") ?? "portrait-c"
        let art = ScreenshotFixtures.sample(name) ?? ScreenshotFixtures.cutoutPhoto
        let size = CGSize(width: 1200, height: 1600)
        let image = ShareRenderer.renderer(size, opaque: true).image { _ in
            art.draw(in: ShareRenderer.fillRect(for: art.size, in: CGRect(origin: .zero, size: size), face: nil))
        }
        return image.cgImage.map { CIImage(cgImage: $0) }
    }
}
#endif
