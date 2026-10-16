import UIKit
import Metal
import CoreImage
import SwiftUI
import AppCore

/// Retro Cam's live preview surface: a CAMetalLayer the renderer draws into.
final class RetroCamPreviewView: UIView {
    /// The preview doesn't need every retina pixel: capping it keeps even the
    /// heaviest effects at camera speed. Core Animation scales it up.
    private static let maxPixels: CGFloat = 1440

    override class var layerClass: AnyClass { CAMetalLayer.self }

    var metalLayer: CAMetalLayer? { layer as? CAMetalLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isUserInteractionEnabled = false
        guard let metalLayer else { return }
        metalLayer.device = ImageFilters.metalDevice
        metalLayer.pixelFormat = .bgra8Unorm
        // Core Image writes into the drawable directly.
        metalLayer.framebufferOnly = false
        metalLayer.isOpaque = true
        metalLayer.contentsGravity = .resizeAspectFill
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = traitCollection.displayScale
        var size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let longest = max(size.width, size.height)
        if longest > Self.maxPixels {
            size = CGSize(width: size.width * Self.maxPixels / longest, height: size.height * Self.maxPixels / longest)
        }
        metalLayer?.drawableSize = CGSize(width: max(1, size.width.rounded()), height: max(1, size.height.rounded()))
    }
}

struct RetroCamPreview: UIViewRepresentable {
    let view: RetroCamPreviewView

    func makeUIView(context: Context) -> RetroCamPreviewView { view }
    func updateUIView(_ uiView: RetroCamPreviewView, context: Context) {}
}

/// Draws camera frames through the chosen effect or Glow look straight into
/// the preview's Metal layer, with the app's shared Core Image context: no
/// UIImage per frame. Effect overlays (date stamp, letterbox, camcorder
/// display) are drawn once per size and reused. `draw` runs on the camera's
/// frame queue; the makeup tint's face finding runs beside it
/// (`GlowFaceTracker`) and pauses itself when frames fall behind.
final class RetroCamRenderer: @unchecked Sendable {
    struct Look: Equatable {
        var effect: RetroEffect
        var showsExtra: Bool
        /// Glow Cam's look, in place of the effect.
        var glow: GlowCamSettings?
        /// Reduce Motion: Sparkle's glints stay where they are.
        var holdsSparkle = false
    }

    /// Where held glints are (the frames' clock).
    static let heldSparkleTime = 1.5

    /// The upright frame's width over height changed (camera switch, iPad
    /// rotation); on the main actor.
    var onAspectChange: (@MainActor (CGFloat) -> Void)?
    /// Whether the makeup tint has a face to go on (false a moment after the
    /// last one left); on the main actor.
    var onFaceChange: (@MainActor (Bool) -> Void)?
    /// The makeup tint paused itself to keep the camera smooth; on the main actor.
    var onTintPause: (@MainActor () -> Void)?

    /// One queue for the app's lifetime, however often the camera opens.
    private static let commandQueue = ImageFilters.metalDevice?.makeCommandQueue()
    #if DEBUG
    /// `-GLTintKeepsGoing YES`: the tint never pauses (Simulator captures,
    /// where frames are slow).
    private static let tintKeepsGoing = UserDefaults.standard.bool(forKey: "GLTintKeepsGoing")
    #endif

    private let layer: CAMetalLayer?
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
    private let lock = NSLock()
    private let faces = GlowFaceTracker()
    private var look: Look
    private var isActive = false
    /// The camera (and its clock) started again: the tint starts over.
    private var restarted = false
    private var lastSeconds: Double = 0
    // Frame queue only.
    private var aspect: CGFloat = 0
    private var overlay: (look: Look, size: CGSize, image: CIImage?)?
    private var camcorder: (size: CGSize, parts: CamcorderChrome.VideoParts)?
    private var tint = TintState()

    /// The makeup tint's run on the frame queue: from when it was turned on
    /// (or the camera changed) until it's off or paused.
    private struct TintState {
        var isOn = false
        var isPaused = false
        var started: Double = 0
        var lastFace: Double?
        var reportedFace: Bool?
        var lastHeatCheck: Double = -.infinity
    }

    init(view: RetroCamPreviewView, look: Look) {
        layer = view.metalLayer
        self.look = look
    }

    func update(_ look: Look) {
        lock.withLock { self.look = look }
    }

    /// Off while the camera is stopped or the app is in the background,
    /// where the GPU isn't available.
    func setActive(_ active: Bool) {
        lock.withLock {
            isActive = active
            if active { restarted = true }
        }
    }

    /// The latest frame's time on the frames' clock: where a still's sparkle is.
    var clock: Double {
        lock.withLock { lastSeconds }
    }

