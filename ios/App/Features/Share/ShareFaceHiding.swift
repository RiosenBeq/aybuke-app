import SwiftUI
import Observation

/// "Hide other faces" in the share composer, for a photo shared straight
/// from My Works or Create (the editor has its own Hide faces tool). The
/// Hide faces engine keeps the biggest face, most likely hers, or the ones
/// she taps, and blurs the others, all on the device. Variations of a
/// creation (Photo strip, Which vibe?) keep their own biggest face.
@MainActor
@Observable
final class ShareFaceHiding {
    /// Faces on the shared photo and which ones to blur.
    let hider = FaceHider()
    var isOn = false {
        didSet { if isOn { findOtherFaces() } }
    }
    /// The small copy the face picker shows.
    private(set) var proxy: UIImage?
    /// Faces to blur in the payload's other pictures, once looked for.
    private(set) var others: OtherFaces?

    struct OtherFaces: Equatable, Sendable {
        /// Per variation, every face but its biggest.
        var alternatives: [[CGRect]]
        /// The before photo's own faces when it isn't the same shape as the
        /// shared one; nil: the shared photo's choice applies to it too.
        var original: [CGRect]?
    }

    /// Everything that decides the covered pictures.
    struct Plan: Equatable, Sendable {
        let faces: [CGRect]
        let others: OtherFaces
    }

    @ObservationIgnored private var payload: SharePayload?
    @ObservationIgnored private var othersTask: Task<Void, Never>?
    @ObservationIgnored private var cached: (plan: Plan, payload: SharePayload)?

    /// Only for group photos: two or more faces found.
    var isOffered: Bool { hider.faces.filter { !$0.isManual }.count >= 2 }

    /// The covered pictures to render, or nil while it's off (or still
    /// looking at the variations).
    var plan: Plan? {
        guard isOn, let others else { return nil }
        return Plan(faces: hider.hiddenRects, others: others)
    }

    /// Looks for faces once, off the main thread, when the photo came from
    /// My Works or Create.
    func prepare(_ payload: SharePayload) async {
        guard payload.offersHidingFaces, self.payload == nil else { return }
        self.payload = payload
        let image = payload.image
        let proxy = await Task.detached(priority: .userInitiated) { ImageUtilities.normalized(image, maxLongEdge: 1200) }.value
        self.proxy = proxy
        hider.start(source: image, proxy: proxy, preselect: true)
        #if DEBUG
        // Screenshot QA: `-GLShareHideFaces YES` opens with it switched on.
        if ScreenshotScene.current == .share, UserDefaults.standard.bool(forKey: "GLShareHideFaces") { isOn = true }
        #endif
    }

    /// `payload` with the faces covered, or as it is while this is off.
    /// Cached, so switching formats doesn't cover them again.
    func covering(_ payload: SharePayload) async -> SharePayload {
        guard let plan else { return payload }
        if let cached, cached.plan == plan { return cached.payload }
        let covered = await Task.detached(priority: .userInitiated) { Self.cover(payload, with: plan) }.value
        cached = (plan, covered)
        return covered
    }

    private func findOtherFaces() {
        guard others == nil, othersTask == nil, let payload else { return }
        othersTask = Task {
            var alternatives: [[CGRect]] = []
            for image in payload.alternatives {
                alternatives.append(Self.allButBiggest(await FaceAnalysis.faceRects(in: image)))
            }
            var original: [CGRect]?
            if let before = payload.original, !FaceHiding.sameShape(before, payload.image) {
                original = Self.allButBiggest(await FaceAnalysis.faceRects(in: before))
            }
            others = OtherFaces(alternatives: alternatives, original: original)
        }
    }

    private static func allButBiggest(_ faces: [CGRect]) -> [CGRect] {
        guard let biggest = faces.indices.max(by: { faces[$0].width * faces[$0].height < faces[$1].width * faces[$1].height }) else { return [] }
        return faces.enumerated().filter { $0.offset != biggest }.map(\.element)
    }

    private nonisolated static func cover(_ payload: SharePayload, with plan: Plan) -> SharePayload {
        var covered = payload
        covered.image = FaceHiding.render(payload.image, faces: plan.faces, cover: .blur)
        covered.alternatives = payload.alternatives.enumerated().map { index, image in
            let faces = plan.others.alternatives.indices.contains(index) ? plan.others.alternatives[index] : []
            return FaceHiding.render(image, faces: faces, cover: .blur)
        }
        if let before = payload.original {
            covered.original = FaceHiding.render(before, faces: plan.others.original ?? plan.faces, cover: .blur)
        }
        return covered
    }
}

/// The switch, and while it's on, the photo with every face marked so she
/// can choose who stays visible.
struct HideOtherFacesSection: View {
    @Bindable var faces: ShareFaceHiding

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $faces.isOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hide other faces")
                        .font(.subheadline.weight(.semibold))
                    Text("Keeps the biggest face and blurs the others, right on your device.")
                        .font(.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .tint(Palette.accent)

            if faces.isOn, let proxy = faces.proxy {
                HideFacesCanvas(image: faces.hider.preview ?? proxy, hider: faces.hider)
                    .frame(maxWidth: .infinity, maxHeight: 240)
                    .transition(.opacity)
                Label("Tap a face to blur or show it. Tap anywhere else to cover a face we missed.", systemImage: "hand.tap")
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .animation(.snappy, value: faces.isOn)
    }
}
