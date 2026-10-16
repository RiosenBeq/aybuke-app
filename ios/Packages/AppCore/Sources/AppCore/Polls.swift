import Foundation

// "Which vibe?" polls with friends: she shares two of her own pictures (A
// and B) and an optional question as a private link, friends vote on
// aybuke.org/p/<id> without the app, and she sees the counts here. The
// contract is backend/README.md, "Polls" (functions/polls/handler.ts); this
// file is the app's side of it: the wire formats, her question as the server
// checks it, the picture limits, the counts as percentages, the time left and
// what the device keeps (and for how long).

// MARK: - Wire formats

public enum PollSide: String, Codable, CaseIterable, Sendable {
    case a, b
}

/// Votes per side, as the server counts them.
public struct PollVotes: Codable, Equatable, Sendable {
    public var a: Int
    public var b: Int

    public init(a: Int = 0, b: Int = 0) {
        self.a = a
        self.b = b
    }

    public var total: Int { a + b }

    public subscript(side: PollSide) -> Int {
        side == .a ? a : b
    }

    /// Whole percentages that add up to 100 (largest remainder, so 1 of 3 is
    /// 33 and 67, and a tie stays a tie); nil before the first vote.
    public var percentages: (a: Int, b: Int)? {
        guard a >= 0, b >= 0, total > 0 else { return nil }
        let exactA = Double(a) * 100 / Double(total)
        var shareA = Int(exactA.rounded(.down))
        var shareB = Int((Double(b) * 100 / Double(total)).rounded(.down))
        let left = 100 - shareA - shareB
        if left > 0 {
            // Two sides leave at most one point: it goes to the larger remainder
            // (the larger count when they're equal, A for a tie).
            let remainderA = exactA - Double(shareA)
            let remainderB = Double(b) * 100 / Double(total) - Double(shareB)
            if remainderA > remainderB || (remainderA == remainderB && a >= b) {
                shareA += left
            } else {
                shareB += left
            }
        }
        return (shareA, shareB)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        a = max(0, (try? container.decodeIfPresent(Int.self, forKey: .a)) ?? 0)
        b = max(0, (try? container.decodeIfPresent(Int.self, forKey: .b)) ?? 0)
    }

    enum CodingKeys: String, CodingKey { case a, b }
}

/// Which pictures were made or changed with generative AI (the page says
/// "Edited with AI" under them).
public struct PollAILabels: Codable, Equatable, Sendable {
    public var a: Bool
    public var b: Bool

    public init(a: Bool = false, b: Bool = false) {
        self.a = a
        self.b = b
    }

    public init(sides: [PollSide]) {
        self.init(a: sides.contains(.a), b: sides.contains(.b))
    }

    public var sides: [PollSide] {
        PollSide.allCases.filter { self[$0] }
    }

    public subscript(side: PollSide) -> Bool {
        side == .a ? a : b
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        a = (try? container.decodeIfPresent(Bool.self, forKey: .a)) == true
        b = (try? container.decodeIfPresent(Bool.self, forKey: .b)) == true
    }

    enum CodingKeys: String, CodingKey { case a, b }
}

public enum PollStatus: String, Codable, Sendable {
    case live
    /// Closed to everyone after a report, until its 24 hours end.
    case takenDown = "taken_down"
}

/// `POST /functions/v1/polls`.
public struct PollCreateRequest: Encodable, Equatable, Sendable {
    /// Already cleaned (`PollQuestion.check`); nil for none.
    public var question: String?
    /// A, then B: `data:image/jpeg;base64,…`.
    public var images: [String]
    /// One of the app's languages, as the contract spells them.
    public var locale: String
    /// The pictures made or changed with AI (their Provenance), sorted.
    public var aiSides: [PollSide]

    public init(question: String?, pictureA: Data, pictureB: Data, locale: String, aiSides: [PollSide]) {
        self.question = question
        images = [pictureA, pictureB].map { GenerationRequest.dataURI($0, mimeType: "image/jpeg") }
        self.locale = locale
        self.aiSides = PollSide.allCases.filter(aiSides.contains)
    }

