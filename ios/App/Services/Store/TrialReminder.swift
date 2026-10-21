import Foundation
import UserNotifications
import AppCore

/// "We'll remind you before your trial ends" — a promise made on the paywall
/// timeline, kept with a local notification before the cancel-by time
/// (26 hours before the trial ends), never at night or in school hours.
enum TrialReminder {
    static let identifier = "glowlit.trial-reminder"

    /// When the reminder fires for a trial ending at `trialEnd`; nil when
    /// there's no allowed moment left (see `NotificationPlanner.trialReminder`).
    static func fireDate(trialEnd: Date, now: Date = Date()) -> Date? {
        NotificationPlanner.trialReminder(trialEnd: trialEnd, now: now)
    }

    /// - Parameters:
    ///   - trialEnd: When the trial ends and the first payment is due.
    ///   - price: The first payment, when the product is known.
    ///   - mayAsk: Ask for notification permission. False for trials found
    ///     in the background (an approval, an offer code, a launch), so no
    ///     prompt appears out of nowhere; the reminder is then set only if allowed.
    /// - Returns: Whether the reminder is scheduled.
    @discardableResult
    static func schedule(trialEnd: Date, price: String?, mayAsk: Bool) async -> Bool {
        guard let fireDate = fireDate(trialEnd: trialEnd) else { return false }
        let center = UNUserNotificationCenter.current()
        let granted: Bool
        if mayAsk {
            granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        } else {
            let status = await center.notificationSettings().authorizationStatus
            granted = status == .authorized || status == .provisional
        }
        guard granted else { return false }

        // The reminder can come two days early (never at night), so it names
        // the day rather than saying "tomorrow".
        let style = Date.FormatStyle.dateTime.weekday(.wide).hour().minute()
        let ends = trialEnd.formatted(style)
        let cancelBy = trialEnd.addingTimeInterval(-86_400).formatted(style)
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Your free trial ends \(ends)")
        // On the Mac, subscriptions are managed in the App Store app, not Settings.
        if let price {
            content.body = Platform.isMac
                ? String(localized: "To avoid the \(price) charge, cancel before \(cancelBy) in the App Store app › your name › Account Settings › Subscriptions.")
                : String(localized: "To avoid the \(price) charge, cancel before \(cancelBy) in Settings › Apple Account › Subscriptions.")
        } else {
            content.body = Platform.isMac
                ? String(localized: "To avoid being charged, cancel before \(cancelBy) in the App Store app › your name › Account Settings › Subscriptions.")
                : String(localized: "To avoid being charged, cancel before \(cancelBy) in Settings › Apple Account › Subscriptions.")
        }
        content.sound = .default

        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        return true
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
