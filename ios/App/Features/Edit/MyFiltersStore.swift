import Foundation
import Observation
import AppCore

/// "My filters": the Adjust looks she saved under her own names, newest
/// first. Only in this device's preferences: never synced, never in the
/// widgets' shared container, and erased by Delete my data.
@MainActor
@Observable
final class MyFiltersStore {
    nonisolated static let key = "adjust.myFilters.v1"

    private(set) var shelf: MyFilterShelf
    /// `nil` keeps everything in memory (screenshot scenes).
    @ObservationIgnored private let defaults: UserDefaults?

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        shelf = MyFilterShelf.decode(defaults?.data(forKey: Self.key))
    }

    var filters: [MyFilter] { shelf.filters }

    @discardableResult
    func save(name: String, settings: AdjustmentSettings, vibe: AdjustVibe?) -> MyFilterShelf.SaveResult {
        let result = shelf.save(name: name, settings: settings, vibeID: vibe?.id)
        persist()
        return result
    }

    @discardableResult
    func rename(_ filter: MyFilter, to name: String) -> Bool {
        let renamed = shelf.rename(filter.id, to: name)
        persist()
        return renamed
    }

    func delete(_ filter: MyFilter) {
        shelf.delete(filter.id)
        persist()
    }

    /// Delete my data.
    func reset() {
        shelf = MyFilterShelf()
        defaults?.removeObject(forKey: Self.key)
    }

    #if DEBUG
    /// Screenshot scenes: a few filters, kept in memory only.
    func seedForScreenshots() {
        var shelf = MyFilterShelf()
        var film = AdjustVibes.preset(id: "analog")!.applied(to: .neutral, replacing: nil)
        film.grain = 0.45
        shelf.save(name: String(localized: "Film days", comment: "Sample name of a saved filter in screenshots"), settings: film, vibeID: "analog")
        var beach = AdjustVibes.preset(id: "golden")!.applied(to: .neutral, replacing: nil)
        beach.brightness = 0.06
        shelf.save(name: String(localized: "Beach glow", comment: "Sample name of a saved filter in screenshots"), settings: beach, vibeID: "golden")
        self.shelf = shelf
    }
    #endif

    private func persist() {
        guard let defaults else { return }
        if shelf.filters.isEmpty {
            defaults.removeObject(forKey: Self.key)
        } else if let data = shelf.encoded() {
            defaults.set(data, forKey: Self.key)
        }
    }
}
