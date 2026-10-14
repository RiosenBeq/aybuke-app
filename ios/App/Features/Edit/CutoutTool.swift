import SwiftUI
import PhotosUI
import Observation

/// Cut out after Vision has run: which subjects to keep, brushed fixes to
/// the edge, and what goes behind them, previewed on a small copy and
/// rendered at full size on Apply.
@MainActor
@Observable
final class CutoutSession {
    /// The refine brush: paint more of the photo back in, or paint some away.
    enum RefineMode {
        case keepMore, keepLess
    }

    private(set) var analysis: CutoutAnalysis?
    private(set) var selection = IndexSet()
    private(set) var backdrop: CutoutBackdrop = .transparent
    private(set) var customColor = Palette.blush
    private(set) var backdropPhoto: UIImage?
    private(set) var preview: UIImage?
    private(set) var outlines: UIImage?
    /// The photo was already a cut-out: there's nothing behind it to blur.
    private(set) var sourceHasAlpha = false
    /// While set, the canvas is a brush instead of tap-to-pick.
    private(set) var refineMode: RefineMode?
    private(set) var refineStrokes: [CutoutRefineStroke] = []
    /// A soft shadow under the subject on its new background.
    private(set) var showsShadow = false

    /// Refine brush diameter at fit, as a share of the photo's width.
    static let refineBrushSize: CGFloat = 0.05

    /// The first tap keeps only that subject; later taps add or remove.
    @ObservationIgnored private var hasPicked = false
    @ObservationIgnored private var previewTask: Task<Void, Never>?

    var isActive: Bool { analysis != nil }
    var subjects: [CutoutAnalysis.Subject] { analysis?.subjects ?? [] }
    var keepsEverything: Bool { analysis.map { selection == $0.allIDs } ?? true }
    /// A cut-out on another photo is a composite (IPTC), not just an edit.
    var isComposite: Bool { backdrop == .photo && backdropPhoto != nil }
    /// A shadow needs something to fall on: not transparency, and not the
    /// blurred original, where she still stands in her own scene.
    var offersShadow: Bool {
        switch backdrop {
        case .transparent, .blurOriginal: return false
        case .photo: return backdropPhoto != nil
        case .color, .custom, .gradient: return true
        }
    }

    func begin(_ analysis: CutoutAnalysis, keeping subject: Int?) {
        reset()
        self.analysis = analysis
        sourceHasAlpha = analysis.hasTransparency
        if let subject, analysis.allIDs.contains(subject), analysis.subjects.count > 1 {
            selection = [subject]
            hasPicked = true
        } else {
            selection = analysis.allIDs
        }
        refresh()
    }

    func reset() {
        previewTask?.cancel()
        analysis = nil
        selection = []
        backdrop = .transparent
        backdropPhoto = nil
        preview = nil
        outlines = nil
        hasPicked = false
        refineMode = nil
        refineStrokes = []
        showsShadow = false
    }

    /// WWDC23's lift-subject behaviour: the first tap keeps only what she
    /// tapped, later taps add or remove, and the background brings everyone back.
    func tap(at point: CGPoint) {
        guard let analysis, analysis.subjects.count > 1 else { return }
        guard let id = analysis.subject(atNormalized: point), analysis.allIDs.contains(id) else {
            keepAll()
            return
        }
        if !hasPicked {
            selection = [id]
            hasPicked = true
        } else if selection.contains(id) {
            selection.remove(id)
            if selection.isEmpty { selection = analysis.allIDs; hasPicked = false }
        } else {
            selection.insert(id)
        }
        Haptics.selection()
        refresh()
    }

    func keepOnly(_ id: Int) {
        selection = [id]
        hasPicked = true
        Haptics.selection()
        refresh()
    }

    func keepAll() {
        guard let analysis else { return }
        selection = analysis.allIDs
        hasPicked = false
        Haptics.selection()
        refresh()
    }

    func setBackdrop(_ backdrop: CutoutBackdrop) {
        guard backdrop != self.backdrop else { return }
        self.backdrop = backdrop
        Haptics.selection()
        refresh()
    }

    func setCustomColor(_ color: Color) {
        customColor = color
        backdrop = .custom
        refresh()
    }

    func setBackdropPhoto(_ photo: UIImage) {
        backdropPhoto = photo
        backdrop = .photo
        Haptics.selection()
        refresh()
    }

