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

    /// Stored for images that only received manual adjustments (no AI).
    static let manualEditRaw = "adjust"

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        operation: AIOperation?,
        title: String,
        prompt: String?,
        imageFileName: String,
        pixelWidth: Int,
        pixelHeight: Int
    ) {
        self.id = id
        self.createdAt = createdAt
        self.operationRaw = operation?.rawValue ?? Self.manualEditRaw
        self.title = title
        self.prompt = prompt
        self.imageFileName = imageFileName
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    /// The AI operation behind this image; `nil` when it was only adjusted
    /// by hand (so exports make no AI claim).
    var operation: AIOperation? { AIOperation(rawValue: operationRaw) }

    var kindTitle: String { operation?.displayName ?? "Adjusted" }
}
