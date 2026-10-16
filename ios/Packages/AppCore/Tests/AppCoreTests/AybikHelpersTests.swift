import XCTest
@testable import AppCore

/// The app's side of Aybik's four newer helpers (backend `functions/assist`,
/// tasks `looks`, `poll_questions`, `card_text` and `help`): what the app
/// sends, how it reads every answer, what reaches her screen, and the
/// on-device fallbacks it uses when Aybik can't answer.
final class AybikHelpersTests: XCTestCase {
    private func json(_ request: AssistRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
    }

    // MARK: Requests

    func testTheNewTasksEncodeTheContract() throws {
        XCTAssertEqual(Set(AssistTask.allCases.map(\.rawValue)),
                       ["inspire", "magic", "captions", "makeup", "looks", "poll_questions", "card_text", "help"])

        // Kinds once each, in the contract's order, and only for looks.
        let looks = try json(AssistRequest(task: .looks, text: " birthday  picnic\nby the sea ", locale: "tr",
                                           kinds: [.glow, .effect, .look, .effect]))
        XCTAssertEqual(looks["task"] as? String, "looks")
        XCTAssertEqual(looks["text"] as? String, "birthday picnic by the sea")
        XCTAssertEqual(looks["kinds"] as? [String], ["look", "effect", "glow"])
        XCTAssertNil(looks["slots"])
        XCTAssertNil(try json(AssistRequest(task: .looks, text: "picnic", locale: "en"))["kinds"], "all five: no key")
        XCTAssertNil(try json(AssistRequest(task: .captions, text: "x", locale: "en", kinds: [.look]))["kinds"])

        // Poll questions: no text needed, the pictures as a few words each.
        let poll = try json(AssistRequest(task: .pollQuestions, locale: "en", context: AssistContext(a: "Golden Hour", b: " VHS  '86 ")))
        XCTAssertEqual(poll["task"] as? String, "poll_questions")
        XCTAssertNil(poll["text"])
        XCTAssertEqual(poll["context"] as? [String: String], ["a": "Golden Hour", "b": "VHS '86"])

        // Card text: slots once each, in the contract's order, and only for card text.
        let card = try json(AssistRequest(task: .cardText, locale: "ja", context: AssistContext(format: "cover"),
                                          slots: [.coverHeadline, .coverMasthead, .coverHeadline]))
        XCTAssertEqual(card["slots"] as? [String], ["coverMasthead", "coverHeadline"])
        XCTAssertNil(card["kinds"])
        XCTAssertNil(try json(AssistRequest(task: .help, text: "x", locale: "en", slots: [.storyLine]))["slots"])

        let help = try json(AssistRequest(task: .help, text: "How do I cancel Pro?", locale: "de"))
        XCTAssertEqual(help["task"] as? String, "help")
        XCTAssertEqual(help["text"] as? String, "How do I cancel Pro?")
    }

    func testValidationMirrorsTheServerForTheNewTasks() {
        XCTAssertNoThrow(try AssistRequest(task: .pollQuestions, locale: "en").validate())
        XCTAssertNoThrow(try AssistRequest(task: .cardText, locale: "en", slots: [.storyLine]).validate())
        for task in [AssistTask.looks, .help] {
            XCTAssertThrowsError(try AssistRequest(task: task, locale: "en").validate(), task.rawValue) { error in
                XCTAssertEqual(error as? AssistError, .badRequest)
            }
        }
        XCTAssertThrowsError(try AssistRequest(task: .cardText, locale: "en").validate(), "card text needs a slot")
        XCTAssertThrowsError(try AssistRequest(task: .cardText, locale: "en", slots: []).validate())
        XCTAssertThrowsError(try AssistRequest(task: .looks, text: "picnic", locale: "en", kinds: []).validate(), "no kinds at all")
        // Context values are cut to the server's 100 characters on a whole word.
        let long = AssistContext(a: String(repeating: "pastel ", count: 40))
        XCTAssertLessThanOrEqual(long.a?.count ?? 0, AssistContext.maxValueLength)
        XCTAssertNoThrow(try AssistRequest(task: .pollQuestions, locale: "en", context: long).validate())
        XCTAssertNil(AssistContext(a: "  ", b: nil).a, "nothing in it is nothing")
    }

    // MARK: Answers

