import XCTest
@testable import AppCore

/// The local seasons: who sees them, when they're on, how they share Explore
/// with Halloween, winter and Galentine's, and what their looks may ask for.
final class LocalSeasonTests: XCTestCase {
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func region(_ code: String, language: String? = nil) -> SeasonAudience {
        SeasonAudience(region: code, language: language)
    }

    private func active(_ audience: SeasonAudience, _ year: Int, _ month: Int, _ day: Int) -> [SeasonalTheme] {
        SeasonalTheme.active(on: Self.date(year, month, day), for: audience, calendar: Self.utc)
    }

    private func upcoming(_ audience: SeasonAudience, _ year: Int, _ month: Int, _ day: Int, within days: Int = 14) -> UpcomingSeason? {
        SeasonalTheme.upcoming(on: Self.date(year, month, day), within: days, for: audience, calendar: Self.utc)
    }

    // MARK: Who

    func testRegionsGetTheirOwnSeasons() {
        let expected: [String: [SeasonalTheme]] = [
            "TR": [.eidAlFitr, .eidAlAdha], "ID": [.eidAlFitr, .eidAlAdha],
            "KR": [.lunarNewYear, .chuseok],
            "TW": [.lunarNewYear], "HK": [.lunarNewYear], "SG": [.lunarNewYear], "MY": [.lunarNewYear], "CN": [.lunarNewYear],
            "JP": [.hanami, .tanabata],
            "BR": [.carnaval, .festaJunina],
            "MX": [.diaDeMuertos], "AR": [.diaDeMuertos], "CO": [.diaDeMuertos], "PE": [.diaDeMuertos],
            "US": [], "ES": [], "DE": [], "GB": [], "FR": [], "PT": [],
        ]
        for (code, seasons) in expected {
            XCTAssertEqual(SeasonalTheme.local(for: region(code)), seasons, code)
        }
        XCTAssertEqual(SeasonalTheme.local(for: .everyone), [])
        // Simplified Chinese anywhere, whatever the region.
        XCTAssertEqual(SeasonalTheme.local(for: region("US", language: "zh-Hans")), [.lunarNewYear])
        XCTAssertEqual(SeasonalTheme.local(for: SeasonAudience(region: nil, language: "zh-Hans-SG")), [.lunarNewYear])
        XCTAssertEqual(SeasonalTheme.local(for: region("US", language: "zh-Hant")), [])
        // The global seasons are for everyone.
        for theme in [SeasonalTheme.halloween, .winter, .galentines] {
            XCTAssertTrue(theme.isShown(to: .everyone))
            XCTAssertTrue(theme.isShown(to: region("KR")))
        }
    }

    func testRegionComesFromTheDeviceThenTheStorefrontThenTheLanguage() {
        XCTAssertEqual(SeasonAudience.resolve(localeRegion: "TR", storefront: "USA", language: "en").region, "TR")
        XCTAssertEqual(SeasonAudience.resolve(localeRegion: "tr", storefront: nil, language: nil).region, "TR")
        // A numeric region ("World") isn't a country: the storefront decides.
        XCTAssertEqual(SeasonAudience.resolve(localeRegion: "001", storefront: "KOR", language: "en").region, "KR")
        XCTAssertEqual(SeasonAudience.resolve(localeRegion: nil, storefront: "BRA", language: "en").region, "BR")
        XCTAssertEqual(SeasonAudience.resolve(localeRegion: nil, storefront: "mex", language: nil).region, "MX")
        // A storefront without a local season still beats the language.
        XCTAssertEqual(SeasonalTheme.local(for: .resolve(localeRegion: nil, storefront: "USA", language: "tr")), [])
        // Only the language left.
        XCTAssertEqual(SeasonAudience.resolve(localeRegion: nil, storefront: nil, language: "pt-BR").region, "BR")
        XCTAssertEqual(SeasonAudience.resolve(localeRegion: nil, storefront: nil, language: "tr").region, "TR")
        XCTAssertEqual(SeasonAudience.resolve(localeRegion: nil, storefront: nil, language: "ja").region, "JP")
        XCTAssertEqual(SeasonAudience.resolve(localeRegion: nil, storefront: nil, language: "ko").region, "KR")
        XCTAssertEqual(SeasonAudience.resolve(localeRegion: nil, storefront: nil, language: "id").region, "ID")
        XCTAssertEqual(SeasonAudience.resolve(localeRegion: nil, storefront: nil, language: "es-419").region, "419")
        XCTAssertEqual(SeasonAudience.resolve(localeRegion: nil, storefront: nil, language: "es-MX").region, "MX")
        XCTAssertEqual(SeasonAudience.resolve(localeRegion: nil, storefront: nil, language: "zh_Hans_SG").region, "SG")
        XCTAssertNil(SeasonAudience.resolve(localeRegion: nil, storefront: nil, language: "es").region)
        XCTAssertNil(SeasonAudience.resolve(localeRegion: nil, storefront: nil, language: "en").region)
        XCTAssertEqual(SeasonalTheme.local(for: .resolve(localeRegion: nil, storefront: nil, language: "es-419")), [.diaDeMuertos])
    }

