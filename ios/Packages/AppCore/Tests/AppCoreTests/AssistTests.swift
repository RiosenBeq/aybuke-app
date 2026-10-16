import XCTest
@testable import AppCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The writing helper's contract (backend `functions/assist`): what the app
/// sends, how it reads the answers and errors, and what reaches her screen.
final class AssistTests: XCTestCase {
    private let config = BackendConfiguration(baseURL: URL(string: "https://demo.supabase.co")!, anonKey: "anon-key")

    private func json(_ request: AssistRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
    }

    // MARK: Requests

    func testRequestEncodesTheContract() throws {
        let inspire = try json(AssistRequest(task: .inspire, locale: "tr"))
        XCTAssertEqual(inspire["task"] as? String, "inspire")
        XCTAssertEqual(inspire["locale"] as? String, "tr")
        XCTAssertNil(inspire["text"], "no text, no key")
        XCTAssertEqual((inspire["context"] as? [String: Any])?.isEmpty, true, "context is always sent")

        let magic = try json(AssistRequest(task: .magic, text: "  a cat\n in the   snow ", locale: "en",
                                           context: AssistContext(style: "watercolor")))
        XCTAssertEqual(magic["task"] as? String, "magic")
        XCTAssertEqual(magic["text"] as? String, "a cat in the snow")
        XCTAssertEqual(magic["context"] as? [String: String], ["style": "watercolor"])

        let captions = try json(AssistRequest(task: .captions, text: "A photo to share with friends", locale: "pt-BR",
                                              context: AssistContext(format: "cover")))
        XCTAssertEqual(captions["context"] as? [String: String], ["format": "cover"])
        let makeup = try json(AssistRequest(task: .makeup, text: "soft winter party glam", locale: "zh-Hans",
                                            context: AssistContext(look: "coldGirl")))
        XCTAssertEqual(makeup["task"] as? String, "makeup")
        XCTAssertEqual(makeup["context"] as? [String: String], ["look": "coldGirl"])
        XCTAssertEqual(Set(AssistTask.allCases.map(\.rawValue)), ["inspire", "magic", "captions", "makeup"])
    }

    func testValidationMirrorsTheServer() {
        XCTAssertNoThrow(try AssistRequest(task: .inspire, locale: "en").validate(), "ideas need no text")
        XCTAssertNil(AssistRequest(task: .magic, text: " \n ", locale: "en").text, "only whitespace is no text")
        for task in [AssistTask.magic, .captions, .makeup] {
            XCTAssertThrowsError(try AssistRequest(task: task, locale: "en").validate()) { error in
                XCTAssertEqual(error as? AssistError, .badRequest, task.rawValue)
            }
        }
        let longest = String(repeating: "a", count: AssistRequest.maxTextLength)
        XCTAssertNoThrow(try AssistRequest(task: .magic, text: longest, locale: "en").validate())
        XCTAssertThrowsError(try AssistRequest(task: .magic, text: longest + "a", locale: "en").validate())
        XCTAssertThrowsError(try AssistRequest(task: .inspire, locale: "nl").validate(), "a language the app doesn't speak")
    }

