import SwiftUI

// Layouts for the Mac's wider pages. They work on any platform, but only the
// Mac uses them, so iPhone and iPad keep their own layouts.

/// Where the editor's tool panel sits: under the photo (iPhone, iPad, a
/// narrow Mac window) or in the Mac's inspector beside it.
enum EditorPanelPlacement {
    case bar, inspector
}

extension EnvironmentValues {
    @Entry var editorPanelPlacement: EditorPanelPlacement = .bar
}

/// A row of chips: it scrolls sideways under the photo, and wraps onto more
/// lines in the Mac's inspector, where a mouse can't swipe a row.
struct ChipRow<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder let content: Content
    @Environment(\.editorPanelPlacement) private var placement

    var body: some View {
        if placement == .inspector {
            FlowLayout(spacing: spacing, lineSpacing: spacing) {
                content
            }
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: spacing) {
                    content
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

/// Tiles in rows of equal columns: as many as fit at `minimumWidth`, then
/// evened out so the last row isn't a lone tile (eleven tools at six across
/// make rows of six and five, not ten and one). Every tile in a row gets the
/// row's height, so cards line up.
struct BalancedGrid: Layout {
    var minimumWidth: CGFloat
    var spacing: CGFloat = 12
    var maxColumns = 8

    func columns(fitting width: CGFloat, count: Int) -> Int {
        guard count > 0 else { return 1 }
        let fitting = max(1, min(maxColumns, Int((width + spacing) / (minimumWidth + spacing))))
        let rows = (count + fitting - 1) / fitting
        return max(1, (count + rows - 1) / rows)
    }

    private func metrics(width: CGFloat, subviews: Subviews) -> (columns: Int, columnWidth: CGFloat, rowHeights: [CGFloat]) {
        let columns = columns(fitting: width, count: subviews.count)
        let columnWidth = max((width - CGFloat(columns - 1) * spacing) / CGFloat(columns), 0)
        let proposal = ProposedViewSize(width: columnWidth, height: nil)
        let rowHeights = stride(from: 0, to: subviews.count, by: columns).map { start in
            subviews[start..<min(start + columns, subviews.count)].map { $0.sizeThatFits(proposal).height }.max() ?? 0
        }
        return (columns, columnWidth, rowHeights)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? minimumWidth * 3 + spacing * 2
        let layout = metrics(width: width, subviews: subviews)
        let height = layout.rowHeights.reduce(0, +) + CGFloat(max(layout.rowHeights.count - 1, 0)) * spacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = metrics(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for (row, height) in layout.rowHeights.enumerated() {
            for column in 0..<layout.columns {
                let index = row * layout.columns + column
                guard index < subviews.count else { break }
                let x = bounds.minX + CGFloat(column) * (layout.columnWidth + spacing)
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                      proposal: ProposedViewSize(width: layout.columnWidth, height: height))
            }
            y += height + spacing
        }
    }
}

/// Chips that wrap onto more lines instead of scrolling sideways: for the
/// Mac's inspector and wide forms, where a mouse can't swipe a row.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    private func rows(width: CGFloat, subviews: Subviews) -> [[(index: Int, size: CGSize)]] {
        var rows: [[(index: Int, size: CGSize)]] = [[]]
        var lineWidth: CGFloat = 0
        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)
            size.width = min(size.width, width)
            if lineWidth > 0, lineWidth + spacing + size.width > width {
                rows.append([])
                lineWidth = 0
            }
            lineWidth += (lineWidth > 0 ? spacing : 0) + size.width
            rows[rows.count - 1].append((index, size))
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let lines = rows(width: width, subviews: subviews)
        var height: CGFloat = 0
        var usedWidth: CGFloat = 0
        for (index, line) in lines.enumerated() {
            let lineHeight: CGFloat = line.map(\.size.height).max() ?? 0
            height += lineHeight + (index > 0 ? lineSpacing : 0)
            let lineWidth: CGFloat = line.map(\.size.width).reduce(0, +) + CGFloat(max(line.count - 1, 0)) * spacing
            usedWidth = max(usedWidth, lineWidth)
        }
        return CGSize(width: proposal.width ?? usedWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in rows(width: bounds.width, subviews: subviews) {
            let height = line.map(\.size.height).max() ?? 0
            var x = bounds.minX
            for item in line {
                subviews[item.index].place(at: CGPoint(x: x, y: y + (height - item.size.height) / 2), anchor: .topLeading,
                                           proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += height + lineSpacing
        }
    }
}