    enum CodingKeys: String, CodingKey {
        case question, images, locale
        case aiSides = "ai_sides"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(question, forKey: .question)
        try container.encode(images, forKey: .images)
        try container.encode(locale, forKey: .locale)
        try container.encode(aiSides, forKey: .aiSides)
    }
}

/// `201` after a poll was made.
public struct PollCreated: Decodable, Equatable, Sendable {
    public var pollID: String
    public var shareURL: URL
    public var expiresAt: Date
    /// Polls she may still make today.
    public var remainingToday: Int?

    public init(pollID: String, shareURL: URL, expiresAt: Date, remainingToday: Int?) {
        self.pollID = pollID
        self.shareURL = shareURL
        self.expiresAt = expiresAt
        self.remainingToday = remainingToday
    }

    enum CodingKeys: String, CodingKey {
        case pollID = "poll_id"
        case shareURL = "share_url"
        case expiresAt = "expires_at"
        case remainingToday = "remaining_today"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pollID = try container.decode(String.self, forKey: .pollID)
        guard PollID.isValid(pollID) else {
            throw DecodingError.dataCorruptedError(forKey: .pollID, in: container, debugDescription: "not a poll id")
        }
        shareURL = try PollID.shareURL(container.decode(String.self, forKey: .shareURL), id: pollID)
        expiresAt = try ServerDate.decode(container, .expiresAt)
        remainingToday = try? container.decodeIfPresent(Int.self, forKey: .remainingToday)
    }
}

/// One of her polls in `GET /functions/v1/polls/mine`.
public struct PollSummary: Decodable, Equatable, Sendable {
    public var pollID: String
    public var shareURL: URL
    public var question: String?
    public var createdAt: Date?
    public var expiresAt: Date
    public var status: PollStatus
    public var ai: PollAILabels
    public var votes: PollVotes

    public init(pollID: String, shareURL: URL, question: String?, createdAt: Date?, expiresAt: Date,
                status: PollStatus, ai: PollAILabels, votes: PollVotes) {
        self.pollID = pollID
        self.shareURL = shareURL
        self.question = question
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.status = status
        self.ai = ai
        self.votes = votes
    }

    enum CodingKeys: String, CodingKey {
        case question, status, ai, votes
        case pollID = "poll_id"
        case shareURL = "share_url"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pollID = try container.decode(String.self, forKey: .pollID)
        guard PollID.isValid(pollID) else {
            throw DecodingError.dataCorruptedError(forKey: .pollID, in: container, debugDescription: "not a poll id")
        }
        shareURL = try PollID.shareURL((try? container.decodeIfPresent(String.self, forKey: .shareURL)) ?? nil, id: pollID)
        let question = (try? container.decodeIfPresent(String.self, forKey: .question)) ?? nil
        self.question = question.flatMap { $0.isEmpty ? nil : $0 }
        createdAt = (try? container.decodeIfPresent(String.self, forKey: .createdAt))?.flatMap(ServerDate.parse)
        expiresAt = try ServerDate.decode(container, .expiresAt)
        // A state this version doesn't know is shown as live: the server
        // closes the link itself.
        status = (try? container.decodeIfPresent(PollStatus.self, forKey: .status)) ?? .live
        ai = (try? container.decodeIfPresent(PollAILabels.self, forKey: .ai)) ?? PollAILabels()
        votes = (try? container.decodeIfPresent(PollVotes.self, forKey: .votes)) ?? PollVotes()
    }
}

/// `GET /functions/v1/polls/mine`: her polls that haven't ended.
public struct PollList: Decodable, Equatable, Sendable {
    public var polls: [PollSummary]
    public var remainingToday: Int?
    public var dailyCap: Int?

