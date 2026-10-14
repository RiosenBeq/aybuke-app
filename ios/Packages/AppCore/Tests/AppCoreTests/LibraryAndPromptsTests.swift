import XCTest
@testable import AppCore

final class RecentPromptsTests: XCTestCase {
    func testNewestFirstWithoutDuplicates() {
        var recent = RecentPrompts()
        recent.add("pink hair")
        recent.add("a cat in the snow")
        recent.add("  Pink   hair ")
        XCTAssertEqual(recent.items, ["Pink hair", "a cat in the snow"])
    }

    func testKeepsTheLastTen() {
        var recent = RecentPrompts()
        for index in 1...14 { recent.add("idea \(index)") }
        XCTAssertEqual(recent.items.count, RecentPrompts.limit)
        XCTAssertEqual(recent.items.first, "idea 14")
        XCTAssertEqual(recent.items.last, "idea 5")
    }

    func testIgnoresEmptyPrompts() {
        var recent = RecentPrompts()
        recent.add("   \n\t ")
        recent.add("")
        XCTAssertTrue(recent.items.isEmpty)
    }

    func testStoredListIsCleanedInOrder() {
        let stored = ["newest", "NEWEST", "", "middle", "oldest"] + (1...12).map { "old \($0)" }
        let recent = RecentPrompts(stored)
        XCTAssertEqual(Array(recent.items.prefix(3)), ["newest", "middle", "oldest"])
        XCTAssertEqual(recent.items.count, RecentPrompts.limit)
    }

    func testRemoveAndClear() {
        var recent = RecentPrompts(["b", "a"])
        recent.remove("B")
        XCTAssertEqual(recent.items, ["a"])
        recent.removeAll()
        XCTAssertTrue(recent.items.isEmpty)
    }

    func testLongPromptsAreCapped() {
        var recent = RecentPrompts()
        recent.add(String(repeating: "a", count: PromptBuilder.maxPromptLength + 50))
        XCTAssertEqual(recent.items.first?.count, PromptBuilder.maxPromptLength)
    }
}

final class RecentlyDeletedTests: XCTestCase {
    private let deletedAt = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    func testThirtyDaysRightAfterDeleting() {
        XCTAssertEqual(RecentlyDeleted.daysLeft(deletedAt: deletedAt, now: deletedAt), 30)
        XCTAssertEqual(RecentlyDeleted.daysLeft(deletedAt: deletedAt, now: deletedAt.addingTimeInterval(60)), 30)
    }

    func testCountsDownInWholeDays() {
        XCTAssertEqual(RecentlyDeleted.daysLeft(deletedAt: deletedAt, now: deletedAt.addingTimeInterval(day + 1)), 29)
        XCTAssertEqual(RecentlyDeleted.daysLeft(deletedAt: deletedAt, now: deletedAt.addingTimeInterval(29.5 * day)), 1)
    }

    func testExpiresAfterThirtyDays() {
        let due = deletedAt.addingTimeInterval(30 * day)
        XCTAssertFalse(RecentlyDeleted.isExpired(deletedAt: deletedAt, now: due.addingTimeInterval(-1)))
        XCTAssertTrue(RecentlyDeleted.isExpired(deletedAt: deletedAt, now: due))
        XCTAssertEqual(RecentlyDeleted.daysLeft(deletedAt: deletedAt, now: due), 0)
        XCTAssertEqual(RecentlyDeleted.daysLeft(deletedAt: deletedAt, now: due.addingTimeInterval(90 * day)), 0)
        XCTAssertEqual(RecentlyDeleted.purgeDate(deletedAt: deletedAt), due)
    }

    func testClockThatMovedBackShowsAtMostThirtyDays() {
        XCTAssertEqual(RecentlyDeleted.daysLeft(deletedAt: deletedAt, now: deletedAt.addingTimeInterval(-10 * day)), 30)
        XCTAssertFalse(RecentlyDeleted.isExpired(deletedAt: deletedAt, now: deletedAt.addingTimeInterval(-10 * day)))
    }
}
