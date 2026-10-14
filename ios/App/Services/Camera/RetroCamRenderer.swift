import UIKit
import Metal
import CoreImage
import SwiftUI

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

/// Draws camera frames through the chosen effect straight into the preview's
/// Metal layer, with the app's shared Core Image context: no UIImage per
/// frame. Effect overlays (date stamp, letterbox, camcorder display) are
/// drawn once per size and reused. `draw` runs on the camera's frame queue.
final class RetroCamRenderer: @unchecked Sendable {
    struct Look: Equatable {
        var effect: RetroEffect
        var showsExtra: Bool
    }

    /// The upright frame's width over height changed (camera switch, iPad
    /// rotation); on the main actor.
    var onAspectChange: (@MainActor (CGFloat) -> Void)?

    /// One queue for the app's lifetime, however often the camera opens.
    private static let commandQueue = ImageFilters.metalDevice?.makeCommandQueue()

    private let layer: CAMetalLayer?
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
    private let lock = NSLock()
    private var look: Look
    private var isActive = false
    // Frame queue only.
    private var aspect: CGFloat = 0
    private var overlay: (look: Look, size: CGSize, image: CIImage?)?
    private var camcorder: (size: CGSize, parts: CamcorderChrome.VideoParts)?

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
        lock.withLock { isActive = active }
    }

    func draw(_ frame: CIImage, seconds: Double) {
        let (look, isActive) = lock.withLock { (self.look, self.isActive) }
        noteAspect(of: frame.extent)
        guard isActive, let layer, layer.drawableSize.width > 1,
              let drawable = layer.nextDrawable(), let buffer = Self.commandQueue?.makeCommandBuffer() else { return }
        let size = CGSize(width: drawable.texture.width, height: drawable.texture.height)
        let bounds = CGRect(origin: .zero, size: size)

        // Fill the drawable (same shape as the frame, so nothing is lost).
        let extent = frame.extent
        let scale = max(size.width / extent.width, size.height / extent.height)
        var image = frame
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        image = image
            .transformed(by: CGAffineTransform(translationX: (size.width - extent.width * scale) / 2, y: (size.height - extent.height * scale) / 2))
            .cropped(to: bounds)

        image = look.effect.grade(image).cropped(to: bounds)
        if look.showsExtra, look.effect.option?.worksOnVideo == true {
            if let overlay = overlay(for: look, size: size) {
                image = overlay.composited(over: image)
            }
            if look.effect.option == .cameraInfo {
                image = camcorderParts(for: size).composite(over: image, seconds: seconds, fps: 30)
            }
        }

        let destination = CIRenderDestination(mtlTexture: drawable.texture, commandBuffer: buffer)
        destination.colorSpace = colorSpace
        _ = try? ImageFilters.context.startTask(toRender: image, to: destination)
        buffer.present(drawable)
        buffer.commit()
    }

    private func noteAspect(of extent: CGRect) {
        guard extent.height > 0 else { return }
        let value = extent.width / extent.height
        guard abs(value - aspect) > 0.001 else { return }
        aspect = value
        Task { @MainActor [weak self] in self?.onAspectChange?(value) }
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
