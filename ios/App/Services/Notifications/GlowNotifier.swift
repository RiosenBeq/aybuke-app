import UIKit
import Observation
import UserNotifications
import AppCore

/// Local notifications only: no push server and no device token. Every kind
/// is opt-in, nothing is scheduled between 21:00 and 09:00, and tapping a
/// notification opens the matching screen.
@MainActor
@Observable
final class GlowNotifier {
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var preferences: GlowNotificationPreferences
    /// Opens a deep link when a notification is tapped.
    var onOpenLink: ((GlowDeepLink) -> Void)?

    private let defaults: UserDefaults
    private let delegate = NotificationDelegate()
    private static let storageKey = "notifications.preferences.v1"
    private static let readyPingDeclinedKey = "notifications.readyPingDeclined"
    private static let scheduledPrefixes = ["glowlit.credits-back", "glowlit.weekly-look"]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(GlowNotificationPreferences.self, from: data) {
            preferences = saved
        } else {
            preferences = GlowNotificationPreferences()
        }
        // Must be set before launch finishes, so cold-start taps arrive.
        UNUserNotificationCenter.current().delegate = delegate
        delegate.onOpen = { [weak self] link in self?.onOpenLink?(link) }
    }

    var isAllowedBySystem: Bool {
        switch authorization {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    /// True until she has answered the system prompt once.
    var canAskPermission: Bool { authorization == .notDetermined }

    /// The waiting screen's "Ping me when it's ready": offered until she
    /// turns it on, or switches it off on purpose in Settings.
    var offersReadyPing: Bool {
        !preferences.glowReady && authorization != .denied && !defaults.bool(forKey: Self.readyPingDeclinedKey)
    }

    func refreshAuthorization() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Turns one kind on or off, asking iOS for permission the first time.
    /// Returns false when the system permission is missing.
    @discardableResult
    func set(_ kind: GlowNotificationKind, on: Bool) async -> Bool {
        if on, !(await ensurePermission()) { return false }
        switch kind {
        case .glowReady:
            preferences.glowReady = on
            defaults.set(!on, forKey: Self.readyPingDeclinedKey)
        case .creditsBack: preferences.creditsBack = on
        case .weeklyLook: preferences.weeklyLook = on
        }
        persist()
        return true
    }

    /// "Delete my data": every reminder off, and nothing left in Notification
    /// Center (a delivered "glow ready" shows her prompt). `kept` survives.
    func reset(keeping kept: Set<String>) async {
        preferences = GlowNotificationPreferences()
        defaults.removeObject(forKey: Self.storageKey)
        defaults.removeObject(forKey: Self.readyPingDeclinedKey)
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { !kept.contains($0) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        center.removeAllDeliveredNotifications()
    }

    private func ensurePermission() async -> Bool {
        await refreshAuthorization()
        if canAskPermission {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            await refreshAuthorization()
        }
        return isAllowedBySystem
    }

    /// Replaces the scheduled reminders with the current plan.
    /// `cloudAIAllowed` false (under 13): no credits or AI-look reminders,
    /// they'd only point at tools she doesn't have.
    func reschedule(credits: Int, isPro: Bool, nextRefill: Date, dailyCredits: Int, cloudAIAllowed: Bool) async {
        let center = UNUserNotificationCenter.current()
        let ours = await center.pendingNotificationRequests().map(\.identifier).filter { id in
            Self.scheduledPrefixes.contains { id.hasPrefix($0) }
        }
        center.removePendingNotificationRequests(withIdentifiers: ours)
        await refreshAuthorization()
        guard isAllowedBySystem else { return }

        var plan: [PlannedNotification] = []
        if cloudAIAllowed, preferences.creditsBack, !isPro, credits == 0 {
            plan.append(NotificationPlanner.creditsBack(refill: nextRefill, dailyCredits: dailyCredits))
        }
        if cloudAIAllowed, preferences.weeklyLook {
            plan += NotificationPlanner.weeklyLooks(after: Date(), isPro: isPro)
        }
        for item in plan where item.date > Date() {
            let content = UNMutableNotificationContent()
            let copy = Self.localizedCopy(for: item, dailyCredits: dailyCredits)
            content.title = copy.title
            content.body = copy.body
            content.sound = .default
            content.userInfo = ["link": item.link.url.absoluteString]
            content.threadIdentifier = item.kind.rawValue
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
        }
    }

    /// "Your edit is ready" when a job finishes while she's in another app
    /// and no Live Activity is showing it already. Never at night or in
    /// school hours (a later ping could point at an edit that's gone), and
    /// never her prompt: it would sit on the Lock Screen.
    func notifyJobFinished(success: Bool, isCreate: Bool) {
        guard preferences.glowReady, isAllowedBySystem, NotificationPlanner.mayPostNow(Date()),
              UIApplication.shared.applicationState != .active else { return }
        let content = UNMutableNotificationContent()
        let copy = success
            ? (title: isCreate ? String(localized: "Your images are ready ✨") : String(localized: "Your edit is ready ✨"),
               body: Platform.isMac ? String(localized: "Click to see it.") : String(localized: "Tap to see it."))
            : (title: String(localized: "That one didn't work"),
               // Not "no credit was used": a result lost with the connection is
               // refunded later, by the server.
               body: Platform.isMac ? String(localized: "Failed creations are refunded automatically. Click to try again.")
                                    : String(localized: "Failed creations are refunded automatically. Tap to try again."))
        content.title = copy.title
        content.body = copy.body
        content.sound = .default
        content.threadIdentifier = GlowNotificationKind.glowReady.rawValue
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "glowlit.job.\(UUID().uuidString)", content: content, trigger: nil))
    }

    /// "Your poll ends in an hour": one reminder per poll, only while
    /// notifications are allowed (it never asks), at the planner's times
    /// (never at night or in school hours, or not at all), and never with her
    /// question: it would sit on the Lock Screen.
    func schedulePollReminder(id: String, expiresAt: Date) async {
        await refreshAuthorization()
        guard isAllowedBySystem, let date = NotificationPlanner.pollEnding(expiresAt: expiresAt, now: Date()) else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Your poll ends in an hour ⏳")
        content.body = Platform.isMac ? String(localized: "Click to see how your friends voted.")
                                      : String(localized: "Tap to see how your friends voted.")
        content.sound = .default
        content.userInfo = ["link": GlowDeepLink.poll(id).url.absoluteString]
        content.threadIdentifier = "glowlit.polls"
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: Self.pollReminderID(id), content: content, trigger: trigger))
    }

    /// Her poll was deleted: no reminder for it.
    func cancelPollReminder(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.pollReminderID(id)])
    }

    private static func pollReminderID(_ id: String) -> String { "glowlit.poll-ending.\(id)" }

    /// The planner decides when; the words are in the user's language.
    private static func localizedCopy(for item: PlannedNotification, dailyCredits: Int) -> (title: String, body: String) {
        switch item.kind {
        case .creditsBack:
            return (String(localized: "Your free credits are back ✨"),
                    String(localized: "\(dailyCredits) fresh credits for today."))
        case .weeklyLook:
            guard case .template(let id) = item.link, let look = TemplateCatalog.template(id: id) else {
                return (item.title, item.body)
            }
            return (String(localized: "This week's look: \(L10n.core(look.title)) ✨"),
                    String(localized: "\(L10n.core(look.subtitle))."))
        case .glowReady:
            return (item.title, item.body)
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(preferences) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}

/// Shows reminders as banners in the foreground and routes taps to deep links.
private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    var onOpen: (@MainActor (GlowDeepLink) -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let link = (response.notification.request.content.userInfo["link"] as? String)
            .flatMap(URL.init(string:))
            .flatMap(GlowDeepLink.init(url:))
        if let link {
            Task { @MainActor in self.onOpen?(link) }
        }
        completionHandler()
    }
}
