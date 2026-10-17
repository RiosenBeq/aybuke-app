import Foundation

// Gentle engagement: when to ask for a rating or show the invite card, and which
// reminders to schedule. All conservative on purpose — the app is for teens and
// young women, so no streak pressure, no night-time pings, no nagging.

// MARK: - Sessions

/// Her visits: every launch starts one, and so does coming back after at least
/// half an hour away. The first is for finding her way around, so neither the
/// rating request nor the invite card ever comes in it.
public struct EngagementSessions: Codable, Equatable, Sendable {
    public private(set) var count: Int
    /// When the app last went to the background; cleared when she's back.
    public private(set) var backgroundedAt: Date?

    public static let newSessionAfter: TimeInterval = 30 * 60

    public init(count: Int = 0) {
        self.count = count
    }

    public mutating func noteLaunch() {
        count += 1
        backgroundedAt = nil
    }

    public mutating func noteBackground(at date: Date) {
        backgroundedAt = date
    }

    /// Back in front: a new session after long enough away (a clock set back
    /// counts as no time away).
    public mutating func noteForeground(at date: Date) {
        if let backgroundedAt, date.timeIntervalSince(backgroundedAt) >= Self.newSessionAfter {
            count += 1
        }
        backgroundedAt = nil
    }

    public var isFirstSession: Bool { count <= 1 }
}

// MARK: - Review prompts

/// Asks for an App Store rating only after real happy moments (a finished save
/// or share): from the third one on, never in her first session, never soon
/// after something went wrong, at most once per app version and at most once
/// every 60 days. iOS itself also caps the system prompt at three times a year.
/// The app asks at a natural break (nothing else on screen, never during the
/// tour), and never at the same break as the invite card or an ad.
public struct ReviewPromptPolicy: Codable, Equatable, Sendable {
    /// Finished saves and shares (the stored name predates that rule).
    public var happyMoments: Int
    public var firstSeen: Date
    public var lastPromptedVersion: String?
    public var lastPromptDate: Date?
    public var lastSetback: Date?

    public static let minimumHappyMoments = 3
    public static let minimumDaysBetweenPrompts = 60.0
    public static let setbackCooldownHours = 72.0

    public init(firstSeen: Date) {
        happyMoments = 0
        self.firstSeen = firstSeen
    }

    /// A failed job, a report or a "doesn't look like you" retry.
    public mutating func recordSetback(at date: Date) {
        lastSetback = date
    }

    /// A finished save or share.
    public mutating func recordExport() {
        happyMoments += 1
    }

    /// A clock set back counts as "too soon", never as "long ago".
    public func shouldPrompt(now: Date, appVersion: String, isFirstSession: Bool) -> Bool {
        guard happyMoments >= Self.minimumHappyMoments, !isFirstSession else { return false }
        guard lastPromptedVersion != appVersion else { return false }
        if let last = lastPromptDate, now.timeIntervalSince(last) < Self.minimumDaysBetweenPrompts * 86_400 {
            return false
        }
        if let setback = lastSetback, now.timeIntervalSince(setback) < Self.setbackCooldownHours * 3600 {
            return false
        }
        return true
    }

    public mutating func notePrompted(at date: Date, appVersion: String) {
        lastPromptedVersion = appVersion
        lastPromptDate = date
    }
}

// MARK: - Invite card

/// "Loving Aybuke? Invite a friend": a small card after a finished save or
/// share, rarer than the rating request. Never before the fifth one or in her
/// first session; after that only once three more have followed and 14 days
/// have passed, never soon after something went wrong, three times at most,
/// and never again once she taps "Don't show again" or opens the invite from it.
public struct InviteCardPacing: Codable, Equatable, Sendable {
    public struct Rules: Equatable, Sendable {
        public var minimumExports: Int
        public var exportsBetween: Int
        public var spacing: TimeInterval
        public var maximumShows: Int
        public var setbackCooldown: TimeInterval

        public init(minimumExports: Int, exportsBetween: Int, spacing: TimeInterval, maximumShows: Int, setbackCooldown: TimeInterval) {
            self.minimumExports = minimumExports
            self.exportsBetween = exportsBetween
            self.spacing = spacing
            self.maximumShows = maximumShows
            self.setbackCooldown = setbackCooldown
        }

        public static let standard = Rules(minimumExports: 5, exportsBetween: 3, spacing: 14 * 86_400, maximumShows: 3,
                                           setbackCooldown: 72 * 3600)
    }