    public init(polls: [PollSummary], remainingToday: Int? = nil, dailyCap: Int? = nil) {
        self.polls = polls
        self.remainingToday = remainingToday
        self.dailyCap = dailyCap
    }

    enum CodingKeys: String, CodingKey {
        case polls
        case remainingToday = "remaining_today"
        case dailyCap = "daily_cap"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // One poll this version can't read doesn't hide the others.
        polls = ((try? container.decode([Lenient<PollSummary>].self, forKey: .polls)) ?? []).compactMap(\.value)
        remainingToday = try? container.decodeIfPresent(Int.self, forKey: .remainingToday)
        dailyCap = try? container.decodeIfPresent(Int.self, forKey: .dailyCap)
    }
}

private struct Lenient<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

/// Poll ids and their links.
public enum PollID {
    /// What the server makes: 16 of A–Z a–z 0–9 - _ (POLL_ID_PATTERN).
    public static func isValid(_ id: String) -> Bool {
        id.utf8.count == 16 && id.unicodeScalars.allSatisfy { scalar in
            switch scalar {
            case "A"..."Z", "a"..."z", "0"..."9", "-", "_": return true
            default: return false
            }
        }
    }

    /// Where friends vote.
    public static let shareBase = "https://aybuke.org/p/"

    /// The server's link when it's the poll page on aybuke.org, else the
    /// page's own address for this id (a link elsewhere is never shared).
    static func shareURL(_ value: String?, id: String) throws -> URL {
        let expected = shareBase + id
        if let value, value == expected, let url = URL(string: value) { return url }
        guard let url = URL(string: expected) else { throw PollError.invalidResponse }
        return url
    }
}

extension ServerDate {
    static func decode<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, _ key: Key) throws -> Date {
        guard let date = try parse(container.decode(String.self, forKey: key)) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "not a date")
        }
        return date
    }
}

// MARK: - Errors

/// Every refusal the contract documents, for short, kind messages.
public enum PollError: Error, Equatable, Sendable {
    /// No session on this device yet (her list is empty until she makes one).
    case noSession
    /// 401: the session wasn't accepted.
    case unauthorized
    /// 403 `install_blocked`: the team stopped polls (and cloud AI) for her.
    case installBlocked
    /// 413 `too_large`.
    case tooLarge(side: PollSide?)
    /// 422 `image_invalid`.
    case imageInvalid(side: PollSide?)
    /// 422 `content_blocked`: the question, with a `PolicyCategory` raw value.
    case contentBlocked(category: String?)
    /// 422 `image_blocked`: the safety check wouldn't let a picture be shared.
    case imageBlocked(sides: [PollSide])
    /// 429 `rate_limited`: today's polls (or this hour's) are used.
    case rateLimited(retryAfter: TimeInterval?)
    /// 429 `cooldown`: cloud AI rests for her until `until`.
    case cooldown(until: Date?, retryAfter: TimeInterval?)
    /// 503 `safety_unavailable`: the check couldn't run (the attempt was given back).
    case safetyUnavailable(retryAfter: TimeInterval?)
    /// 404 `not_found`: ended, deleted or removed (one answer for all).
    case notFound
    /// 400 `bad_request`.
    case badRequest
    case server(status: Int, code: String?)
    /// A 2xx the app can't read.
    case invalidResponse
}

extension RequestFactory {
    static let pollsPath = "functions/v1/polls"

    /// Making a poll: the server decodes, re-encodes and has both pictures
    /// checked for safety, so it takes a while.
    public static let pollCreateTimeout: TimeInterval = 60

