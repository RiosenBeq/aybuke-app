import Foundation

/// Meteorological season, used to pick timely ideas ("Inspire me").
public enum Season: String, CaseIterable, Sendable {
    case spring, summer, autumn, winter

    /// The season on `date`. Months are flipped south of the equator, so an
    /// October idea in São Paulo is a spring one.
    public static func of(_ date: Date, calendar: Calendar = .current, southernHemisphere: Bool = false) -> Season {
        let month = calendar.component(.month, from: date)
        let north: Season
        switch month {
        case 3...5: north = .spring
        case 6...8: north = .summer
        case 9...11: north = .autumn
        default: north = .winter
        }
        return southernHemisphere ? north.opposite : north
    }

    /// Regions (ISO 3166 codes) where the seasons run opposite to the north.
    /// Equatorial places are left out: "autumn" ideas read fine there.
    public static let southernRegions: Set<String> = [
        "AR", "AU", "BR", "CL", "NZ", "PY", "UY", "ZA",
    ]

    var opposite: Season {
        switch self {
        case .spring: return .autumn
        case .summer: return .winter
        case .autumn: return .spring
        case .winter: return .summer
        }
    }
}

extension PromptBuilder {
    /// A random idea that differs from `previous` whenever there's a choice,
    /// so tapping "Inspire me" twice never shows the same line.
    public static func pickIdea<G: RandomNumberGenerator>(
        from ideas: [String],
        avoiding previous: String?,
        using generator: inout G
    ) -> String? {
        let fresh = ideas.filter { $0 != previous }
        return (fresh.isEmpty ? ideas : fresh).randomElement(using: &generator)
    }
}
