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

enum MaskRenderer {
    /// White strokes on black, at the image's pixel size (the format inpainting
    /// models expect).
    static func render(_ strokes: [MaskStroke], size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
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
/// pan and pinch to zoom in on small things (see `BrushCanvas`).
struct MaskCanvas: View {
    let image: UIImage
    @Binding var strokes: [MaskStroke]
    let brushSize: CGFloat

    var body: some View {
        BrushCanvas(image: image, strokes: strokes, color: .brandBlush, opacity: 0.75, brushSize: brushSize) { stroke in
            strokes.append(stroke)
            Haptics.tap()
        }
        .aspectRatio(image.size.width / max(image.size.height, 1), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Brush over the area to erase")
        .accessibilityAddTraits(.allowsDirectInteraction)
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
    let color: UIColor
    var opacity: CGFloat = 0.6
    /// Brush diameter at fit, as a fraction of the image width.
    let brushSize: CGFloat
    let onStroke: (MaskStroke) -> Void

    func makeUIView(context: Context) -> BrushCanvasView {
        BrushCanvasView()
    }

    func updateUIView(_ view: BrushCanvasView, context: Context) {
        view.update(image: image, strokes: strokes)
        view.overlay.color = color
        view.overlay.alpha = opacity
        view.brushSize = brushSize
        view.onStroke = onStroke
    }
}

final class BrushCanvasView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    fileprivate let overlay = BrushOverlayView()
    var brushSize: CGFloat = 0.07
    var onStroke: (MaskStroke) -> Void = { _ in }

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let brush = BrushGestureRecognizer()
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