    // MARK: Refine and shadow

    /// Picks a brush, or puts it down when she taps the same one again.
    func setRefineMode(_ mode: RefineMode) {
        refineMode = refineMode == mode ? nil : mode
        Haptics.selection()
    }

    func addRefineStroke(_ stroke: MaskStroke) {
        guard let refineMode else { return }
        refineStrokes.append(CutoutRefineStroke(stroke: stroke, keeps: refineMode == .keepMore))
        refresh()
    }

    func undoRefineStroke() {
        guard !refineStrokes.isEmpty else { return }
        refineStrokes.removeLast()
        Haptics.selection()
        refresh()
    }

    func toggleShadow() {
        showsShadow.toggle()
        Haptics.selection()
        refresh()
    }

    /// The final image at the analysed photo's full size.
    func renderFinal() async -> UIImage? {
        guard let analysis else { return nil }
        let job = renderJob(analysis)
        return await Task.detached(priority: .userInitiated) {
            guard let mask = job.mask(from: analysis) else { return nil }
            let source = CIImage(cgImage: analysis.source)
            let output = CutoutRenderer.composite(source: source, mask: mask, backdrop: job.backdrop, color: job.color, photo: job.photo,
                                                  shadowUnder: job.shadowBounds)
            return CutoutRenderer.render(output, opaque: job.backdrop != .transparent)
        }.value
    }

    /// The kept subjects as an outlined sticker on transparency.
    func renderSticker() async -> UIImage? {
        guard let analysis else { return nil }
        let job = renderJob(analysis)
        return await Task.detached(priority: .userInitiated) {
            guard let mask = job.mask(from: analysis) else { return nil }
            return CutoutRenderer.sticker(source: CIImage(cgImage: analysis.source), mask: mask, bounds: job.bounds)
        }.value
    }

    private struct RenderJob: Sendable {
        let selection: IndexSet
        let refine: [CutoutRefineStroke]
        let backdrop: CutoutBackdrop
        let color: UIColor
        let photo: UIImage?
        /// Normalized bounds of what she keeps, brushed-in parts included.
        let bounds: CGRect
        /// Each kept subject's bounds (with what she brushed in around it),
        /// when it gets a shadow.
        let shadowBounds: [CGRect]

        /// The kept subjects' mask with her brush strokes on top, at the
        /// analysed photo's size.
        func mask(from analysis: CutoutAnalysis) -> CIImage? {
            guard let mask = try? analysis.mask(for: selection) else { return nil }
            return CutoutRenderer.refined(mask, with: refine)
        }
    }

    private func renderJob(_ analysis: CutoutAnalysis) -> RenderJob {
        var backdrop = backdrop
        if backdrop == .blurOriginal && sourceHasAlpha { backdrop = .transparent }
        if backdrop == .photo && backdropPhoto == nil { backdrop = .transparent }
        let whole = CGRect(x: 0, y: 0, width: 1, height: 1)
        let brushedIn = refineStrokes.filter { $0.keeps }.map { $0.stroke.bounds }
        let bounds = brushedIn.reduce(analysis.bounds(of: selection)) { $0.union($1) }.intersection(whole)
        let shadowBounds = !(showsShadow && offersShadow) ? [] : analysis.subjects.filter { selection.contains($0.id) }.map { subject in
            brushedIn.filter { $0.intersects(subject.bounds) }.reduce(subject.bounds) { $0.union($1) }.intersection(whole)
        }
        return RenderJob(selection: selection, refine: refineStrokes, backdrop: backdrop, color: UIColor(customColor), photo: backdropPhoto,
                         bounds: bounds, shadowBounds: shadowBounds)
    }

