import XCTest
@testable import AppCore

final class AutoAdjustTests: XCTestCase {
    private func photo(_ make: (Int) -> AutoAdjust.Pixel) -> [AutoAdjust.Pixel] {
        (0..<400).map(make)
    }

    /// A "good" photo: full tonal range, natural colour, neutral balance.
    private var balanced: [AutoAdjust.Pixel] {
        photo { i in
            let v = Double(i % 100) / 99
            return AutoAdjust.Pixel(r: min(1, v * 1.05), g: v * 0.92, b: v * 0.8)
        }
    }

    func testGoodPhotosStayAlmostUntouched() {
        let plan = AutoAdjust.plan(pixels: balanced)
        XCTAssertEqual(plan.brightness, 0)
        XCTAssertEqual(plan.contrast, 1)
        XCTAssertLessThan(abs(plan.saturation - 1), 0.15)
        XCTAssertLessThan(abs(plan.warmth), 0.15)
    }

    func testDarkPhotosGetBrighterAndBrightOnesDarker() {
        let dark = photo { i in let v = 0.05 + Double(i % 20) / 100; return .init(r: v, g: v, b: v * 0.9) }
        let bright = photo { i in let v = 0.8 + Double(i % 20) / 100; return .init(r: min(v, 1), g: min(v, 1), b: min(v, 1) * 0.95) }
        XCTAssertGreaterThan(AutoAdjust.plan(pixels: dark).brightness, 0.05)
        XCTAssertLessThan(AutoAdjust.plan(pixels: bright).brightness, -0.05)
    }

    func testFlatDullBluePhotosAreFixed() {
        let flat = photo { i in let v = 0.45 + Double(i % 10) / 100; return .init(r: v * 0.9, g: v * 0.95, b: v * 1.1) }
        let plan = AutoAdjust.plan(pixels: flat)
        XCTAssertGreaterThan(plan.contrast, 1.1, "flat photos get contrast")
        XCTAssertGreaterThan(plan.saturation, 1.05, "dull photos get colour")
        XCTAssertGreaterThan(plan.warmth, 0.05, "a blue cast gets warmed")
        XCTAssertLessThanOrEqual(plan.contrast, 1.25)
        XCTAssertLessThanOrEqual(plan.warmth, 0.4)
    }

    func testWarmPhotosAreNotCooledMuch() {
        let orange = photo { i in let v = 0.3 + Double(i % 50) / 100; return .init(r: min(1, v * 1.5), g: v * 0.9, b: v * 0.4) }
        XCTAssertGreaterThanOrEqual(AutoAdjust.plan(pixels: orange).warmth, -0.15)
        XCTAssertLessThan(AutoAdjust.plan(pixels: orange).warmth, 0)
    }

    func testTooFewPixelsIsNeutral() {
        XCTAssertEqual(AutoAdjust.plan(pixels: []), .neutral)
    }
}
