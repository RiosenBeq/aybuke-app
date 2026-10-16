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
    /// Explore's "Describe your vibe": up to three catalog items (`LookFinder`).
    case looks
    /// "Ideas from Aybik" in a poll's Ask friends sheet.
    case pollQuestions = "poll_questions"
    /// "Write it for me" for the share composer's text slots.
    case cardText = "card_text"
    /// Settings › Help › Ask Aybik: an answer about the app.
    case help

    /// The policy rules every line it writes must pass on the device before
    /// she sees it. Captions, makeup notes, look reasons, poll questions and
    /// card text go with someone's photo, so they get the stricter photo
    /// rules, as the on-device writer's do; help answers Create's.
    public var screeningOperation: AIOperation {
        switch self {
        case .inspire, .magic, .help: return .textToImage
        case .captions, .makeup, .looks, .pollQuestions, .cardText: return .magicEdit
        }
    }

    /// Whether the server needs her words for it.
    public var needsText: Bool {
        switch self {
        case .inspire, .pollQuestions, .cardText: return false
        case .magic, .captions, .makeup, .looks, .help: return true
        }
    }
}

/// Hints for the writer, each one optional.
public struct AssistContext: Codable, Equatable, Sendable {
    /// Create's style (`ImageStyle.id`), when she picked one.
    public var style: String?
    /// The share design she picked (`photo`, `beforeAfter`, `story`, `cover`, `strip`, `pick`).
    public var format: String?
    /// The Makeup Studio look she has on (`MakeupPreset.id`), or for card
    /// text the look or effect on her photo.
    public var look: String?
    /// Poll question ideas: what picture A and picture B are (a look, a
    /// style, an effect or the title of the creation), never the pictures.
    public var a: String?
    public var b: String?

    /// The server's limit on each value, in characters.
    public static let maxValueLength = 100

    public init(style: String? = nil, format: String? = nil, look: String? = nil, a: String? = nil, b: String? = nil) {
        func clean(_ value: String?) -> String? {
            let words = value.map { PromptBuilder.normalized($0).trimmingCharacters(in: .whitespaces) }
            guard let words, !words.isEmpty else { return nil }
            return Assist.cut(words, to: Self.maxValueLength)
        }
        self.style = clean(style)
        self.format = clean(format)
        self.look = clean(look)
        self.a = clean(a)
        self.b = clean(b)
    }

    var values: [String] { [style, format, look, a, b].compactMap { $0 } }
}

/// The body of `POST /functions/v1/assist`.
public struct AssistRequest: Encodable, Equatable, Sendable {
    /// The server's limit on `text`, in characters.
    public static let maxTextLength = 400

    public var task: AssistTask
    /// Her words: optional for `inspire`, `poll_questions` and `card_text`,
    /// needed by the others (`AssistTask.needsText`). Whitespace is
    /// collapsed, and text with nothing in it counts as none.
    public var text: String?
    /// The language the app shows (`Assist.languageCode(for:)`): the answer comes in it.
    public var locale: String
    /// Always sent, even empty.
    public var context: AssistContext
    /// `looks`: the kinds of item she can use (all five when nil).
    public var kinds: [LookFinder.Kind]?
    /// `card_text`: the slots to write for.
    public var slots: [ShareTextSlot]?

    public init(task: AssistTask, text: String? = nil, locale: String, context: AssistContext = AssistContext(),
                kinds: [LookFinder.Kind]? = nil, slots: [ShareTextSlot]? = nil) {
        self.task = task
        let words = text.map { PromptBuilder.normalized($0).trimmingCharacters(in: .whitespaces) }
        self.text = words?.isEmpty == false ? words : nil
        self.locale = locale
        self.context = context
        // Each once, in the contract's order, as the server reads them.
        self.kinds = kinds.map { list in LookFinder.Kind.allCases.filter(list.contains) }
        self.slots = slots.map { list in ShareTextSlot.allCases.filter(list.contains) }
    }

    enum CodingKeys: String, CodingKey { case task, text, locale, context, kinds, slots }

