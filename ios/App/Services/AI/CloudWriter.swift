import Foundation
import AppCore

/// Writing help from the server (`POST /functions/v1/assist`, the contract
/// in AppCore's `Assist.swift`): Anthropic's Claude writes Create's ideas and
/// prompt upgrades, share captions and Makeup Studio's picks for "Describe
/// your vibe". Text only, never a photo, and no credits.
///
/// It uses only the session she already has (`existingAccessToken()`), so
/// nobody gets an account for writing help, and sends StoreKit's
/// AppTransaction like cloud jobs do: without a verified install the server
/// only shares a small allowance. Every failure throws; the callers in
/// `AppModel` fall back to Apple's on-device writer and the hand-written
/// lists without a word, and screen every line on the device
/// (`Assist.screened`) before she sees it.
final class CloudWriter: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse?)

    private let config: BackendConfiguration
    private let accessToken: @Sendable () async throws -> String?
    private let appTransaction: @Sendable () async -> String?
    private let transport: Transport

    init(config: BackendConfiguration, auth: AuthSessionManager, appTransactions: AppTransactionProvider, session: URLSession = .shared) {
        self.config = config
        accessToken = { try await auth.existingAccessToken() }
        // Usually read at launch already; writing help never waits long for
        // it and goes without when StoreKit has none yet.
        appTransaction = { await appTransactions.jws(waitingAtMost: .seconds(1)) }
        transport = { request in
            let (data, response) = try await session.mappedData(for: request)
            return (data, response as? HTTPURLResponse)
        }
    }

    private init(config: BackendConfiguration, accessToken: @escaping @Sendable () async throws -> String?, transport: @escaping Transport) {
        self.config = config
        self.accessToken = accessToken
        appTransaction = { nil }
        self.transport = transport
    }

    /// Ideas, a prompt upgrade or captions, not screened yet.
    func suggestions(for request: AssistRequest) async throws -> [String] {
        let (data, response) = try await send(request)
        return try ResponseDecoder.decodeAssistSuggestions(
            data: data, statusCode: response?.statusCode ?? 0, retryAfter: response?.value(forHTTPHeaderField: "Retry-After"))
    }

    /// Makeup Studio ids for her words, and a note about them.
    func makeup(for request: AssistRequest) async throws -> AssistMakeupReply {
        let (data, response) = try await send(request)
        return try ResponseDecoder.decodeAssistMakeup(
            data: data, statusCode: response?.statusCode ?? 0, retryAfter: response?.value(forHTTPHeaderField: "Retry-After"))
    }

    private func send(_ body: AssistRequest) async throws -> (Data, HTTPURLResponse?) {
        try body.validate()
        // Refreshed if it expired, but never a new sign-up.
        guard let token = try await accessToken() else { throw AssistError.noSession }
        let request = try RequestFactory.assist(body, config: config, accessToken: token, appTransactionJWS: await appTransaction())
        return try await transport(request)
    }
}

/// Which model wrote a suggestion on screen, so the screen can say so.
enum WrittenBy: Equatable {
    /// Apple's on-device model (`OnDeviceWriter`): nothing left the device.
    case device
    /// The server's writing help, Claude (`CloudWriter`).
    case cloud
}

/// What "Describe your vibe" came to.
enum MakeupVibeOutcome: Equatable {
    /// Picks to show on the chips, and a line about them when one passed the policy.
    case suggested(MakeupRecipe, note: String?)
    /// Her words aren't allowed (on the device or on the server): why, in her language.
    case blocked(String)
    /// Nothing usable came back (an error, a timeout, no ids we know).
    case notFound
}

extension AppModel {
    /// The server's writing help may be asked: cloud AI allowed for her age,
    /// her consent, a session (it never makes one), a connection, no rest
    /// for her (`cloudPause`) and no pause of all cloud AI. Otherwise the
    /// on-device writer and the hand-written lists answer, exactly as before.
    var usesCloudWriter: Bool {
        guard cloudWriter != nil, allowsCloudAI, hasAIConsent, !isCloudOffline, cloudPause?.isActive() != true,
              !pausesWritingHelp else { return false }
        #if DEBUG
        if CloudWriter.isStubbed { return true }
        #endif
        return hasSession && !Self.staysOffServer
    }

