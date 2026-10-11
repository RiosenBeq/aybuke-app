// Prints the template/style catalog as JSON for the backend.
// Usage: scripts/export-catalog.sh
import Foundation
import AppCore

struct Recipe: Encodable {
    let id: String
    let title: String
    let isPro: Bool
    let prompt: String
}

let recipes = TemplateCatalog.all.map { Recipe(id: $0.id, title: $0.title, isPro: $0.isPro, prompt: $0.prompt) }
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
let payload: [String: AnyEncodable] = [
    "_comment": AnyEncodable("Generated from ios/Packages/AppCore (TemplateCatalog/StyleCatalog). Do not edit by hand: run scripts/export-catalog.sh."),
    "templates": AnyEncodable(recipes),
    "proStyles": AnyEncodable(StyleCatalog.all.filter(\.isPro).map(\.id)),
]
print(String(data: try encoder.encode(payload), encoding: .utf8)!)

struct AnyEncodable: Encodable {
    let encodeValue: (Encoder) throws -> Void
    init<T: Encodable>(_ value: T) { encodeValue = value.encode }
    func encode(to encoder: Encoder) throws { try encodeValue(encoder) }
}
