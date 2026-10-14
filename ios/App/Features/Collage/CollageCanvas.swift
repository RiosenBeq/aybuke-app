import SwiftUI
import AppCore

/// The live collage. It follows the same layout and drawing rules as the
/// export: drag a photo to move it in its frame, pinch to zoom, double-tap
/// to fit it, hold and drag it onto another to swap them.
struct CollageCanvas: View {
    @Bindable var model: CollageModel

    static let space = "collageCanvas"

    private struct Cell: Identifiable {
        let index: Int
        let photo: CollageModel.Photo
        let slot: CollageSlot
        var id: UUID { photo.id }
    }

    /// Keyed by photo, so a swap slides the two photos into place.
    private var cells: [Cell] {
        zip(model.photos, model.layout.slots).enumerated().map { Cell(index: $0.offset, photo: $0.element.0, slot: $0.element.1) }
    }

    var body: some View {
        let design = model.design
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                CollageBackdropView(background: design.background, backdrop: model.backdrop)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .contentShape(Rectangle())
                    .onTapGesture { model.clearSelection() }
                ForEach(Array(model.layout.strips.enumerated()), id: \.offset) { _, strip in
                    FilmStripView(strip: strip, canvas: size)
                }
                ForEach(cells) { cell in
                    CollageCell(model: model, index: cell.index, photo: cell.photo, slot: cell.slot, canvas: size)
                        .zIndex(model.lifted == cell.index ? 100 : Double(cell.index))
                }
                ForEach(Array(model.layout.decorations.enumerated()), id: \.offset) { _, decoration in
                    CollageDecorationView(decoration: decoration, canvas: size, swatches: model.photos.map(\.swatch))
                        .zIndex(200)
                }
                if let caption = model.layout.captionFrame {
                    CollageCaptionView(frame: caption, design: design, canvas: size)
                        .zIndex(200)
                }
                if design.format.isCarousel {
                    SeamGuides(count: design.format.slides, size: size)
                        .zIndex(300)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
            .coordinateSpace(.named(Self.space))
        }
        .aspectRatio(design.format.widthOverHeight, contentMode: .fit)
    }
}

// MARK: - A photo

private struct CollageCell: View {
    @Bindable var model: CollageModel
    let index: Int
    let photo: CollageModel.Photo
    let slot: CollageSlot
    let canvas: CGSize

    @Environment(AppModel.self) private var app

    /// A drag and a pinch in progress, applied to the photo live and
    /// committed when they end.
    private struct Live: Equatable {
        var translation = CGSize.zero
        var magnification: CGFloat = 1
    }

    /// Held and dragged to swap: where the finger is on the canvas.
    private struct Hold: Equatable {
        var isLifted = false
        var translation = CGSize.zero
        var location: CGPoint?
    }

    @GestureState private var live = Live()
    @GestureState(resetTransaction: Transaction(animation: .snappy)) private var hold = Hold()

