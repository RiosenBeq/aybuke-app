import Foundation

// "My filters": Adjust settings she saved under her own name, to put on any
// photo with one tap. Kept on this device only (never synced, never sent),
// at most 12, and removed by Delete my data.

/// One saved filter: every slider and the vibe it was built on.
public struct MyFilter: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var settings: AdjustmentSettings
    /// The vibe her values started from, so picking another vibe on top
    /// replaces it cleanly (`AdjustVibe.applied(to:replacing:)`).
    public var vibeID: String?

    public init(id: UUID = UUID(), name: String, settings: AdjustmentSettings, vibeID: String? = nil) {
        self.id = id
        self.name = name
        self.settings = settings
        self.vibeID = vibeID
    }

    public var vibe: AdjustVibe? { vibeID.flatMap(AdjustVibes.preset(id:)) }
}

/// Her saved filters, newest first.
public struct MyFilterShelf: Codable, Equatable, Sendable {
    public static let limit = 12
    public static let maxNameLength = 24

    public private(set) var filters: [MyFilter]

    public init(filters: [MyFilter] = []) {
        self.filters = Array(filters.prefix(Self.limit))
    }

    public var isFull: Bool { filters.count >= Self.limit }

    public enum SaveResult: Equatable, Sendable {
        case saved(MyFilter)
        /// The same values are already saved under this filter.
        case duplicate(MyFilter)
        case full
        case emptyName
        /// Nothing to save: every slider is at rest.
        case neutral
    }

    /// One line, trimmed and at most `maxNameLength` characters; nil when empty.
    public static func cleanName(_ raw: String) -> String? {
        let line = raw.components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }
        return String(line.prefix(maxNameLength)).trimmingCharacters(in: .whitespaces)
    }

    /// The first name like "My filter 2" that isn't taken; `base` is the
    /// localized "My filter".
    public func suggestedName(base: String) -> String {
        let taken = Set(filters.map { $0.name.lowercased() })
        var number = filters.count + 1
        while taken.contains("\(base) \(number)".lowercased()) { number += 1 }
        return "\(base) \(number)"
    }

    /// The saved filter with exactly these values, if any.
    public func filter(matching settings: AdjustmentSettings) -> MyFilter? {
        filters.first { $0.settings == settings.clamped() }
    }

    @discardableResult
    public mutating func save(name: String, settings: AdjustmentSettings, vibeID: String?, id: UUID = UUID()) -> SaveResult {
        let settings = settings.clamped()
        guard !settings.isNeutral else { return .neutral }
        if let existing = filter(matching: settings) { return .duplicate(existing) }
        guard !isFull else { return .full }
        guard let name = Self.cleanName(name) else { return .emptyName }
        let filter = MyFilter(id: id, name: name, settings: settings, vibeID: vibeID)
        filters.insert(filter, at: 0)
        return .saved(filter)
    }

    /// False (and no change) for an empty name or an unknown filter.
    @discardableResult
    public mutating func rename(_ id: UUID, to name: String) -> Bool {
        guard let name = Self.cleanName(name), let index = filters.firstIndex(where: { $0.id == id }) else { return false }
        filters[index].name = name
        return true
    }

    public mutating func delete(_ id: UUID) {
        filters.removeAll { $0.id == id }
    }

    // MARK: Storage

    public func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    /// What was stored; a damaged payload reads as no filters, and names
    /// and values are cleaned up on the way in.
    public static func decode(_ data: Data?) -> MyFilterShelf {
        guard let data, let shelf = try? JSONDecoder().decode(MyFilterShelf.self, from: data) else { return MyFilterShelf() }
        let cleaned = shelf.filters.compactMap { filter -> MyFilter? in
            guard let name = cleanName(filter.name) else { return nil }
            var filter = filter
            filter.name = name
            filter.settings = filter.settings.clamped()
            return filter.settings.isNeutral ? nil : filter
        }
        return MyFilterShelf(filters: cleaned)
    }
}

/// Stored by slider name: a slider added later reads as at rest, and one
/// that's gone is ignored.
extension AdjustmentSettings: Codable {
    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        var settings = AdjustmentSettings.neutral
        for parameter in AdjustmentParameter.allCases {
            if let value = try container.decodeIfPresent(Double.self, forKey: Key(parameter.rawValue)), value.isFinite {
                settings[parameter] = value
            }
        }
        self = settings.clamped()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        for parameter in AdjustmentParameter.allCases {
            try container.encode(self[parameter], forKey: Key(parameter.rawValue))
        }
    }
}