    // MARK: When

    func testDatesFollowTheAuthorities() {
        let turkey = region("TR"), indonesia = region("ID")
        // Ramazan Bayramı / Lebaran: Türkiye's eve to Indonesia's last cuti bersama.
        XCTAssertEqual(active(turkey, 2026, 3, 18), [])
        XCTAssertEqual(active(turkey, 2026, 3, 19), [.eidAlFitr], "arefe")
        XCTAssertEqual(active(indonesia, 2026, 3, 21), [.eidAlFitr])
        XCTAssertEqual(active(indonesia, 2026, 3, 24), [.eidAlFitr], "cuti bersama")
        XCTAssertEqual(active(turkey, 2026, 3, 25), [])
        XCTAssertEqual(active(turkey, 2027, 3, 8), [.eidAlFitr])
        XCTAssertEqual(active(indonesia, 2027, 3, 15), [.eidAlFitr])
        XCTAssertEqual(active(turkey, 2027, 3, 16), [])
        XCTAssertEqual(active(turkey, 2028, 2, 25), [.eidAlFitr])
        XCTAssertEqual(active(turkey, 2028, 2, 29), [.eidAlFitr], "leap day")
        XCTAssertEqual(active(turkey, 2028, 3, 1), [])
        // Kurban Bayramı / Iduladha.
        XCTAssertEqual(active(turkey, 2026, 5, 25), [])
        XCTAssertEqual(active(turkey, 2026, 5, 26), [.eidAlAdha])
        XCTAssertEqual(active(indonesia, 2026, 5, 30), [.eidAlAdha])
        XCTAssertEqual(active(turkey, 2027, 5, 19), [.eidAlAdha])
        XCTAssertEqual(active(turkey, 2028, 5, 4), [.eidAlAdha])
        XCTAssertEqual(active(turkey, 2028, 5, 9), [])
        // Lunar New Year: Korea's Seollal falls a day after China's in 2027 and 2028.
        let korea = region("KR"), taiwan = region("TW")
        XCTAssertEqual(active(korea, 2026, 2, 17), [.lunarNewYear])
        XCTAssertEqual(active(taiwan, 2027, 2, 5), [.lunarNewYear, .galentines], "New Year's Eve")
        XCTAssertEqual(active(korea, 2027, 2, 9), [.lunarNewYear, .galentines], "Seollal's substitute holiday")
        XCTAssertEqual(active(korea, 2028, 1, 24), [])
        XCTAssertEqual(active(korea, 2028, 1, 27), [.lunarNewYear], "Seollal 2028")
        XCTAssertEqual(active(taiwan, 2028, 1, 31), [])
        // Chuseok.
        XCTAssertEqual(active(korea, 2026, 9, 25), [.chuseok])
        XCTAssertEqual(active(korea, 2027, 9, 13), [])
        XCTAssertEqual(active(korea, 2027, 9, 16), [.chuseok])
        XCTAssertEqual(active(korea, 2028, 10, 5), [.chuseok, .halloween], "substitute day, during Halloween")
        // Carnaval: Saturday to Ash Wednesday.
        let brazil = region("BR")
        XCTAssertEqual(active(brazil, 2026, 2, 13), [.galentines])
        XCTAssertEqual(active(brazil, 2026, 2, 14), [.carnaval, .galentines])
        XCTAssertEqual(active(brazil, 2026, 2, 18), [.carnaval])
        XCTAssertEqual(active(brazil, 2027, 2, 10), [.carnaval, .galentines])
        XCTAssertEqual(active(brazil, 2028, 2, 29), [.carnaval])
        XCTAssertEqual(active(brazil, 2028, 3, 1), [.carnaval], "Ash Wednesday")
        XCTAssertEqual(active(brazil, 2028, 3, 2), [])
        // The same days every year.
        let japan = region("JP")
        for year in [2026, 2031] {
            XCTAssertEqual(active(japan, year, 3, 19), [])
            XCTAssertEqual(active(japan, year, 3, 20), [.hanami])
            XCTAssertEqual(active(japan, year, 4, 15), [.hanami])
            XCTAssertEqual(active(japan, year, 4, 16), [])
            XCTAssertEqual(active(japan, year, 7, 7), [.tanabata])
            XCTAssertEqual(active(japan, year, 7, 8), [])
            XCTAssertEqual(active(brazil, year, 6, 24), [.festaJunina])
            XCTAssertEqual(active(brazil, year, 7, 1), [])
        }
        // Lunar and Easter dates are listed, never guessed: off past the table.
        XCTAssertEqual(active(korea, 2031, 1, 23), [], "Seollal 2031 isn't listed")
        XCTAssertEqual(active(turkey, 2031, 1, 25), [])
    }

