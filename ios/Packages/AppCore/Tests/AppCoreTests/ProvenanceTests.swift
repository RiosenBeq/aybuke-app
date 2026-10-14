import XCTest
@testable import AppCore

final class ProvenanceTests: XCTestCase {
    func testParsesURIAndBareTerm() {
        XCTAssertEqual(DigitalSourceType(uri: "http://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicMedia"), .trainedAlgorithmicMedia)
        XCTAssertEqual(DigitalSourceType(uri: " compositeWithTrainedAlgorithmicMedia "), .compositeWithTrainedAlgorithmicMedia)
        XCTAssertEqual(DigitalSourceType(uri: "https://cv.iptc.org/newscodes/digitalsourcetype/algorithmicallyEnhanced/"), .algorithmicallyEnhanced)
        XCTAssertNil(DigitalSourceType(uri: "http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture"))
        XCTAssertNil(DigitalSourceType(uri: ""))
    }

    func testStrongestKeepsTheMoreGeneratedType() {
        XCTAssertEqual(DigitalSourceType.strongest(nil, nil), nil)
        XCTAssertEqual(DigitalSourceType.strongest(.algorithmicallyEnhanced, nil), .algorithmicallyEnhanced)
        XCTAssertEqual(DigitalSourceType.strongest(.trainedAlgorithmicMedia, .compositeWithTrainedAlgorithmicMedia), .trainedAlgorithmicMedia)
        XCTAssertEqual(DigitalSourceType.strongest(.algorithmicallyEnhanced, .compositeWithTrainedAlgorithmicMedia), .compositeWithTrainedAlgorithmicMedia)
        XCTAssertEqual(AIOperation.stronger(.textToImage, .removeBackground), .textToImage)
        XCTAssertEqual(AIOperation.stronger(.removeBackground, .magicEdit), .magicEdit)
        XCTAssertEqual(AIOperation.stronger(nil, .enhance), .enhance)
    }

    func testCreateResultReEditedKeepsMarkAndLabel() {
        let provenance = Provenance(operation: AIOperation.stronger(.textToImage, .removeBackground))
        XCTAssertEqual(provenance.sourceType, .trainedAlgorithmicMedia)
        XCTAssertTrue(provenance.showsMark(isPro: false))
        XCTAssertFalse(provenance.showsMark(isPro: true))
        XCTAssertTrue(provenance.carriesAIProvenance)
        XCTAssertTrue(provenance.isFullyGenerated)
    }

    func testRestyleStaysFullyGeneratedType() {
        let provenance = Provenance(operation: .restyle)
        XCTAssertEqual(provenance.sourceType, .trainedAlgorithmicMedia)
        XCTAssertFalse(provenance.isFullyGenerated)
    }

    func testOnDeviceOnlyEditsAreUnmarked() {
        XCTAssertNil(Provenance.none.sourceType)
        XCTAssertFalse(Provenance.none.showsMark(isPro: false))
        XCTAssertFalse(Provenance.none.carriesAIProvenance)

        let cutOut = Provenance(operation: .removeBackground)
        XCTAssertEqual(cutOut.sourceType, .algorithmicallyEnhanced)
        XCTAssertFalse(cutOut.showsMark(isPro: false))
        XCTAssertFalse(cutOut.carriesAIProvenance)
    }

    func testInheritedMarkingIsKeptWithoutGlowlitMark() {
        let imported = Provenance(inheritedSourceType: .compositeWithTrainedAlgorithmicMedia)
        XCTAssertEqual(imported.sourceType, .compositeWithTrainedAlgorithmicMedia)
        XCTAssertTrue(imported.carriesAIProvenance)
        XCTAssertFalse(imported.showsMark(isPro: false))

        // A cut-out of an imported AI picture keeps the stronger inherited type.
        let cutOut = Provenance(operation: .removeBackground, inheritedSourceType: .trainedAlgorithmicMedia)
        XCTAssertEqual(cutOut.sourceType, .trainedAlgorithmicMedia)
        XCTAssertTrue(cutOut.carriesAIProvenance)
        XCTAssertFalse(cutOut.showsMark(isPro: false))

        let playground = Provenance(inheritedSourceType: .trainedAlgorithmicMedia)
        XCTAssertTrue(playground.isFullyGenerated)
        XCTAssertFalse(playground.showsMark(isPro: false))
    }

    func testCloudEditOfImportedPictureGetsTheMark() {
        let provenance = Provenance(operation: .magicEdit, inheritedSourceType: .trainedAlgorithmicMedia)
        XCTAssertEqual(provenance.sourceType, .trainedAlgorithmicMedia)
        XCTAssertTrue(provenance.showsMark(isPro: false))
    }
}
