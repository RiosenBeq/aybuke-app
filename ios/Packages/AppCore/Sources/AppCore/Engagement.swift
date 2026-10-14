import Foundation

// Gentle engagement: when to ask for a rating and which reminders to schedule.
// Both are opt-in and conservative on purpose — the app is for teens and
// young women, so no streak pressure, no night-time pings, no nagging.

// MARK: - Review prompts

/// Asks for an App Store rating only after real happy moments (saving,
/// sharing, hearting), never soon after something went wrong, never in the
/// first days, and at most once per app version. iOS itself also caps the
/// system prompt at three times a year.
public struct ReviewPromptPolicy: Codable, Equatable, Sendable {
    public var happyMoments: Int
    public var firstSeen: Date
    public var lastPromptedVersion: String?
    public var lastPromptDate: Date?
    public var lastSetback: Date?

    public static let minimumHappyMoments = 3
    public static let minimumDaysSinceFirstSeen = 2.0
    public static let minimumDaysBetweenPrompts = 120.0
    public static let setbackCooldownHours = 72.0

    public init(firstSeen: Date) {
        happyMoments = 0
        self.firstSeen = firstSeen
    }

    /// A failed job, a report or a "doesn't look like you" retry.
    public mutating func recordSetback(at date: Date) {
        lastSetback = date
    }

    /// Counts a happy moment and returns true when this is the moment to ask.
    public mutating func recordHappyMoment(at now: Date, appVersion: String) -> Bool {
        happyMoments += 1
        guard shouldPrompt(now: now, appVersion: appVersion) else { return false }
        lastPromptedVersion = appVersion
        lastPromptDate = now
        return true
    }

    public func shouldPrompt(now: Date, appVersion: String) -> Bool {
        guard happyMoments >= Self.minimumHappyMoments else { return false }
        guard now.timeIntervalSince(firstSeen) >= Self.minimumDaysSinceFirstSeen * 86_400 else { return false }
        guard lastPromptedVersion != appVersion else { return false }
        if let last = lastPromptDate, now.timeIntervalSince(last) < Self.minimumDaysBetweenPrompts * 86_400 {
            return false
        }
        if let setback = lastSetback, now.timeIntervalSince(setback) < Self.setbackCooldownHours * 3600 {
            return false
        }
        return true
    }
}

// MARK: - Notifications

public enum GlowNotificationKind: String, CaseIterable, Codable, Sendable {
    /// A cloud job finished while the app was in the background.
    case glowReady
    /// Free daily credits are back (only scheduled after running out).
    case creditsBack
    /// One look a week, on Friday afternoon.
    case weeklyLook
}

/// What the user agreed to hear about. Everything stays off until she says yes.
public struct GlowNotificationPreferences: Codable, Equatable, Sendable {
    public var glowReady: Bool
    public var creditsBack: Bool
    public var weeklyLook: Bool

    public init(glowReady: Bool = false, creditsBack: Bool = false, weeklyLook: Bool = false) {
        self.glowReady = glowReady
        self.creditsBack = creditsBack
        self.weeklyLook = weeklyLook
    }

    public func isOn(_ kind: GlowNotificationKind) -> Bool {
        switch kind {
        case .glowReady: return glowReady
        case .creditsBack: return creditsBack
        case .weeklyLook: return weeklyLook
        }
    }
}

public struct PlannedNotification: Equatable, Sendable {
    public let id: String
    public let kind: GlowNotificationKind
    public let date: Date
    public let title: String
    public let body: String
    public let link: GlowDeepLink

    public init(id: String, kind: GlowNotificationKind, date: Date, title: String, body: String, link: GlowDeepLink) {
        self.id = id
        self.kind = kind
        self.date = date
        self.title = title
        self.body = body
        self.link = link
    }
}

public enum NotificationPlanner {
    /// Quiet hours, local time: nothing is scheduled from 21:00 to 09:00.
    public static let quietStartHour = 21
    public static let quietEndHour = 9
    /// School hours, Monday to Friday: reminders wait until 15:00.
    public static let schoolStartHour = 8
    public static let schoolEndHour = 15
    /// The weekly look arrives on Friday (weekday 6) at 17:00.
    public static let weeklyLookWeekday = 6
    public static let weeklyLookHour = 17

    public static func isQuiet(_ date: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= quietStartHour || hour < quietEndHour
    }

