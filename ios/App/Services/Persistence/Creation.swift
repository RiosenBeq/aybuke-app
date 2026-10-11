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

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        operation: AIOperation,
        title: String,
        prompt: String?,
        imageFileName: String,
        pixelWidth: Int,
        pixelHeight: Int
    ) {
        self.id = id
        self.createdAt = createdAt
        self.operationRaw = operation.rawValue
        self.title = title
        self.prompt = prompt
        self.imageFileName = imageFileName
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    var operation: AIOperation { AIOperation(rawValue: operationRaw) ?? .textToImage }

    var aspectRatio: CGFloat {
        pixelHeight > 0 ? CGFloat(pixelWidth) / CGFloat(pixelHeight) : 1
    }
}