    /// Re-renders the preview on a ≤ 1200 px copy. Subjects she isn't keeping
    /// stay faintly visible, so she can tap them back.
    private func refresh() {
        previewTask?.cancel()
        guard let analysis else { return }
        let job = renderJob(analysis)
        let showsGhosts = !keepsEverything
        let showsOutlines = analysis.subjects.count > 1
        previewTask = Task {
            // Taps come quickly; a short pause saves a render per tap.
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            let rendered = await Task.detached(priority: .userInitiated) { () -> (UIImage?, UIImage?) in
                guard let mask = job.mask(from: analysis) else { return (nil, nil) }
                let full = CIImage(cgImage: analysis.source)
                let scale = min(1, 1200 / max(full.extent.width, full.extent.height))
                let transform = CGAffineTransform(scaleX: scale, y: scale)
                let extent = CGRect(x: 0, y: 0, width: (full.extent.width * scale).rounded(), height: (full.extent.height * scale).rounded())
                let source = full.transformed(by: transform).cropped(to: extent)
                var output = CutoutRenderer.composite(
                    source: source, mask: mask.transformed(by: transform), backdrop: job.backdrop, color: job.color, photo: job.photo,
                    shadowUnder: job.shadowBounds
                )
                // Whole subjects she left out show faintly; what she brushed away doesn't.
                if showsGhosts, let others = try? analysis.mask(for: analysis.allIDs.subtracting(job.selection)) {
                    output = Self.ghosts(source: source, others: others.transformed(by: transform), kept: mask.transformed(by: transform))
                        .composited(over: output)
                        .cropped(to: extent)
                }
                let preview = CutoutRenderer.render(output, opaque: false)
                let outlines = showsOutlines ? analysis.outlines(kept: job.selection).map { UIImage(cgImage: $0) } : nil
                return (preview, outlines)
            }.value
            guard !Task.isCancelled else { return }
            preview = rendered.0
            outlines = rendered.1
        }
    }

    /// The subjects that aren't kept (`left`, minus anything brushed back
    /// in), at 40%.
    private nonisolated static func ghosts(source: CIImage, others left: CIImage, kept: CIImage) -> CIImage {
        let extent = source.extent
        let others = CIFilter(name: "CIBlendWithMask", parameters: [
            kCIInputImageKey: CIImage(color: .black).cropped(to: extent),
            kCIInputBackgroundImageKey: left,
            "inputMaskImage": kept,
        ])?.outputImage ?? CIImage(color: .black).cropped(to: extent)
        let faded = source.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.4)])
        return CIFilter(name: "CIBlendWithMask", parameters: [
            kCIInputImageKey: faded,
            kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: extent),
            "inputMaskImage": others,
        ])?.outputImage ?? CIImage(color: .clear).cropped(to: extent)
    }
}

/// The cut-out preview: tap a subject to keep it, tap the background to keep
/// everyone again. With a refine brush picked, one finger paints the edge
/// and two fingers pan and zoom, as in Erase.
struct CutoutCanvas: View {
    let session: CutoutSession
    let fallback: UIImage

    var body: some View {
        if let mode = session.refineMode {
            refineCanvas(mode)
        } else {
            pickCanvas
        }
    }

    private func refineCanvas(_ mode: CutoutSession.RefineMode) -> some View {
        let image = session.preview ?? fallback
        return ZStack {
            if session.backdrop == .transparent || session.preview == nil {
                CheckerboardBackground()
            }
            // Mint paints the photo back in, ink takes it away.
            BrushCanvas(image: image, color: mode == .keepMore ? .auraMint : .brandInk, opacity: 0.55,
                        brushSize: CutoutSession.refineBrushSize) { stroke in
                session.addRefineStroke(stroke)
            }
        }
        .aspectRatio(image.size.width / max(image.size.height, 1), contentMode: .fit)
        .clipShape(.control)
        .shadow(color: Palette.shadow, radius: 16, y: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mode == .keepMore ? Text("Brush over what to keep") : Text("Brush over what to remove"))
        .accessibilityAddTraits(.allowsDirectInteraction)
    }

    private var pickCanvas: some View {
        let image = session.preview ?? fallback
        return GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                if session.backdrop == .transparent || session.preview == nil {
                    CheckerboardBackground()
                }
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                if let outlines = session.outlines {
                    Image(uiImage: outlines)
                        .resizable()
                        .interpolation(.medium)
                        .allowsHitTesting(false)
                        .opacity(0.9)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                session.tap(at: CGPoint(x: location.x / max(size.width, 1), y: location.y / max(size.height, 1)))
            }
        }
        .aspectRatio(image.size.width / max(image.size.height, 1), contentMode: .fit)
        .clipShape(.control)
        .shadow(color: Palette.shadow, radius: 16, y: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cut-out preview")
        .accessibilityValue(session.subjects.count > 1 ? Text("Keeping \(session.selection.count) of \(session.subjects.count)") : Text(""))
        .accessibilityAddTraits(.isImage)
        .accessibilityActions {
            if session.subjects.count > 1 {
                ForEach(Array(session.subjects.enumerated()), id: \.element.id) { index, subject in
                    Button(actionName(index: index, count: session.subjects.count)) { session.keepOnly(subject.id) }
                }
                Button("Keep every subject") { session.keepAll() }
            }
        }
    }

