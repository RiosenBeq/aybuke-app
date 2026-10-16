import XCTest
@testable import AppCore

final class AdjustmentsTests: XCTestCase {
    // MARK: Sliders

    func testEverySliderRestsInsideItsRange() {
        XCTAssertTrue(AdjustmentSettings.neutral.isNeutral)
        XCTAssertFalse(AdjustmentSettings.neutral.hasToneMap)
        XCTAssertEqual(Set(AdjustmentParameter.allCases.map(\.keyPath)).count, AdjustmentParameter.allCases.count, "one slider per value")
        for parameter in AdjustmentParameter.allCases {
            XCTAssertTrue(parameter.range.contains(parameter.neutral), parameter.id)
            var moved = AdjustmentSettings.neutral
            moved[parameter] = parameter.range.upperBound
            XCTAssertFalse(moved.isNeutral, "\(parameter.id) changes the photo")
        }
        // Every value is a slider, in one of the groups.
        let groups = Set(AdjustmentParameter.autoSet + AdjustmentParameter.vibeSet)
        XCTAssertEqual(groups, Set(AdjustmentParameter.allCases))
        XCTAssertTrue(Set(AdjustmentParameter.shifted).isSubset(of: Set(AdjustmentParameter.autoSet)))
        XCTAssertEqual(AdjustmentParameter.allCases.filter(\.isCentered),
                       [.brightness, .contrast, .highlights, .shadows, .saturation, .warmth, .tint])
    }

    func testClampingKeepsValuesOnTheirSliders() {
        var wild = AdjustmentSettings(brightness: 2, contrast: 9, saturation: -1, warmth: 5, sharpness: 3, vignette: -2, glow: 4,
                                      fade: 2, grain: 7, tint: -3, highlights: 2, shadows: -9)
        wild = wild.clamped()
        for parameter in AdjustmentParameter.allCases {
            XCTAssertTrue(parameter.range.contains(wild[parameter]), parameter.id)
        }
        XCTAssertEqual(wild.tint, -1)
        XCTAssertEqual(wild.contrast, 1.4)
    }

    // MARK: Auto

    func testAutoOnlySetsLightAndColour() {
        let plan = AutoAdjustment(brightness: 0.08, contrast: 1.12, saturation: 1.2, warmth: 0.25, sharpness: 0.25)
        let auto = AdjustmentSettings(auto: plan)
        XCTAssertEqual(auto, AdjustmentSettings(brightness: 0.08, contrast: 1.12, saturation: 1.2, warmth: 0.25, sharpness: 0.25))
        for parameter in AdjustmentParameter.vibeSet {
            XCTAssertEqual(auto[parameter], parameter.neutral, "Auto never sets \(parameter.id)")
        }
        XCTAssertEqual(AdjustmentSettings(auto: .neutral), .neutral)

        // On sliders she has moved: the vibe sliders stay as they are.
        let mine = AdjustmentSettings(brightness: -0.2, warmth: -0.5, vignette: 0.4, glow: 0.3, grain: 0.2, tint: 0.5)
        let fixed = mine.applyingAuto(plan, vibe: nil)
        XCTAssertEqual(fixed.brightness, 0.08)
        XCTAssertEqual(fixed.warmth, 0.25)
        XCTAssertEqual(fixed.vignette, 0.4)
        XCTAssertEqual(fixed.glow, 0.3)
        XCTAssertEqual(fixed.grain, 0.2)
        XCTAssertEqual(fixed.tint, 0.5)
    }

    func testAutoKeepsThePickedVibeOnTop() throws {
        let golden = try XCTUnwrap(AdjustVibes.preset(id: "golden"))
        let plan = AutoAdjustment(brightness: 0.05, contrast: 1.1, saturation: 1.15, warmth: 0.2, sharpness: 0.25)
        let withVibe = golden.applied(to: .neutral, replacing: nil)
        let fixed = withVibe.applyingAuto(plan, vibe: golden)
        XCTAssertEqual(fixed.warmth, 0.2 + golden.shift(of: .warmth), accuracy: 1e-9, "Auto's warmth, then the vibe's")
        XCTAssertEqual(fixed.saturation, 1.15 + golden.shift(of: .saturation), accuracy: 1e-9)
        XCTAssertEqual(fixed.glow, golden.settings.glow)
        XCTAssertEqual(fixed.brightness, 0.05)
    }

    // MARK: Vibes

