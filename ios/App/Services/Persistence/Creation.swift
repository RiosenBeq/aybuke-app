import Foundation
import SwiftData
import AppCore

/// A saved result in the user's library. Pixels live on disk (`ImageStore`);
/// the model only stores metadata.
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
    /// Hearted in My Works.
    var isFavorite: Bool = false
    /// Who made the pixels when it wasn't Glowlit's own pipeline
    /// (`imagePlaygroundSource`); `nil` for everything else.
    var source: String? = nil

    /// Stored for images that only received manual adjustments (no AI).
    static let manualEditRaw = "adjust"
    /// Made by Apple's Image Playground sheet.
    static let imagePlaygroundSource = "imagePlayground"

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        operation: AIOperation?,
        title: String,
        prompt: String?,
        imageFileName: String,
        pixelWidth: Int,
        pixelHeight: Int,
        source: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.operationRaw = operation?.rawValue ?? Self.manualEditRaw
        self.title = title
        self.prompt = prompt
        self.imageFileName = imageFileName
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.source = source
    }

    /// The AI operation behind this image; `nil` when it was only adjusted
    /// by hand (so exports make no AI claim).
    var operation: AIOperation? { AIOperation(rawValue: operationRaw) }

    var isFromImagePlayground: Bool { source == Self.imagePlaygroundSource }

    var kindTitle: String {
        if isFromImagePlayground { return String(localized: "Made with Image Playground") }
        return operation.map { L10n.core($0.displayName) } ?? String(localized: "Adjusted")
    }
}