    func testOverlapsPutTheLocalSeasonFirstAtHome() {
        // Día de Muertos leads in Mexico, follows Halloween elsewhere in Latin America.
        XCTAssertEqual(active(region("MX"), 2026, 10, 30), [.halloween])
        XCTAssertEqual(active(region("MX"), 2026, 10, 31), [.diaDeMuertos, .halloween])
        XCTAssertEqual(active(region("MX"), 2026, 11, 2), [.diaDeMuertos, .halloween])
        XCTAssertEqual(active(region("MX"), 2026, 11, 3), [])
        XCTAssertEqual(active(region("AR"), 2026, 11, 1), [.halloween, .diaDeMuertos])
        XCTAssertEqual(active(region("US"), 2026, 11, 1), [.halloween])
        XCTAssertEqual(SeasonalTheme.current(on: Self.date(2026, 11, 1), for: region("MX"), calendar: Self.utc), .diaDeMuertos)
        // A Chinese speaker in the US gets Lunar New Year ahead of Galentine's.
        XCTAssertEqual(active(region("US", language: "zh-Hans"), 2027, 2, 6), [.lunarNewYear, .galentines])
        XCTAssertEqual(active(region("US"), 2027, 2, 6), [.galentines])
        // Nobody in particular: exactly the global seasons, as before.
        XCTAssertEqual(active(.everyone, 2027, 2, 6), [.galentines])
        XCTAssertEqual(active(.everyone, 2026, 3, 20), [])
    }

