import Foundation
import SwiftData
import AppCore
import os

/// The library as it was before `sourceTypeRaw`. Frozen: its hash must keep
/// matching stores written by those builds.
enum CreationSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [Creation.self] }

    @Model
    final class Creation {
        @Attribute(.unique) var id: UUID
        var createdAt: Date
        var operationRaw: String
        var title: String
        var prompt: String?
        var imageFileName: String
        var pixelWidth: Int
        var pixelHeight: Int
        var isFavorite: Bool = false
        var source: String? = nil

        init(id: UUID, createdAt: Date, operationRaw: String, title: String, imageFileName: String, pixelWidth: Int, pixelHeight: Int) {
            self.id = id
            self.createdAt = createdAt
            self.operationRaw = operationRaw
            self.title = title
            self.imageFileName = imageFileName
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
        }
    }
}

enum GlowlitMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [CreationSchemaV1.self, CreationSchemaV2.self] }
    static var stages: [MigrationStage] {
        // V2 only adds an optional property.
        [.lightweight(fromVersion: CreationSchemaV1.self, toVersion: CreationSchemaV2.self)]
    }
}

/// Opens My Works without ever crashing at launch. A store that can't be
/// opened or migrated is moved aside and the rows are rebuilt from the image
/// files; a full disk or a permissions problem leaves the store untouched
/// and runs on a temporary in-memory library instead.
enum LibraryStore {
    enum Outcome: Equatable {
        case opened
        /// The old store was moved aside; rows were rebuilt from the files.
        case rebuilt
        /// Nothing on disk could be opened; this session's library is in memory.
        case temporary
    }

    private static let log = Logger(subsystem: "app.glowlit.ios", category: "library")
    private static let schema = Schema(versionedSchema: CreationSchemaV2.self)
    private static let corruptPrefix = "Corrupt-"

    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// SwiftData's default store, its SQLite sidecars and Core Data's
    /// external-storage folder.
    private static var storeFiles: [URL] {
        ["default.store", "default.store-shm", "default.store-wal", ".default_SUPPORT"]
            .map { supportDirectory.appendingPathComponent($0) }
    }

    static func open() -> (ModelContainer, Outcome) {
        removeOldCorruptStores()
        let configuration = ModelConfiguration(schema: schema)
        #if DEBUG
        let fault = UserDefaults.standard.string(forKey: "GLLibraryFault")
        if fault == "corrupt" { debugCorruptStore() }
        #endif
        do {
            #if DEBUG
            if fault == "diskFull" { throw debugDiskFullError }
            #endif
            return (try ModelContainer(for: schema, migrationPlan: GlowlitMigrationPlan.self, configurations: configuration), .opened)
        } catch {
            log.error("Library didn't open with the migration plan: \(String(describing: error), privacy: .public)")
        }
        // Retry once with inferred lightweight migration: covers stores from
        // development builds that match no versioned schema.
        let failure: Error
        do {
            #if DEBUG
            if fault == "diskFull" { throw debugDiskFullError }
            #endif
            return (try ModelContainer(for: schema, configurations: configuration), .opened)
        } catch {
            log.error("Library didn't open on retry: \(String(describing: error), privacy: .public)")
            failure = error
        }

        if isStoreDamaged(failure), moveStoreAside(),
           let fresh = try? ModelContainer(for: schema, migrationPlan: GlowlitMigrationPlan.self, configurations: configuration) {
            rebuildRows(in: fresh)
            return (fresh, .rebuilt)
        }
        return (temporaryContainer(), .temporary)
    }

    private static func temporaryContainer() -> ModelContainer {
        // An in-memory store has no file that could fail to open.
        // swiftlint:disable:next force_try
        try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    }