    /// Subjects are sorted left to right, so name them by where they are.
    private func actionName(index: Int, count: Int) -> LocalizedStringKey {
        if index == 0 { return "Keep only the subject on the left" }
        if index == count - 1 { return "Keep only the subject on the right" }
        if count == 3 { return "Keep only the subject in the middle" }
        return "Keep only subject \(index + 1) from the left"
    }
}

/// Subjects, backgrounds, sticker and Apply. Every background is free.
struct CutoutPanel: View {
    let session: CutoutSession
    let onStart: () -> Void
    let onApply: () -> Void
    let onCopySticker: () -> Void
    let onSaveSticker: () -> Void

    @State private var photoItem: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    @Environment(AppModel.self) private var app
    @Environment(\.editorPanelPlacement) private var placement

    private static let gradientThumbnails: [CutoutGradient: UIImage] = Dictionary(
        uniqueKeysWithValues: CutoutGradient.allCases.map { ($0, CutoutRenderer.thumbnail(of: $0, side: 88)) }
    )

    var body: some View {
        if session.isActive {
            VStack(alignment: .leading, spacing: 12) {
                if let mode = session.refineMode {
                    HStack(spacing: 8) {
                        Image(systemName: "paintbrush.pointed")
                            .foregroundStyle(Palette.accent)
                        Text(mode == .keepMore ? "Brush over what to keep" : "Brush over what to remove")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                } else if session.subjects.count > 1 {
                    HStack(spacing: 8) {
                        Image(systemName: "hand.tap")
                            .foregroundStyle(Palette.accent)
                        Text(Platform.isMac ? "Click who or what to keep" : "Tap who or what to keep")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        SelectableChip(title: "All", isSelected: session.keepsEverything) { session.keepAll() }
                    }
                }

                refineRow

                HStack(spacing: 8) {
                    Text("Background")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.textSecondary)
                    Spacer(minLength: 0)
                    if session.offersShadow {
                        SelectableChip(title: "Shadow", symbolName: "shadow", isSelected: session.showsShadow) {
                            session.toggleShadow()
                        }
                        .accessibilityHint("Adds a soft shadow under the subject")
                    }
                }
                backdropRow

                ButtonRow {
                    Menu {
                        Button(action: onCopySticker) { Label("Copy as sticker", systemImage: "doc.on.doc") }
                        Button(action: onSaveSticker) { Label("Save sticker", systemImage: "square.and.arrow.down") }
                    } label: {
                        Label("Sticker", systemImage: "sparkles.rectangle.stack")
                            .font(.headline)
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                            .padding(.horizontal, 18)
                            .frame(maxWidth: .infinity, minHeight: Metrics.buttonHeight)
                            .background(Palette.surface, in: .button)
                            .overlay(RoundedRectangle.button.strokeBorder(Palette.stroke, lineWidth: 1))
                    }
                } primary: {
                    Button("Apply", action: onApply)
                        .buttonStyle(.primary)
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                loadPhoto(item)
            }
        } else {
            OneTapPanel(
                title: "Remove background",
                message: "Runs privately on your device. Always free.",
                buttonTitle: "Remove background",
                cost: 0,
                action: onStart
            )
        }
    }

    /// The refine brushes for the edge Vision drew, and Undo for their strokes.
    private var refineRow: some View {
        Group {
            if placement == .inspector {
                FlowLayout {
                    refineChips
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        refineChips
                    }
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.hidden)
            }
        }
        .animation(.snappy, value: session.refineStrokes.isEmpty)
    }

