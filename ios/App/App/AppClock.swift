import Foundation
import AppCore

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

extension AppModel {
    /// Whose local seasons Explore shows (`SeasonAudience` in AppCore): the
    /// device's region, then the App Store storefront, then the app's
    /// language. DEBUG builds can pin the region with `-GLRegion TR`, like
    /// `-GLDate`, so QA and screenshot scenes can check every country.
    var seasonAudience: SeasonAudience {
        let language = Bundle.main.preferredLocalizations.first
        #if DEBUG
        if let region = UserDefaults.standard.string(forKey: "GLRegion"), !region.isEmpty {
            return SeasonAudience(region: region, language: language)
        }
        #endif
        return .resolve(localeRegion: Locale.current.region?.identifier, storefront: storefrontCountry, language: language)
    }
}
