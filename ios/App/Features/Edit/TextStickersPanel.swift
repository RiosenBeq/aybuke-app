import SwiftUI
import UniformTypeIdentifiers
import AppCore

/// Text, Stickers and Doodle, then Apply. The rows keep one height in every
/// mode, so the photo doesn't jump when she switches.
struct TextStickersPanel: View {
    let session: OverlaySession
    let onApply: () -> Void

    @Environment(\.editorPanelPlacement) private var placement

    private static let contentHeight: CGFloat = 112

    var body: some View {
        VStack(spacing: 12) {
            // Side by side where they fit; a scrolling row at the largest
            // text sizes, so the chips never push the editor off the screen.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    modeChips
                    Spacer(minLength: 0)
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        modeChips
                    }
                    .padding(.horizontal, 1)
                }
                .scrollIndicators(.hidden)
            }

            Group {
                switch session.mode {
                case .text:
                    TextStyleRows(session: session, showsAddButton: true)
                case .stickers:
                    StickerTray(session: session)
                case .doodle:
                    DoodleTools(session: session)
                }
            }
            // The Mac's inspector scrolls, so its rows take the room they need.
            .frame(height: placement == .inspector ? nil : Self.contentHeight, alignment: .top)

            Button("Apply", action: onApply)
                .buttonStyle(.primary)
                .disabled(!session.hasContent)
        }
    }

    @ViewBuilder
    private var modeChips: some View {
        modeChip(.text, title: "Text", symbol: "textformat")
        modeChip(.stickers, title: "Stickers", symbol: "face.smiling")
        modeChip(.doodle, title: "Doodle", symbol: "scribble.variable")
    }

    private func modeChip(_ mode: OverlaySession.Mode, title: LocalizedStringKey, symbol: String) -> some View {
        SelectableChip(title: title, symbolName: symbol, isSelected: session.mode == mode) {
            session.setMode(mode)
        }
    }
}

// MARK: Text

/// Fonts on top; look, alignment and colours below. Shared by the panel and
/// the typing screen.
struct TextStyleRows: View {
    let session: OverlaySession
    var showsAddButton = false

    var body: some View {
        let style = session.currentStyle
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if showsAddButton {
                    Button {
                        session.addText()
                    } label: {
                        Label("Add text", systemImage: "plus")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Palette.onAccent)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(Palette.accent, in: .chip)
                    }
                    .buttonStyle(.pressable)
                }
                ScrollViewReader { reader in
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(OverlayFont.allCases) { font in
                                FontChip(font: font, isSelected: style.font == font) { session.setFont(font) }
                                    .id(font)
                            }
                        }
                        .padding(.horizontal, 1)
                    }
                    .scrollIndicators(.hidden)
                    .onAppear { reader.scrollTo(style.font, anchor: .center) }
                    .onChange(of: style.font) { _, font in
                        withAnimation(.snappy) { reader.scrollTo(font) }
                    }
                }
            }

            HStack(spacing: 8) {
                Button {
                    session.cycleLook()
                } label: {
                    Text(verbatim: "Aa")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .modifier(TextLookPreview(style: style, scale: 0.45))
                        .frame(width: 44, height: 44)
                        // Mid grey, so light and dark colours both show.
                        .background(Color(hex: 0x8C8790), in: .chip)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Text style")
                .accessibilityValue(style.look.title)
                .accessibilityHint("Switches between plain, outline, pill and neon")

                Button {
                    session.cycleAlignment()
                } label: {
                    Image(systemName: style.alignment.symbolName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(Palette.surface, in: .chip)
                        .overlay(RoundedRectangle.chip.strokeBorder(Palette.stroke, lineWidth: 1))
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Alignment")
                .accessibilityValue(style.alignment.title)

                ColorSwatches(selected: style.color) { session.setColor($0) }
            }
        }
    }
}

