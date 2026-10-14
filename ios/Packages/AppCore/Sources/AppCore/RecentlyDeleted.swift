import Foundation

/// My Works' "Recently deleted": a deleted creation is kept for 30 days, so
/// a slip of the thumb can be undone, then removed for good after the next
/// launch.
public enum RecentlyDeleted {
    public static let retentionDays = 30
    static let day: TimeInterval = 24 * 60 * 60

    /// When a creation deleted at `deletedAt` is removed for good.
    public static func purgeDate(deletedAt: Date) -> Date {
        deletedAt.addingTimeInterval(TimeInterval(retentionDays) * day)
    }

    /// Whole days left, rounded up as Photos counts them: 30 right after
    /// deleting, 1 on the last day, 0 once it's due. A clock that moved
    /// back never shows more than 30.
    public static func daysLeft(deletedAt: Date, now: Date) -> Int {
        let remaining = purgeDate(deletedAt: deletedAt).timeIntervalSince(now)
        guard remaining > 0 else { return 0 }
        return min(retentionDays, Int((remaining / day).rounded(.up)))
    }

    public static func isExpired(deletedAt: Date, now: Date) -> Bool {
        now >= purgeDate(deletedAt: deletedAt)
    }
}
