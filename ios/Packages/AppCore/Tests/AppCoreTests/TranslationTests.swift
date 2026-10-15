import XCTest
@testable import AppCore

/// AppCore's English text is translated at runtime from the app's and the
/// widgets' string catalogs (`L10n.core`). These keep every look, style,
/// idea, Makeup Studio choice and Adjust vibe translated into all the app's
/// languages, and every idea she can tap (which fills a prompt in her
/// language) inside the content policy.
final class TranslationTests: XCTestCase {
    static let languages = ["tr", "es", "pt-BR", "fr", "de", "it", "ru", "ja", "ko", "zh-Hans", "id"]

    private struct Catalog: Decodable {
        struct Entry: Decodable {
            struct Localization: Decodable {
                struct Unit: Decodable {
                    let state: String
                    let value: String
                }

                let stringUnit: Unit?
            }

            let comment: String?
            let localizations: [String: Localization]?
        }

        let strings: [String: Entry]

        /// Translated values by language.
        func translations(of key: String) -> [String: String] {
            var values: [String: String] = [:]
            for (language, localization) in strings[key]?.localizations ?? [:] {
                if let unit = localization.stringUnit, unit.state == "translated", !unit.value.isEmpty {
                    values[language] = unit.value
                }
            }
            return values
        }
    }

    private func load(_ path: String) throws -> Catalog {
        let url = try RepositoryFile.url("ios/\(path)")
        return try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
    }

    func testLooksStylesAndIdeasAreTranslated() throws {
        let app = try load("App/Resources/Localizable.xcstrings")
        let widgets = try load("GlowlitWidgets/Localizable.xcstrings")
        // The widgets show look and collection names too.
        let names = TemplateCatalog.all.flatMap { [$0.title, $0.subtitle] }
            + TemplateCategory.allCases.map(\.title) + SeasonalTheme.allCases.map(\.rowTitle)
        let makeup = MakeupStudio.presets.map(\.name) + MakeupLips.allCases.map(\.name) + MakeupLipFinish.allCases.map(\.name)
            + MakeupEyes.allCases.map(\.name) + MakeupCheeks.allCases.map(\.name) + MakeupExtra.allCases.map(\.name)
            + MakeupHair.allCases.map(\.name) + MakeupIntensity.allCases.map(\.name)
        let appOnly = StyleCatalog.all.map(\.name) + PromptBuilder.surprisePrompts + LookSuggester.allMagicEditIdeas
            + makeup + AdjustVibes.all.map(\.name)
        for (catalog, keys, name) in [(app, names + appOnly, "app"), (widgets, names, "widgets")] {
            for key in Set(keys) {
                let missing = Self.languages.filter { catalog.translations(of: key)[$0] == nil }
                XCTAssertEqual(missing, [], "\(name): \"\(key)\" needs translating")
            }
        }
    }

    func testTranslatedIdeasPassThePolicy() throws {
        let app = try load("App/Resources/Localizable.xcstrings")
        // Ideas that go into the Magic Edit box, and ideas for Create.
        var edits = Set(LookSuggester.allMagicEditIdeas)
        var creates = Set(PromptBuilder.surprisePrompts)
        for (key, entry) in app.strings {
            let comment = entry.comment ?? ""
            if comment.contains("Example request for editing a photo") || comment.contains("Magic Edit request") {
                edits.insert(key)
            }
            if comment.contains("idea for creating an image") { creates.insert(key) }
        }
        XCTAssertGreaterThan(edits.count, LookSuggester.allMagicEditIdeas.count)
        XCTAssertGreaterThan(creates.count, PromptBuilder.surprisePrompts.count)

        // (English with the edit guard and with every style suffix is
        // covered by LookSuggesterTests and ContentPolicyTests.)
        for key in edits {
            for (language, text) in app.translations(of: key) {
                XCTAssertEqual(ContentPolicy.evaluate(text, operation: .magicEdit), .allowed, "[\(language)] \(text)")
            }
        }
        for key in creates {
            for (language, text) in app.translations(of: key) {
                XCTAssertEqual(ContentPolicy.evaluate(text, operation: .textToImage), .allowed, "[\(language)] \(text)")
            }
        }
    }
}
