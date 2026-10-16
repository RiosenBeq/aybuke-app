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

    /// What the app says on its own when Aybik can't (the look finder's
    /// lines, "Write it for me"'s ready-made lines, Ask Aybik's common
    /// questions) is translated, and in every language passes the rules the
    /// server's own lines pass: the photo rules next to her photo, each text
    /// box's length, and Create's rules and the answer screening for help.
    func testAybikFallbacksAreTranslatedAndSafe() throws {
        let app = try load("App/Resources/Localizable.xcstrings")
        let finder = LookFinder.effects.map(\.about) + LookFinder.glowLooks.map(\.about) + [LookFinder.styleAbout]
        let help = HelpTopic.all.flatMap { [$0.question, $0.answer] }
        for key in Set(finder + CardLines.all + help) {
            let missing = Self.languages.filter { app.translations(of: key)[$0] == nil }
            XCTAssertEqual(missing, [], "\"\(key)\" needs translating")
        }
        func everyLanguage(_ key: String) -> [(String, String)] {
            [("en", key)] + app.translations(of: key).sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        }
        for key in finder {
            for (language, text) in everyLanguage(key) {
                XCTAssertEqual(Assist.screenedShown([text], maxLength: LookFinder.maxReasonLength, limit: 1), [text], "[\(language)] \(text)")
            }
        }
        for slot in ShareTextSlot.allCases {
            for key in CardLines.lines(for: slot) {
                for (language, text) in everyLanguage(key) {
                    XCTAssertEqual(Assist.screenedCardLines([text], for: slot), [text], "[\(language)] \(slot): \(text)")
                }
            }
        }
        for topic in HelpTopic.all {
            for (language, text) in everyLanguage(topic.question) {
                XCTAssertEqual(ContentPolicy.evaluate(text, operation: .textToImage), .allowed, "[\(language)] \(text)")
            }
            for (language, text) in everyLanguage(topic.answer) {
                XCTAssertEqual(Assist.screenedAnswer(text), text, "[\(language)] \(topic.id)")
            }
        }
        // In every language a common question finds its own answer first,
        // though the words they're all asked with ("nasıl", "怎么") don't count.
        for language in ["en"] + Self.languages {
            let localize = { (key: String) in language == "en" ? key : app.translations(of: key)[language] ?? key }
            for topic in HelpTopic.all {
                let found = HelpTopic.matching(localize(topic.question), in: HelpTopic.all, localize: localize)
                XCTAssertEqual(found.first?.id, topic.id, "[\(language)] \(localize(topic.question))")
            }
        }
    }
}
