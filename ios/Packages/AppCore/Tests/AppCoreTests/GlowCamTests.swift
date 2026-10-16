import XCTest
@testable import AppCore

final class GlowCamTests: XCTestCase {
    // MARK: Looks and light

    func testLooksAreTheEditorsVibesInOrder() {
        XCTAssertEqual(GlowCam.vibes.map(\.id), ["dreamy", "golden", "analog", "moody"])
        XCTAssertEqual(GlowCam.vibes.map(\.name), ["Dreamy", "Golden", "Analog", "Moody"])
    }

    func testNaturalWithCentredSlidersChangesNothing() {
        let settings = GlowCamSettings()
        XCTAssertNil(settings.vibe)
        XCTAssertTrue(settings.adjustment.isNeutral)
        XCTAssertFalse(settings.hasTint)
        XCTAssertFalse(settings.sparkle)
        XCTAssertFalse(settings.hasLightChange)
    }

    func testAVibeGetsTheEditorsNumbers() {
        for vibe in GlowCam.vibes {
            XCTAssertEqual(GlowCamSettings(vibeID: vibe.id).adjustment, vibe.applied(to: .neutral, replacing: nil), vibe.id)
        }
        XCTAssertNil(GlowCamSettings(vibeID: "unknown").vibe)
        XCTAssertTrue(GlowCamSettings(vibeID: "unknown").adjustment.isNeutral)
    }

    func testQuickSlidersStayInsideTheEditorsRanges() {
        var previous: (brightness: Double, contrast: Double)?
        for slider in stride(from: -1.0, through: 1.0, by: 0.25) {
            let brightness = GlowCam.brightness(slider: slider)
            let contrast = GlowCam.contrast(slider: slider)
            XCTAssertTrue(AdjustmentParameter.brightness.range.contains(brightness))
            XCTAssertTrue(AdjustmentParameter.contrast.range.contains(contrast))
            if let previous {
                XCTAssertGreaterThan(brightness, previous.brightness)
                XCTAssertGreaterThan(contrast, previous.contrast)
            }
            previous = (brightness, contrast)
        }
        XCTAssertEqual(GlowCam.brightness(slider: 0), 0)
        XCTAssertEqual(GlowCam.contrast(slider: 0), 1)
        XCTAssertEqual(GlowCam.brightness(slider: 7), GlowCam.brightness(slider: 1))
        XCTAssertEqual(GlowCam.contrast(slider: -7), GlowCam.contrast(slider: -1))
        XCTAssertEqual(GlowCam.brightness(slider: .nan), 0)
    }

    func testSlidersSetHerLightUnderTheVibe() throws {
        let golden = try XCTUnwrap(AdjustVibes.preset(id: "golden"))
        let settings = GlowCamSettings(vibeID: "golden", brightness: 1, contrast: -1).adjustment
        XCTAssertEqual(settings.brightness, 0.15, accuracy: 1e-9)
        XCTAssertEqual(settings.contrast, 0.85 + golden.shift(of: .contrast), accuracy: 1e-9)
        XCTAssertEqual(settings.warmth, golden.settings.warmth, accuracy: 1e-9)
        XCTAssertEqual(settings.glow, golden.settings.glow)
        XCTAssertTrue(GlowCamSettings(contrast: 0.5).hasLightChange)
    }

    // MARK: Makeup colours

    func testTintIsSheerMakeupStudioColour() throws {
        XCTAssertTrue(GlowCamSettings(lips: .rosy).hasTint)
        XCTAssertTrue(GlowCamSettings(cheeks: .softBlush).hasTint)
        for lips in GlowCam.lipColors {
            let tint = try XCTUnwrap(GlowCam.lipTint(lips), lips.rawValue)
            XCTAssertEqual(tint.color, GlowColor(hex: try XCTUnwrap(lips.swatch)))
            // A wash, never paint.
            XCTAssertTrue((0.3...0.6).contains(tint.opacity), lips.rawValue)
            XCTAssertTrue((0...0.4).contains(tint.depth), lips.rawValue)
        }
        for cheeks in GlowCam.cheekColors {
            let tint = try XCTUnwrap(GlowCam.cheekTint(cheeks), cheeks.rawValue)
            XCTAssertEqual(tint.color, GlowColor(hex: try XCTUnwrap(cheeks.swatch)))
            XCTAssertTrue((0.15...0.4).contains(tint.opacity), cheeks.rawValue)
        }
        XCTAssertNil(GlowCam.lipTint(.none))
        XCTAssertNil(GlowCam.cheekTint(.none))
        // Gloss and shine aren't colours, so the live palette leaves them out.
        XCTAssertNil(GlowCam.lipTint(.clearGloss))
        XCTAssertNil(GlowCam.cheekTint(.iridescentShine))
        XCTAssertGreaterThan(try XCTUnwrap(GlowCam.lipTint(.cherryRed)).depth, try XCTUnwrap(GlowCam.lipTint(.softPink)).depth)
    }

