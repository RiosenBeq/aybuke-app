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
    /// so no AI provenance is claimed.
    static func encode(_ image: UIImage, operation: AIOperation?, watermark: Bool = false) -> (data: Data, fileExtension: String)? {
        var normalized = ImageUtilities.normalized(image, maxLongEdge: 4096)
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
        if let operation {
            _ = CGImageMetadataRegisterNamespaceForPrefix(metadata, iptcExtNamespace, iptcExtPrefix, nil)
            _ = CGImageMetadataSetValueWithPath(
                metadata, nil,
                "Iptc4xmpExt:DigitalSourceType" as CFString,
                operation.digitalSourceType.uri as CFString
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
        return (output as Data, usePNG ? "png" : "jpg")
    }

    /// Writes a temporary file for the share sheet.
    static func temporaryFile(for image: UIImage, operation: AIOperation?, watermark: Bool = false) throws -> URL {
        guard let encoded = encode(image, operation: operation, watermark: watermark) else { throw CocoaError(.fileWriteUnknown) }
        let name = "creation-\(Int(Date().timeIntervalSince1970)).\(encoded.fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try encoded.data.write(to: url, options: .atomic)
        return url
    }
}

enum PhotoLibrarySaver {
    enum SaveError: LocalizedError {
        case denied
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .denied: return "Allow photo access in Settings to save your creations."
            case .encodingFailed: return "Couldn't prepare the image. Please try again."
            }
        }
    }

    static func save(_ image: UIImage, operation: AIOperation?, watermark: Bool = false) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw SaveError.denied }
        guard let encoded = ImageExporter.encode(image, operation: operation, watermark: watermark) else { throw SaveError.encodingFailed }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: encoded.data, options: nil)
        }
    }
}

/// Small corner wordmark on free-tier exports — a gentle viral loop. Paid
/// exports never carry it, and the in-app preview never shows it.
enum Watermark {
    static func apply(to image: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = !ImageUtilities.hasAlpha(image)
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
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
            text.draw(at: CGPoint(x: image.size.width - size.width - margin, y: image.size.height - size.height - margin),
                      withAttributes: attributes)
        }
    }
}