    /// `kinds` only for `looks` and `slots` only for `card_text`.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(task, forKey: .task)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encode(locale, forKey: .locale)
        try container.encode(context, forKey: .context)
        if task == .looks { try container.encodeIfPresent(kinds?.map(\.rawValue), forKey: .kinds) }
        if task == .cardText { try container.encodeIfPresent(slots?.map(\.rawValue), forKey: .slots) }
    }

    /// Mirrors the server's `bad_request` checks, so the app never asks in
    /// vain: text where the task needs it, at most `maxTextLength`
    /// characters, a language the app speaks, context values of at most 100
    /// characters, kinds that aren't empty, and one to four slots for card text.
    public func validate() throws {
        if task.needsText && text == nil { throw AssistError.badRequest }
        if let text, text.count > Self.maxTextLength { throw AssistError.badRequest }
        guard Assist.languages.contains(locale) else { throw AssistError.badRequest }
        if context.values.contains(where: { $0.count > AssistContext.maxValueLength }) { throw AssistError.badRequest }
        if task == .looks, let kinds, kinds.isEmpty { throw AssistError.badRequest }
        if task == .cardText, slots?.isEmpty ?? true { throw AssistError.badRequest }
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

/// `200 { "slots": { "<slot>": [string] } }`: options per share text slot,
/// not screened yet. Slots this version doesn't know are left out.
public struct AssistCardReply: Decodable, Equatable, Sendable {
    public var slots: [ShareTextSlot: [String]]

    public init(slots: [ShareTextSlot: [String]]) {
        self.slots = slots
    }

    enum CodingKeys: String, CodingKey { case slots }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode([String: [String?]?].self, forKey: .slots)
        var slots: [ShareTextSlot: [String]] = [:]
        for (key, lines) in raw {
            guard let slot = ShareTextSlot(rawValue: key) else { continue }
            slots[slot] = (lines ?? []).compactMap { $0 }
        }
        self.slots = slots
    }
}

/// `200 { "answer": "…", "support": true }`: Ask Aybik's answer, not screened yet.
public struct AssistHelpReply: Decodable, Equatable, Sendable {
    public var answer: String
    /// The answer points her to support (or Feel good): the screen offers it.
    public var support: Bool

    public init(answer: String, support: Bool) {
        self.answer = answer
        self.support = support
    }

    enum CodingKeys: String, CodingKey { case answer, support }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        answer = try container.decode(String.self, forKey: .answer)
        // When in doubt, offer support.
        support = (try? container.decodeIfPresent(Bool.self, forKey: .support)) ?? true
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

    /// Lines people read next to her photo (a look's reason, a poll question,
    /// card text), tidied as the server tidies them: NFC, control characters
    /// as spaces, hidden characters removed, whitespace collapsed, no list
    /// markers or wrapping quotes, emoji as written. Each passes the photo
    /// rules as shown and as a prompt would be cleaned up, holds no link,
    /// e-mail address or @handle, fits `maxLength`, comes once, and at most
    /// `limit` are kept. (The server also drops lines about bodies, faces,
    /// skin, weight or rating looks, in every language.)
    public static func screenedShown(_ lines: [String], maxLength: Int, limit: Int) -> [String] {
        var seen = Set<String>()
        var kept: [String] = []
        for line in lines where kept.count < limit {
            let text = tidyShown(line)
            guard !text.isEmpty, text.count <= maxLength, !hasLink(text),
                  [text, PollQuestion.serverSanitized(text)].allSatisfy({ ContentPolicy.evaluate($0, operation: .magicEdit).isAllowed }),
                  seen.insert(text.lowercased()).inserted else { continue }
            kept.append(text)
        }
        return kept
    }

    /// Poll question ideas she may tap: shown lines that also pass the
    /// poll's own question check (`PollQuestion.check`), as friends will read them.
    public static func screenedQuestions(_ lines: [String], limit: Int = 4) -> [String] {
        screenedShown(lines, maxLength: PollQuestion.maxLength, limit: .max).compactMap { line -> String? in
            guard case .ok(let question?) = PollQuestion.check(line) else { return nil }
            return question
        }
        .prefix(limit)
        .map { $0 }
    }

    /// Card text options for `slot`: shown lines within the slot's length.
    public static func screenedCardLines(_ lines: [String], for slot: ShareTextSlot, limit: Int = 4) -> [String] {
        screenedShown(lines.map(slot.clean), maxLength: slot.maxLength, limit: limit)
    }

    /// The longest answer Ask Aybik shows, in characters.
    public static let maxAnswerLength = 600