    /// Only an unreadable, incompatible or unmigratable store is moved aside.
    /// A full disk or missing permission would fail the same way next
    /// launch, and moving the store would lose titles and hearts for nothing.
    static func isStoreDamaged(_ error: Error) -> Bool {
        if let capacity = try? supportDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage, capacity < 50_000_000 {
            return false
        }
        let environmental: [String: Set<Int>] = [
            NSCocoaErrorDomain: [NSFileWriteOutOfSpaceError, NSFileWriteNoPermissionError, NSFileReadNoPermissionError,
                                 NSFileWriteVolumeReadOnlyError],
            NSPOSIXErrorDomain: [Int(ENOSPC), Int(EACCES), Int(EPERM), Int(EROFS), Int(EDQUOT)],
            // SQLITE_PERM, SQLITE_BUSY, SQLITE_LOCKED, SQLITE_IOERR, SQLITE_FULL, SQLITE_AUTH
            "NSSQLiteErrorDomain": [3, 5, 6, 10, 13, 23],
        ]
        for nsError in errorChain(error) where environmental[nsError.domain]?.contains(nsError.code) == true {
            return false
        }
        return FileManager.default.fileExists(atPath: storeFiles[0].path)
    }

    private static func errorChain(_ error: Error) -> [NSError] {
        var result: [NSError] = []
        var queue: [NSError] = [error as NSError]
        while let next = queue.popLast(), result.count < 32 {
            result.append(next)
            if let underlying = next.userInfo[NSUnderlyingErrorKey] as? NSError { queue.append(underlying) }
            if let detailed = next.userInfo["NSDetailedErrors"] as? [NSError] { queue.append(contentsOf: detailed) }
            if let code = next.userInfo["NSSQLiteErrorDomain"] as? Int {
                result.append(NSError(domain: "NSSQLiteErrorDomain", code: code))
            }
        }
        return result
    }

    /// Moves the store into Application Support/Corrupt-<date>/ so it can be
    /// inspected (and is deleted after 30 days or with Delete my data).
    private static func moveStoreAside() -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let folder = supportDirectory.appendingPathComponent(corruptPrefix + formatter.string(from: Date()), isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for file in storeFiles where FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.moveItem(at: file, to: folder.appendingPathComponent(file.lastPathComponent))
            }
            return true
        } catch {
            log.error("Couldn't move the library store aside: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// One row per image file. Titles, prompts and hearts lived only in the
    /// store; the AI marking comes back from the tag `ImageStore` writes.
    private static func rebuildRows(in container: ModelContainer) {
        let context = ModelContext(container)
        let directory = ImageStore.directory
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles]
        )) ?? []
        for file in files where ["png", "jpg"].contains(file.pathExtension.lowercased()) {
            guard let info = ImageStore.libraryInfo(at: file) else { continue }
            let created = (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            let creation = Creation(
                createdAt: created,
                operation: info.tag.operation,
                title: String(localized: "Restored"),
                prompt: nil,
                imageFileName: file.lastPathComponent,
                pixelWidth: info.size.width,
                pixelHeight: info.size.height,
                source: info.tag.source,
                inheritedSourceType: info.tag.inheritedSourceType
            )
            context.insert(creation)
        }
        do { try context.save() } catch {
            log.error("Couldn't save rebuilt rows: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Moved-aside stores

    private static var corruptFolders: [URL] {
        ((try? FileManager.default.contentsOfDirectory(
            at: supportDirectory, includingPropertiesForKeys: [.creationDateKey], options: []
        )) ?? []).filter { $0.lastPathComponent.hasPrefix(corruptPrefix) }
    }

    /// They hold old titles and prompts, so they don't stay forever.
    private static func removeOldCorruptStores() {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        for folder in corruptFolders {
            let created = (try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            if created < cutoff { try? FileManager.default.removeItem(at: folder) }
        }
    }

    /// Delete my data: no copy of the old library stays behind.
    static func removeAllCorruptStores() {
        for folder in corruptFolders { try? FileManager.default.removeItem(at: folder) }
    }

    #if DEBUG
    // `-GLLibraryFault corrupt` overwrites the store with junk before opening;
    // `-GLLibraryFault diskFull` fails both attempts like a full disk would,
    // which must not move the store aside.
    private static var debugDiskFullError: NSError {
        NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
    }

    private static func debugCorruptStore() {
        guard FileManager.default.fileExists(atPath: storeFiles[0].path) else { return }
        for file in storeFiles.dropFirst() { try? FileManager.default.removeItem(at: file) }
        try? Data(repeating: 0x2A, count: 8192).write(to: storeFiles[0])
    }
    #endif
}