    var body: some View {
        let design = model.design
        let style = design.style
        let frame = CollageArt.pixels(slot.frame, in: canvas)
        let window = CollageArt.pixels(slot.window, in: canvas)
        let short = min(canvas.width, canvas.height)
        let radii = style.cornerRadii(amount: design.corners, aspect: design.format.widthOverHeight)
        let windowRadius = min(radii.window * canvas.height, min(window.width, window.height) / 2)
        let cardRadius = min(radii.card * canvas.height, min(frame.width, frame.height) / 2)
        let placed = CollageArt.photoFrame(crop(for: live, window: window.size), imageSize: photo.image.size,
                                           window: CGRect(origin: .zero, size: window.size))
        let isPicked = model.selection == index || model.swapping == index
        let isTarget = model.dropTarget == index

        ZStack(alignment: .topLeading) {
            if style.hasCards {
                RoundedRectangle(cornerRadius: cardRadius)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.22), radius: short * 0.0175, y: short * 0.01)
            }
            Image(uiImage: photo.image)
                .resizable()
                .frame(width: placed.width, height: placed.height)
                .position(x: placed.midX, y: placed.midY)
                .frame(width: window.width, height: window.height)
                .clipShape(RoundedRectangle(cornerRadius: windowRadius))
                .overlay {
                    if isPicked || isTarget {
                        RoundedRectangle(cornerRadius: windowRadius)
                            .strokeBorder(Color.white, style: StrokeStyle(lineWidth: 3, dash: isTarget ? [8, 5] : []))
                            .overlay(RoundedRectangle(cornerRadius: windowRadius).strokeBorder(Palette.ink.opacity(0.45), lineWidth: 1))
                    }
                }
                .offset(x: window.minX - frame.minX, y: window.minY - frame.minY)
        }
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.toggleFit(index) }
        .onTapGesture { model.tap(index) }
        .gesture(swapGesture.exclusively(before: panZoomGesture(window: window.size)))
        .dropDestination(for: DroppedPhoto.self) { files, _ in
            guard let file = files.first else { return false }
            Task {
                if await model.addDropped([file.data], replacing: index) > 0 {
                    app.showToast("Couldn't open that photo. Try another one.", style: .error)
                }
            }
            return true
        } isTargeted: { targeted in
            if targeted {
                model.dropTarget = index
            } else if model.dropTarget == index {
                model.dropTarget = nil
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Photo \(index + 1) of \(model.photos.count)"))
        .accessibilityAddTraits(isPicked ? [.isImage, .isSelected] : .isImage)
        .accessibilityAction { model.tap(index) }
        .accessibilityActions {
            Button(model.isFitting(index) ? "Fill the frame" : "Show the whole photo") { model.toggleFit(index) }
            if index > 0 {
                Button("Move earlier") { withAnimation(.snappy) { model.swap(index, index - 1) } }
            }
            if index < model.photos.count - 1 {
                Button("Move later") { withAnimation(.snappy) { model.swap(index, index + 1) } }
            }
            if model.photos.count > CollageModel.minPhotos {
                Button("Remove photo") { model.remove(index) }
            }
        }
        .rotationEffect(.degrees(slot.rotation))
        .scaleEffect(hold.isLifted ? 1.06 : 1)
        .shadow(color: .black.opacity(hold.isLifted ? 0.3 : 0), radius: hold.isLifted ? 18 : 0, y: hold.isLifted ? 10 : 0)
        .offset(hold.translation)
        .position(x: frame.midX, y: frame.midY)
        .onChange(of: hold) { old, new in
            if new.isLifted, !old.isLifted {
                Haptics.tap()
                model.clearSelection()
                model.lifted = index
            }
            if new.isLifted {
                model.dropTarget = new.location.flatMap(target(at:))
            } else if old.isLifted {
                if model.lifted == index { model.lifted = nil }
                model.dropTarget = nil
            }
        }
    }

    // MARK: Gestures

    /// Hold, then drag onto another photo to swap the two.
    private var swapGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(CollageCanvas.space)))
            .updating($hold) { value, state, _ in
                guard case .second(true, let drag) = value else { return }
                state = Hold(isLifted: true, translation: drag?.translation ?? .zero, location: drag?.location)
            }
            .onEnded { value in
                guard case .second(true, let drag?) = value, let target = target(at: drag.location) else { return }
                withAnimation(.snappy) { model.swap(index, target) }
                Haptics.success()
            }
    }

    /// Drag to move the photo in its frame, pinch to zoom.
    private func panZoomGesture(window: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(CollageCanvas.space))
            .simultaneously(with: MagnifyGesture())
            .updating($live) { value, state, _ in
                state = Live(translation: value.first?.translation ?? .zero, magnification: value.second?.magnification ?? 1)
            }
            .onEnded { value in
                let final = Live(translation: value.first?.translation ?? .zero, magnification: value.second?.magnification ?? 1)
                model.setCrop(crop(for: final, window: window), at: index)
            }
    }

    /// The photo's pan and zoom with a gesture in progress. The drag is
    /// turned back by the frame's tilt, so the photo follows the finger.
    private func crop(for live: Live, window: CGSize) -> CollageCrop {
        let photoAspect = photo.aspect
        let windowAspect = window.height > 0 ? window.width / window.height : 1
        var crop = photo.crop
        if live.translation != .zero, window.width > 0, window.height > 0 {
            let radians = slot.rotation * .pi / 180
            let dx = live.translation.width * cos(radians) + live.translation.height * sin(radians)
            let dy = -live.translation.width * sin(radians) + live.translation.height * cos(radians)
            crop = crop.moved(dx: dx / window.width, dy: dy / window.height, photoAspect: photoAspect, windowAspect: windowAspect)
        }
        if live.magnification != 1 {
            crop = crop.zoomed(by: live.magnification, photoAspect: photoAspect, windowAspect: windowAspect)
        }
        return crop
    }

    /// Another photo under a point of the canvas.
    private func target(at point: CGPoint) -> Int? {
        guard canvas.width > 0, canvas.height > 0 else { return nil }
        let hit = model.layout.slotIndex(atX: point.x / canvas.width, y: point.y / canvas.height,
                                         aspect: model.design.format.widthOverHeight)
        return hit == index ? nil : hit
    }
}

