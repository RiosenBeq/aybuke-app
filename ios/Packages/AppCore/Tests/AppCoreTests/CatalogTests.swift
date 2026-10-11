import XCTest
@testable import AppCore

final class CatalogTests: XCTestCase {
    func testTemplateIDsAreUnique() {
        let ids = TemplateCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testTemplatesAreComplete() {
        for template in TemplateCatalog.all {
            XCTAssertFalse(template.title.isEmpty, template.id)
            XCTAssertGreaterThan(template.prompt.count, 40, template.id)
            XCTAssertLessThanOrEqual(template.prompt.count, PromptBuilder.maxPromptLength, template.id)
            XCTAssertEqual(template.gradient.count, 2, template.id)
            XCTAssertTrue(ContentPolicy.evaluate(template.prompt).isAllowed, template.id)
        }
    }

    func testEveryCategoryShownHasTemplates() {
        for category in TemplateCatalog.categories {
            XCTAssertFalse(TemplateCatalog.templates(in: category).isEmpty, category.rawValue)
        }
    }

    func testFreeTemplatesExistInEveryTier() {
        // Users must be able to try the product without paying.
        XCTAssertGreaterThanOrEqual(TemplateCatalog.all.filter { !$0.isPro }.count, 5)
    }

    func testStyleLookupFallsBackToAuto() {
        XCTAssertEqual(StyleCatalog.style(id: nil), StyleCatalog.auto)
        XCTAssertEqual(StyleCatalog.style(id: "does-not-exist"), StyleCatalog.auto)
        XCTAssertEqual(StyleCatalog.style(id: "anime").name, "Anime")
    }

    func testStyleIDsAreUnique() {
        let ids = StyleCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testHexColorsAreWellFormed() {
        let colors = TemplateCatalog.all.flatMap(\.gradient) + StyleCatalog.all.flatMap(\.swatch)
        for hex in colors {
            XCTAssertTrue(hex.hasPrefix("#") && hex.count == 7, hex)
            XCTAssertNotNil(UInt32(hex.dropFirst(), radix: 16), hex)
        }
    }
}
