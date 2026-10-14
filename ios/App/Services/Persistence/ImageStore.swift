import UIKit
import ImageIO
import UniformTypeIdentifiers
import AppCore

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

    /// What a library file says about itself, so a lost database can be
    /// rebuilt without dropping the AI marking or the free-tier mark.
    struct Tag: Equatable {
        var operationRaw: String = Creation.manualEditRaw
        var source: String?
        var inheritedSourceType: DigitalSourceType?

        init(operation: AIOperation?, source: String? = nil, inheritedSourceType: DigitalSourceType? = nil) {
            self.operationRaw = operation?.rawValue ?? Creation.manualEditRaw
            self.source = source
            self.inheritedSourceType = inheritedSourceType
        }

        var operation: AIOperation? { AIOperation(rawValue: operationRaw) }
        var provenance: Provenance { Creation.provenance(operation: operation, source: source, inheritedSourceType: inheritedSourceType) }
    }

    private static let iptcExtNamespace = "http://iptc.org/std/Iptc4xmpExt/2008-02-29/" as CFString
    private static let tagNamespace = "https://glowlit.app/ns/library/1.0/" as CFString

    /// "Unless open" lets a job that finishes after the device locks still
    /// write its file, which stays unreadable until the next unlock. The Mac
    /// uses "until first unlock": FileVault already encrypts its disk, and a
    /// locked screen would otherwise leave My Works blank.
    #if targetEnvironment(macCatalyst)
    private static let fileProtection: Data.WritingOptions = .completeFileProtectionUntilFirstUserAuthentication
    #else
    private static let fileProtection: Data.WritingOptions = .completeFileProtectionUnlessOpen
    #endif

    /// PNG keeps transparency (cut-outs); everything else is stored as JPEG.
    static func save(_ image: UIImage, tag: Tag) throws -> String {
        let image = ImageUtilities.droppingUnusedAlpha(image)
        let usePNG = ImageUtilities.hasAlpha(image)
        let name = UUID().uuidString + (usePNG ? ".png" : ".jpg")
        let data = try encode(image, png: usePNG, tag: tag)
        try data.write(to: url(for: name), options: [.atomic, fileProtection])
        return name
    }

    private static func encode(_ image: UIImage, png: Bool, tag: Tag) throws -> Data {
        let source = image.cgImage == nil || image.imageOrientation != .up ? ImageUtilities.redraw(image, to: ImageUtilities.pixelSize(of: image)) : image
        guard let cgImage = source.cgImage else { throw CocoaError(.fileWriteUnknown) }
        let output = NSMutableData()
        let type = (png ? UTType.png : UTType.jpeg).identifier as CFString
        guard let destination = CGImageDestinationCreateWithData(output, type, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
        let metadata = CGImageMetadataCreateMutable()
        _ = CGImageMetadataRegisterNamespaceForPrefix(metadata, tagNamespace, "glowlit" as CFString, nil)
        _ = CGImageMetadataSetValueWithPath(metadata, nil, "glowlit:operation" as CFString, tag.operationRaw as CFString)
        if let value = tag.source {
            _ = CGImageMetadataSetValueWithPath(metadata, nil, "glowlit:source" as CFString, value as CFString)
        }
        if let value = tag.inheritedSourceType {
            _ = CGImageMetadataSetValueWithPath(metadata, nil, "glowlit:inherited" as CFString, value.rawValue as CFString)
        }
        if let sourceType = tag.provenance.sourceType {
            _ = CGImageMetadataRegisterNamespaceForPrefix(metadata, iptcExtNamespace, "Iptc4xmpExt" as CFString, nil)
            _ = CGImageMetadataSetValueWithPath(metadata, nil, "Iptc4xmpExt:DigitalSourceType" as CFString, sourceType.uri as CFString)
        }
        var properties: [CFString: Any] = [:]
        if !png { properties[kCGImageDestinationLossyCompressionQuality] = 0.92 }
        CGImageDestinationAddImageAndMetadata(destination, cgImage, metadata, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        #if DEBUG
        assert(libraryInfo(in: CGImageSourceCreateWithData(output, nil))?.tag == tag, "The library file lost its tag")
        #endif
        return output as Data
    }

    /// The tag and upright pixel size of a stored file. Files saved before
    /// tags existed carry no marking, so they're treated as AI-made rather
    /// than risk losing a label.
    static func libraryInfo(at url: URL) -> (tag: Tag, size: PixelSize)? {
        libraryInfo(in: CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary))
    }

    private static func libraryInfo(in source: CGImageSource?) -> (tag: Tag, size: PixelSize)? {
        guard let source,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? UInt32) ?? 1
        let size = orientation >= 5 ? PixelSize(width: height, height: width) : PixelSize(width: width, height: height)
        let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil)
        func value(_ path: String) -> String? {
            metadata.flatMap { CGImageMetadataCopyStringValueWithPath($0, nil, path as CFString) as String? }
        }
        guard let operationRaw = value("glowlit:operation") else {
            let marked = value("Iptc4xmpExt:DigitalSourceType").flatMap(DigitalSourceType.init(uri:))
            return (Tag(operation: nil, inheritedSourceType: marked ?? .trainedAlgorithmicMedia), size)
        }
        var tag = Tag(operation: nil, source: value("glowlit:source"),
                      inheritedSourceType: value("glowlit:inherited").flatMap(DigitalSourceType.init(rawValue:)))
        tag.operationRaw = operationRaw
        return (tag, size)
    }

    static func url(for name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    static func load(_ name: String) -> UIImage? {
        UIImage(contentsOfFile: url(for: name).path)
    }

    /// Whether the file is still there. Works while the device is locked:
    /// only reading the pixels needs the file key.
    static func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: name).path)
    }

    /// A small upright bitmap straight from ImageIO, without decoding the
    /// full-size image first. `nil` when the file is missing or unreadable.
    static func downsampled(_ name: String, maxPixel: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let source = CGImageSourceCreateWithURL(url(for: name) as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: thumbnail)
    }

    /// A second file with the same pixels and tag ("Duplicate" in My Works).
    static func duplicate(_ name: String) throws -> String {
        let data = try Data(contentsOf: url(for: name))
        let ext = (name as NSString).pathExtension
        let copy = UUID().uuidString + (ext.isEmpty ? "" : "." + ext)
        try data.write(to: url(for: copy), options: [.atomic, fileProtection])
        return copy
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
        cache.totalCostLimit = 50 * 1024 * 1024
    }

    enum Outcome {
        case image(UIImage)
        /// The file is gone: the tile offers "Remove" instead of staying blank.
        case missing
        /// Still there but unreadable, usually because the device is locked.
        case unreadable
    }

    func thumbnail(for name: String, maxPixel: CGFloat = 480) async -> UIImage? {
        if case .image(let image) = await load(name, maxPixel: maxPixel) { return image }
        return nil
    }

    func load(_ name: String, maxPixel: CGFloat = 480) async -> Outcome {
        if let cached = cache.object(forKey: name as NSString) {
            return .image(cached)
        }
        let outcome = await Task.detached(priority: .utility) { () -> Outcome in
            // ImageIO decodes straight to a small bitmap. preparingThumbnail
            // needed the full-size decode first, and on the Mac its images
            // drew as blank tiles.
            if let image = ImageStore.downsampled(name, maxPixel: maxPixel) { return .image(image) }
            return ImageStore.exists(name) ? .unreadable : .missing
        }.value
        if case .image(let image) = outcome {
            let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
            cache.setObject(image, forKey: name as NSString, cost: cost)
        }
        return outcome
    }

    func remove(_ name: String) {
        cache.removeObject(forKey: name as NSString)
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}
