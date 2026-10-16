import XCTest
@testable import AppCore

/// "Which vibe?" polls: the contract in backend/README.md ("Polls"), her
/// question as the server checks it, the picture limits and what the device
/// keeps.
final class PollsTests: XCTestCase {
    private let config = BackendConfiguration(baseURL: URL(string: "https://example.supabase.co")!, anonKey: "anon")
    private let id = "Ab3_Xy9-Kq2LmN0p"

    // MARK: Counts

    func testPercentagesAddUpToAHundred() {
        XCTAssertNil(PollVotes().percentages)
        XCTAssertTrue(PollVotes(a: 1, b: 2).percentages! == (33, 67))
        XCTAssertTrue(PollVotes(a: 2, b: 1).percentages! == (67, 33))
        XCTAssertTrue(PollVotes(a: 1, b: 1).percentages! == (50, 50))
        XCTAssertTrue(PollVotes(a: 1, b: 0).percentages! == (100, 0))
        XCTAssertTrue(PollVotes(a: 0, b: 7).percentages! == (0, 100))
        XCTAssertTrue(PollVotes(a: 1, b: 6).percentages! == (14, 86))
        // 50.5 and 49.5: the point goes to the larger count.
        XCTAssertTrue(PollVotes(a: 101, b: 99).percentages! == (51, 49))
        XCTAssertTrue(PollVotes(a: 99, b: 101).percentages! == (49, 51))
        for a in 0...40 {
            for b in 0...40 where a + b > 0 {
                let shares = PollVotes(a: a, b: b).percentages!
                XCTAssertEqual(shares.a + shares.b, 100, "\(a) vs \(b)")
                XCTAssertLessThan(abs(Double(shares.a) - Double(a) * 100 / Double(a + b)), 1, "\(a) vs \(b)")
                if a == b { XCTAssertEqual(shares.a, shares.b) }
            }
        }
    }

    // MARK: Wire formats