    /// A new poll with her session. StoreKit's AppTransaction goes along
    /// when the device has one (the daily limit belongs to the download too).
    public static func createPoll(_ body: PollCreateRequest, config: BackendConfiguration, accessToken: String,
                                  appTransactionJWS: String? = nil) throws -> URLRequest {
        var request = try authorized(config: config, path: pollsPath, method: "POST", query: [], accessToken: accessToken)
        attach(entitlementJWS: nil, appTransactionJWS: appTransactionJWS, to: &request)
        request.timeoutInterval = pollCreateTimeout
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    /// Her polls that haven't ended, with their counts.
    public static func myPolls(config: BackendConfiguration, accessToken: String, appTransactionJWS: String? = nil) throws -> URLRequest {
        var request = try authorized(config: config, path: pollsPath + "/mine", method: "GET", query: [], accessToken: accessToken)
        attach(entitlementJWS: nil, appTransactionJWS: appTransactionJWS, to: &request)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    /// Deletes one of her polls now: pictures, question and votes.
    public static func deletePoll(id: String, config: BackendConfiguration, accessToken: String) throws -> URLRequest {
        var request = try authorized(config: config, path: pollsPath, method: "DELETE",
                                     query: [URLQueryItem(name: "id", value: id)], accessToken: accessToken)
        request.timeoutInterval = 20
        return request
    }
}

extension ResponseDecoder {
    public static func decodePollCreated(data: Data, statusCode: Int, retryAfter: String? = nil) throws -> PollCreated {
        guard (200..<300).contains(statusCode) else { throw pollError(from: data, statusCode: statusCode, retryAfter: retryAfter) }
        guard let created = try? JSONDecoder().decode(PollCreated.self, from: data) else { throw PollError.invalidResponse }
        return created
    }

    public static func decodePollList(data: Data, statusCode: Int, retryAfter: String? = nil) throws -> PollList {
        guard (200..<300).contains(statusCode) else { throw pollError(from: data, statusCode: statusCode, retryAfter: retryAfter) }
        guard let list = try? JSONDecoder().decode(PollList.self, from: data) else { throw PollError.invalidResponse }
        return list
    }

    /// `200 { "deleted": true }`; a 404 means it's gone already.
    public static func decodePollDeleted(data: Data, statusCode: Int, retryAfter: String? = nil) throws {
        guard (200..<300).contains(statusCode) else { throw pollError(from: data, statusCode: statusCode, retryAfter: retryAfter) }
        struct Body: Decodable { let deleted: Bool }
        guard (try? JSONDecoder().decode(Body.self, from: data))?.deleted == true else { throw PollError.invalidResponse }
    }

    /// `{ "error": { "code", "message", "side" | "sides" | "category" | "until", "retry_after" } }`:
    /// the code first, then the status.
    public static func pollError(from data: Data, statusCode: Int, retryAfter: String? = nil) -> PollError {
        let body = (try? JSONDecoder().decode(PollErrorEnvelope.self, from: data))?.error
        let wait = body?.retryAfter.map(TimeInterval.init) ?? retryAfter.flatMap(TimeInterval.init)
        switch body?.code {
        case "install_blocked": return .installBlocked
        case "too_large": return .tooLarge(side: body?.side)
        case "image_invalid": return .imageInvalid(side: body?.side)
        case "content_blocked": return .contentBlocked(category: body?.category)
        case "image_blocked": return .imageBlocked(sides: body?.sides ?? [])
        case "rate_limited": return .rateLimited(retryAfter: wait)
        case "cooldown": return .cooldown(until: body?.until.flatMap(ServerDate.parse), retryAfter: wait)
        case "safety_unavailable": return .safetyUnavailable(retryAfter: wait)
        case "not_found": return .notFound
        case "bad_request": return .badRequest
        case "unauthorized": return .unauthorized
        default: break
        }
        switch statusCode {
        case 400: return .badRequest
        case 401: return .unauthorized
        case 404: return .notFound
        case 413: return .tooLarge(side: nil)
        case 429: return .rateLimited(retryAfter: wait)
        case 503: return .safetyUnavailable(retryAfter: wait)
        default: return .server(status: statusCode, code: body?.code)
        }
    }

    private struct PollErrorEnvelope: Decodable {
        struct Body: Decodable {
            var code: String?
            var side: PollSide?
            var sides: [PollSide]?
            var category: String?
            var until: String?
            var retryAfter: Int?

            enum CodingKeys: String, CodingKey {
                case code, side, sides, category, until
                case retryAfter = "retry_after"
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                code = (try? container.decodeIfPresent(String.self, forKey: .code)) ?? nil
                side = (try? container.decodeIfPresent(PollSide.self, forKey: .side)) ?? nil
                sides = (try? container.decodeIfPresent([String].self, forKey: .sides))?.compactMap(PollSide.init(rawValue:))
                category = (try? container.decodeIfPresent(String.self, forKey: .category)) ?? nil
                until = (try? container.decodeIfPresent(String.self, forKey: .until)) ?? nil
                retryAfter = (try? container.decodeIfPresent(Int.self, forKey: .retryAfter)) ?? nil
            }
        }

        let error: Body
    }
}

// MARK: - Her question

/// The optional question above her pictures: at most 80 characters, and
/// allowed by the prompt policy with an edit's rules (no rating or reshaping
/// looks), checked the way the server checks it.
public enum PollQuestion {
    /// Characters, as grapheme clusters (emoji stay whole): MAX_QUESTION.
    public static let maxLength = 80
    /// The server's ceiling on code points behind those characters.
    public static let maxCodePoints = 800

    /// Ready-made questions, shown in her language (`L10n.core`); every one
    /// passes `check` in all the app's languages (PollsTests).
    public static let presets = [
        preset("Which vibe?"),
        preset("Which one for Friday?"),
        preset("Which edit should I post?"),
        preset("Which colour?"),
    ]

    /// Marks a preset for scripts/export-core-strings.py.
    static func preset(_ english: String) -> String { english }

    public enum Check: Equatable, Sendable {
        /// What to send: cleaned, nil when she wrote nothing.
        case ok(String?)
        case tooLong
        case blocked(reason: String, category: PolicyCategory)
    }

    public static func check(_ raw: String) -> Check {
        let question = cleaned(raw)
        if question.count > maxLength || question.unicodeScalars.count > maxCodePoints { return .tooLong }
        // As sent, as friends will read it, and as a prompt would be cleaned
        // up: the server's screenQuestion.
        for text in [raw, question, serverSanitized(raw)] where !text.isEmpty {
            if case .blocked(let reason, let category) = ContentPolicy.evaluate(text, operation: .magicEdit) {
                return .blocked(reason: reason, category: category)
            }
        }
        return .ok(question.isEmpty ? nil : question)
    }

    /// Her question as friends will read it (the server's cleanQuestion):
    /// NFC, control characters as spaces, invisible direction and zero-width
    /// characters removed, whitespace collapsed. Emoji keep their joiners.
    public static func cleaned(_ raw: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in raw.precomposedStringWithCanonicalMapping.unicodeScalars {
            if scalar.properties.generalCategory == .control {
                scalars.append(" ")
            } else if !isHidden(scalar) {
                scalars.append(scalar)
            }
        }
        return collapsingWhitespace(String(scalars))
    }

    /// At most `maxLength` characters, for the text field as she types.
    public static func clipped(_ text: String) -> String {
        guard text.count > maxLength else { return text }
        return String(text.prefix(maxLength))
    }

    /// What the server's prompt clean-up makes of it (sanitizePrompt): NFKC,
    /// controls as spaces, format characters and variation selectors removed.
    static func serverSanitized(_ raw: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in raw.precomposedStringWithCompatibilityMapping.unicodeScalars {
            let category = scalar.properties.generalCategory
            if category == .control || scalar.value == 0x2028 || scalar.value == 0x2029 {
                scalars.append(" ")
            } else if category == .format || (0xFE00...0xFE0F).contains(scalar.value) || (0xE0100...0xE01EF).contains(scalar.value) {
                continue
            } else {
                scalars.append(scalar)
            }
        }
        return collapsingWhitespace(String(scalars))
    }

    /// The server's HIDDEN set: soft hyphen, zero-width space, direction
    /// marks and overrides, word joiners and invisible operators, isolates,
    /// the byte-order mark, interlinear annotations and tag characters.
    static func isHidden(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x00AD, 0x200B, 0x200E, 0x200F, 0x202A...0x202E, 0x2060...0x2064, 0x2066...0x2069, 0xFEFF, 0xFFF9...0xFFFB,
             0xE0000...0xE007F:
            return true
        default:
            return false
        }
    }

    private static func collapsingWhitespace(_ text: String) -> String {
        var result = String.UnicodeScalarView()
        var pendingSpace = false
        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace {
                pendingSpace = !result.isEmpty
            } else {
                if pendingSpace { result.append(" ") }
                pendingSpace = false
                result.append(scalar)
            }
        }
        return String(result)
    }
}