    @ViewBuilder
    private var refineChips: some View {
        SelectableChip(title: "Keep more", symbolName: "plus.circle", isSelected: session.refineMode == .keepMore) {
            session.setRefineMode(.keepMore)
        }
        SelectableChip(title: "Keep less", symbolName: "minus.circle", isSelected: session.refineMode == .keepLess) {
            session.setRefineMode(.keepLess)
        }
        if !session.refineStrokes.isEmpty {
            Button { session.undoRefineStroke() } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.icon)
            .accessibilityLabel("Undo stroke")
            .macHelp("Undo stroke")
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var backdropRow: some View {
        if placement == .inspector {
            // Room for the selection rings drawn outside each tile.
            FlowLayout(spacing: 14, lineSpacing: 14) {
                backdropTiles
            }
            .padding(4)
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    backdropTiles
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private var backdropTiles: some View {
        tile(.transparent, label: "Transparent") { CheckerboardBackground() }
        ForEach(CutoutBackdrop.swatches, id: \.self) { hex in
            tile(.color(hex), label: colorName(hex)) { Color(hex: hex) }
        }
        ColorPicker(
            "Custom color",
            selection: Binding(get: { session.customColor }, set: { session.setCustomColor($0) }),
            supportsOpacity: false
        )
        .labelsHidden()
        .frame(width: 44, height: 44)
        .overlay(Circle().strokeBorder(Palette.accent, lineWidth: session.backdrop == .custom ? 2.5 : 0).padding(-4))
        if !session.sourceHasAlpha {
            tile(.blurOriginal, label: "Blur original") {
                ZStack {
                    Palette.petal
                    Image(systemName: "drop.halffull")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                }
            }
        }
        ForEach(CutoutGradient.allCases) { gradient in
            tile(.gradient(gradient), label: gradientName(gradient)) {
                Image(uiImage: Self.gradientThumbnails[gradient] ?? UIImage())
                    .resizable()
                    .scaledToFill()
            }
        }
        // The picker's label is built off the main actor: read state first.
        let photoTile = PhotoTile(photo: session.backdropPhoto, isLoading: isLoadingPhoto, isSelected: session.backdrop == .photo)
        PhotosPicker(selection: $photoItem, matching: .images) {
            photoTile
        }
        .accessibilityLabel("Your photo")
        .accessibilityAddTraits(session.backdrop == .photo ? .isSelected : [])
    }

    private func tile(_ backdrop: CutoutBackdrop, label: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        let isSelected = session.backdrop == backdrop
        return Button {
            session.setBackdrop(backdrop)
        } label: {
            content()
                .frame(width: 44, height: 44)
                .clipShape(.chip)
                .overlay(RoundedRectangle.chip.strokeBorder(Palette.stroke, lineWidth: 1))
                .overlay(selectionRing(isSelected: isSelected))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func selectionRing(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: Metrics.chipRadius + 4, style: .continuous)
            .strokeBorder(Palette.accent, lineWidth: isSelected ? 2.5 : 0)
            .padding(-4)
    }

    private func loadPhoto(_ item: PhotosPickerItem) {
        isLoadingPhoto = true
        Task {
            defer {
                isLoadingPhoto = false
                photoItem = nil
            }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let photo = await PhotoDecoder.decode(data)?.image else {
                app.showToast("That file isn't a supported photo.", style: .error)
                return
            }
            session.setBackdropPhoto(photo)
        }
    }

    private func colorName(_ hex: UInt32) -> LocalizedStringKey {
        switch hex {
        case 0xFFFFFF: return "White"
        case 0xF8E0EA: return "Petal"
        case 0xF7C1D9: return "Blush"
        case 0xFF5CA1: return "Pink"
        case 0xA78BFA: return "Lilac"
        case 0x78E1CD: return "Mint"
        case 0xFFDE6E: return "Butter"
        default: return "Black"
        }
    }

    private func gradientName(_ gradient: CutoutGradient) -> LocalizedStringKey {
        switch gradient {
        case .pastel: return "Pastel"
        case .cottonCandy: return "Cotton candy"
        case .pinkSunset: return "Pink sunset"
        case .auraGlow: return "Aura glow"
        case .lilacHaze: return "Lilac haze"
        case .mint: return "Mint breeze"
        case .y2kGrid: return "Y2K grid"
        }
    }
}

private struct PhotoTile: View {
    let photo: UIImage?
    let isLoading: Bool
    let isSelected: Bool

    var body: some View {
        ZStack {
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill()
            } else {
                Palette.surface
                if isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                }
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(.chip)
        .overlay(RoundedRectangle.chip.strokeBorder(Palette.stroke, lineWidth: 1))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.chipRadius + 4, style: .continuous)
                .strokeBorder(Palette.accent, lineWidth: isSelected ? 2.5 : 0)
                .padding(-4)
        )
    }
}
