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
        let looks = NotificationPlanner.weeklyLooks(after: now, isPro: false, count: 4, calendar: calendar)
        XCTAssertEqual(looks.count, 4)
        XCTAssertEqual(looks.first?.date, date(2026, 10, 16, 17))
        XCTAssertEqual(Set(looks.map(\.id)).count, 4)
        for look in looks {
            XCTAssertEqual(calendar.component(.weekday, from: look.date), 6)
            XCTAssertFalse(NotificationPlanner.isQuiet(look.date, calendar: calendar))
            XCTAssertFalse(NotificationPlanner.isSchoolTime(look.date, calendar: calendar))
            guard case .template(let id) = look.link else { return XCTFail("expected a template link") }
            XCTAssertEqual(TemplateCatalog.trendOfTheDay(on: look.date, isPro: false, calendar: calendar).id, id)
            XCTAssertFalse(TemplateCatalog.template(id: id)?.isPro ?? true, "a free user's push never leads to the paywall")
        }
    }

    func testPreferencesStartOff() {
        let preferences = GlowNotificationPreferences()
        XCTAssertTrue(GlowNotificationKind.allCases.allSatisfy { !preferences.isOn($0) })
    }

    func testJobFinishedCopyNeverQuotesThePrompt() {
        XCTAssertEqual(NotificationPlanner.jobFinished(success: true, isCreate: false).title, "Your edit is ready ✨")
        XCTAssertEqual(NotificationPlanner.jobFinished(success: true, isCreate: true).title, "Your images are ready ✨")
        XCTAssertTrue(NotificationPlanner.jobFinished(success: false, isCreate: false).body.contains("No credit"))
    }

    func testReadyPingWaitsOutNightsAndSchool() {
        XCTAssertFalse(NotificationPlanner.mayPostNow(date(2026, 10, 13, 23), calendar: calendar)) // Tuesday night
        XCTAssertFalse(NotificationPlanner.mayPostNow(date(2026, 10, 13, 10), calendar: calendar)) // Tuesday, school
        XCTAssertTrue(NotificationPlanner.mayPostNow(date(2026, 10, 13, 16), calendar: calendar))
        XCTAssertTrue(NotificationPlanner.mayPostNow(date(2026, 10, 17, 10), calendar: calendar)) // Saturday
    }

    func testTrialReminderBeforeTheCancelByTimeAndNeverAtNight() {
        // Bought Monday 22:30 with a 7-day trial: ends next Monday 22:30.
        let mondayEvening = date(2026, 10, 12, 22, 30)
        let end1 = mondayEvening.addingTimeInterval(7 * 86_400)
        XCTAssertEqual(NotificationPlanner.trialReminder(trialEnd: end1, now: mondayEvening, calendar: calendar),
                       date(2026, 10, 18, 20, 30)) // Sunday
        // Bought Tuesday 10:00: end-26h is Monday 08:00 (night), so Sunday 20:59.
        let tuesdayMorning = date(2026, 10, 13, 10)
        let end2 = tuesdayMorning.addingTimeInterval(7 * 86_400)
        XCTAssertEqual(NotificationPlanner.trialReminder(trialEnd: end2, now: tuesdayMorning, calendar: calendar),
                       date(2026, 10, 18, 20, 59))
        // End-26h in Wednesday school hours: Tuesday evening.
        let end3 = date(2026, 10, 22, 13) // Thursday 13:00 → Wednesday 11:00
        XCTAssertEqual(NotificationPlanner.trialReminder(trialEnd: end3, now: date(2026, 10, 15, 13), calendar: calendar),
                       date(2026, 10, 20, 20, 59))
        // Every purchase hour over two weeks: allowed slot, at least 26 h ahead.
        for hours in stride(from: 0, to: 14 * 24, by: 1) {
            let bought = date(2026, 10, 12, 0).addingTimeInterval(TimeInterval(hours) * 3600)
            let end = bought.addingTimeInterval(7 * 86_400)
            guard let reminder = NotificationPlanner.trialReminder(trialEnd: end, now: bought, calendar: calendar) else {
                return XCTFail("no reminder for \(bought)")
            }
            XCTAssertFalse(NotificationPlanner.isQuiet(reminder, calendar: calendar))
            XCTAssertFalse(NotificationPlanner.isSchoolTime(reminder, calendar: calendar))
            XCTAssertLessThanOrEqual(reminder, end.addingTimeInterval(-26 * 3600))
            XCTAssertGreaterThan(reminder, bought)
        }
        // A sped-up sandbox trial has no slot left.
        XCTAssertNil(NotificationPlanner.trialReminder(trialEnd: date(2026, 10, 13, 16, 5), now: date(2026, 10, 13, 16), calendar: calendar))
    }
}
