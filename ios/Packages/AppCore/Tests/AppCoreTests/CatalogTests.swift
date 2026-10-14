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
            XCTAssertTrue(ContentPolicy.evaluate(template.prompt, operation: .restyle).isAllowed, template.id)
        }
    }

    func testEveryCategoryShownHasTemplates() {
        for category in TemplateCatalog.categories {
            XCTAssertFalse(TemplateCatalog.templates(in: category).isEmpty, category.rawValue)
        }
        for (month, day) in [(1, 1), (2, 10), (3, 3), (7, 15), (10, 20), (12, 24)] {
            let date = Self.date(month, day)
            for category in TemplateCatalog.categories(on: date, calendar: Self.utc) {
                XCTAssertFalse(TemplateCatalog.templates(in: category, on: date, calendar: Self.utc).isEmpty, "\(category) \(month)/\(day)")
            }
        }
    }

    // MARK: Seasons

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static func date(_ month: Int, _ day: Int, year: Int = 2026) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func season(_ month: Int, _ day: Int, year: Int = 2026) -> SeasonalTheme? {
        SeasonalTheme.current(on: Self.date(month, day, year: year), calendar: Self.utc)
    }

    func testSeasonWindowsAreInclusiveAndWrapTheYear() {
        XCTAssertEqual(season(10, 1), .halloween)
        XCTAssertEqual(season(10, 20), .halloween)
        XCTAssertEqual(season(11, 2), .halloween)
        XCTAssertNil(season(11, 3))
        XCTAssertNil(season(11, 30))
        XCTAssertEqual(season(12, 1), .winter)
        XCTAssertEqual(season(12, 20), .winter)
        XCTAssertEqual(season(1, 6, year: 2027), .winter)
        XCTAssertNil(season(1, 7, year: 2027))
        XCTAssertEqual(season(2, 1), .galentines)
        XCTAssertEqual(season(2, 14), .galentines)
        XCTAssertNil(season(2, 15))
        XCTAssertNil(season(3, 3))
        XCTAssertNil(season(7, 4))
    }

    func testSeasonalRowFollowsTheSeason() {
        let halloween = Self.date(10, 20)
        XCTAssertTrue(TemplateCatalog.categories(on: halloween, calendar: Self.utc).contains(.seasonal))
        XCTAssertEqual(TemplateCategory.seasonal.title(on: halloween, calendar: Self.utc), "Spooky season")
        XCTAssertTrue(TemplateCatalog.templates(in: .seasonal, on: halloween, calendar: Self.utc).allSatisfy { $0.season == .halloween })

        let winter = Self.date(12, 20)
        XCTAssertEqual(TemplateCategory.seasonal.title(on: winter, calendar: Self.utc), "Cozy winter")
        XCTAssertTrue(TemplateCatalog.templates(in: .seasonal, on: winter, calendar: Self.utc).allSatisfy { $0.season == .winter })

        let galentines = Self.date(2, 14)
        XCTAssertGreaterThanOrEqual(TemplateCatalog.templates(in: .seasonal, on: galentines, calendar: Self.utc).count, 2)

        let spring = Self.date(3, 3)
        XCTAssertFalse(TemplateCatalog.categories(on: spring, calendar: Self.utc).contains(.seasonal))
        XCTAssertEqual(TemplateCategory.trending.title(on: spring, calendar: Self.utc), "Trending now")
    }

    func testEverySeasonHasLooksAndSeasonalLooksHaveASeason() {
        for theme in SeasonalTheme.allCases {
            XCTAssertGreaterThanOrEqual(TemplateCatalog.all.filter { $0.season == theme }.count, 2, theme.rawValue)
        }
        for template in TemplateCatalog.templates(in: .seasonal) {
            XCTAssertNotNil(template.season, template.id)
        }
    }

    func testEditorKeepsEveryLookReachable() {
        let spring = Self.date(3, 3)
        let order = TemplateCatalog.editorOrder(on: spring, calendar: Self.utc)
        XCTAssertEqual(Set(order.map(\.id)), Set(TemplateCatalog.all.map(\.id)))
        XCTAssertEqual(order.count, TemplateCatalog.all.count)
        // Out-of-season looks go last.
        XCTAssertTrue(order.suffix(TemplateCatalog.all.filter { $0.season != nil }.count).allSatisfy { $0.season != nil })

        let winter = Self.date(12, 20)
        XCTAssertEqual(TemplateCatalog.editorOrder(on: winter, calendar: Self.utc).first?.season, .winter)
    }

    func testDeepLinksOpenOutOfSeasonLooks() {
        XCTAssertNotNil(GlowDeepLink(url: URL(string: "glowlit://template/snow-globe")!))
    }

    func testTrendOfTheDayIsNeverSeasonal() {
        for offset in 0..<120 {
            let date = Self.date(1, 1).addingTimeInterval(Double(offset) * 86_400 * 3)
            XCTAssertNil(TemplateCatalog.trendOfTheDay(on: date, calendar: Self.utc).season)
        }
    }

    func testPetAndToyLooksSkipTheLikenessCheck() {
        for template in TemplateCatalog.templates(in: .pets) {
            XCTAssertFalse(template.keepsLikeness, template.id)
            XCTAssertTrue(template.prompt.contains(TemplateCatalog.petClause), template.id)
        }
        XCTAssertFalse(TemplateCatalog.template(id: "plushie")!.keepsLikeness)
        XCTAssertTrue(TemplateCatalog.template(id: "80s-studio")!.keepsLikeness)
        XCTAssertTrue(TemplateCatalog.template(id: "soft-glam")!.keepsLikeness)
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
        let colors = StyleCatalog.all.flatMap(\.swatch)
        for hex in colors {
            XCTAssertTrue(hex.hasPrefix("#") && hex.count == 7, hex)
            XCTAssertNotNil(UInt32(hex.dropFirst(), radix: 16), hex)
        }
    }
}
