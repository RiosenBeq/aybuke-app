import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// A brush stroke in normalized coordinates (0…1 on both axes) so it maps
/// directly onto the image regardless of on-screen size.
struct MaskStroke: Equatable {
    var points: [CGPoint]
    /// Brush diameter as a fraction of the image width.
    var width: CGFloat

    func path(in size: CGSize) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        let start = CGPoint(x: first.x * size.width, y: first.y * size.height)
        path.move(to: start)
        if points.count == 1 {
            path.addLine(to: CGPoint(x: start.x + 0.5, y: start.y))
        }
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
        }
        return path
    }

    /// Normalized area the stroke covers, brush included.
    var bounds: CGRect {
        guard let first = points.first else { return .null }
        let box = points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
        return box.insetBy(dx: -width / 2, dy: -width / 2)
    }
}

/// A person or thing she picked in Erase: its subject matte from
/// `SubjectMasks`, grown a little so her outline and soft edge go too.
struct EraseRegion: Equatable {
    /// The subject's label in `SubjectMasks`.
    let id: Int
    /// White where it's erased (grey on the soft edge), at most 1024 px,
    /// covering the whole photo.
    let mask: CGImage
    /// The mask in the brush colour, for the canvas.
    let overlay: UIImage

    static func == (lhs: EraseRegion, rhs: EraseRegion) -> Bool { lhs.id == rhs.id }

    /// Call it off the main actor.
    static func make(id: Int, from masks: SubjectMasks) -> EraseRegion? {
        let matte = masks.matte(for: [id])
        let unit = max(matte.extent.width, matte.extent.height) / 1000
        let grown = Matte.blur(Matte.dilate(Matte.ramp(matte, 0.15, 0.5), 12 * unit), 2 * unit)
        guard let mask = Matte.grayImage(grown, longEdge: 1024) else { return nil }
        let alpha = CIImage(cgImage: mask, options: [.colorSpace: NSNull()])
        let tinted = CIImage(color: CIColor(color: .brandBlush)).cropped(to: alpha.extent)
            .applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: alpha.extent), kCIInputMaskImageKey: alpha,
            ])
        guard let overlay = ImageFilters.context.createCGImage(tinted, from: alpha.extent) else { return nil }
        return EraseRegion(id: id, mask: mask, overlay: UIImage(cgImage: overlay))
    }
}

enum MaskRenderer {
    /// White strokes and picked regions on black, at the image's pixel size
    /// (the format inpainting models expect).
    static func render(_ strokes: [MaskStroke], regions: [EraseRegion] = [], size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            for region in regions {
                UIImage(cgImage: region.mask).draw(in: CGRect(origin: .zero, size: size), blendMode: .lighten, alpha: 1)
            }
            let cg = context.cgContext
            cg.setStrokeColor(UIColor.white.cgColor)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            for stroke in strokes {
                cg.setLineWidth(stroke.width * size.width)
                cg.addPath(stroke.path(in: size).cgPath)
                cg.strokePath()
            }
        }
    }
}

/// Lets the user paint over objects to erase. One finger paints; two fingers
/// pan and pinch to zoom in on small things (see `BrushCanvas`). While she
/// picks people and things (`onPick`), a tap picks one instead of painting.
struct MaskCanvas: View {
    let image: UIImage
    let strokes: [MaskStroke]
    var regions: [EraseRegion] = []
    let brushSize: CGFloat
    /// What she can pick, left to right (for VoiceOver).
    var subjects: [SubjectMasks.Subject] = []
    /// Set while picking: the tapped point, normalized, top-left origin.
    var onPick: ((CGPoint) -> Void)?
    var onPickSubject: (Int) -> Void = { _ in }
    let onStroke: (MaskStroke) -> Void

