import SwiftUI

/// The floating bar of select mode in My Works: how many are picked (with
/// a little stack of the last ones), a hint when one helps, and what she
/// can do with them. Liquid Glass on iOS 26, frosted before.
struct LibrarySelectionBar: View {
    enum Action: Hashable {
        case share, save, favorite, unfavorite, collage, delete
        case restore, deleteNow
    }

    let count: Int
    /// Picked pictures whose files are there, for the collage maker.
    let collageCount: Int
    let isRecentlyDeleted: Bool
    let allFavorite: Bool
    let isWorking: Bool
    /// File names of the last few picked, oldest first.
    let stack: [String]
    let perform: (Action) -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var actions: [Action] {
        isRecentlyDeleted
            ? [.restore, .deleteNow]
            : [.share, .save, allFavorite ? .unfavorite : .favorite, .collage, .delete]
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular && !dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 16) {
                    header
                    buttons
                        .frame(maxWidth: isRecentlyDeleted ? 260 : 440)
                        // The buttons get their room first; the header wraps.
                        .layoutPriority(1)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    header
                    buttons
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background {
            // Frosted material alone is thin over bright thumbnails.
            if #available(iOS 26.0, *) {
                Color.clear
            } else {
                RoundedRectangle.card.fill(Palette.surface.opacity(0.55))
            }
        }
        .liquidGlass(in: RoundedRectangle.card, tint: Palette.surface.opacity(0.4))
        .shadow(color: Palette.shadow, radius: 16, y: 8)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : Motion.press, value: count)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : Motion.press, value: allFavorite)
        .animation(.easeInOut(duration: 0.2), value: isWorking)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            SelectionStack(fileNames: stack)
            VStack(alignment: .leading, spacing: 1) {
                if isWorking {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Preparing…")
                    }
                    .font(.cardTitle)
                    .foregroundStyle(Palette.textPrimary)
                } else if count == 0 {
                    Text(Platform.isMac ? "Click or drag across creations to select them."
                                        : "Tap or swipe across creations to select them.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.textSecondary)
                } else {
                    Text("\(count) selected")
                        .font(.cardTitle)
                        .foregroundStyle(Palette.textPrimary)
                        .contentTransition(.numericText(value: Double(count)))
                    if let hint {
                        Text(hint)
                            .font(.legibleCaption)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Why Collage is dimmed, when it is.
    private var hint: LocalizedStringKey? {
        guard !isRecentlyDeleted else { return nil }
        if collageCount == CollageModel.minPhotos - 1 { return "Select one more to make a collage." }
        if collageCount > CollageModel.maxPhotos { return "A collage takes up to \(CollageModel.maxPhotos) photos." }
        return nil
    }

    // MARK: Buttons

    /// One-line labels if they all fit, then labels broken between words,
    /// then icons (named in VoiceOver, the large content viewer and the
    /// pointer's tooltip): a label is never cut or split inside a word.
    @ViewBuilder
    private var buttons: some View {
        if dynamicTypeSize.isAccessibilitySize {
            row(.icon)
        } else {
            ViewThatFits(in: .horizontal) {
                row(.oneLine)
                row(.twoLines)
                row(.icon)
            }
        }
    }

    private func row(_ style: BarButton.Style) -> some View {
        ButtonRowLayout(spacing: 2) {
            ForEach(actions, id: \.slot) { action in
                BarButton(title: action.title, accessibilityLabel: action.accessibilityLabel,
                          systemImage: action.systemImage, isDestructive: action.isDestructive, style: style) {
                    perform(action)
                }
                .disabled(!isEnabled(action))
                .keyboardShortcut(action.isDestructive && Platform.isMac ? KeyboardShortcut(.delete, modifiers: []) : nil)
            }
        }
    }

    private func isEnabled(_ action: Action) -> Bool {
        guard count > 0, !isWorking else { return false }
        if action == .collage {
            return (CollageModel.minPhotos...CollageModel.maxPhotos).contains(collageCount)
        }
        return true
    }
}

extension LibrarySelectionBar.Action {
    /// Its place in the bar; Favorite and Unfavorite share one, so the
    /// button stays put while its symbol swaps.
    var slot: Int {
        switch self {
        case .share, .restore: return 0
        case .save, .deleteNow: return 1
        case .favorite, .unfavorite: return 2
        case .collage: return 3
        case .delete: return 4
        }
    }

    var title: String {
        switch self {
        case .share: return String(localized: "Share")
        case .save: return String(localized: "Save")
        case .favorite: return String(localized: "Favorite")
        case .unfavorite: return String(localized: "Unfavorite")
        case .collage: return String(localized: "Collage")
        case .delete: return String(localized: "Delete")
        case .restore: return String(localized: "Restore")
        case .deleteNow: return String(localized: "Delete now")
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .save: return String(localized: "Save to Photos")
        case .favorite: return String(localized: "Add to favorites")
        case .unfavorite: return String(localized: "Remove from favorites")
        case .collage: return String(localized: "Make a collage")
        case .share, .delete, .restore, .deleteNow: return title
        }
    }

    var systemImage: String {
        switch self {
        case .share: return "square.and.arrow.up"
        case .save: return "square.and.arrow.down"
        case .favorite: return "heart"
        case .unfavorite: return "heart.slash"
        case .collage: return "rectangle.3.offgrid"
        case .delete, .deleteNow: return "trash"
        case .restore: return "arrow.uturn.backward"
        }
    }

    var isDestructive: Bool {
        self == .delete || self == .deleteNow
    }
}

// MARK: - Pieces

/// An icon over its name, in an equal column of the bar.
private struct BarButton: View {
    enum Style {
        case oneLine, twoLines, icon
    }

    let title: String
    let accessibilityLabel: String
    let systemImage: String
    let isDestructive: Bool
    let style: Style
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .semibold))
                    // Same height for every symbol, so the names line up.
                    .frame(height: 24)
                    .contentTransition(.symbolEffect(.replace))
                switch style {
                case .oneLine:
                    Text(verbatim: title)
                        .lineLimit(1)
                        .fixedSize()
                case .twoLines:
                    Text(verbatim: Self.twoLines(title))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .fixedSize()
                case .icon:
                    EmptyView()
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isDestructive ? Palette.danger : Palette.textPrimary)
            .opacity(isEnabled ? 1 : 0.35)
            .padding(.horizontal, 4)
            .padding(.top, 4)
            .frame(minWidth: 44, maxWidth: .infinity, minHeight: 48, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .macHoverLift(scale: 1.04)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityShowsLargeContentViewer {
            Label(title, systemImage: systemImage)
        }
        .macHelp(Text(verbatim: accessibilityLabel))
    }

    /// "Ajouter aux favoris" → "Ajouter aux⏎favoris": two lines as even as
    /// the words allow, broken only between words. One word stays as it is.
    static func twoLines(_ text: String) -> String {
        let words = text.split(separator: " ")
        guard words.count > 1 else { return text }
        var best = text
        var longest = Int.max
        for cut in 1..<words.count {
            let first = words[..<cut].joined(separator: " ")
            let second = words[cut...].joined(separator: " ")
            if max(first.count, second.count) < longest {
                longest = max(first.count, second.count)
                best = first + "\n" + second
            }
        }
        return best
    }
}

