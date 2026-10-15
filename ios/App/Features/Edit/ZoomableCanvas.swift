import SwiftUI
import UIKit
import AppCore

/// Lets SwiftUI drive the canvas zoom (VoiceOver's zoom action) and know
/// whether it's zoomed in.
@MainActor
final class CanvasZoom {
    fileprivate weak var scrollView: ZoomScrollView?

    func step(zoomIn: Bool) {
        guard let scrollView else { return }
        let target = zoomIn ? min(scrollView.zoomScale * 2, scrollView.maximumZoomScale) : scrollView.minimumZoomScale
        scrollView.setZoomScale(target, animated: true)
    }
}

/// The editor canvas: pinch or double-tap to zoom (up to 4×, double-tap to
/// 2× where she tapped), drag to look around, hold to see the original, and
/// one tap for focus mode. A UIKit scroll view, because SwiftUI on iOS 17
/// can't pan with the pinch; it also brings trackpad pinch and two-finger
/// scrolling on iPad and the Mac. The numbers are `CanvasZoomMath`'s.
struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    let zoom: CanvasZoom
    var onHold: (Bool) -> Void = { _ in }
    var onZoomChange: (Bool) -> Void = { _ in }
    /// The zoom as it changes (1 at fit), for the "2×" badge.
    var onScale: (CGFloat) -> Void = { _ in }
    /// One tap (after a double tap had its chance): focus mode.
    var onTap: (() -> Void)?

    func makeUIView(context: Context) -> UIView {
        let scrollView = ZoomScrollView()
        zoom.scrollView = scrollView
        return scrollView
    }

    func updateUIView(_ view: UIView, context: Context) {
        guard let scrollView = view as? ZoomScrollView else { return }
        if scrollView.imageView.image !== image { scrollView.imageView.image = image }
        scrollView.onHold = onHold
        scrollView.onZoomChange = onZoomChange
        scrollView.onScale = onScale
        scrollView.onTap = onTap
        zoom.scrollView = scrollView
    }
}

private final class ZoomScrollView: UIScrollView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    let imageView = UIImageView()
    var onHold: (Bool) -> Void = { _ in }
    var onZoomChange: (Bool) -> Void = { _ in }
    var onScale: (CGFloat) -> Void = { _ in }
    var onTap: (() -> Void)? {
        didSet { singleTap.isEnabled = onTap != nil }
    }
    private let holdRecognizer = UILongPressGestureRecognizer()
    private let singleTap = UITapGestureRecognizer()
    private var laidOutSize = CGSize.zero
    private var wasZoomed = false

    init() {
        super.init(frame: .zero)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = CanvasZoomMath.maximumScale
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .clear
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        singleTap.addTarget(self, action: #selector(tapped))
        singleTap.require(toFail: doubleTap)
        singleTap.isEnabled = false
        addGestureRecognizer(singleTap)

        holdRecognizer.addTarget(self, action: #selector(held(_:)))
        holdRecognizer.minimumPressDuration = 0.15
        holdRecognizer.allowableMovement = 40
        holdRecognizer.delegate = self
        addGestureRecognizer(holdRecognizer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != laidOutSize else { return }
        // The canvas grows and shrinks with the tool panel and focus mode:
        // zoomed in, it keeps the zoom and the spot in the middle.
        let scale = zoomScale
        let center = CGPoint(
            x: contentSize.width > 0 ? (contentOffset.x + laidOutSize.width / 2) / contentSize.width : 0.5,
            y: contentSize.height > 0 ? (contentOffset.y + laidOutSize.height / 2) / contentSize.height : 0.5
        )
        let firstLayout = laidOutSize == .zero
        laidOutSize = bounds.size
        setZoomScale(minimumZoomScale, animated: false)
        imageView.frame = bounds
        contentSize = bounds.size
        var restored = CanvasZoomMath.isAtFit(scale) ? 1 : scale
        #if DEBUG
        // Screenshot QA of the zoomed canvas and its badge: -GLCanvasZoom <scale>.
        let debugZoom = CGFloat(UserDefaults.standard.double(forKey: "GLCanvasZoom"))
        if firstLayout, ScreenshotScene.current != nil, debugZoom > 1 { restored = debugZoom }
        #endif
        guard restored > 1, bounds.width > 0 else { return }
        setZoomScale(restored, animated: false)
        let offset = CanvasZoomMath.offset(keeping: (firstLayout ? 0.5 : center.x, firstLayout ? 0.42 : center.y),
                                           contentWidth: contentSize.width, contentHeight: contentSize.height,
                                           viewWidth: bounds.width, viewHeight: bounds.height)
        contentOffset = CGPoint(x: offset.x, y: offset.y)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        // A pinch that starts with one finger resting shouldn't show the original.
        holdRecognizer.isEnabled = false
        holdRecognizer.isEnabled = true
        onHold(false)
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        onScale(zoomScale)
        let isZoomed = !CanvasZoomMath.isAtFit(zoomScale)
        guard isZoomed != wasZoomed else { return }
        wasZoomed = isZoomed
        onZoomChange(isZoomed)
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        // A pinch let go just above fit: back to fit, with a light tap.
        guard !CanvasZoomMath.isAtFit(scale), CanvasZoomMath.settledScale(scale) == 1 else { return }
        setZoomScale(minimumZoomScale, animated: true)
        Haptics.selection()
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === holdRecognizer { return CanvasZoomMath.isAtFit(zoomScale) }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    @objc private func doubleTapped(_ recognizer: UITapGestureRecognizer) {
        let target = CanvasZoomMath.doubleTapTarget(from: zoomScale)
        if target <= minimumZoomScale {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let point = recognizer.location(in: imageView)
            let rect = CanvasZoomMath.zoomRect(around: point.x, point.y, width: imageView.bounds.width, height: imageView.bounds.height,
                                               scale: target)
            zoom(to: CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height), animated: true)
        }
        Haptics.selection()
    }

    @objc private func tapped() {
        onTap?()
    }

    @objc private func held(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began: onHold(true)
        case .ended, .cancelled, .failed: onHold(false)
        default: break
        }
    }
}