    var body: some View {
        BrushCanvas(image: image, strokes: strokes, regions: regions.map(\.overlay), color: .brandBlush, opacity: 0.75,
                    brushSize: brushSize, onTap: onPick) { stroke in
            onStroke(stroke)
            Haptics.tap()
        }
        .aspectRatio(image.size.width / max(image.size.height, 1), contentMode: .fit)
        .clipShape(.control)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(onPick == nil ? Text("Brush over the area to erase") : Text(Self.pickHint))
        .accessibilityAddTraits(.allowsDirectInteraction)
        .accessibilityActions {
            if onPick != nil {
                ForEach(Array(subjects.enumerated()), id: \.element.id) { index, subject in
                    Button {
                        onPickSubject(subject.id)
                    } label: {
                        Text("Pick subject \(index + 1) of \(subjects.count)",
                             comment: "VoiceOver action in Erase: adds the person or thing (counted from the left) to what's erased, or takes it off again")
                    }
                }
            }
        }
    }

    static var pickHint: LocalizedStringKey {
        Platform.isMac ? "Click a person or thing to remove it" : "Tap a person or thing to remove it"
    }
}

/// A photo to paint on. One finger paints; two fingers pan, and a pinch
/// zooms up to 4× like the editor canvas (`ZoomableImage`), with the
/// trackpad on iPad and the Mac too. The brush keeps its size on screen, so
/// a stroke made zoomed in is finer on the photo. Give it the image's aspect
/// ratio.
struct BrushCanvas: UIViewRepresentable {
    let image: UIImage
    /// Strokes to show (normalized). Leave empty when the canvas shows their
    /// result instead: a new stroke then stays until `image` changes.
    var strokes: [MaskStroke] = []
    /// Picked areas in the brush colour (Erase), drawn under the strokes.
    var regions: [UIImage] = []
    let color: UIColor
    var opacity: CGFloat = 0.6
    /// Brush diameter at fit, as a fraction of the image width.
    let brushSize: CGFloat
    /// Set: one finger taps to pick (normalized point) instead of painting.
    var onTap: ((CGPoint) -> Void)?
    let onStroke: (MaskStroke) -> Void

    func makeUIView(context: Context) -> BrushCanvasView {
        BrushCanvasView()
    }

    func updateUIView(_ view: BrushCanvasView, context: Context) {
        view.update(image: image, strokes: strokes)
        if view.overlay.regions.map(ObjectIdentifier.init) != regions.map(ObjectIdentifier.init) {
            view.overlay.regions = regions
        }
        view.overlay.color = color
        view.overlay.alpha = opacity
        view.brushSize = brushSize
        view.onStroke = onStroke
        view.onTap = onTap
    }
}

