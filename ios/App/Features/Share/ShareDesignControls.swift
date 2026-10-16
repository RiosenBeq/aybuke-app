import SwiftUI
import AppCore

// The share composer's design controls, each shown only where it does
// something: sizes for the Photo and the Story card, a background where the
// design has room around the photo, and her own text on the Story card,
// Cover star and Photo strip.

// MARK: - Sizes

/// "Where are you posting?": one row of sizes, the chosen one explained under it.
struct ShareSizeRow: View {
    let sizes: [ShareSize]
    let selected: ShareSize
    let onSelect: (ShareSize) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ShareControlRow(selection: selected) {
                ForEach(sizes) { size in
                    ShareSizeChip(size: size, isSelected: size == selected) {
                        guard size != selected else { return }
                        Haptics.selection()
                        withAnimation(.snappy) { onSelect(size) }
                    }
                    .id(size)
                }
            }
            Text(selected.note)
                .font(.legibleCaption)
                .foregroundStyle(Palette.textSecondary)
                .contentTransition(.opacity)
                .animation(.snappy, value: selected)
        }
    }
}

private struct ShareSizeChip: View {
    let size: ShareSize
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                ShapeGlyph(size: size)
                    .stroke(lineWidth: 1.6)
                    .frame(width: 16, height: 16)
                size.titleText
                    .font(.subheadline.weight(isSelected ? .bold : .semibold))
                if !size.ratio.isEmpty {
                    Text(verbatim: size.ratio)
                        .font(.legibleCaption.weight(.semibold))
                        .monospacedDigit()
                        .opacity(0.7)
                }
            }
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .foregroundStyle(isSelected ? Palette.onPrimary : Palette.textPrimary)
            .background(isSelected ? Palette.primary : Palette.surface, in: .chip)
            .overlay(RoundedRectangle.chip.strokeBorder(isSelected ? Palette.ink : Palette.stroke, lineWidth: isSelected ? 1.5 : 1))
            .selectionPop(isSelected)
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(size.titleText)
        .accessibilityValue(Text(verbatim: size.ratio))
        .accessibilityHint(Text(size.note))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A small outline of the size's shape (a dashed square for the photo's own).
private struct ShapeGlyph: Shape {
    let size: ShareSize

    func path(in rect: CGRect) -> Path {
        guard let pixels = size.pixelSize else {
            return Path(roundedRect: rect.insetBy(dx: 2, dy: 2), cornerRadius: 3)
                .strokedPath(StrokeStyle(lineWidth: 1, dash: [2.5, 2]))
        }
        let fitted = ShareLayout.fit(width: pixels.width, height: pixels.height,
                                     in: CanvasRect(x: rect.minX + 1, y: rect.minY + 1, width: rect.width - 2, height: rect.height - 2))
        return Path(roundedRect: fitted.cgRect, cornerRadius: 2.5)
    }
}

extension ShareSize {
    var titleText: Text {
        switch self {
        case .original: return Text("Original")
        case .story: return Text("Story")
        case .post: return Text("Post", comment: "Share size: an Instagram feed post (4:5)")
        case .square: return Text("Square")
        case .tiktok: return Text(verbatim: "TikTok")
        case .wide: return Text("Wide")
        case .pin: return Text(verbatim: "Pinterest")
        }
    }

    /// Where it fits, under the row.
    var note: LocalizedStringKey {
        switch self {
        case .original: return "Your photo’s own shape"
        case .story: return "Instagram Stories and Reels"
        case .post: return "An Instagram feed post"
        case .square: return "Any feed, and chats"
        case .tiktok: return "TikTok, clear of its buttons and caption"
        case .wide: return "X and other wide screens"
        case .pin: return "A Pinterest pin"
        }
    }
}

// MARK: - Background