    func testComingSoonTeasesTheSeasonThatWillLead() {
        let turkey = region("TR")
        XCTAssertEqual(upcoming(turkey, 2026, 3, 5), UpcomingSeason(theme: .eidAlFitr, daysLeft: 14))
        XCTAssertEqual(upcoming(turkey, 2026, 3, 18), UpcomingSeason(theme: .eidAlFitr, daysLeft: 1))
        XCTAssertNil(upcoming(turkey, 2026, 3, 4), "more than two weeks away")
        XCTAssertNil(upcoming(turkey, 2026, 3, 19), "its first day belongs to its banner")
        XCTAssertEqual(upcoming(turkey, 2027, 3, 1), UpcomingSeason(theme: .eidAlFitr, daysLeft: 7))
        XCTAssertEqual(upcoming(turkey, 2028, 4, 27), UpcomingSeason(theme: .eidAlAdha, daysLeft: 7))
        // Her local season is teased during a global one; a global one never
        // during hers, and Día de Muertos only where it will lead.
        XCTAssertEqual(upcoming(region("MX"), 2026, 10, 20), UpcomingSeason(theme: .diaDeMuertos, daysLeft: 11))
        XCTAssertNil(upcoming(region("AR"), 2026, 10, 20))
        XCTAssertEqual(upcoming(region("KR"), 2026, 2, 10), UpcomingSeason(theme: .lunarNewYear, daysLeft: 6))
        XCTAssertNil(upcoming(region("US"), 2026, 2, 10), "Galentine's is on and nothing outranks it")
        XCTAssertNil(upcoming(region("KR"), 2026, 9, 25, within: 30), "Chuseok is on; Halloween won't lead")
        // Across the new year: winter is on, and Seollal 2028 is local.
        XCTAssertEqual(upcoming(region("KR"), 2027, 12, 28, within: 30), UpcomingSeason(theme: .lunarNewYear, daysLeft: 28))
        XCTAssertEqual(upcoming(region("KR"), 2028, 1, 11), UpcomingSeason(theme: .lunarNewYear, daysLeft: 14))
        XCTAssertNil(upcoming(.everyone, 2027, 12, 28, within: 30), "winter is on for everyone else")
        // Japan: blossoms in two weeks; Brazil: June.
        XCTAssertEqual(upcoming(region("JP"), 2027, 3, 10), UpcomingSeason(theme: .hanami, daysLeft: 10))
        XCTAssertEqual(upcoming(region("BR"), 2026, 5, 25), UpcomingSeason(theme: .festaJunina, daysLeft: 7))
        // Two in the window: the local season first, then the sooner.
        XCTAssertEqual(upcoming(region("KR"), 2028, 9, 20), UpcomingSeason(theme: .chuseok, daysLeft: 12))
        XCTAssertEqual(upcoming(region("US"), 2028, 9, 20), UpcomingSeason(theme: .halloween, daysLeft: 11))
    }

    func testEveryListedSeasonHasThisYearAndNext() {
        // Lunar and Easter dates are typed in from the authorities a year or
        // more ahead: add the next year's before this fails (see the sources
        // in SeasonCalendar.swift).
        let year = Calendar(identifier: .gregorian).component(.year, from: Date())
        for theme in SeasonalTheme.allCases {
            guard let last = theme.dates.lastYear else { continue }
            XCTAssertGreaterThanOrEqual(last, year + 1, "\(theme): add the dates for \(year + 1)")
        }
    }

    // MARK: Explore and the editor

    func testExploreShowsHerSeason() {
        let bayram = Self.date(2027, 3, 9), turkey = region("TR")
        XCTAssertEqual(TemplateCategory.seasonal.title(on: bayram, for: turkey, calendar: Self.utc), "Eid al-Fitr")
        let row = TemplateCatalog.templates(in: .seasonal, on: bayram, for: turkey, calendar: Self.utc)
        XCTAssertEqual(row.map(\.id), ["eid-lanterns", "eid-sweets"])
        XCTAssertTrue(TemplateCatalog.categories(on: bayram, for: turkey, calendar: Self.utc).contains(.seasonal))
        // Elsewhere, no seasonal row that day.
        XCTAssertFalse(TemplateCatalog.categories(on: bayram, calendar: Self.utc).contains(.seasonal))
        XCTAssertEqual(TemplateCategory.seasonal.title(on: bayram, calendar: Self.utc), TemplateCategory.seasonal.title)

        // The editor leads with her season and keeps every look.
        let mexico = region("MX"), muertos = Self.date(2026, 11, 1)
        let order = TemplateCatalog.editorOrder(on: muertos, for: mexico, calendar: Self.utc)
        XCTAssertEqual(order.prefix(2).map(\.season), [.diaDeMuertos, .diaDeMuertos])
        XCTAssertEqual(order[2].season, .halloween)
        XCTAssertEqual(Set(order.map(\.id)), Set(TemplateCatalog.all.map(\.id)))
        XCTAssertEqual(order.count, TemplateCatalog.all.count)
    }

