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
        XCTAssertNil(request.value(forHTTPHeaderField: RequestFactory.appTransactionHeader), "nothing to send, nothing sent")
    }

    /// Free credits belong to a verified App Store install: every request
    /// that spends or shows them carries StoreKit's AppTransaction.
    func testAppTransactionRidesAlong() throws {
        let job = try RequestFactory.generation(GenerationRequest(operation: .enhance, image: "data:x"), config: config,
                                                accessToken: "user-jwt", appTransactionJWS: "app.jws")
        XCTAssertEqual(job.value(forHTTPHeaderField: "X-App-Transaction"), "app.jws")
        let balance = try RequestFactory.balance(config: config, accessToken: "user-jwt", appTransactionJWS: "app.jws")
        XCTAssertEqual(balance.value(forHTTPHeaderField: "X-App-Transaction"), "app.jws")
        let pack = try RequestFactory.redeemCreditPack(signedTransaction: "tx", config: config, accessToken: "user-jwt",
                                                       appTransactionJWS: "app.jws")
        XCTAssertEqual(pack.value(forHTTPHeaderField: "X-App-Transaction"), "app.jws")
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
        // The photo check (ai-image) fails with this code; the app's copy is keyed on it.
        let photo = Data(#"{"job_id":"j1","status":"failed","error":{"code":"photo_check_failed","message":"We couldn't check this photo, so we didn't edit it. Your credit was refunded."}}"#.utf8)
        XCTAssertThrowsError(try ResponseDecoder.decodeGeneration(data: photo, statusCode: 200)) { error in
            XCTAssertEqual(error as? AIServiceError, .server(code: "photo_check_failed",
                                                             message: "We couldn't check this photo, so we didn't edit it. Your credit was refunded."))
        }
    }

    /// Every code ai-image fails a job with has its own sentence in the app
    /// (`AppModel.serverMessages`), translated into every app language; the
    /// server's English message is only the fallback.
    func testEveryJobFailureCodeHasTranslatedAppCopy() throws {
        let server = try String(contentsOf: RepositoryFile.url("backend/supabase/functions/ai-image/index.ts"), encoding: .utf8)
        let app = try String(contentsOf: RepositoryFile.url("ios/App/App/AppModel.swift"), encoding: .utf8)
        let catalog = try JSONSerialization.jsonObject(
            with: Data(contentsOf: RepositoryFile.url("ios/App/Resources/Localizable.xcstrings"))) as? [String: Any]
        let strings = try XCTUnwrap(catalog?["strings"] as? [String: Any])

        let codes = Set(server.matches(of: #/failJob\(db, [\w.]+, "([a-z_]+)"/#).map { String($0.output.1) })
        XCTAssertTrue(codes.isSuperset(of: ["photo_check_failed", "safety_check_failed"]), "\(codes)")
        let start = try XCTUnwrap(app.range(of: "serverMessages: [String: String] = ["))
        let end = try XCTUnwrap(app.range(of: "\n    ]\n", range: start.upperBound..<app.endIndex))
        var copy: [String: String] = [:]
        for match in app[start.upperBound..<end.lowerBound].matches(of: #/"([a-z_]+)": String\(localized: "([^"]+)"\)/#) {
            copy[String(match.output.1)] = String(match.output.2)
        }

        for code in codes.sorted() {
            let english = try XCTUnwrap(copy[code], "AppModel.serverMessages needs a sentence for \(code)")
            let localizations = (strings[english] as? [String: Any])?["localizations"] as? [String: Any] ?? [:]
            let missing = TranslationTests.languages.filter { language in
                let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any]
                return unit?["state"] as? String != "translated" || (unit?["value"] as? String ?? "").isEmpty
            }
            XCTAssertEqual(missing, [], "\"\(english)\" (\(code)) needs translating")
        }
        XCTAssertNotEqual(copy["photo_check_failed"], copy["safety_check_failed"],
                          "The photo check runs before anything is made; the output check's words don't fit it")
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

    func testDecodesBalanceState() throws {
        let state = try ResponseDecoder.decodeBalanceState(data: Data("""
        {"credits_remaining": 2, "is_pro": false, "free_credits": "ok", "ai_status": "cooldown",
         "cooldown_until": "2026-10-15T12:00:00.123456+00:00", "cooldown_seconds": 7200,
         "policy": {"free_daily": 2, "pro_monthly": 80, "rollover_cap": 160, "trial_credits": 20, "free_retries_daily": 3}}
        """.utf8), statusCode: 200)
        XCTAssertEqual(state.creditsRemaining, 2)
        XCTAssertEqual(state.freeCredits, .ok)
        XCTAssertEqual(state.aiStatus, .cooldown)
        XCTAssertEqual(state.policy, ServerCreditPolicy(freeDaily: 2, proMonthly: 80, rolloverCap: 160, trialCredits: 20,
                                                        freeRetriesDaily: 3))
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(CloudPause.from(state, now: now), .cooldown(until: now.addingTimeInterval(7200)))
        XCTAssertTrue(try XCTUnwrap(CloudPause.from(state, now: now)).isActive(at: now))
        XCTAssertFalse(CloudPause.cooldown(until: now).isActive(at: now.addingTimeInterval(1)))

        // An older server, or a status this version doesn't know: nothing breaks.
        let old = try ResponseDecoder.decodeBalanceState(data: Data(#"{"credits_remaining": 5, "ai_status": "later"}"#.utf8),
                                                         statusCode: 200)
        XCTAssertNil(old.freeCredits)
        XCTAssertNil(old.aiStatus)
        XCTAssertNil(CloudPause.from(old))
        let unverified = try ResponseDecoder.decodeBalanceState(
            data: Data(#"{"credits_remaining": 0, "free_credits": "unverified", "ai_status": "blocked"}"#.utf8), statusCode: 200)
        XCTAssertEqual(unverified.freeCredits, .unverified)
        XCTAssertEqual(CloudPause.from(unverified), .blocked)
    }

    func testCooldownWithoutSecondsRestsADay() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let state = try ResponseDecoder.decodeBalanceState(
            data: Data(#"{"credits_remaining": 0, "ai_status": "cooldown"}"#.utf8), statusCode: 200)
        XCTAssertNil(state.cooldownSeconds)
        XCTAssertEqual(CloudPause.from(state, now: now), .cooldown(until: now.addingTimeInterval(24 * 3600)))
    }

    func testJobRequests() throws {
        let status = try RequestFactory.jobStatus(jobID: "j 1", config: config, accessToken: "t")
        XCTAssertEqual(status.httpMethod, "GET")
        XCTAssertEqual(status.url?.absoluteString, "https://demo.supabase.co/functions/v1/ai-image?job_id=j%201")
        XCTAssertEqual(status.value(forHTTPHeaderField: "Authorization"), "Bearer t")
        // The server holds a poll up to 20 s (ai-image/long-poll.ts): the request outlasts that by 10 s or more.
        XCTAssertEqual(status.timeoutInterval, RequestFactory.pollTimeout)
        XCTAssertGreaterThanOrEqual(RequestFactory.pollTimeout - 20, 10)

        let cancel = try RequestFactory.cancelJob(jobID: "j1", config: config, accessToken: "t")
        XCTAssertEqual(cancel.httpMethod, "DELETE")
        XCTAssertEqual(cancel.timeoutInterval, 30)

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

        // After `apple_reauth_required`: a fresh Apple code, or none when Apple couldn't give one.
        let deleteWithCode = try RequestFactory.deleteAccount(config: config, accessToken: "t", authorizationCode: "code")
        let codeBody = try XCTUnwrap(deleteWithCode.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: String] })
        XCTAssertEqual(codeBody, ["authorization_code": "code"])
        let deleteSkipping = try RequestFactory.deleteAccount(config: config, accessToken: "t", skipAppleRevoke: true)
        let skipBody = try XCTUnwrap(deleteSkipping.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Bool] })
        XCTAssertEqual(skipBody, ["skip_apple_revoke": true])
    }

    func testPollingScheduleBacksOff() {
        // The server holds each poll while the job runs, so a few seconds between polls is plenty.
        let schedule = PollingSchedule.standard
        XCTAssertEqual(schedule.delay(forAttempt: 0), 2)
        XCTAssertEqual(schedule.delay(forAttempt: 1), 2)
        XCTAssertEqual(schedule.delay(forAttempt: 2), 3)
        XCTAssertEqual(schedule.delay(forAttempt: 50), 3)
        XCTAssertEqual(schedule.timeout, 180)
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
        XCTAssertEqual(schedule.next(elapsed: 5, attempt: 0, failures: 0), .poll(after: 2))
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

    func testAutomaticBalanceReadsWaitFifteenMinutes() {
        let policy = BalanceRefreshPolicy.standard
        let read = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(policy.isDue(lastRead: nil, now: read), "the first read after launch")
        XCTAssertFalse(policy.isDue(lastRead: read, now: read.addingTimeInterval(60)))
        XCTAssertFalse(policy.isDue(lastRead: read, now: read.addingTimeInterval(15 * 60 - 1)))
        XCTAssertTrue(policy.isDue(lastRead: read, now: read.addingTimeInterval(15 * 60)))
        XCTAssertTrue(policy.isDue(lastRead: read, now: read.addingTimeInterval(-60)), "a clock set back reads again")
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

    /// The abuse controls' answers: never a paywall, never "your session expired".
    func testMapsAbuseControlErrors() {
        func error(_ status: Int, _ body: String, retryAfter: String? = nil) -> AIServiceError {
            ResponseDecoder.error(from: Data(body.utf8), statusCode: status, retryAfter: retryAfter)
        }
        XCTAssertEqual(error(429, #"{"error":{"code":"cooldown","message":"x","retry_after":3600,"until":"2026-10-15"}}"#),
                       .cooldown(retryAfter: 3600))
        XCTAssertEqual(error(403, #"{"error":{"code":"install_blocked","message":"x"}}"#), .cloudBlocked,
                       "a block isn't an expired session")
        XCTAssertEqual(error(503, #"{"error":{"code":"ai_paused","message":"x"}}"#, retryAfter: "600"), .aiPaused(retryAfter: 600))
        XCTAssertEqual(error(429, #"{"error":{"code":"usage_limit","message":"x","retry_after":1200}}"#),
                       .usageLimit(retryAfter: 1200))
        XCTAssertEqual(error(428, #"{"error":{"code":"app_transaction_required","message":"x"}}"#), .appStoreCheckFailed)
        XCTAssertEqual(error(428, #"{"error":{"code":"app_transaction_invalid","message":"x"}}"#), .appStoreCheckFailed)
        XCTAssertEqual(error(409, #"{"error":{"code":"retry_limit","message":"x"}}"#), .retryLimit)
        XCTAssertEqual(error(429, #"{"error":{"code":"rate_limited","message":"x","retry_after":20}}"#), .rateLimited(retryAfter: 20))
        // The code decides, not the status: a proxy's 503 with the same code is still a rate limit.
        XCTAssertEqual(error(503, #"{"error":{"code":"rate_limited","message":"x","retry_after":20}}"#), .rateLimited(retryAfter: 20))
        XCTAssertEqual(error(402, #"{"error":{"code":"pro_required","message":"x"}}"#), .insufficientCredits(remaining: nil),
                       "unchanged")
        let errors: [AIServiceError] = [.cooldown(retryAfter: nil), .cloudBlocked, .aiPaused(retryAfter: nil),
                                        .usageLimit(retryAfter: nil), .appStoreCheckFailed, .retryLimit]
        for message in errors.compactMap(\.errorDescription) {
            XCTAssertNil(message.range(of: #"abuse|violat|banned|suspend|fraud"#, options: [.regularExpression, .caseInsensitive]),
                         "kind words for teens: \(message)")
        }
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