/// What fills the room around the photo.
struct ShareBackdropRow: View {
    let photo: UIImage
    let selected: ShareBackdrop
    let onSelect: (ShareBackdrop) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Background")
                .font(.legibleFootnote.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
            ShareControlRow(spacing: 6, selection: selected) {
                ForEach(ShareBackdrop.all, id: \.self) { backdrop in
                    Button {
                        guard backdrop != selected else { return }
                        Haptics.selection()
                        onSelect(backdrop)
                    } label: {
                        swatch(backdrop)
                            .frame(width: 34, height: 34)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(Palette.stroke, lineWidth: 1))
                            .padding(3)
                            .overlay(Circle().strokeBorder(backdrop == selected ? Palette.ink : .clear, lineWidth: 2))
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.pressable)
                    .id(backdrop)
                    .accessibilityLabel(backdrop.title)
                    .accessibilityAddTraits(backdrop == selected ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
    }

    @ViewBuilder
    private func swatch(_ backdrop: ShareBackdrop) -> some View {
        switch backdrop {
        case .glow:
            LinearGradient(colors: [Color(uiColor: .brandBlush), .white], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(Image(systemName: "sparkle").font(.system(size: 13, weight: .bold)).foregroundStyle(Color(uiColor: .auraPink)))
        case .blur:
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .blur(radius: 3)
                .overlay(Image(systemName: "drop.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.9)))
        case .color(let swatch):
            Color(uiColor: UIColor(hex: swatch.hex))
        }
    }
}

extension ShareBackdrop {
    var title: Text {
        switch self {
        case .glow: return Text("Brand glow", comment: "Share background: the app's pink gradient")
        case .blur: return Text("Blurred photo")
        case .color(let swatch):
            switch swatch {
            case .petal: return Text("Petal")
            case .blush: return Text("Blush")
            case .butter: return Text("Butter")
            case .lilac: return Text("Lilac")
            case .mint: return Text("Mint")
            case .white: return Text("White")
            case .ink: return Text("Black")
            }
        }
    }
}

// MARK: - Text

/// Options "Write it for me" brought for one text slot, and who wrote them
/// (nil: the hand-written lines).
struct CardTextIdeas: Equatable {
    var lines: [String]
    var writtenBy: WrittenBy?
}

/// Her words on the design: a field per text, a font and a colour. Every
/// word goes through the same rules as text on a photo before it's drawn.
/// "Write it for me" brings options for a slot (Aybik's, or hand-written
/// ones); a tap puts one in the field.
struct ShareTextEditor: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let slots: [ShareTextSlot]
    @Binding var drafts: [ShareTextSlot: String]
    @Binding var font: OverlayFont?
    @Binding var color: OverlayColor?
    let notice: String?
    var focus: FocusState<ShareTextSlot?>.Binding
    var ideas: [ShareTextSlot: CardTextIdeas] = [:]
    var writingSlot: ShareTextSlot?
    /// Aybik may write: the note says what it gets.
    var usesAybik = false
    var onWrite: (ShareTextSlot) -> Void = { _ in }
    var onPick: (ShareTextSlot, String) -> Void = { _, _ in }
    let onDone: () -> Void

    static let colors: [OverlayColor] = [.white, .ink, .blush, .pink, .lilac, .butter, .mint]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Text")
                    .font(.cardTitle)
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Button("Done", action: onDone)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Palette.accent)
            }
            ForEach(slots, id: \.self) { slot in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        slot.label
                            .font(.legibleFootnote.weight(.semibold))
                            .foregroundStyle(Palette.textSecondary)
                        Spacer(minLength: 4)
                        writeButton(for: slot)
                    }
                    TextField(text: binding(for: slot), axis: slot.allowsLineBreak ? .vertical : .horizontal) {
                        Text(slot.placeholder)
                    }
                    .lineLimit(slot.allowsLineBreak ? 1...2 : 1...1)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .submitLabel(.done)
                    .focused(focus, equals: slot)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Palette.background, in: .control)
                    if let found = ideas[slot], !found.lines.isEmpty {
                        ideaChips(found, for: slot)
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            if usesAybik {
                Text("Aybik, our AI helper, reads what you typed in the box, never the photo.",
                     comment: "Share composer, under the text boxes: what “Write it for me” sends to the app's AI helper. Aybik is the app's AI helper: keep the name Aybik.")
                    .font(.legibleCaption)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let notice {
                Label(notice, systemImage: "exclamationmark.circle.fill")
                    .font(.legibleFootnote.weight(.semibold))
                    .foregroundStyle(Palette.accent)
                    .transition(.opacity)
            }
            ShareControlRow(spacing: 6, selection: font?.rawValue ?? "auto") {
                fontChip(nil)
                ForEach(OverlayFont.allCases) { option in
                    fontChip(option)
                }
            }
            ShareControlRow(spacing: 6, selection: color?.rawValue ?? "auto") {
                colorDot(nil)
                ForEach(Self.colors) { option in
                    colorDot(option)
                }
            }
        }
        .padding(16)
        .cardStyle()
        .animation(.snappy, value: notice)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy, value: ideas)
    }

    private func writeButton(for slot: ShareTextSlot) -> some View {
        let isWriting = writingSlot == slot
        return Button {
            Haptics.tap()
            onWrite(slot)
        } label: {
            HStack(spacing: 5) {
                if isWriting {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: "sparkles")
                        .accessibilityHidden(true)
                }
                Text("Write it for me", comment: "Share composer: a button beside a text box that suggests words for it (the app's AI helper or ready-made lines)")
            }
            .font(.legibleFootnote.weight(.bold))
            .foregroundStyle(Palette.accent)
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .disabled(writingSlot != nil)
        .accessibilityLabel(Text("Write it for me: \(slot.label)", comment: "Accessibility label of the share composer's “Write it for me” button; the placeholder is the text box's name (Your words, Title, Headline, Caption)"))
        .accessibilityValue(isWriting ? Text("Writing…") : Text(verbatim: ""))
    }