/// Which two pictures can be a poll. Never her photo against its AI edit:
/// friends would be voting on her, not on a vibe. A picture edited with AI
/// (Magic Edit, a look, makeup, Erase…) beside one with no AI at all is most
/// likely just that, so it's refused; two edits, two creations, a creation
/// and a photo, or two plain photos are fine. (The share composer's "Which
/// vibe?" only ever pairs two variations of one creation.)
public enum PollPair {
    public static func allows(_ a: Provenance, _ b: Provenance) -> Bool {
        !(editsAPhoto(a) && !b.carriesAIProvenance) && !(editsAPhoto(b) && !a.carriesAIProvenance)
    }

    /// Generative AI changed a photo (rather than making a picture from words).
    static func editsAPhoto(_ provenance: Provenance) -> Bool {
        provenance.carriesAIProvenance && !provenance.isFullyGenerated
    }
}

// MARK: - Pictures

/// What the app uploads: upright, at most 1080 px on the long side, sRGB,
/// a JPEG with no metadata, well under the server's limits (1.5 MB, 4,096 px
/// a side, 6 MP); the server shrinks it to 720 px and re-encodes it anyway.
public enum PollPicture {
    public static let maxLongEdge = 1080
    /// The server's MAX_PICTURE_BYTES is 1,572,864.
    public static let serverMaxBytes = 1_572_864
    public static let maxBytes = 1_400_000
    public static let serverMaxSide = 4096
    public static let serverMaxPixels = 6_000_000
    /// Tried in order until the file fits.
    public static let qualities: [Double] = [0.85, 0.75, 0.65, 0.5]
    /// The small copies the device keeps for "Your polls".
    public static let thumbnailLongEdge = 360