    /// Ask Aybik's answer as it may be shown, or nil: plain text in short
    /// paragraphs (Markdown marks removed), at most `maxAnswerLength`
    /// characters, allowed by Create's rules, naming no AI company, with no
    /// e-mail address and no web address but the support page's and the
    /// helpline finder's (the server's own checks, again on the device).
    public static func screenedAnswer(_ answer: String) -> String? {
        let paragraphs = answer.precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { line -> String in
                var text = PromptBuilder.normalized(line).trimmingCharacters(in: .whitespaces)
                for mark in ["**", "__", "`"] { text = text.replacingOccurrences(of: mark, with: "") }
                while text.hasPrefix("#") || text.hasPrefix(">") { text = String(text.dropFirst()) }
                return text.trimmingCharacters(in: .whitespaces)
            }
        var text = paragraphs.joined(separator: "\n")
        while text.contains("\n\n\n") { text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= maxAnswerLength,
              ContentPolicy.evaluate(text.replacingOccurrences(of: "\n", with: " "), operation: .textToImage).isAllowed,
              !matches(companyPattern, in: text), !matches(emailPattern, in: text) else { return nil }
        for host in webHosts(in: text) where !allowedAnswerHosts.contains(host) { return nil }
        return text
    }

    // MARK: Shown text

    /// Invisible characters that can hide or reorder text (as polls' `PollQuestion.cleaned`).
    static func tidyShown(_ line: String) -> String {
        var text = PollQuestion.cleaned(line)
        let markers = try? NSRegularExpression(pattern: #"^(?:\d{1,2}[.)]|[-•*])\s+"#)
        if let markers {
            text = markers.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        let quotes = CharacterSet(charactersIn: "\"“”«»„")
        return text.trimmingCharacters(in: quotes).trimmingCharacters(in: .whitespaces)
    }

    private static let linkPattern =
        #"(?:https?://|www\.)\S|[\p{L}\p{N}._%+-]+@[\p{L}\p{N}-]+\.\p{L}|(?:^|\s)@[\p{L}\p{N}_]|\b[a-z0-9-]+\.(?:com|net|org|io|app|co|me|ly|gg|tv|link)\b"#
    private static let companyPattern = #"\b(?:claude|anthropic|x\.?ai|grok|supabase|openai|chatgpt|gpt-?\d*|gemini|revenuecat|admob)\b"#
    private static let emailPattern = #"[\p{L}\p{N}._%+-]+@[\p{L}\p{N}-]+\.\p{L}"#
    private static let allowedAnswerHosts: Set<String> = ["aybuke.org", "www.aybuke.org", "findahelpline.com", "www.findahelpline.com"]

    /// A link, an e-mail address, an @handle or a bare web address.
    public static func hasLink(_ text: String) -> Bool {
        matches(linkPattern, in: text)
    }

    private static func matches(_ pattern: String, in text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return true }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// The hosts of the web addresses in `text`, lowercased.
    private static func webHosts(in text: String) -> [String] {
        let pattern = #"\b(?:https?://)?((?:[a-z0-9-]+\.)+[a-z]{2,})(?:/[^\s)]*)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range(at: 1), in: text).map { text[$0].lowercased() }
        }
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

    /// `200 { "picks": [{ "kind", "id", "reason" }] }` for the look finder; a
    /// pick of a kind this version doesn't know is left out. Throws
    /// `AssistError` otherwise. Not screened yet (`LookFinder.usable`).
    public static func decodeAssistPicks(data: Data, statusCode: Int, retryAfter: String? = nil) throws -> [LookFinder.Pick] {
        try decodeAssist(LookFinder.Reply.self, data: data, statusCode: statusCode, retryAfter: retryAfter).picks
    }

    /// `200 { "slots": { "<slot>": [string] } }` for card text.
    public static func decodeAssistCards(data: Data, statusCode: Int, retryAfter: String? = nil) throws -> AssistCardReply {
        try decodeAssist(AssistCardReply.self, data: data, statusCode: statusCode, retryAfter: retryAfter)
    }

    /// `200 { "answer": "…", "support": bool }` for Ask Aybik.
    public static func decodeAssistHelp(data: Data, statusCode: Int, retryAfter: String? = nil) throws -> AssistHelpReply {
        try decodeAssist(AssistHelpReply.self, data: data, statusCode: statusCode, retryAfter: retryAfter)
    }

    private static func decodeAssist<Reply: Decodable>(_ type: Reply.Type, data: Data, statusCode: Int, retryAfter: String?) throws -> Reply {
        guard (200..<300).contains(statusCode) else {
            throw assistError(from: data, statusCode: statusCode, retryAfter: retryAfter)
        }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { throw AssistError.invalidResponse }
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
