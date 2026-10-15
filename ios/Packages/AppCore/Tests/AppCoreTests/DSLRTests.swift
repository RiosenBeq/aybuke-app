import XCTest
@testable import AppCore

final class DSLRTests: XCTestCase {
    func testLongerLensesBlurMore() {
        XCTAssertEqual(DSLRLens.allCases.map(\.focalLength), [85, 50, 35])
        XCTAssertEqual(DSLRLens.standard, .portrait85)
        XCTAssertGreaterThan(DSLRLens.portrait85.blurRadius, DSLRLens.standard50.blurRadius)
        XCTAssertGreaterThan(DSLRLens.standard50.blurRadius, DSLRLens.wide35.blurRadius)
        for lens in DSLRLens.allCases {
            // A real blur, yet never so wide that the photo turns to mush.
            XCTAssertGreaterThan(lens.blurRadius, 0.005, lens.rawValue)
            XCTAssertLessThan(lens.blurRadius, 0.04, lens.rawValue)
        }
        XCTAssertTrue((0.2...0.8).contains(DSLRLens.nearBlurShare))
    }

    func testGradeKeepsGreysNeutralInTheMiddle() {
        let mid = DSLRGrade.map(0.5, 0.5, 0.5)
        XCTAssertEqual(mid.r, 0.5, accuracy: 0.02)
        XCTAssertEqual(mid.g, 0.5, accuracy: 0.02)
        XCTAssertEqual(mid.b, 0.5, accuracy: 0.02)
        XCTAssertLessThan(abs(mid.r - mid.b), 0.02)
    }

    func testGradeWarmsHighlightsAndCoolsShadows() {
        let light = DSLRGrade.map(0.9, 0.9, 0.9)
        XCTAssertGreaterThan(light.r, light.b + 0.02)
        let dark = DSLRGrade.map(0.12, 0.12, 0.12)
        XCTAssertGreaterThan(dark.b, dark.r + 0.01)
    }

    func testGradeIsGentleOnSkinAndKeepsItsHue() {
        // Light, medium and deep skin tones (gamma-encoded sRGB).
        let skins: [(Double, Double, Double)] = [(0.94, 0.78, 0.68), (0.78, 0.57, 0.44), (0.45, 0.30, 0.22), (0.30, 0.20, 0.15)]
        for skin in skins {
            let graded = DSLRGrade.map(skin.0, skin.1, skin.2)
            XCTAssertLessThan(abs(graded.r - skin.0), 0.06, "\(skin)")
            XCTAssertLessThan(abs(graded.g - skin.1), 0.06, "\(skin)")
            XCTAssertLessThan(abs(graded.b - skin.2), 0.07, "\(skin)")
            // Still red above green above blue: the same hue family.
            XCTAssertGreaterThan(graded.r, graded.g, "\(skin)")
            XCTAssertGreaterThan(graded.g, graded.b, "\(skin)")
        }
    }

    func testGradeIsMonotoneAndInRange() {
        var previous = -1.0
        for step in 0...40 {
            let value = Double(step) / 40
            let graded = DSLRGrade.map(value, value, value)
            let luma = ToneMap.luma(graded.r, graded.g, graded.b)
            XCTAssertGreaterThan(luma, previous)
            previous = luma
        }
        let cube = DSLRGrade.cube(dimension: 8)
        XCTAssertEqual(cube.count, 8 * 8 * 8 * 4)
        XCTAssertTrue(cube.allSatisfy { (0...1).contains($0) })
        // Red changes fastest, alpha is always 1.
        XCTAssertLessThan(cube[0], cube[4 * 7])
        XCTAssertTrue(stride(from: 3, to: cube.count, by: 4).allSatisfy { cube[$0] == 1 })
    }

    func testCutoutEdgeGoesFromCrispThroughNaturalToSoft() {
        XCTAssertTrue(CutoutEdge.plan(CutoutEdge.natural).isIdentity)
        let crisp = CutoutEdge.plan(0)
        XCTAssertLessThan(crisp.high - crisp.low, 0.3, "a steep ramp")
        XCTAssertEqual(crisp.feather, 0)
        XCTAssertGreaterThan((crisp.low + crisp.high) / 2, 0.5, "pulled in a little, so no fringe")
        let soft = CutoutEdge.plan(1)
        XCTAssertGreaterThan(soft.feather, 0)
        XCTAssertGreaterThan(soft.choke, 0, "the feather starts inside the edge")
        XCTAssertEqual(soft.low, 0)
        XCTAssertEqual(soft.high, 1)
        // Out-of-range values are clamped, and the steps are gradual.
        XCTAssertEqual(CutoutEdge.plan(-3), crisp)
        XCTAssertEqual(CutoutEdge.plan(7), soft)
        XCTAssertLessThan(CutoutEdge.plan(0.6).feather, soft.feather)
        XCTAssertGreaterThan(CutoutEdge.plan(0.4).high - CutoutEdge.plan(0.4).low, crisp.high - crisp.low)
    }
}
