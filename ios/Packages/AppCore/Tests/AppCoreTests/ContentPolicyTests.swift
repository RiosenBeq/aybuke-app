import XCTest
@testable import AppCore

/// The vectors in backend/supabase/functions/_shared/policy-vectors.json also
/// run in `_shared/policy_test.ts`, so the app and the server agree.
final class ContentPolicyTests: XCTestCase {
    private struct Vectors: Decodable {
        struct Vector: Decodable {
            let lang: String
            let text: String
            let operation: String?
            let expected: String?
        }

        struct Words: Decodable {
            let text: String
            let words: [String]
        }

        let vectors: [Vector]
        let words: [Words]
    }

    private struct BackendTerms: Decodable {
        let editGuard: String
        let messages: [String: String]
        let terms: [String: [String]]
    }

    private func load<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        let url = try RepositoryFile.url("backend/supabase/functions/_shared/\(name)")
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    func testSharedVectors() throws {
        let file = try load("policy-vectors.json", as: Vectors.self)
        XCTAssertGreaterThan(file.vectors.count, 150)
        for vector in file.vectors {
            let operation = try XCTUnwrap(AIOperation(rawValue: vector.operation ?? "magic_edit"), vector.text)
            let verdict = ContentPolicy.evaluate(vector.text, operation: operation)
            XCTAssertEqual(verdict.category?.rawValue, vector.expected, "[\(vector.lang)] \(vector.text)")
            // The server checks the instruction with the guard appended.
            if vector.expected == nil, operation == .magicEdit {
                let guarded = PromptBuilder.editInstruction(vector.text)
                XCTAssertTrue(ContentPolicy.evaluate(guarded, operation: .magicEdit).isAllowed, guarded)
            }
        }
    }

    func testSharedNormalisationVectors() throws {
        let file = try load("policy-vectors.json", as: Vectors.self)
        XCTAssertFalse(file.words.isEmpty)
        for vector in file.words {
            XCTAssertEqual(ContentPolicy.words(in: vector.text), vector.words, vector.text)
        }
    }

    func testBackendTermsMatchApp() throws {
        let backend = try load("policy-terms.json", as: BackendTerms.self)
        XCTAssertEqual(backend.terms, ContentPolicy.exportedTerms, "Run scripts/export-catalog.sh")
        XCTAssertEqual(backend.messages, ContentPolicy.exportedMessages, "Run scripts/export-catalog.sh")
        XCTAssertEqual(backend.editGuard, PromptBuilder.editGuard, "Run scripts/export-catalog.sh")
    }

    func testEveryTermCompiles() {
        XCTAssertEqual(ContentPolicy.invalidTerms, [])
    }

    func testBuiltInPromptsPass() {
        let fixed = [
            PromptBuilder.editGuard, TemplateCatalog.identityClause, DirectAIPrompts.enhance,
            "Give me pink hair. Only change the main person in front; keep everyone else exactly as they are.",
        ]
        for prompt in fixed {
            XCTAssertTrue(ContentPolicy.evaluate(prompt, operation: .magicEdit).isAllowed, prompt)
        }
        for template in TemplateCatalog.all {
            XCTAssertTrue(ContentPolicy.evaluate(template.prompt, operation: .restyle).isAllowed, template.id)
        }
        for style in StyleCatalog.all {
            for idea in PromptBuilder.surprisePrompts {
                let prompt = PromptBuilder.textToImagePrompt(idea, style: style)
                XCTAssertTrue(ContentPolicy.evaluate(prompt, operation: .textToImage).isAllowed, prompt)
            }
        }
    }

    func testMinorsGetTheStrictMessage() {
        guard case .blocked(let reason, .sexualMinor) = ContentPolicy.evaluate("sexy teen", operation: .textToImage) else {
            return XCTFail("expected a strict block")
        }
        XCTAssertTrue(reason.contains("violates"))
    }

    func testTextToImageSkipsReshapingRules() {
        XCTAssertTrue(ContentPolicy.evaluate("make me skinnier", operation: .textToImage).isAllowed)
        XCTAssertEqual(ContentPolicy.evaluate("make me skinnier", operation: .restyle).category, .appearanceChange)
    }

    func testNormalisation() {
        XCTAssertEqual(ContentPolicy.words(in: "BENİ ZAYIFLAT"), ["beni", "zayiflat"])
        XCTAssertEqual(ContentPolicy.words(in: "Ｂｉｋｉｎｉ"), ["bikini"])
        XCTAssertEqual(ContentPolicy.words(in: "b i k i n i at 5pm"), ["bikini", "at", "5pm"])
        XCTAssertEqual(ContentPolicy.words(in: "s3xy 1990s 3d"), ["sexy", "1990s", "3d"])
        XCTAssertEqual(ContentPolicy.words(in: "Crème brûlée"), ["creme", "brulee"])
        XCTAssertEqual(ContentPolicy.words(in: "чёрный йогурт"), ["черный", "йогурт"])
        XCTAssertEqual(ContentPolicy.words(in: "がんばって"), ["がんばって"])
        XCTAssertEqual(ContentPolicy.forms(of: "skinnnnier"), ["skinnnnier", "skinnier", "skinier"])
    }

