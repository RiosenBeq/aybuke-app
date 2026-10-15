import XCTest
@testable import AppCore

final class ConsentTests: XCTestCase {
    private let processors = ["Supabase", "xAI (Grok Imagine)", "Anthropic (Claude)"]

    func testValidForSameVersionAndProcessorsInAnyOrder() {
        let record = AIConsentRecord(version: 2, acceptedAt: Date(), processors: processors)
        XCTAssertTrue(record.isValid(currentVersion: 2, currentProcessors: processors))
        XCTAssertTrue(record.isValid(currentVersion: 2, currentProcessors: processors.reversed()))
    }

    func testVersionBumpAsksAgain() {
        let record = AIConsentRecord(version: 1, acceptedAt: Date(), processors: processors)
        XCTAssertFalse(record.isValid(currentVersion: 2, currentProcessors: processors))
    }

    func testChangedProcessorsAskAgainWithoutABump() {
        let record = AIConsentRecord(version: 2, acceptedAt: Date(), processors: ["Supabase", "xAI (Grok Imagine)"])
        XCTAssertFalse(record.isValid(currentVersion: 2, currentProcessors: processors), "a new processor")
        XCTAssertFalse(record.isValid(currentVersion: 2, currentProcessors: ["Supabase", "OpenAI"]), "a different one")
    }

    func testRoundTripAndOlderFormatsCountAsNoRecord() throws {
        let record = AIConsentRecord(version: 2, acceptedAt: Date(timeIntervalSince1970: 1_800_000_000),
                                     processors: processors, guardianConfirmed: true)
        XCTAssertEqual(AIConsentRecord.decode(try JSONEncoder().encode(record)), record)
        // The never-shipped v2 shape ({granted, date, guardianConfirmed}) has no version.
        let old = Data(#"{"granted":true,"guardianConfirmed":false}"#.utf8)
        XCTAssertNil(AIConsentRecord.decode(old))
        XCTAssertNil(AIConsentRecord.decode(nil))
    }

    /// The independent safety check (backend `_shared/safety.ts`, run by
    /// `ai-image`) sends photos and results to a company, so the sheet must
    /// name it. ANTHROPIC_API_KEY is a launch requirement, so Anthropic is
    /// listed whenever the code can call it. FAL_KEY (fal.ai) isn't here on
    /// purpose: it stays unset, and setting it needs an app update that lists
    /// fal.ai first.
    func testTheConsentSheetNamesTheSafetyCheck() throws {
        struct Processor: Decodable, Equatable { let name, role: String }
        struct Config: Decodable { let consentVersion: Int; let aiProcessors: [Processor] }
        let config = try JSONDecoder().decode(
            Config.self, from: Data(contentsOf: RepositoryFile.url("ios/App/Resources/AppConfig.json")))
        let safety = try ["_shared/safety.ts", "ai-image/index.ts"].map { file in
            try String(contentsOf: RepositoryFile.url("backend/supabase/functions/\(file)"), encoding: .utf8)
        }.joined()
        let companies = [
            "XAI_SAFETY_MODEL": Processor(name: "xAI (Grok Imagine)", role: "images"),
            "ANTHROPIC_API_KEY": Processor(name: "Anthropic (Claude)", role: "safety"),
        ]
        for (secret, processor) in companies where safety.contains(secret) {
            XCTAssertTrue(config.aiProcessors.contains(processor), "the backend reads \(secret): list \(processor.name)")
        }
        // Whoever said yes to the list before Anthropic joined is asked again.
        let before = AIConsentRecord(version: 1, acceptedAt: Date(), processors: ["Supabase", "xAI (Grok Imagine)"])
        XCTAssertGreaterThanOrEqual(config.consentVersion, 2)
        XCTAssertFalse(before.isValid(currentVersion: config.consentVersion,
                                      currentProcessors: config.aiProcessors.map(\.name)))
    }
}
