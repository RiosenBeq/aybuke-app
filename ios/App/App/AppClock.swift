import Foundation

/// Today's date for date-driven content (seasonal looks). DEBUG builds can
/// pin it with `-GLDate 2026-12-20` so QA and screenshot scenes can check
/// every season on any day.
enum AppClock {
    static var now: Date {
        #if DEBUG
        if let text = UserDefaults.standard.string(forKey: "GLDate") {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.dateFormat = "yyyy-MM-dd"
            if let day = formatter.date(from: text) {
                // Midday, so time zones can't push it onto the next or previous day.
                return day.addingTimeInterval(12 * 3600)
            }
        }
        #endif
        return Date()
    }
}
