import Foundation

/// Share exports, invite cards and picked video copies live in tmp. Most are
/// deleted when they're done with, but a crash or a force quit can leave them
/// behind, and a video can be gigabytes, so old ones are swept at launch.
enum TemporaryFiles {
    /// Name prefixes of the files the app writes to tmp.
    static let ownedPrefixes = ["glowlit-", "Glowlit-", "creation-"]

    /// Deletes app-owned tmp files last changed more than `age` ago. Runs off
    /// the main actor: listing and deleting big files can take a moment.
    static func sweep(olderThan age: TimeInterval = 24 * 60 * 60) async {
        await Task.detached(priority: .utility) {
            let manager = FileManager.default
            let cutoff = Date().addingTimeInterval(-age)
            let files = (try? manager.contentsOfDirectory(at: manager.temporaryDirectory,
                                                          includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for file in files where ownedPrefixes.contains(where: file.lastPathComponent.hasPrefix) {
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if let modified, modified < cutoff {
                    try? manager.removeItem(at: file)
                }
            }
        }.value
    }
}
