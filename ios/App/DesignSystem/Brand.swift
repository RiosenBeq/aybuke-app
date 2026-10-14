import Foundation

/// Brand constants. Rationale and research: docs/02-brand-identity.md
enum Brand {
    static let name = "Aybuke"
    static var tagline: String { String(localized: "Make it glow") }
    /// App Store title (≤ 30 characters).
    static let storeTitle = "Aybuke: AI Photo Editor"
}