    func testCreateRequestFollowsTheContract() throws {
        let body = PollCreateRequest(question: "Which vibe?", pictureA: Data([0xFF, 0xD8, 1]), pictureB: Data([0xFF, 0xD8, 2]),
                                     locale: "tr", aiSides: [.b, .a, .b])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])
        XCTAssertEqual(json["question"] as? String, "Which vibe?")
        XCTAssertEqual(json["locale"] as? String, "tr")
        XCTAssertEqual(json["ai_sides"] as? [String], ["a", "b"])
        let images = try XCTUnwrap(json["images"] as? [String])
        XCTAssertEqual(images.count, 2)
        XCTAssertTrue(images.allSatisfy { $0.hasPrefix("data:image/jpeg;base64,") })
        XCTAssertEqual(images[0], "data:image/jpeg;base64,/9gB")

        let plain = PollCreateRequest(question: nil, pictureA: Data([1]), pictureB: Data([2]), locale: "en", aiSides: [])
        let plainJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(plain)) as? [String: Any])
        XCTAssertNil(plainJSON["question"])
        XCTAssertEqual(plainJSON["ai_sides"] as? [String], [])
    }

    func testRequestsCarryHerSessionAndTheAppTransaction() throws {
        let body = PollCreateRequest(question: nil, pictureA: Data([1]), pictureB: Data([2]), locale: "en", aiSides: [])
        let create = try RequestFactory.createPoll(body, config: config, accessToken: "token", appTransactionJWS: "jws")
        XCTAssertEqual(create.httpMethod, "POST")
        XCTAssertEqual(create.url?.absoluteString, "https://example.supabase.co/functions/v1/polls")
        XCTAssertEqual(create.value(forHTTPHeaderField: "Authorization"), "Bearer token")
        XCTAssertEqual(create.value(forHTTPHeaderField: "apikey"), "anon")
        XCTAssertEqual(create.value(forHTTPHeaderField: RequestFactory.appTransactionHeader), "jws")
        XCTAssertEqual(create.timeoutInterval, RequestFactory.pollCreateTimeout)
        let withoutProof = try RequestFactory.createPoll(body, config: config, accessToken: "token")
        XCTAssertNil(withoutProof.value(forHTTPHeaderField: RequestFactory.appTransactionHeader))

        let mine = try RequestFactory.myPolls(config: config, accessToken: "token", appTransactionJWS: "jws")
        XCTAssertEqual(mine.httpMethod, "GET")
        XCTAssertEqual(mine.url?.absoluteString, "https://example.supabase.co/functions/v1/polls/mine")
        XCTAssertEqual(mine.value(forHTTPHeaderField: RequestFactory.appTransactionHeader), "jws")

        let delete = try RequestFactory.deletePoll(id: id, config: config, accessToken: "token")
        XCTAssertEqual(delete.httpMethod, "DELETE")
        XCTAssertEqual(delete.url?.absoluteString, "https://example.supabase.co/functions/v1/polls?id=\(id)")
    }

    func testDecodesWhatTheServerAnswers() throws {
        let created = try ResponseDecoder.decodePollCreated(data: Data("""
        {"poll_id":"\(id)","share_url":"https://aybuke.org/p/\(id)","expires_at":"2026-10-17T09:30:00.123456+00:00","remaining_today":2}
        """.utf8), statusCode: 201)
        XCTAssertEqual(created.pollID, id)
        XCTAssertEqual(created.shareURL.absoluteString, "https://aybuke.org/p/\(id)")
        XCTAssertEqual(created.remainingToday, 2)
        XCTAssertEqual(created.expiresAt.timeIntervalSince1970, 1_792_229_400.123, accuracy: 0.01)

        // A link to anywhere else is never shared: the page's own address is.
        let elsewhere = try ResponseDecoder.decodePollCreated(data: Data("""
        {"poll_id":"\(id)","share_url":"https://example.com/p/\(id)","expires_at":"2026-10-17T09:30:00Z"}
        """.utf8), statusCode: 201)
        XCTAssertEqual(elsewhere.shareURL.absoluteString, "https://aybuke.org/p/\(id)")
        XCTAssertThrowsError(try ResponseDecoder.decodePollCreated(data: Data("""
        {"poll_id":"../../etc","share_url":"https://aybuke.org/p/x","expires_at":"2026-10-17T09:30:00Z"}
        """.utf8), statusCode: 201)) { XCTAssertEqual($0 as? PollError, .invalidResponse) }

        let list = try ResponseDecoder.decodePollList(data: Data("""
        {"polls":[
          {"poll_id":"\(id)","share_url":"https://aybuke.org/p/\(id)","question":"Which vibe?","locale":"en",
           "created_at":"2026-10-16T09:30:00Z","expires_at":"2026-10-17T09:30:00Z","status":"live",
           "ai":{"a":false,"b":true},"votes":{"a":3,"b":5}},
          {"poll_id":"Zz9_Xy9-Kq2LmN0p","share_url":"https://aybuke.org/p/Zz9_Xy9-Kq2LmN0p","question":null,"locale":"tr",
           "created_at":"2026-10-16T08:00:00Z","expires_at":"2026-10-17T08:00:00Z","status":"taken_down",
           "ai":{"a":false,"b":false},"votes":{"a":0,"b":0}},
          {"poll_id":"broken"},
          {"poll_id":"Yy9_Xy9-Kq2LmN0p","share_url":"https://aybuke.org/p/Yy9_Xy9-Kq2LmN0p","expires_at":"2026-10-17T07:00:00Z",
           "status":"under_review","votes":{"a":1}}
        ],"remaining_today":1,"daily_cap":3}
        """.utf8), statusCode: 200)
        XCTAssertEqual(list.polls.map(\.pollID), [id, "Zz9_Xy9-Kq2LmN0p", "Yy9_Xy9-Kq2LmN0p"])
        XCTAssertEqual(list.polls[0].votes, PollVotes(a: 3, b: 5))
        XCTAssertEqual(list.polls[0].ai, PollAILabels(a: false, b: true))
        XCTAssertEqual(list.polls[0].question, "Which vibe?")
        XCTAssertEqual(list.polls[1].status, .takenDown)
        XCTAssertNil(list.polls[1].question)
        XCTAssertEqual(list.polls[2].status, .live, "a state this version doesn't know")
        XCTAssertEqual(list.polls[2].votes, PollVotes(a: 1, b: 0))
        XCTAssertEqual(list.remainingToday, 1)
        XCTAssertEqual(list.dailyCap, 3)

        XCTAssertNoThrow(try ResponseDecoder.decodePollDeleted(data: Data(#"{"deleted":true}"#.utf8), statusCode: 200))
        XCTAssertThrowsError(try ResponseDecoder.decodePollDeleted(data: Data(#"{"error":{"code":"not_found","message":"…"}}"#.utf8),
                                                                    statusCode: 404)) {
            XCTAssertEqual($0 as? PollError, .notFound)
        }
    }

    func testEveryDocumentedErrorHasItsCase() {
        func error(_ status: Int, _ body: String, header: String? = nil) -> PollError {
            ResponseDecoder.pollError(from: Data(body.utf8), statusCode: status, retryAfter: header)
        }
        XCTAssertEqual(error(401, #"{"error":{"code":"unauthorized","message":"…"}}"#), .unauthorized)
        XCTAssertEqual(error(401, ""), .unauthorized)
        XCTAssertEqual(error(403, #"{"error":{"code":"install_blocked","message":"…"}}"#), .installBlocked)
        XCTAssertEqual(error(413, #"{"error":{"side":"b","code":"too_large","message":"…"}}"#), .tooLarge(side: .b))
        XCTAssertEqual(error(413, #"{"error":{"code":"too_large","message":"…"}}"#), .tooLarge(side: nil))
        XCTAssertEqual(error(422, #"{"error":{"side":"a","code":"image_invalid","message":"…"}}"#), .imageInvalid(side: .a))
        XCTAssertEqual(error(422, #"{"error":{"category":"appearanceChange","code":"content_blocked","message":"…"}}"#),
                       .contentBlocked(category: "appearanceChange"))
        XCTAssertEqual(error(422, #"{"error":{"sides":["a","b"],"code":"image_blocked","message":"…"}}"#), .imageBlocked(sides: [.a, .b]))
        XCTAssertEqual(error(429, #"{"error":{"code":"rate_limited","message":"…","retry_after":20}}"#), .rateLimited(retryAfter: 20))
        XCTAssertEqual(error(429, #"{"error":{"code":"rate_limited","message":"…"}}"#, header: "60"), .rateLimited(retryAfter: 60))
        XCTAssertEqual(error(429, #"{"error":{"until":"2026-10-18T09:00:00Z","code":"cooldown","message":"…","retry_after":3600}}"#),
                       .cooldown(until: ServerDate.parse("2026-10-18T09:00:00Z"), retryAfter: 3600))
        XCTAssertEqual(error(503, #"{"error":{"code":"safety_unavailable","message":"…","retry_after":30}}"#),
                       .safetyUnavailable(retryAfter: 30))
        XCTAssertEqual(error(503, "<html>"), .safetyUnavailable(retryAfter: nil))
        XCTAssertEqual(error(404, #"{"error":{"code":"not_found","message":"…"}}"#), .notFound)
        XCTAssertEqual(error(400, #"{"error":{"code":"bad_request","message":"…"}}"#), .badRequest)
        XCTAssertEqual(error(500, #"{"error":{"code":"internal","message":"…"}}"#), .server(status: 500, code: "internal"))
    }

    // MARK: Her question

    func testQuestionIsCountedInCharactersAndCleanedAsFriendsWillSeeIt() {
        XCTAssertEqual(PollQuestion.check(""), .ok(nil))
        XCTAssertEqual(PollQuestion.check("  \n "), .ok(nil))
        XCTAssertEqual(PollQuestion.check("  Which\none\u{200B}   for Friday? "), .ok("Which one for Friday?"))
        // Emoji keep their joiners and count as one character each.
        let family = "👩‍👩‍👧"
        XCTAssertEqual(PollQuestion.cleaned("Which one \(family)❤️"), "Which one \(family)❤️")
        XCTAssertEqual(PollQuestion.check(String(repeating: family, count: 80)), .ok(String(repeating: family, count: 80)))
        XCTAssertEqual(PollQuestion.check(String(repeating: family, count: 81)), .tooLong)
        XCTAssertEqual(PollQuestion.check(String(repeating: "a", count: 81)), .tooLong)
        XCTAssertEqual(PollQuestion.clipped(String(repeating: "b", count: 90)).count, 80)
        // Direction overrides and tags are removed, as the server does.
        XCTAssertEqual(PollQuestion.cleaned("A\u{202E}B\u{E0067}C"), "ABC")
    }

    func testQuestionFollowsTheEditRulesAsTheServerChecksThem() {
        for text in ["make me skinnier", "Which one? Make me skinnier", "smooth my skin", "make him look drunk", "na\u{200B}ked"] {
            guard case .blocked = PollQuestion.check(text) else {
                return XCTFail("\(text) should be blocked")
            }
        }
        for text in ["Which vibe?", "Pink or lilac hair?", "Beach or city?", "Which one for the party 🎉"] {
            XCTAssertEqual(PollQuestion.check(text), .ok(text))
        }
    }

    /// Every preset, in every language, passes the server's checks.
    func testPresetsPassThePolicyInEveryLanguage() throws {
        struct Catalog: Decodable {
            struct Entry: Decodable {
                struct Localization: Decodable {
                    struct Unit: Decodable { let state: String; let value: String }
                    let stringUnit: Unit?
                }
                let localizations: [String: Localization]?
            }
            let strings: [String: Entry]
        }
        let url = try RepositoryFile.url("ios/App/Resources/Localizable.xcstrings")
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
        XCTAssertGreaterThanOrEqual(PollQuestion.presets.count, 4)
        for preset in PollQuestion.presets {
            XCTAssertEqual(PollQuestion.check(preset), .ok(preset))
            let localizations = catalog.strings[preset]?.localizations ?? [:]
            for language in TranslationTests.languages {
                guard let unit = localizations[language]?.stringUnit, unit.state == "translated", !unit.value.isEmpty else {
                    XCTFail("[\(language)] \"\(preset)\" needs translating")
                    continue
                }
                // French keeps its no-break space before "?": friends see a plain one.
                XCTAssertEqual(PollQuestion.check(unit.value), .ok(PollQuestion.cleaned(unit.value)), "[\(language)] \(unit.value)")
            }
        }
    }

    func testNeverHerPhotoAgainstItsEdit() {
        let photo = Provenance()
        let effect = Provenance(operation: nil)
        let edit = Provenance(operation: .magicEdit)
        let look = Provenance(operation: .restyle)
        let creation = Provenance(operation: .textToImage)
        XCTAssertFalse(PollPair.allows(photo, edit))
        XCTAssertFalse(PollPair.allows(look, effect))
        XCTAssertTrue(PollPair.allows(edit, look), "two edits")
        XCTAssertTrue(PollPair.allows(creation, creation), "two creations")
        XCTAssertTrue(PollPair.allows(creation, photo))
        XCTAssertTrue(PollPair.allows(photo, effect), "two plain photos")
        XCTAssertTrue(PollPair.allows(Provenance(inheritedSourceType: .trainedAlgorithmicMedia), photo), "an imported AI picture")
    }

    // MARK: Pictures

    func testPicturesStayWellUnderTheServersLimits() {
        XCTAssertEqual(PollPicture.targetSize(for: PixelSize(width: 4032, height: 3024)), PixelSize(width: 1080, height: 810))
        XCTAssertEqual(PollPicture.targetSize(for: PixelSize(width: 1024, height: 1536)), PixelSize(width: 720, height: 1080))
        XCTAssertEqual(PollPicture.targetSize(for: PixelSize(width: 800, height: 600)), PixelSize(width: 800, height: 600))
        XCTAssertEqual(PollPicture.thumbnailSize(for: PixelSize(width: 1080, height: 1080)), PixelSize(width: 360, height: 360))
        let largest = PollPicture.targetSize(for: PixelSize(width: 9000, height: 9000))
        XCTAssertTrue(PollPicture.isAccepted(byteCount: PollPicture.maxBytes, size: largest))
        XCTAssertLessThan(PollPicture.maxBytes, PollPicture.serverMaxBytes)
        XCTAssertFalse(PollPicture.isAccepted(byteCount: PollPicture.serverMaxBytes + 1, size: largest))
        XCTAssertFalse(PollPicture.isAccepted(byteCount: 1000, size: PixelSize(width: 4097, height: 10)))
        XCTAssertEqual(PollPicture.qualities.first, 0.85)
    }

    func testJPEGMetadataIsStripped() throws {
        func segment(_ marker: UInt8, _ payload: [UInt8]) -> [UInt8] {
            let length = payload.count + 2
            return [0xFF, marker, UInt8(length >> 8), UInt8(length & 0xFF)] + payload
        }
        let scan: [UInt8] = [0xFF, 0xDA, 0x00, 0x04, 0x01, 0x02, 0x11, 0x22, 0xFF, 0x00, 0xFF, 0xD0, 0x33, 0xFF, 0xD9]
        let jpeg: [UInt8] = [0xFF, 0xD8]
            + segment(0xE0, Array("JFIF\0".utf8) + [1, 1, 0, 0, 1, 0, 1, 0, 0])
            + segment(0xE1, Array("Exif\0\0".utf8) + [0x4D, 0x4D, 0, 42])
            + segment(0xE1, Array("http://ns.adobe.com/xap/1.0/\0".utf8) + Array("<x:xmpmeta/>".utf8))
            + segment(0xED, Array("Photoshop 3.0\0".utf8))
            + segment(0xE2, Array("ICC_PROFILE\0".utf8) + [1, 1])
            + segment(0xFE, Array("a comment".utf8))
            + [0xFF, 0xFF] + segment(0xDB, [0, 1, 2]) // with a fill byte
            + segment(0xC0, [8, 0, 1, 0, 1, 1, 1, 0x11, 0])
            + segment(0xC4, [0, 1])
            + scan
        let stripped = try XCTUnwrap(JPEGMetadata.stripped(Data(jpeg)))
        XCTAssertEqual(JPEGMetadata.markers(in: stripped), [0xE0, 0xE2, 0xDB, 0xC0, 0xC4, 0xDA])
        XCTAssertEqual(Array(stripped.suffix(scan.count)), scan, "the scan is untouched")
        XCTAssertFalse(stripped.range(of: Data("Exif".utf8)) != nil)
        XCTAssertFalse(stripped.range(of: Data("xmpmeta".utf8)) != nil)
        XCTAssertFalse(stripped.range(of: Data("comment".utf8)) != nil)
        XCTAssertNil(JPEGMetadata.stripped(Data([0x89, 0x50, 0x4E, 0x47, 0, 0])))
        XCTAssertNil(JPEGMetadata.stripped(Data([0xFF, 0xD8, 0xFF, 0xE1, 0x00, 0x40, 0x00])), "a segment past the end")
        XCTAssertNil(JPEGMetadata.stripped(Data([0xFF, 0xD8, 0xFF, 0xD9, 0x00])), "no scan")
    }

    // MARK: On the device

    func testTimeLeft() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(PollTimeLeft(expiresAt: now.addingTimeInterval(24 * 3600 - 5), now: now), .hours(24))
        XCTAssertEqual(PollTimeLeft(expiresAt: now.addingTimeInterval(5 * 3600 + 1200), now: now), .hours(5))
        XCTAssertEqual(PollTimeLeft(expiresAt: now.addingTimeInterval(3600), now: now), .hours(1))
        XCTAssertEqual(PollTimeLeft(expiresAt: now.addingTimeInterval(3599), now: now), .hours(1))
        XCTAssertEqual(PollTimeLeft(expiresAt: now.addingTimeInterval(45 * 60), now: now), .minutes(45))
        XCTAssertEqual(PollTimeLeft(expiresAt: now.addingTimeInterval(20), now: now), .minutes(1))
        XCTAssertEqual(PollTimeLeft(expiresAt: now, now: now), .ended)
        XCTAssertEqual(PollTimeLeft(expiresAt: now.addingTimeInterval(-60), now: now), .ended)
    }

    func testShelfKeepsLastCountsForADayAndDropsRemovedPolls() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let url = { (id: String) in URL(string: "https://aybuke.org/p/\(id)")! }
        let liveID = "Aa1_Xy9-Kq2LmN0p", endedID = "Bb1_Xy9-Kq2LmN0p", goneID = "Cc1_Xy9-Kq2LmN0p", otherID = "Dd1_Xy9-Kq2LmN0p"
        var shelf = PollShelf()
        shelf.add(PollCreated(pollID: endedID, shareURL: url(endedID), expiresAt: now.addingTimeInterval(-3600), remainingToday: 2),
                  question: nil, ai: PollAILabels(), now: now.addingTimeInterval(-25 * 3600))
        shelf.add(PollCreated(pollID: goneID, shareURL: url(goneID), expiresAt: now.addingTimeInterval(10 * 3600), remainingToday: 1),
                  question: "Which colour?", ai: PollAILabels(), now: now.addingTimeInterval(-14 * 3600))
        shelf.add(PollCreated(pollID: liveID, shareURL: url(liveID), expiresAt: now.addingTimeInterval(20 * 3600), remainingToday: 0),
                  question: "Which vibe?", ai: PollAILabels(a: false, b: true), now: now.addingTimeInterval(-4 * 3600))
        XCTAssertEqual(shelf.records.map(\.id), [liveID, goneID, endedID], "newest first")

        let list = PollList(polls: [
            PollSummary(pollID: liveID, shareURL: url(liveID), question: "Which vibe?", createdAt: nil,
                        expiresAt: now.addingTimeInterval(20 * 3600), status: .live, ai: PollAILabels(b: true), votes: PollVotes(a: 2, b: 5)),
            PollSummary(pollID: otherID, shareURL: url(otherID), question: nil, createdAt: now.addingTimeInterval(-3600),
                        expiresAt: now.addingTimeInterval(23 * 3600), status: .takenDown, ai: PollAILabels(), votes: PollVotes()),
        ], remainingToday: 0, dailyCap: 3)
        let dropped = shelf.merge(list, now: now)
        XCTAssertEqual(dropped, [goneID], "deleted elsewhere while it should be live")
        XCTAssertEqual(shelf.records.map(\.id), [otherID, liveID, endedID])
        XCTAssertEqual(shelf.record(liveID)?.votes, PollVotes(a: 2, b: 5))
        XCTAssertEqual(shelf.record(liveID)?.updatedAt, now)
        XCTAssertEqual(shelf.record(otherID)?.status, .takenDown)
        XCTAssertEqual(shelf.live(at: now).map(\.id), [liveID])
        XCTAssertNotNil(shelf.record(endedID), "an ended poll keeps its last counts")

        // A day after it ended, everything goes.
        XCTAssertEqual(shelf.prune(now: now.addingTimeInterval(23 * 3600)), [endedID])
        XCTAssertEqual(shelf.prune(now: now.addingTimeInterval(23 * 3600)), [])
        // Missing from the list just as it ends: ended, not removed.
        var edge = PollShelf()
        edge.add(PollCreated(pollID: liveID, shareURL: url(liveID), expiresAt: now.addingTimeInterval(60), remainingToday: nil),
                 question: nil, ai: PollAILabels(), now: now.addingTimeInterval(-24 * 3600))
        XCTAssertEqual(edge.merge(PollList(polls: []), now: now), [])
        shelf.remove(liveID)
        XCTAssertNil(shelf.record(liveID))
    }

    func testEndingReminderNeverLandsAtNightOrInSchool() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Istanbul"))
        func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
        }
        // Saturday 17 October 2026.
        XCTAssertEqual(NotificationPlanner.pollEnding(expiresAt: date(17, 18), now: date(17, 9), calendar: calendar), date(17, 17))
        XCTAssertNil(NotificationPlanner.pollEnding(expiresAt: date(17, 22, 30), now: date(17, 9), calendar: calendar), "21:30")
        XCTAssertNil(NotificationPlanner.pollEnding(expiresAt: date(17, 9, 30), now: date(17, 7), calendar: calendar), "08:30")
        // Monday 19 October, 11:00: school.
        XCTAssertNil(NotificationPlanner.pollEnding(expiresAt: date(19, 12), now: date(18, 12), calendar: calendar))
        XCTAssertNil(NotificationPlanner.pollEnding(expiresAt: date(17, 18), now: date(17, 17, 30), calendar: calendar), "past")
    }

    func testPollLinksOpenOnlyRealIDs() {
        XCTAssertEqual(GlowDeepLink(url: URL(string: "glowlit://poll/\(id)")!), .poll(id))
        XCTAssertEqual(GlowDeepLink(url: GlowDeepLink.poll(id).url), .poll(id))
        XCTAssertNil(GlowDeepLink(url: URL(string: "glowlit://poll/short")!))
        XCTAssertNil(GlowDeepLink(url: URL(string: "glowlit://poll")!))
        XCTAssertNil(GlowDeepLink(url: URL(string: "glowlit://poll/Ab3_Xy9-Kq2LmN0p!")!))
        XCTAssertTrue(PollID.isValid(id))
        XCTAssertFalse(PollID.isValid("Ab3_Xy9-Kq2LmN0ü"))
    }
}
