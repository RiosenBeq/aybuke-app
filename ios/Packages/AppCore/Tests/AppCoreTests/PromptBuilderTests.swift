import XCTest
@testable import AppCore

final class PromptBuilderTests: XCTestCase {
    func testSanitizeCollapsesWhitespaceAndControls() {
        XCTAssertEqual(PromptBuilder.sanitize("  a\tcat \n\n on   the\u{0000}moon  "), "a cat on the moon")
    }

    func testSanitizeKeepsEmojiSequences() {
        let family = "👨‍👩‍👧 picnic"
        XCTAssertEqual(PromptBuilder.sanitize(family), family)
    }

    func testSanitizeTruncates() {
        let long = String(repeating: "word ", count: 400)
        XCTAssertLessThanOrEqual(PromptBuilder.sanitize(long).count, PromptBuilder.maxPromptLength)
    }

    func testTextToImageAppendsStyle() {
        let anime = StyleCatalog.style(id: "anime")
        let prompt = PromptBuilder.textToImagePrompt("a fox in the snow", style: anime)
        XCTAssertTrue(prompt.hasPrefix("a fox in the snow, "))
        XCTAssertTrue(prompt.contains("anime illustration"))
    }

    func testTextToImageWithAutoStyleIsUnchanged() {
        XCTAssertEqual(PromptBuilder.textToImagePrompt(" a fox ", style: StyleCatalog.auto), "a fox")
    }

    func testEditInstructionProtectsIdentity() {
        let instruction = PromptBuilder.editInstruction("make the sky a sunset")
        XCTAssertTrue(instruction.hasPrefix("make the sky a sunset."))
        XCTAssertTrue(instruction.contains("faces and identity"))
    }

    func testEditInstructionDoesNotDuplicateIdentityClause() {
        let instruction = PromptBuilder.editInstruction("Change the hair color, keep my face.")
        XCTAssertEqual(instruction, "Change the hair color, keep my face.")
    }

    func testEnhanceOnlyTouchesShortPrompts() {
        XCTAssertTrue(PromptBuilder.enhance("a cat").contains("highly detailed"))
        let long = "a very detailed and specific prompt that already has more than twelve words in it for sure"
        XCTAssertEqual(PromptBuilder.enhance(long), long)
        XCTAssertEqual(PromptBuilder.enhance("   "), "")
    }

    func testSurprisePromptIsDeterministicWithSeededGenerator() {
        var a = SeededGenerator(seed: 42)
        var b = SeededGenerator(seed: 42)
        XCTAssertEqual(PromptBuilder.surprisePrompt(using: &a), PromptBuilder.surprisePrompt(using: &b))
    }
}

final class ContentPolicyTests: XCTestCase {
    func testAllowsOrdinaryPrompts() {
        XCTAssertTrue(ContentPolicy.evaluate("a kid flying a kite at the beach").isAllowed)
        XCTAssertTrue(ContentPolicy.evaluate("turn me into a comic strip hero").isAllowed)
        XCTAssertTrue(ContentPolicy.evaluate("Sussex countryside at dawn").isAllowed)
    }

    func testBlocksSexualContent() {
        XCTAssertFalse(ContentPolicy.evaluate("make her naked").isAllowed)
        XCTAssertFalse(ContentPolicy.evaluate("Remove her clothes please").isAllowed)
        XCTAssertFalse(ContentPolicy.evaluate("NSFW art").isAllowed)
    }

    func testBlocksSexualContentWithMinorsWithStrictMessage() {
        guard case .blocked(let reason) = ContentPolicy.evaluate("sexy teen") else {
            return XCTFail("expected block")
        }
        XCTAssertTrue(reason.contains("violates"))
    }
}

/// Small deterministic RNG for tests (SplitMix64).
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
