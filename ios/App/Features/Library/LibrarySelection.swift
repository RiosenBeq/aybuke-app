import SwiftUI

/// The creations picked in select mode, in the order she picked them: a
/// collage lays its photos out in that order, like the photo picker does.
struct LibrarySelection: Equatable {
    private(set) var order: [UUID] = []
    private var members: Set<UUID> = []

    var count: Int { order.count }
    var isEmpty: Bool { order.isEmpty }

    func contains(_ id: UUID) -> Bool {
        members.contains(id)
    }

    mutating func toggle(_ id: UUID) {
        self = applying([id], selected: !contains(id))
    }

    /// Exactly these, in this order.
    mutating func set(_ ids: [UUID]) {
        self = LibrarySelection().applying(ids, selected: true)
    }

    mutating func removeAll() {
        self = LibrarySelection()
    }

    /// Drops what's no longer on screen (moved to Recently deleted,
    /// unfavorited in Favorites…), so an action only touches what she sees.
    mutating func keepOnly(_ ids: Set<UUID>) {
        guard !members.isSubset(of: ids) else { return }
        members.formIntersection(ids)
        order.removeAll { !members.contains($0) }
    }

    /// This selection with `ids` added (new ones join in their order) or taken out.
    func applying(_ ids: [UUID], selected: Bool) -> LibrarySelection {
        var next = self
        for id in ids {
            if selected {
                if next.members.insert(id).inserted { next.order.append(id) }
            } else if next.members.remove(id) != nil {
                next.order.removeAll { $0 == id }
            }
        }
        return next
    }
}

/// Drag to select: where each tile is, and the drag in progress. A plain
/// class kept in `@State`, so recording frames (they arrive as tiles appear
/// while she scrolls) never redraws the screen.
@MainActor
final class LibraryDragTracker {
    struct Run {
        /// The tiles in grid order when the drag began, and where each one is.
        let order: [UUID]
        let positions: [UUID: Int]
        let anchor: Int
        var current: Int
        /// From an unselected tile the drag selects; from a selected one it deselects.
        let selects: Bool
        let baseline: LibrarySelection

        /// Every tile from the first one to the one under the finger, in
        /// reading order (like Photos), changed; the rest as they were, so
        /// dragging back gives tiles back.
        var selection: LibrarySelection {
            let passed = anchor <= current
                ? Array(order[anchor...current])
                : Array(order[current...anchor].reversed())
            return baseline.applying(passed, selected: selects)
        }
    }

    enum Phase {
        case idle
        /// Started up or down: a scroll, left alone until the finger lifts.
        case scrolling
        case selecting(Run)
    }

    /// Tiles on screen, in the grid's coordinate space.
    var frames: [UUID: CGRect] = [:]
    var phase = Phase.idle
    /// When the last drag-select ended: lifting the finger over a tile
    /// isn't a tap on it.
    var endedAt = Date.distantPast

    var isSelecting: Bool {
        if case .selecting = phase { return true }
        return false
    }

    /// The tile under `point`. Half of the grid's 6 pt gap counts as the
    /// tile beside it, so a finger between two tiles doesn't drop out.
    func tile(at point: CGPoint) -> UUID? {
        frames.first { $0.value.insetBy(dx: -3, dy: -3).contains(point) }?.key
    }
}
