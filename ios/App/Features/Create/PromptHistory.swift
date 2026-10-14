import Foundation
import Observation
import AppCore

/// Create's recent prompts and the draft she's still writing. Both live only
/// in this device's preferences: never synced, never in the widgets' shared
/// container, and erased by Delete my data.
@MainActor
@Observable
final class PromptHistory {
    nonisolated static let recentKey = "create.recentPrompts.v1"
    nonisolated static let draftKey = "create.draft.v1"

    private(set) var recent: [String] = []
    /// What's in the prompt box, so it survives leaving the tab or the app.
    var draft = "" {
        didSet { if draft != oldValue { defaults?.set(draft, forKey: Self.draftKey) } }
    }

    /// `nil` keeps everything in memory (screenshot scenes).
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private var list = RecentPrompts()

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        list = RecentPrompts(defaults?.stringArray(forKey: Self.recentKey) ?? [])
        recent = list.items
        draft = defaults?.string(forKey: Self.draftKey) ?? ""
        guard !recent.isEmpty else { return }
        // A prompt today's safety filters would stop is never offered again.
        // Checked off the launch path: the filters compile on first use.
        let stored = recent
        Task { [weak self] in
            let blocked = await Task.detached(priority: .utility) { stored.filter { !Self.isAllowed($0) } }.value
            guard let self, !blocked.isEmpty else { return }
            self.update { list in
                for prompt in blocked { list.remove(prompt) }
            }
        }
    }

    /// Called when a Create job starts, after the safety check passed.
    func record(_ prompt: String) {
        guard Self.isAllowed(prompt) else { return }
        update { $0.add(prompt) }
    }

    func remove(_ prompt: String) {
        update { $0.remove(prompt) }
    }

    func clear() {
        update { $0.removeAll() }
    }

    /// Delete my data: the stored keys are removed with the other settings.
    func reset() {
        list = RecentPrompts()
        recent = []
        draft = ""
        defaults?.removeObject(forKey: Self.recentKey)
        defaults?.removeObject(forKey: Self.draftKey)
    }

    #if DEBUG
    /// Screenshot scenes: a fixed list, kept in memory only.
    func seedForScreenshots(_ prompts: [String]) {
        list = RecentPrompts(prompts)
        recent = list.items
    }
    #endif

    private func update(_ change: (inout RecentPrompts) -> Void) {
        change(&list)
        guard list.items != recent else { return }
        recent = list.items
        if recent.isEmpty {
            defaults?.removeObject(forKey: Self.recentKey)
        } else {
            defaults?.set(recent, forKey: Self.recentKey)
        }
    }

    private nonisolated static func isAllowed(_ prompt: String) -> Bool {
        if case .blocked = ContentPolicy.evaluate(prompt, operation: .textToImage) { return false }
        return true
    }
}
