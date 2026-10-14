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

/// A company that processes what she sends to cloud AI, as listed on the
/// consent sheet and in Settings. Names stay as they are; roles are
/// translated in the app.
struct AIProcessor: Codable, Equatable, Hashable {
    enum Role: String, Codable {
        case servers, images, safety
    }

    let name: String
    let role: Role

    var roleText: String {
        switch role {
        case .servers: return String(localized: "Our servers: your AI jobs and credits")
        case .images: return String(localized: "Creates and edits the images")
        case .safety: return String(localized: "Checks results for safety")
        }
    }
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
    /// Added only when the picture was made or changed with generative AI.
    var aiShareHashtags: [String] = ["AIphoto", "MadeWithAI"]
    /// RevenueCat public SDK key ("appl_…"; safe to ship). Empty: RevenueCat off.
    var revenueCatAPIKey: String
    /// Offers Sign in with Apple (Settings › Account, the paywall's "Sign in",
    /// the prompt after a purchase). Off until the backend can revoke Apple
    /// tokens on deletion (APPLE_SIGNIN_KEY_ID / APPLE_SIGNIN_PRIVATE_KEY);
    /// anonymous accounts, purchases, credits and Delete my data work either way.
    var signInWithApple = false
    /// Bump to ask everyone for consent again (the processor list changing
    /// asks again by itself).
    var consentVersion = 1
    /// Who processes cloud AI requests. Must match the backend: a new
    /// provider or FAL_KEY (fal.ai's output check, role `.safety`) needs an
    /// app update that lists it first. Without FAL_KEY, xAI's own moderation
    /// is the output check, so fal.ai sees nothing and isn't listed.
    var aiProcessors: [AIProcessor] = AppConfig.defaultProcessors

    static let defaultProcessors = [
        AIProcessor(name: "Supabase", role: .servers),
        AIProcessor(name: "xAI (Grok Imagine)", role: .images),
    ]

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
        aiProviderName: String(localized: "our AI processing partners"),
        dataRetentionHours: 1,
        privacyPolicyURL: URL(string: "https://github.com/RiosenBeq/aybuke-app/blob/main/docs/legal/en/privacy-policy.md")!,
        termsURL: URL(string: "https://github.com/RiosenBeq/aybuke-app/blob/main/docs/legal/en/terms-of-use.md")!,
        supportEmail: "hello@buaze.com",
        appStoreID: "",
        websiteURL: "",
        instagramAppID: "",
        shareHashtags: ["Glowlit", "GlowUp"],
        revenueCatAPIKey: ""
    )

    private enum CodingKeys: String, CodingKey {
        case backendBaseURL, supabaseAnonKey, forceDemoMode, aiProviderName, dataRetentionHours
        case privacyPolicyURL, termsURL, supportEmail, appStoreID, websiteURL, instagramAppID, shareHashtags
        case aiShareHashtags, revenueCatAPIKey, consentVersion, aiProcessors, signInWithApple
    }

    init(
        backendBaseURL: String, supabaseAnonKey: String, forceDemoMode: Bool, aiProviderName: String,
        dataRetentionHours: Int, privacyPolicyURL: URL, termsURL: URL, supportEmail: String, appStoreID: String,
        websiteURL: String, instagramAppID: String, shareHashtags: [String], revenueCatAPIKey: String = ""
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
        self.revenueCatAPIKey = revenueCatAPIKey
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
        aiShareHashtags = try container.decodeIfPresent([String].self, forKey: .aiShareHashtags) ?? fallback.aiShareHashtags
        revenueCatAPIKey = try container.decodeIfPresent(String.self, forKey: .revenueCatAPIKey) ?? ""
        consentVersion = try container.decodeIfPresent(Int.self, forKey: .consentVersion) ?? fallback.consentVersion
        aiProcessors = try container.decodeIfPresent([AIProcessor].self, forKey: .aiProcessors) ?? fallback.aiProcessors
        signInWithApple = try container.decodeIfPresent(Bool.self, forKey: .signInWithApple) ?? false
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

    /// "an hour" or "N hours", matching the privacy policy's 1-hour promise.
    var retentionPhrase: String {
        dataRetentionHours <= 1 ? String(localized: "an hour") : String(localized: "\(dataRetentionHours) hours")
    }

    /// Who processes photos, as named on the consent screen and in Settings.
    var processorName: String {
        if case .direct(let direct) = aiMode { return direct.provider.processorName }
        return aiProviderName
    }

    /// The processors the consent sheet names; a developer key goes straight
    /// to its provider.
    var consentProcessors: [AIProcessor] {
        if case .direct(let direct) = aiMode { return [AIProcessor(name: direct.provider.processorName, role: .images)] }
        return aiProcessors
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