final class BrushCanvasView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    fileprivate let overlay = BrushOverlayView()
    var brushSize: CGFloat = 0.07
    var onStroke: (MaskStroke) -> Void = { _ in }
    /// While set, a one-finger tap picks instead of painting.
    var onTap: ((CGPoint) -> Void)? {
        didSet {
            brush.isEnabled = onTap == nil
            tap.isEnabled = onTap != nil
        }
    }

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let brush = BrushGestureRecognizer()
    private let tap = UITapGestureRecognizer()
    private var laidOutSize = CGSize.zero

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        // Previews are ~1200 px and photos at most 2048 px: more is just blur.
        scrollView.maximumZoomScale = 4
        // The strokes are drawn outside the zoomed view, so a zoom that
        // springs back on its own would leave them behind for a moment.
        scrollView.bouncesZoom = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delaysContentTouches = false
        scrollView.backgroundColor = .clear
        // One finger is the brush; two fingers move the photo.
        scrollView.panGestureRecognizer.minimumNumberOfTouches = 2
        imageView.contentMode = .scaleToFill
        scrollView.addSubview(imageView)
        addSubview(scrollView)

        // Drawn at screen resolution over the scroll view rather than inside
        // it, so strokes stay sharp at any zoom without a huge backing store.
        overlay.isUserInteractionEnabled = false
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.contentMode = .redraw
        addSubview(overlay)

        brush.addTarget(self, action: #selector(painted(_:)))
        brush.delegate = self
        scrollView.addGestureRecognizer(brush)
        tap.addTarget(self, action: #selector(tapped(_:)))
        tap.isEnabled = false
        scrollView.addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(image: UIImage, strokes: [MaskStroke]) {
        // The stroke she just made stays until the canvas shows its result.
        if imageView.image !== image {
            imageView.image = image
            overlay.pending = []
        }
        if overlay.strokes != strokes {
            overlay.strokes = strokes
            overlay.pending = []
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        overlay.frame = bounds
        if bounds.size != laidOutSize {
            // The canvas grows and shrinks with the tool panel: start again at fit.
            laidOutSize = bounds.size
            scrollView.setZoomScale(1, animated: false)
            imageView.frame = bounds
            scrollView.contentSize = bounds.size
            #if DEBUG
            // Screenshot QA of the zoomed canvas: -GLBrushZoom <scale>.
            let zoom = CGFloat(UserDefaults.standard.double(forKey: "GLBrushZoom"))
            if ScreenshotScene.current != nil, zoom > 1, bounds.width > 0 {
                scrollView.setZoomScale(zoom, animated: false)
                let size = scrollView.contentSize
                scrollView.contentOffset = CGPoint(x: min(max(size.width * 0.5 - bounds.width / 2, 0), size.width - bounds.width),
                                                   y: min(max(size.height * 0.6 - bounds.height / 2, 0), size.height - bounds.height))
            }
            #endif
        }
        followImage()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { followImage() }

    func scrollViewDidScroll(_ scrollView: UIScrollView) { followImage() }

    private func followImage() {
        overlay.imageFrame = scrollView.convert(imageView.frame, to: self)
    }

    // MARK: Brush

    @objc private func painted(_ recognizer: BrushGestureRecognizer) {
        let size = imageView.bounds.size
        let location = recognizer.location(in: imageView)
        let point = CGPoint(
            x: min(max(location.x / max(size.width, 1), 0), 1),
            y: min(max(location.y / max(size.height, 1), 0), 1)
        )
        switch recognizer.state {
        case .began:
            overlay.active = MaskStroke(points: [point], width: brushSize / max(scrollView.zoomScale, 1))
        case .changed:
            overlay.active?.points.append(point)
        case .ended:
            if let stroke = overlay.active {
                overlay.pending.append(stroke)
                onStroke(stroke)
            }
            overlay.active = nil
        default:
            // A second finger came down: that was a pinch or a pan.
            overlay.active = nil
        }
    }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        let size = imageView.bounds.size
        let location = recognizer.location(in: imageView)
        onTap?(CGPoint(x: min(max(location.x / max(size.width, 1), 0), 1), y: min(max(location.y / max(size.height, 1), 0), 1)))
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // The pinch and the two-finger pan can start while the brush is down.
        true
    }
}

/// Starts at once with one finger, so a tap paints a dot, and gives up as
/// soon as a second finger lands.
private final class BrushGestureRecognizer: UIGestureRecognizer {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if numberOfTouches > 1 {
            state = state == .possible ? .failed : .cancelled
        } else if state == .possible {
            state = .began
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        if state == .began || state == .changed { state = .changed }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        if state == .began || state == .changed {
            state = .ended
        } else if state == .possible {
            state = .failed
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        state = .cancelled
    }
}

/// Draws the strokes where the photo is on screen.
private final class BrushOverlayView: UIView {
    var strokes: [MaskStroke] = [] { didSet { setNeedsDisplay() } }
    var regions: [UIImage] = [] { didSet { setNeedsDisplay() } }
    /// Finished strokes the canvas hasn't shown yet.
    var pending: [MaskStroke] = [] { didSet { setNeedsDisplay() } }
    var active: MaskStroke? { didSet { setNeedsDisplay() } }
    var color = UIColor.brandBlush {
        didSet { if color != oldValue { setNeedsDisplay() } }
    }
    /// The photo's frame in this view, following pan and zoom.
    var imageFrame = CGRect.zero {
        didSet { if imageFrame != oldValue { setNeedsDisplay() } }
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), imageFrame.width > 0 else { return }
        for region in regions {
            region.draw(in: imageFrame)
        }
        // Opaque strokes under the view's alpha: overlaps don't get darker.
        context.setStrokeColor(color.withAlphaComponent(1).cgColor)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.translateBy(x: imageFrame.minX, y: imageFrame.minY)
        for stroke in strokes + pending + [active].compactMap({ $0 }) {
            context.setLineWidth(stroke.width * imageFrame.width)
            context.addPath(stroke.path(in: imageFrame.size).cgPath)
            context.strokePath()
        }
    }
}
