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

/// A company that processes what she sends to cloud AI. Apple asks apps to
/// say who gets the data before sharing it with a third-party AI (5.1.2(i)),
/// so the consent sheet names them in one small footnote and Settings in a
/// collapsed "Providers" row (`providersLine`); everywhere else the app says
/// "our servers", "a third-party AI provider" or "Aybik, our AI helper",
/// never a company. `name` is what the consent record compares, so it stays
/// as stored.
struct AIProcessor: Codable, Equatable, Hashable {
    enum Role: String, Codable {
        case servers, images, safety
        /// The safety check that also writes prompts, captions and makeup
        /// picks from text (`assist`, `CloudWriter`): Aybik, the app's AI
        /// helper, since consent version 3.
        case safetyAndWriting

        /// Checks photos and results: the consent sheet says how long it keeps them.
        var checksSafety: Bool { self == .safety || self == .safetyAndWriting }

        /// The footnote names the AI providers first, then the servers.
        fileprivate var footnoteOrder: Int {
            switch self {
            case .images: return 0
            case .safety, .safetyAndWriting: return 1
            case .servers: return 2
            }
        }
    }

    let name: String
    let role: Role

    /// The company alone, without its product: "xAI (Grok Imagine)" → "xAI".
    var displayName: String {
        name.components(separatedBy: " (").first ?? name
    }

    /// The row's title on the consent sheet: what it is, never who.
    var title: String {
        switch role {
        case .servers: return String(localized: "Our servers")
        case .images: return String(localized: "AI image provider")
        case .safety: return String(localized: "AI safety provider")
        case .safetyAndWriting: return String(localized: "AI safety and writing provider")
        }
    }

    var roleText: String {
        switch role {
        case .servers:
            return String(localized: "Your AI jobs, credits and polls",
                          comment: "What “Our servers” (the app's own backend) do, on the AI consent sheet: run her AI jobs, keep her credits and her “Which vibe?” polls with friends")
        case .images: return String(localized: "Creates and edits the images")
        // The independent check sees the photo before an edit and every
        // result; Create sends text only, so "photos you edit", not "your photo".
        case .safety: return String(localized: "Checks photos you edit and every result for safety")
        // Writing help gets her words, never a photo; polls send two pictures to the check.
        case .safetyAndWriting:
            return String(localized: "Powers Aybik, our AI helper: checks photos, results and poll pictures for safety, and helps write prompts and captions (text only)",
                          comment: "Anthropic's role on the AI consent sheet: its AI model is behind Aybik (the app's AI helper), checks photos, results and the pictures of “Which vibe?” polls for safety, and writes ideas, prompts and captions from text. Keep the name Aybik.")
        }
    }

    /// Its part in a word or two, after its name in `providersLine`.
    private var shortRole: String {
        switch role {
        case .servers: return String(localized: "servers")
        case .images: return String(localized: "images")
        case .safety: return String(localized: "safety checks")
        case .safetyAndWriting: return String(localized: "safety checks and Aybik")
        }
    }

    /// The companies and their parts: "xAI (images), Anthropic (safety
    /// checks and Aybik), Supabase (servers)". Settings shows it in a
    /// collapsed "Providers" row.
    static func providersList(_ processors: [AIProcessor]) -> String {
        processors.sorted { $0.role.footnoteOrder < $1.role.footnoteOrder }.map { processor in
            String(localized: "\(processor.displayName) (\(processor.shortRole))",
                   comment: "A company and what it does for the app, in the consent sheet's footnote and Settings' Providers row, e.g. “xAI (images)”. Use the language's own parentheses.")
        }
        .formatted(.list(type: .and, width: .narrow))
    }

    /// The consent sheet's footnote, the one place there the companies are
    /// named: "Providers: xAI (images), Anthropic (safety checks and Aybik),
    /// Supabase (servers)".
    static func providersLine(_ processors: [AIProcessor]) -> String {
        String(localized: "Providers: \(providersList(processors))",
               comment: "Footnote under the AI consent sheet's list: the companies that process what she sends, e.g. “Providers: xAI (images), Anthropic (safety checks and Aybik), Supabase (servers)”")
    }
}

/// Ads for free members 13+ (Pro has none, and neither does the Mac app): an
/// optional rewarded ad (+1 credit) when she's out of credits, and now and
/// then an interstitial after a finished save. DEBUG builds always use
/// Google's test units; Release builds use these, and a missing or malformed
/// id turns that format off.
struct AdsConfig: Decodable, Equatable {
    var enabled = false
    /// The AdMob app id. The SDK reads it from Info.plist (GADApplicationIdentifier,
    /// set from GL_ADMOB_APP_ID in Release.xcconfig); a Release build whose
    /// Info.plist says something else shows no ads.
    var appID = ""
    var rewardedUnitID = ""
    /// Empty: no interstitials.
    var interstitialUnitID = ""
    /// Rewarded ads a day; the server's `ad_reward_policy()` has the final say
    /// (per user and per App Store install).
    var dailyCap = 2

    #if DEBUG
    static let testAppID = "ca-app-pub-3940256099942544~1458002511"
    static let testRewardedUnitID = "ca-app-pub-3940256099942544/1712485313"
    static let testInterstitialUnitID = "ca-app-pub-3940256099942544/4411468910"
    #endif