    public var exports: Int
    public var exportsAtLastShow: Int
    public var lastShown: Date?
    public var shows: Int
    /// "Don't show again", or she opened the invite from the card.
    public var isRetired: Bool

    public init(exports: Int = 0, exportsAtLastShow: Int = 0, lastShown: Date? = nil, shows: Int = 0, isRetired: Bool = false) {
        self.exports = exports
        self.exportsAtLastShow = exportsAtLastShow
        self.lastShown = lastShown
        self.shows = shows
        self.isRetired = isRetired
    }

    public mutating func noteExport() {
        exports += 1
    }

    public mutating func noteShown(at date: Date) {
        lastShown = date
        shows += 1
        exportsAtLastShow = exports
    }

    public mutating func retire() {
        isRetired = true
    }

    /// Whether the card may follow the save or share just counted. A clock set
    /// back counts as "too soon".
    public func isDue(at now: Date, isFirstSession: Bool, lastSetback: Date?, rules: Rules = .standard) -> Bool {
        guard !isRetired, !isFirstSession, shows < rules.maximumShows, exports >= rules.minimumExports else { return false }
        if let lastShown {
            guard now.timeIntervalSince(lastShown) >= rules.spacing, exports - exportsAtLastShow >= rules.exportsBetween else {
                return false
            }
        }
        if let lastSetback, now.timeIntervalSince(lastSetback) < rules.setbackCooldown { return false }
        return true
    }
}

// MARK: - Milestones

/// Firsts the app marks with a little sparkle: her first creation saved and
/// her first poll. Each plays once and then never again: no counts, badges,
/// streaks or reminders come from it. Kept on the device; Delete my data
/// forgets it like the rest.
public struct Milestones: Codable, Equatable, Sendable {
    public enum Kind: String, CaseIterable, Codable, Sendable {
        case firstSave
        case firstPoll
    }

    public private(set) var reached: Set<Kind>

    public init(reached: Set<Kind> = []) {
        self.reached = reached
    }

    /// Someone updating from a version without milestones: what she already
    /// did counts as reached, so no "first" is celebrated late.
    public init(updatingWithExports exports: Int, hasPolls: Bool) {
        var reached: Set<Kind> = []
        if exports > 0 { reached.insert(.firstSave) }
        if hasPolls { reached.insert(.firstPoll) }
        self.reached = reached
    }

    public func has(_ kind: Kind) -> Bool { reached.contains(kind) }

    /// Marks `kind` reached; true only the first time, when it's worth a sparkle.
    @discardableResult
    public mutating func reach(_ kind: Kind) -> Bool {
        reached.insert(kind).inserted
    }

    private enum CodingKeys: String, CodingKey { case reached }

    // Stored as plain names, sorted, so a name this version doesn't know
    // (from a later one) is skipped rather than losing every milestone.
    public init(from decoder: Decoder) throws {
        let names = try decoder.container(keyedBy: CodingKeys.self).decode([String].self, forKey: .reached)
        reached = Set(names.compactMap(Kind.init(rawValue:)))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(reached.map(\.rawValue).sorted(), forKey: .reached)
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
    /// An hour before her "Which vibe?" poll ends (never with her question).
    case pollEnding
}

/// What the user agreed to hear about. Everything stays off until she says yes.
public struct GlowNotificationPreferences: Codable, Equatable, Sendable {
    public var glowReady: Bool
    public var creditsBack: Bool
    public var weeklyLook: Bool
    public var pollEnding: Bool

    public init(glowReady: Bool = false, creditsBack: Bool = false, weeklyLook: Bool = false, pollEnding: Bool = false) {
        self.glowReady = glowReady
        self.creditsBack = creditsBack
        self.weeklyLook = weeklyLook
        self.pollEnding = pollEnding
    }

    private enum CodingKeys: String, CodingKey {
        case glowReady, creditsBack, weeklyLook, pollEnding
    }

    /// Preferences saved before a kind existed still read: the new kind is off.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        glowReady = try container.decodeIfPresent(Bool.self, forKey: .glowReady) ?? false
        creditsBack = try container.decodeIfPresent(Bool.self, forKey: .creditsBack) ?? false
        weeklyLook = try container.decodeIfPresent(Bool.self, forKey: .weeklyLook) ?? false
        pollEnding = try container.decodeIfPresent(Bool.self, forKey: .pollEnding) ?? false
    }

    public func isOn(_ kind: GlowNotificationKind) -> Bool {
        switch kind {
        case .glowReady: return glowReady
        case .creditsBack: return creditsBack
        case .weeklyLook: return weeklyLook
        case .pollEnding: return pollEnding
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