    /// Her session or nothing: the factory has no anonymous variant.
    func testTheRequestCarriesHerSession() throws {
        let request = try RequestFactory.assist(AssistRequest(task: .inspire, locale: "en"), config: config, accessToken: "user-jwt")
        XCTAssertEqual(request.url?.absoluteString, "https://demo.supabase.co/functions/v1/assist")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer user-jwt")
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "anon-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.timeoutInterval, RequestFactory.assistTimeout)
        XCTAssertLessThanOrEqual(RequestFactory.assistTimeout, 15, "a slow answer falls back to the on-device writer")
        XCTAssertNil(request.value(forHTTPHeaderField: RequestFactory.appTransactionHeader), "none on the device yet: sent without")
        let body = try XCTUnwrap(request.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        XCTAssertEqual(body["task"] as? String, "inspire")

        // The install proof, as with cloud jobs and rewarded ads.
        let proven = try RequestFactory.assist(AssistRequest(task: .inspire, locale: "en"), config: config, accessToken: "user-jwt",
                                               appTransactionJWS: "app-transaction-jws")
        XCTAssertEqual(proven.value(forHTTPHeaderField: RequestFactory.appTransactionHeader), "app-transaction-jws")
        XCTAssertEqual(proven.value(forHTTPHeaderField: "Authorization"), "Bearer user-jwt")
        XCTAssertNil(proven.value(forHTTPHeaderField: RequestFactory.entitlementHeader), "no credits, no entitlement")
        let empty = try RequestFactory.assist(AssistRequest(task: .inspire, locale: "en"), config: config, accessToken: "user-jwt",
                                              appTransactionJWS: "")
        XCTAssertNil(empty.value(forHTTPHeaderField: RequestFactory.appTransactionHeader))
    }

    func testLanguageCodes() {
        for code in Assist.languages {
            XCTAssertEqual(Assist.languageCode(for: code), code, "the app's own localizations stay as they are")
        }
        let cases = [
            "en-GB": "en", "tr_TR": "tr", "pt": "pt-BR", "pt_PT": "pt-BR", "zh-Hans-CN": "zh-Hans", "zh_CN": "zh-Hans",
            "zh-Hant": "zh-Hans", "in": "id", "id-ID": "id", "ja-JP": "ja", "nl": "en", "": "en",
        ]
        for (identifier, expected) in cases {
            XCTAssertEqual(Assist.languageCode(for: identifier), expected, identifier)
        }
    }

    // MARK: Answers

    func testDecodesSuggestions() throws {
        let data = Data(#"{"suggestions":["A cozy treehouse library at dusk","A pastel ice-cream truck by the sea"]}"#.utf8)
        XCTAssertEqual(try ResponseDecoder.decodeAssistSuggestions(data: data, statusCode: 200),
                       ["A cozy treehouse library at dusk", "A pastel ice-cream truck by the sea"])
        XCTAssertEqual(try ResponseDecoder.decodeAssistSuggestions(data: Data(#"{"suggestions":[]}"#.utf8), statusCode: 200), [])
        XCTAssertThrowsError(try ResponseDecoder.decodeAssistSuggestions(data: Data(#"{"ideas":["x"]}"#.utf8), statusCode: 200)) { error in
            XCTAssertEqual(error as? AssistError, .invalidResponse)
        }
    }

    func testDecodesMakeup() throws {
        let full = Data("""
        {"makeup":{"look":"coldGirl","lips":"berry","eyes":"glitterLid","cheeks":null,"extras":["glitter"],
         "hair":null,"intensity":"medium"},"note":"A frosty, sparkly look for a winter party."}
        """.utf8)
        let reply = try ResponseDecoder.decodeAssistMakeup(data: full, statusCode: 200)
        XCTAssertEqual(reply.makeup, AssistMakeup(look: "coldGirl", lips: "berry", eyes: "glitterLid", extras: ["glitter"],
                                                  intensity: "medium"))
        XCTAssertEqual(reply.note, "A frosty, sparkly look for a winter party.")

        // Missing, null or wrongly typed values read as missing.
        let sparse = Data(#"{"makeup":{"lips":"rosy","eyes":7,"extras":["glitter",null,3]}}"#.utf8)
        let sparseReply = try ResponseDecoder.decodeAssistMakeup(data: sparse, statusCode: 200)
        XCTAssertEqual(sparseReply.makeup, AssistMakeup(lips: "rosy"), "a list with a wrong type in it is dropped whole")
        XCTAssertNil(sparseReply.note)
        let noExtras = try ResponseDecoder.decodeAssistMakeup(data: Data(#"{"makeup":{"look":"latte"},"note":null}"#.utf8), statusCode: 200)
        XCTAssertEqual(noExtras.makeup.extras, [])

        XCTAssertThrowsError(try ResponseDecoder.decodeAssistMakeup(data: Data(#"{"note":"hi"}"#.utf8), statusCode: 200)) { error in
            XCTAssertEqual(error as? AssistError, .invalidResponse)
        }
    }

    func testErrorsMapToTheContract() {
        func error(_ body: String, _ status: Int, retryAfter: String? = nil) -> AssistError? {
            do {
                _ = try ResponseDecoder.decodeAssistSuggestions(data: Data(body.utf8), statusCode: status, retryAfter: retryAfter)
                return nil
            } catch {
                return error as? AssistError
            }
        }
        XCTAssertEqual(error(#"{"error":{"code":"bad_request"}}"#, 400), .badRequest)
        XCTAssertEqual(error(#"{"error":{"code":"content_blocked","category":"revealingClothing"}}"#, 422),
                       .contentBlocked(category: "revealingClothing"))
        XCTAssertEqual(error(#"{"error":{"code":"rate_limited","retry_after":30}}"#, 429), .rateLimited(retryAfter: 30))
        XCTAssertEqual(error(#"{"error":{"code":"rate_limited"}}"#, 429, retryAfter: "12"), .rateLimited(retryAfter: 12))
        XCTAssertEqual(error(#"{"error":{"code":"assist_unavailable"}}"#, 503), .unavailable)
        // A bare code, or none at all: the status decides.
        XCTAssertEqual(error(#"{"error":"rate_limited"}"#, 429), .rateLimited(retryAfter: nil))
        XCTAssertEqual(error("", 422), .contentBlocked(category: nil))
        XCTAssertEqual(error("<html>", 503), .unavailable)
        XCTAssertEqual(error("", 401), .unauthorized)
        XCTAssertEqual(error(#"{"error":{"code":"internal"}}"#, 500), .server(status: 500, code: "internal"))
        XCTAssertEqual(ResponseDecoder.assistError(from: Data(#"{"error":{"code":"content_blocked"}}"#.utf8), statusCode: 400),
                       .contentBlocked(category: nil), "the code wins over the status")
    }

    // MARK: What she sees

    func testScreeningKeepsOnlyWhatMayBeShown() {
        let lines = [
            "  “A cozy treehouse library at dusk”  ",
            "a cozy treehouse library at dusk",
            "",
            "A girl in a bikini on the beach",
            String(repeating: "pink ", count: 100),
            "A strawberry\n café   on a cloud",
            "A tiny snail mail post office",
            "A fourth idea that comes too late",
        ]
        XCTAssertEqual(Assist.screened(lines, for: .textToImage), [
            "A cozy treehouse library at dusk",
            "A strawberry café on a cloud",
            "A tiny snail mail post office",
        ])
        XCTAssertEqual(Assist.screened(lines, for: .textToImage, limit: 1), ["A cozy treehouse library at dusk"])
        XCTAssertEqual(Assist.screened([String(repeating: "pink ", count: 100)], for: .textToImage, maxLength: 800).count, 1)
        // Captions and makeup notes are about her photo: the photo rules apply.
        XCTAssertEqual(AssistTask.captions.screeningOperation, .magicEdit)
        XCTAssertEqual(AssistTask.makeup.screeningOperation, .magicEdit)
        XCTAssertEqual(AssistTask.inspire.screeningOperation, .textToImage)
        XCTAssertEqual(AssistTask.magic.screeningOperation, .textToImage)
        XCTAssertEqual(Assist.screened(["Make me look thinner"], for: .magicEdit), [])
    }

    func testTheCaptionWriterHearsTheVibeNotHerLooks() {
        XCTAssertEqual(Assist.captionHint(prompt: " A dreamy  pastel bedroom ", madeWithAI: true), "A dreamy pastel bedroom")
        XCTAssertEqual(Assist.captionHint(prompt: nil, madeWithAI: true), "A picture made with AI, to share with friends")
        XCTAssertEqual(Assist.captionHint(prompt: "", madeWithAI: false), "A photo to share with friends")
        XCTAssertEqual(Assist.captionHint(prompt: "A girl in a bikini", madeWithAI: true), "A picture made with AI, to share with friends")
        let long = Assist.captionHint(prompt: String(repeating: "starry ", count: 80), madeWithAI: true)
        XCTAssertLessThanOrEqual(long.count, AssistRequest.maxTextLength)
        XCTAssertTrue(long.hasSuffix("starry"), "cut on a whole word")
        XCTAssertNoThrow(try AssistRequest(task: .captions, text: long, locale: "en").validate())
    }

    // MARK: Makeup Studio

    func testAnAnswerBecomesHerPicks() throws {
        let answer = AssistMakeup(look: "coldGirl", lips: "berry", eyes: "glitterLid", extras: ["glitter"], intensity: "bold")
        let recipe = try XCTUnwrap(MakeupStudio.recipe(from: answer, keepingHair: .lilac))
        XCTAssertEqual(recipe, MakeupRecipe(lips: .berry, eyes: .glitterLid, cheeks: .rosyFlush, extras: [.glitter],
                                            hair: .lilac, intensity: .bold), "the look, with what it named on top and her hair")

        // Without a look, what it didn't name is "As is".
        XCTAssertEqual(MakeupStudio.recipe(from: AssistMakeup(lips: "cherryRed"), keepingHair: .none),
                       MakeupRecipe(lips: .cherryRed))
        // An empty list keeps the look's extras; a hair color it names wins.
        let strawberry = try XCTUnwrap(MakeupStudio.recipe(from: AssistMakeup(look: "strawberryGirl", hair: "pastelPink"),
                                                           keepingHair: .blue))
        XCTAssertEqual(strawberry.extras, [.fauxFreckles])
        XCTAssertEqual(strawberry.hair, .pastelPink)
        XCTAssertEqual(MakeupStudio.preset(matching: strawberry)?.id, "strawberryGirl", "still the look, with a hair color")
        // A hair color alone is a look too.
        XCTAssertEqual(MakeupStudio.recipe(from: AssistMakeup(hair: "copper"), keepingHair: .none), MakeupRecipe(hair: .copper))
    }

    func testIdsThisVersionDoesntKnowAreLeftOut() throws {
        XCTAssertNil(MakeupStudio.recipe(from: AssistMakeup(), keepingHair: .lilac), "nothing ours: her picks stay")
        XCTAssertNil(MakeupStudio.recipe(from: AssistMakeup(look: "neonDream", lips: "glowstick", extras: ["tattoo"],
                                                            intensity: "bold"), keepingHair: .none))
        XCTAssertNil(MakeupStudio.recipe(from: AssistMakeup(lips: "none"), keepingHair: .none), "nothing to try")
        let mixed = try XCTUnwrap(MakeupStudio.recipe(from: AssistMakeup(look: "latte", eyes: "laserEyes", extras: ["tattoo", "faceGems"],
                                                                         intensity: "extreme"), keepingHair: .none))
        XCTAssertEqual(mixed, MakeupRecipe(lips: .mocha, eyes: .smokyBrown, extras: [.faceGems]))
    }

    func testALipFinishAndExtrasComeBackAsTheAppAllowsThem() throws {
        let decoded = try ResponseDecoder.decodeAssistMakeup(
            data: Data(#"{"makeup":{"look":null,"lips":"berry","lipFinish":"gloss","extras":["glitter"]},"note":"Berry shine"}"#.utf8),
            statusCode: 200
        )
        XCTAssertEqual(decoded.makeup, AssistMakeup(lips: "berry", lipFinish: "gloss", extras: ["glitter"]))
        XCTAssertEqual(MakeupStudio.recipe(from: decoded.makeup, keepingHair: .none),
                       MakeupRecipe(lips: .berry, lipFinish: .gloss, extras: [.glitter]))
        // A finish on a look's color, a finish clear gloss can't take, and a finish alone.
        let cola = try XCTUnwrap(MakeupStudio.recipe(from: AssistMakeup(look: "cherryCola", lipFinish: "matte"), keepingHair: .none))
        XCTAssertEqual(cola.lips, .cherryCola)
        XCTAssertEqual(cola.lipFinish, .matte)
        XCTAssertEqual(MakeupStudio.recipe(from: AssistMakeup(lips: "clearGloss", lipFinish: "matte"), keepingHair: .none)?.lipFinish, MakeupLipFinish.none)
        XCTAssertNil(MakeupStudio.recipe(from: AssistMakeup(lipFinish: "shimmer"), keepingHair: .none), "a finish needs lips")
        // Never more than three extras.
        let crowded = try XCTUnwrap(MakeupStudio.recipe(from: AssistMakeup(extras: ["rhinestones", "facePearls", "heartFreckles", "glitter"]),
                                                        keepingHair: .none))
        XCTAssertEqual(crowded.extras.count, MakeupRecipe.maxExtras)
    }

    func testEveryLookComesBackAsItself() throws {
        for preset in MakeupStudio.presets {
            let recipe = try XCTUnwrap(MakeupStudio.recipe(from: AssistMakeup(look: preset.id), keepingHair: .honeyBlonde))
            XCTAssertEqual(recipe, preset.recipe.withHair(.honeyBlonde), preset.id)
            XCTAssertEqual(ContentPolicy.evaluate(MakeupStudio.instruction(for: recipe), operation: .magicEdit), .allowed, preset.id)
        }
    }
}
