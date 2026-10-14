import SwiftUI
import Observation

/// "Hide faces": the faces Vision found plus spots she placed, which ones to
/// cover, and a live preview. Face boxes live only here, in memory, and are
/// dropped when she leaves the tool.
@MainActor
@Observable
final class FaceHider {
    struct Face: Identifiable, Equatable {
        let id: Int
        /// Normalized face box, top-left origin.
        let rect: CGRect
        var isHidden: Bool
        let isManual: Bool
    }

    /// Left to right, so "Face 1" is the leftmost.
    private(set) var faces: [Face] = []
    private(set) var cover: FaceCover = .blur
    private(set) var preview: UIImage?
    private(set) var isDetecting = false

    @ObservationIgnored private var proxy: UIImage?
    @ObservationIgnored private var detectTask: Task<Void, Never>?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var nextID = 0

    var hiddenRects: [CGRect] { faces.filter(\.isHidden).map(\.rect) }
    var hasSelection: Bool { faces.contains(where: \.isHidden) }

    /// Finds the faces on `source`. With `preselect`, everyone but the
    /// largest face (most likely her) starts hidden; she can change that.
    func start(source: UIImage, proxy: UIImage, preselect: Bool) {
        reset()
        self.proxy = proxy
        isDetecting = true
        detectTask = Task {
            var rects = await FaceAnalysis.faceRects(in: source)
            guard !Task.isCancelled else { return }
            #if DEBUG
            // Screenshots use cartoon figures, which have no real faces.
            if rects.isEmpty, preselect, ScreenshotScene.current == .hideFaces || ScreenshotScene.current == .share {
                rects = ScreenshotFixtures.groupFaces
                if let cover = UserDefaults.standard.string(forKey: "GLFaceCover").flatMap(FaceCover.init(rawValue:)) { self.cover = cover }
            }
            #endif
            let largest = rects.indices.max { rects[$0].width * rects[$0].height < rects[$1].width * rects[$1].height }
            faces = rects.enumerated().map { index, rect in
                Face(id: makeID(), rect: rect, isHidden: preselect && index != largest, isManual: false)
            }
            isDetecting = false
            refreshPreview()
        }
    }

    func reset() {
        detectTask?.cancel()
        previewTask?.cancel()
        faces = []
        preview = nil
        proxy = nil
        isDetecting = false
    }

    func toggle(_ id: Face.ID) {
        guard let index = faces.firstIndex(where: { $0.id == id }) else { return }
        // A hand-placed spot that's switched off is just removed.
        if faces[index].isManual && faces[index].isHidden {
            faces.remove(at: index)
        } else {
            faces[index].isHidden.toggle()
        }
        Haptics.selection()
        refreshPreview()
    }

    /// A tap on the photo away from every face hides a face-sized spot there,
    /// for the faces Vision misses (profiles, sunglasses, hands in the way).
    func addSpot(at point: CGPoint) {
        guard let proxy, !isDetecting else { return }
        let size = proxy.size
        let detected = faces.filter { !$0.isManual }.map { $0.rect.width * size.width }.sorted()
        let side = detected.isEmpty ? min(size.width, size.height) * 0.16 : detected[detected.count / 2]
        let rect = FaceHiding.spot(at: point, side: side, imageSize: size)
        faces.append(Face(id: makeID(), rect: rect, isHidden: true, isManual: true))
        faces.sort { $0.rect.midX < $1.rect.midX }
        Haptics.tap()
        refreshPreview()
    }

    func setCover(_ cover: FaceCover) {
        guard cover != self.cover else { return }
        self.cover = cover
        Haptics.selection()
        refreshPreview()
    }

    /// Shows every face again and removes hand-placed spots.
    func showAll() {
        faces = faces.filter { !$0.isManual }.map { Face(id: $0.id, rect: $0.rect, isHidden: false, isManual: false) }
        refreshPreview()
    }

    private func refreshPreview() {
        previewTask?.cancel()
        guard let proxy, hasSelection else {
            preview = nil
            return
        }
        let rects = hiddenRects
        let cover = cover
        previewTask = Task {
            let rendered = await Task.detached(priority: .userInitiated) {
                FaceHiding.render(proxy, faces: rects, cover: cover)
            }.value
            guard !Task.isCancelled else { return }
            preview = rendered
        }
    }

