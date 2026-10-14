import SwiftUI
import PhotosUI
import Observation

/// Cut out after Vision has run: which subjects to keep and what goes behind
/// them, previewed on a small copy and rendered at full size on Apply.
@MainActor
@Observable
final class CutoutSession {
    private(set) var analysis: CutoutAnalysis?
    private(set) var selection = IndexSet()
    private(set) var backdrop: CutoutBackdrop = .transparent
    private(set) var customColor = Palette.blush
    private(set) var backdropPhoto: UIImage?
    private(set) var preview: UIImage?
    private(set) var outlines: UIImage?
    /// The photo was already a cut-out: there's nothing behind it to blur.
    private(set) var sourceHasAlpha = false

    /// The first tap keeps only that subject; later taps add or remove.
    @ObservationIgnored private var hasPicked = false
    @ObservationIgnored private var previewTask: Task<Void, Never>?

    var isActive: Bool { analysis != nil }
    var subjects: [CutoutAnalysis.Subject] { analysis?.subjects ?? [] }
    var keepsEverything: Bool { analysis.map { selection == $0.allIDs } ?? true }
    /// A cut-out on another photo is a composite (IPTC), not just an edit.
    var isComposite: Bool { backdrop == .photo && backdropPhoto != nil }

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

    /// The final image at the analysed photo's full size.
    func renderFinal() async -> UIImage? {
        guard let analysis else { return nil }
        let job = renderJob(analysis)
        return await Task.detached(priority: .userInitiated) {
            guard let mask = try? analysis.mask(for: job.selection) else { return nil }
            let source = CIImage(cgImage: analysis.source)
            let output = CutoutRenderer.composite(source: source, mask: mask, backdrop: job.backdrop, color: job.color, photo: job.photo)
            return CutoutRenderer.render(output, opaque: job.backdrop != .transparent)
        }.value
    }

    /// The kept subjects as an outlined sticker on transparency.
    func renderSticker() async -> UIImage? {
        guard let analysis else { return nil }
        let selection = selection
        return await Task.detached(priority: .userInitiated) {
            guard let mask = try? analysis.mask(for: selection) else { return nil }
            return CutoutRenderer.sticker(source: CIImage(cgImage: analysis.source), mask: mask, bounds: analysis.bounds(of: selection))
        }.value
    }

    private struct RenderJob: Sendable {
        let selection: IndexSet
        let backdrop: CutoutBackdrop
        let color: UIColor
        let photo: UIImage?
    }

    private func renderJob(_ analysis: CutoutAnalysis) -> RenderJob {
        var backdrop = backdrop
        if backdrop == .blurOriginal && sourceHasAlpha { backdrop = .transparent }
        if backdrop == .photo && backdropPhoto == nil { backdrop = .transparent }
        return RenderJob(selection: selection, backdrop: backdrop, color: UIColor(customColor), photo: backdropPhoto)
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
                guard let mask = try? analysis.mask(for: job.selection) else { return (nil, nil) }
                let full = CIImage(cgImage: analysis.source)
                let scale = min(1, 1200 / max(full.extent.width, full.extent.height))
                let transform = CGAffineTransform(scaleX: scale, y: scale)
                let extent = CGRect(x: 0, y: 0, width: (full.extent.width * scale).rounded(), height: (full.extent.height * scale).rounded())
                let source = full.transformed(by: transform).cropped(to: extent)
                var output = CutoutRenderer.composite(
                    source: source, mask: mask.transformed(by: transform), backdrop: job.backdrop, color: job.color, photo: job.photo
                )
                if showsGhosts, let all = try? analysis.mask(for: analysis.allIDs) {
                    output = Self.ghosts(source: source, all: all.transformed(by: transform), kept: mask.transformed(by: transform))
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

    /// The subjects that aren't kept, at 40%.
    private nonisolated static func ghosts(source: CIImage, all: CIImage, kept: CIImage) -> CIImage {
        let extent = source.extent
        let others = CIFilter(name: "CIBlendWithMask", parameters: [
            kCIInputImageKey: CIImage(color: .black).cropped(to: extent),
            kCIInputBackgroundImageKey: all,
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
/// everyone again.
struct CutoutCanvas: View {
    let session: CutoutSession
    let fallback: UIImage

    var body: some View {
        let image = session.preview ?? fallback
        GeometryReader { proxy in
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
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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

    private static let gradientThumbnails: [CutoutGradient: UIImage] = Dictionary(
        uniqueKeysWithValues: CutoutGradient.allCases.map { ($0, CutoutRenderer.thumbnail(of: $0, side: 88)) }
    )

    var body: some View {
        if session.isActive {
            VStack(alignment: .leading, spacing: 12) {
                if session.subjects.count > 1 {
                    HStack(spacing: 8) {
                        Image(systemName: "hand.tap")
                            .foregroundStyle(Palette.accent)
                        Text("Tap who or what to keep")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        SelectableChip(title: "All", isSelected: session.keepsEverything) { session.keepAll() }
                    }
                }

                Text("Background")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
                backdropRow

                HStack(spacing: 12) {
                    Menu {
                        Button(action: onCopySticker) { Label("Copy as sticker", systemImage: "doc.on.doc") }
                        Button(action: onSaveSticker) { Label("Save sticker", systemImage: "square.and.arrow.down") }
                    } label: {
                        Label("Sticker", systemImage: "sparkles.rectangle.stack")
                            .font(.headline)
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Palette.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(Palette.stroke, lineWidth: 1))
                    }
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

    private var backdropRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
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
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func tile(_ backdrop: CutoutBackdrop, label: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        let isSelected = session.backdrop == backdrop
        return Button {
            session.setBackdrop(backdrop)
        } label: {
            content()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.stroke, lineWidth: 1))
                .overlay(selectionRing(isSelected: isSelected))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func selectionRing(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
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
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.stroke, lineWidth: 1))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Palette.accent, lineWidth: isSelected ? 2.5 : 0)
                .padding(-4)
        )
    }
}