// MARK: - Art

/// The background: a brand colour, an aura gradient or the blurred photo.
struct CollageBackdropView: View {
    let background: CollageBackground
    let backdrop: UIImage?

    var body: some View {
        if background == .photo, let backdrop {
            Image(uiImage: backdrop)
                .resizable()
                .scaledToFill()
                .overlay(Color.white.opacity(CollageArt.backdropVeil))
        } else if background.colors.count > 1 {
            LinearGradient(colors: background.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            background.colors.first ?? Palette.petal
        }
    }
}

private struct FilmStripView: View {
    let strip: CollageStrip
    let canvas: CGSize

    var body: some View {
        let rect = CollageArt.pixels(strip.frame, in: canvas)
        let short = min(canvas.width, canvas.height)
        Path(CollageArt.stripPath(strip, in: CGRect(origin: .zero, size: rect.size)))
            .fill(Palette.ink, style: FillStyle(eoFill: true))
            .frame(width: rect.width, height: rect.height)
            .shadow(color: .black.opacity(0.28), radius: short * 0.0125, y: short * 0.008)
            .rotationEffect(.degrees(strip.rotation))
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
    }
}

private struct CollageDecorationView: View {
    let decoration: CollageDecoration
    let canvas: CGSize
    let swatches: [UIColor]

    var body: some View {
        let rect = CollageArt.pixels(decoration.frame, in: canvas)
        art(in: rect)
            .frame(width: rect.width, height: rect.height)
            .rotationEffect(.degrees(decoration.rotation))
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func art(in rect: CGRect) -> some View {
        let short = min(canvas.width, canvas.height)
        switch decoration.kind {
        case .tape(let tone):
            Rectangle().fill(Color(uiColor: CollageArt.tapeColor(tone)))
        case .sticker(let index):
            let sticker = CollageArt.sticker(index)
            StickerGlyph(symbol: sticker.symbol, color: Color(uiColor: sticker.color), size: rect.height)
        case .palette:
            RoundedRectangle(cornerRadius: min(rect.height * 0.16, rect.width / 2))
                .fill(Color.white)
                .shadow(color: .black.opacity(0.12), radius: short * 0.007, y: short * 0.004)
        case .swatch(let photo):
            Circle()
                .fill(Color(uiColor: photo < swatches.count ? swatches[photo] : .brandBlush))
                .overlay(Circle().strokeBorder(Color.black.opacity(0.08), lineWidth: max(1, rect.width * 0.03)))
        }
    }
}

/// An SF Symbol as a die-cut sticker with a white edge, like the export's
/// `ShareRenderer.drawSymbol`.
private struct StickerGlyph: View {
    let symbol: String
    let color: Color
    let size: CGFloat

