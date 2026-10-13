import Foundation
import UserNotifications

/// "We'll remind you before your trial ends" — a promise made on the paywall
/// timeline and kept with a local notification 24 hours before billing.
enum TrialReminder {
    static let identifier = "glowlit.trial-reminder"

    static func schedule(trialDays: Int, price: String) async {
        guard trialDays > 1 else { return }
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Your free trial ends tomorrow")
        content.body = String(localized: "You'll be charged \(price) unless you cancel. Manage it anytime in Settings › Apple Account › Subscriptions.")
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(trialDays - 1) * 86_400, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