    private enum CodingKeys: String, CodingKey {
        case enabled, appID, rewardedUnitID, interstitialUnitID, dailyCap
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        appID = try container.decodeIfPresent(String.self, forKey: .appID) ?? ""
        rewardedUnitID = try container.decodeIfPresent(String.self, forKey: .rewardedUnitID) ?? ""
        interstitialUnitID = try container.decodeIfPresent(String.self, forKey: .interstitialUnitID) ?? ""
        dailyCap = try container.decodeIfPresent(Int.self, forKey: .dailyCap) ?? 2
    }

    /// The app id this build's Info.plist hands the SDK, when it's the one
    /// these units belong to (Google's sample app in DEBUG builds).
    var bundleAppIDMatches: Bool {
        let bundled = (Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String) ?? ""
        #if DEBUG
        return bundled == Self.testAppID
        #else
        return AdMobID.isAppID(bundled) && bundled == appID
        #endif
    }

    /// The rewarded unit this build requests, or nil when rewarded ads are off.
    var activeRewardedUnitID: String? {
        guard enabled, bundleAppIDMatches else { return nil }
        #if DEBUG
        return Self.testRewardedUnitID
        #else
        return AdMobID.isUnitID(rewardedUnitID) && AdMobID.publisher(of: rewardedUnitID) == AdMobID.publisher(of: appID)
            ? rewardedUnitID : nil
        #endif
    }

    /// The interstitial unit this build requests, or nil when they're off.
    var activeInterstitialUnitID: String? {
        guard enabled, bundleAppIDMatches else { return nil }
        #if DEBUG
        return Self.testInterstitialUnitID
        #else
        return AdMobID.isUnitID(interstitialUnitID) && AdMobID.publisher(of: interstitialUnitID) == AdMobID.publisher(of: appID)
            ? interstitialUnitID : nil
        #endif
    }
}

/// Runtime configuration loaded from `AppConfig.json` in the bundle.
/// Leave `backendBaseURL` empty to run in demo mode (no network, simulated AI).
struct AppConfig: Decodable {
    var backendBaseURL: String
    var supabaseAnonKey: String
    var forceDemoMode: Bool
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
    /// the prompt after a purchase). On in AppConfig.json since 1.0, once the
    /// backend could revoke Apple tokens on deletion (APPLE_SIGNIN_KEY_ID /
    /// APPLE_SIGNIN_PRIVATE_KEY); defaults to off when the key is missing.
    /// Anonymous accounts, purchases, credits and Delete my data work either way.
    var signInWithApple = false
    /// Bump to ask everyone for consent again (the processor list changing
    /// asks again by itself). 2: Anthropic joined as the safety check.
    /// 3: Anthropic also helps write prompts and captions (`assist`).
    var consentVersion = 3
    /// Who processes cloud AI requests. Must match the backend: Anthropic
    /// (role `.safetyAndWriting`) is the independent check in
    /// `_shared/safety.ts` and the writing help in `functions/assist`
    /// (ANTHROPIC_API_KEY). A new provider, or setting FAL_KEY (fal.ai), needs
    /// an app update that lists it first; without FAL_KEY fal.ai sees nothing,
    /// so it isn't listed.
    var aiProcessors: [AIProcessor] = AppConfig.defaultProcessors
    /// Ads for free members (not an AI processor, so not on the consent sheet).
    var ads = AdsConfig()
    /// The credit numbers the copy shows until the server reports its own
    /// (`credit_policy()`; the app keeps the last ones it saw).
    var creditPolicy = CreditPolicy.standard

    static let defaultProcessors = [
        AIProcessor(name: "Supabase", role: .servers),
        AIProcessor(name: "xAI (Grok Imagine)", role: .images),
        AIProcessor(name: "Anthropic", role: .safetyAndWriting),
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
        dataRetentionHours: 1,
        privacyPolicyURL: URL(string: "https://github.com/RiosenBeq/aybuke-app/blob/main/docs/legal/en/privacy-policy.md")!,
        termsURL: URL(string: "https://github.com/RiosenBeq/aybuke-app/blob/main/docs/legal/en/terms-of-use.md")!,
        supportEmail: "hello@buaze.com",
        appStoreID: "",
        websiteURL: "",
        instagramAppID: "",
        shareHashtags: ["Aybuke", "GlowUp"],
        revenueCatAPIKey: ""
    )

    private enum CodingKeys: String, CodingKey {
        case backendBaseURL, supabaseAnonKey, forceDemoMode, dataRetentionHours
        case privacyPolicyURL, termsURL, supportEmail, appStoreID, websiteURL, instagramAppID, shareHashtags
        case aiShareHashtags, revenueCatAPIKey, consentVersion, aiProcessors, signInWithApple, ads, creditPolicy
    }

    init(
        backendBaseURL: String, supabaseAnonKey: String, forceDemoMode: Bool,
        dataRetentionHours: Int, privacyPolicyURL: URL, termsURL: URL, supportEmail: String, appStoreID: String,
        websiteURL: String, instagramAppID: String, shareHashtags: [String], revenueCatAPIKey: String = ""
    ) {
        self.backendBaseURL = backendBaseURL
        self.supabaseAnonKey = supabaseAnonKey
        self.forceDemoMode = forceDemoMode
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
        // A broken ads section turns ads off, never the rest of the config.
        ads = (try? container.decodeIfPresent(AdsConfig.self, forKey: .ads)) ?? AdsConfig()
        creditPolicy = (try? container.decodeIfPresent(CreditPolicy.self, forKey: .creditPolicy)) ?? .standard
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