/// A font's name set in the font itself.
private struct FontChip: View {
    let font: OverlayFont
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(font.title)
                .font(Font(font.uiFont(size: 16) as CTFont))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .foregroundStyle(isSelected ? Palette.onPrimary : Palette.textPrimary)
                .background(isSelected ? Palette.primary : Palette.surface, in: .chip)
                .overlay(RoundedRectangle.chip.strokeBorder(isSelected ? Palette.ink : Palette.stroke, lineWidth: isSelected ? 1.5 : 1))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(font.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The Blush and Aura colours in one scrolling row.
private struct ColorSwatches: View {
    let selected: OverlayColor
    let onSelect: (OverlayColor) -> Void

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(OverlayColor.allCases) { color in
                        let isSelected = color == selected
                        Button {
                            onSelect(color)
                        } label: {
                            Circle()
                                .fill(Color(hex: color.hex))
                                .overlay(Circle().strokeBorder(Palette.strokeStrong, lineWidth: 1))
                                .frame(width: 30, height: 30)
                                .padding(3)
                                .overlay(Circle().strokeBorder(isSelected ? Palette.accent : Color.clear, lineWidth: 2.5))
                                .frame(width: 44, height: 44)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel(color.title)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .id(color)
                    }
                }
            }
            .scrollIndicators(.hidden)
            // The picked colour in view, also when another text is picked.
            .onAppear { reader.scrollTo(selected, anchor: .center) }
            .onChange(of: selected) { _, color in
                // No anchor: it only moves when the colour is out of view.
                withAnimation(.snappy) { reader.scrollTo(color) }
            }
        }
    }
}

// MARK: Stickers

/// The sticker pack: its sections (All, Cute, Y2K, Glam, Love, Sky, Words)
/// over one scrolling row of stickers, after a Paste tile for a cut-out she
/// copied as a sticker. Paste uses the system button, so there's no paste
/// prompt. Both rows fit the panel's one content height.
private struct StickerTray: View {
    let session: OverlaySession

    @State private var category: StickerCategory = .all
    @State private var thumbnails = StickerThumbnails.cached
    @Environment(\.displayScale) private var displayScale
    @Environment(\.editorPanelPlacement) private var placement

    private static let tileSide: CGFloat = 56

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if placement == .inspector {
                // The Mac's inspector: every section's chips and a sheet of stickers.
                FlowLayout {
                    categoryChips
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.tileSide), spacing: 8)], spacing: 8) {
                    stickerTiles
                }
            } else {
                categoryRow
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 8) {
                        stickerTiles
                    }
                    .padding(.horizontal, 1)
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                // Another section starts at its first sticker.
                .id(category)
            }
        }
        .task {
            guard thumbnails.count < StickerKind.allCases.count else { return }
            thumbnails = await StickerThumbnails.load(scale: displayScale)
        }
    }

    @ViewBuilder
    private var stickerTiles: some View {
        PasteButton(supportedContentTypes: [.png, .image]) { providers in
            paste(providers)
        }
        .labelStyle(.iconOnly)
        .buttonBorderShape(.roundedRectangle(radius: Metrics.controlRadius))
        .tint(Palette.accent)
        .frame(width: Self.tileSide, height: Self.tileSide)

        ForEach(category.kinds) { kind in
            Button {
                session.addSticker(kind)
            } label: {
                tile(kind)
            }
            .buttonStyle(.pressable)
            .macHoverLift(scale: 1.06)
            .accessibilityLabel(kind.title)
            .accessibilityHint("Adds it to the photo")
        }
    }

    private var categoryChips: some View {
        ForEach(StickerCategory.allCases) { item in
            SelectableChip(title: item.title, isSelected: category == item) {
                guard item != category else { return }
                Haptics.selection()
                category = item
            }
            .id(item)
        }
    }

    private var categoryRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    categoryChips
                }
                .padding(.horizontal, 1)
            }
            .scrollIndicators(.hidden)
            .onChange(of: category) { _, item in
                withAnimation(.snappy) { proxy.scrollTo(item) }
            }
        }
        // The chips grow with Dynamic Type up to AX1, so the two rows keep
        // the panel's height.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .frame(height: 44)
    }

    private func tile(_ kind: StickerKind) -> some View {
        ZStack {
            Palette.surface
            if let thumbnail = thumbnails[kind] {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            }
        }
        .frame(width: Self.tileSide, height: Self.tileSide)
        .clipShape(.control)
        .overlay(RoundedRectangle.control.strokeBorder(Palette.stroke, lineWidth: 1))
    }

    private func paste(_ providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        let type = provider.hasItemConformingToTypeIdentifier(UTType.png.identifier) ? UTType.png : UTType.image
        provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
            Task { @MainActor in
                guard let data, let sticker = await PastedStickerLoader.load(data) else {
                    session.notice = String(localized: "That can't be pasted as a sticker.")
                    return
                }
                session.addPasted(sticker)
            }
        }
    }
}

