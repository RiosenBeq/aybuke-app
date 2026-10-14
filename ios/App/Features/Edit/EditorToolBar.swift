import SwiftUI

/// The editor's tools on a floating Liquid Glass bar. Every item keeps a
/// comfortable width and its whole label (no shrinking, no truncation) at
/// any text size and in every language. When they all fit (iPad, the Mac)
/// they share one row; otherwise (iPhone) the bar scrolls, fades where more
/// tools wait, and keeps the chosen tool in view.
struct EditorToolBar: View {
    let tools: [EditorTool]
    let activeTool: EditorTool?
    let onSelect: (EditorTool) -> Void

    /// Room at both ends for the fade, so the first and last tools rest
    /// clear of it and only tools that scroll on pass under it.
    private static let edge: CGFloat = 18

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 2) {
                ForEach(tools) { item($0, fills: true) }
            }
            scrollingRow
        }
        .padding(5)
        // A capsule at the usual size, like the items inside it.
        .liquidGlass(in: RoundedRectangle(cornerRadius: 32), tint: Palette.white.opacity(0.4))
        // Labels grow with Dynamic Type up to AX1; past that, a long press
        // shows the large content viewer, as Apple's own bars do.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private var scrollingRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 2) {
                    ForEach(tools) { item($0, fills: false) }
                }
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, Self.edge, for: .scrollContent)
            .mask {
                HStack(spacing: 0) {
                    LinearGradient(colors: [.black.opacity(0), .black], startPoint: .leading, endPoint: .trailing)
                        .frame(width: Self.edge)
                    Color.black
                    LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: Self.edge)
                }
            }
            .onAppear {
                // A tool opened from elsewhere (Hide faces from the kindness
                // note, a deep link) may sit past the screen's edge.
                if let activeTool { proxy.scrollTo(activeTool, anchor: .center) }
            }
            .onChange(of: activeTool) { _, tool in
                guard let tool else { return }
                withAnimation(.snappy) { proxy.scrollTo(tool, anchor: .center) }
            }
        }
    }

    private func item(_ tool: EditorTool, fills: Bool) -> some View {
        ToolItem(tool: tool, isActive: activeTool == tool, fills: fills) {
            onSelect(tool)
        }
        .id(tool)
    }
}

private struct ToolItem: View {
    let tool: EditorTool
    let isActive: Bool
    let fills: Bool
    let action: () -> Void

    // The room around the label grows with it, so big text never meets the
    // selection's edge (read inside the bar's Dynamic Type cap).
    @ScaledMetric(relativeTo: .caption2) private var sidePadding: CGFloat = 10
    @ScaledMetric(relativeTo: .caption2) private var bottomPadding: CGFloat = 6

    var body: some View {
        // A capsule at the usual size; when big text makes the item taller,
        // the corners stop growing, so they never cut into the label.
        let shape = RoundedRectangle(cornerRadius: 27)
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: tool.symbolName)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(height: 22)
                    .symbolEffect(.bounce, value: isActive)
                Text(tool.shortTitle)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(isActive ? Palette.onPrimary : Palette.textSecondary)
            .padding(.horizontal, sidePadding)
            .padding(.top, 6)
            .padding(.bottom, bottomPadding)
            .frame(minWidth: 64, maxWidth: fills ? .infinity : nil, minHeight: 54)
            .background(isActive ? Palette.primary : Color.clear, in: shape)
            // Blush alone is too faint on the glass to mark the tool.
            .overlay(shape.strokeBorder(isActive ? Palette.ink : Color.clear, lineWidth: 1.5))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        // The short "Cut out" fits the bar; VoiceOver reads it in full.
        .accessibilityLabel(tool == .removeBackground ? String(localized: "Remove background") : tool.title)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityShowsLargeContentViewer {
            Label(tool.shortTitle, systemImage: tool.symbolName)
        }
    }
}
