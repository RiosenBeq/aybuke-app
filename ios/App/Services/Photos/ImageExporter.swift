import UIKit
import ImageIO
import Photos
import UniformTypeIdentifiers
import AppCore

/// Encodes results with machine-readable AI provenance (IPTC
/// DigitalSourceType in XMP), as expected by the EU AI Act Art. 50 and read by
/// Google, Meta and Adobe "AI info" labels.
enum ImageExporter {
    private static let iptcExtNamespace = "http://iptc.org/std/Iptc4xmpExt/2008-02-29/" as CFString
    private static let iptcExtPrefix = "Iptc4xmpExt" as CFString

    /// `operation == nil` means no AI was involved (manual adjustments only),
    /// so no AI provenance is claimed. `composite`: a cut-out was placed on
    /// another photo.
    static func encode(_ image: UIImage, operation: AIOperation?, watermark: Bool = false, composite: Bool = false) -> (data: Data, fileExtension: String)? {
        encode(image, sourceType: DigitalSourceType.strongest(operation?.digitalSourceType, composite ? .composite : nil), watermark: watermark)
    }

    /// `sourceType == nil` claims no AI. Only this one value is written, so
    /// a source's EXIF and location never reach the file.
    static func encode(_ image: UIImage, sourceType: DigitalSourceType?, watermark: Bool = false) -> (data: Data, fileExtension: String)? {
        var normalized = ImageUtilities.droppingUnusedAlpha(ImageUtilities.normalized(image, maxLongEdge: 4096))
        if watermark {
            normalized = Watermark.apply(to: normalized)
        }
        let usePNG = ImageUtilities.hasAlpha(normalized)
        let type = usePNG ? UTType.png : UTType.jpeg
        guard let cgImage = normalized.cgImage else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else {
            return nil
        }
        let metadata = CGImageMetadataCreateMutable()
        if let sourceType {
            _ = CGImageMetadataRegisterNamespaceForPrefix(metadata, iptcExtNamespace, iptcExtPrefix, nil)
            _ = CGImageMetadataSetValueWithPath(
                metadata, nil,
                "Iptc4xmpExt:DigitalSourceType" as CFString,
                sourceType.uri as CFString
            )
        }
        _ = CGImageMetadataSetValueWithPath(
            metadata, nil,
            "xmp:CreatorTool" as CFString,
            (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "App") as CFString
        )
        let options = [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary
        CGImageDestinationAddImageAndMetadata(destination, cgImage, metadata, options)
        guard CGImageDestinationFinalize(destination) else { return nil }
        #if DEBUG
        // There's no app test target, so the ImageIO round trip is checked here.
        assert(digitalSourceType(in: output as Data) == sourceType, "The exported file lost its IPTC DigitalSourceType")
        #endif
        return (output as Data, usePNG ? "png" : "jpg")
    }

    /// The AI marking an image file already carries (IPTC DigitalSourceType
    /// in its XMP), so re-edits keep it. Other values, such as a camera's
    /// `digitalCapture`, give `nil`.
    static func digitalSourceType(in data: Data) -> DigitalSourceType? {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
            let value = CGImageMetadataCopyStringValueWithPath(metadata, nil, "Iptc4xmpExt:DigitalSourceType" as CFString)
        else { return nil }
        return DigitalSourceType(uri: value as String)
    }

    /// Writes a temporary file for the share sheet.
    static func temporaryFile(for image: UIImage, operation: AIOperation?, watermark: Bool = false, composite: Bool = false) throws -> URL {
        try temporaryFile(for: image, sourceType: DigitalSourceType.strongest(operation?.digitalSourceType, composite ? .composite : nil), watermark: watermark)
    }

    static func temporaryFile(for image: UIImage, sourceType: DigitalSourceType?, watermark: Bool = false) throws -> URL {
        guard let encoded = encode(image, sourceType: sourceType, watermark: watermark) else { throw CocoaError(.fileWriteUnknown) }
        let name = "creation-\(Int(Date().timeIntervalSince1970)).\(encoded.fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try encoded.data.write(to: url, options: .atomic)
        return url
    }
}

extension ImageExporter {
    /// A "Which vibe?" poll picture as friends will get it, through the
    /// export path: the free mark where an export would have it, upright, at
    /// most 1080 px on the long side, in sRGB on white, a JPEG with no
    /// metadata at all (no EXIF, location, XMP or IPTC: the server would drop
    /// them, but they never leave the device). Its small copy is what "Your
    /// polls" shows. Call it off the main actor.
    static func pollPicture(_ image: UIImage, watermark: Bool) -> (upload: Data, thumbnail: Data)? {
        let target = PollPicture.targetSize(for: ImageUtilities.pixelSize(of: image))
        var picture = srgbDrawing(of: image, size: target)
        if watermark {
            picture = Watermark.apply(to: picture)
        }
        guard let cgImage = picture.cgImage else { return nil }
        var upload: Data?
        for quality in PollPicture.qualities {
            guard let encoded = plainJPEG(cgImage, quality: quality) else { continue }
            upload = encoded
            if encoded.count <= PollPicture.maxBytes { break }
        }
        guard let upload, PollPicture.isAccepted(byteCount: upload.count, size: target) else { return nil }
        let small = srgbDrawing(of: picture, size: PollPicture.thumbnailSize(for: target))
        guard let thumbnail = small.cgImage.flatMap({ plainJPEG($0, quality: 0.8) }) else { return nil }
        return (upload, thumbnail)
    }