    /// The upload's size for a picture of `size`.
    public static func targetSize(for size: PixelSize) -> PixelSize {
        ImageSizing.fit(size, maxLongEdge: maxLongEdge)
    }

    public static func thumbnailSize(for size: PixelSize) -> PixelSize {
        ImageSizing.fit(size, maxLongEdge: thumbnailLongEdge)
    }

    /// Within everything the server accepts.
    public static func isAccepted(byteCount: Int, size: PixelSize) -> Bool {
        byteCount <= serverMaxBytes && size.width <= serverMaxSide && size.height <= serverMaxSide
            && size.width * size.height <= serverMaxPixels && size.width > 0 && size.height > 0
    }
}

/// Removes what a JPEG says besides its pixels.
public enum JPEGMetadata {
    /// The JPEG without EXIF or XMP (APP1), IPTC (APP13), other application
    /// segments or comments. JFIF (APP0), the colour profile (APP2) and
    /// Adobe's colour transform (APP14) stay, and so does every byte from the
    /// start of the scan. Nil if it isn't a JPEG that can be walked.
    public static func stripped(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count > 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return nil }
        var output: [UInt8] = [0xFF, 0xD8]
        output.reserveCapacity(bytes.count)
        var index = 2
        while index + 1 < bytes.count {
            guard bytes[index] == 0xFF else { return nil }
            // Fill bytes before a marker.
            var markerIndex = index + 1
            while markerIndex < bytes.count, bytes[markerIndex] == 0xFF { markerIndex += 1 }
            guard markerIndex < bytes.count else { return nil }
            let marker = bytes[markerIndex]
            switch marker {
            case 0xDA:
                // Start of scan: the rest is image data.
                output.append(contentsOf: [0xFF, 0xDA])
                output.append(contentsOf: bytes[(markerIndex + 1)...])
                return Data(output)
            case 0xD9:
                return nil // an image without a scan
            case 0x01, 0xD0...0xD7:
                output.append(contentsOf: [0xFF, marker])
                index = markerIndex + 1
                continue
            default:
                break
            }
            guard markerIndex + 2 < bytes.count else { return nil }
            let length = Int(bytes[markerIndex + 1]) << 8 | Int(bytes[markerIndex + 2])
            let end = markerIndex + 1 + length
            guard length >= 2, end <= bytes.count else { return nil }
            if keeps(marker) {
                output.append(0xFF)
                output.append(contentsOf: bytes[markerIndex..<end])
            }
            index = end
        }
        return nil
    }

    /// The markers before the scan, for checks.
    public static func markers(in data: Data) -> [UInt8] {
        let bytes = [UInt8](data)
        var markers: [UInt8] = []
        var index = 2
        while index + 3 < bytes.count, bytes[index] == 0xFF {
            let marker = bytes[index + 1]
            markers.append(marker)
            if marker == 0xDA || marker == 0xD9 { break }
            if marker == 0x01 || (0xD0...0xD7).contains(marker) {
                index += 2
                continue
            }
            index += 2 + (Int(bytes[index + 2]) << 8 | Int(bytes[index + 3]))
        }
        return markers
    }

    private static func keeps(_ marker: UInt8) -> Bool {
        switch marker {
        case 0xE0, 0xE2, 0xEE: return true // JFIF, ICC profile, Adobe
        case 0xE1, 0xE3...0xED, 0xEF, 0xFE: return false // EXIF/XMP, IPTC and the like, comments
        default: return true // tables, frame headers, restart interval
        }
    }
}

