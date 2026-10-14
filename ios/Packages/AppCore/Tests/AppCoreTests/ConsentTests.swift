import XCTest
@testable import AppCore

final class ConsentTests: XCTestCase {
    private let processors = ["Supabase", "xAI (Grok Imagine)", "fal.ai"]

    func testValidForSameVersionAndProcessorsInAnyOrder() {
        let record = AIConsentRecord(version: 1, acceptedAt: Date(), processors: processors)
        XCTAssertTrue(record.isValid(currentVersion: 1, currentProcessors: processors))
        XCTAssertTrue(record.isValid(currentVersion: 1, currentProcessors: processors.reversed()))
    }

    func testVersionBumpAsksAgain() {
        let record = AIConsentRecord(version: 1, acceptedAt: Date(), processors: processors)
        XCTAssertFalse(record.isValid(currentVersion: 2, currentProcessors: processors))
    }

    func testChangedProcessorsAskAgainWithoutABump() {
        let record = AIConsentRecord(version: 1, acceptedAt: Date(), processors: ["Supabase", "xAI (Grok Imagine)"])
        XCTAssertFalse(record.isValid(currentVersion: 1, currentProcessors: processors), "a new processor")
        XCTAssertFalse(record.isValid(currentVersion: 1, currentProcessors: ["Supabase", "OpenAI"]), "a different one")
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
}
