import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Writing help (shared contract with backend/supabase/functions/assist)

/// What the server's writing helper (`POST /functions/v1/assist`) is asked
/// for. Anthropic's Claude answers from text alone, never a photo; it costs
/// no credits and needs her session.
public enum AssistTask: String, Codable, CaseIterable, Sendable {
    /// Create's "Inspire me": new picture ideas.
    case inspire
    /// Create's "Make it magic": her idea as one richer image prompt.
    case magic
    /// Caption ideas in the share composer.
    case captions
    /// Makeup Studio's "Describe your vibe": Makeup Studio ids for her words.
    case makeup

    /// The policy rules every line it writes must pass on the device before
    /// she sees it. Captions and makeup notes are about someone's photo, so
    /// they get the stricter photo rules, as the on-device writer's do.
    public var screeningOperation: AIOperation {
        switch self {
        case .inspire, .magic: return .textToImage
        case .captions, .makeup: return .magicEdit
        }
    }
}

/// Hints for the writer, each one optional.
public struct AssistContext: Codable, Equatable, Sendable {
    /// Create's style (`ImageStyle.id`), when she picked one.
    public var style: String?
    /// The share design she picked (`photo`, `beforeAfter`, `story`, `cover`, `strip`, `pick`).
    public var format: String?
    /// The Makeup Studio look she has on (`MakeupPreset.id`).
    public var look: String?

    public init(style: String? = nil, format: String? = nil, look: String? = nil) {
        self.style = style
        self.format = format
        self.look = look
    }
}

/// The body of `POST /functions/v1/assist`.
public struct AssistRequest: Encodable, Equatable, Sendable {
    /// The server's limit on `text`, in characters.
    public static let maxTextLength = 400

    public var task: AssistTask
    /// Her words: optional for `inspire`, needed by the others. Whitespace
    /// is collapsed, and text with nothing in it counts as none.
    public var text: String?
    /// The language the app shows (`Assist.languageCode(for:)`): the answer comes in it.
    public var locale: String
    /// Always sent, even empty.
    public var context: AssistContext

    public init(task: AssistTask, text: String? = nil, locale: String, context: AssistContext = AssistContext()) {
        self.task = task
        let words = text.map { PromptBuilder.normalized($0).trimmingCharacters(in: .whitespaces) }
        self.text = words?.isEmpty == false ? words : nil
        self.locale = locale
        self.context = context
    }

    /// Mirrors the server's `bad_request` checks, so the app never asks in
    /// vain: text where the task needs it, at most `maxTextLength`
    /// characters, and a language the app speaks.
    public func validate() throws {
        if task != .inspire && text == nil { throw AssistError.badRequest }
        if let text, text.count > Self.maxTextLength { throw AssistError.badRequest }
        guard Assist.languages.contains(locale) else { throw AssistError.badRequest }
    }
}

/// Makeup Studio ids the writer picked for her words. Any of them may be
/// missing, null or unknown to this version (`MakeupStudio.recipe(from:keepingHair:)`
/// leaves those out).
public struct AssistMakeup: Decodable, Equatable, Sendable {
    public var look: String?
    public var lips: String?
    /// `MakeupLipFinish` (gloss, matte, shimmer); servers before it was added leave it out.
    public var lipFinish: String?
    public var eyes: String?
    public var cheeks: String?
    public var extras: [String]
    public var hair: String?
    public var intensity: String?

    enum CodingKeys: String, CodingKey {
        case look, lips, lipFinish, eyes, cheeks, extras, hair, intensity
    }

    public init(look: String? = nil, lips: String? = nil, lipFinish: String? = nil, eyes: String? = nil, cheeks: String? = nil,
                extras: [String] = [], hair: String? = nil, intensity: String? = nil) {
        self.look = look
        self.lips = lips
        self.lipFinish = lipFinish
        self.eyes = eyes
        self.cheeks = cheeks
        self.extras = extras
        self.hair = hair
        self.intensity = intensity
    }

    /// A value of the wrong type reads as missing, never as an error.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func id(_ key: CodingKeys) -> String? { (try? container.decodeIfPresent(String.self, forKey: key)) ?? nil }
        look = id(.look)
        lips = id(.lips)
        lipFinish = id(.lipFinish)
        eyes = id(.eyes)
        cheeks = id(.cheeks)
        hair = id(.hair)
        intensity = id(.intensity)
        let list = (try? container.decodeIfPresent([String?].self, forKey: .extras)) ?? nil
        extras = list?.compactMap { $0 } ?? []
    }
}

/// `200 { "makeup": {…}, "note": "…" }`: the picks and one line about them.
public struct AssistMakeupReply: Decodable, Equatable, Sendable {
    public var makeup: AssistMakeup
    /// In her language; screened on the device like every other line.
    public var note: String?

    public init(makeup: AssistMakeup, note: String? = nil) {
        self.makeup = makeup
        self.note = note
    }

