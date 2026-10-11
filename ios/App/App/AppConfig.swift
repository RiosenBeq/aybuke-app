import Foundation
import AppCore

/// Runtime configuration loaded from `AppConfig.json` in the bundle.
/// Leave `backendBaseURL` empty to run in demo mode (no network, simulated AI).
struct AppConfig: Decodable {
    var backendBaseURL: String
    var supabaseAnonKey: String
    var forceDemoMode: Bool
    var aiProviderName: String
    var dataRetentionHours: Int
    var privacyPolicyURL: URL
    var termsURL: URL
    var supportEmail: String
    var appStoreID: String

    static let current: AppConfig = load()

    static func load(bundle: Bundle = .main) -> AppConfig {
        guard
            let url = bundle.url(forResource: "AppConfig", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let config = try? JSONDecoder().decode(AppConfig.self, from: data)
        else {
            return .fallback
        }
        return config
    }

    static let fallback = AppConfig(
        backendBaseURL: "",
        supabaseAnonKey: "",
        forceDemoMode: true,
        aiProviderName: "our AI processing partners",
        dataRetentionHours: 24,
        privacyPolicyURL: URL(string: "https://example.com/privacy")!,
        termsURL: URL(string: "https://example.com/terms")!,
        supportEmail: "support@example.com",
        appStoreID: ""
    )

    var backend: BackendConfiguration? {
        guard
            !forceDemoMode,
            let url = URL(string: backendBaseURL),
            url.scheme == "https",
            !supabaseAnonKey.isEmpty
        else { return nil }
        return BackendConfiguration(baseURL: url, anonKey: supabaseAnonKey)
    }

    var isDemoMode: Bool { backend == nil }

    var supportURL: URL? { URL(string: "mailto:\(supportEmail)") }

    var appStoreReviewURL: URL? {
        guard !appStoreID.isEmpty else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")
    }
}