    private func ideaChips(_ found: CardTextIdeas, for slot: ShareTextSlot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(found.lines, id: \.self) { line in
                    SelectableChip(verbatim: line, isSelected: drafts[slot] == line) {
                        Haptics.selection()
                        onPick(slot, line)
                    }
                    .accessibilityHint(Text("Puts these words on the design", comment: "Accessibility hint of a suggested line in the share composer"))
                }
            }
            Group {
                if found.writtenBy == .cloud {
                    Text("Written by Aybik, our AI helper.", comment: "Under suggested words in the share composer. Aybik is the app's AI helper: keep the name Aybik.")
                } else {
                    Text("Ready-made ideas to start with.", comment: "Under suggested words in the share composer when they are the app's own lines")
                }
            }
            .font(.legibleCaption)
            .foregroundStyle(Palette.textTertiary)
        }
    }

    private func binding(for slot: ShareTextSlot) -> Binding<String> {
        Binding(
            get: { drafts[slot] ?? "" },
            set: { drafts[slot] = String($0.prefix(slot.maxLength + 8)) }
        )
    }

    private func fontChip(_ option: OverlayFont?) -> some View {
        let isSelected = font == option
        return Button {
            Haptics.selection()
            font = option
        } label: {
            Group {
                if let option {
                    Text(verbatim: option.title).font(Font(option.uiFont(size: 15) as CTFont))
                } else {
                    Text("Auto").font(.subheadline.weight(.semibold))
                }
            }
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .foregroundStyle(isSelected ? Palette.onPrimary : Palette.textPrimary)
            .background(isSelected ? Palette.primary : Palette.background, in: .chip)
            .overlay(RoundedRectangle.chip.strokeBorder(isSelected ? Palette.ink : Palette.stroke, lineWidth: isSelected ? 1.5 : 1))
            .selectionPop(isSelected)
            .frame(minHeight: 44)
        }
        .buttonStyle(.pressable)
        .id(option?.rawValue ?? "auto")
        .accessibilityLabel(option.map { Text(verbatim: $0.title) } ?? Text("Auto"))
        .accessibilityHint(option == nil ? Text("The design’s own font", comment: "Accessibility hint of Auto in the share composer's text fonts") : Text(verbatim: ""))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func colorDot(_ option: OverlayColor?) -> some View {
        let isSelected = color == option
        return Button {
            Haptics.selection()
            color = option
        } label: {
            Group {
                if let option {
                    Circle().fill(Color(uiColor: option.uiColor))
                } else {
                    // Auto: the design picks what reads best.
                    Circle()
                        .fill(AngularGradient(colors: [.white, Palette.ink, .white], center: .center))
                        .overlay(Text("A").font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(Palette.accent))
                }
            }
            .frame(width: 30, height: 30)
            .overlay(Circle().strokeBorder(Palette.stroke, lineWidth: 1))
            .padding(3)
            .overlay(Circle().strokeBorder(isSelected ? Palette.ink : .clear, lineWidth: 2))
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .id(option?.rawValue ?? "auto")
        .accessibilityLabel(option.map { Text(verbatim: $0.title) } ?? Text("Auto"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

extension ShareTextSlot {
    var label: Text {
        switch self {
        case .storyLine: return Text("Your words", comment: "Share composer: the line of text under the photo on the Story card")
        case .coverMasthead: return Text("Title", comment: "Share composer: the big title on the Cover star (GLOW)")
        case .coverHeadline: return Text("Headline", comment: "Share composer: the headline on the Cover star")
        case .stripCaption: return Text("Caption")
        }
    }

    /// The design's own text, shown until she writes hers.
    var placeholder: String {
        switch self {
        case .storyLine: return String(localized: "Say it your way…", comment: "Share composer: placeholder of the line under the photo on the Story card")
        case .coverMasthead: return String(localized: "GLOW", comment: "Magazine cover masthead")
        case .coverHeadline:
            return String(localized: "Main character\nenergy", comment: "Magazine cover headline, two short lines")
                .replacingOccurrences(of: "\n", with: " ")
        case .stripCaption: return Date().formatted(.dateTime.day(.twoDigits).month(.twoDigits).year(.twoDigits))
        }
    }
}

// MARK: - Layout

/// A row of controls: wrapped on the Mac, a sideways scroll elsewhere that
/// keeps the picked one (the control with that `.id`) in view.
struct ShareControlRow<Content: View>: View {
    var spacing: CGFloat = 8
    var selection: AnyHashable?
    @ViewBuilder let content: Content

    var body: some View {
        if Platform.isMac {
            FlowLayout(spacing: spacing, lineSpacing: spacing) { content }
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: spacing) { content }
                        .padding(.horizontal, Metrics.gutter)
                }
                .scrollIndicators(.hidden)
                .padding(.horizontal, -Metrics.gutter)
                // A turn after it appears, once the row has its size.
                .task(id: selection) {
                    guard let selection else { return }
                    withAnimation(.snappy) { proxy.scrollTo(selection, anchor: .center) }
                }
            }
        }
    }
}
