import XCTest
@testable import AppCore

final class EnhanceTests: XCTestCase {
    // MARK: Prompts

    func testEveryModeKeepsTheSkinAndIdentityGuardWordForWord() {
        XCTAssertEqual(DirectAIPrompts.enhance, "Enhance this photo: make it sharper and more detailed, reduce blur and noise, restore faces naturally and gently improve the lighting. Keep real skin texture, freckles, moles, pores and blemishes; don't retouch or smooth the skin, and don't reshape the face or body. Keep the composition, colors, every person and their identity exactly the same.",
                       "Unblur is the AI Enhance of 1.0, unchanged")
        for mode in EnhanceMode.allCases {
            XCTAssertTrue(mode.prompt.contains(EnhanceMode.skinGuard), mode.rawValue)
            XCTAssertTrue(mode.prompt.contains("every person and their identity exactly the same"), mode.rawValue)
            // The only "smooth" in any instruction is the guard's "don't … smooth".
            let rest = mode.prompt.replacingOccurrences(of: EnhanceMode.skinGuard, with: "").lowercased()
            for word in ["smooth", "retouch", "flawless", "perfect skin", "slim", "beautif"] {
                XCTAssertFalse(rest.contains(word), "\(mode.rawValue) asks for \(word)")
            }
            XCTAssertTrue(ContentPolicy.evaluate(mode.prompt, operation: .magicEdit).isAllowed, mode.rawValue)
            XCTAssertLessThan(mode.prompt.count, 1_200, "the server's prompt cap")
        }
        // Only colourising may change the colours.
        XCTAssertFalse(EnhanceMode.restoreColor.prompt.contains(EnhanceMode.identityGuard))
        XCTAssertTrue(EnhanceMode.restore.prompt.contains("keep it black and white"))
        XCTAssertTrue(EnhanceMode.lowLight.prompt.contains("no added glow"))
    }

    func testOptionsMapToModes() {
        XCTAssertNil(EnhanceOption.quickFix.mode())
        XCTAssertFalse(EnhanceOption.quickFix.isCloud)
        XCTAssertEqual(EnhanceOption.restore.mode(addingColor: false), .restore)
        XCTAssertEqual(EnhanceOption.restore.mode(addingColor: true), .restoreColor)
        XCTAssertEqual(EnhanceOption.unblur.mode(addingColor: true), .unblur, "Add color is Restore's alone")
        XCTAssertEqual(EnhanceOption.available(cloudAI: false), [.quickFix], "under 13: the free fix only")
        XCTAssertEqual(EnhanceOption.available(cloudAI: true).first, .quickFix)
    }