    /// The owner's pause for all cloud AI, which the writing help keeps too
    /// (a pause of free credits only leaves it on).
    private var pausesWritingHelp: Bool {
        guard let aiServicePause, aiServicePause.isActive() else { return false }
        return !aiServicePause.freeOnly
    }

    /// The language the app shows, which the answer comes in.
    private var writingLanguage: String {
        Assist.languageCode(for: Bundle.main.preferredLocalizations.first ?? "en")
    }

    private static func styleHint(_ style: ImageStyle) -> String? {
        style == StyleCatalog.auto ? nil : style.id
    }

    /// "Inspire me": up to four ideas (one shown, the rest kept for the next
    /// taps), screened on the device; none when writing help is off or fails.
    func cloudIdeas(style: ImageStyle) async -> [String] {
        guard usesCloudWriter, let cloudWriter else { return [] }
        let request = AssistRequest(task: .inspire, locale: writingLanguage, context: AssistContext(style: Self.styleHint(style)))
        guard let lines = try? await cloudWriter.suggestions(for: request) else { return [] }
        return Assist.screened(lines, for: AssistTask.inspire.screeningOperation, limit: 4)
    }

    /// "Make it magic": her idea as one richer prompt, or nil (writing help
    /// off or failing, her idea too long or not allowed, nothing new back).
    func cloudPromptUpgrade(_ prompt: String, style: ImageStyle) async -> String? {
        let idea = PromptBuilder.sanitize(prompt)
        guard usesCloudWriter, let cloudWriter, !idea.isEmpty, idea.count <= AssistRequest.maxTextLength,
              ContentPolicy.evaluate(idea, operation: .textToImage).isAllowed else { return nil }
        let request = AssistRequest(task: .magic, text: idea, locale: writingLanguage, context: AssistContext(style: Self.styleHint(style)))
        guard let lines = try? await cloudWriter.suggestions(for: request) else { return nil }
        let upgraded = Assist.screened(lines, for: AssistTask.magic.screeningOperation, maxLength: PromptBuilder.maxPromptLength, limit: 1)
        return upgraded.first.flatMap { $0 == idea ? nil : $0 }
    }

    /// Caption ideas for the share composer, about the vibe, only after she
    /// asked: the writer hears her Create prompt (`SharePayload.shareablePrompt`)
    /// or a plain line, and the design she picked. None when writing help is
    /// off or fails.
    func cloudCaptions(prompt: String?, madeWithAI: Bool, format: String) async -> [String] {
        guard usesCloudWriter, let cloudWriter else { return [] }
        let request = AssistRequest(task: .captions, text: Assist.captionHint(prompt: prompt, madeWithAI: madeWithAI),
                                    locale: writingLanguage, context: AssistContext(format: format))
        guard let lines = try? await cloudWriter.suggestions(for: request) else { return [] }
        return Assist.screened(lines, for: AssistTask.captions.screeningOperation)
    }