    enum CodingKeys: String, CodingKey { case makeup, note }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        makeup = try container.decode(AssistMakeup.self, forKey: .makeup)
        note = (try? container.decodeIfPresent(String.self, forKey: .note)) ?? nil
    }
}

/// Why writing help didn't answer. Never shown as such: the app falls back
/// to Apple's on-device writer and its own hand-written lists.
public enum AssistError: Error, Equatable, Sendable {
    /// No session on this device yet. Writing help never makes an account:
    /// one comes with her first consented cloud job or a purchase.
    case noSession
    /// 400 `bad_request`.
    case badRequest
    /// 422 `content_blocked`: the server's policy turned the words (or its
    /// own answer) down. `category` is a `PolicyCategory` raw value, if sent.
    case contentBlocked(category: String?)
    /// 429 `rate_limited`.
    case rateLimited(retryAfter: TimeInterval?)
    /// 503 `assist_unavailable`: writing help is off, or its model is down.
    case unavailable
    /// 401 or 403: the session wasn't accepted.
    case unauthorized
    /// Any other answer.
    case server(status: Int, code: String?)
    /// A 200 the app can't read.
    case invalidResponse
}

/// Helpers both writers share: the app's language for the contract, the
/// screen every written line passes, and what the caption writer hears.
public enum Assist {
    /// The languages the app speaks, as the contract's `locale` spells them.
    public static let languages = ["en", "tr", "es", "pt-BR", "fr", "de", "it", "ru", "ja", "ko", "zh-Hans", "id"]

    /// The contract's code for a localization or locale identifier ("pt-BR",
    /// "pt_PT", "zh-Hans-CN", "en-GB"…): the app's own variant of that
    /// language, else English.
    public static func languageCode(for identifier: String) -> String {
        switch CaptionLanguage.parts(identifier).language {
        case "pt": return "pt-BR"
        case "zh": return "zh-Hans"
        // Indonesian's old code.
        case "in": return "id"
        case let code where languages.contains(code): return code
        default: return "en"
        }
    }

    /// Lines a writer returned that may be shown: unquoted, whitespace
    /// collapsed, at most `maxLength` characters, allowed by `ContentPolicy`
    /// for `operation`, each once, and at most `limit` of them.
    public static func screened(
        _ lines: [String], for operation: AIOperation, maxLength: Int = AssistRequest.maxTextLength, limit: Int = 3
    ) -> [String] {
        let edges = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"“”«»„"))
        var seen = Set<String>()
        var kept: [String] = []
        for line in lines where kept.count < limit {
            let text = PromptBuilder.normalized(line.trimmingCharacters(in: edges)).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, text.count <= maxLength,
                  ContentPolicy.evaluate(text, operation: operation).isAllowed,
                  seen.insert(text.lowercased()).inserted else { continue }
            kept.append(text)
        }
        return kept
    }

    /// What the caption writer hears about the picture: her Create prompt
    /// when it's a text-to-image creation (cut to fit), otherwise a plain
    /// line. Never an edit instruction: those can be about how she looks,
    /// and captions are about the vibe. English, never shown.
    public static func captionHint(prompt: String?, madeWithAI: Bool) -> String {
        let words = PromptBuilder.sanitize(prompt ?? "")
        if !words.isEmpty, ContentPolicy.evaluate(words, operation: .textToImage).isAllowed {
            return cut(words, to: AssistRequest.maxTextLength)
        }
        return madeWithAI ? "A picture made with AI, to share with friends" : "A photo to share with friends"
    }

    /// Whether the caption writer would hear her prompt, not just a plain
    /// line: what the share composer's note says before she asks.
    public static func sendsPrompt(_ prompt: String?, madeWithAI: Bool) -> Bool {
        captionHint(prompt: prompt, madeWithAI: madeWithAI) != captionHint(prompt: nil, madeWithAI: madeWithAI)
    }

    /// At most `limit` characters, ending on a whole word where there is one.
    static func cut(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let head = String(text.prefix(limit))
        guard let space = head.lastIndex(of: " "), space > head.startIndex else { return head }
        return String(head[..<space])
    }
}

