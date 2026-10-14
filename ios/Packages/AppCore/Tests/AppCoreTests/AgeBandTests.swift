import XCTest
@testable import AppCore

final class AgeBandTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testBirthMonthAssumesTheYoungestAge() {
        let now = date(2026, 10, 14)
        XCTAssertEqual(AgeBand(birthMonth: 6, birthYear: 2015, now: now, calendar: utc), .under13)
        XCTAssertEqual(AgeBand(birthMonth: 6, birthYear: 2011, now: now, calendar: utc), .teen13to15)
        XCTAssertEqual(AgeBand(birthMonth: 6, birthYear: 1999, now: now, calendar: utc), .adult)
        // Turns 13 sometime this month: still 12 until proven otherwise.
        XCTAssertEqual(AgeBand(birthMonth: 10, birthYear: 2013, now: now, calendar: utc), .under13)
        XCTAssertEqual(AgeBand(birthMonth: 9, birthYear: 2013, now: now, calendar: utc), .teen13to15)
        XCTAssertEqual(AgeBand(birthMonth: 11, birthYear: 2010, now: now, calendar: utc), .teen13to15)
        XCTAssertEqual(AgeBand(birthMonth: 9, birthYear: 2010, now: now, calendar: utc), .teen16to17)
        XCTAssertEqual(AgeBand(birthMonth: 1, birthYear: 2027, now: now, calendar: utc), .under13, "future dates are young, not an error")
    }

    func testAppleRangesMapToTheYoungerBand() {
        XCTAssertEqual(AgeBand(appleLowerBound: nil), .under13)
        XCTAssertEqual(AgeBand(appleLowerBound: 13), .teen13to15)
        XCTAssertEqual(AgeBand(appleLowerBound: 14), .teen13to15)
        XCTAssertEqual(AgeBand(appleLowerBound: 16), .teen16to17)
        XCTAssertEqual(AgeBand(appleLowerBound: 18), .adult)
        XCTAssertEqual(AgeBand(appleLowerBound: 21), .adult)
    }

    func testDefaultsByBand() {
        func defaults(_ band: AgeBand, _ country: String? = "USA") -> AgeDefaults {
            AgeDefaults(record: AgeRecord(band: band, source: .selfDeclared, setAt: .distantPast), storefrontCountry: country)
        }
        let child = defaults(.under13)
        XCTAssertFalse(child.allowsCloudAI)
        XCTAssertFalse(child.allowsPurchases)
        XCTAssertFalse(child.autoPaywall)

        let teen = defaults(.teen13to15)
        XCTAssertTrue(teen.allowsCloudAI)
        XCTAssertFalse(teen.autoPaywall, "no automatic paywall for minors")
        XCTAssertTrue(teen.requiresGuardianStep)

        XCTAssertFalse(defaults(.teen16to17).requiresGuardianStep)
        XCTAssertFalse(defaults(.teen16to17).autoPaywall)
        XCTAssertFalse(defaults(.teen16to17, "DEU").requiresGuardianStep, "16 is the consent age in Germany")
        XCTAssertTrue(defaults(.teen16to17, "TUR").requiresGuardianStep, "under 18 in Türkiye")

        let adult = defaults(.adult)
        XCTAssertTrue(adult.autoPaywall)
        XCTAssertFalse(adult.requiresGuardianStep)

        let unanswered = AgeDefaults(record: nil, storefrontCountry: nil)
        XCTAssertFalse(unanswered.autoPaywall, "unknown gets the protective teen defaults")
        XCTAssertTrue(unanswered.requiresGuardianStep)
    }

    func testBrazilNeedsMoreThanSelfDeclaration() {
        let selfDeclaredAdult = AgeRecord(band: .adult, source: .selfDeclared, setAt: .distantPast)
        XCTAssertFalse(AgeDefaults(record: selfDeclaredAdult, storefrontCountry: "BRA").autoPaywall)
        XCTAssertTrue(AgeDefaults(record: selfDeclaredAdult, storefrontCountry: "bra").requiresGuardianStep)
        let confirmedAdult = AgeRecord(band: .adult, source: .apple, setAt: .distantPast)
        XCTAssertTrue(AgeDefaults(record: confirmedAdult, storefrontCountry: "BRA").autoPaywall)
        let child = AgeRecord(band: .under13, source: .selfDeclared, setAt: .distantPast)
        XCTAssertFalse(AgeDefaults(record: child, storefrontCountry: "BRA").allowsCloudAI)
    }

    func testDecliningWhereRequiredKeepsOnDeviceOnly() {
        let declined = AgeRecord(band: .unknown, source: .declined, setAt: .distantPast)
        let defaults = AgeDefaults(record: declined, storefrontCountry: "USA")
        XCTAssertFalse(defaults.allowsCloudAI)
        XCTAssertFalse(defaults.allowsPurchases)
    }

    func testAnAgeCanOnlyBeRaisedOnceAYearUnlessAppleSaysSo() {
        let start = date(2026, 1, 1)
        let teen = AgeRecord(band: .teen13to15, source: .selfDeclared, setAt: start)
        XCTAssertTrue(teen.accepts(AgeRecord(band: .under13, source: .selfDeclared, setAt: start)), "younger always")
        XCTAssertFalse(teen.accepts(AgeRecord(band: .adult, source: .selfDeclared, setAt: date(2026, 6, 1))))
        XCTAssertTrue(teen.accepts(AgeRecord(band: .adult, source: .selfDeclared, setAt: date(2027, 1, 2))))
        XCTAssertTrue(teen.accepts(AgeRecord(band: .adult, source: .apple, setAt: start)), "Apple's answer always")
        XCTAssertFalse(teen.accepts(AgeRecord(band: .unknown, source: .declined, setAt: start)), "declining keeps the answer")

        let unknown = AgeRecord(band: .unknown, source: .declined, setAt: start)
        XCTAssertTrue(unknown.accepts(AgeRecord(band: .adult, source: .selfDeclared, setAt: start)))
    }

    func testRecordRoundTrips() throws {
        let record = AgeRecord(band: .teen16to17, source: .appleSelfDeclared, setAt: Date(timeIntervalSince1970: 1_800_000_000))
        let decoded = try JSONDecoder().decode(AgeRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(decoded, record)
    }
}