    var body: some View {
        let border = size * 0.06
        ZStack {
            ForEach(0..<8, id: \.self) { step in
                let angle = Double(step) * .pi / 4
                glyph.foregroundStyle(Color.white)
                    .offset(x: cos(angle) * border * 1.2, y: sin(angle) * border * 1.2)
            }
            glyph.foregroundStyle(color)
        }
    }

    private var glyph: some View {
        Image(systemName: symbol)
            .resizable()
            .scaledToFit()
            .fontWeight(.bold)
    }
}

private struct CollageCaptionView: View {
    let frame: CollageRect
    let design: CollageDesign
    let canvas: CGSize

    var body: some View {
        let rect = CollageArt.pixels(frame, in: canvas)
        let hasPill = CollageArt.captionHasPill(design.background)
        Text(verbatim: CollageArt.captionText(design.caption, date: Date()))
            .font(.custom(CollageArt.captionFontName, fixedSize: rect.height * CollageArt.captionFontShare))
            .foregroundStyle(design.background.isDark ? Color.white : Palette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.3)
            .padding(.horizontal, hasPill ? rect.height * CollageArt.captionPillPadding : 0)
            .frame(height: hasPill ? rect.height * CollageArt.captionPillHeight : rect.height)
            .background {
                if hasPill {
                    Capsule().fill(Color.white.opacity(CollageArt.captionPillOpacity))
                }
            }
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
    }
}

/// Dashed seams and slide numbers over a carousel (preview only).
private struct SeamGuides: View {
    let count: Int
    let size: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(CarouselSlicer.seams(count: count), id: \.self) { seam in
                Path { path in
                    path.move(to: CGPoint(x: seam * size.width, y: 0))
                    path.addLine(to: CGPoint(x: seam * size.width, y: size.height))
                }
                .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .shadow(color: .black.opacity(0.35), radius: 1)
            }
            ForEach(1...max(count, 1), id: \.self) { number in
                Text(verbatim: "\(number)/\(count)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Palette.ink.opacity(0.55), in: .tag)
                    .offset(x: Double(number - 1) / Double(max(count, 1)) * size.width + 6, y: 6)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A small drawing of a style's layout for the Layout panel.
struct CollageLayoutThumbnail: View {
    let style: CollageStyle
    let count: Int

    private static let tones: [Color] = [Palette.auraPink, Palette.auraLilac, Palette.auraMint, Palette.auraPeach, Palette.auraButter]

    var body: some View {
        let layout = CollageLayout.make(style: style, count: max(count, CollageModel.minPhotos), format: .square, spacing: 0.6)
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                ForEach(Array(layout.strips.enumerated()), id: \.offset) { _, strip in
                    let rect = CollageArt.pixels(strip.frame, in: size)
                    Rectangle()
                        .fill(Palette.ink)
                        .frame(width: rect.width, height: rect.height)
                        .rotationEffect(.degrees(strip.rotation))
                        .position(x: rect.midX, y: rect.midY)
                }
                ForEach(Array(layout.slots.enumerated()), id: \.offset) { index, slot in
                    let frame = CollageArt.pixels(slot.frame, in: size)
                    let window = CollageArt.pixels(slot.window, in: size)
                    ZStack(alignment: .topLeading) {
                        if style.hasCards {
                            Rectangle()
                                .fill(Color.white)
                                .shadow(color: .black.opacity(0.18), radius: 1)
                        }
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Self.tones[index % Self.tones.count].opacity(0.85))
                            .frame(width: window.width, height: window.height)
                            .offset(x: window.minX - frame.minX, y: window.minY - frame.minY)
                    }
                    .frame(width: frame.width, height: frame.height, alignment: .topLeading)
                    .rotationEffect(.degrees(slot.rotation))
                    .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
