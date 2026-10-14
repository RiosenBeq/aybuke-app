import XCTest
@testable import AppCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class BackendAPITests: XCTestCase {
    private let config = BackendConfiguration(baseURL: URL(string: "https://demo.supabase.co")!, anonKey: "anon-key")

    func testRequestEncodesSnakeCaseContract() throws {
        let body = GenerationRequest(operation: .textToImage, prompt: "a fox", styleID: "anime", aspectRatio: .story, numOutputs: 2)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])
        XCTAssertEqual(json["operation"] as? String, "text_to_image")
        XCTAssertEqual(json["style_id"] as? String, "anime")
        XCTAssertEqual(json["aspect_ratio"] as? String, "9:16")
        XCTAssertEqual(json["num_outputs"] as? Int, 2)
        XCTAssertNil(json["image"])
        XCTAssertNil(json["retry_of"])

        let retry = GenerationRequest(operation: .restyle, templateID: "figurine", image: "data:x", retryOf: "req-1")
        let retryJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(retry)) as? [String: Any])
        XCTAssertEqual(retryJSON["retry_of"] as? String, "req-1")
    }

    func testValidation() {
        XCTAssertThrowsError(try GenerationRequest(operation: .magicEdit, prompt: "sunset").validate())
        XCTAssertThrowsError(try GenerationRequest(operation: .textToImage, prompt: "  ").validate())
        XCTAssertThrowsError(try GenerationRequest(operation: .eraseObject, image: "data:x").validate())
        XCTAssertThrowsError(try GenerationRequest(operation: .textToImage, prompt: "a", numOutputs: 5).validate())
        XCTAssertNoThrow(try GenerationRequest(operation: .restyle, templateID: "figurine", image: "data:x").validate())
        XCTAssertNoThrow(try GenerationRequest(operation: .enhance, image: "data:x").validate())
    }

    func testDataURI() {
        XCTAssertEqual(GenerationRequest.dataURI(Data([0xFF, 0xD8]), mimeType: "image/jpeg"), "data:image/jpeg;base64,/9g=")
    }

    func testGenerationRequestHeaders() throws {
        let request = try RequestFactory.generation(
            GenerationRequest(operation: .enhance, image: "data:x"),
            config: config, accessToken: "user-jwt", entitlementJWS: "jws"
        )
        XCTAssertEqual(request.url?.absoluteString, "https://demo.supabase.co/functions/v1/ai-image")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer user-jwt")
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "anon-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: RequestFactory.entitlementHeader), "jws")
    }

    func testRefreshRequestURL() throws {
        let request = try RequestFactory.refreshSession(refreshToken: "r1", config: config)
        XCTAssertEqual(request.url?.absoluteString, "https://demo.supabase.co/auth/v1/token?grant_type=refresh_token")
    }

    func testDecodesCompletedJob() throws {
        let data = Data("""
        {"job_id":"abc","status":"completed","credits_remaining":2,
         "outputs":[{"url":"https://cdn.example.com/1.png","width":1024,"height":1024,"content_type":"image/png"}]}
        """.utf8)
        let response = try ResponseDecoder.decodeGeneration(data: data, statusCode: 200)
        XCTAssertEqual(response.jobID, "abc")
        XCTAssertEqual(response.status, .completed)
        XCTAssertTrue(response.isFinished)
        XCTAssertEqual(response.creditsRemaining, 2)
        XCTAssertEqual(response.outputs.first?.url?.host, "cdn.example.com")
    }

    func testQueuedJobIsReturnedForPolling() throws {
        let data = Data(#"{"job_id":"j1","status":"queued","credits_remaining":4}"#.utf8)
        let response = try ResponseDecoder.decodeGeneration(data: data, statusCode: 202)
        XCTAssertEqual(response.status, .queued)
        XCTAssertFalse(response.isFinished)
        XCTAssertTrue(response.outputs.isEmpty)
    }

    func testOutputsWithoutStatusMeanCompleted() throws {
        let data = Data(#"{"outputs":[{"url":"https://cdn.example.com/1.png"}]}"#.utf8)
        XCTAssertEqual(try ResponseDecoder.decodeGeneration(data: data, statusCode: 200).status, .completed)
    }

    func testCompletedWithoutOutputsIsInvalid() {
        let data = Data(#"{"status":"completed","outputs":[]}"#.utf8)
        XCTAssertThrowsError(try ResponseDecoder.decodeGeneration(data: data, statusCode: 200)) { error in
            XCTAssertEqual(error as? AIServiceError, .invalidResponse)
        }
    }

    func testFailedJobMapsItsError() {
        let blocked = Data(#"{"job_id":"j1","status":"failed","error":{"code":"content_blocked","message":"Not allowed"}}"#.utf8)
        XCTAssertThrowsError(try ResponseDecoder.decodeGeneration(data: blocked, statusCode: 200)) { error in
            XCTAssertEqual(error as? AIServiceError, .contentBlocked("Not allowed"))
        }
        let generic = Data(#"{"job_id":"j1","status":"failed"}"#.utf8)
        XCTAssertThrowsError(try ResponseDecoder.decodeGeneration(data: generic, statusCode: 200)) { error in
            XCTAssertEqual(error as? AIServiceError, .server(code: "job_failed", message: "This creation failed. Your credit was refunded."))
        }
    }

    func testCancelledJobThrowsCancellation() {
        let data = Data(#"{"job_id":"j1","status":"cancelled"}"#.utf8)
        XCTAssertThrowsError(try ResponseDecoder.decodeGeneration(data: data, statusCode: 200)) { error in
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testDecodesBalance() throws {
        XCTAssertEqual(try ResponseDecoder.decodeBalance(data: Data(#"{"credits_remaining":7}"#.utf8), statusCode: 200), 7)
        XCTAssertThrowsError(try ResponseDecoder.decodeBalance(data: Data(), statusCode: 401))
    }

    func testJobRequests() throws {
        let status = try RequestFactory.jobStatus(jobID: "j 1", config: config, accessToken: "t")
        XCTAssertEqual(status.httpMethod, "GET")
        XCTAssertEqual(status.url?.absoluteString, "https://demo.supabase.co/functions/v1/ai-image?job_id=j%201")
        XCTAssertEqual(status.value(forHTTPHeaderField: "Authorization"), "Bearer t")

        let cancel = try RequestFactory.cancelJob(jobID: "j1", config: config, accessToken: "t")
        XCTAssertEqual(cancel.httpMethod, "DELETE")

        let balance = try RequestFactory.balance(config: config, accessToken: "t", entitlementJWS: "jws")
        XCTAssertEqual(balance.url?.absoluteString, "https://demo.supabase.co/functions/v1/ai-image")
        XCTAssertEqual(balance.value(forHTTPHeaderField: RequestFactory.entitlementHeader), "jws")

        let redeem = try RequestFactory.redeemCreditPack(signedTransaction: "sig", config: config, accessToken: "t")
        XCTAssertEqual(redeem.url?.path, "/functions/v1/credits-redeem")
        let body = try XCTUnwrap(redeem.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: String] })
        XCTAssertEqual(body["signed_transaction"], "sig")

        let delete = try RequestFactory.deleteAccount(config: config, accessToken: "t")
        XCTAssertEqual(delete.httpMethod, "DELETE")
        XCTAssertEqual(delete.url?.path, "/functions/v1/account")
        XCTAssertNil(delete.httpBody)

        let deleteBoth = try RequestFactory.deleteAccount(config: config, accessToken: "t", anonymousToken: "anon")
        let deleteBody = try XCTUnwrap(deleteBoth.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: String] })
        XCTAssertEqual(deleteBody["anonymous_token"], "anon")
    }

    func testPollingScheduleBacksOff() {
        let schedule = PollingSchedule.standard
        XCTAssertEqual(schedule.delay(forAttempt: 0), 1)
        XCTAssertEqual(schedule.delay(forAttempt: 6), 2.5)
        XCTAssertEqual(schedule.delay(forAttempt: 50), 3)
        let total = (0..<80).map(schedule.delay(forAttempt:)).reduce(0, +)
        XCTAssertGreaterThan(total, schedule.timeout, "the deadline, not the attempt count, ends polling")
    }

    func testCancelAndConfirmAreDifferentRequests() throws {
        let cancel = try RequestFactory.cancelJob(jobID: "j1", config: config, accessToken: "t")
        XCTAssertEqual(cancel.httpMethod, "DELETE")
        XCTAssertEqual(cancel.url?.absoluteString, "https://demo.supabase.co/functions/v1/ai-image?job_id=j1&intent=cancel")
        let confirm = try RequestFactory.confirmJob(jobID: "j1", config: config, accessToken: "t")
        XCTAssertEqual(confirm.httpMethod, "DELETE")
        XCTAssertEqual(confirm.url?.absoluteString, "https://demo.supabase.co/functions/v1/ai-image?job_id=j1")
        XCTAssertEqual(confirm.value(forHTTPHeaderField: "Authorization"), "Bearer t")
    }

    func testPollingRidesOutDroppedConnections() {
        let schedule = PollingSchedule.standard
        XCTAssertEqual(schedule.next(elapsed: 5, attempt: 0, failures: 0), .poll(after: 1))
        XCTAssertEqual(schedule.next(elapsed: 60, attempt: 30, failures: 0), .poll(after: 3))
        // A drop backs off instead of abandoning a job whose credit is reserved.
        XCTAssertEqual(schedule.next(elapsed: 20, attempt: 5, failures: 1, outage: 0), .poll(after: 2))
        XCTAssertEqual(schedule.next(elapsed: 40, attempt: 5, failures: 5, outage: 20), .poll(after: 13))
        XCTAssertEqual(schedule.next(elapsed: 100, attempt: 5, failures: 40, outage: 80), .poll(after: 13))
        // Past the deadline a job the server still runs is cancelled (and refunded)…
        XCTAssertEqual(schedule.next(elapsed: 180, attempt: 70, failures: 0), .cancel)
        // …while an unreachable server keeps being asked, even past the deadline…
        XCTAssertEqual(schedule.next(elapsed: 200, attempt: 70, failures: 2, outage: 10), .poll(after: 3))
        // …until it has been out of reach for the whole grace period.
        XCTAssertEqual(schedule.next(elapsed: 300, attempt: 70, failures: 9, outage: 120), .giveUp)
        // Back from the background long after the deadline: a poll cut off on
        // the way out isn't an outage yet, so the app asks again.
        XCTAssertEqual(schedule.next(elapsed: 900, attempt: 20, failures: 1, outage: 0), .poll(after: 2))

        // Two minutes without a connection still leave room for many attempts.
        var outage: TimeInterval = 0
        var failures = 1
        while case .poll(let wait) = schedule.next(elapsed: 30 + outage, attempt: 10, failures: failures, outage: outage) {
            outage += wait
            failures += 1
        }
        XCTAssertGreaterThanOrEqual(failures, 10)
        XCTAssertGreaterThanOrEqual(outage, schedule.offlineGrace)
    }

    func testOnlyPassingFailuresAreRetried() {
        XCTAssertTrue(PollingSchedule.isWorthRetrying(AIServiceError.offline))
        XCTAssertTrue(PollingSchedule.isWorthRetrying(AIServiceError.timedOut))
        XCTAssertTrue(PollingSchedule.isWorthRetrying(AIServiceError.network("Check your internet connection and try again.")))
        XCTAssertTrue(PollingSchedule.isWorthRetrying(AIServiceError.rateLimited(retryAfter: 20)))
        XCTAssertTrue(PollingSchedule.isWorthRetrying(AIServiceError.server(code: "http_502", message: "busy")))
        XCTAssertTrue(PollingSchedule.isWorthRetrying(AIServiceError.server(code: "internal", message: "oops")))
        XCTAssertFalse(PollingSchedule.isWorthRetrying(AIServiceError.server(code: "not_found", message: "gone")))
        XCTAssertFalse(PollingSchedule.isWorthRetrying(AIServiceError.unauthorized))
        XCTAssertFalse(PollingSchedule.isWorthRetrying(AIServiceError.contentBlocked("no")))
        XCTAssertFalse(PollingSchedule.isWorthRetrying(CancellationError()))
    }

    func testReportedBalanceAndStatus() {
        XCTAssertEqual(ResponseDecoder.reportedBalance(in: Data(#"{"job_id":"j1","status":"queued","credits_remaining":2}"#.utf8)), 2)
        let failed = Data(#"{"job_id":"j1","status":"failed","error":{"code":"provider_failed","message":"x"},"credits_remaining":3}"#.utf8)
        XCTAssertEqual(ResponseDecoder.reportedBalance(in: failed), 3)
        let empty = Data(#"{"error":{"code":"insufficient_credits","message":"x","credits_remaining":0}}"#.utf8)
        XCTAssertEqual(ResponseDecoder.reportedBalance(in: empty), 0)
        XCTAssertNil(ResponseDecoder.reportedBalance(in: Data(#"{"job_id":"j1","status":"processing"}"#.utf8)))
        XCTAssertNil(ResponseDecoder.reportedBalance(in: Data("<html>".utf8)))
        let cancelled = Data(#"{"job_id":"j1","status":"cancelled","credits_remaining":3}"#.utf8)
        XCTAssertEqual(ResponseDecoder.reportedStatus(in: cancelled), .cancelled)
        XCTAssertNil(ResponseDecoder.reportedStatus(in: Data("{}".utf8)))
    }

    func testMapsErrors() {
        let credits = Data(#"{"error":{"code":"insufficient_credits","message":"No credits","credits_remaining":0}}"#.utf8)
        XCTAssertEqual(ResponseDecoder.error(from: credits, statusCode: 402), .insufficientCredits(remaining: 0))

        let blocked = Data(#"{"error":{"code":"content_blocked","message":"Nope"}}"#.utf8)
        XCTAssertEqual(ResponseDecoder.error(from: blocked, statusCode: 422), .contentBlocked("Nope"))

        XCTAssertEqual(ResponseDecoder.error(from: Data(), statusCode: 401), .unauthorized)
        XCTAssertEqual(ResponseDecoder.error(from: Data(), statusCode: 429, retryAfter: "7"), .rateLimited(retryAfter: 7))
        XCTAssertEqual(ResponseDecoder.error(from: Data("oops".utf8), statusCode: 503),
                       .server(code: "http_503", message: "The AI service is busy. Please try again."))
    }

    func testDecodesSupabaseSession() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let data = Data("""
        {"access_token":"at","token_type":"bearer","expires_in":3600,"refresh_token":"rt","user":{"id":"u-1","is_anonymous":true}}
        """.utf8)
        let session = try ResponseDecoder.decodeSession(data: data, statusCode: 200, now: now)
        XCTAssertEqual(session.userID, "u-1")
        XCTAssertEqual(session.expiresAt, Date(timeIntervalSince1970: 4_600))
        XCTAssertFalse(session.isExpired(at: now))
        XCTAssertTrue(session.isExpired(at: Date(timeIntervalSince1970: 4_560)))
        XCTAssertEqual(session.isAnonymous, true)
        XCTAssertFalse(session.isAccount)
    }

    func testSignInWithAppleRequestAndAccountSession() throws {
        let request = try RequestFactory.signInWithApple(idToken: "id.token", nonce: "raw-nonce", config: config)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://demo.supabase.co/auth/v1/token?grant_type=id_token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "anon-key")
        let body = try JSONDecoder().decode([String: String].self, from: request.httpBody ?? Data())
        XCTAssertEqual(body, ["provider": "apple", "id_token": "id.token", "nonce": "raw-nonce"])

        let data = Data("""
        {"access_token":"at","expires_in":3600,"refresh_token":"rt","user":{"id":"u-2","is_anonymous":false,"email":"x@privaterelay.appleid.com"}}
        """.utf8)
        let session = try ResponseDecoder.decodeSession(data: data, statusCode: 200)
        XCTAssertTrue(session.isAccount)
        XCTAssertEqual(session.email, "x@privaterelay.appleid.com")
    }

    func testLinkAccountRequestOmitsMissingFields() throws {
        let request = try RequestFactory.linkAccount(anonymousToken: "anon.jwt", authorizationCode: nil, config: config, accessToken: "account.jwt")
        XCTAssertEqual(request.url?.path, "/functions/v1/account/link")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer account.jwt")
        let body = try JSONDecoder().decode([String: String].self, from: request.httpBody ?? Data())
        XCTAssertEqual(body, ["anonymous_token": "anon.jwt"])
    }

    func testSessionsSavedBeforeAccountsStillDecode() throws {
        let legacy = Data(#"{"accessToken":"a","refreshToken":"r","expiresAt":0,"userID":"u"}"#.utf8)
        let session = try JSONDecoder().decode(AuthSession.self, from: legacy)
        XCTAssertNil(session.isAnonymous)
        XCTAssertFalse(session.isAccount)
    }

    func testDigitalSourceTypes() {
        XCTAssertEqual(AIOperation.textToImage.digitalSourceType.uri,
                       "http://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicMedia")
        XCTAssertEqual(AIOperation.eraseObject.digitalSourceType, .compositeWithTrainedAlgorithmicMedia)
        XCTAssertTrue(AIOperation.removeBackground.runsOnDevice)
        XCTAssertFalse(AIOperation.magicEdit.runsOnDevice)
    }

    func testCompositeProvenance() {
        XCTAssertEqual(DigitalSourceType.composite.uri, "http://cv.iptc.org/newscodes/digitalsourcetype/composite")
        // A cut-out on another photo is a composite, unless generative AI made more of it.
        XCTAssertEqual(DigitalSourceType.strongest(AIOperation.removeBackground.digitalSourceType, .composite), .composite)
        XCTAssertEqual(DigitalSourceType.strongest(.composite, AIOperation.restyle.digitalSourceType), .trainedAlgorithmicMedia)
        XCTAssertEqual(DigitalSourceType.strongest(AIOperation.magicEdit.digitalSourceType, .composite), .compositeWithTrainedAlgorithmicMedia)
        XCTAssertEqual(DigitalSourceType.strongest(nil, .composite), .composite)
        XCTAssertNil(DigitalSourceType.strongest(nil, nil))
    }
}
