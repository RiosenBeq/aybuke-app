import Foundation
import SwiftData
import AppCore
import os

/// "Recently deleted" in My Works. Deleting a creation only stamps
/// `deletedAt`: its file stays for 30 days (`RecentlyDeleted`) so it can be
/// restored, and is removed for good after a later launch.
@MainActor
enum LibraryTrash {
    private static let log = Logger(subsystem: "app.glowlit.ios", category: "library")

    static func moveToRecentlyDeleted(_ creations: [Creation], in context: ModelContext, at date: Date = Date()) {
        for creation in creations { creation.deletedAt = date }
        save(context)
    }

    static func restore(_ creations: [Creation], in context: ModelContext) {
        for creation in creations { creation.deletedAt = nil }
        save(context)
    }

    /// "Delete now", and "Remove" on a tile whose file is gone. The rows go at
    /// once; the files are deleted off the main thread.
    static func deleteForGood(_ creations: [Creation], in context: ModelContext) {
        let names = creations.map(\.imageFileName)
        for creation in creations { context.delete(creation) }
        save(context)
        Task.detached(priority: .utility) {
            for name in names { ImageStore.delete(name) }
        }
    }

    /// After launch: creations deleted more than 30 days ago. Finding them and
    /// deleting their files happens off the main thread; the rows are then
    /// deleted through the main context, so My Works never shows a row
    /// another context removed. Files go first: if the app stops halfway,
    /// the rows are still due and go next time.
    static func purgeExpired(in container: ModelContainer) async {
        let due: [UUID] = await Task.detached(priority: .utility) {
            let context = ModelContext(container)
            let trashed = (try? context.fetch(FetchDescriptor<Creation>(predicate: #Predicate { $0.deletedAt != nil }))) ?? []
            let now = Date()
            let expired = trashed.filter { creation in
                creation.deletedAt.map { RecentlyDeleted.isExpired(deletedAt: $0, now: now) } ?? false
            }
            for creation in expired { ImageStore.delete(creation.imageFileName) }
            return expired.map(\.id)
        }.value
        guard !due.isEmpty else { return }
        let context = container.mainContext
        // Still in Recently deleted: one restored meanwhile keeps its row.
        let rows = (try? context.fetch(FetchDescriptor<Creation>(predicate: #Predicate { creation in
            creation.deletedAt != nil && due.contains(creation.id)
        }))) ?? []
        for creation in rows { context.delete(creation) }
        save(context)
        log.info("Removed \(rows.count, privacy: .public) creations from Recently deleted")
    }

    private static func save(_ context: ModelContext) {
        do { try context.save() } catch {
            log.error("Couldn't save My Works: \(String(describing: error), privacy: .public)")
        }
    }
}