extension MakeupStudio {
    /// Her picks from the writer's answer to "Describe your vibe": its look
    /// (when it's one of ours) with every part it named on top. Ids this
    /// version doesn't know are left out; a part it didn't name stays as the
    /// look has it ("As is" without a look); a list of extras replaces the
    /// look's (three at most); a lip finish needs a lip color that takes one;
    /// her hair color stays unless it named one. Nil when nothing in the
    /// answer is ours, so her current picks stay.
    public static func recipe(from answer: AssistMakeup, keepingHair hair: MakeupHair) -> MakeupRecipe? {
        let look = answer.look.flatMap { preset(id: $0) }
        let lips = answer.lips.flatMap(MakeupLips.init(rawValue:))
        let finish = answer.lipFinish.flatMap(MakeupLipFinish.init(rawValue:))
        let eyes = answer.eyes.flatMap(MakeupEyes.init(rawValue:))
        let cheeks = answer.cheeks.flatMap(MakeupCheeks.init(rawValue:))
        let extras = Set(answer.extras.compactMap(MakeupExtra.init(rawValue:)))
        let newHair = answer.hair.flatMap(MakeupHair.init(rawValue:))
        guard look != nil || lips != nil || eyes != nil || cheeks != nil || !extras.isEmpty || newHair != nil else { return nil }
        var recipe = look?.recipe ?? MakeupRecipe()
        if let lips { recipe.lips = lips }
        if let finish { recipe.lipFinish = finish }
        if let eyes { recipe.eyes = eyes }
        if let cheeks { recipe.cheeks = cheeks }
        if !extras.isEmpty { recipe.extras = extras }
        recipe.hair = newHair ?? hair
        if let intensity = answer.intensity.flatMap(MakeupIntensity.init(rawValue:)) { recipe.intensity = intensity }
        return recipe.isEmpty ? nil : recipe
    }
}

// MARK: - Request building

extension RequestFactory {
    static let assistPath = "functions/v1/assist"

    /// How long writing help may take: a slow answer falls back to the
    /// on-device writer, so it's short.
    public static let assistTimeout: TimeInterval = 10

    /// Writing help with her session's token. There's no anonymous variant:
    /// a request without a session is never sent. StoreKit's AppTransaction
    /// goes along when the device has one: callers without a verified
    /// install only share a small allowance on the server.
    public static func assist(_ body: AssistRequest, config: BackendConfiguration, accessToken: String,
                              appTransactionJWS: String? = nil) throws -> URLRequest {
        var request = try authorized(config: config, path: assistPath, method: "POST", query: [], accessToken: accessToken)
        attach(entitlementJWS: nil, appTransactionJWS: appTransactionJWS, to: &request)
        request.timeoutInterval = assistTimeout
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }
}

// MARK: - Response decoding

extension ResponseDecoder {
    private struct AssistSuggestions: Decodable {
        let suggestions: [String]
    }

    /// `200 { "suggestions": [string] }` for ideas, prompt upgrades and
    /// captions; throws `AssistError` otherwise. The lines aren't screened yet.
    public static func decodeAssistSuggestions(data: Data, statusCode: Int, retryAfter: String? = nil) throws -> [String] {
        guard (200..<300).contains(statusCode) else {
            throw assistError(from: data, statusCode: statusCode, retryAfter: retryAfter)
        }
        guard let body = try? JSONDecoder().decode(AssistSuggestions.self, from: data) else {
            throw AssistError.invalidResponse
        }
        return body.suggestions
    }

    /// `200 { "makeup": {…}, "note": "…" }`; throws `AssistError` otherwise.
    public static func decodeAssistMakeup(data: Data, statusCode: Int, retryAfter: String? = nil) throws -> AssistMakeupReply {
        guard (200..<300).contains(statusCode) else {
            throw assistError(from: data, statusCode: statusCode, retryAfter: retryAfter)
        }
        guard let reply = try? JSONDecoder().decode(AssistMakeupReply.self, from: data) else {
            throw AssistError.invalidResponse
        }
        return reply
    }

    /// `{ "error": { "code": …, "category": …, "retry_after": … } }` (or a
    /// bare `{ "error": "code" }`): the code first, then the status.
    public static func assistError(from data: Data, statusCode: Int, retryAfter: String? = nil) -> AssistError {
        let body = try? JSONDecoder().decode(AssistErrorBody.self, from: data)
        let wait = body?.retryAfter.map(TimeInterval.init) ?? retryAfter.flatMap(TimeInterval.init)
        switch body?.code {
        case "bad_request": return .badRequest
        case "content_blocked": return .contentBlocked(category: body?.category)
        case "rate_limited": return .rateLimited(retryAfter: wait)
        case "assist_unavailable": return .unavailable
        default: break
        }
        switch statusCode {
        case 400: return .badRequest
        case 401, 403: return .unauthorized
        case 422: return .contentBlocked(category: body?.category)
        case 429: return .rateLimited(retryAfter: wait)
        case 503: return .unavailable
        default: return .server(status: statusCode, code: body?.code)
        }
    }

    private struct AssistErrorBody: Decodable {
        var code: String?
        var category: String?
        var retryAfter: Int?

        enum CodingKeys: String, CodingKey { case error }
        enum ErrorKeys: String, CodingKey {
            case code, category
            case retryAfter = "retry_after"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let code = try? container.decode(String.self, forKey: .error) {
                self.code = code
                return
            }
            let error = try container.nestedContainer(keyedBy: ErrorKeys.self, forKey: .error)
            code = (try? error.decodeIfPresent(String.self, forKey: .code)) ?? nil
            category = (try? error.decodeIfPresent(String.self, forKey: .category)) ?? nil
            retryAfter = (try? error.decodeIfPresent(Int.self, forKey: .retryAfter)) ?? nil
        }
    }
}