    func testColoursParseFromSwatches() {
        XCTAssertEqual(GlowColor(hex: "#FF0080"), GlowColor(red: 1, green: 0, blue: 128.0 / 255))
        XCTAssertEqual(GlowColor(hex: "FFFFFF")?.luma ?? 0, 1, accuracy: 1e-9)
        XCTAssertNil(GlowColor(hex: "#FFF"))
        XCTAssertNil(GlowColor(hex: "#ZZZZZZ"))
    }

    // MARK: Sparkle

    func testSparkleIsTheSameOnEveryRender() {
        XCTAssertEqual(SparkleField.glints(at: 3.7), SparkleField.glints(at: 3.7))
        XCTAssertEqual(SparkleField.glints(at: 0).count, SparkleField.count)
        XCTAssertEqual(SparkleField.glints(at: -2), SparkleField.glints(at: 0))
        XCTAssertEqual(SparkleField.glints(at: .nan), SparkleField.glints(at: 0))
        let kinds = Set(SparkleField.glints(at: 0).map { "\($0.kind)" })
        XCTAssertEqual(kinds, ["bokeh", "star"])
    }

    func testSparkleStaysSubtleLightAndInTheFrame() {
        var total = 0.0
        var samples = 0
        for time in stride(from: 0.0, to: 40, by: 0.37) {
            for glint in SparkleField.glints(at: time) {
                XCTAssertTrue((0...1).contains(glint.opacity))
                XCTAssertTrue(glint.radius > 0 && glint.radius <= 0.04)
                XCTAssertTrue((0..<1).contains(glint.y))
                XCTAssertTrue((-0.05...1.05).contains(glint.x))
                XCTAssertGreaterThan(glint.color.luma, 0.8)
                total += glint.opacity
                samples += 1
            }
        }
        XCTAssertLessThan(total / Double(samples), 0.3)
    }

    func testSparkleKeepsTheMiddleClear() {
        for time in stride(from: 0.0, to: 60, by: 0.21) {
            for glint in SparkleField.glints(at: time) {
                let distance = ((glint.x - SparkleField.clearX) * (glint.x - SparkleField.clearX)
                    + (glint.y - SparkleField.clearY) * (glint.y - SparkleField.clearY)).squareRoot()
                if distance <= SparkleField.clearRadius { XCTAssertEqual(glint.opacity, 0) }
            }
        }
    }

    func testSparkleDriftsSmoothlyAndTwinkles() {
        var brightest = [Double](repeating: 0, count: SparkleField.count)
        var faintest = [Double](repeating: 1, count: SparkleField.count)
        for frame in 0..<(30 * 20) {
            let time = Double(frame) / 30
            let now = SparkleField.glints(at: time)
            let next = SparkleField.glints(at: time + 1.0 / 30)
            for index in now.indices {
                XCTAssertLessThan(abs(next[index].x - now[index].x), 0.005)
                // Wrapping from the top back to the bottom happens unseen (faded out).
                if abs(next[index].y - now[index].y) > 0.5 {
                    XCTAssertLessThan(now[index].opacity, 0.05)
                } else {
                    XCTAssertLessThan(abs(next[index].y - now[index].y), 0.005)
                }
                brightest[index] = max(brightest[index], now[index].opacity)
                faintest[index] = min(faintest[index], now[index].opacity)
            }
        }
        let stars = SparkleField.glints(at: 0).indices.filter { SparkleField.glints(at: 0)[$0].kind == .star }
        XCTAssertTrue(stars.contains { brightest[$0] > 0.4 && faintest[$0] < 0.05 })
    }

