import XCTest
@testable import AppCore

final class PhotoBoothTests: XCTestCase {
    func testCountdownsUseTheTimerOnlyForTheFirstShot() {
        XCTAssertEqual(PhotoBooth.countdowns(timer: 0), [3, 3, 3, 3])
        XCTAssertEqual(PhotoBooth.countdowns(timer: 3), [3, 3, 3, 3])
        XCTAssertEqual(PhotoBooth.countdowns(timer: 10), [10, 3, 3, 3])
        XCTAssertEqual(PhotoBooth.countdowns(timer: 10).count, PhotoBooth.shotCount)
    }

    func testTimerCyclesOffThreeTen() {
        XCTAssertEqual(PhotoBooth.nextTimer(after: 0), 3)
        XCTAssertEqual(PhotoBooth.nextTimer(after: 3), 10)
        XCTAssertEqual(PhotoBooth.nextTimer(after: 10), 0)
        XCTAssertEqual(PhotoBooth.nextTimer(after: 7), 0)
    }

    func testCaptionIsOneShortLine() {
        XCTAssertEqual(PhotoBooth.cleanCaption("  besties\nforever  "), "besties forever")
        XCTAssertEqual(PhotoBooth.cleanCaption(String(repeating: "x", count: 90)).count, PhotoBooth.captionMaxLength)
        XCTAssertEqual(PhotoBooth.cleanCaption("   "), "")
    }

    func testEveryLayoutHasFourEqualCellsInsideTheCanvas() {
        for layout in BoothLayout.allCases {
            for hasFooter in [true, false] {
                let plan = layout.plan(hasFooter: hasFooter)
                XCTAssertEqual(plan.cells.count, PhotoBooth.shotCount)
                for cell in plan.cells {
                    XCTAssertEqual(cell.width, plan.cells[0].width)
                    XCTAssertEqual(cell.height, plan.cells[0].height)
                    XCTAssertGreaterThan(cell.x, 0)
                    XCTAssertGreaterThan(cell.y, 0)
                    XCTAssertLessThan(cell.maxX, plan.width)
                    XCTAssertLessThan(cell.maxY, plan.height)
                    XCTAssertEqual(cell.width / cell.height, layout.cellAspect, accuracy: 0.01)
                }
                for (index, cell) in plan.cells.enumerated() {
                    for other in plan.cells[(index + 1)...] {
                        let apart = cell.maxX <= other.x || other.maxX <= cell.x || cell.maxY <= other.y || other.maxY <= cell.y
                        XCTAssertTrue(apart, "\(layout) cells \(cell) and \(other) overlap")
                    }
                }
                // Same margin on the left and the right.
                let left = plan.cells.map(\.x).min() ?? 0
                let right = plan.width - (plan.cells.map(\.maxX).max() ?? 0)
                XCTAssertEqual(left, right, accuracy: 1)
            }
        }
    }

    func testStripStacksLandscapeFramesTopToBottom() {
        let plan = BoothLayout.strip.plan(hasFooter: true)
        XCTAssertEqual(Set(plan.cells.map(\.x)).count, 1)
        XCTAssertEqual(plan.cells.map(\.y), plan.cells.map(\.y).sorted())
        XCTAssertGreaterThan(plan.cells[0].width, plan.cells[0].height)
        // A tall strip, about 1:3 like the real thing.
        XCTAssertEqual(plan.height / plan.width, 3, accuracy: 0.25)
    }

    func testGridIsTwoRowsOfTwoPortraitFrames() {
        let plan = BoothLayout.grid.plan(hasFooter: false)
        XCTAssertEqual(plan.cells[0].y, plan.cells[1].y)
        XCTAssertEqual(plan.cells[2].y, plan.cells[3].y)
        XCTAssertLessThan(plan.cells[0].x, plan.cells[1].x)
        XCTAssertLessThan(plan.cells[1].y, plan.cells[2].y)
        XCTAssertLessThan(plan.cells[0].width, plan.cells[0].height)
    }

    func testFooterSitsUnderTheShots() {
        for layout in BoothLayout.allCases {
            let withFooter = layout.plan(hasFooter: true)
            let without = layout.plan(hasFooter: false)
            XCTAssertNil(without.footer)
            guard let footer = withFooter.footer else { return XCTFail("\(layout) has no footer") }
            XCTAssertGreaterThanOrEqual(footer.y, withFooter.cells.map(\.maxY).max() ?? 0)
            XCTAssertEqual(footer.maxY, withFooter.height, accuracy: 0.5)
            XCTAssertGreaterThan(withFooter.height, without.height)
            XCTAssertEqual(withFooter.cells, without.cells)
        }
    }
}
