import XCTest
@testable import AppCore

final class SeasonTests: XCTestCase {
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(month: Int) -> Date {
        utc.date(from: DateComponents(year: 2026, month: month, day: 15))!
    }

    func testNorthernSeasons() {
        XCTAssertEqual(Season.of(date(month: 1), calendar: utc), .winter)
        XCTAssertEqual(Season.of(date(month: 4), calendar: utc), .spring)
        XCTAssertEqual(Season.of(date(month: 7), calendar: utc), .summer)
        XCTAssertEqual(Season.of(date(month: 10), calendar: utc), .autumn)
        XCTAssertEqual(Season.of(date(month: 12), calendar: utc), .winter)
    }

    func testSouthernHemisphereIsFlipped() {
        XCTAssertEqual(Season.of(date(month: 10), calendar: utc, southernHemisphere: true), .spring)
        XCTAssertEqual(Season.of(date(month: 1), calendar: utc, southernHemisphere: true), .summer)
    }

    func testPickIdeaAvoidsPrevious() {
        var generator = SeededGenerator(seed: 7)
        for _ in 0..<20 {
            XCTAssertEqual(PromptBuilder.pickIdea(from: ["a", "b"], avoiding: "a", using: &generator), "b")
        }
    }

    func testPickIdeaWithSingleOptionRepeats() {
        var generator = SeededGenerator(seed: 1)
        XCTAssertEqual(PromptBuilder.pickIdea(from: ["a"], avoiding: "a", using: &generator), "a")
        XCTAssertNil(PromptBuilder.pickIdea(from: [], avoiding: nil, using: &generator))
    }
}