    // MARK: Cheeks and lips

    func testCheeksSitBelowTheEyesAboveTheMouthInsideTheFace() {
        let cheeks = FaceTintGeometry.cheeks(of: Self.face())
        XCTAssertEqual(cheeks.count, 2)
        guard cheeks.count == 2 else { return }
        XCTAssertEqual(cheeks[0].center.x, -cheeks[1].center.x, accuracy: 1e-9)
        XCTAssertEqual(cheeks[0].center.y, cheeks[1].center.y, accuracy: 1e-9)
        for cheek in cheeks {
            XCTAssertLessThan(cheek.center.y + cheek.radiusY, -10, "under the eyes")
            XCTAssertGreaterThan(cheek.center.y - cheek.radiusY, -87, "above the mouth")
            XCTAssertLessThan(abs(cheek.center.x) + cheek.radiusX, 120, "inside the face")
            XCTAssertGreaterThan(abs(cheek.center.x) - cheek.radiusX, 18, "beside the nose")
            XCTAssertEqual(cheek.angle, 0, accuracy: 1e-9)
        }
    }

    func testCheeksFollowATiltedHead() {
        let angle = 25 * Double.pi / 180
        let shift = FacePoint(x: 300, y: 200)
        let upright = FaceTintGeometry.cheeks(of: Self.face())
        let tilted = FaceTintGeometry.cheeks(of: Self.face(at: shift, angle: angle))
        XCTAssertEqual(tilted.count, 2)
        for (a, b) in zip(upright, tilted) {
            let expected = Self.rotate(a.center, by: angle) + shift
            XCTAssertEqual(b.center.x, expected.x, accuracy: 1e-6)
            XCTAssertEqual(b.center.y, expected.y, accuracy: 1e-6)
            XCTAssertEqual(b.angle, angle, accuracy: 1e-9)
            XCTAssertEqual(b.radiusX, a.radiusX, accuracy: 1e-9)
        }
    }

    func testBlushStaysOnTheFarCheekOfATurnedHead() {
        var face = Self.face()
        // A head turned to her left: the face's right edge is close to the eye.
        face.faceContour = face.faceContour.map { $0.x > 0 ? FacePoint(x: $0.x * 0.6, y: $0.y) : $0 }
        let cheeks = FaceTintGeometry.cheeks(of: face)
        XCTAssertLessThanOrEqual(cheeks[1].center.x + 0.8 * cheeks[1].radiusX, 72 + 1e-9)
        XCTAssertEqual(cheeks[0].center.x, -60, accuracy: 1e-9)
    }

    func testLipTintStaysInsideTheLipLineAndOffTheTeeth() throws {
        let face = Self.face()
        let plan = try XCTUnwrap(FaceTintGeometry.lips(of: face))
        XCTAssertEqual(plan.feather, 0.035 * 90, accuracy: 0.01)
        for point in plan.outline {
            XCTAssertTrue(Self.contains(face.outerLips, point), "\(point) is over the lip line")
            XCTAssertGreaterThanOrEqual(Self.distanceToEdge(of: face.outerLips, from: point), plan.feather * 0.5)
        }
        for point in face.innerLips {
            XCTAssertTrue(Self.contains(plan.opening, point), "\(point) of the opening would be tinted")
        }
        let fewPoints = FaceLandmarks(outerLips: Array(face.outerLips.prefix(4)), leftEye: face.leftEye, rightEye: face.rightEye)
        XCTAssertNil(FaceTintGeometry.lips(of: fewPoints))
        XCTAssertTrue(FaceTintGeometry.cheeks(of: FaceLandmarks(outerLips: [], leftEye: [], rightEye: [])).isEmpty)
    }

