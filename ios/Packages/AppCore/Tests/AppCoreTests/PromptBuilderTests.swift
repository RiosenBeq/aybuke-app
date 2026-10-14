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

    func testEditInstructionAlwaysAppendsTheGuard() {
        let instruction = PromptBuilder.editInstruction("make the sky a sunset")
        XCTAssertEqual(instruction, "make the sky a sunset." + PromptBuilder.editGuard)
        // Mentioning a face used to drop the guard: exactly the reshaping case.
        XCTAssertTrue(PromptBuilder.editInstruction("make my face glow").hasSuffix(PromptBuilder.editGuard))
    }

    func testEditInstructionDoesNotDuplicateTheGuard() {
        let once = PromptBuilder.editInstruction("Give me pink hair")
        XCTAssertEqual(PromptBuilder.editInstruction(once), once)
    }

    func testGuardedInstructionFitsTheServerLimit() {
        let longest = PromptBuilder.editInstruction(String(repeating: "a", count: 2000))
        XCTAssertLessThanOrEqual(longest.count, 1000) // MAX_PROMPT_LENGTH in ai-image/index.ts
        XCTAssertLessThanOrEqual(PromptBuilder.maxPromptLength + 1 + PromptBuilder.editGuard.count, 1000)
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