    func testRequestCarriesTheModeOnly() throws {
        let request = GenerationRequest(operation: .enhance, image: "data:x", enhanceMode: .lowLight)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        XCTAssertEqual(json?["enhance_mode"] as? String, "low_light")
        XCTAssertNil(json?["prompt"])
        let old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(GenerationRequest(operation: .enhance, image: "data:x"))) as? [String: Any]
        XCTAssertNil(old?["enhance_mode"], "no mode: the server's unblur, as in 1.0")
    }

    // MARK: Sizes

    func testUpscaleDoublesSmallPhotosUpToTheEditorsSize() {
        XCTAssertEqual(EnhanceSizing.upscaleFactor(longEdge: 800), 2)
        XCTAssertEqual(EnhanceSizing.upscaleFactor(longEdge: 1600), 1.28, accuracy: 0.001)
        XCTAssertEqual(EnhanceSizing.upscaleFactor(longEdge: 2048), 1)
        XCTAssertEqual(EnhanceSizing.upscaleFactor(longEdge: 4000), 1, "never shrinks")
        XCTAssertTrue(EnhanceSizing.canUpscale(longEdge: 1200))
        XCTAssertFalse(EnhanceSizing.canUpscale(longEdge: 1800))
    }

    func testAIResultsNeverComeBackSmaller() {
        // The model answers at about 1k.
        XCTAssertEqual(EnhanceSizing.resultLongEdge(source: 2048, result: 1024, mode: .unblur), 2048)
        XCTAssertEqual(EnhanceSizing.resultLongEdge(source: 640, result: 1024, mode: .unblur), 1024)
        XCTAssertEqual(EnhanceSizing.resultLongEdge(source: 640, result: 1024, mode: .hd), 1280, "HD: twice her photo")
        XCTAssertEqual(EnhanceSizing.resultLongEdge(source: 1500, result: 1024, mode: .hd), 2048, "up to the editor's size")
    }

    // MARK: Measuring

    /// A synthetic photo: soft gradients with sharp-edged shapes, optional noise.
    private func photo(width: Int = 320, height: Int = 240, blur: Bool = false, noise: Double = 0, dim: Double = 1,
                       gray: Bool = false, faded: Bool = false) -> [UInt8] {
        var generator = SplitMix(seed: 7)
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                var r = 40 + 160 * Double(x) / Double(width)
                var g = 60 + 120 * Double(y) / Double(height)
                var b = 200 - 140 * Double(x) / Double(width)
                // Checkers and stripes: lots of sharp edges, unless blurred.
                let edge = ((x / 12) + (y / 12)) % 2 == 0 ? 50.0 : -50.0
                let soft = 50 * sin(Double(x) / 9) * sin(Double(y) / 9)
                let detail = blur ? soft * 0.15 : edge
                r += detail
                g += detail
                b += detail
                if gray {
                    let l = 0.299 * r + 0.587 * g + 0.114 * b
                    (r, g, b) = (l, l, l)
                }
                if faded {
                    (r, g, b) = (60 + r * 0.5, 60 + g * 0.5, 60 + b * 0.5)
                }
                let n = noise > 0 ? generator.gaussian() * noise : 0
                let i = 4 * (y * width + x)
                pixels[i] = UInt8(max(0, min(255, (r + n) * dim)))
                pixels[i + 1] = UInt8(max(0, min(255, (g + n) * dim)))
                pixels[i + 2] = UInt8(max(0, min(255, (b + n) * dim)))
            }
        }
        return pixels
    }

    private func measure(_ pixels: [UInt8]) -> PhotoQuality {
        PhotoQuality.measure(rgba: pixels, width: 320, height: 240)
    }

    func testMeasuresTellBlurNoiseDarkAndOldPrints() {
        let sharp = measure(photo())
        XCTAssertFalse(sharp.isBlurry)
        XCTAssertFalse(sharp.isNoisy)
        XCTAssertFalse(sharp.isLowLight)
        XCTAssertFalse(sharp.looksOld)
        XCTAssertNil(EnhanceAdvisor.suggestion(for: sharp, cloudAI: true), "a good photo gets no fix")

        let blurry = measure(photo(blur: true))
        XCTAssertTrue(blurry.isBlurry, "\(blurry.sharpness)")
        XCTAssertEqual(EnhanceAdvisor.suggestion(for: blurry, cloudAI: true), EnhanceSuggestion(option: .unblur, reason: .blurry))

        let noisy = measure(photo(noise: 12))
        XCTAssertTrue(noisy.isNoisy, "\(noisy.noise)")
        XCTAssertFalse(noisy.isBlurry, "noise isn't mistaken for detail lost")
        XCTAssertEqual(EnhanceAdvisor.suggestion(for: noisy, cloudAI: true)?.option, .quickFix, "the free fix handles noise")

        let dark = measure(photo(dim: 0.3))
        XCTAssertTrue(dark.isLowLight)
        XCTAssertEqual(EnhanceAdvisor.suggestion(for: dark, cloudAI: true)?.option, .lowLight)

        let old = measure(photo(blur: true, gray: true, faded: true))
        XCTAssertTrue(old.isMonochrome)
        XCTAssertTrue(old.looksOld)
        XCTAssertEqual(EnhanceAdvisor.suggestion(for: old, cloudAI: true), EnhanceSuggestion(option: .restore, reason: .oldPrint))

        let crispBlackAndWhite = measure(photo(gray: true))
        XCTAssertTrue(crispBlackAndWhite.isMonochrome)
        XCTAssertFalse(crispBlackAndWhite.looksOld, "a crisp black-and-white photo of today isn't an old print")
    }

    func testWithoutCloudAIEveryFixIsTheFreeOne() {
        for quality in [PhotoQuality(sharpness: 10), PhotoQuality(meanLuma: 0.1, highLuma: 0.3), PhotoQuality(noise: 6)] {
            XCTAssertEqual(EnhanceAdvisor.suggestion(for: quality, cloudAI: false)?.option, .quickFix)
        }
        XCTAssertNil(EnhanceAdvisor.suggestion(for: nil, cloudAI: true))
    }

    func testIdeasLeadWithTheFix() {
        let insight = PhotoInsight(labels: ["sky"], quality: PhotoQuality(sharpness: 10))
        let ideas = LookSuggester.suggest(for: insight, date: Date(timeIntervalSince1970: 1_780_000_000), freeEffects: ["instant", "vhs"])
        XCTAssertEqual(ideas.first, .enhance(.unblur))
        XCTAssertLessThanOrEqual(ideas.count, LookSuggester.maxSuggestions)
        let young = LookSuggester.suggest(for: insight, date: Date(timeIntervalSince1970: 1_780_000_000), freeEffects: ["instant"], cloudAI: false)
        XCTAssertEqual(young.first, .enhance(.quickFix))
        let fine = LookSuggester.suggest(for: PhotoInsight(labels: ["sky"]), date: Date(timeIntervalSince1970: 1_780_000_000), freeEffects: ["instant"])
        XCTAssertFalse(fine.contains { if case .enhance = $0 { return true } else { return false } })
    }

    // MARK: Quick fix

    func testQuickFixScalesWithThePhotoAndLeavesCleanPhotosUndenoised() {
        let light = AutoAdjustment(brightness: 0.05, contrast: 1.1, saturation: 1.05, warmth: 0.1, sharpness: 0.3)
        let preview = QuickFix.plan(light: light, noise: 4, longEdge: 1200)
        let full = QuickFix.plan(light: light, noise: 4, longEdge: 2400)
        XCTAssertEqual(full.clarityRadius / preview.clarityRadius, 2, accuracy: 1e-9)
        XCTAssertEqual(full.sharpenRadius / preview.sharpenRadius, 2, accuracy: 1e-9)
        XCTAssertGreaterThan(full.noiseLevel, preview.noiseLevel, "the bigger copy has more noise to remove")
        XCTAssertEqual(preview.light.sharpness, 0, "sharpening is Quick fix's own")
        XCTAssertEqual(preview.light.brightness, 0.05)
        XCTAssertEqual(QuickFix.plan(light: light, noise: 1, longEdge: 2400).noiseLevel, 0, "clean photos keep their texture")
        XCTAssertLessThanOrEqual(QuickFix.plan(light: light, noise: 40, longEdge: 4000).noiseLevel, 0.06, "gentle, even on a grainy photo")
        XCTAssertEqual(QuickFix.plan(light: light, noise: 1, longEdge: 900, upscale: true).scale, 2)
        XCTAssertEqual(QuickFix.plan(light: light, noise: 1, longEdge: 900).scale, 1)
    }
}

/// Deterministic noise for the tests.
private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
    }

    /// Box–Muller.
    mutating func gaussian() -> Double {
        let u = max(next(), 1e-12), v = next()
        return (-2 * log(u)).squareRoot() * cos(2 * .pi * v)
    }
}
