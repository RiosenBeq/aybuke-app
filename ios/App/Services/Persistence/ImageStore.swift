import UIKit

/// Stores library images in Application Support with file protection, plus a
/// small in-memory thumbnail cache for the grid.
enum ImageStore {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Creations", isDirectory: true)
        if !FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }

    /// PNG keeps transparency (cut-outs); everything else is stored as JPEG.
    static func save(_ image: UIImage) throws -> String {
        let usePNG = ImageUtilities.hasAlpha(image)
        let name = UUID().uuidString + (usePNG ? ".png" : ".jpg")
        guard let data = usePNG ? image.pngData() : image.jpegData(compressionQuality: 0.92) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url(for: name), options: [.atomic, .completeFileProtection])
        return name
    }

    static func url(for name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    static func load(_ name: String) -> UIImage? {
        UIImage(contentsOfFile: url(for: name).path)
    }

    static func delete(_ name: String) {
        try? FileManager.default.removeItem(at: url(for: name))
        ThumbnailCache.shared.remove(name)
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
        ThumbnailCache.shared.removeAll()
    }
}

final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 200
    }

    func thumbnail(for name: String, maxPixel: CGFloat = 480) async -> UIImage? {
        if let cached = cache.object(forKey: name as NSString) {
            return cached
        }
        let image = await Task.detached(priority: .utility) { () -> UIImage? in
            guard let full = ImageStore.load(name) else { return nil }
            let scale = min(1, maxPixel / max(full.size.width, full.size.height))
            let size = CGSize(width: full.size.width * scale, height: full.size.height * scale)
            return full.preparingThumbnail(of: size) ?? full
        }.value
        if let image {
            cache.setObject(image, forKey: name as NSString)
        }
        return image
    }

    func remove(_ name: String) {
        cache.removeObject(forKey: name as NSString)
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}
