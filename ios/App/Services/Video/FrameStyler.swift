import CoreImage
import AppCore

/// What every frame of the edited video gets once it's in place: Auto
/// edit's colour look, the retro effect, the effect's overlay (date stamp,
/// letterbox or camcorder display) and the captions on top. The plain and
/// the vertical Auto edit compositions both draw through it, so the preview
/// and the saved video match either way.
final class FrameStyler: @unchecked Sendable {
    private let effect: RetroEffect?
    private let look: AdjustmentSettings?
    private let captions: CaptionTrack?
    private let overlays: OverlayCache
    private let rate: Double

    /// `fps` sets the camcorder timecode's frame count.
    init(effect: RetroEffect?, showsExtra: Bool, fps: Double, look: AdjustVibe? = nil, captions: CaptionTrack? = nil) {
        self.effect = effect
        self.look = look?.settings
        self.captions = captions
        overlays = OverlayCache(effect: showsExtra && effect?.option?.worksOnVideo == true ? effect : nil)
        rate = CamcorderClock.frameRate(fps)
    }

    /// Nothing to draw: the plain composition plays the clip as it is.
    var isEmpty: Bool { effect == nil && look == nil && captions == nil }

    /// One frame at `seconds` on the edited timeline (the output's time, so
    /// the preview and the export match).
    func style(_ source: CIImage, seconds: Double) -> CIImage {
        let extent = source.extent
        var frame = source
        if let look { frame = Self.colorLook(frame, settings: look, seconds: seconds) }
        if let effect { frame = effect.grade(frame).cropped(to: extent) }
        if let overlay = overlays.overlay(for: extent) {
            frame = overlay.composited(over: frame)
        }
        if let camcorder = overlays.camcorder(for: extent) {
            frame = camcorder.composite(over: frame, seconds: seconds, fps: rate)
        }
        if let captions {
            frame = captions.composite(over: frame, seconds: seconds)
        }
        return frame
    }

    /// An Adjust vibe on a video frame. Its film grain moves from frame to
    /// frame like real grain; a still pattern would look like dirt on the lens.
    private static func colorLook(_ image: CIImage, settings: AdjustmentSettings, seconds: Double) -> CIImage {
        let extent = image.extent
        var still = settings
        still.grain = 0
        var frame = ImageFilters.adjust(image, with: still)
        if let grain = AdjustRendering.grain(settings.grain, longEdge: Double(max(extent.width, extent.height))) {
            let index = Int((seconds * 30).rounded())
            let shift = CGAffineTransform(translationX: CGFloat(index * 7919 % 2048), y: CGFloat(index * 6271 % 2048))
            frame = ImageFilters.filmGrain(over: frame.transformed(by: shift), amount: grain.amount, scale: grain.scale)
                .transformed(by: shift.inverted())
        }
        return frame.cropped(to: extent)
    }
}

/// Overlays are drawn once per frame size, not every frame.
private final class OverlayCache: @unchecked Sendable {
    private let effect: RetroEffect?
    private var cached: (CGRect, CIImage?)?
    private var parts: (CGRect, CamcorderChrome.VideoParts)?
    private let lock = NSLock()

    init(effect: RetroEffect?) { self.effect = effect }

    func overlay(for extent: CGRect) -> CIImage? {
        guard let effect else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let cached, cached.0 == extent { return cached.1 }
        let layer = effect.videoOverlay(size: extent.size)?
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
        cached = (extent, layer)
        return layer
    }

    func camcorder(for extent: CGRect) -> CamcorderChrome.VideoParts? {
        guard effect?.option == .cameraInfo else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let parts, parts.0 == extent { return parts.1 }
        let made = CamcorderChrome.VideoParts(size: extent.size)
        parts = (extent, made)
        return made
    }
}
