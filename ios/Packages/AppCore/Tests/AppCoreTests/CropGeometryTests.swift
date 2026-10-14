import XCTest
@testable import AppCore

final class CropGeometryTests: XCTestCase {
    private let photo = CropSize(width: 3000, height: 2000)

    private func assertPoint(_ point: (x: Double, y: Double), _ x: Double, _ y: Double, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(point.x, x, accuracy: 1e-6, file: file, line: line)
        XCTAssertEqual(point.y, y, accuracy: 1e-6, file: file, line: line)
    }

    /// Output pixel back to source pixel.
    private func inverse(_ t: CropTransform, x: Double, y: Double) -> (x: Double, y: Double) {
        let det = t.a * t.d - t.b * t.c
        let px = x - t.tx, py = y - t.ty
        return ((t.d * px - t.c * py) / det, (-t.b * px + t.a * py) / det)
    }

    func testUntouchedGeometryKeepsThePhoto() {
        let geometry = CropGeometry()
        XCTAssertTrue(geometry.isIdentity)
        let size = geometry.outputSize(for: photo, aspect: .original)
        XCTAssertEqual(size.width, 3000)
        XCTAssertEqual(size.height, 2000)
        let t = geometry.transform(source: photo, output: size)
        assertPoint(t.apply(x: 0, y: 0), 0, 0)
        assertPoint(t.apply(x: 3000, y: 2000), 3000, 2000)
    }

    func testPostingShapesAreExact() {
        for aspect in [CropAspect.square, .portrait, .story, .landscape] {
            var geometry = CropGeometry()
            geometry.rect = CropGeometry.largestRect(ratio: aspect.widthOverHeight(for: photo), in: photo)
            let size = geometry.outputSize(for: photo, aspect: aspect)
            let ratio = aspect.ratio!
            XCTAssertEqual(size.width * ratio.height, size.height * ratio.width, "\(aspect)")
            XCTAssertLessThanOrEqual(size.width, 3000)
            XCTAssertLessThanOrEqual(size.height, 2000)
            XCTAssertGreaterThan(max(Double(size.width) / 3000, Double(size.height) / 2000), 0.99, "\(aspect) is the largest that fits")
        }
    }

    func testRotateLeftTurnsWhatIsOnScreen() {
        var geometry = CropGeometry()
        geometry.rotateLeft(aspect: .original, source: photo)
        let oriented = geometry.orientedSize(of: photo)
        XCTAssertEqual(oriented, CropSize(width: 2000, height: 3000))
        let size = geometry.outputSize(for: photo, aspect: .original)
        XCTAssertEqual(size.width, 2000)
        XCTAssertEqual(size.height, 3000)
        let t = geometry.transform(source: photo, output: size)
        // Turning left brings the top-right corner to the top-left.
        assertPoint(t.apply(x: 3000, y: 0), 0, 0)
        assertPoint(t.apply(x: 0, y: 0), 0, 3000)
        for _ in 0..<3 { geometry.rotateLeft(aspect: .original, source: photo) }
        XCTAssertTrue(geometry.isIdentity)
    }

    func testFlipMirrorsAndRotateFollowsTheMirroredPicture() {
        var geometry = CropGeometry()
        geometry.flip()
        let size = geometry.outputSize(for: photo, aspect: .original)
        assertPoint(geometry.transform(source: photo, output: size).apply(x: 0, y: 0), 3000, 0)

        geometry.rotateLeft(aspect: .original, source: photo)
        let turned = geometry.outputSize(for: photo, aspect: .original)
        // Mirrored top-left sits top-right; turning left brings it to the top-left.
        assertPoint(geometry.transform(source: photo, output: turned).apply(x: 0, y: 0), 0, 0)
    }

    func testFlipMirrorsTheCropAndTheAngle() {
        var geometry = CropGeometry()
        geometry.rect = CropRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        geometry.angle = 5
        geometry.flip()
        XCTAssertEqual(geometry.rect.x, 0.6, accuracy: 1e-9)
        XCTAssertEqual(geometry.angle, -5)
    }

    func testStraightenNeverShowsEmptyCorners() {
        for angle in [-15.0, -5, 3, 15] {
            for rect in [CropRect.full, CropRect(x: 0.05, y: 0.6, width: 0.3, height: 0.35)] {
                var geometry = CropGeometry()
                geometry.angle = angle
                geometry.rect = rect
                let size = geometry.outputSize(for: photo, aspect: .free)
                let t = geometry.transform(source: photo, output: size)
                for (x, y) in [(0.0, 0.0), (Double(size.width), 0), (0, Double(size.height)), (Double(size.width), Double(size.height))] {
                    let source = inverse(t, x: x, y: y)
                    XCTAssertTrue((0...3000).contains(source.x) && (0...2000).contains(source.y), "angle \(angle) corner \(x),\(y) → \(source)")
                }
            }
        }
    }

    func testStraightenScalesUniformly() {
        var geometry = CropGeometry()
        geometry.angle = 7
        let t = geometry.transform(source: photo, output: geometry.outputSize(for: photo, aspect: .original))
        XCTAssertEqual(t.a * t.a + t.b * t.b, t.c * t.c + t.d * t.d, accuracy: 1e-9)
        XCTAssertEqual(t.a * t.c + t.b * t.d, 0, accuracy: 1e-9)
    }

    func testResizeKeepsTheShapeAndStaysInside() {
        let start = CropGeometry.largestRect(ratio: 0.8, in: photo)
        let resized = CropGeometry.resized(start, corner: .bottomTrailing, to: (2, 2), ratio: 0.8, in: photo)
        XCTAssertEqual(resized.width * 3000 / (resized.height * 2000), 0.8, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(resized.maxX, 1 + 1e-9)
        XCTAssertLessThanOrEqual(resized.maxY, 1 + 1e-9)

        let tiny = CropGeometry.resized(.full, corner: .topLeading, to: (0.99, 0.99), ratio: nil, in: photo)
        XCTAssertEqual(tiny.width, CropGeometry.minFraction, accuracy: 1e-9)
        XCTAssertEqual(tiny.maxX, 1, accuracy: 1e-9)

        let moved = CropGeometry.moved(CropRect(x: 0.5, y: 0.5, width: 0.4, height: 0.4), dx: 0.5, dy: -1)
        XCTAssertEqual(moved.x, 0.6, accuracy: 1e-9)
        XCTAssertEqual(moved.y, 0, accuracy: 1e-9)

        let grown = CropGeometry.scaled(CropRect(x: 0.4, y: 0.4, width: 0.2, height: 0.25), by: 1.5)
        XCTAssertEqual(grown.width / grown.height, 0.8, accuracy: 1e-9)
        XCTAssertEqual(grown.midX, 0.5, accuracy: 1e-9)
    }

    func testRotatingAFixedShapeRefitsIt() {
        var geometry = CropGeometry()
        geometry.rect = CropGeometry.largestRect(ratio: 0.8, in: photo)
        geometry.rotateLeft(aspect: .portrait, source: photo)
        let size = geometry.outputSize(for: photo, aspect: .portrait)
        XCTAssertEqual(size.width * 5, size.height * 4)
        XCTAssertEqual(size.width, 2000)
    }

    func testAngleSnapsToLevel() {
        XCTAssertEqual(CropGeometry.snappedAngle(0.3), 0)
        XCTAssertEqual(CropGeometry.snappedAngle(-20), -15)
        XCTAssertEqual(CropGeometry.snappedAngle(4), 4)
    }
}
