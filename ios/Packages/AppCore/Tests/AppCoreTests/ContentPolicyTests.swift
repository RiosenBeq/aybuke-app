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

        let vectors: [Vector]
    }

    private struct BackendTerms: Decodable {
        let editGuard: String
        let messages: [String: String]
        let terms: [String: [String]]
    }

    private static let sharedFolder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // → AppCoreTests/
        .deletingLastPathComponent() // → Tests/
        .deletingLastPathComponent() // → AppCore/
        .deletingLastPathComponent() // → Packages/
        .deletingLastPathComponent() // → ios/
        .deletingLastPathComponent() // → repository root
        .appendingPathComponent("backend/supabase/functions/_shared")

    private func load<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        let url = Self.sharedFolder.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("\(name) not found at \(url.path)")
        }
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
}