    func testDecodesLookPicks() throws {
        let data = Data("""
        {"picks":[{"kind":"look","id":"birthday","reason":"Balloons and confetti for the party"},
                  {"kind":"sticker","id":"heart","reason":"A kind this version doesn't know"},
                  {"kind":"effect","id":"disposable","reason":"A 90s flash for picnic snapshots"},
                  {"kind":"glow","id":"golden"}]}
        """.utf8)
        let picks = try ResponseDecoder.decodeAssistPicks(data: data, statusCode: 200)
        XCTAssertEqual(picks, [
            LookFinder.Pick(kind: .look, id: "birthday", reason: "Balloons and confetti for the party"),
            LookFinder.Pick(kind: .effect, id: "disposable", reason: "A 90s flash for picnic snapshots"),
        ], "unknown kinds and picks missing a field are left out")
        XCTAssertEqual(try ResponseDecoder.decodeAssistPicks(data: Data(#"{"picks":[]}"#.utf8), statusCode: 200), [])
        XCTAssertThrowsError(try ResponseDecoder.decodeAssistPicks(data: Data(#"{"looks":[]}"#.utf8), statusCode: 200)) { error in
            XCTAssertEqual(error as? AssistError, .invalidResponse)
        }
        XCTAssertThrowsError(try ResponseDecoder.decodeAssistPicks(data: Data(#"{"error":{"code":"assist_unavailable"}}"#.utf8), statusCode: 503)) { error in
            XCTAssertEqual(error as? AssistError, .unavailable)
        }
        XCTAssertThrowsError(try ResponseDecoder.decodeAssistPicks(
            data: Data(#"{"error":{"code":"content_blocked","category":"sexual"}}"#.utf8), statusCode: 422)) { error in
            XCTAssertEqual(error as? AssistError, .contentBlocked(category: "sexual"))
        }
    }

    func testDecodesCardText() throws {
        let data = Data("""
        {"slots":{"coverMasthead":["PICNIC","SUNNY DAYS!!"],"coverHeadline":["The picnic issue"],
                  "stripCaption":null,"posterTitle":["A slot this version doesn't know"]}}
        """.utf8)
        let reply = try ResponseDecoder.decodeAssistCards(data: data, statusCode: 200)
        XCTAssertEqual(reply.slots, [.coverMasthead: ["PICNIC", "SUNNY DAYS!!"], .coverHeadline: ["The picnic issue"],
                                     .stripCaption: []])
        XCTAssertEqual(Assist.screenedCardLines(reply.slots[.coverMasthead] ?? [], for: .coverMasthead), ["PICNIC"],
                       "longer than the slot: dropped, never cut")
        XCTAssertThrowsError(try ResponseDecoder.decodeAssistCards(data: Data(#"{"suggestions":["x"]}"#.utf8), statusCode: 200)) { error in
            XCTAssertEqual(error as? AssistError, .invalidResponse)
        }
        XCTAssertThrowsError(try ResponseDecoder.decodeAssistCards(data: Data(#"{"error":{"code":"rate_limited","retry_after":9}}"#.utf8), statusCode: 429)) { error in
            XCTAssertEqual(error as? AssistError, .rateLimited(retryAfter: 9))
        }
    }

    func testDecodesHelp() throws {
        let reply = try ResponseDecoder.decodeAssistHelp(
            data: Data(#"{"answer":"Free credits come back every day.","support":false}"#.utf8), statusCode: 200)
        XCTAssertEqual(reply, AssistHelpReply(answer: "Free credits come back every day.", support: false))
        let unsure = try ResponseDecoder.decodeAssistHelp(data: Data(#"{"answer":"Ask support.","support":"maybe"}"#.utf8), statusCode: 200)
        XCTAssertTrue(unsure.support, "when in doubt, offer support")
        XCTAssertThrowsError(try ResponseDecoder.decodeAssistHelp(data: Data(#"{"support":true}"#.utf8), statusCode: 200)) { error in
            XCTAssertEqual(error as? AssistError, .invalidResponse)
        }
        XCTAssertThrowsError(try ResponseDecoder.decodeAssistHelp(data: Data(), statusCode: 503)) { error in
            XCTAssertEqual(error as? AssistError, .unavailable)
        }
    }

    func testPollQuestionsDecodeAsSuggestions() throws {
        let data = Data("""
        {"suggestions":["Which one feels more like summer? ☀️","which one feels more like summer? ☀️",
                        "Who looks prettier?","Vote at www.example.com","Ask @someone","Which vibe?",
                        "\(String(repeating: "Sunset or city lights ", count: 5))?","Pink or lilac?","One too many?"]}
        """.utf8)
        let lines = try ResponseDecoder.decodeAssistSuggestions(data: data, statusCode: 200)
        XCTAssertEqual(Assist.screenedQuestions(lines), [
            "Which one feels more like summer? ☀️",
            "Which vibe?",
            "Pink or lilac?",
            "One too many?",
        ], "repeats, links, handles, rating looks and lines over 80 characters are dropped; four at most")
    }

    // MARK: What she sees

    func testOnlyPicksTheAppCanOpenAreShown() {
        let picks = [
            LookFinder.Pick(kind: .look, id: "birthday", reason: "Balloons and confetti for the party"),
            LookFinder.Pick(kind: .look, id: "birthday", reason: "The same look again"),
            LookFinder.Pick(kind: .look, id: "no-such-look", reason: "An id this version doesn't have"),
            LookFinder.Pick(kind: .style, id: "anime", reason: "A style she can't use here"),
            LookFinder.Pick(kind: .effect, id: "vhs", reason: "A girl in a bikini on the beach"),
            LookFinder.Pick(kind: .enhance, id: "quickFix", reason: "Clearer light, on your device"),
            LookFinder.Pick(kind: .glow, id: "golden", reason: "Visit https://example.com for more"),
            LookFinder.Pick(kind: .effect, id: "disposable", reason: "A 90s flash for picnic snapshots"),
            LookFinder.Pick(kind: .glow, id: "dreamy", reason: "A fourth pick, one too many"),
        ]
        let shown = LookFinder.usable(picks, kinds: [.look, .effect, .enhance, .glow])
        XCTAssertEqual(shown.map(\.key), ["look:birthday", "enhance:quickFix", "effect:disposable"])
        XCTAssertEqual(LookFinder.usable(picks, kinds: [.look, .effect, .enhance, .glow]) { $0.kind != .enhance }.map(\.key),
                       ["look:birthday", "effect:disposable", "glow:dreamy"], "a pick this build can't open is skipped")
    }

    func testAnswersAreShownOnlyAsTheServerWouldSendThem() {
        XCTAssertEqual(Assist.screenedAnswer("## Credits\n**Free** credits come back every day.\n\n\n\nTap your balance."),
                       "Credits\nFree credits come back every day.\n\nTap your balance.")
        XCTAssertEqual(Assist.screenedAnswer("See https://aybuke.org/support for more."), "See https://aybuke.org/support for more.")
        XCTAssertNotNil(Assist.screenedAnswer("findahelpline.com lists free helplines."))
        XCTAssertNil(Assist.screenedAnswer("Claude writes these answers."), "no AI company by name")
        XCTAssertNil(Assist.screenedAnswer("It runs on Anthropic's models."))
        XCTAssertNil(Assist.screenedAnswer("Read more at example.com."), "no other web address")
        XCTAssertNil(Assist.screenedAnswer("Write to someone@example.com."), "no e-mail address")
        XCTAssertNil(Assist.screenedAnswer(String(repeating: "Credits come back daily. ", count: 30)), "over 600 characters")
        XCTAssertNil(Assist.screenedAnswer("  \n "))
    }

    // MARK: On the device

    /// The catalog as `AppModel.finderItems` builds it: under 13 (`cloudAI`
    /// false) Enhance offers Quick fix only.
    private func items(_ kinds: Set<LookFinder.Kind> = Set(LookFinder.Kind.allCases), cloudAI: Bool = true) -> [LookFinder.Item] {
        LookFinder.items(kinds: kinds, localize: { $0 }, effectName: { id in
            ["vhs": "VHS '86", "disposable": "Disposable '98", "digicam": "Digicam '04", "neon": "Neon '84",
             "tinyWorld": "Tiny World", "dslr12": "DSLR '12", "filmStill": "Film Still"][id]
        }, enhance: { option in
            EnhanceOption.available(cloudAI: cloudAI).contains(option) ? (option.rawValue, "Fix a blurry, old or dark photo") : nil
        })
    }

    func testTheDeviceMatchesHerWords() {
        let all = items()
        XCTAssertEqual(LookFinder.localMatches(for: "a birthday party", in: all).first?.key, "look:birthday")
        XCTAssertTrue(LookFinder.localMatches(for: "neon city nights", in: all).contains { $0.key == "effect:neon" })
        XCTAssertTrue(LookFinder.localMatches(for: "golden hour by the sea", in: all).contains { $0.key == "glow:golden" })
        XCTAssertEqual(LookFinder.localMatches(for: "zzqx", in: all), [], "nothing shared, nothing found")
        XCTAssertEqual(LookFinder.localMatches(for: "the and with", in: all), [], "small words say nothing")
        // At most two of a kind, three in all.
        let mix = LookFinder.localMatches(for: "retro 80s 90s Y2K film camera", in: all)
        XCTAssertLessThanOrEqual(mix.count, LookFinder.maxPicks)
        for kind in LookFinder.Kind.allCases {
            XCTAssertLessThanOrEqual(mix.filter { $0.kind == kind }.count, 2)
        }
        // Under 13 only effects, Quick fix and Glow are there to find.
        let free = items([.effect, .enhance, .glow], cloudAI: false)
        XCTAssertFalse(LookFinder.localMatches(for: "birthday", in: free).contains { $0.kind == .look })
        let fixes = LookFinder.localMatches(for: "blurry old photo", in: free)
        XCTAssertTrue(fixes.contains { $0.key == "enhance:quickFix" }, "\(fixes.map(\.key))")
        XCTAssertTrue(fixes.allSatisfy { $0.kind == .effect || $0.kind == .glow || $0.key == "enhance:quickFix" },
                      "no AI fix under 13: \(fixes.map(\.key))")
        XCTAssertTrue(LookFinder.localMatches(for: "blurry old photo", in: items([.enhance])).contains { $0.key == "enhance:unblur" })
    }

    func testStemsAndDenseScriptsMatch() {
        XCTAssertTrue(LookFinder.matches("pikniği", "piknik"))
        XCTAssertTrue(LookFinder.matches("sea", "seaside"))
        XCTAssertFalse(LookFinder.matches("cat", "car"))
        let item = LookFinder.Item(kind: .look, id: "x", name: "誕生日パーティー", about: "風船と紙吹雪")
        XCTAssertEqual(LookFinder.localMatches(for: "友達の誕生日に", in: [item]).map(\.id), ["x"], "pairs of characters")
        XCTAssertEqual(LookFinder.localMatches(for: "のにを", in: [item]), [], "kana particles alone aren't words")
    }

    func testFavoritesWhenNothingMatches() {
        XCTAssertEqual(LookFinder.favorites(in: items()).map(\.key).count, LookFinder.maxPicks)
        XCTAssertEqual(LookFinder.favorites(in: items()).first?.kind, .look)
        XCTAssertEqual(LookFinder.favorites(in: items([.effect, .enhance, .glow])).map(\.key),
                       ["effect:disposable", "glow:dreamy", "effect:digicam"], "under 13: free things only")
        XCTAssertEqual(LookFinder.favorites(in: items([.effect, .enhance])).map(\.key),
                       ["effect:disposable", "effect:digicam", "enhance:quickFix"], "no camera: no Glow")
    }

    func testTheFinderKnowsTheServersCatalog() throws {
        struct Catalog: Decodable {
            struct Entry: Decodable { let id: String }
            struct Finder: Decodable {
                let looks, styles, effects, enhance, glow: [Entry]
            }

            let finder: Finder
        }
        let url = try RepositoryFile.url("backend/supabase/functions/_shared/catalog.json")
        let finder = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url)).finder
        let server: [LookFinder.Kind: [Catalog.Entry]] = [
            .look: finder.looks, .style: finder.styles, .effect: finder.effects, .enhance: finder.enhance, .glow: finder.glow,
        ]
        for (kind, entries) in server {
            XCTAssertEqual(Set(entries.map(\.id)), LookFinder.ids(of: kind), "\(kind): run scripts/export-catalog.sh")
        }
    }

    // MARK: Hand-written fallbacks

    func testCuratedCardLinesFitTheirSlots() {
        for slot in ShareTextSlot.allCases {
            let lines = CardLines.lines(for: slot)
            XCTAssertGreaterThanOrEqual(lines.count, 4, "\(slot)")
            XCTAssertEqual(Assist.screenedCardLines(lines, for: slot, limit: .max), lines, "\(slot): each fits and may be shown")
        }
    }

    func testPollIdeasNeverHearAMagicEditsInstruction() {
        let names = Assist.pollHintNames().union(["Disposable '98", "Hide faces"])
        // The editor saves a typed edit titled with her instruction and no prompt.
        XCTAssertEqual(Assist.pollHint(title: "give me pink hair and freckles like my sister", operation: .magicEdit,
                                       prompt: nil, names: names), "Magic Edit")
        XCTAssertEqual(Assist.pollHint(title: "make me look older", operation: .eraseObject, prompt: nil, names: names), "Erase",
                       "a later AI step keeps the old title")
        XCTAssertNil(Assist.pollHint(title: "give me red hair", operation: nil, prompt: nil, names: names), "after Undo")
        XCTAssertEqual(Assist.pollHint(title: "give me red hair", operation: .magicEdit, prompt: "give me red hair", names: names),
                       "Magic Edit", "a prompt alone never lets an edit's words through")
        // Names the app gave a step, and her Create prompt, go through.
        let look = TemplateCatalog.all[0].title
        XCTAssertEqual(Assist.pollHint(title: look, operation: .restyle, prompt: nil, names: names), look)
        let makeup = MakeupStudio.presets[0].name
        XCTAssertEqual(Assist.pollHint(title: makeup, operation: .magicEdit, prompt: nil, names: names), makeup)
        XCTAssertEqual(Assist.pollHint(title: "Disposable '98", operation: nil, prompt: nil, names: names), "Disposable '98")
        XCTAssertEqual(Assist.pollHint(title: "a cat in the snow", operation: .textToImage, prompt: "a cat in the snow",
                                       names: names), "a cat in the snow")
        XCTAssertEqual(Assist.pollHint(title: "Hide faces", operation: .magicEdit, prompt: nil, names: names), "Hide faces")
        XCTAssertEqual(Assist.pollHint(title: "a dog", operation: .textToImage, prompt: nil, names: names,
                                       localize: { $0 == "Create" ? "Oluştur" : $0 }), "Oluştur")
    }

    func testHelpTopicsAnswerFromTheDevice() {
        let all = HelpTopic.topics(cloudAI: true)
        XCTAssertEqual(all, HelpTopic.all)
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
        let young = HelpTopic.topics(cloudAI: false)
        XCTAssertFalse(young.isEmpty)
        XCTAssertTrue(young.allSatisfy { !$0.needsCloudAI }, "under 13: nothing about AI, credits, Pro or polls")
        XCTAssertEqual(HelpTopic.matching("how can I cancel my Pro subscription", in: all).first?.id, "cancel")
        XCTAssertEqual(HelpTopic.matching("delete a poll", in: all).first?.id, "polls")
        XCTAssertEqual(HelpTopic.matching("zzqx", in: all), [])
        XCTAssertFalse(HelpTopic.matching("cancel Pro", in: young).contains { $0.needsCloudAI })
        // How she asks says nothing about what: no "How do I…" topic for a refund.
        XCTAssertEqual(HelpTopic.matching("How do I get a refund?", in: all), [])
        XCTAssertEqual(HelpTopic.matching("what can I do, why was it, who are you", in: all), [])
        XCTAssertEqual(HelpTopic.matching("Who is Aybik?", in: all).first?.id, "aybik")
        XCTAssertFalse(young.contains { $0.answer.contains("Pro") }, "under 13 nothing points to a purchase")
        for topic in all {
            XCTAssertNotNil(Assist.screenedAnswer(topic.answer), topic.id)
            XCTAssertEqual(ContentPolicy.evaluate(topic.question, operation: .textToImage), .allowed, topic.id)
        }
    }

    func testOnDeviceLinesPassThePhotoRules() {
        for line in LookFinder.effects.map(\.about) + LookFinder.glowLooks.map(\.about) + [LookFinder.styleAbout] {
            XCTAssertEqual(Assist.screenedShown([line], maxLength: LookFinder.maxReasonLength, limit: 1), [line])
        }
        for preset in PollQuestion.presets {
            XCTAssertEqual(Assist.screenedQuestions([preset]), [preset])
        }
    }
}
