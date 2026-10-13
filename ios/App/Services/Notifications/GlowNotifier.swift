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

    private func ensurePermission() async -> Bool {
        await refreshAuthorization()
        if canAskPermission {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            await refreshAuthorization()
        }
        return isAllowedBySystem
    }

    /// Replaces the scheduled reminders with the current plan.
    func reschedule(credits: Int, isPro: Bool, nextRefill: Date, dailyCredits: Int) async {
        let center = UNUserNotificationCenter.current()
        let ours = await center.pendingNotificationRequests().map(\.identifier).filter { id in
            Self.scheduledPrefixes.contains { id.hasPrefix($0) }
        }
        center.removePendingNotificationRequests(withIdentifiers: ours)
        await refreshAuthorization()
        guard isAllowedBySystem else { return }

        var plan: [PlannedNotification] = []
        if preferences.creditsBack, !isPro, credits == 0 {
            plan.append(NotificationPlanner.creditsBack(refill: nextRefill, dailyCredits: dailyCredits))
        }
        if preferences.weeklyLook {
            plan += NotificationPlanner.weeklyLooks(after: Date())
        }
        for item in plan where item.date > Date() {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            content.userInfo = ["link": item.link.url.absoluteString]
            content.threadIdentifier = item.kind.rawValue
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
        }
    }

    /// "Your glow-up is ready" when a job finishes while she's in another app
    /// and no Live Activity is showing it already.
    func notifyJobFinished(success: Bool, title: String) {
        guard preferences.glowReady, isAllowedBySystem,
              UIApplication.shared.applicationState != .active else { return }
        let copy = NotificationPlanner.jobFinished(success: success, title: title)
        let content = UNMutableNotificationContent()
        content.title = copy.title
        content.body = copy.body
        content.sound = .default
        content.threadIdentifier = GlowNotificationKind.glowReady.rawValue
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "glowlit.job.\(UUID().uuidString)", content: content, trigger: nil))
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