    func testSmoothOutlinePassesThroughItsPoints() {
        let square = [FacePoint(x: 0, y: 0), FacePoint(x: 10, y: 0), FacePoint(x: 10, y: 10), FacePoint(x: 0, y: 10)]
        let curve = FaceTintGeometry.smoothOutline(square, samplesPerSegment: 4)
        XCTAssertEqual(curve.count, 16)
        for (index, point) in square.enumerated() {
            XCTAssertEqual(curve[index * 4].x, point.x, accuracy: 1e-9)
            XCTAssertEqual(curve[index * 4].y, point.y, accuracy: 1e-9)
        }
        for point in curve {
            XCTAssertTrue((-2...12).contains(point.x) && (-2...12).contains(point.y), "\(point) overshoots")
        }
        XCTAssertEqual(FaceTintGeometry.smoothOutline(Array(square.prefix(2))), Array(square.prefix(2)))
    }

    func testInsetMovesEveryPointTowardTheCentre() {
        let square = [FacePoint(x: 0, y: 0), FacePoint(x: 10, y: 0), FacePoint(x: 10, y: 10), FacePoint(x: 0, y: 10)]
        let center = FacePoint(x: 5, y: 5)
        for (original, moved) in zip(square, FaceTintGeometry.inset(square, by: 1)) {
            XCTAssertEqual(original.distance(to: moved), 1, accuracy: 1e-9)
            XCTAssertEqual(moved.distance(to: center), original.distance(to: center) - 1, accuracy: 1e-9)
        }
        for (original, moved) in zip(square, FaceTintGeometry.inset(square, by: -1)) {
            XCTAssertEqual(moved.distance(to: center), original.distance(to: center) + 1, accuracy: 1e-9)
        }
        // Either way round.
        XCTAssertEqual(FaceTintGeometry.inset(Array(square.reversed()), by: 1).map { $0.distance(to: center) },
                       FaceTintGeometry.inset(square, by: 1).reversed().map { $0.distance(to: center) })
    }

    // MARK: Smoothing

    func testANewFaceFadesIn() {
        var smoother = FaceTrackSmoother()
        smoother.update([Self.face()], at: 0)
        XCTAssertEqual(smoother.advance(to: 0), [])
        XCTAssertEqual(smoother.advance(to: 0.1).first?.opacity ?? 0, 0.5, accuracy: 1e-9)
        XCTAssertEqual(smoother.advance(to: 0.3).first?.opacity, 1)
    }

    func testAFaceGlidesToItsNewPlace() throws {
        var smoother = FaceTrackSmoother()
        smoother.update([Self.face()], at: 0)
        _ = smoother.advance(to: 0)
        _ = smoother.advance(to: 0.3)
        smoother.update([Self.face(at: FacePoint(x: 20, y: 0))], at: 0.3)
        var last = 0.0
        for frame in 1...12 {
            let faces = smoother.advance(to: 0.3 + Double(frame) / 30)
            XCTAssertEqual(faces.count, 1)
            let x = try XCTUnwrap(faces.first?.landmarks.center?.x)
            if frame == 1 { XCTAssertLessThan(x, 15, "no jump") }
            XCTAssertGreaterThan(x, last)
            XCTAssertLessThanOrEqual(x, 20 + 1e-9)
            last = x
        }
        XCTAssertEqual(last, 20, accuracy: 0.5)
    }

    func testABigJumpSnapsAndSomeoneFarAwayIsSomeoneElse() throws {
        var smoother = FaceTrackSmoother()
        smoother.update([Self.face()], at: 0)
        _ = smoother.advance(to: 0)
        let id = try XCTUnwrap(smoother.advance(to: 0.3).first?.id)
        smoother.update([Self.face(at: FacePoint(x: 80, y: 0))], at: 0.3)
        let snapped = smoother.advance(to: 0.33)
        XCTAssertEqual(snapped.first?.id, id)
        XCTAssertEqual(snapped.first?.landmarks.center?.x ?? 0, 80, accuracy: 1e-9)

        smoother.update([Self.face(at: FacePoint(x: 600, y: 0))], at: 0.4)
        let faces = smoother.advance(to: 0.5)
        XCTAssertEqual(faces.count, 2)
        XCTAssertEqual(Set(faces.map(\.id)).count, 2)
    }

