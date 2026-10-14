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
        let categories: Set<TemplateCategory> = [.trending, .aesthetic, .art]
        XCTAssertTrue(categories.contains(TemplateCatalog.trendOfTheDay(on: day, calendar: calendar).category))
    }

    func testFreeUsersNeverGetAProTrendAndNoOneGetsGlowUps() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = Date(timeIntervalSince1970: 1_791_000_000)
        for offset in 0..<365 {
            let day = start.addingTimeInterval(TimeInterval(offset) * 86_400)
            let free = TemplateCatalog.trendOfTheDay(on: day, isPro: false, calendar: calendar)
            XCTAssertFalse(free.isPro, "day \(offset)")
            XCTAssertNotEqual(free.category, .glowUp)
            XCTAssertNotEqual(TemplateCatalog.trendOfTheDay(on: day, isPro: true, calendar: calendar).category, .glowUp)
        }
        XCTAssertFalse(TemplateCatalog.pushPool(isPro: false).isEmpty)
        XCTAssertTrue(TemplateCatalog.pushPool(isPro: true).allSatisfy { $0.season == nil })
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

    func testSnapshotFromAnOlderVersionStillDecodes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = #"{"credits":2,"isPro":false,"latestIsFavorite":false,"creationsCount":1,"updatedAt":"2026-10-01T09:00:00Z"}"#
        try Data(old.utf8).write(to: directory.appendingPathComponent("widget-snapshot.json"))
        let snapshot = try XCTUnwrap(GlowSharedStore.load(from: directory))
        XCTAssertEqual(snapshot.credits, 2)
        XCTAssertNil(snapshot.packs)
        XCTAssertEqual(snapshot.balanceKind, .mixed, "unknown split: no \"today\" or \"this month\" label")
        XCTAssertTrue(snapshot.showsCloudAI, "no age band yet: as before")
        var under13 = snapshot
        under13.cloudAIAllowed = false
        XCTAssertFalse(under13.showsCloudAI)
    }

    func testBalanceKindAndGauge() {
        let free = GlowWidgetSnapshot(credits: 2, isPro: false, nextRefill: nil, latestTitle: nil, creationsCount: 0,
                                      daily: 2, monthly: 0, packs: 0)
        XCTAssertEqual(free.balanceKind, .daily)
        XCTAssertEqual(free.gaugeRange(), 0...3)
        let withPack = GlowWidgetSnapshot(credits: 32, isPro: false, nextRefill: nil, latestTitle: nil, creationsCount: 0,
                                          daily: 2, monthly: 0, packs: 30)
        XCTAssertEqual(withPack.balanceKind, .mixed)
        XCTAssertEqual(withPack.gaugeValue(), 3)
        let pro = GlowWidgetSnapshot(credits: 180, isPro: true, nextRefill: nil, latestTitle: nil, creationsCount: 0,
                                     daily: 0, monthly: 180, packs: 0)
        XCTAssertEqual(pro.balanceKind, .monthly)
        XCTAssertEqual(pro.gaugeRange(), 0...100)
        XCTAssertEqual(pro.gaugeValue(), 100, "rollover can pass the monthly allowance")
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
