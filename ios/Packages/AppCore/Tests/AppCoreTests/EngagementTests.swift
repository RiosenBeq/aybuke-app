import XCTest
@testable import AppCore

final class EngagementTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: Review prompts

    func testReviewWaitsForEnoughHappyMomentsAndDays() {
        let start = date(2026, 10, 1, 12)
        var policy = ReviewPromptPolicy(firstSeen: start)
        XCTAssertFalse(policy.recordHappyMoment(at: start, appVersion: "1.0"))
        XCTAssertFalse(policy.recordHappyMoment(at: start, appVersion: "1.0"))
        // Third happy moment, but still on day one.
        XCTAssertFalse(policy.recordHappyMoment(at: start.addingTimeInterval(3600), appVersion: "1.0"))
        XCTAssertTrue(policy.recordHappyMoment(at: date(2026, 10, 4, 12), appVersion: "1.0"))
        // Once per version.
        XCTAssertFalse(policy.recordHappyMoment(at: date(2026, 10, 5, 12), appVersion: "1.0"))
    }

    func testReviewRespectsSetbacksAndSpacing() {
        var policy = ReviewPromptPolicy(firstSeen: date(2026, 1, 1, 12))
        policy.happyMoments = 10
        policy.recordSetback(at: date(2026, 3, 1, 10))
        XCTAssertFalse(policy.shouldPrompt(now: date(2026, 3, 2, 10), appVersion: "1.0"))
        XCTAssertTrue(policy.shouldPrompt(now: date(2026, 3, 5, 10), appVersion: "1.0"))

        XCTAssertTrue(policy.recordHappyMoment(at: date(2026, 3, 5, 10), appVersion: "1.0"))
        // A new version, but only a month later: too soon.
        XCTAssertFalse(policy.shouldPrompt(now: date(2026, 4, 5, 10), appVersion: "1.1"))
        XCTAssertTrue(policy.shouldPrompt(now: date(2026, 7, 10, 10), appVersion: "1.1"))
    }

    func testReviewPolicyRoundTripsThroughJSON() throws {
        var policy = ReviewPromptPolicy(firstSeen: date(2026, 1, 1, 12))
        policy.happyMoments = 4
        policy.lastPromptedVersion = "1.0"
        let decoded = try JSONDecoder().decode(ReviewPromptPolicy.self, from: JSONEncoder().encode(policy))
        XCTAssertEqual(decoded, policy)
    }

    // MARK: Notifications

    func testQuietAndSchoolHours() {
        // Saturday night → Sunday 09:00.
        XCTAssertEqual(NotificationPlanner.outsideQuietHours(date(2026, 10, 17, 3), calendar: calendar), date(2026, 10, 17, 9))
        XCTAssertEqual(NotificationPlanner.outsideQuietHours(date(2026, 10, 17, 22, 30), calendar: calendar), date(2026, 10, 18, 9))
        // A Tuesday: night and school hours both wait until 15:00.
        XCTAssertEqual(NotificationPlanner.outsideQuietHours(date(2026, 10, 13, 3), calendar: calendar), date(2026, 10, 13, 15))
        XCTAssertEqual(NotificationPlanner.outsideQuietHours(date(2026, 10, 13, 11), calendar: calendar), date(2026, 10, 13, 15))
        XCTAssertEqual(NotificationPlanner.outsideQuietHours(date(2026, 10, 13, 17), calendar: calendar), date(2026, 10, 13, 17))
        XCTAssertTrue(NotificationPlanner.isSchoolTime(date(2026, 10, 16, 8), calendar: calendar))
        XCTAssertFalse(NotificationPlanner.isSchoolTime(date(2026, 10, 17, 10), calendar: calendar))
        XCTAssertTrue(NotificationPlanner.isQuiet(date(2026, 10, 13, 21), calendar: calendar))
        XCTAssertFalse(NotificationPlanner.isQuiet(date(2026, 10, 13, 9), calendar: calendar))
    }

    func testCreditsBackNeverArrivesAtMidnight() {
        let midnight = date(2026, 10, 18, 0) // Sunday
        let planned = NotificationPlanner.creditsBack(refill: midnight, dailyCredits: 3, calendar: calendar)
        XCTAssertEqual(planned.date, date(2026, 10, 18, 9))
        XCTAssertEqual(planned.kind, .creditsBack)
        XCTAssertTrue(planned.body.contains("3"))
    }

    func testWeeklyLooksLandOnFridayAfternoons() {
        let now = date(2026, 10, 13, 12) // a Tuesday
        let looks = NotificationPlanner.weeklyLooks(after: now, count: 4, calendar: calendar)
        XCTAssertEqual(looks.count, 4)
        XCTAssertEqual(looks.first?.date, date(2026, 10, 16, 17))
        XCTAssertEqual(Set(looks.map(\.id)).count, 4)
        for look in looks {
            XCTAssertEqual(calendar.component(.weekday, from: look.date), 6)
            XCTAssertFalse(NotificationPlanner.isQuiet(look.date, calendar: calendar))
            XCTAssertFalse(NotificationPlanner.isSchoolTime(look.date, calendar: calendar))
            guard case .template(let id) = look.link else { return XCTFail("expected a template link") }
            XCTAssertEqual(TemplateCatalog.trendOfTheDay(on: look.date, calendar: calendar).id, id)
        }
    }

    func testPreferencesStartOff() {
        let preferences = GlowNotificationPreferences()
        XCTAssertTrue(GlowNotificationKind.allCases.allSatisfy { !preferences.isOn($0) })
    }

    func testJobFinishedCopy() {
        XCTAssertTrue(NotificationPlanner.jobFinished(success: true, title: "Pink Hair").body.contains("Pink Hair"))
        XCTAssertTrue(NotificationPlanner.jobFinished(success: false, title: "Pink Hair").body.contains("No credit"))
    }
}