// MARK: - On the device

/// How long until a poll ends, for "12 h left".
public enum PollTimeLeft: Equatable, Sendable {
    case hours(Int)
    case minutes(Int)
    case ended

    public init(expiresAt: Date, now: Date) {
        let left = expiresAt.timeIntervalSince(now)
        let minutes = Int((left / 60).rounded(.up))
        if left <= 0 {
            self = .ended
        } else if minutes < 60 {
            self = .minutes(max(1, minutes))
        } else {
            self = .hours(max(1, Int((left / 3600).rounded())))
        }
    }
}

/// One of her polls as this device keeps it: the id, the link, her question,
/// the last counts it saw and its own small thumbnails (kept by the app).
/// Never synced; deleted a day after the poll ends, or by Delete my data.
public struct PollRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var shareURL: URL
    public var question: String?
    public var createdAt: Date
    public var expiresAt: Date
    public var status: PollStatus
    public var votes: PollVotes
    public var ai: PollAILabels
    /// When the counts were last read from the server.
    public var updatedAt: Date?

    public init(id: String, shareURL: URL, question: String?, createdAt: Date, expiresAt: Date,
                status: PollStatus = .live, votes: PollVotes = PollVotes(), ai: PollAILabels = PollAILabels(), updatedAt: Date? = nil) {
        self.id = id
        self.shareURL = shareURL
        self.question = question
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.status = status
        self.votes = votes
        self.ai = ai
        self.updatedAt = updatedAt
    }

    public func hasEnded(at now: Date) -> Bool { expiresAt <= now }
}

/// Her polls on this device, newest first.
public struct PollShelf: Codable, Equatable, Sendable {
    public private(set) var records: [PollRecord]

