import SwiftUI
import PhotosUI
import AppCore

/// "Best shot": pick up to 12 selfies and the iPhone sorts them by light,
/// focus and how clearly the face shows (Apple's face capture quality),
/// never by looks. No crown or rank numbers on selfies: the top one just
/// gets a "Best light & focus" chip. Free, on the device, nothing uploaded.
struct BestShotView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var items: [PhotosPickerItem] = []
    @State private var shots: [Shot] = []
    @State private var noFace = 0
    @State private var isAnalyzing = false
    @State private var chosen: Shot.ID?

    static let maxPhotos = 12

    /// Only a small thumbnail stays in memory; the chosen photo is loaded
    /// again from Photos for editing, so twelve full selfies are never held.
    struct Shot: Identifiable {
        enum Source {
            case item(PhotosPickerItem)
            case image(UIImage)
        }

        let id = UUID()
        let source: Source
        let thumbnail: UIImage
        let quality: Float
    }

    private var selected: Shot? { shots.first { $0.id == chosen } ?? shots.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if isAnalyzing {
                        analyzing
                    } else if shots.isEmpty {
                        picker
                    } else {
                        results
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .background(AuroraBackground(intensity: 0.4))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let selected, !isAnalyzing {
                    VStack(spacing: 10) {
                        Button {
                            edit(selected)
                        } label: {
                            Label("Edit this one", systemImage: "slider.horizontal.3")
                        }
                        .buttonStyle(.primary)
                        PhotosPicker(selection: $items, maxSelectionCount: Self.maxPhotos, matching: .images) {
                            Text("Pick other photos")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.vertical, 10)
                    .background(.regularMaterial)
                }
            }
        }
        .tint(Palette.accent)
        .onChange(of: items) { _, newItems in
            Task { await analyze(newItems) }
        }
        #if DEBUG
        .onAppear {
            // Sample pictures (no real faces), already sorted, for screenshots.
            guard ScreenshotScene.current == .bestShot, shots.isEmpty else { return }
            shots = ScreenshotFixtures.generatedArt(count: 6).enumerated().map { index, image in
                Shot(source: .image(image), thumbnail: image, quality: 1 - Float(index) / 10)
            }
        }
        #endif
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Free · on your device")
                .eyebrowStyle()
            Text(styled: "Find your *best shot*", size: 28)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Took a bunch of selfies? Pick up to \(Self.maxPhotos). We find the one with the best light and focus. Never by looks.")
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(.top, 8)
    }

    private var picker: some View {
        PhotosPicker(selection: $items, maxSelectionCount: Self.maxPhotos, matching: .images) {
            VStack(spacing: 12) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 84, height: 84)
                    .background(Palette.blush, in: Circle())
                    .floating(distance: 4)
                Text("Choose selfies")
                    .font(.cardTitle)
                    .foregroundStyle(Palette.textPrimary)
                Text("Photos never leave your device")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
            .cardStyle()
        }
        .buttonStyle(.pressable)
    }

    private var analyzing: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(Palette.accent)
            Text("Looking at light and focus…")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                ForEach(Array(shots.enumerated()), id: \.element.id) { index, shot in
                    Button {
                        Haptics.selection()
                        chosen = shot.id
                    } label: {
                        ShotTile(shot: shot, isTop: index == 0, isSelected: selected?.id == shot.id)
                    }
                    .buttonStyle(.pressable)
                    .reveal(min(index, 8))
                }
            }
            if noFace > 0 {
                Text(noFace == 1 ? "1 photo without a clear face was left out." : "\(noFace) photos without a clear face were left out.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
    }

    // MARK: Work

    private func analyze(_ newItems: [PhotosPickerItem]) async {
        guard !newItems.isEmpty else { return }
        isAnalyzing = true
        chosen = nil
        var ranked: [Shot] = []
        var missing = 0
        for item in newItems {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let analysis = await Task.detached(priority: .userInitiated, operation: {
                      ImageUtilities.decodedImage(from: data, maxPixel: 1280)
                  }).value
            else { continue }
            if let quality = await FaceAnalysis.captureQuality(of: analysis) {
                let thumbnail = await Task.detached(priority: .userInitiated) {
                    ImageUtilities.normalized(analysis, maxLongEdge: 480)
                }.value
                ranked.append(Shot(source: .item(item), thumbnail: thumbnail, quality: quality))
            } else {
                missing += 1
            }
        }
        withAnimation(.snappy) {
            shots = ranked.sorted { $0.quality > $1.quality }
            noFace = missing
            isAnalyzing = false
        }
        if shots.isEmpty {
            app.showToast("We couldn't find a clear face in those photos.", style: .info)
        } else {
            Haptics.success()
        }
    }

    /// Opens the free, on-device Adjust tool; she can switch tools there.
    private func edit(_ shot: Shot) {
        Task {
            let image: UIImage
            var sourceType: DigitalSourceType?
            switch shot.source {
            case .image(let fixture):
                image = fixture
            case .item(let item):
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let decoded = await PhotoDecoder.decode(data) else {
                    app.showToast("That file isn't a supported photo.", style: .error)
                    return
                }
                image = decoded.image
                // Keeps an AI marking the file already carries.
                sourceType = decoded.sourceType
            }
            dismiss()
            try? await Task.sleep(for: .milliseconds(450))
            app.openEditor(with: image, tool: .adjust, provenance: Provenance(inheritedSourceType: sourceType))
        }
    }
}

private struct ShotTile: View {
    let shot: BestShotView.Shot
    let isTop: Bool
    let isSelected: Bool

    var body: some View {
        Color.clear
            .aspectRatio(3 / 4, contentMode: .fit)
            .overlay {
                Image(uiImage: shot.thumbnail)
                    .resizable()
                    .scaledToFill()
            }
            .clipShape(RoundedRectangle(cornerRadius: Metrics.printRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.printRadius)
                    .strokeBorder(isSelected ? Palette.accent : Palette.stroke, lineWidth: isSelected ? 3 : 1)
            )
            .overlay(alignment: .bottomLeading) {
                // A capture-quality fact, not a verdict on the person.
                if isTop {
                    Label("Best light & focus", systemImage: "sun.max.fill")
                        .font(.caption2.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Palette.blush, in: .tag)
                        .padding(5)
                }
            }
            .shadow(color: Palette.shadow, radius: 8, y: 4)
            .accessibilityElement()
            .accessibilityLabel(isTop ? "Photo with the best light and focus" : "Photo")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