    public static func isSchoolTime(_ date: Date, calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: date) // 1 = Sunday
        let hour = calendar.component(.hour, from: date)
        return (2...6).contains(weekday) && hour >= schoolStartHour && hour < schoolEndHour
    }

    /// Moves a date out of quiet hours (to the next 09:00) and, on school
    /// days, out of school hours (to 15:00).
    public static func outsideQuietHours(_ date: Date, calendar: Calendar = .current) -> Date {
        var result = date
        if isQuiet(result, calendar: calendar) {
            let hour = calendar.component(.hour, from: result)
            let day = hour >= quietStartHour ? calendar.date(byAdding: .day, value: 1, to: result) ?? result : result
            result = calendar.date(bySettingHour: quietEndHour, minute: 0, second: 0, of: day) ?? result
        }
        if isSchoolTime(result, calendar: calendar) {
            result = calendar.date(bySettingHour: schoolEndHour, minute: 0, second: 0, of: result) ?? result
        }
        return result
    }

    /// How long before the trial ends the reminder may fire at the latest:
    /// she must cancel at least 24 hours before, and gets 2 more to do it.
    public static let trialReminderLead: TimeInterval = 26 * 3600

    /// The trial reminder: the latest moment outside quiet and school hours
    /// that is at least 26 hours before `trialEnd` (so before the 24-hour
    /// cancel-by time) and still after `now`. Nil when no such moment is
    /// left (a sandbox trial, which StoreKit speeds up).
    public static func trialReminder(trialEnd: Date, now: Date, calendar: Calendar = .current) -> Date? {
        // On a whole minute, rounded down (never later than the lead allows).
        let latest = trialEnd.addingTimeInterval(-trialReminderLead).timeIntervalSinceReferenceDate
        var candidate = Date(timeIntervalSinceReferenceDate: (latest / 60).rounded(.down) * 60)
        // Each step lands on the evening before (or the same evening), so a
        // few steps always reach an allowed slot.
        for _ in 0..<4 {
            if !isQuiet(candidate, calendar: calendar) && !isSchoolTime(candidate, calendar: calendar) {
                return candidate > now ? candidate : nil
            }
            let hour = calendar.component(.hour, from: candidate)
            let day = hour >= quietStartHour ? candidate : calendar.date(byAdding: .day, value: -1, to: candidate) ?? candidate
            candidate = calendar.date(bySettingHour: quietStartHour - 1, minute: 59, second: 0, of: day) ?? candidate
        }
        return nil
    }

    /// "Your free credits are back" at the refill time, moved out of quiet hours.
    public static func creditsBack(refill: Date, dailyCredits: Int, calendar: Calendar = .current) -> PlannedNotification {
        PlannedNotification(
            id: "glowlit.credits-back",
            kind: .creditsBack,
            date: outsideQuietHours(refill, calendar: calendar),
            title: "Your free credits are back ✨",
            body: "\(dailyCredits) fresh credits for today.",
            link: .create
        )
    }

    /// The next few Friday looks, each naming that day's trend, so the
    /// notification matches the "Today's trend" widget (free looks unless Pro).
    public static func weeklyLooks(after now: Date, isPro: Bool, count: Int = 4,
                                   calendar: Calendar = .current) -> [PlannedNotification] {
        var components = DateComponents()
        components.weekday = weeklyLookWeekday
        components.hour = weeklyLookHour
        components.minute = 0
        var results: [PlannedNotification] = []
        var cursor = now
        while results.count < count,
              let next = calendar.nextDate(after: cursor, matching: components, matchingPolicy: .nextTime) {
            let look = TemplateCatalog.trendOfTheDay(on: next, isPro: isPro, calendar: calendar)
            let stamp = calendar.dateComponents([.year, .month, .day], from: next)
            results.append(PlannedNotification(
                id: "glowlit.weekly-look.\(stamp.year ?? 0)-\(stamp.month ?? 0)-\(stamp.day ?? 0)",
                kind: .weeklyLook,
                date: next,
                title: "This week's look: \(look.title) ✨",
                body: "\(look.subtitle).",
                link: .template(look.id)
            ))
            cursor = next
        }
        return results
    }

    /// Shown right away when a job finishes while the app is in the
    /// background, never at night or in school hours (then the Live Activity
    /// and My Works show it). Never her prompt: it would sit on the Lock Screen.
    public static func jobFinished(success: Bool, isCreate: Bool) -> (title: String, body: String) {
        if success {
            return (isCreate ? "Your images are ready ✨" : "Your edit is ready ✨", "Tap to see it.")
        }
        return ("That one didn't work", "No credit was used. Tap to try again.")
    }

    /// Whether a "ready" ping may be posted now.
    public static func mayPostNow(_ date: Date, calendar: Calendar = .current) -> Bool {
        !isQuiet(date, calendar: calendar) && !isSchoolTime(date, calendar: calendar)
    }
}