    /// A poll lives 24 hours on the server.
    public static let lifetime: TimeInterval = 24 * 3600
    /// The last counts stay this long after it ended, then everything goes.
    public static let keepsEnded: TimeInterval = 24 * 3600
    /// A poll missing from her list this close to its end counts as ended
    /// (the device's clock may be a little behind the server's).
    public static let clockSlack: TimeInterval = 5 * 60

    public init(records: [PollRecord] = []) {
        self.records = records.sorted { $0.createdAt > $1.createdAt }
    }

    public var isEmpty: Bool { records.isEmpty }

    public func record(_ id: String) -> PollRecord? {
        records.first { $0.id == id }
    }

    /// Polls friends can still vote on.
    public func live(at now: Date) -> [PollRecord] {
        records.filter { !$0.hasEnded(at: now) && $0.status == .live }
    }

    /// A poll she just made.
    public mutating func add(_ created: PollCreated, question: String?, ai: PollAILabels, now: Date) {
        records.removeAll { $0.id == created.pollID }
        let record = PollRecord(id: created.pollID, shareURL: created.shareURL, question: question,
                                createdAt: now, expiresAt: created.expiresAt, ai: ai, updatedAt: now)
        records.insert(record, at: 0)
        sort()
    }

    /// Her list from the server: counts and states for the polls it has, her
    /// polls made on another device (without thumbnails), and the ended ones
    /// kept with their last counts. A poll that should still be live but
    /// isn't on the list was deleted or closed: it goes. Returns the ids that went.
    @discardableResult
    public mutating func merge(_ list: PollList, now: Date) -> [String] {
        let byID = Dictionary(list.polls.map { ($0.pollID, $0) }, uniquingKeysWith: { first, _ in first })
        var dropped: [String] = []
        var kept: [PollRecord] = []
        for var record in records {
            if let summary = byID[record.id] {
                record.question = summary.question
                record.expiresAt = summary.expiresAt
                record.status = summary.status
                record.votes = summary.votes
                record.ai = summary.ai
                record.shareURL = summary.shareURL
                record.updatedAt = now
                kept.append(record)
            } else if record.expiresAt.timeIntervalSince(now) <= Self.clockSlack {
                kept.append(record)
            } else {
                dropped.append(record.id)
            }
        }
        let known = Set(records.map(\.id))
        for summary in list.polls where !known.contains(summary.pollID) {
            kept.append(PollRecord(id: summary.pollID, shareURL: summary.shareURL, question: summary.question,
                                   createdAt: summary.createdAt ?? summary.expiresAt.addingTimeInterval(-Self.lifetime),
                                   expiresAt: summary.expiresAt, status: summary.status, votes: summary.votes,
                                   ai: summary.ai, updatedAt: now))
        }
        records = kept
        sort()
        return dropped + prune(now: now)
    }

    public mutating func remove(_ id: String) {
        records.removeAll { $0.id == id }
    }

    /// Drops what ended more than a day ago. Returns their ids.
    @discardableResult
    public mutating func prune(now: Date) -> [String] {
        let gone = records.filter { now.timeIntervalSince($0.expiresAt) >= Self.keepsEnded }.map(\.id)
        records.removeAll { gone.contains($0.id) }
        return gone
    }

    private mutating func sort() {
        records.sort { $0.createdAt > $1.createdAt }
    }
}

extension NotificationPlanner {
    /// "Your poll ends in an hour" comes this long before the end.
    public static let pollReminderLead: TimeInterval = 3600

    /// When to say a poll ends in an hour: then, if that's still ahead and
    /// outside quiet and school hours; otherwise never (a later reminder
    /// would be wrong, and an earlier one isn't worth a ping).
    public static func pollEnding(expiresAt: Date, now: Date, calendar: Calendar = .current) -> Date? {
        let date = expiresAt.addingTimeInterval(-pollReminderLead)
        guard date > now, !isQuiet(date, calendar: calendar), !isSchoolTime(date, calendar: calendar) else { return nil }
        return date
    }
}