    func draw(_ frame: CIImage, seconds: Double) {
        let started = CACurrentMediaTime()
        let (look, isActive, restarted) = lock.withLock {
            lastSeconds = seconds
            defer { self.restarted = false }
            return (self.look, self.isActive, self.restarted)
        }
        if restarted { tint.isOn = false }
        noteAspect(of: frame.extent)
        guard isActive, let layer, layer.drawableSize.width > 1,
              let drawable = layer.nextDrawable(), let buffer = Self.commandQueue?.makeCommandBuffer() else { return }
        let size = CGSize(width: drawable.texture.width, height: drawable.texture.height)
        let bounds = CGRect(origin: .zero, size: size)

        // Fill the drawable (same shape as the frame, so nothing is lost).
        let extent = frame.extent
        let scale = max(size.width / extent.width, size.height / extent.height)
        let fill = CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: (size.width - extent.width * scale) / 2, y: (size.height - extent.height * scale) / 2))
        var image = frame.transformed(by: fill).cropped(to: bounds)

        if let glow = look.glow {
            let tinted = tintFaces(in: frame, glow: glow, seconds: seconds, fill: fill)
            let sparkleTime = look.holdsSparkle ? Self.heldSparkleTime : seconds
            image = GlowCamRender.apply(image, settings: glow, faces: tinted, seconds: sparkleTime).cropped(to: bounds)
        } else {
            tint.isOn = false
            image = look.effect.grade(image).cropped(to: bounds)
            if look.showsExtra, look.effect.option?.worksOnVideo == true {
                if let overlay = overlay(for: look, size: size) {
                    image = overlay.composited(over: image)
                }
                if look.effect.option == .cameraInfo {
                    image = camcorderParts(for: size).composite(over: image, seconds: seconds, fps: 30)
                }
            }
        }

        let destination = CIRenderDestination(mtlTexture: drawable.texture, commandBuffer: buffer)
        destination.colorSpace = colorSpace
        _ = try? ImageFilters.context.startTask(toRender: image, to: destination)
        buffer.present(drawable)
        buffer.commit()
        if tint.isOn, !tint.isPaused {
            watchTint(seconds: seconds, duration: CACurrentMediaTime() - started)
        }
    }

    private func noteAspect(of extent: CGRect) {
        guard extent.height > 0 else { return }
        let value = extent.width / extent.height
        guard abs(value - aspect) > 0.001 else { return }
        aspect = value
        // Another camera or a turn: faces start over.
        tint.isOn = false
        Task { @MainActor [weak self] in self?.onAspectChange?(value) }
    }

    // MARK: Makeup tint

    /// Frame queue: the faces to tint, in the drawable's pixels. Looks for
    /// faces when it's time; between looks they glide.
    private func tintFaces(in frame: CIImage, glow: GlowCamSettings, seconds: Double, fill: CGAffineTransform) -> [GlowCamRender.TintFace] {
        guard glow.hasTint else {
            tint.isOn = false
            return []
        }
        if !tint.isOn {
            faces.reset()
            tint = TintState(isOn: true, started: seconds)
        }
        guard !tint.isPaused else { return [] }
        faces.look(at: frame, seconds: seconds)
        let found = faces.faces(at: seconds)
        noteFace(!found.isEmpty, at: seconds)
        let extent = frame.extent
        return found.map { face in
            GlowCamRender.TintFace(landmarks: face.landmarks.mapped { point in
                let pixel = CGPoint(x: extent.minX + point.x * extent.width, y: extent.minY + point.y * extent.height).applying(fill)
                return FacePoint(x: pixel.x, y: pixel.y)
            }, opacity: face.opacity)
        }
    }

    /// Tells the camera when the tint has no face, a moment after the last one left.
    private func noteFace(_ seen: Bool, at seconds: Double) {
        if seen { tint.lastFace = seconds }
        let present = seconds - (tint.lastFace ?? tint.started) < 1.2
        guard present != tint.reportedFace else { return }
        tint.reportedFace = present
        Task { @MainActor [weak self] in self?.onFaceChange?(present) }
    }

    /// Pauses the tint when frames keep falling behind or the device runs hot.
    private func watchTint(seconds: Double, duration: Double) {
        #if DEBUG
        // Not even the tracker's own pacing or the heat check (a busy Mac
        // reads as hot): it would stop looking for faces.
        if Self.tintKeepsGoing { return }
        #endif
        var pause = faces.frameDrawn(at: seconds, duration: duration)
        if seconds - tint.lastHeatCheck >= 1 {
            tint.lastHeatCheck = seconds
            if ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue {
                faces.pause()
                pause = true
            }
        }
        guard pause else { return }
        tint.isPaused = true
        Task { @MainActor [weak self] in self?.onTintPause?() }
    }

    private func overlay(for look: Look, size: CGSize) -> CIImage? {
        if let overlay, overlay.look == look, overlay.size == size { return overlay.image }
        let image = look.effect.videoOverlay(size: size)
        overlay = (look, size, image)
        return image
    }

    private func camcorderParts(for size: CGSize) -> CamcorderChrome.VideoParts {
        if let camcorder, camcorder.size == size { return camcorder.parts }
        let parts = CamcorderChrome.VideoParts(size: size)
        camcorder = (size, parts)
        return parts
    }
}