    /// Mirrors "evasion folding matches ContentPolicy" in _shared/policy_test.ts.
    func testEvasionFolding() {
        // Invisible characters vanish; line breaks still separate words.
        XCTAssertEqual(ContentPolicy.words(in: "bi\u{200B}kini b\u{202E}ikini na\u{00AD}ked"), ["bikini", "bikini", "naked"])
        XCTAssertEqual(ContentPolicy.words(in: "n\u{0336}a\u{0336}k\u{0336}e\u{0336}d\u{0336}"), ["naked"])
        XCTAssertEqual(ContentPolicy.clean("remove\nher\u{0007} clothes"), "remove\nher clothes")
        // Lookalike letters read in the word's script; one script stays as it is.
        XCTAssertEqual(ContentPolicy.foldConfusables("n\u{0430}ked"), "naked")
        XCTAssertEqual(ContentPolicy.foldConfusables("\u{0433}\u{006F}\u{043B}\u{0430}\u{044F}"), "голая")
        XCTAssertEqual(ContentPolicy.foldConfusables("москва"), "москва")
        XCTAssertEqual(ContentPolicy.foldConfusables("café"), "café")
        // The squeezed view joins pieces inside a run of non-space characters.
        XCTAssertEqual(ContentPolicy.squeezedWords(in: "na.ked se-xy n@ked $exy 5exy b!k!n!"),
                       ["naked", "sexy", "naked", "sexy", "sexy", "bikini"])
        XCTAssertEqual(ContentPolicy.squeezedWords(in: "Sussex, Essex and class"), ["sussex", "essex", "and", "class"])
        // Never across 。: "女性" + "感谢" would hold "性感".
        XCTAssertEqual(ContentPolicy.squeezedWords(in: "女性。感谢你"), ["女性", "感谢你"])
        // Doubled letters are real words in supported languages.
        XCTAssertEqual(ContentPolicy.forms(of: "tangga"), ["tangga"])
        // A control character inside a word joins its halves; the split reading keeps newlines between words.
        XCTAssertEqual(ContentPolicy.words(in: "b\nikini bi\tkini na\u{000B}ked"), ["bikini", "bikini", "naked"])
        XCTAssertEqual(ContentPolicy.words(in: "remove\nher clothes", splitControls: true), ["remove", "her", "clothes"])
        XCTAssertEqual(ContentPolicy.squeezedWords(in: "n\na.ked"), ["naked"])
        XCTAssertEqual(ContentPolicy.squeezedWords(in: "remove\nher\nclothes", splitControls: true), ["remove", "her", "clothes"])
        XCTAssertEqual(ContentPolicy.squeezedWords(in: "remove\nher\nclothes"), ["removeherclothes"])
    }

    /// Mirrors "control characters: every bypass form is caught" in _shared/policy_test.ts.
    func testControlCharactersDontSplitAWord() {
        for text in ["b\nikini", "bi\tkini", "na\u{000B}ked", "make her na\u{000C}ked", "make her n\na.ked"] {
            XCTAssertFalse(ContentPolicy.evaluate(text, operation: .magicEdit).isAllowed, text)
        }
        XCTAssertFalse(ContentPolicy.evaluate("remove\nher\nclothes", operation: .magicEdit).isAllowed)
        XCTAssertTrue(ContentPolicy.evaluate("Give me pink hair\nand a cozy knit sweater", operation: .magicEdit).isAllowed)
    }

    /// Decision, mirrored in _shared/policy_test.ts: a line break next to CJK
    /// splits words like a space, even inside a CJK term.
    func testLineBreakNextToCJKSplitsLikeASpaceEvenInsideACJKTerm() {
        // Without spaces, dropping the break would join two words into a term ("女性" + "感谢你" holds "性感").
        for text in ["女性\n感谢你", "女性\r\n感谢你", "바나나\n체리 케이크 배경"] {
            XCTAssertTrue(ContentPolicy.evaluate(text, operation: .magicEdit).isAllowed, text)
        }
        // So a broken CJK term passes, exactly as it already does with a space; the provider and output checks follow.
        XCTAssertTrue(ContentPolicy.evaluate("生成裸\n照", operation: .magicEdit).isAllowed)
        XCTAssertTrue(ContentPolicy.evaluate("生成裸 照", operation: .magicEdit).isAllowed)
        XCTAssertFalse(ContentPolicy.evaluate("生成裸照", operation: .magicEdit).isAllowed)
        // A break inside a Latin word still joins it, also in a CJK sentence.
        XCTAssertFalse(ContentPolicy.evaluate("给她穿 b\nikini", operation: .magicEdit).isAllowed)
    }

    /// Mirrors "a final sigma folds to σ" in _shared/policy_test.ts: JavaScript
    /// lowercases a word-final Σ to ς, Swift to σ.
    func testFinalSigmaFoldsToSigma() {
        XCTAssertEqual(ContentPolicy.clean("ΚΟΣΜΟΣ"), "κοσμοσ")
        XCTAssertEqual(ContentPolicy.clean("κόσμος"), ContentPolicy.clean("ΚΌΣΜΟΣ"))
    }

    /// Mirrors "English sexual gaps are blocked" in _shared/policy_test.ts.
    func testEnglishSexualGapsAreBlocked() {
        for text in ["make him shirtless", "an unclothed model", "a bare chested man", "strip her down", "show her boobs", "give her tits"] {
            XCTAssertEqual(ContentPolicy.evaluate(text, operation: .magicEdit).category, .sexual, text)
        }
        for text in ["blue-footed boobies on a cliff", "great tits in the garden", "strip down the old wallpaper", "a bare tree at dusk", "the plan went tits up"] {
            XCTAssertTrue(ContentPolicy.evaluate(text, operation: .magicEdit).isAllowed, text)
        }
    }
}