    func testVibesAreWellFormed() {
        let vibes = AdjustVibes.all
        XCTAssertTrue((3...4).contains(vibes.count))
        XCTAssertEqual(Set(vibes.map(\.id)).count, vibes.count)
        XCTAssertEqual(Set(vibes.map(\.name)).count, vibes.count)
        for vibe in vibes {
            XCTAssertEqual(AdjustVibes.preset(id: vibe.id), vibe)
            XCTAssertFalse(vibe.symbolName.isEmpty, vibe.id)
            XCTAssertEqual(vibe.settings, vibe.settings.clamped(), "\(vibe.id) stays on the sliders")
            // Her own light and detail are hers.
            XCTAssertEqual(vibe.settings.brightness, 0, vibe.id)
            XCTAssertEqual(vibe.settings.sharpness, 0, vibe.id)
            XCTAssertNotEqual(vibe.settings[vibe.lead], vibe.lead.neutral, "\(vibe.id) shows a slider it moved")
            // Tasteful: no slider past the middle of its way.
            for parameter in AdjustmentParameter.allCases {
                let room = parameter.range.upperBound - parameter.range.lowerBound
                XCTAssertLessThanOrEqual(abs(vibe.settings[parameter] - parameter.neutral), room / 2 + 1e-9, "\(vibe.id) \(parameter.id)")
            }
        }
        XCTAssertNil(AdjustVibes.preset(id: "nope"))
    }

    func testAVibeLandsOnTheSlidersAndComesOffAgain() throws {
        let mine = AdjustmentSettings(brightness: 0.1, contrast: 1.05, saturation: 1.2, warmth: 0.1, sharpness: 0.3, grain: 0.5)
        for vibe in AdjustVibes.all {
            let applied = vibe.applied(to: mine, replacing: nil)
            XCTAssertEqual(applied.brightness, mine.brightness, vibe.id)
            XCTAssertEqual(applied.sharpness, mine.sharpness, vibe.id)
            for parameter in AdjustmentParameter.vibeSet {
                XCTAssertEqual(applied[parameter], vibe.settings[parameter], "\(vibe.id) sets \(parameter.id)")
            }
            for parameter in AdjustmentParameter.shifted {
                XCTAssertEqual(applied[parameter], mine[parameter] + vibe.shift(of: parameter), accuracy: 1e-9, "\(vibe.id) nudges \(parameter.id)")
            }
            let removed = vibe.removed(from: applied)
            for parameter in AdjustmentParameter.autoSet {
                XCTAssertEqual(removed[parameter], mine[parameter], accuracy: 1e-9, "\(vibe.id): her \(parameter.id) is back")
            }
            for parameter in AdjustmentParameter.vibeSet {
                XCTAssertEqual(removed[parameter], parameter.neutral, "\(vibe.id): \(parameter.id) at rest")
            }
            // On an untouched photo, a vibe is its own settings.
            XCTAssertEqual(vibe.applied(to: .neutral, replacing: nil), vibe.settings, vibe.id)
        }
    }

    func testSwitchingVibesNeverPilesThemUp() throws {
        let dreamy = try XCTUnwrap(AdjustVibes.preset(id: "dreamy"))
        let golden = try XCTUnwrap(AdjustVibes.preset(id: "golden"))
        let moody = try XCTUnwrap(AdjustVibes.preset(id: "moody"))
        let base = AdjustmentSettings(brightness: 0.05, contrast: 1.1, saturation: 1.1, warmth: 0.2)
        var settings = dreamy.applied(to: base, replacing: nil)
        settings = golden.applied(to: settings, replacing: dreamy)
        settings = moody.applied(to: settings, replacing: golden)
        let direct = moody.applied(to: base, replacing: nil)
        for parameter in AdjustmentParameter.allCases {
            XCTAssertEqual(settings[parameter], direct[parameter], accuracy: 1e-9, parameter.id)
        }
        // Her tweak after a vibe stays when she switches.
        var tweaked = golden.applied(to: base, replacing: nil)
        tweaked.warmth -= 0.1
        let switched = dreamy.applied(to: tweaked, replacing: golden)
        XCTAssertEqual(switched.warmth, base.warmth - 0.1 + dreamy.shift(of: .warmth), accuracy: 1e-9)
    }

    func testTakingAVibeOffAfterAnotherLeavesNothingBehind() throws {
        // Adding and taking off the nudges left warmth at ±2.8e-17, which kept
        // Reset, Apply and Save as my filter on for an invisible change.
        for (first, second) in [("analog", "moody"), ("golden", "analog")] {
            let a = try XCTUnwrap(AdjustVibes.preset(id: first))
            let b = try XCTUnwrap(AdjustVibes.preset(id: second))
            var settings = a.applied(to: .neutral, replacing: nil)
            settings = b.applied(to: settings, replacing: a)
            settings = b.removed(from: settings)
            XCTAssertEqual(settings, .neutral, "\(first) → \(second) → \(second) off")
            XCTAssertTrue(settings.isNeutral, "\(first) → \(second) → \(second) off")
        }
        // A real value next to the resting point stays hers.
        var nudged = AdjustmentSettings()
        nudged.warmth = 0.001
        XCTAssertEqual(nudged.clamped().warmth, 0.001)
    }

