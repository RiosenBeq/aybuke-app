import XCTest
@testable import AppCore

final class SoftSkinTests: XCTestCase {
    private func defaults(_ band: AgeBand, source: AgeSource = .selfDeclared, country: String? = "USA") -> AgeDefaults {
        AgeDefaults(record: AgeRecord(band: band, source: source, setAt: .distantPast), storefrontCountry: country)
    }

    func testOnlyAdultsGetTheSlider() {
        XCTAssertTrue(SoftSkin.isAvailable(for: defaults(.adult)))
        XCTAssertTrue(SoftSkin.isAvailable(for: defaults(.adult, source: .apple)))
        for band in [AgeBand.under13, .teen13to15, .teen16to17, .unknown] {
            XCTAssertFalse(SoftSkin.isAvailable(for: defaults(band)), "\(band)")
        }
        // Not answered yet, or declined: the protective defaults.
        XCTAssertFalse(SoftSkin.isAvailable(for: AgeDefaults(record: nil, storefrontCountry: "USA")))
        XCTAssertFalse(SoftSkin.isAvailable(for: defaults(.adult, source: .declined)))
        // Where a self-declared age isn't accepted, a self-declared adult isn't one.
        XCTAssertFalse(SoftSkin.isAvailable(for: defaults(.adult, country: "BRA")))
        XCTAssertTrue(SoftSkin.isAvailable(for: defaults(.adult, source: .apple, country: "BRA")))
    }

    func testOffByDefaultAndGentleAtMost() {
        XCTAssertEqual(SoftSkin.defaultAmount, 0)
        XCTAssertNil(SoftSkin.plan(amount: 0, longEdge: 2000), "off changes nothing")
        XCTAssertEqual(SoftSkin.blend(for: 1), 0.35)
        XCTAssertEqual(SoftSkin.blend(for: 7), 0.35, "never past the cap")
        XCTAssertEqual(SoftSkin.blend(for: -1), 0)
        XCTAssertEqual(SoftSkin.blend(for: .nan), 0)
        XCTAssertEqual(SoftSkin.blend(for: 0.5), 0.175, accuracy: 1e-12)
        XCTAssertLessThanOrEqual(SoftSkin.maxBlend, 0.35)
    }

    func testPreviewAndFullSizeUseTheSameProportions() throws {
        let preview = try XCTUnwrap(SoftSkin.plan(amount: 1, longEdge: 1200))
        let full = try XCTUnwrap(SoftSkin.plan(amount: 1, longEdge: 2400))
        XCTAssertEqual(full.smoothingRadius / preview.smoothingRadius, 2, accuracy: 1e-9)
        XCTAssertEqual(full.textureSigma / preview.textureSigma, 2, accuracy: 1e-9)
        XCTAssertEqual(full.blend, preview.blend)
        // The texture band is far finer than the smoothing, so pores and freckles stay.
        XCTAssertLessThan(full.textureSigma * 4, full.smoothingRadius)
    }

    func testSkinColourExcludesHairLipsAndBackground() throws {
        // A warm medium skin tone sampled on the cheeks, with some spread.
        let samples = (0..<30).map { i -> (r: Double, g: Double, b: Double) in
            let k = Double(i % 5) * 0.01
            return (0.78 + k, 0.58 + k, 0.47 + k)
        }
        let tone = try XCTUnwrap(SkinTone.reference(samples: samples))
        XCTAssertEqual(tone.likelihood(r: 0.79, g: 0.59, b: 0.48), 1)
        XCTAssertGreaterThan(tone.likelihood(r: 0.55, g: 0.40, b: 0.33), 0.5, "the same skin in shadow")
        XCTAssertLessThan(tone.likelihood(r: 0.25, g: 0.18, b: 0.12), 0.2, "dark brown hair")
        XCTAssertEqual(tone.likelihood(r: 0.85, g: 0.30, b: 0.40), 0, "lip colour")
        XCTAssertEqual(tone.likelihood(r: 0.30, g: 0.45, b: 0.80), 0, "a blue background")
        XCTAssertEqual(tone.likelihood(r: 0.02, g: 0.02, b: 0.02), 0, "pupils and lashes")
        XCTAssertNil(SkinTone.reference(samples: Array(samples.prefix(3))), "too few samples to tell")
    }

    func testEyesBrowsLipsAndNostrilsStaySharp() {
        // A level face, fractions with y up: eyes at 0.4/0.6, mouth below.
        func ring(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> [FacePoint] {
            (0..<8).map { i in
                let a = Double(i) / 8 * 2 * .pi
                return FacePoint(x: x + w / 2 * cos(a), y: y + h / 2 * sin(a))
            }
        }
        let face = FaceLandmarks(outerLips: ring(0.5, 0.35, 0.16, 0.05), leftEye: ring(0.4, 0.55, 0.08, 0.03),
                                 rightEye: ring(0.6, 0.55, 0.08, 0.03), nose: [FacePoint(x: 0.5, y: 0.5), FacePoint(x: 0.47, y: 0.44),
                                                                              FacePoint(x: 0.53, y: 0.44)])
        let ellipses = FaceFeatureMask.ellipses(for: face)
        func kept(_ x: Double, _ y: Double) -> Bool { ellipses.contains { $0.normalizedDistance(to: FacePoint(x: x, y: y)) <= 1 } }
        XCTAssertTrue(kept(0.4, 0.55), "left eye")
        XCTAssertTrue(kept(0.6, 0.55), "right eye")
        XCTAssertTrue(kept(0.4, 0.62), "left brow, made from the eye")
        XCTAssertTrue(kept(0.5, 0.35), "lips")
        XCTAssertTrue(kept(0.5, 0.45), "nostrils")
        XCTAssertFalse(kept(0.33, 0.43), "cheek")
        XCTAssertFalse(kept(0.5, 0.75), "forehead")
        // The skin colour is sampled on skin, never on a feature.
        let samples = FaceFeatureMask.skinSamplePoints(for: face)
        XCTAssertFalse(samples.isEmpty)
        XCTAssertFalse(samples.contains { kept($0.x, $0.y) })
    }
}
