import Foundation
import SwiftData
import AppCore

/// The live library model. Changing a stored property means a new frozen
/// schema version plus a migration stage in `GlowlitMigrationPlan`.
typealias Creation = CreationSchemaV3.Creation

enum CreationSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }
    static var models: [any PersistentModel.Type] { [Creation.self] }

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
        /// Who made the pixels when it wasn't Aybuke's own pipeline
        /// (`imagePlaygroundSource`); `nil` for everything else.
        var source: String? = nil
        /// The IPTC marking the edited photo already carried (a `DigitalSourceType`
        /// raw value), so the copy keeps it on export.
        var sourceTypeRaw: String? = nil
        /// Set when she deletes it: the creation waits in "Recently deleted"
        /// (`RecentlyDeleted` has the rules) before it's removed for good.
        var deletedAt: Date? = nil

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
            source: String? = nil,
            inheritedSourceType: DigitalSourceType? = nil
        ) {
            self.sourceTypeRaw = inheritedSourceType?.rawValue
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
    }
}

extension CreationSchemaV3.Creation {
    /// The AI operation behind this image; `nil` when it was only adjusted
    /// by hand (so exports make no AI claim).
    var operation: AIOperation? { AIOperation(rawValue: operationRaw) }

    var isFromImagePlayground: Bool { source == Self.imagePlaygroundSource }

    var isInRecentlyDeleted: Bool { deletedAt != nil }

    /// Export markings. Apple made Image Playground pictures, so they're
    /// marked as AI-generated but never carry Aybuke's mark.
    var provenance: Provenance {
        Creation.provenance(operation: operation, source: source, inheritedSourceType: sourceTypeRaw.flatMap(DigitalSourceType.init(rawValue:)))
    }

    static func provenance(operation: AIOperation?, source: String?, inheritedSourceType: DigitalSourceType? = nil) -> Provenance {
        guard source == imagePlaygroundSource else {
            return Provenance(operation: operation, inheritedSourceType: inheritedSourceType)
        }
        return Provenance(inheritedSourceType: DigitalSourceType.strongest(.trainedAlgorithmicMedia, inheritedSourceType))
    }

    var kindTitle: String {
        if isFromImagePlayground { return String(localized: "Made with Image Playground") }
        return operation.map { L10n.core($0.displayName) } ?? String(localized: "Adjusted")
    }
}