    private func makeID() -> Int {
        nextID += 1
        return nextID
    }
}

/// The photo with an outline on every face: tap a face to hide or show it,
/// tap anywhere else to hide a spot Vision missed.
struct HideFacesCanvas: View {
    let image: UIImage
    let hider: FaceHider

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { location in
                        hider.addSpot(at: CGPoint(
                            x: min(max(location.x / max(size.width, 1), 0), 1),
                            y: min(max(location.y / max(size.height, 1), 0), 1)
                        ))
                    }
                    .accessibilityLabel("Photo")
                    .accessibilityHint("Tap to hide a spot")

                ForEach(Array(hider.faces.enumerated()), id: \.element.id) { index, face in
                    faceMarker(face, number: index + 1, in: size)
                }
            }
        }
        .aspectRatio(image.size.width / max(image.size.height, 1), contentMode: .fit)
        .clipShape(.control)
        .shadow(color: Palette.shadow, radius: 16, y: 8)
        .overlay {
            if hider.isDetecting {
                ProgressView()
                    .tint(Palette.white)
                    .padding(12)
                    .background(Palette.ink.opacity(0.45), in: Circle())
            }
        }
    }

    private func faceMarker(_ face: FaceHider.Face, number: Int, in size: CGSize) -> some View {
        let cover = FaceHiding.coverRect(for: face.rect)
        let frame = CGRect(x: cover.minX * size.width, y: cover.minY * size.height,
                           width: cover.width * size.width, height: cover.height * size.height)
        return Ellipse()
            .strokeBorder(
                Palette.white,
                style: StrokeStyle(lineWidth: face.isHidden ? 2.5 : 1.5, dash: face.isHidden ? [] : [5, 4])
            )
            .background(Ellipse().fill(Palette.ink.opacity(face.isHidden ? 0 : 0.12)))
            .overlay(alignment: .topTrailing) {
                Image(systemName: face.isHidden ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(face.isHidden ? Palette.onAccent : Palette.textPrimary)
                    .frame(width: 22, height: 22)
                    .background(face.isHidden ? Palette.accent : Palette.white, in: Circle())
                    .offset(x: 4, y: -4)
            }
            .shadow(color: .black.opacity(0.35), radius: 2)
            .frame(width: max(frame.width, 28), height: max(frame.height, 28))
            .contentShape(Ellipse())
            .onTapGesture { hider.toggle(face.id) }
            .position(x: frame.midX, y: frame.midY)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Face \(number)"))
            .accessibilityValue(face.isHidden ? Text("Hidden") : Text("Visible"))
            .accessibilityAddTraits(.isToggle)
            .accessibilityAction { hider.toggle(face.id) }
    }
}

/// Cover style, a hint that Vision can miss faces, and Apply.
struct HideFacesPanel: View {
    let hider: FaceHider
    let onApply: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "person.2.slash")
                    .foregroundStyle(Palette.accent)
                Text(hint)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(FaceCover.allCases) { cover in
                        SelectableChip(title: title(of: cover), symbolName: cover.symbolName, isSelected: hider.cover == cover) {
                            hider.setCover(cover)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)

            ButtonRow {
                Button("Reset") { withAnimation(.snappy) { hider.showAll() } }
                    .buttonStyle(.secondary)
                    .disabled(!hider.hasSelection)
            } primary: {
                Button("Apply", action: onApply)
                    .buttonStyle(.primary)
                    .disabled(!hider.hasSelection)
            }
        }
    }

    private var hint: LocalizedStringKey {
        if hider.isDetecting { return "Looking for faces…" }
        if hider.faces.isEmpty { return "Tap the photo to hide a spot" }
        // Vision misses some faces, so never suggest every face was found.
        return "Check every face. Tap to hide any we missed."
    }

    private func title(of cover: FaceCover) -> LocalizedStringKey {
        switch cover {
        case .blur: return "Blur"
        case .pixelate: return "Pixelate"
        case .heart: return "Heart"
        // A face cover, not the Kira Kira effect's "Sparkle".
        case .star: return "Star"
        case .smiley: return "Smiley"
        }
    }
}
