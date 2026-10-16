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

    // MARK: Sessions

    func testSessionsCountLaunchesAndLongBreaks() {
        var sessions = EngagementSessions()
        XCTAssertTrue(sessions.isFirstSession)
        sessions.noteLaunch()
        XCTAssertTrue(sessions.isFirstSession)
        // A quick look at another app: the same session.
        sessions.noteBackground(at: date(2026, 10, 1, 12))
        sessions.noteForeground(at: date(2026, 10, 1, 12, 20))
        XCTAssertEqual(sessions.count, 1)
        // Half an hour away: a new one.
        sessions.noteBackground(at: date(2026, 10, 1, 13))
        sessions.noteForeground(at: date(2026, 10, 1, 13, 30))
        XCTAssertEqual(sessions.count, 2)
        XCTAssertFalse(sessions.isFirstSession)
        // A clock set back is no time away; a relaunch always counts.
        sessions.noteBackground(at: date(2026, 10, 2, 12))
        sessions.noteForeground(at: date(2026, 10, 1, 12))
        XCTAssertEqual(sessions.count, 2)
        sessions.noteLaunch()
        XCTAssertEqual(sessions.count, 3)
        XCTAssertNil(sessions.backgroundedAt)
    }

    // MARK: Review prompts

    func testReviewWaitsForThreeExportsAndASecondSession() {
        var policy = ReviewPromptPolicy(firstSeen: date(2026, 10, 1, 12))
        let now = date(2026, 10, 1, 15)
        policy.recordExport()
        policy.recordExport()
        XCTAssertFalse(policy.shouldPrompt(now: now, appVersion: "1.1", isFirstSession: false))
        policy.recordExport()
        // The third, but still in her first session.
        XCTAssertFalse(policy.shouldPrompt(now: now, appVersion: "1.1", isFirstSession: true))
        XCTAssertTrue(policy.shouldPrompt(now: now, appVersion: "1.1", isFirstSession: false))
        policy.notePrompted(at: now, appVersion: "1.1")
        // Once per version.
        XCTAssertFalse(policy.shouldPrompt(now: date(2027, 3, 1, 12), appVersion: "1.1", isFirstSession: false))
    }

    func testReviewRespectsSetbacksAndSixtyDays() {
        var policy = ReviewPromptPolicy(firstSeen: date(2026, 1, 1, 12))
        policy.happyMoments = 10
        policy.recordSetback(at: date(2026, 3, 1, 10))
        XCTAssertFalse(policy.shouldPrompt(now: date(2026, 3, 2, 10), appVersion: "1.0", isFirstSession: false))
        XCTAssertTrue(policy.shouldPrompt(now: date(2026, 3, 5, 10), appVersion: "1.0", isFirstSession: false))

        policy.notePrompted(at: date(2026, 3, 5, 10), appVersion: "1.0")
        // A new version, but only a month later: too soon.
        XCTAssertFalse(policy.shouldPrompt(now: date(2026, 4, 5, 10), appVersion: "1.1", isFirstSession: false))
        XCTAssertFalse(policy.shouldPrompt(now: date(2026, 5, 3, 10), appVersion: "1.1", isFirstSession: false))
        XCTAssertTrue(policy.shouldPrompt(now: date(2026, 5, 5, 10), appVersion: "1.1", isFirstSession: false))
        // A clock set back is too soon, never long ago.
        XCTAssertFalse(policy.shouldPrompt(now: date(2026, 2, 1, 10), appVersion: "1.1", isFirstSession: false))
    }

    func testReviewPolicyRoundTripsThroughJSON() throws {
        var policy = ReviewPromptPolicy(firstSeen: date(2026, 1, 1, 12))
        policy.happyMoments = 4
        policy.lastPromptedVersion = "1.0"
        let decoded = try JSONDecoder().decode(ReviewPromptPolicy.self, from: JSONEncoder().encode(policy))
        XCTAssertEqual(decoded, policy)
    }

    // MARK: Invite card

    func testInviteCardWaitsForFiveExportsAndASecondSession() {
        var pacing = InviteCardPacing()
        let now = date(2026, 10, 1, 15)
        for _ in 0..<4 { pacing.noteExport() }
        XCTAssertFalse(pacing.isDue(at: now, isFirstSession: false, lastSetback: nil))
        pacing.noteExport()
        XCTAssertFalse(pacing.isDue(at: now, isFirstSession: true, lastSetback: nil))
        XCTAssertTrue(pacing.isDue(at: now, isFirstSession: false, lastSetback: nil))
        // Not soon after something went wrong.
        XCTAssertFalse(pacing.isDue(at: now, isFirstSession: false, lastSetback: date(2026, 9, 30, 15)))
        XCTAssertTrue(pacing.isDue(at: now, isFirstSession: false, lastSetback: date(2026, 9, 27, 15)))
    }

    func testInviteCardSpacingCapAndDontShowAgain() {
        var pacing = InviteCardPacing(exports: 5)
        pacing.noteShown(at: date(2026, 10, 1, 15))
        // 14 days and three more exports, both.
        for _ in 0..<3 { pacing.noteExport() }
        XCTAssertFalse(pacing.isDue(at: date(2026, 10, 14, 15), isFirstSession: false, lastSetback: nil))
        XCTAssertTrue(pacing.isDue(at: date(2026, 10, 15, 15), isFirstSession: false, lastSetback: nil))
        var fewer = InviteCardPacing(exports: 5)
        fewer.noteShown(at: date(2026, 10, 1, 15))
        fewer.noteExport()
        XCTAssertFalse(fewer.isDue(at: date(2026, 11, 1, 15), isFirstSession: false, lastSetback: nil))
        // Three times at most.
        pacing.noteShown(at: date(2026, 10, 15, 15))
        for _ in 0..<3 { pacing.noteExport() }
        pacing.noteShown(at: date(2026, 11, 1, 15))
        for _ in 0..<3 { pacing.noteExport() }
        XCTAssertEqual(pacing.shows, 3)
        XCTAssertFalse(pacing.isDue(at: date(2027, 1, 1, 15), isFirstSession: false, lastSetback: nil))
        // "Don't show again" is for good; a clock set back is too soon.
        var retired = InviteCardPacing(exports: 9)
        XCTAssertTrue(retired.isDue(at: date(2026, 10, 1, 15), isFirstSession: false, lastSetback: nil))
        retired.retire()
        XCTAssertFalse(retired.isDue(at: date(2026, 10, 1, 15), isFirstSession: false, lastSetback: nil))
        var backwards = InviteCardPacing(exports: 9)
        backwards.noteShown(at: date(2026, 10, 1, 15))
        for _ in 0..<3 { backwards.noteExport() }
        XCTAssertFalse(backwards.isDue(at: date(2026, 9, 1, 15), isFirstSession: false, lastSetback: nil))
    }

    func testEngagementStateRoundTripsThroughJSON() throws {
        var pacing = InviteCardPacing(exports: 7)
        pacing.noteShown(at: date(2026, 10, 1, 15))
        XCTAssertEqual(try JSONDecoder().decode(InviteCardPacing.self, from: JSONEncoder().encode(pacing)), pacing)
        var sessions = EngagementSessions()
        sessions.noteLaunch()
        sessions.noteBackground(at: date(2026, 10, 1, 15))
        XCTAssertEqual(try JSONDecoder().decode(EngagementSessions.self, from: JSONEncoder().encode(sessions)), sessions)
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

    func testPreferencesSavedBeforePollRemindersStillRead() throws {
        let saved = Data(#"{"glowReady":true,"creditsBack":false,"weeklyLook":true}"#.utf8)
        let preferences = try JSONDecoder().decode(GlowNotificationPreferences.self, from: saved)
        XCTAssertEqual(preferences, GlowNotificationPreferences(glowReady: true, weeklyLook: true))
        XCTAssertFalse(preferences.isOn(.pollEnding), "a new kind starts off")
        let again = try JSONDecoder().decode(GlowNotificationPreferences.self, from: JSONEncoder().encode(GlowNotificationPreferences(pollEnding: true)))
        XCTAssertTrue(again.pollEnding)
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