    func testALostFaceKeepsItsTintBrieflyThenFades() {
        var smoother = FaceTrackSmoother()
        smoother.update([Self.face()], at: 0)
        _ = smoother.advance(to: 0)
        _ = smoother.advance(to: 0.3)
        smoother.update([], at: 0.3)
        XCTAssertEqual(smoother.advance(to: 0.34).first?.opacity, 1)
        let fading = smoother.advance(to: 0.5).first?.opacity ?? 0
        XCTAssertTrue(fading > 0 && fading < 1)
        XCTAssertEqual(smoother.advance(to: 0.75), [])
        XCTAssertTrue(smoother.isEmpty)
    }

    func testSeveralFacesKeepTheirOwnTint() throws {
        var smoother = FaceTrackSmoother()
        let left = FacePoint(x: -200, y: 0), right = FacePoint(x: 200, y: 0)
        smoother.update([Self.face(at: left), Self.face(at: right)], at: 0)
        _ = smoother.advance(to: 0)
        let before = smoother.advance(to: 0.3)
        XCTAssertEqual(before.count, 2)
        let leftID = try XCTUnwrap(before.first { ($0.landmarks.center?.x ?? 0) < 0 }?.id)
        smoother.update([Self.face(at: right + FacePoint(x: 10, y: 0)), Self.face(at: left + FacePoint(x: 10, y: 0))], at: 0.3)
        let after = smoother.advance(to: 0.6)
        XCTAssertEqual(after.first { ($0.landmarks.center?.x ?? 0) < 0 }?.id, leftID)
    }

    func testSmoothingStaysOnTheFaceFrameAfterFrame() throws {
        var smoother = FaceTrackSmoother()
        var frame = 0
        // Ten seconds at 30 fps; Vision looks every third frame and lands a
        // little off each time, as it does.
        while frame < 300 {
            let time = Double(frame) / 30
            if frame % 3 == 0 {
                let wobble = FacePoint(x: Double(frame % 7) - 3, y: Double(frame % 5) - 2)
                smoother.update([Self.face(at: FacePoint(x: 500, y: 400) + wobble)], at: time)
            }
            let faces = smoother.advance(to: time)
            if frame > 10 {
                XCTAssertEqual(faces.count, 1)
                let center = try XCTUnwrap(faces.first?.landmarks.center)
                XCTAssertEqual(center.x, 500, accuracy: 5)
                XCTAssertEqual(center.y, 400 - 52.5, accuracy: 5)
                XCTAssertEqual(faces.first?.landmarks.eyeDistance ?? 0, 100, accuracy: 1)
            }
            frame += 1
        }
    }

    func testAtMostFourFacesTheBiggestFirst() {
        var smoother = FaceTrackSmoother()
        let faces = (0..<6).map { Self.face(at: FacePoint(x: Double($0) * 400, y: 0), eyeDistance: 100 - Double($0) * 10) }
        smoother.update(faces, at: 0)
        _ = smoother.advance(to: 0)
        let shown = smoother.advance(to: 0.3)
        XCTAssertEqual(shown.count, FaceTrackSmoother.maxFaces)
        XCTAssertTrue(shown.allSatisfy { $0.landmarks.eyeDistance >= 70 - 1e-9 })
        smoother.reset()
        XCTAssertTrue(smoother.isEmpty)
    }

    // MARK: Pacing

    func testLooksAreThrottledAndNeverOverlap() {
        var pacing = MakeupTintPacing()
        XCTAssertTrue(pacing.shouldDetect(at: 0))
        XCTAssertFalse(pacing.shouldDetect(at: 0.5), "one look at a time")
        pacing.detectionFinished(duration: 0.02)
        XCTAssertEqual(pacing.interval, MakeupTintPacing.fastestInterval, accuracy: 1e-9)
        XCTAssertFalse(pacing.shouldDetect(at: 0.05))
        XCTAssertTrue(pacing.shouldDetect(at: 0.09))
    }

    func testSlowLooksComeLessOften() {
        var pacing = MakeupTintPacing()
        XCTAssertTrue(pacing.shouldDetect(at: 0))
        pacing.detectionFinished(duration: 0.2)
        XCTAssertEqual(pacing.interval, 0.4, accuracy: 1e-9)
        XCTAssertFalse(pacing.shouldDetect(at: 0.3))
        XCTAssertTrue(pacing.shouldDetect(at: 0.41))
        pacing.detectionFinished(duration: 0.5)
        XCTAssertEqual(pacing.interval, MakeupTintPacing.slowestInterval, accuracy: 1e-9)
    }

