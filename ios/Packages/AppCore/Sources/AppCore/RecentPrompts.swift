import Foundation

/// Create's recent prompts: the last ones she made pictures with, newest
/// first. The app keeps them only on her device (never synced) and she can
/// clear them.
public struct RecentPrompts: Equatable, Sendable {
    public static let limit = 10

    public private(set) var items: [String] = []

    /// Restores a stored list (newest first), cleaned up as if each prompt
    /// had been added again.
    public init(_ stored: [String] = []) {
        for prompt in stored.reversed() { add(prompt) }
    }

    /// Moves `prompt` to the front. The same text with different case or
    /// spacing is kept once, as last typed.
    public mutating func add(_ prompt: String) {
        let clean = PromptBuilder.sanitize(prompt)
        guard !clean.isEmpty else { return }
        items.removeAll { Self.matches($0, clean) }
        items.insert(clean, at: 0)
        if items.count > Self.limit { items.removeLast(items.count - Self.limit) }
    }

    public mutating func remove(_ prompt: String) {
        let clean = PromptBuilder.sanitize(prompt)
        items.removeAll { Self.matches($0, clean) }
    }

    public mutating func removeAll() {
        items = []
    }

    static func matches(_ lhs: String, _ rhs: String) -> Bool {
        lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }
}
