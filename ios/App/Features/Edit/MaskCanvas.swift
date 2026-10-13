import SwiftUI
import UIKit

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

/// Lets the user paint over objects to erase.
struct MaskCanvas: View {
    let image: UIImage
    @Binding var strokes: [MaskStroke]
    let brushSize: CGFloat

    @State private var activeStroke: MaskStroke?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                Canvas { context, canvasSize in
                    let all = strokes + (activeStroke.map { [$0] } ?? [])
                    for stroke in all {
                        context.stroke(
                            stroke.path(in: canvasSize),
                            with: .color(Palette.blush.opacity(0.75)),
                            style: StrokeStyle(lineWidth: stroke.width * canvasSize.width, lineCap: .round, lineJoin: .round)
                        )
                    }
                }
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let point = CGPoint(
                            x: min(max(value.location.x / max(size.width, 1), 0), 1),
                            y: min(max(value.location.y / max(size.height, 1), 0), 1)
                        )
                        if activeStroke == nil {
                            activeStroke = MaskStroke(points: [point], width: brushSize)
                        } else {
                            activeStroke?.points.append(point)
                        }
                    }
                    .onEnded { _ in
                        if let activeStroke {
                            strokes.append(activeStroke)
                            Haptics.tap()
                        }
                        activeStroke = nil
                    }
            )
        }
        .aspectRatio(image.size.width / max(image.size.height, 1), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityLabel("Brush over the area to erase")
    }
}