    /// Upright, at `size`, colour-matched into sRGB, see-through parts on white.
    private static func srgbDrawing(of image: UIImage, size: PixelSize) -> UIImage {
        let bounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        return ImageUtilities.draw(size: bounds.size, opaque: true, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) { context in
            context.setFillColor(UIColor.white.cgColor)
            context.fill(bounds)
            image.draw(in: bounds)
        }
    }

    /// A JPEG of `cgImage` and nothing else: ImageIO adds an EXIF block and
    /// an IPTC one of its own, which `JPEGMetadata.stripped` takes out.
    private static func plainJPEG(_ cgImage: CGImage, quality: Double) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return JPEGMetadata.stripped(output as Data)
    }
}

enum PhotoLibrarySaver {
    enum SaveError: LocalizedError {
        case denied
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .denied: return String(localized: "Allow photo access in Settings to save your creations.")
            case .encodingFailed: return String(localized: "Couldn't prepare the image. Please try again.")
            }
        }
    }

    static func save(_ image: UIImage, operation: AIOperation?, watermark: Bool = false, composite: Bool = false) async throws {
        try await save(image, sourceType: DigitalSourceType.strongest(operation?.digitalSourceType, composite ? .composite : nil), watermark: watermark)
    }

    static func save(_ image: UIImage, sourceType: DigitalSourceType?, watermark: Bool = false) async throws {
        guard let encoded = ImageExporter.encode(image, sourceType: sourceType, watermark: watermark) else { throw SaveError.encodingFailed }
        try await save(data: encoded.data)
    }

    /// Saves an already encoded image (with its metadata) as it is.
    static func save(data: Data) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw SaveError.denied }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
        }
    }
}

/// Small corner wordmark on free-tier exports — a gentle viral loop. Paid
/// exports never carry it, and the in-app preview never shows it.
enum Watermark {
    /// In the bottom-right corner, inside `insets` (pixels): the edges an
    /// app's own buttons cover, as on the Photo design at TikTok's size.
    static func apply(to image: UIImage, insets: UIEdgeInsets = .zero) -> UIImage {
        ImageUtilities.draw(size: image.size, scale: image.scale, opaque: !ImageUtilities.hasAlpha(image),
                            colorSpace: image.cgImage?.colorSpace) { _ in
            image.draw(at: .zero)
            let fontSize = max(12, image.size.width * 0.032)
            let font = UIFont(name: BrandFont.postScriptName(for: .bold), size: fontSize)
                ?? UIFont.systemFont(ofSize: fontSize, weight: .bold)
            let shadow = NSShadow()
            shadow.shadowColor = UIColor.black.withAlphaComponent(0.35)
            shadow.shadowBlurRadius = fontSize * 0.25
            shadow.shadowOffset = .zero
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white.withAlphaComponent(0.85),
                .shadow: shadow,
            ]
            let text = "\(Brand.name) ✦" as NSString
            let size = text.size(withAttributes: attributes)
            let margin = fontSize * 0.9
            text.draw(at: CGPoint(x: image.size.width - insets.right - size.width - margin,
                                  y: image.size.height - insets.bottom - size.height - margin),
                      withAttributes: attributes)
        }
    }
}