/// The bar's buttons side by side, filling the row: in equal columns when
/// the widest fits one, otherwise each as wide as it needs plus an equal
/// share of the rest. Its ideal width is what the buttons need, so in
/// `ViewThatFits` a row that doesn't fit gives way to the next choice
/// instead of truncating a label.
private struct ButtonRowLayout: Layout {
    var spacing: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let needed = sizes.reduce(0) { $0 + $1.width } + spacing * CGFloat(subviews.count - 1)
        let offered = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? needed
        return CGSize(width: max(offered, needed), height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let count = CGFloat(subviews.count)
        let natural = subviews.map { $0.sizeThatFits(.unspecified).width }
        let room = bounds.width - spacing * (count - 1)
        let leftover = max(0, room - natural.reduce(0, +)) / count
        let widths = (natural.max() ?? 0) <= room / count
            ? Array(repeating: room / count, count: subviews.count)
            : natural.map { $0 + leftover }
        var x = bounds.minX
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: widths[index], height: bounds.height))
            x += widths[index] + spacing
        }
    }
}

/// The last few picked, fanned like a tiny stack of prints.
private struct SelectionStack: View {
    let fileNames: [String]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if fileNames.isEmpty {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .transition(.opacity)
            }
            ForEach(Array(fileNames.enumerated()), id: \.element) { index, name in
                // 0 is the newest, on top and straight.
                let depth = fileNames.count - 1 - index
                ThumbnailView(fileName: name)
                    .frame(width: 30, height: 30)
                    .clipShape(.tag)
                    .overlay(RoundedRectangle.tag.strokeBorder(Palette.white, lineWidth: 1.5))
                    .shadow(color: Palette.ink.opacity(0.2), radius: 2, y: 1)
                    .rotationEffect(.degrees(depth == 0 ? 0 : depth == 1 ? -9 : 8))
                    .offset(x: CGFloat(depth) * -4)
                    .zIndex(Double(index))
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .frame(width: 44, height: 44)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : Motion.bouncy, value: fileNames)
        .accessibilityHidden(true)
    }
}
