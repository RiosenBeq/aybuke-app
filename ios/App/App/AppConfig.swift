import Foundation
import AppCore

/// Where cloud AI jobs go.
enum AIMode {
    /// Production: our backend authenticates, meters credits and holds the
    /// provider keys.
    case backend(BackendConfiguration)
    /// DEBUG builds only: the app calls an AI provider directly with a
    /// developer key from `ios/Config/Secrets.xcconfig`. Never shipped.
    case direct(DirectAIConfiguration)
    /// No backend and no key: results are simulated on device.
    case demo
}

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
    /// Public landing page, used in share captions until the App Store link exists.
    var websiteURL: String
    /// Meta (Facebook) App ID, required by Instagram for direct Stories sharing.
    /// Empty: the Stories button falls back to the system share sheet.
    var instagramAppID: String
    /// Hashtags suggested in share captions.
    var shareHashtags: [String]

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
        privacyPolicyURL: URL(string: "https://github.com/RiosenBeq/furkan/blob/main/docs/legal/en/privacy-policy.md")!,
        termsURL: URL(string: "https://github.com/RiosenBeq/furkan/blob/main/docs/legal/en/terms-of-use.md")!,
        supportEmail: "support@glowlit.app",
        appStoreID: "",
        websiteURL: "",
        instagramAppID: "",
        shareHashtags: ["Glowlit", "AIphoto", "MadeWithAI"]
    )

    private enum CodingKeys: String, CodingKey {
        case backendBaseURL, supabaseAnonKey, forceDemoMode, aiProviderName, dataRetentionHours
        case privacyPolicyURL, termsURL, supportEmail, appStoreID, websiteURL, instagramAppID, shareHashtags
    }

    init(
        backendBaseURL: String, supabaseAnonKey: String, forceDemoMode: Bool, aiProviderName: String,
        dataRetentionHours: Int, privacyPolicyURL: URL, termsURL: URL, supportEmail: String, appStoreID: String,
        websiteURL: String, instagramAppID: String, shareHashtags: [String]
    ) {
        self.backendBaseURL = backendBaseURL
        self.supabaseAnonKey = supabaseAnonKey
        self.forceDemoMode = forceDemoMode
        self.aiProviderName = aiProviderName
        self.dataRetentionHours = dataRetentionHours
        self.privacyPolicyURL = privacyPolicyURL
        self.termsURL = termsURL
        self.supportEmail = supportEmail
        self.appStoreID = appStoreID
        self.websiteURL = websiteURL
        self.instagramAppID = instagramAppID
        self.shareHashtags = shareHashtags
    }

    /// Keys added after 1.0 are optional so older config files keep working.
    init(from decoder: Decoder) throws {
        let fallback = AppConfig.fallback
        let container = try decoder.container(keyedBy: CodingKeys.self)
        backendBaseURL = try container.decodeIfPresent(String.self, forKey: .backendBaseURL) ?? ""
        supabaseAnonKey = try container.decodeIfPresent(String.self, forKey: .supabaseAnonKey) ?? ""
        forceDemoMode = try container.decodeIfPresent(Bool.self, forKey: .forceDemoMode) ?? false
        aiProviderName = try container.decodeIfPresent(String.self, forKey: .aiProviderName) ?? fallback.aiProviderName
        dataRetentionHours = try container.decodeIfPresent(Int.self, forKey: .dataRetentionHours) ?? fallback.dataRetentionHours
        privacyPolicyURL = try container.decodeIfPresent(URL.self, forKey: .privacyPolicyURL) ?? fallback.privacyPolicyURL
        termsURL = try container.decodeIfPresent(URL.self, forKey: .termsURL) ?? fallback.termsURL
        supportEmail = try container.decodeIfPresent(String.self, forKey: .supportEmail) ?? fallback.supportEmail
        appStoreID = try container.decodeIfPresent(String.self, forKey: .appStoreID) ?? ""
        websiteURL = try container.decodeIfPresent(String.self, forKey: .websiteURL) ?? ""
        instagramAppID = try container.decodeIfPresent(String.self, forKey: .instagramAppID) ?? ""
        shareHashtags = try container.decodeIfPresent([String].self, forKey: .shareHashtags) ?? fallback.shareHashtags
    }

    var backend: BackendConfiguration? {
        guard
            !forceDemoMode,
            let url = URL(string: backendBaseURL),
            url.scheme == "https",
            !supabaseAnonKey.isEmpty
        else { return nil }
        return BackendConfiguration(baseURL: url, anonKey: supabaseAnonKey)
    }

    /// Developer key from the build settings (DEBUG builds only).
    var directAI: DirectAIConfiguration? {
        #if DEBUG
        guard !forceDemoMode else { return nil }
        let info = Bundle.main.infoDictionary ?? [:]
        func value(_ key: String) -> String? {
            (info[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return DirectAIConfiguration(
            provider: value("GLDirectAIProvider") ?? "",
            apiKey: value("GLDirectAIKey") ?? "",
            imageModel: value("GLDirectAIImageModel"),
            editModel: value("GLDirectAIEditModel")
        )
        #else
        return nil
        #endif
    }

    var aiMode: AIMode {
        if let backend { return .backend(backend) }
        if let directAI { return .direct(directAI) }
        return .demo
    }

    var isDemoMode: Bool {
        if case .demo = aiMode { return true }
        return false
    }

    /// Who processes photos, as named on the consent screen and in Settings.
    var processorName: String {
        if case .direct(let direct) = aiMode { return direct.provider.processorName }
        return aiProviderName
    }

    var supportURL: URL? { URL(string: "mailto:\(supportEmail)") }

    var appStoreURL: URL? {
        guard !appStoreID.isEmpty else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(appStoreID)")
    }

    var appStoreReviewURL: URL? {
        guard !appStoreID.isEmpty else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")
    }

    /// Link people can tap in a shared caption: the App Store page once the
    /// app is live, otherwise the landing page (if any).
    var shareLinkURL: URL? {
        appStoreURL ?? URL(string: websiteURL).flatMap { $0.scheme == "https" ? $0 : nil }
    }
}
