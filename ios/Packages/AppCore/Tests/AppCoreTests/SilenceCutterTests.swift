import XCTest
@testable import AppCore

final class SilenceCutterTests: XCTestCase {
    /// 20 ms windows: speech is -20 dBFS, silence -60 dBFS.
    private let window = 0.02

    private func clip(_ parts: [(seconds: Double, loud: Bool)]) -> [Double] {
        parts.flatMap { part in
            Array(repeating: part.loud ? -20.0 : -60.0, count: Int((part.seconds / window).rounded()))
        }
    }

    func testCutsLongSilencesAndKeepsPadding() {
        let levels = clip([(2, true), (1.5, false), (2, true)])
        let plan = SilenceCutter.plan(levels: levels, window: window)
        XCTAssertEqual(plan.keep.count, 2)
        XCTAssertEqual(plan.keep[0].lowerBound, 0, accuracy: 0.001)
        XCTAssertEqual(plan.keep[0].upperBound, 2.15, accuracy: 0.03)
        XCTAssertEqual(plan.keep[1].lowerBound, 3.35, accuracy: 0.03)
        XCTAssertEqual(plan.removedSeconds, 1.2, accuracy: 0.05)
        XCTAssertTrue(plan.cutsSomething)
    }

    func testShortPausesStay() {
        let levels = clip([(2, true), (0.4, false), (2, true)])
        let plan = SilenceCutter.plan(levels: levels, window: window)
        XCTAssertEqual(plan.keep.count, 1)
        XCTAssertFalse(plan.cutsSomething)
    }

    func testLeadingAndTrailingSilenceAreTrimmed() {
        let levels = clip([(1, false), (2, true), (1.2, false)])
        let plan = SilenceCutter.plan(levels: levels, window: window)
        // Speech (1…3 s) plus the padding on each side.
        XCTAssertEqual(plan.keep.count, 1)
        XCTAssertEqual(plan.keep[0].lowerBound, 0.85, accuracy: 0.03)
        XCTAssertEqual(plan.keep[0].upperBound, 3.15, accuracy: 0.03)
    }

    func testNoClearSilenceKeepsEverything() {
        let music = (0..<300).map { _ in -22.0 + Double.random(in: -3...3) }
        let plan = SilenceCutter.plan(levels: music, window: window)
        XCTAssertEqual(plan.keep, [0...6])
        XCTAssertFalse(plan.cutsSomething)
    }

    func testAllSilenceKeepsEverything() {
        let plan = SilenceCutter.plan(levels: clip([(3, false)]), window: window)
        XCTAssertEqual(plan.keep.count, 1)
    }
}
