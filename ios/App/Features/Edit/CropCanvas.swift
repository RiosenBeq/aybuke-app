import SwiftUI
import UIKit
import AppCore

enum CropRenderer {
    /// Draws `image` through `geometry` at its own pixels (scale 1). Photos
    /// stay opaque (JPEG on export); cut-outs keep their transparency.
    nonisolated static func render(_ image: UIImage, geometry: CropGeometry, aspect: CropAspect) -> UIImage {
        let pixels = ImageUtilities.pixelSize(of: image)
        let source = CropSize(width: Double(pixels.width), height: Double(pixels.height))
        let output = geometry.outputSize(for: source, aspect: aspect)
        let t = geometry.transform(source: source, output: output)
        let size = CGSize(width: output.width, height: output.height)
        return ImageUtilities.draw(size: size, opaque: !ImageUtilities.hasAlpha(image), colorSpace: image.cgImage?.colorSpace) { cg in
            cg.interpolationQuality = .high
            cg.concatenate(CGAffineTransform(a: t.a, b: t.b, c: t.c, d: t.d, tx: t.tx, ty: t.ty))
            image.draw(in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        }
    }

    /// Only the quarter turns and the mirror: what the crop box sits on.
    nonisolated static func oriented(_ image: UIImage, geometry: CropGeometry) -> UIImage {
        var turns = CropGeometry()
        turns.quarterTurns = geometry.quarterTurns
        turns.isFlipped = geometry.isFlipped
        return turns.isIdentity ? image : render(image, geometry: turns, aspect: .free)
    }
}

/// The photo (turned and mirrored) under a movable crop box with
/// rule-of-thirds lines. Straightening turns the photo behind the box and
/// enlarges it just enough to keep the box filled.
struct CropCanvas: View {
    let image: UIImage
    @Binding var geometry: CropGeometry
    let aspect: CropAspect
    /// Full-size pixels of the photo before turning, for locked shapes and VoiceOver.
    let sourceSize: CropSize

    @State private var dragStart: CropRect?

    private var orientedSize: CropSize { geometry.orientedSize(of: sourceSize) }
    private var lockedRatio: Double? { aspect.widthOverHeight(for: orientedSize) }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let rect = geometry.rect
            let frame = CGRect(x: rect.x * size.width, y: rect.y * size.height, width: rect.width * size.width, height: rect.height * size.height)
            let anchor = UnitPoint(x: rect.midX, y: rect.midY)
            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(geometry.coverScale(in: orientedSize), anchor: anchor)
                    .rotationEffect(.degrees(geometry.angle), anchor: anchor)
                    .accessibilityHidden(true)

                Path { path in
                    path.addRect(CGRect(origin: .zero, size: size))
                    path.addRect(frame)
                }
                .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

                CropGrid()
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .allowsHitTesting(false)

                Rectangle()
                    .fill(Color.white.opacity(0.001))
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .gesture(moveGesture(in: size))
                    .accessibilityElement()
                    .accessibilityLabel("Crop area")
                    .accessibilityValue(accessibilityValue)
                    .accessibilityAdjustableAction { direction in
                        let factor = direction == .increment ? 1.1 : 1 / 1.1
                        geometry.rect = CropGeometry.scaled(geometry.rect, by: factor)
                    }

                ForEach(CropGeometry.Corner.allCases, id: \.self) { corner in
                    CropHandle(corner: corner)
                        .position(position(of: corner, in: frame))
                        .gesture(resizeGesture(corner, in: size))
                        .accessibilityHidden(true)
                }
            }
            .coordinateSpace(name: "crop")
        }
        .aspectRatio(image.size.width / max(image.size.height, 1), contentMode: .fit)
        .clipped()
    }

    private var accessibilityValue: String {
        let output = geometry.outputSize(for: sourceSize, aspect: aspect)
        if let ratio = aspect.ratio {
            return String(localized: "\(ratio.width) by \(ratio.height), \(output.width) by \(output.height) pixels")
        }
        return String(localized: "\(output.width) by \(output.height) pixels")
    }

    private func position(of corner: CropGeometry.Corner, in frame: CGRect) -> CGPoint {
        switch corner {
        case .topLeading: return CGPoint(x: frame.minX, y: frame.minY)
        case .topTrailing: return CGPoint(x: frame.maxX, y: frame.minY)
        case .bottomLeading: return CGPoint(x: frame.minX, y: frame.maxY)
        case .bottomTrailing: return CGPoint(x: frame.maxX, y: frame.maxY)
        }
    }

    private func moveGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("crop"))
            .onChanged { value in
                let start = dragStart ?? geometry.rect
                dragStart = start
                geometry.rect = CropGeometry.moved(
                    start,
                    dx: value.translation.width / max(size.width, 1),
                    dy: value.translation.height / max(size.height, 1)
                )
            }
            .onEnded { _ in dragStart = nil }
    }

    private func resizeGesture(_ corner: CropGeometry.Corner, in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("crop"))
            .onChanged { value in
                let start = dragStart ?? geometry.rect
                dragStart = start
                let point = (x: Double(value.location.x / max(size.width, 1)), y: Double(value.location.y / max(size.height, 1)))
                geometry.rect = CropGeometry.resized(start, corner: corner, to: point, ratio: lockedRatio, in: orientedSize)
            }
            .onEnded { _ in
                dragStart = nil
                Haptics.selection()
            }
    }
}

private struct CropGrid: View {
    var body: some View {
        Canvas { context, size in
            var lines = Path()
            for i in 1...2 {
                let x = size.width * CGFloat(i) / 3
                let y = size.height * CGFloat(i) / 3
                lines.move(to: CGPoint(x: x, y: 0))
                lines.addLine(to: CGPoint(x: x, y: size.height))
                lines.move(to: CGPoint(x: 0, y: y))
                lines.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(lines, with: .color(.white.opacity(0.55)), lineWidth: 0.75)
            context.stroke(Path(CGRect(origin: .zero, size: size)), with: .color(.white), lineWidth: 1.5)
        }
    }
}

/// A 44 pt touch target around a small L-shaped corner.
private struct CropHandle: View {
    let corner: CropGeometry.Corner

    var body: some View {
        Canvas { context, size in
            let length: CGFloat = 18
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let sx: CGFloat = corner == .topLeading || corner == .bottomLeading ? 1 : -1
            let sy: CGFloat = corner == .topLeading || corner == .topTrailing ? 1 : -1
            var path = Path()
            path.move(to: CGPoint(x: center.x + sx * length, y: center.y))
            path.addLine(to: center)
            path.addLine(to: CGPoint(x: center.x, y: center.y + sy * length))
            context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .hoverEffect(.highlight)
    }
}
