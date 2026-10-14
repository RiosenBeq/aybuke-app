import SwiftUI
import PhotosUI

/// "Best shot": pick up to 12 selfies and the iPhone ranks them by light,
/// focus and how clearly the face shows (Apple's face capture quality),
/// never by looks. Free, on the device, nothing uploaded.
struct BestShotView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var items: [PhotosPickerItem] = []
    @State private var shots: [Shot] = []
    @State private var noFace = 0
    @State private var isAnalyzing = false
    @State private var chosen: Shot.ID?

    static let maxPhotos = 12

    struct Shot: Identifiable {
        let id = UUID()
        let data: Data
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
                            glowUp(selected)
                        } label: {
                            Label(selected.id == shots.first?.id ? "Glow up my best shot" : "Glow up this one", systemImage: "wand.and.stars")
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
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Free · on your device")
                .eyebrowStyle()
            Text(styled: "Find your *best shot*", size: 32)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Took 20 selfies? Pick up to \(Self.maxPhotos). We rank them by light, focus and how clearly your face shows. Never by looks.")
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
                        ShotTile(shot: shot, rank: index + 1, isSelected: selected?.id == shot.id)
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
                  let image = UIImage(data: data) else { continue }
            let thumbnail = await Task.detached(priority: .userInitiated) {
                ImageUtilities.normalized(image, maxLongEdge: 1280)
            }.value
            if let quality = await FaceAnalysis.captureQuality(of: thumbnail) {
                ranked.append(Shot(data: data, thumbnail: thumbnail, quality: quality))
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

    private func glowUp(_ shot: Shot) {
        guard let image = UIImage(data: shot.data) else { return }
        dismiss()
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            app.openEditor(with: image, tool: .magicEdit)
        }
    }
}

private struct ShotTile: View {
    let shot: BestShotView.Shot
    let rank: Int
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
            .overlay(alignment: .topLeading) {
                Group {
                    if rank == 1 {
                        Label("Best", systemImage: "crown.fill")
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Palette.blush, in: Capsule())
                    } else {
                        Text("\(rank)")
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(Palette.white)
                            .frame(width: 22, height: 22)
                            .background(Palette.ink.opacity(0.6), in: Circle())
                    }
                }
                .padding(6)
            }
            .shadow(color: Palette.shadow, radius: 8, y: 4)
            .accessibilityElement()
            .accessibilityLabel(rank == 1 ? "Best shot" : "Photo ranked \(rank)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