    // MARK: Rendering numbers

    func testBlurAndGrainGrowWithThePhoto() throws {
        // The editor previews a 1200 px copy and applies to the full photo.
        let preview = try XCTUnwrap(AdjustRendering.glow(0.6, longEdge: 1200))
        let full = try XCTUnwrap(AdjustRendering.glow(0.6, longEdge: 4800))
        XCTAssertEqual(full.radius / preview.radius, 4, accuracy: 1e-9)
        XCTAssertEqual(full.strength, preview.strength)
        XCTAssertEqual(full.threshold, preview.threshold)

        let previewGrain = try XCTUnwrap(AdjustRendering.grain(0.5, longEdge: 1200))
        let fullGrain = try XCTUnwrap(AdjustRendering.grain(0.5, longEdge: 4800))
        XCTAssertEqual(fullGrain.scale / previewGrain.scale, 4, accuracy: 1e-9)
        XCTAssertEqual(fullGrain.amount, previewGrain.amount)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(AdjustRendering.grain(1, longEdge: 200)).scale, 1, "never finer than a pixel")

        let previewVignette = try XCTUnwrap(AdjustRendering.vignette(0.5, width: 900, height: 1200))
        let fullVignette = try XCTUnwrap(AdjustRendering.vignette(0.5, width: 3600, height: 4800))
        XCTAssertEqual(fullVignette.radius / previewVignette.radius, 4, accuracy: 1e-9)
        XCTAssertEqual(previewVignette.radius, 0.6 * 750, accuracy: 1e-9, "the middle stays untouched")

