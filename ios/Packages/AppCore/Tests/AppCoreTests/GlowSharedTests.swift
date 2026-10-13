import XCTest
@testable import AppCore

final class GlowSharedTests: XCTestCase {
    func testDeepLinksRoundTrip() {
        let links: [GlowDeepLink] = [.magicEdit, .create, .removeBackground, .effects, .video, .template("pink-hair"), .library]
        for link in links {
            XCTAssertEqual(GlowDeepLink(url: link.url), link, link.url.absoluteString)
        }
    }

    func testDeepLinksRejectUnknownInput() {
        XCTAssertNil(GlowDeepLink(url: URL(string: "glowlit://template/not-a-template")!))
        XCTAssertNil(GlowDeepLink(url: URL(string: "https://glowlit.app/create")!))
        XCTAssertNil(GlowDeepLink(url: URL(string: "glowlit://paywall")!))
        XCTAssertEqual(GlowDeepLink(url: URL(string: "GLOWLIT://Create")!), .create)
    }

    func testTrendOfTheDayIsStableAndRotates() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let day = Date(timeIntervalSince1970: 1_791_000_000)
        let next = day.addingTimeInterval(86_400)
        XCTAssertEqual(TemplateCatalog.trendOfTheDay(on: day, calendar: calendar), TemplateCatalog.trendOfTheDay(on: day.addingTimeInterval(60), calendar: calendar))
        XCTAssertNotEqual(TemplateCatalog.trendOfTheDay(on: day, calendar: calendar), TemplateCatalog.trendOfTheDay(on: next, calendar: calendar))
        let categories: Set<TemplateCategory> = [.trending, .glowUp, .aesthetic]
        XCTAssertTrue(categories.contains(TemplateCatalog.trendOfTheDay(on: day, calendar: calendar).category))
    }

    func testSnapshotRoundTripsThroughADirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertNil(GlowSharedStore.load(from: directory))
        let snapshot = GlowWidgetSnapshot(
            credits: 2, isPro: false, nextRefill: Date(timeIntervalSince1970: 1_791_100_000),
            latestTitle: "Pink Hair", latestIsFavorite: true, creationsCount: 7,
            updatedAt: Date(timeIntervalSince1970: 1_791_000_000)
        )
        GlowSharedStore.save(snapshot, in: directory)
        XCTAssertEqual(GlowSharedStore.load(from: directory), snapshot)

        GlowSharedStore.saveLatestImage(Data([1, 2, 3]), in: directory)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("latest-creation.jpg")), Data([1, 2, 3]))
        GlowSharedStore.saveLatestImage(nil, in: directory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("latest-creation.jpg").path))
    }

    func testShortenedKeepsWholeWords() {
        XCTAssertEqual("Pink Hair".shortened(to: 34), "Pink Hair")
        let prompt = "A tiny fairy house inside a teacup on a mossy windowsill"
        XCTAssertEqual(prompt.shortened(to: 34), "A tiny fairy house inside a…")
        XCTAssertLessThanOrEqual(prompt.shortened(to: 34).count, 34)
        XCTAssertEqual("Soft glam, golden hour, film grain".shortened(to: 20), "Soft glam, golden…")
        XCTAssertEqual("Supercalifragilistic".shortened(to: 10), "Supercali…")
        XCTAssertEqual("  two\nlines  ".shortened(to: 34), "two lines")
    }

    func testJobStagesHaveCopy() {
        for stage in [GlowJobStage.creating, .finishing, .ready, .failed] {
            XCTAssertFalse(stage.headline.isEmpty)
            XCTAssertFalse(stage.detail.isEmpty)
        }
    }
}
