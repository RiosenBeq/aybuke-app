import XCTest
@testable import AppCore

final class OverlayGeometryTests: XCTestCase {
    /// A 3:4 photo on screen and the same photo at full size.
    private let view = OverlayCanvas(width: 300, height: 400)
    private let photo = OverlayCanvas(width: 1536, height: 2048)

    private func assertPoint(_ point: (x: Double, y: Double), _ x: Double, _ y: Double, accuracy: Double = 1e-6,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(point.x, x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(point.y, y, accuracy: accuracy, file: file, line: line)
    }

    func testUnitIsAThousandthOfTheShorterSide() {
        XCTAssertEqual(view.unit, 0.3, accuracy: 1e-9)
        XCTAssertEqual(photo.unit, 1.536, accuracy: 1e-9)
        XCTAssertEqual(OverlayCanvas(width: 4000, height: 3000).unit, 3, accuracy: 1e-9)
        XCTAssertEqual(photo.sizeInUnits.width, 1000, accuracy: 1e-9)
        XCTAssertEqual(photo.sizeInUnits.height, 2048 / 1.536, accuracy: 1e-9)
    }

    func testArtworkCentreLandsOnThePlacementCentre() {
        let placement = OverlayPlacement(x: 0.25, y: 0.75, scale: 2, rotation: 0.7)
        assertPoint(placement.transform(in: view).apply(x: 0, y: 0), 75, 300)
        assertPoint(placement.transform(in: photo).apply(x: 0, y: 0), 384, 1536)
    }

    func testScaleIsInUnitsOfTheCanvas() {
        // 100 units at scale 2 on a photo whose unit is 1.536 px: 307.2 px.
        let placement = OverlayPlacement(x: 0.5, y: 0.5, scale: 2)
        let t = placement.transform(in: photo)
        assertPoint(t.apply(x: 100, y: 0), 768 + 307.2, 1024)
        assertPoint(t.apply(x: 0, y: -100), 768, 1024 - 307.2)
    }

    func testPositiveRotationTurnsClockwiseOnScreen() {
        // y points down, so a quarter turn takes the right edge to the bottom.
        let placement = OverlayPlacement(x: 0.5, y: 0.5, scale: 1, rotation: .pi / 2)
        let t = placement.transform(in: view)
        assertPoint(t.apply(x: 100, y: 0), 150, 200 + 30)
        assertPoint(t.apply(x: 0, y: 100), 150 - 30, 200)
    }

    func testPreviewAndFullSizeAgreeOnEveryPoint() {
        // What she arranges on the small canvas is what the full-size photo gets.
        let placement = OverlayPlacement(x: 0.31, y: 0.62, scale: 1.7, rotation: -0.4)
        let toPixels = photo.width / view.width
        for (x, y) in [(0.0, 0.0), (120, -45), (-80, 60), (500, 500)] {
            let onScreen = placement.transform(in: view).apply(x: x, y: y)
            let inPhoto = placement.transform(in: photo).apply(x: x, y: y)
            assertPoint(inPhoto, onScreen.x * toPixels, onScreen.y * toPixels, accuracy: 1e-6)
        }
    }

    func testArtworkPointInvertsTheTransform() {
        let placement = OverlayPlacement(x: 0.4, y: 0.3, scale: 0.8, rotation: 2.1)
        let t = placement.transform(in: photo)
        for (x, y) in [(0.0, 0.0), (37, -12), (-210, 90)] {
            let mapped = t.apply(x: x, y: y)
            assertPoint(placement.artworkPoint(x: mapped.x, y: mapped.y, in: photo), x, y, accuracy: 1e-6)
        }
    }

    func testHitTestingFollowsTheTurn() {
        // 200 × 40 units, turned a quarter: tall and thin on screen.
        let placement = OverlayPlacement(x: 0.5, y: 0.5, scale: 1, rotation: .pi / 2)
        let width = 200.0, height = 40.0
        // 50 units (15 pt) below the centre: inside once turned.
        XCTAssertTrue(placement.contains(x: 150, y: 215, artworkWidth: width, artworkHeight: height, in: view))
        // 50 units to the right: outside once turned.
        XCTAssertFalse(placement.contains(x: 165, y: 200, artworkWidth: width, artworkHeight: height, in: view))
        // Slop reaches it.
        XCTAssertTrue(placement.contains(x: 165, y: 200, artworkWidth: width, artworkHeight: height, slop: 10, in: view))
    }

    func testDraggingKeepsTheCentreOnThePhoto() {
        let start = OverlayPlacement(x: 0.5, y: 0.5)
        let moved = start.moved(dx: 30, dy: -40, in: view)
        XCTAssertEqual(moved.x, 0.6, accuracy: 1e-9)
        XCTAssertEqual(moved.y, 0.4, accuracy: 1e-9)
        let flung = start.moved(dx: -1000, dy: 5000, in: view)
        XCTAssertEqual(flung.x, 0)
        XCTAssertEqual(flung.y, 1)
    }

    func testScaleStaysInRange() {
        let placement = OverlayPlacement(scale: 1)
        XCTAssertEqual(placement.scaled(by: 1.5).scale, 1.5, accuracy: 1e-9)
        XCTAssertEqual(placement.scaled(by: 100).scale, OverlayPlacement.scaleRange.upperBound)
        XCTAssertEqual(placement.scaled(by: 0.001).scale, OverlayPlacement.scaleRange.lowerBound)
    }

    func testRotationWrapsAndSnaps() {
        XCTAssertEqual(OverlayPlacement(rotation: 3).rotated(by: 1).rotation, 4 - 2 * .pi, accuracy: 1e-9)
        XCTAssertEqual(OverlayPlacement.normalized(-.pi), .pi, accuracy: 1e-9)
        let degree = Double.pi / 180
        XCTAssertEqual(OverlayPlacement.snapped(3 * degree), 0, accuracy: 1e-9)
        XCTAssertEqual(OverlayPlacement.snapped(10 * degree), 10 * degree, accuracy: 1e-9)
        XCTAssertEqual(OverlayPlacement.snapped(88 * degree), .pi / 2, accuracy: 1e-9)
        XCTAssertEqual(OverlayPlacement.snapped(-178 * degree), .pi, accuracy: 1e-9)
    }

    func testCornerHandleScalesAndTurnsAroundTheCentre() {
        let placement = OverlayPlacement(x: 0.5, y: 0.5, scale: 1, rotation: 0)
        // Centre at (150, 200). Twice as far, a quarter turn clockwise.
        let next = placement.dragged(handleFrom: (x: 190, y: 200), to: (x: 150, y: 280), in: view)
        XCTAssertEqual(next.scale, 2, accuracy: 1e-9)
        XCTAssertEqual(next.rotation, .pi / 2, accuracy: 1e-9)
        XCTAssertEqual(next.x, 0.5)
        // A handle dragged onto the centre changes nothing.
        XCTAssertEqual(placement.dragged(handleFrom: (x: 190, y: 200), to: (x: 150, y: 200), in: view), placement)
    }

    func testNewItemsCascadeOnThePhoto() {
        let placements = (0..<7).map(OverlayPlacement.newItem(index:))
        XCTAssertNotEqual(placements[0], placements[1])
        XCTAssertEqual(placements[0], placements[5])
        for placement in placements {
            XCTAssertTrue((0.2...0.8).contains(placement.x))
            XCTAssertTrue((0.2...0.8).contains(placement.y))
        }
    }

    func testDoodleMapsOntoTheFullSizePhoto() {
        // Drawn on the 300 × 400 pt canvas, applied to the 1536 × 2048 photo.
        let rect = DoodleMapping.rect(drawnOn: view, onto: photo)
        XCTAssertEqual(rect.x, 0)
        XCTAssertEqual(rect.y, 0)
        XCTAssertEqual(rect.width, 1536, accuracy: 1e-9)
        XCTAssertEqual(rect.height, 2048, accuracy: 1e-9)
        XCTAssertEqual(DoodleMapping.scale(drawnOn: view, onto: photo), 5.12, accuracy: 1e-9)
        // After the photo's shape changed, the doodle keeps its own shape.
        let square = OverlayCanvas(width: 1536, height: 1536)
        XCTAssertEqual(DoodleMapping.rect(drawnOn: view, onto: square).height, 2048, accuracy: 1e-9)
    }
}