        XCTAssertNil(AdjustRendering.glow(0, longEdge: 1200))
        XCTAssertNil(AdjustRendering.grain(0, longEdge: 1200))
        XCTAssertNil(AdjustRendering.vignette(0, width: 900, height: 1200))
    }

    func testMoreGlowIsMoreLight() throws {
        let soft = try XCTUnwrap(AdjustRendering.glow(0.2, longEdge: 1000))
        let strong = try XCTUnwrap(AdjustRendering.glow(1, longEdge: 1000))
        XCTAssertGreaterThan(strong.strength, soft.strength)
        XCTAssertGreaterThan(strong.radius, soft.radius)
        XCTAssertLessThan(strong.threshold, soft.threshold)
        XCTAssertGreaterThan(strong.threshold, 0.2, "the darkest tones never glow")
        XCTAssertLessThan(strong.strength, 1)
    }

    // MARK: Tone and tint

    private func curve(fade: Double = 0, highlights: Double = 0, shadows: Double = 0) -> ToneMap.Curve {
        ToneMap.Curve(ToneMap.curvePoints(fade: fade, highlights: highlights, shadows: shadows))
    }

    func testANeutralMapChangesNothing() {
        let identity = curve()
        for i in 0...100 {
            let x = Double(i) / 100
            XCTAssertEqual(identity(x), x, accuracy: 1e-12)
        }
        let cube = ToneMap.cube(for: .neutral, dimension: 8)
        XCTAssertEqual(cube.count, 8 * 8 * 8 * 4)
        var index = 0
        for b in 0..<8 {
            for g in 0..<8 {
                for r in 0..<8 {
                    XCTAssertEqual(Double(cube[index]), Double(r) / 7, accuracy: 1e-6)
                    XCTAssertEqual(Double(cube[index + 1]), Double(g) / 7, accuracy: 1e-6)
                    XCTAssertEqual(Double(cube[index + 2]), Double(b) / 7, accuracy: 1e-6)
                    XCTAssertEqual(cube[index + 3], 1)
                    index += 4
                }
            }
        }
    }

    func testEveryCurveRisesAndStaysInRange() {
        let steps = stride(from: -1.0, through: 1.0, by: 0.25)
        for fade in stride(from: 0.0, through: 1.0, by: 0.25) {
            for highlights in steps {
                for shadows in steps {
                    let map = curve(fade: fade, highlights: highlights, shadows: shadows)
                    var previous = -1.0
                    for i in 0...200 {
                        let y = map(Double(i) / 200)
                        XCTAssertGreaterThanOrEqual(y, 0)
                        XCTAssertLessThanOrEqual(y, 1)
                        XCTAssertGreaterThan(y, previous, "fade \(fade) highlights \(highlights) shadows \(shadows) at \(i)")
                        previous = y
                    }
                }
            }
        }
    }

    func testEachSliderMovesItsOwnTones() {
        let faded = curve(fade: 1)
        XCTAssertGreaterThan(faded(0), 0.1, "fade lifts black")
        XCTAssertLessThan(faded(1), 1, "and softens white")
        XCTAssertEqual(faded(0.5), 0.51, accuracy: 0.02, "the middle barely moves")

        let lifted = curve(shadows: 1)
        XCTAssertEqual(lifted(0), 0, "shadows keep black")
        XCTAssertGreaterThan(lifted(0.25), 0.3)
        XCTAssertEqual(lifted(0.9), 0.9, accuracy: 0.02)
        XCTAssertLessThan(curve(shadows: -1)(0.25), 0.2)

        let bright = curve(highlights: 1)
        XCTAssertEqual(bright(1), 1, "highlights keep white")
        XCTAssertGreaterThan(bright(0.75), 0.8)
        XCTAssertEqual(bright(0.1), 0.1, accuracy: 0.02)
        XCTAssertLessThan(curve(highlights: -1)(0.75), 0.7)
    }

    func testTintIsPinkOrLilacAndKeepsTheLight() {
        for luma in [0.1, 0.3, 0.8, 0.95] {
            let pink = ToneMap.tintShift(luma: luma, tint: -1)
            let lilac = ToneMap.tintShift(luma: luma, tint: 1)
            // Luma-neutral: the photo gets no lighter or darker.
            XCTAssertEqual(0.2126 * pink.r + 0.7152 * pink.g + 0.0722 * pink.b, 0, accuracy: 1e-9)
            XCTAssertEqual(0.2126 * lilac.r + 0.7152 * lilac.g + 0.0722 * lilac.b, 0, accuracy: 1e-9)
            XCTAssertGreaterThan(pink.r, pink.b, "pink leans red at \(luma)")
            XCTAssertGreaterThan(lilac.b, lilac.r, "lilac leans blue at \(luma)")
            XCTAssertLessThan(pink.g, 0)
            XCTAssertLessThan(lilac.g, 0)
        }
        XCTAssertTrue(ToneMap.tintShift(luma: 0.3, tint: 0) == (0, 0, 0))
        // Stronger in the shadows than in the middle, where most skin is.
        XCTAssertGreaterThan(abs(ToneMap.tintShift(luma: 0.1, tint: 1).b), abs(ToneMap.tintShift(luma: 0.6, tint: 1).b) * 3)
    }

    /// Skin from very light to very dark keeps its own colour at the tint the
    /// vibes use: a change of at most 2% per channel, and the same order of
    /// red, green and blue (no grey, purple or green skin).
    func testSkinStaysNaturalAtModerateTints() {
        let skins: [(Double, Double, Double)] = [
            (0.96, 0.84, 0.76), (0.89, 0.71, 0.60), (0.78, 0.57, 0.44), (0.63, 0.43, 0.31),
            (0.47, 0.31, 0.22), (0.35, 0.22, 0.16), (0.24, 0.15, 0.11),
        ]
        let identity = curve()
        for tint in [-0.3, -0.2, 0.2, 0.3] {
            for skin in skins {
                let mapped = ToneMap.map(skin.0, skin.1, skin.2, curve: identity, tint: tint)
                XCTAssertLessThanOrEqual(abs(mapped.r - skin.0), 0.02, "\(skin) at \(tint)")
                XCTAssertLessThanOrEqual(abs(mapped.g - skin.1), 0.02, "\(skin) at \(tint)")
                XCTAssertLessThanOrEqual(abs(mapped.b - skin.2), 0.02, "\(skin) at \(tint)")
                XCTAssertGreaterThan(mapped.r, mapped.g)
                XCTAssertGreaterThan(mapped.g, mapped.b)
            }
        }
    }

    func testTheCubeMatchesTheMap() {
        let settings = AdjustmentSettings(fade: 0.3, tint: -0.6, highlights: 0.4, shadows: -0.2)
        let dimension = 9
        let cube = ToneMap.cube(for: settings, dimension: dimension)
        let map = curve(fade: 0.3, highlights: 0.4, shadows: -0.2)
        for (r, g, b) in [(0, 0, 0), (8, 8, 8), (2, 5, 7), (8, 0, 3), (4, 4, 1)] {
            let index = ((b * dimension + g) * dimension + r) * 4
            let expected = ToneMap.map(Double(r) / 8, Double(g) / 8, Double(b) / 8, curve: map, tint: -0.6)
            XCTAssertEqual(Double(cube[index]), expected.r, accuracy: 1e-6)
            XCTAssertEqual(Double(cube[index + 1]), expected.g, accuracy: 1e-6)
            XCTAssertEqual(Double(cube[index + 2]), expected.b, accuracy: 1e-6)
        }
        XCTAssertTrue(cube.allSatisfy { (0...1).contains($0) })
        XCTAssertTrue(settings.hasToneMap)
        XCTAssertFalse(AdjustmentSettings(vignette: 1, glow: 1, grain: 1).hasToneMap)
    }
}
