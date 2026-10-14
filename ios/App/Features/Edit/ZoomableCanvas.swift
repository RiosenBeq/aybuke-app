import SwiftUI
import UIKit

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

/// The editor canvas: pinch or double-tap to zoom (up to 4×), drag to look
/// around, and hold to see the original. A UIKit scroll view, because
/// SwiftUI on iOS 17 can't pan with the pinch; it also brings trackpad
/// pinch and two-finger scrolling on iPad and the Mac.
struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    let zoom: CanvasZoom
    var onHold: (Bool) -> Void = { _ in }
    var onZoomChange: (Bool) -> Void = { _ in }

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
        zoom.scrollView = scrollView
    }
}

private final class ZoomScrollView: UIScrollView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    let imageView = UIImageView()
    var onHold: (Bool) -> Void = { _ in }
    var onZoomChange: (Bool) -> Void = { _ in }
    private let holdRecognizer = UILongPressGestureRecognizer()
    private var laidOutSize = CGSize.zero
    private var wasZoomed = false

    init() {
        super.init(frame: .zero)
        delegate = self
        minimumZoomScale = 1
        // Previews are ~1200 px and photos at most 2048 px: more is just blur.
        maximumZoomScale = 4
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .clear
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

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
        // The canvas grows and shrinks with the tool panel: start again at fit.
        laidOutSize = bounds.size
        setZoomScale(minimumZoomScale, animated: false)
        imageView.frame = bounds
        contentSize = bounds.size
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        // A pinch that starts with one finger resting shouldn't show the original.
        holdRecognizer.isEnabled = false
        holdRecognizer.isEnabled = true
        onHold(false)
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        let isZoomed = zoomScale > minimumZoomScale + 0.01
        guard isZoomed != wasZoomed else { return }
        wasZoomed = isZoomed
        onZoomChange(isZoomed)
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === holdRecognizer { return zoomScale <= minimumZoomScale + 0.01 }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    @objc private func doubleTapped(_ recognizer: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale + 0.01 {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let point = recognizer.location(in: imageView)
            let size = CGSize(width: bounds.width / 2, height: bounds.height / 2)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }

    @objc private func held(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began: onHold(true)
        case .ended, .cancelled, .failed: onHold(false)
        default: break
        }
    }
}