    func testSlowFramesPauseTheTintAfterAWhile() {
        var pacing = MakeupTintPacing()
        var time = 0.0
        func frames(until end: Double, taking duration: Double) {
            while time < end {
                pacing.frameDrawn(at: time, duration: duration)
                time += 1.0 / 30
            }
        }
        frames(until: 1.4, taking: 0.08)
        XCTAssertFalse(pacing.isPaused, "the first frames are always slow")
        frames(until: 3.3, taking: 0.08)
        XCTAssertFalse(pacing.isPaused, "not for a moment")
        frames(until: 3.7, taking: 0.08)
        XCTAssertTrue(pacing.isPaused)
        XCTAssertFalse(pacing.shouldDetect(at: time + 1))
    }

    func testAHiccupDoesNotPauseTheTint() {
        var pacing = MakeupTintPacing()
        var time = 0.0
        for (end, duration) in [(3.0, 0.02), (3.3, 0.1), (6.0, 0.02)] {
            while time < end {
                pacing.frameDrawn(at: time, duration: duration)
                time += 1.0 / 30
            }
        }
        XCTAssertFalse(pacing.isPaused)
    }

    func testHeatPausesTheTintAtOnce() {
        var pacing = MakeupTintPacing()
        pacing.pause()
        XCTAssertTrue(pacing.isPaused)
        XCTAssertFalse(pacing.shouldDetect(at: 0))
    }

    // MARK: Helpers

    /// A front-facing face in pixels (y up): eyes `eyeDistance` apart on the
    /// x axis around `center`, nose and mouth below, the jaw's outline round
    /// the bottom; then turned by `angle`.
    static func face(at center: FacePoint = FacePoint(x: 0, y: 0), eyeDistance d: Double = 100, angle: Double = 0) -> FaceLandmarks {
        func ring(_ middle: FacePoint, _ rx: Double, _ ry: Double, _ count: Int) -> [FacePoint] {
            (0..<count).map { index in
                let theta = 2 * Double.pi * Double(index) / Double(count)
                return FacePoint(x: middle.x + rx * cos(theta), y: middle.y + ry * sin(theta))
            }
        }
        let nose = (0...6).map { FacePoint(x: 0, y: -0.05 * d - Double($0) * 0.65 * d / 6) }
            + [FacePoint(x: -0.18 * d, y: -0.62 * d), FacePoint(x: 0.18 * d, y: -0.62 * d)]
        let contour = (0...16).map { index -> FacePoint in
            let theta = Double.pi + Double.pi * Double(index) / 16
            return FacePoint(x: 1.2 * d * cos(theta), y: 1.75 * d * sin(theta))
        }
        let face = FaceLandmarks(
            outerLips: ring(FacePoint(x: 0, y: -1.05 * d), 0.45 * d, 0.18 * d, 14),
            innerLips: ring(FacePoint(x: 0, y: -1.05 * d), 0.32 * d, 0.04 * d, 8),
            leftEye: ring(FacePoint(x: -0.5 * d, y: 0), 0.22 * d, 0.08 * d, 6),
            rightEye: ring(FacePoint(x: 0.5 * d, y: 0), 0.22 * d, 0.08 * d, 6),
            nose: nose,
            faceContour: contour
        )
        return face.mapped { rotate($0, by: angle) + center }
    }

    static func rotate(_ point: FacePoint, by angle: Double) -> FacePoint {
        FacePoint(x: point.x * cos(angle) - point.y * sin(angle), y: point.x * sin(angle) + point.y * cos(angle))
    }

    /// Ray casting.
    static func contains(_ polygon: [FacePoint], _ point: FacePoint) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (a.y > point.y) != (b.y > point.y), point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    static func distanceToEdge(of polygon: [FacePoint], from point: FacePoint) -> Double {
        var nearest = Double.infinity
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            let ab = b - a
            let t = min(max((point - a).dot(ab) / max(ab.dot(ab), 1e-12), 0), 1)
            nearest = min(nearest, point.distance(to: a + ab * t))
        }
        return nearest
    }
}