    /// Makeup Studio's "Describe your vibe": her words pass the policy here
    /// first, then the writer picks ids, which become chips for her to check
    /// before Try it (that still costs a credit and goes through every gate).
    func suggestMakeup(for vibe: String, current: MakeupRecipe) async -> MakeupVibeOutcome {
        let words = PromptBuilder.sanitize(vibe)
        guard !words.isEmpty else { return .notFound }
        if case .blocked(let reason, _) = ContentPolicy.evaluate(words, operation: .magicEdit) {
            return .blocked(L10n.core(reason))
        }
        guard usesCloudWriter, let cloudWriter, words.count <= AssistRequest.maxTextLength else { return .notFound }
        let request = AssistRequest(task: .makeup, text: words, locale: writingLanguage,
                                    context: AssistContext(look: MakeupStudio.preset(matching: current)?.id))
        do {
            let reply = try await cloudWriter.makeup(for: request)
            guard let recipe = MakeupStudio.recipe(from: reply.makeup, keepingHair: current.hair) else { return .notFound }
            let note = reply.note.flatMap { Assist.screened([$0], for: AssistTask.makeup.screeningOperation, maxLength: 240, limit: 1).first }
            return .suggested(recipe, note: note)
        } catch AssistError.contentBlocked(let category) {
            // The server's policy: its reason when it names one, else "try other words".
            if let category = category.flatMap(PolicyCategory.init(rawValue:)),
               case .blocked(let reason, _) = ContentPolicy.verdict(for: category) {
                return .blocked(L10n.core(reason))
            }
            return .notFound
        } catch {
            return .notFound
        }
    }
}

#if DEBUG
extension CloudWriter {
    /// `-GLAssistStub YES`: canned answers without a server or a session, so
    /// screenshots and QA show the writing help (`fail` answers 503, as an
    /// outage would; `blocked` answers 422). The answers go through the same
    /// request building and decoding as the server's.
    static var stubMode: String? {
        guard let mode = UserDefaults.standard.string(forKey: "GLAssistStub")?.lowercased(),
              ["yes", "true", "1", "fail", "blocked"].contains(mode) else { return nil }
        return mode
    }

    static var isStubbed: Bool { stubMode != nil }

    static func stub() -> CloudWriter {
        let mode = stubMode ?? "yes"
        // Never reached: the transport below answers instead of the network.
        let config = BackendConfiguration(baseURL: URL(string: "https://assist.stub.invalid")!, anonKey: "stub")
        return CloudWriter(config: config, accessToken: { "stub-session" }) { request in
            try await Task.sleep(for: .milliseconds(700))
            let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            let (status, json) = Self.stubAnswer(task: body["task"] as? String, text: body["text"] as? String, mode: mode)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)
            return (Data(json.utf8), response)
        }
    }

    private static func stubAnswer(task: String?, text: String?, mode: String) -> (Int, String) {
        switch mode {
        case "fail": return (503, #"{"error":{"code":"assist_unavailable"}}"#)
        case "blocked": return (422, #"{"error":{"code":"content_blocked","category":"revealingClothing"}}"#)
        default: break
        }
        let answer: Any
        switch AssistTask(rawValue: task ?? "") {
        case .inspire:
            answer = ["suggestions": [
                "A cozy treehouse library at dusk with fairy lights, floating lanterns and a sleepy cat on a velvet cushion",
                "A strawberry-milk café on a cloud with pastel balloons and a rainbow at golden hour",
                "A tiny snail post office in a mushroom forest, soft morning light and sparkling dewdrops",
            ]]
        case .magic:
            let idea = (text ?? "a cat in the snow").trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            answer = ["suggestions": [
                "\(idea), at blue hour with soft falling snowflakes, warm glowing windows in the distance, pastel pink and lilac sky, gentle bokeh and a cozy, dreamy mood",
            ]]
        case .captions:
            answer = ["suggestions": [
                "Pink skies and pocket-sized daydreams",
                "Main character in my own cozy movie",
                "Collecting soft moments like seashells",
            ]]
        case .makeup:
            answer = [
                "makeup": ["look": "coldGirl", "lips": "berry", "lipFinish": "gloss", "eyes": "glitterLid", "cheeks": NSNull(),
                           "extras": ["glitter"], "hair": NSNull(), "intensity": "medium"],
                "note": "A frosty, sparkly look for a winter party: berry lips, glittery lids and a cold-weather flush.",
            ]
        case nil:
            return (400, #"{"error":{"code":"bad_request"}}"#)
        }
        let data = (try? JSONSerialization.data(withJSONObject: answer)) ?? Data()
        return (200, String(decoding: data, as: UTF8.self))
    }
}
#endif
