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

    private func upcoming(_ month: Int, _ day: Int, year: Int = 2026, within days: Int = 14) -> UpcomingSeason? {
        SeasonalTheme.upcoming(on: Self.date(month, day, year: year), within: days, calendar: Self.utc)
    }

    func testUpcomingSeasonIsTeasedTwoWeeksAhead() {
        // Between seasons: the next one, in days to its first day.
        XCTAssertEqual(upcoming(11, 20), UpcomingSeason(theme: .winter, daysLeft: 11))
        XCTAssertEqual(upcoming(1, 20, year: 2027), UpcomingSeason(theme: .galentines, daysLeft: 12))
        XCTAssertEqual(upcoming(9, 17), UpcomingSeason(theme: .halloween, daysLeft: 14))
        XCTAssertEqual(upcoming(9, 30), UpcomingSeason(theme: .halloween, daysLeft: 1), "tomorrow")
        XCTAssertEqual(upcoming(11, 30), UpcomingSeason(theme: .winter, daysLeft: 1))
        XCTAssertEqual(upcoming(1, 31, year: 2027), UpcomingSeason(theme: .galentines, daysLeft: 1))
        // More than two weeks away: nothing yet.
        XCTAssertNil(upcoming(9, 16))
        XCTAssertNil(upcoming(11, 16))
        XCTAssertNil(upcoming(1, 7, year: 2027))
        XCTAssertNil(upcoming(3, 3))
        // During a season Home shows that season, never a teaser for the next.
        XCTAssertNil(upcoming(10, 15))
        XCTAssertNil(upcoming(11, 2), "Halloween's last day")
        XCTAssertNil(upcoming(12, 1), "the first day belongs to the season's own row")
        XCTAssertNil(upcoming(12, 25), "winter is on, and Galentine's is weeks away")
        XCTAssertNil(upcoming(12, 25, within: 60), "even looking further ahead")
        // Across the new year, a leap year, and a long look ahead.
        XCTAssertEqual(upcoming(1, 7, year: 2027, within: 30), UpcomingSeason(theme: .galentines, daysLeft: 25))
        XCTAssertEqual(upcoming(1, 18, year: 2028), UpcomingSeason(theme: .galentines, daysLeft: 14))
        XCTAssertEqual(upcoming(2, 15, within: 365), UpcomingSeason(theme: .halloween, daysLeft: 228))
        XCTAssertNil(upcoming(11, 20, within: 0))
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
        for category in TemplateCatalog.categories where category != .seasonal {
            XCTAssertTrue(TemplateCatalog.templates(in: category).contains { !$0.isPro }, "\(category) has a free look")
        }
    }

    func testCatalogSizesMatchTheCopy() {
        // README, AGENTS.md, web/index.html, docs and the App Store text in every
        // locale say "50+ one-tap looks", "20 styles" and "8 collections".
        XCTAssertGreaterThanOrEqual(TemplateCatalog.all.filter { $0.season == nil }.count, 50)
        XCTAssertEqual(StyleCatalog.all.filter { $0 != StyleCatalog.auto }.count, 20)
        XCTAssertEqual(TemplateCatalog.categories.filter { $0 != .seasonal }.count, 8)
        // AGENTS.md, docs, the screenshot captions and the App Store text in
        // every locale say Makeup Studio has "20 looks".
        XCTAssertEqual(MakeupStudio.presets.count, 20)
    }

    func testBestieLooksKeepEveryoneAsTheyAre() {
        let besties = TemplateCatalog.templates(in: .besties)
        XCTAssertGreaterThanOrEqual(besties.count, 3)
        for template in besties {
            XCTAssertTrue(template.prompt.contains(TemplateCatalog.groupIdentityClause), template.id)
            XCTAssertTrue(template.keepsLikeness, template.id)
            XCTAssertNil(template.season, template.id)
        }
    }

    func testLooksOfPeopleCarryTheIdentityClause() {
        // Art looks keep people recognizable in their own words, and these
        // three restore or restyle something other than a person.
        let ownWords: Set<String> = [
            "anime-film", "watercolor", "3d-cartoon", "oil-painting", "comic", "claymation", "manga",
            "restore", "product-studio", "golden-sky",
        ]
        for template in TemplateCatalog.all where !ownWords.contains(template.id) {
            let prompt = template.prompt
            XCTAssertTrue(prompt.contains(TemplateCatalog.identityClause) || prompt.contains(TemplateCatalog.groupIdentityClause), template.id)
        }
        for id in ownWords {
            XCTAssertNotNil(TemplateCatalog.template(id: id), "\(id) is still in the catalog")
        }
    }

    func testLooksNeverNameBrandsOrBeautyFixes() {
        let banned: Set<String> = [
            "sexy", "slim", "slimmer", "skinny", "thinner", "flawless", "poreless", "airbrushed",
            "barbie", "disney", "pixar", "ghibli", "pokemon", "pokémon", "lego", "sanrio",
        ]
        for template in TemplateCatalog.all {
            let words = Set(template.prompt.lowercased().split { !$0.isLetter }.map(String.init))
            XCTAssertTrue(words.isDisjoint(with: banned), "\(template.id): \(words.intersection(banned))")
        }
    }

    func testStyleLookupFallsBackToAuto() {
        XCTAssertEqual(StyleCatalog.style(id: nil), StyleCatalog.auto)
        XCTAssertEqual(StyleCatalog.style(id: "does-not-exist"), StyleCatalog.auto)
        XCTAssertEqual(StyleCatalog.style(id: "anime").name, "Anime")
    }

    func testStyleIDsAreUnique() {
        let ids = StyleCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        let names = StyleCatalog.all.map(\.name)
        XCTAssertEqual(names.count, Set(names).count)
    }

    func testStylesAreCompleteAndMostlyFree() {
        for style in StyleCatalog.all where style != StyleCatalog.auto {
            XCTAssertFalse(style.name.isEmpty, style.id)
            XCTAssertFalse(style.symbolName.isEmpty, style.id)
            XCTAssertGreaterThan(style.promptSuffix.count, 20, style.id)
            XCTAssertEqual(style.swatch.count, 2, style.id)
            XCTAssertTrue(ContentPolicy.evaluate(style.promptSuffix, operation: .textToImage).isAllowed, style.id)
        }
        // Like the looks: most styles are free to try.
        XCTAssertGreaterThan(StyleCatalog.all.filter { !$0.isPro }.count, StyleCatalog.all.count / 2)
    }

    func testHexColorsAreWellFormed() {
        let colors = StyleCatalog.all.flatMap(\.swatch)
        for hex in colors {
            XCTAssertTrue(hex.hasPrefix("#") && hex.count == 7, hex)
            XCTAssertNotNil(UInt32(hex.dropFirst(), radix: 16), hex)
        }
    }
}