/// Tray pictures, drawn once by the same renderer as the photo.
@MainActor
enum StickerThumbnails {
    private(set) static var cached: [StickerKind: UIImage] = [:]

    static func load(scale: CGFloat) async -> [StickerKind: UIImage] {
        if cached.count == StickerKind.allCases.count { return cached }
        let rendered = await Task.detached(priority: .userInitiated) {
            Dictionary(uniqueKeysWithValues: StickerKind.allCases.map { kind -> (StickerKind, UIImage) in
                let content = OverlayContent.sticker(Sticker(kind))
                let size = OverlayRenderer.artworkSize(of: content)
                // The tile's picture is 48 pt across.
                let pixelsPerUnit = 48 * scale / max(size.width, size.height)
                return (kind, OverlayRenderer.image(of: content, size: size, pixelsPerUnit: pixelsPerUnit))
            })
        }.value
        cached = rendered
        return rendered
    }
}

/// Decodes a pasted sticker off the main actor, at most 1024 px, keeping
/// the AI marking the file carried (a sticker of an AI edit has one).
enum PastedStickerLoader {
    static func load(_ data: Data) async -> PastedSticker? {
        await Task.detached(priority: .userInitiated) {
            guard let image = ImageUtilities.decodedImage(from: data, maxPixel: 1024) else { return nil }
            return PastedSticker(image: image, sourceType: ImageExporter.digitalSourceType(in: data))
        }.value
    }
}

// MARK: Doodle

/// Pen, marker, highlighter and eraser; Undo and Clear; the colours.
private struct DoodleTools: View {
    let session: OverlaySession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        brushChip(.pen, title: "Pen", symbol: "pencil.tip")
                        brushChip(.marker, title: "Marker", symbol: "paintbrush.pointed")
                        brushChip(.highlighter, title: "Highlighter", symbol: "highlighter")
                        brushChip(.eraser, title: "Eraser", symbol: "eraser")
                    }
                    .padding(.horizontal, 1)
                }
                .scrollIndicators(.hidden)
                Button { session.undoDoodle() } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(.icon)
                    .disabled(!session.canUndoDoodle)
                    .opacity(session.canUndoDoodle ? 1 : 0.4)
                    .accessibilityLabel("Undo stroke")
                    .macHelp("Undo stroke")
                Button { session.clearDoodle() } label: { Image(systemName: "trash") }
                    .buttonStyle(.icon)
                    .disabled(session.doodle.strokes.isEmpty)
                    .opacity(session.doodle.strokes.isEmpty ? 0.4 : 1)
                    .accessibilityLabel("Clear drawing")
                    .macHelp("Clear drawing")
            }
            ColorSwatches(selected: session.inkColor) { session.setInkColor($0) }
        }
    }

    private func brushChip(_ brush: OverlaySession.Brush, title: LocalizedStringKey, symbol: String) -> some View {
        SelectableChip(title: title, symbolName: symbol, isSelected: session.brush == brush) {
            session.setBrush(brush)
        }
    }
}
