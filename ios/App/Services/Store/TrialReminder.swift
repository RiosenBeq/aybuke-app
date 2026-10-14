import Foundation
import UserNotifications

/// "We'll remind you before your trial ends" — a promise made on the paywall
/// timeline and kept with a local notification 24 hours before billing.
enum TrialReminder {
    static let identifier = "glowlit.trial-reminder"

    /// - Parameters:
    ///   - billingDate: When the trial ends and the first payment is due.
    ///   - mayAsk: Ask for notification permission. False for trials that
    ///     start in the background (an approval, an offer code), so no prompt
    ///     appears out of nowhere; the reminder is then set only if allowed.
    static func schedule(billingDate: Date, price: String, mayAsk: Bool) async {
        let fireDate = billingDate.addingTimeInterval(-86_400)
        guard fireDate.timeIntervalSinceNow > 3_600 else { return }
        let center = UNUserNotificationCenter.current()
        let granted: Bool
        if mayAsk {
            granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        } else {
            let status = await center.notificationSettings().authorizationStatus
            granted = status == .authorized || status == .provisional
        }
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Your free trial ends tomorrow")
        content.body = String(localized: "You'll be charged \(price) unless you cancel. Manage it anytime in Settings › Apple Account › Subscriptions.")
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: fireDate.timeIntervalSinceNow, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