    func testIdeasLeadWithHerSeason() {
        let insight = PhotoInsight(faceCount: 1)
        let ideas = LookSuggester.suggest(
            for: insight, date: Self.date(2026, 3, 20), calendar: Self.utc, audience: region("TR"),
            freeEffects: ["digicam", "instant"]
        )
        XCTAssertTrue(ideas.contains(.template("eid-lanterns")), "\(ideas)")
        XCTAssertTrue(ideas.contains(.magicEdit(prompt: "Add glowing lanterns and soft gold lights")), "\(ideas)")
        // The same day elsewhere: no local look.
        let elsewhere = LookSuggester.suggest(
            for: insight, date: Self.date(2026, 3, 20), calendar: Self.utc, freeEffects: ["digicam", "instant"]
        )
        XCTAssertFalse(elsewhere.contains { if case .template(let id) = $0 { id.hasPrefix("eid") } else { false } })
    }

    // MARK: The looks

    func testLocalLooksAreRespectful() {
        // No attire for a faith or a costume of someone's culture; her outfit,
        // hair, head covering and face stay hers.
        let attire = ["hijab", "headscarf", "veil", "turban", "hanbok", "kimono", "yukata", "qipao", "cheongsam",
                      "sombrero", "poncho", "costume", "skull", "catrina", "calavera", "face paint on her", "tan"]
        for theme in SeasonalTheme.allCases where theme.isLocal {
            let looks = TemplateCatalog.all.filter { $0.season == theme }
            XCTAssertEqual(looks.count, 2, "\(theme)")
            XCTAssertTrue(looks.contains { !$0.isPro }, "\(theme) has a free look")
            for look in looks {
                let prompt = look.prompt
                XCTAssertEqual(look.category, .seasonal, look.id)
                XCTAssertTrue(look.keepsLikeness, look.id)
                XCTAssertTrue(prompt.hasSuffix(TemplateCatalog.modestyClause + " " + TemplateCatalog.identityClause), look.id)
                XCTAssertTrue(prompt.contains(TemplateCatalog.headClause), look.id)
                XCTAssertTrue(prompt.contains("Keep her own outfit"), look.id)
                XCTAssertTrue(prompt.contains("no skin smoothing"), look.id)
                let words = Set(prompt.lowercased().split { !$0.isLetter }.map(String.init))
                for term in attire {
                    let hit = term.contains(" ") ? prompt.lowercased().contains(term) : words.contains(term)
                    XCTAssertFalse(hit, "\(look.id) mentions \(term)")
                }
                // What the server checks: the recipe from catalog.json, as a restyle.
                XCTAssertEqual(ContentPolicy.evaluate(prompt, operation: .restyle), .allowed, look.id)
                XCTAssertLessThanOrEqual(prompt.count, PromptBuilder.maxPromptLength, look.id)
                XCTAssertEqual(PromptBuilder.sanitize(prompt), prompt, "\(look.id) survives the server's clean-up")
            }
        }
        for id in ["marigold-glow", "papel-picado"] {
            XCTAssertTrue(TemplateCatalog.template(id: id)!.prompt.contains("with no face paint"), id)
        }
        // Celebrations without drinks.
        for id in ["hanami-picnic", "carnaval-confetti", "junina-sweets"] {
            XCTAssertTrue(TemplateCatalog.template(id: id)!.prompt.contains("No alcohol."), id)
        }
    }

    func testLocalLooksStayOffTheYearRoundCount() {
        // The copy's "50+ looks" counts year-round looks only.
        let local = TemplateCatalog.all.filter { $0.season?.isLocal == true }
        XCTAssertEqual(local.count, 18)
        XCTAssertEqual(TemplateCatalog.all.filter { $0.season == nil }.count, 52)
        // Never the look of the day or a push.
        XCTAssertTrue(local.allSatisfy { $0.category == .seasonal })
    }
}
